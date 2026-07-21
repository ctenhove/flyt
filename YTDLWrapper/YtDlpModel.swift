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

    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "The bundled yt-dlp binary is missing."
        case .processFailed(let detail): return detail
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

    /// Number of "Destination:" lines seen this download; the first stream
    /// is the video track, any later ones are audio.
    private var destinationCount = 0
    private let dependencyManager: DependencyManager

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
                let result = try await run(args: ["--dump-json", urlString])
                videoInfo = try JSONDecoder().decode(VideoInfo.self, from: Data(result.utf8))
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

        Task {
            do {
                try await runWithProgress(args: [
                    "--newline",
                    "--ffmpeg-location", dependencyManager.ffmpegURL.path,
                    "-o", "\(downloadsDirectory.path)/%(title)s.%(ext)s",
                    urlString
                ])
                downloadProgress = 1.0
            } catch {
                errorMessage = error.localizedDescription
            }
            isDownloading = false
            downloadPhase = .idle
        }
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

        // Drain stderr concurrently with stdout so the child can't block
        // on a full pipe, keeping the text to report if yt-dlp fails.
        async let stderrLines: [String] = {
            var lines: [String] = []
            for try await line in errorPipe.fileHandleForReading.bytes.lines {
                print("yt-dlp stderr: \(line)")
                lines.append(line)
            }
            return lines
        }()

        for try await line in outputPipe.fileHandleForReading.bytes.lines {
            await processOutputLine(line)
        }

        let stderrOutput = (try? await stderrLines) ?? []
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw YtDlpError.processFailed(
                Self.failureMessage(stderrLines: stderrOutput, status: process.terminationStatus)
            )
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
        if line.contains("[download] Destination:") {
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
