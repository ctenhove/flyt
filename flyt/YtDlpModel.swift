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
    /// Cutting one of several requested time ranges. yt-dlp's own stdout
    /// reports no incremental progress for this step (it's a keyframe-
    /// accurate ffmpeg cut, not a plain download) — but ffmpeg's own
    /// encode progress on stderr does, parsed in processFFmpegStderrLine
    /// and turned into a real percentage against this section's duration.
    case trimmingSection(index: Int, total: Int)

    var label: String {
        switch self {
        case .idle: return ""
        case .downloadingVideo: return "Downloading video…"
        case .downloadingAudio: return "Downloading audio…"
        case .merging: return "Merging…"
        case .trimmingSection(let index, let total):
            return total > 1 ? "Trimming section \(index) of \(total)…" : "Trimming…"
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

    /// True for H.264/AVC — the one video codec reliably playable in
    /// QuickTime Player and other AVFoundation-based software once muxed
    /// into an MP4 container. VP9 and AV1 often produce an MP4 QuickTime
    /// opens fine (the container and AAC audio both decode normally) but
    /// won't render any video from — audio plays, the picture doesn't.
    /// Used only as a selection tie-break, not a filter: a video with no
    /// H.264 option at a given quality still needs *a* format.
    var isBroadlyCompatibleCodec: Bool {
        vcodec?.hasPrefix("avc1") == true
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
    /// Every file the last download actually produced, populated once it
    /// finishes: one entry normally (or once merged sections land in a
    /// single file), several when multiple time-range sections were
    /// requested without merging. The completion screen uses this rather
    /// than `lastDownloadedFile` alone so it can report — and reveal in
    /// Finder — every file, not just whichever one happened to finish last.
    var downloadedFiles: [URL] = []
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
    /// Number of time-range sections requested this download; 0 means
    /// trimming isn't active and `processOutputLine` uses the normal
    /// video/audio-pair tracking above instead. A sectioned download's
    /// Destination line represents one whole cut section rather than one
    /// video/audio track, so it needs its own counter.
    private var expectedSectionCount = 0
    private var sectionsCompleted = 0
    /// Each section's finished file, in the order yt-dlp reports them —
    /// used to concatenate them into one file when the caller asked to
    /// merge sections.
    private var sectionOutputFiles: [URL] = []
    /// Each requested section's target length in seconds, in the same
    /// order as sectionOutputFiles will be filled — the denominator
    /// processFFmpegStderrLine normalizes ffmpeg's own elapsed-time
    /// progress against for the section currently being cut.
    private var sectionDurations: [Double] = []
    private let dependencyManager: DependencyManager

    /// The yt-dlp process currently running, if any, so `cancel()` can
    /// terminate it while `run`/`runWithProgress` are executing off the main
    /// actor. `Process.terminate()` is safe to call from any thread, so this
    /// is marked unsafe rather than hopping actors on every process start/stop.
    private nonisolated(unsafe) var activeProcess: Process?
    /// Guards `activeProcess` and `cancelRequested`, which are touched from
    /// both the main actor (`cancel()`) and the background process runners.
    private nonisolated let processLock = NSLock()
    /// Set by `cancel()`; cleared when a new fetch or download begins.
    private nonisolated(unsafe) var cancelRequested = false

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
        resetCancellation()
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
    /// `subtitleLanguage` is `nil`. When not embedding, `subtitleFileName`
    /// (without extension; empty falls back to `fileName`) names the
    /// sidecar file, which yt-dlp writes as `<name>.<lang>.srt`.
    /// `timeRanges` trims the download to those spans (each becomes a
    /// `--download-sections`); empty downloads the full video. With more than
    /// one range, `mergeSections` chooses between one output file per range
    /// (each named with its start/end) or concatenating them into a single
    /// file afterward.
    ///
    /// Bails out if a fetch or download is already in flight — see the note
    /// on `runVersion()`.
    ///
    /// Returns whether a download actually started, so a caller that
    /// reserved a `DownloadCoordinator` slot for it knows to release the
    /// slot when it didn't.
    @discardableResult
    func download(
        urlString: String,
        videoFormatId: String?,
        audioFormatId: String?,
        outputContainer: OutputContainer,
        destinationFolder: URL,
        fileName: String,
        subtitleLanguage: SubtitleSelection.LanguageOption?,
        embedSubtitles: Bool,
        subtitleFileName: String = "",
        timeRanges: [VideoTimeRange] = [],
        mergeSections: Bool = false
    ) -> Bool {
        guard !isBusy else { return false }
        resetCancellation()
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
        destinationCount = 0
        seenDestinations = []
        isDownloadingSubtitle = false
        expectedSectionCount = timeRanges.count
        sectionsCompleted = 0
        sectionOutputFiles = []
        sectionDurations = timeRanges.map { $0.end - $0.start }
        downloadedFiles = []
        downloadPhase = expectedSectionCount > 0
            ? .trimmingSection(index: 1, total: expectedSectionCount)
            : (expectsVideoTrack ? .downloadingVideo : .downloadingAudio)

        // Every download writes into its own hidden, per-download scratch
        // folder rather than the visible destination directly:
        //  - keeps in-progress fragments/.part files out of Finder instead
        //    of appearing (and disappearing) in the destination folder
        //    while a download is running;
        //  - means two downloads of the same video — same title, same
        //    format — can never collide on the same fragment/temp
        //    filenames the way they would sharing one folder, which is
        //    what was corrupting/leaving fragments behind before;
        //  - makes "delete everything" on cancel or failure a single
        //    directory removal instead of hunting down whatever partial
        //    files yt-dlp happened to leave behind.
        // The dot prefix is what actually hides it from Finder; the UUID
        // just needs to be unique per download, not itself secret.
        let tempFolder = destinationFolder.appendingPathComponent(".flyt-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Couldn't write to \(destinationFolder.path): \(error.localizedDescription)"
            isDownloading = false
            downloadPhase = .idle
            return false
        }
        // Recorded so a quit or crash before the cleanup below can't leave
        // it behind for good — see ScratchFolderRegistry.sweepStale.
        ScratchFolderRegistry.register(tempFolder)

        let nameComponent = fileName.isEmpty ? "%(title)s" : Self.sanitizedFileNameComponent(fileName)
        // Requesting more than one time range without a per-range output
        // template would have every range write to the same final path —
        // yt-dlp then silently skips every range after the first as
        // "already downloaded". The suffix is yt-dlp's own template fields,
        // not something this code resolves itself; the actual paths
        // produced are read back from its Destination lines below.
        let sectionSuffix = timeRanges.count > 1 ? " [%(section_start)s-%(section_end)s]" : ""
        var args = [
            "--newline",
            // Force single-video mode: without this, a playlist URL
            // downloads every entry in sequence, each with its own
            // video/audio destination pair, which would blow past
            // the two streams processOutputLine expects to see.
            "--no-playlist",
            "--ffmpeg-location", dependencyManager.ffmpegURL.path,
            "--merge-output-format", outputContainer.rawValue,
            "-o", "\(tempFolder.path)/\(nameComponent)\(sectionSuffix).%(ext)s"
        ]
        let formatSelector = [videoFormatId, audioFormatId].compactMap { $0 }.joined(separator: "+")
        if !formatSelector.isEmpty {
            args += ["-f", formatSelector]
        }
        if let subtitleLanguage {
            // Both write flags, always: --write-subs alone ignores a
            // language that only exists as auto-generated captions, and
            // --write-auto-subs alone ignores manual tracks. With both,
            // yt-dlp prefers the manual track and falls back to auto.
            args += ["--sub-langs", subtitleLanguage.code, "--write-subs", "--write-auto-subs"]
            if embedSubtitles {
                // Explicit --write-subs makes yt-dlp treat the subtitle file
                // as requested and keep it as a sidecar next to the embedded
                // copy; the no-keep-subs compat option (there is no
                // --no-keep-subs flag) restores delete-after-embedding.
                args += ["--embed-subs", "--compat-options", "no-keep-subs"]
            } else {
                // Converting to srt gives the sidecar a known extension, so
                // the UI can show it as the field's fixed suffix. (Not done
                // when embedding: webm only accepts vtt subtitles.)
                args += ["--convert-subs", "srt"]
                // A `subtitle:` output template only changes the base name;
                // yt-dlp still appends ".<lang>.<ext>" itself.
                let subtitleName = subtitleFileName.isEmpty ? nameComponent : Self.sanitizedFileNameComponent(subtitleFileName)
                args += ["-o", "subtitle:\(tempFolder.path)/\(subtitleName).%(ext)s"]
            }
        }
        for range in timeRanges {
            args += ["--download-sections", "*\(Self.sectionTimestamp(range.start))-\(Self.sectionTimestamp(range.end))"]
        }
        if !timeRanges.isEmpty {
            args += ["--force-keyframes-at-cuts"]
        }
        args.append(urlString)

        Task {
            do {
                try await runWithProgress(args: args)
                // yt-dlp skips a section whose output path already exists
                // without printing a Destination line, so a short count
                // means clips are missing. Fail loudly instead of
                // reporting (or merging) a partial set.
                if expectedSectionCount > 0, sectionOutputFiles.count != expectedSectionCount {
                    throw YtDlpError.processFailed(
                        "Only \(sectionOutputFiles.count) of \(expectedSectionCount) clips were downloaded."
                    )
                }

                // What the user asked for, still inside the scratch folder.
                var primaryFiles: [URL]
                if expectedSectionCount > 0 {
                    primaryFiles = sectionOutputFiles
                    if mergeSections, sectionOutputFiles.count > 1 {
                        downloadPhase = .merging
                        // Same fallback the section files themselves used:
                        // the video title when no name was given.
                        let mergedFileName = fileName.isEmpty
                            ? (FilenamePolicy.sanitize(videoInfo?.title ?? "").nonEmpty ?? "download")
                            : FilenamePolicy.sanitize(fileName)
                        // Merged inside the scratch folder too, so the one
                        // move below handles it like any other result.
                        primaryFiles = [try await concatenateSections(
                            sectionOutputFiles,
                            finalFileName: mergedFileName,
                            into: tempFolder
                        )]
                    }
                } else {
                    primaryFiles = lastDownloadedFile.map { [$0] } ?? []
                }

                // Move the results out to where the user actually asked
                // for them, then delete the scratch folder (any leftover
                // intermediate files yt-dlp didn't already clean up go
                // with it). Off the main actor: across volumes this is a
                // full copy.
                let primary = primaryFiles
                let outcome = await Task.detached {
                    Self.moveOutputs(primary: primary, tempFolder: tempFolder, destinationFolder: destinationFolder)
                }.value
                if outcome.failed.isEmpty, !primary.isEmpty {
                    downloadedFiles = outcome.moved
                    lastDownloadedFile = outcome.moved.last
                    try? FileManager.default.removeItem(at: tempFolder)
                } else {
                    // The download itself succeeded but never made it out,
                    // so don't delete it (or let a later sweep) — report
                    // the failure instead of a "Complete" card pointing
                    // at a hidden folder.
                    downloadedFiles = []
                    lastDownloadedFile = nil
                    errorMessage = primary.isEmpty
                        ? "The download finished, but no output file was found. Anything yt-dlp wrote is in \(tempFolder.path)."
                        : "The download finished, but couldn't be moved to \(destinationFolder.path). It's still at \(tempFolder.path)."
                }
                if errorMessage == nil { downloadProgress = 1.0 }
            } catch YtDlpError.cancelled {
                // User-initiated; leave the UI clean rather than showing an
                // error. wasCancelled is how callers still tell this apart
                // from a genuine completion, since errorMessage alone can't.
                wasCancelled = true
                try? FileManager.default.removeItem(at: tempFolder)
            } catch {
                errorMessage = error.diagnosticDescription
                try? FileManager.default.removeItem(at: tempFolder)
            }
            // Whether it was deleted or deliberately kept (failed move),
            // it's no longer a leftover for a later launch to sweep.
            ScratchFolderRegistry.unregister(tempFolder)
            isDownloading = false
            downloadPhase = .idle
        }
        return true
    }

    /// Moves a finished download from its hidden scratch folder to
    /// `destinationFolder`, re-resolving a unique name there (the same way
    /// `FilenamePolicy.uniqueFilename` does before a download even starts)
    /// in case two downloads targeting the same name both finish around
    /// the same time — `FileManager.moveItem` never silently overwrites,
    /// so without this the second one to finish would just fail to move
    /// at all rather than risk clobbering the first. Returns `nil` if the
    /// move couldn't be completed.
    private nonisolated static func moveToDestination(_ file: URL, destinationFolder: URL) -> URL? {
        let ext = file.pathExtension
        let base = file.deletingPathExtension().lastPathComponent
        // The name is re-resolved on each attempt: another download can
        // claim it between the check and the move, and moveItem then fails
        // rather than overwrite.
        for _ in 0..<5 {
            let uniqueBase = FilenamePolicy.uniqueFilename(base: base, in: destinationFolder)
            let target = destinationFolder.appendingPathComponent(ext.isEmpty ? uniqueBase : "\(uniqueBase).\(ext)")
            do {
                try FileManager.default.moveItem(at: file, to: target)
                return target
            } catch {
                if !FileManager.default.fileExists(atPath: file.path) { return nil }
            }
        }
        return nil
    }

    /// Moves a download's results out of its scratch folder: each `primary`
    /// file first (so its name is resolved before anything else can claim
    /// it), then any other finished file left in the folder — a subtitle
    /// sidecar, say. Partial-download leftovers are skipped. Returns the
    /// primary files' new locations, in order, plus any that couldn't move.
    private nonisolated static func moveOutputs(
        primary: [URL],
        tempFolder: URL,
        destinationFolder: URL
    ) -> (moved: [URL], failed: [URL]) {
        var moved: [URL] = []
        var failed: [URL] = []
        for file in primary {
            if let target = moveToDestination(file, destinationFolder: destinationFolder) {
                moved.append(target)
            } else {
                failed.append(file)
            }
        }
        let partialExtensions: Set<String> = ["part", "ytdl", "temp"]
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            at: tempFolder, includingPropertiesForKeys: nil
        )) ?? []
        for file in leftovers where !primary.contains(file) && !partialExtensions.contains(file.pathExtension.lowercased()) {
            if moveToDestination(file, destinationFolder: destinationFolder) == nil {
                failed.append(file)
            }
        }
        return (moved, failed)
    }

    /// Cancels the in-flight fetch or download, if any, by terminating the
    /// underlying yt-dlp process. Safe to call even if nothing is running.
    func cancel() {
        processLock.lock()
        defer { processLock.unlock() }
        cancelRequested = true
        activeProcess?.terminate()
    }

    /// Starts `process` and records it as the one `cancel()` should stop,
    /// atomically with respect to `cancel()`. A cancel that lands before the
    /// process is registered is remembered in `cancelRequested` and honoured
    /// here, so it can't slip through the gap between `run()` and the
    /// assignment (and never calls `terminate()` on a process not yet running).
    private nonisolated func launch(_ process: Process) throws {
        processLock.lock()
        defer { processLock.unlock() }
        if cancelRequested { throw YtDlpError.cancelled }
        try process.run()
        activeProcess = process
    }

    private func resetCancellation() {
        processLock.lock()
        cancelRequested = false
        processLock.unlock()
    }

    private nonisolated func clearActiveProcess() {
        processLock.lock()
        activeProcess = nil
        processLock.unlock()
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

    /// Formats seconds for yt-dlp's `--download-sections "*start-end"`
    /// syntax, which accepts plain seconds (fractional or not).
    private nonisolated static func sectionTimestamp(_ seconds: Double) -> String {
        String(format: "%.2f", seconds)
    }

    /// Concatenates already-downloaded section files into one final file
    /// via ffmpeg's concat demuxer (stream copy, no re-encode — every
    /// section was already cut into the same codec/container by this same
    /// download). Deletes the section files only once the merge succeeds,
    /// so a failure still leaves the individual clips behind instead of
    /// losing them.
    @concurrent
    private func concatenateSections(_ files: [URL], finalFileName: String, into folder: URL) async throws -> URL {
        let ext = files.first?.pathExtension ?? "mp4"
        let uniqueName = FilenamePolicy.uniqueFilename(base: finalFileName, in: folder)
        let finalURL = folder.appendingPathComponent("\(uniqueName).\(ext)")

        let listURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        // ffmpeg's concat demuxer format: one `file '<path>'` per line: a
        // literal single quote in a path has to be closed, escaped, and
        // reopened (concat's own escaping rule), even though our own
        // filenames won't produce one in practice.
        let listContents = files
            .map { "file '\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }
            .joined(separator: "\n")
        try listContents.write(to: listURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: listURL) }

        let process = Process()
        process.executableURL = dependencyManager.ffmpegURL
        process.arguments = ["-y", "-loglevel", "error", "-nostats", "-f", "concat", "-safe", "0", "-i", listURL.path, "-c", "copy", finalURL.path]
        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        // Tracked the same way runProcess tracks the yt-dlp process, so
        // cancel() can still stop something while this step is running.
        try launch(process)
        defer { clearActiveProcess() }
        // Drain stderr before waiting: ffmpeg's banner and progress output
        // can exceed the pipe buffer, and a child blocked on a full pipe
        // never exits. Reads until ffmpeg closes stderr (i.e. exits).
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            if process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGTERM {
                throw YtDlpError.cancelled
            }
            let detail = String(data: errorData, encoding: .utf8)
            throw YtDlpError.processFailed(detail?.isEmpty == false ? detail! : "Merging sections failed.")
        }

        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        return finalURL
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

        try launch(process)
        defer { clearActiveProcess() }

        // Drain stderr concurrently with stdout so the child can't block
        // on a full pipe buffer, keeping the text to report if yt-dlp fails.
        // Also the only place a sectioned download's real progress shows
        // up at all — see processFFmpegStderrLine.
        async let stderrLines: [String] = {
            var lines: [String] = []
            for await line in Self.lines(from: errorPipe.fileHandleForReading) {
                print("yt-dlp stderr: \(line)")
                lines.append(line)
                if reportProgress {
                    await processFFmpegStderrLine(line)
                }
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
                // yt-dlp's own stdout (under --newline) only ever uses LF,
                // so this is a no-op there; ffmpeg's stderr progress line
                // updates in place with CR instead — without also
                // splitting on it, every update would sit unterminated in
                // the buffer as one ever-growing "line" until the next
                // real LF, instead of arriving as its own line each time.
                while let terminatorRange = Self.earliestLineTerminator(in: buffer) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<terminatorRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex..<terminatorRange.upperBound)
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

    private nonisolated static func earliestLineTerminator(in data: Data) -> Range<Data.Index>? {
        let newline = data.range(of: Data([0x0A]))
        let carriageReturn = data.range(of: Data([0x0D]))
        switch (newline, carriageReturn) {
        case (nil, nil): return nil
        case (let n?, nil): return n
        case (nil, let c?): return c
        case (let n?, let c?): return n.lowerBound < c.lowerBound ? n : c
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

    /// Interprets one line of ffmpeg's own stderr output during a sectioned
    /// (trimmed) download — a plain yt-dlp download never routes through
    /// this pipeline, and this is a no-op outside of one. ffmpeg's
    /// "frame=... time=HH:MM:SS.ss ..." progress updates in place via
    /// carriage return rather than yt-dlp's own newline-per-update
    /// "[download] NN%" — see `lines(from:)` for why those still arrive
    /// here one at a time regardless.
    private func processFFmpegStderrLine(_ line: String) {
        guard expectedSectionCount > 0, sectionsCompleted > 0, sectionsCompleted <= sectionDurations.count else { return }
        guard let elapsed = Self.parseFFmpegTime(from: line) else { return }
        let targetDuration = sectionDurations[sectionsCompleted - 1]
        guard targetDuration > 0 else { return }
        downloadProgress = min(1.0, elapsed / targetDuration)
    }

    /// Extracts the "time=HH:MM:SS.ss" field ffmpeg prints on its own
    /// progress line — how far into the current cut it's encoded so far.
    private nonisolated static func parseFFmpegTime(from line: String) -> Double? {
        guard let match = line.firstMatch(of: /time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})/) else { return nil }
        guard let hours = Double(match.1), let minutes = Double(match.2),
              let seconds = Double(match.3), let centiseconds = Double(match.4) else { return nil }
        return hours * 3600 + minutes * 60 + seconds + centiseconds / 100
    }

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
        // A subtitle fetch is nothing but "[download]" lines; any other
        // tag ([info], [Merger], …) or an "already downloaded" notice means
        // it's over, even if no video/audio Destination line follows (the
        // video was already on disk, or a partial file is being resumed).
        if isDownloadingSubtitle,
           !line.hasPrefix("[download]") || line.contains("has already been downloaded") {
            isDownloadingSubtitle = false
        }
        if line.contains("[download] Destination:"), let dest {
            isDownloadingSubtitle = Self.isSubtitleDestination(dest)
            if !isDownloadingSubtitle, !seenDestinations.contains(dest) {
                seenDestinations.insert(dest)
                // A sectioned (trimmed) download reports one Destination line
                // per *section* rather than per video/audio track — yt-dlp cuts
                // each range with a direct ffmpeg pipeline that never prints
                // the usual separate video-then-audio Destination pair — so it
                // needs its own counter instead of the video/audio-pair logic
                // below.
                if expectedSectionCount > 0 {
                    sectionsCompleted += 1
                    sectionOutputFiles.append(URL(fileURLWithPath: dest))
                    downloadPhase = .trimmingSection(index: min(sectionsCompleted, expectedSectionCount), total: expectedSectionCount)
                    lastDownloadedFile = URL(fileURLWithPath: dest)
                    // Fresh section, fresh progress — ffmpeg's own progress
                    // (parsed from stderr in processFFmpegStderrLine) hasn't
                    // reported anything for it yet.
                    downloadProgress = 0.0
                    downloadedSizeText = nil
                    totalSizeText = nil
                    speedText = nil
                    etaText = nil
                } else {
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
        }

        if line.contains("[Merger]") {
            downloadPhase = .merging
        }

        // The subtitle stream's own progress/size lines (percentage, "of X
        // at Y ETA Z", its Destination path) are irrelevant to the
        // video/audio progress this view tracks — see isDownloadingSubtitle above.
        if isDownloadingSubtitle {
            // Its own 100% line is the last thing it prints.
            if Self.parseProgress(from: line) == 1.0 { isDownloadingSubtitle = false }
            return
        }

        // A sectioned download's own progress lines (a single 0%→100%
        // per section, no incremental updates) aren't worth surfacing as a
        // percentage — the UI shows an indeterminate spinner for
        // `.trimmingSection` instead — and `lastDownloadedFile` is already
        // tracked per-section above.
        guard expectedSectionCount == 0 else { return }

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

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
