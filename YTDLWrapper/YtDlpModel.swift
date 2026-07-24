//
//  YtDlpModel.swift
//  YTDLWrapper
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

/// Metadata about a video, decoded from yt-dlp's `--dump-json` output.
/// Only the fields the app needs are declared; the decoder ignores the rest.
struct VideoInfo: Codable {
    let title: String
    let thumbnail: String?
    /// Length in seconds, if known (live streams may have none).
    let duration: Double?
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
    /// first stream is the video track, any later ones are audio.
    private var destinationCount = 0
    /// Destination paths already counted, so a reprinted "Destination:" line
    /// for the same file — e.g. a retried fragment — doesn't advance the phase.
    private var seenDestinations: Set<String> = []
    private let dependencyManager: DependencyManager

    /// The yt-dlp process currently running, if any, so `cancel()` can
    /// terminate it while `run`/`runWithProgress` are executing off the main
    /// actor. `Process.terminate()` is safe to call from any thread, so this
    /// is marked unsafe rather than hopping actors on every process start/stop.
    private nonisolated(unsafe) var activeProcess: Process?

    private nonisolated var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    init(dependencyManager: DependencyManager) {
        self.dependencyManager = dependencyManager
    }

    // MARK: Actions

    /// Asks yt-dlp for its version string and publishes it to `output`.
    /// Also serves as a quick sanity check that the bundled binary runs.
    func runVersion() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                output = try await run(args: ["--version"])
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Fetches metadata for the video at `urlString` (without downloading it)
    /// and publishes the decoded result to `videoInfo`.
    func fetchInfo(for urlString: String) {
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
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    /// Downloads the video at `urlString` into the user's Downloads folder,
    /// updating `downloadProgress` and `downloadPhase` as it goes.
    func download(urlString: String) {
        isDownloading = true
        downloadProgress = 0.0
        errorMessage = nil
        downloadPhase = .downloadingVideo
        destinationCount = 0
        seenDestinations = []

        Task {
            do {
                try await runWithProgress(args: [
                    "--newline",
                    // Force single-video mode: without this, a playlist URL
                    // downloads every entry in sequence, each with its own
                    // video/audio destination pair, which would blow past
                    // the two streams processOutputLine expects to see.
                    "--no-playlist",
                    "--ffmpeg-location", dependencyManager.ffmpegURL.path,
                    "-o", "\(downloadsDirectory.path)/%(title)s.%(ext)s",
                    urlString
                ])
                downloadProgress = 1.0
            } catch YtDlpError.cancelled {
                // User-initiated; leave the UI clean rather than showing an error.
            } catch {
                errorMessage = error.localizedDescription
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

    // MARK: Running yt-dlp

    /// Locates the yt-dlp binary, which ships in the app bundle as a plain resource.
    private nonisolated func locateBinary() throws -> URL {
        guard let url = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) else {
            throw YtDlpError.binaryNotFound
        }
        return url
    }

    /// Runs yt-dlp and returns everything it wrote to stdout once it exits.
    /// Runs off the main actor: the pipe reads and `waitUntilExit()` block.
    @concurrent
    private func run(args: [String]) async throws -> String {
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
            for try await line in errorPipe.fileHandleForReading.bytes.lines {
                print("yt-dlp stderr: \(line)")
                lines.append(line)
            }
            return lines
        }()

        var outputLines: [String] = []
        for try await line in outputPipe.fileHandleForReading.bytes.lines {
            outputLines.append(line)
        }

        let stderrOutput = (try? await stderrLines) ?? []
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // A signal-terminated process means `cancel()` killed it.
            if process.terminationReason == .uncaughtSignal {
                throw YtDlpError.cancelled
            }
            throw YtDlpError.processFailed(
                Self.failureMessage(stderrLines: stderrOutput, status: process.terminationStatus)
            )
        }

        return outputLines.joined(separator: "\n")
    }

    /// Runs yt-dlp, parsing its stdout line by line as it arrives so progress
    /// updates live. Throws if the process exits non-zero.
    @concurrent
    private func runWithProgress(args: [String]) async throws {
        let process = Process()
        process.executableURL = try locateBinary()
        process.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        activeProcess = process
        defer { activeProcess = nil }

        // Drain stderr concurrently with stdout so the child can't block
        // on a full pipe, keeping the text to report if yt-dlp fails.
        async let stderrLines: [String] = {
            var lines: [String] = []
            for await line in Self.lines(from: errorPipe.fileHandleForReading) {
                print("yt-dlp stderr: \(line)")
                lines.append(line)
            }
            return lines
        }()

        for await line in Self.lines(from: outputPipe.fileHandleForReading) {
            await processOutputLine(line)
        }

        let stderrOutput = await stderrLines
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // A signal-terminated process means `cancel()` killed it.
            if process.terminationReason == .uncaughtSignal {
                throw YtDlpError.cancelled
            }
            throw YtDlpError.processFailed(
                Self.failureMessage(stderrLines: stderrOutput, status: process.terminationStatus)
            )
        }
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
            downloadPhase = destinationCount == 1 ? .downloadingVideo : .downloadingAudio
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
