//
//  YtDlpModel.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import Foundation
import Observation

/// The user-visible stage of an in-flight download.
enum DownloadPhase {
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
struct VideoInfo: Codable {
    let title: String
    let thumbnail: String?
    /// Length in seconds, if known (live streams may have none).
    let duration: Double?
    /// Every format yt-dlp offers for this video, worst to best as yt-dlp orders them.
    let formats: [VideoFormat]
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
    /// `fileName` falls back to the video's title.
    ///
    /// Bails out if a fetch or download is already in flight — see the note
    /// on `runVersion()`.
    func download(
        urlString: String,
        videoFormatId: String?,
        audioFormatId: String?,
        outputContainer: OutputContainer,
        destinationFolder: URL,
        fileName: String
    ) {
        guard !isBusy else { return }
        isDownloading = true
        downloadProgress = 0.0
        errorMessage = nil
        // yt-dlp's own default format selection (both nil) resolves to
        // bestvideo+bestaudio, i.e. video first — so the first destination
        // is audio only when the caller explicitly picked audio with no video.
        expectsVideoTrack = !(videoFormatId == nil && audioFormatId != nil)
        downloadPhase = expectsVideoTrack ? .downloadingVideo : .downloadingAudio
        destinationCount = 0
        seenDestinations = []

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
        args.append(urlString)

        Task {
            do {
                try await runWithProgress(args: args)
                downloadProgress = 1.0
            } catch YtDlpError.cancelled {
                // User-initiated; leave the UI clean rather than showing an error.
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

    /// Escapes a user-supplied name for safe use as a path segment in yt-dlp's
    /// `-o` output template: `/` would otherwise be read as a directory
    /// separator (e.g. a title like "AC/DC - Thunderstruck" would create an
    /// unintended "AC" subfolder), and `%` starts a `%(field)s` reference in
    /// yt-dlp's own template syntax.
    private nonisolated static func sanitizedFileNameComponent(_ name: String) -> String {
        name
            .replacingOccurrences(of: "%", with: "%%")
            .replacingOccurrences(of: "/", with: "-")
    }

    // MARK: Running yt-dlp

    /// Locates the yt-dlp binary, which ships in the app bundle as a plain resource.
    private nonisolated func locateBinary() throws -> URL {
        guard let url = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) else {
            throw YtDlpError.binaryNotFound
        }
        return url
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
        // Each stream yt-dlp downloads starts with its own Destination line.
        // A retried/resumed fragment can reprint the same line for the file
        // already in progress, so only a *new* path counts as a new stream.
        if line.contains("[download] Destination:"),
           let dest = Self.parseDestination(from: line),
           !seenDestinations.contains(dest) {
            seenDestinations.insert(dest)
            destinationCount += 1
            let isVideoTrack = destinationCount == 1 && expectsVideoTrack
            downloadPhase = isVideoTrack ? .downloadingVideo : .downloadingAudio
            downloadProgress = 0.0
        }

        if line.contains("[Merger]") {
            downloadPhase = .merging
        }

        if let percent = Self.parseProgress(from: line) {
            downloadProgress = percent
        }

        if let dest = Self.parseDestination(from: line) {
            lastDownloadedFile = URL(fileURLWithPath: dest)
        }
    }

    /// Extracts a download percentage from a line of yt-dlp output
    /// (e.g. "[download]  42.5% of ...") and returns it as a fraction
    /// in 0.0...1.0, or nil if the line contains no percentage.
    private nonisolated static func parseProgress(from line: String) -> Double? {
        guard let match = line.firstMatch(of: /(\d+\.\d+)%/) else { return nil }
        return Double(match.1).map { $0 / 100.0 }
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
