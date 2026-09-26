//
//  YtDlpModel.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import Foundation
import Observation

/// The user-visible stage of an in-flight download.
enum DownloadPhase: Equatable {
    case idle
    case downloadingVideo
    case downloadingAudio
    case merging

    var label: String {
        switch self {
        case .idle: return ""
        case .downloadingVideo: return "Downloading video…"
        case .downloadingAudio: return "Downloading audio…"
        case .merging: return "Merging…"
        }
    }
}

enum YtDlpError: LocalizedError {
    case binaryNotFound
    case processFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "The bundled yt-dlp binary is missing."
        case .processFailed(let detail): return detail
        case .cancelled: return "Cancelled."
        }
    }
}

/// Container to mux the final output into, passed to yt-dlp's
/// `--merge-output-format`. Only takes effect when yt-dlp actually needs to
/// merge separate video/audio streams; it's ignored otherwise.
enum OutputContainer: String, CaseIterable, Identifiable, Hashable {
    case mp4
    case mkv
    case webm

    var id: String { rawValue }
    var label: String { rawValue }
}

private extension Error {
    /// A diagnostic description: prefers `LocalizedError.errorDescription`
    /// for errors that define one (e.g. `YtDlpError`), but falls back to the
    /// full case dump otherwise. `DecodingError` (thrown when yt-dlp's
    /// `--dump-json` output is malformed) doesn't conform to `LocalizedError`,
    /// so `.localizedDescription` on it collapses to a generic, undiagnosable
    /// "The operation couldn't be completed" message.
    var diagnosticDescription: String {
        if let localizedError = self as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return String(describing: self)
    }
}

/// Metadata about a video, decoded from yt-dlp's `--dump-json` output.
/// Only the fields the app needs are declared; the decoder ignores the rest.
struct VideoInfo: Codable, Equatable {
    let title: String
    let thumbnail: String?
    /// Length in seconds, if known (live streams may have none).
    let duration: Double?
    let channel: String?
    let viewCount: Int?
    /// Every format yt-dlp offers for this video, worst to best as yt-dlp orders them.
    let formats: [VideoFormat]
    /// Manually-authored subtitle tracks, keyed by yt-dlp language code (e.g. "en", "es").
    let subtitles: [String: [SubtitleTrackInfo]]?
    /// Auto-generated caption tracks, keyed by language code. Sites like
    /// YouTube can offer dozens of auto-translated languages here.
    let automaticCaptions: [String: [SubtitleTrackInfo]]?

    enum CodingKeys: String, CodingKey {
        case title
        case thumbnail
        case duration
        case channel
        case viewCount = "view_count"
        case formats
        case subtitles
        case automaticCaptions = "automatic_captions"
    }
}

/// One available subtitle track for a language, decoded from an entry in
/// yt-dlp's "subtitles"/"automatic_captions" maps. yt-dlp lists one entry
/// per sub-format (vtt, srv3, ...) for the same language; only `name` is
/// used here (for a human-readable label when yt-dlp provides one) since
/// `--sub-langs`/`--sub-format` select by language, not by individual entry.
struct SubtitleTrackInfo: Codable, Hashable {
    let name: String?
}

/// One downloadable format of a video, decoded from an entry in yt-dlp's
/// `--dump-json` "formats" array. Only the fields the picker UI needs are
/// declared; the decoder ignores the rest.
///
/// Sites like YouTube publish many formats per video: separate DASH streams
/// for each video codec (avc1/h264, vp9, av1), separate 30fps/60fps variants
/// at the same resolution, and sometimes a legacy "progressive" stream that
/// already has audio muxed in alongside a video-only stream at the same
/// resolution — which is why two entries can share a resolution/extension
/// but differ in size.
struct VideoFormat: Codable, Identifiable, Hashable {
    let formatId: String
    let ext: String
    let resolution: String?
    let height: Int?
    let fps: Double?
    let vcodec: String?
    let acodec: String?
    let abr: Double?
    let tbr: Double?
    let filesize: Int64?
    let filesizeApprox: Int64?
    /// yt-dlp's download protocol for this format, e.g. "https" or
    /// "m3u8_native" (HLS). Used only to break quality ties in favor of a
    /// format whose progress reporting is reliable — see `hasReliableProgress`.
    let formatProtocol: String?

    var id: String { formatId }

    enum CodingKeys: String, CodingKey {
        case formatId = "format_id"
        case ext
        case resolution
        case height
        case fps
        case vcodec
        case acodec
        case abr
        case tbr
        case filesize
        case filesizeApprox = "filesize_approx"
        case formatProtocol = "protocol"
    }

    /// True if this format carries a video track (yt-dlp uses vcodec "none" for audio-only formats).
    var hasVideo: Bool {
        guard let vcodec else { return false }
        return vcodec != "none"
    }

    /// True if this format is audio-only.
    var isAudioOnly: Bool {
        !hasVideo && acodec != nil && acodec != "none"
    }

    /// True if this format has no separate audio track (common for high-res DASH video streams).
    var isVideoOnly: Bool {
        hasVideo && (acodec == nil || acodec == "none")
    }

    /// False for streaming-manifest protocols (HLS/DASH segments), whose
    /// per-fragment progress reporting is far less reliable than a plain
    /// HTTP download — yt-dlp's own size estimate for these swings wildly
    /// fragment to fragment, and it prints a literal "ETA Unknown" for long
    /// stretches even mid-download. Same underlying quality, worse UI, so
    /// this only matters as a tie-break — see `FormatSelection`.
    var hasReliableProgress: Bool {
        guard let formatProtocol else { return true }
        return !formatProtocol.contains("m3u8") && !formatProtocol.contains("dash")
    }

    /// A rough quality score for sorting/defaulting a picker to "best first".
    var qualityRank: Double {
        if hasVideo {
            return Double((height ?? 0) * 1000) + (fps ?? 0)
        }
        return abr ?? tbr ?? 0
    }

    /// A short human-readable summary for a format picker, e.g.
    /// "1080p60 · mp4 · h264 · video only · 85.4 MB" or "128 kbps · m4a · aac · 3.1 MB".
    var label: String {
        var components: [String] = []

        if isAudioOnly {
            if let abr {
                components.append("\(Int(abr)) kbps")
            }
            components.append(ext)
            if let codec = Self.shortCodec(acodec) {
                components.append(codec)
            }
        } else {
            if let resolution {
                components.append(resolution)
            } else if let height {
                components.append("\(height)p")
            }
            if let fps, fps > 30 {
                components.append("\(Int(fps))fps")
            }
            components.append(ext)
            if let codec = Self.shortCodec(vcodec) {
                components.append(codec)
            }
            if isVideoOnly {
                components.append("video only")
            }
        }

        if let size = Self.formattedFileSize(filesize ?? filesizeApprox) {
            components.append(size)
        }

        return components.joined(separator: " · ")
    }

    /// Maps a raw yt-dlp codec string (e.g. "avc1.640028", "vp09.00.40.08")
    /// to a short recognizable name.
    private static func shortCodec(_ raw: String?) -> String? {
        guard let raw, raw != "none" else { return nil }
        let base = raw.split(separator: ".").first.map(String.init) ?? raw
        switch base {
        case "avc1": return "h264"
        case "vp9", "vp09": return "vp9"
        case "av01": return "av1"
        case "mp4a": return "aac"
        default: return base
        }
    }

    private static func formattedFileSize(_ bytes: Int64?) -> String? {
        guard let bytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Wraps the bundled `yt-dlp_macos` command-line binary and exposes its
/// results as observable state that SwiftUI views can render directly.
///
/// All public methods return immediately and run the tool asynchronously,
/// publishing results back on the main actor.
@Observable
final class YtDlpModel {

    // MARK: Observable state

    /// True while a version check or info fetch is in flight (see `isDownloading` for downloads).
    var isLoading = false
    /// Raw stdout from the most recent simple command (e.g. `--version`).
    var output: String = ""
    var errorMessage: String?
    var videoInfo: VideoInfo?
    /// Download completion in 0.0...1.0, driven by yt-dlp's progress lines.
    var downloadProgress: Double = 0.0
    var isDownloading = false
    var downloadPhase: DownloadPhase = .idle
    /// Where the last download landed, parsed from yt-dlp's output.
    var lastDownloadedFile: URL?
    /// True if the most recent download ended via `cancel()` rather than
    /// finishing or failing. Cancellation intentionally leaves
    /// `errorMessage` nil (see `download()`), so callers that need to tell
    /// a genuine completion apart from a cancelled one — the main window's
    /// completion screen, notably — need this rather than inferring it
    /// from the absence of an error.
    var wasCancelled = false
    /// Downloaded-so-far and total size, already unit-formatted (e.g.
    /// "34.1 MB", "74.3 MB"), derived from yt-dlp's own progress line.
    /// `nil` until the first progress line with a total size arrives.
    var downloadedSizeText: String?
    var totalSizeText: String?
    /// Transfer speed exactly as yt-dlp prints it (e.g. "4.10MiB/s").
    var speedText: String?
    /// Remaining time exactly as yt-dlp prints it (e.g. "00:12").
    var etaText: String?
    var isBusy: Bool {
        isLoading || isDownloading
    }

    // MARK: Private state

    /// Number of distinct "Destination:" file paths seen this download; the
    /// first stream is the video track, any later ones are audio — unless no
    /// video track was requested, see `expectsVideoTrack`.
    private var destinationCount = 0
    /// Destination paths already counted, so a reprinted "Destination:" line
    /// for the same file — e.g. a retried fragment — doesn't advance the phase.
    private var seenDestinations: Set<String> = []
    /// Whether the current download includes a video track, so the first
    /// "Destination:" line is labeled correctly for audio-only downloads.
    private var expectsVideoTrack = true
    /// True while the stream most recently announced by a "Destination:"
    /// line is a subtitle sidecar file rather than video/audio — see
    /// `processOutputLine`.
    private var isDownloadingSubtitle = false
    private let dependencyManager: DependencyManager

    /// The yt-dlp process currently running, if any, so `cancel()` can
    /// terminate it while `run`/`runWithProgress` are executing off the main
    /// actor. `Process.terminate()` is safe to call from any thread, so this
    /// is marked unsafe rather than hopping actors on every process start/stop.
    private nonisolated(unsafe) var activeProcess: Process?

    /// The user's Downloads folder, offered as the default destination.
    nonisolated static var defaultDownloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    init(dependencyManager: DependencyManager) {
        self.dependencyManager = dependencyManager
    }

    // MARK: Actions

    /// Asks yt-dlp for its version string and publishes it to `output`.
    /// Also serves as a quick sanity check that the bundled binary runs.
    ///
    /// Bails out if a fetch or download is already in flight rather than
    /// relying solely on the UI's `.disabled(isBusy)` — a fast double-click
    /// can race ahead of SwiftUI's re-render and call this twice before the
    /// button actually becomes disabled.
    func runVersion() {
        guard !isBusy else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                output = try await run(args: ["--version"])
            } catch {
                errorMessage = error.diagnosticDescription
            }
            isLoading = false
        }
    }

    /// Fetches metadata for the video at `urlString` (without downloading it)
    /// and publishes the decoded result to `videoInfo`.
    ///
    /// Bails out if a fetch or download is already in flight — see the note
    /// on `runVersion()`.
    func fetchInfo(for urlString: String) {
        guard !isBusy else { return }
        isLoading = true
        errorMessage = nil
        videoInfo = nil

        Task {
            do {
                // --dump-json prints the video's metadata as a single JSON
                // object on stdout instead of downloading anything.
                // --no-playlist forces single-video mode: without it, a
                // playlist URL makes yt-dlp print one JSON object per entry,
                // which wouldn't parse as the single VideoInfo we expect.
                // --ffmpeg-location points at the bundled binary so yt-dlp
                // doesn't warn about a missing system ffmpeg it doesn't need.
                let result = try await run(args: [
                    "--dump-json", "--no-playlist",
                    "--ffmpeg-location", dependencyManager.ffmpegURL.path,
                    urlString
                ])
                videoInfo = try JSONDecoder().decode(VideoInfo.self, from: Data(result.utf8))
            } catch YtDlpError.cancelled {
                // User-initiated; leave the UI clean rather than showing an error.
            } catch {
                errorMessage = error.diagnosticDescription
            }
            isLoading = false
        }
    }

    /// Downloads the video at `urlString` into `destinationFolder`, updating
    /// `downloadProgress` and `downloadPhase` as it goes. Pass the
    /// `format_id`s of `VideoFormat`s from `videoInfo.formats` to select
    /// specific video and/or audio streams — yt-dlp merges them if both are
    /// given. Passing `nil` for one track downloads only the other; passing
    /// `nil` for both lets yt-dlp pick its own default. `outputContainer`
    /// controls the container yt-dlp merges into; it's ignored if no merge
    /// is needed (e.g. only one track was selected). `fileName` is used
    /// without its extension — yt-dlp appends the real one; an empty
    /// `fileName` falls back to the video's title. Pass `subtitleLanguage`
    /// to also fetch subtitles for that language — `nil` skips subtitles
    /// entirely. `embedSubtitles` muxes them into the video file instead of
    /// writing a sidecar file alongside it; it's ignored when
    /// `subtitleLanguage` is `nil`.
    ///
    /// Bails out if a fetch or download is already in flight — see the note
    /// on `runVersion()`.
    func download(
        urlString: String,
        videoFormatId: String?,
        audioFormatId: String?,
        outputContainer: OutputContainer,
        destinationFolder: URL,
        fileName: String,
        subtitleLanguage: SubtitleSelection.LanguageOption?,
        embedSubtitles: Bool
    ) {
        guard !isBusy else { return }
        isDownloading = true
        downloadProgress = 0.0
        downloadedSizeText = nil
        totalSizeText = nil
        speedText = nil
        etaText = nil
        errorMessage = nil
        wasCancelled = false
        // yt-dlp's own default format selection (both nil) resolves to
        // bestvideo+bestaudio, i.e. video first — so the first destination
        // is audio only when the caller explicitly picked audio with no video.
        expectsVideoTrack = !(videoFormatId == nil && audioFormatId != nil)
        downloadPhase = expectsVideoTrack ? .downloadingVideo : .downloadingAudio
        destinationCount = 0
        seenDestinations = []
        isDownloadingSubtitle = false

        let nameComponent = fileName.isEmpty ? "%(title)s" : Self.sanitizedFileNameComponent(fileName)
        var args = [
            "--newline",
            // Force single-video mode: without this, a playlist URL
            // downloads every entry in sequence, each with its own
            // video/audio destination pair, which would blow past
            // the two streams processOutputLine expects to see.
            "--no-playlist",
            "--ffmpeg-location", dependencyManager.ffmpegURL.path,
            "--merge-output-format", outputContainer.rawValue,
            "-o", "\(destinationFolder.path)/\(nameComponent).%(ext)s"
        ]
        let formatSelector = [videoFormatId, audioFormatId].compactMap { $0 }.joined(separator: "+")
        if !formatSelector.isEmpty {
            args += ["-f", formatSelector]
        }
        if let subtitleLanguage {
            args += ["--sub-langs", subtitleLanguage.code]
            if embedSubtitles {
                // --embed-subs alone (without --write-subs/--write-auto-subs)
                // already fetches whichever of manual/auto is available for
                // --sub-langs, embeds it, and deletes the temp subtitle file
                // once done. Adding --write-subs/--write-auto-subs here would
                // make yt-dlp treat the file as explicitly requested and
                // keep it as a sidecar alongside the embedded copy.
                args += ["--embed-subs"]
            } else {
                // Without embedding, explicitly ask for the file yt-dlp
                // should keep. Manually-authored and auto-generated tracks
                // live under different flags; SubtitleSelection.languageOptions
                // only labels a language auto-generated when no manual track
                // for it exists, so exactly one of these is what's available.
                args += [subtitleLanguage.isAutoGenerated ? "--write-auto-subs" : "--write-subs"]
            }
        }
        args.append(urlString)

        Task {
            do {
                try await runWithProgress(args: args)
                downloadProgress = 1.0
            } catch YtDlpError.cancelled {
                // User-initiated; leave the UI clean rather than showing an
                // error. wasCancelled is how callers still tell this apart
                // from a genuine completion, since errorMessage alone can't.
                wasCancelled = true
            } catch {
                errorMessage = error.diagnosticDescription
            }
            isDownloading = false
            downloadPhase = .idle
        }
    }

    /// Cancels the in-flight fetch or download, if any, by terminating the
    /// underlying yt-dlp process. Safe to call even if nothing is running.
    func cancel() {
        activeProcess?.terminate()
    }

    /// Sanitizes a user-supplied name for safe use as a path segment in
    /// yt-dlp's `-o` output template. Builds on `FilenamePolicy.sanitize`
    /// (filesystem-hostile/control characters, whitespace, length) and adds
    /// one thing specific to yt-dlp's own template syntax: escaping `%`,
    /// which it would otherwise read as the start of a `%(field)s`
    /// reference. Applied last, after the general sanitization, so a `%`
    /// introduced by that pass (there isn't one) couldn't slip through unescaped.
    private nonisolated static func sanitizedFileNameComponent(_ name: String) -> String {
        FilenamePolicy.sanitize(name).replacingOccurrences(of: "%", with: "%%")
    }

    // MARK: Running yt-dlp

    /// Locates the yt-dlp binary: prefers a self-updated copy installed
    /// by `DependencyManager` in Application Support, falling back to the
    /// copy bundled in the app as a plain resource if nothing has been
    /// installed yet (or it's gone missing).
    private nonisolated func locateBinary() throws -> URL {
        let installed = dependencyManager.ytdlpURL
        if FileManager.default.isExecutableFile(atPath: installed.path) {
            return installed
        }
        guard let bundled = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) else {
            throw YtDlpError.binaryNotFound
        }
        return bundled
    }

    /// Runs yt-dlp and returns everything it wrote to stdout once it exits.
    private func run(args: [String]) async throws -> String {
        try await runProcess(args: args, reportProgress: false).joined(separator: "\n")
    }

    /// Runs yt-dlp, parsing its stdout line by line as it arrives so progress
    /// updates live. Throws if the process exits non-zero.
    private func runWithProgress(args: [String]) async throws {
        _ = try await runProcess(args: args, reportProgress: true)
    }

    /// Runs yt-dlp and collects its stdout lines. When `reportProgress` is
    /// true, each stdout line is also fed to `processOutputLine` as it
    /// arrives, driving the live download UI; when false, lines are just
    /// collected for the caller to consume once the process exits.
    /// Runs off the main actor: the pipe reads and `waitUntilExit()` block.
    @concurrent
    private func runProcess(args: [String], reportProgress: Bool) async throws -> [String] {
        let process = Process()
        process.executableURL = try locateBinary()
        process.arguments = args

        // Capture stdout and stderr separately so error text doesn't
        // pollute the parsed output.
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        activeProcess = process
        defer { activeProcess = nil }

        // Drain stderr concurrently with stdout so the child can't block
        // on a full pipe buffer, keeping the text to report if yt-dlp fails.
        async let stderrLines: [String] = {
            var lines: [String] = []
            for await line in Self.lines(from: errorPipe.fileHandleForReading) {
                print("yt-dlp stderr: \(line)")
                lines.append(line)
            }
            return lines
        }()

        var outputLines: [String] = []
        for await line in Self.lines(from: outputPipe.fileHandleForReading) {
            outputLines.append(line)
            if reportProgress {
                await processOutputLine(line)
            }
        }

        let stderrOutput = await stderrLines
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // `cancel()` sends SIGTERM specifically, so only that signal means
            // *we* killed it. Any other uncaught signal (e.g. a crash) is a
            // real failure and shouldn't be swallowed as a benign cancel.
            // When terminationReason is .uncaughtSignal, terminationStatus
            // holds the signal number rather than an exit code.
            if process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGTERM {
                throw YtDlpError.cancelled
            }
            throw YtDlpError.processFailed(
                Self.failureMessage(stderrLines: stderrOutput, status: process.terminationStatus)
            )
        }

        return outputLines
    }

    /// Streams a pipe's contents as lines as they're written, instead of
    /// buffering until the pipe closes. `FileHandle.bytes.lines` only
    /// surfaces data once the pipe reaches EOF, which held progress updates
    /// back until the process exited; `readabilityHandler` fires as soon as
    /// data is available.
    private nonisolated static func lines(from handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            var buffer = Data()
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty else {
                    if let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
                        continuation.yield(line)
                    }
                    fileHandle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                buffer.append(data)
                while let newlineRange = buffer.range(of: Data([0x0A])) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                    if let line = String(data: lineData, encoding: .utf8) {
                        continuation.yield(line)
                    }
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }

    /// Builds a user-facing failure message, preferring yt-dlp's "ERROR:"
    /// lines on stderr over a bare exit code.
    private nonisolated static func failureMessage(stderrLines: [String], status: Int32) -> String {
        stderrLines.last(where: { $0.contains("ERROR") })
            ?? stderrLines.last
            ?? "yt-dlp exited with code \(status)"
    }

    // MARK: Output parsing

    /// Interprets one complete line of yt-dlp stdout and updates observable state.
    private func processOutputLine(_ line: String) {
        // Parsed once and reused below (both in the Destination-line check
        // and to update lastDownloadedFile) rather than matched twice per line.
        let dest = Self.parseDestination(from: line)

        // Each stream yt-dlp downloads starts with its own Destination line.
        // A retried/resumed fragment can reprint the same line for the file
        // already in progress, so only a *new* path counts as a new stream.
        // A requested subtitle file gets its own Destination line too,
        // fetched (and fully downloaded, with its own 0%-100% progress)
        // before the real video/audio streams — isDownloadingSubtitle tracks
        // that so its lines don't count as stream #1 below, or flash
        // downloadProgress to its own 100% just before the real video
        // stream's Destination line resets it back to 0%.
        if line.contains("[download] Destination:"), let dest {
            isDownloadingSubtitle = Self.isSubtitleDestination(dest)
            if !isDownloadingSubtitle, !seenDestinations.contains(dest) {
                seenDestinations.insert(dest)
                destinationCount += 1
                let isVideoTrack = destinationCount == 1 && expectsVideoTrack
                downloadPhase = isVideoTrack ? .downloadingVideo : .downloadingAudio
                downloadProgress = 0.0
                // Clear the previous stream's stats rather than leaving them
                // to show alongside the new stream's phase/progress until its
                // own first progress line arrives.
                downloadedSizeText = nil
                totalSizeText = nil
                speedText = nil
                etaText = nil
            }
        }

        if line.contains("[Merger]") {
            downloadPhase = .merging
        }

        // The subtitle stream's own progress/size lines (percentage, "of X
        // at Y ETA Z", its Destination path) are irrelevant to the
        // video/audio progress this view tracks — see isDownloadingSubtitle above.
        guard !isDownloadingSubtitle else { return }

        // Parsed once and reused below rather than re-read from
        // `downloadProgress`: that stored value can be stale (left over
        // from a previous line, or from the previous stream if this line
        // has size/speed/ETA but, for whatever reason, no percentage of
        // its own), which would make `downloadedSizeText` show a wrong
        // "X of Y" pairing rather than staying nil until real data exists.
        let percent = Self.parseProgress(from: line)
        if let percent {
            downloadProgress = percent
        }

        if let detail = Self.parseProgressDetail(from: line) {
            totalSizeText = detail.total
            speedText = detail.speed
            etaText = detail.eta
            // yt-dlp only prints the *total* size per progress line, not
            // how much has landed so far, so derive that from this same
            // line's own percentage — only when this line actually has one.
            if let percent, let totalBytes = Self.parseByteCount(detail.total) {
                let downloadedBytes = Int64(Double(totalBytes) * percent)
                downloadedSizeText = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
            }
        }

        if let dest {
            lastDownloadedFile = URL(fileURLWithPath: dest)
        }
    }

    /// Subtitle sidecar extensions yt-dlp can write with `--write-subs`/
    /// `--write-auto-subs`, so their Destination lines can be told apart
    /// from the video/audio streams `processOutputLine` tracks.
    private static let subtitleExtensions: Set<String> = ["vtt", "srt", "ass", "ttml", "srv1", "srv2", "srv3", "json3"]

    private nonisolated static func isSubtitleDestination(_ path: String) -> Bool {
        subtitleExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    /// Extracts a download percentage from a line of yt-dlp output
    /// (e.g. "[download]  42.5% of ..." or "[download] 100% of ...") and
    /// returns it as a fraction in 0.0...1.0, or nil if the line contains
    /// no percentage. The fractional part is optional — yt-dlp always
    /// prints one in practice, but a whole-number percent (e.g. a bare
    /// "3%" or "100%") shouldn't fail to parse just because it lacks one.
    private nonisolated static func parseProgress(from line: String) -> Double? {
        guard let match = line.firstMatch(of: /(\d+(?:\.\d+)?)%/) else { return nil }
        return Double(match.1).map { $0 / 100.0 }
    }

    /// Extracts the unit-formatted total size, speed, and ETA yt-dlp prints
    /// on its own progress line, e.g. "[download]  46.5% of ~74.32MiB at
    /// 4.10MiB/s ETA 00:12" — already human-readable, so passed through as-is
    /// rather than re-parsed into raw numbers (`parseByteCount` below only
    /// exists to derive the downloaded-so-far figure, which yt-dlp doesn't
    /// print directly). The ETA group requires a leading digit so a literal
    /// "ETA Unknown" — which HLS/DASH streams print for long stretches —
    /// fails to match here, same as the already-numeric-only speed group,
    /// rather than surfacing a useless "Unknown left" in the UI.
    private nonisolated static func parseProgressDetail(from line: String) -> (total: String, speed: String, eta: String)? {
        guard let match = line.firstMatch(of: /of\s+~?([\d.]+\w+)\s+at\s+([\d.]+\w+\/s)\s+ETA\s+(\d\S*)/) else { return nil }
        return (total: String(match.1), speed: String(match.2), eta: String(match.3))
    }

    /// Parses a yt-dlp size string like "74.32MiB" into raw bytes. Only
    /// needs to handle the units yt-dlp actually prints in `--newline` mode.
    private nonisolated static func parseByteCount(_ text: String) -> Int64? {
        guard let match = text.firstMatch(of: /([\d.]+)(B|KiB|MiB|GiB|TiB)/) else { return nil }
        guard let value = Double(match.1) else { return nil }
        let multiplier: Double
        switch String(match.2) {
        case "KiB": multiplier = 1_024
        case "MiB": multiplier = 1_048_576
        case "GiB": multiplier = 1_073_741_824
        case "TiB": multiplier = 1_099_511_627_776
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }

    /// Extracts the output file path from a "Destination:" or Merger line,
    /// or nil for any other line.
    private nonisolated static func parseDestination(from line: String) -> String? {
        if let match = line.firstMatch(of: /\[download\] Destination: (.+)/) {
            return String(match.1)
        }
        if let match = line.firstMatch(of: /\[Merger\] Merging formats into "(.+)"/) {
            return String(match.1)
        }
        return nil
    }
}
