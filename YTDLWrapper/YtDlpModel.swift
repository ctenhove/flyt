//
//  YtDlpModel.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import Foundation
import Observation

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

/// Metadata about a video, decoded from yt-dlp's `--dump-json` output.
/// Only the fields the app needs are declared; the decoder ignores the rest.
struct VideoInfo: Codable {
    /// The video's title.
    let title: String
    /// URL of the video's thumbnail image, if one is available.
    let thumbnail: String?
    /// Length of the video in seconds, if known (live streams may have none).
    let duration: Double?
}

/// Wraps the bundled `yt-dlp_macos` command-line binary and exposes its
/// results as observable state that SwiftUI views can render directly.
///
/// All public methods return immediately and run the tool asynchronously,
/// publishing results back on the main actor.
@Observable
class YtDlpModel {
    /// True while a version check or info fetch is in flight.
    var isLoading = false
    /// Raw stdout text from the most recent simple command (e.g. `--version`).
    var output: String = ""
    /// Human-readable description of the last failure, or nil if none.
    var errorMessage: String?
    /// Metadata for the most recently fetched video, or nil if none.
    var videoInfo: VideoInfo?
    /// Download completion in the range 0.0...1.0, driven by yt-dlp's progress lines.
    var downloadProgress: Double = 0.0
    /// True while a download is in progress.
    var isDownloading = false
    var downloadPhase: DownloadPhase = .idle
    var lastDownloadedFile: URL?
    var isBusy: Bool {
        isLoading || isDownloading
    }
    
    private var destinationCount = 0
    private let dependencyManager: DependencyManager
    
    init(dependencyManager: DependencyManager) {
        self.dependencyManager = dependencyManager
    }

    /// Runs the bundled yt-dlp binary with the given arguments and returns
    /// everything it wrote to stdout once the process exits.
    ///
    /// The process runs on a detached task so the blocking reads and
    /// `waitUntilExit()` never touch the main thread.
    private func run(args: [String]) async throws -> String {
        // The binary is shipped inside the app bundle as a plain resource.
        guard let toolURL = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) else {
            throw NSError(domain: "YtDlpModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Binary not found"])
        }
        
        return try await Task.detached {
            let process = Process()
            process.executableURL = toolURL
            process.arguments = args
            
            // Capture stdout and stderr separately so error text doesn't
            // pollute the parsed output.
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            try process.run()
            
            // Read both pipes to completion before waiting on the process;
            // draining the pipes prevents the child from blocking on a full buffer.
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            // Surface stderr in the console for debugging, but don't treat it
            // as a failure — yt-dlp writes warnings there too.
            if let errorText = String(data: errorData, encoding: .utf8), !errorText.isEmpty {
                print("yt-dlp stderr: \(errorText)")
            }
            
            return String(data: outputData, encoding: .utf8) ?? ""
        }.value
    }
    
    /// Runs yt-dlp with the given arguments, streaming its stdout line by line
    /// and updating `downloadProgress` whenever a percentage appears.
    ///
    /// Used for downloads, where we care about live progress rather than the
    /// final output text.
    private func runWithProgress(args: [String]) async throws {
        guard let toolURL = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) else {
            throw NSError(domain: "YtDlpModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Binary not found"])
        }

        try await Task.detached {
            let process = Process()
            process.executableURL = toolURL
            process.arguments = args

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let outHandle = outputPipe.fileHandleForReading
            let errHandle = errorPipe.fileHandleForReading
            
            // Read output incrementally as it arrives instead of waiting for
            // the process to finish, so progress can update in real time.
            outHandle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }

                // Detect a new stream starting (Destination line)
                if line.contains("[download] Destination:") {
                    Task { @MainActor in
                        self.destinationCount += 1
                        self.downloadPhase = self.destinationCount == 1 ? .downloadingVideo : .downloadingAudio
                        self.downloadProgress = 0.0
                    }
                }

                // Detect the merge phase
                if line.contains("[Merger]") {
                    Task { @MainActor in
                        self.downloadPhase = .merging
                    }
                }

                if let percent = Self.parseProgress(from: line) {
                    Task { @MainActor in
                        self.downloadProgress = percent
                    }
                }

                if let dest = Self.parseDestination(from: line) {
                    Task { @MainActor in
                        self.lastDownloadedFile = URL(fileURLWithPath: dest)
                    }
                }
            }
            
            errHandle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                print("yt-dlp stderr: \(line)")
            }

            try process.run()
            process.waitUntilExit()
            // Clear the handler so the file handle stops calling into us
            // after the process has exited.
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
        }.value
    }

    /// Extracts a download percentage from a line of yt-dlp output
    /// (e.g. "[download]  42.5% of ...") and returns it as a fraction
    /// in 0.0...1.0, or nil if the line contains no percentage.
    private nonisolated static func parseProgress(from line: String) -> Double? {
        // Match a decimal number immediately followed by a percent sign.
        guard let range = line.range(of: #"(\d+\.\d+)%"#, options: .regularExpression) else {
            return nil
        }
        let match = line[range].dropLast() // remove "%"
        return Double(match).map { $0 / 100.0 }
    }
    
    private nonisolated static func parseDestination(from line: String) -> String? {
        if let range = line.range(of: #"\[download\] Destination: (.+)"#, options: .regularExpression) {
            return String(line[range].replacingOccurrences(of: "[download] Destination: ", with: ""))
        }
        if let range = line.range(of: #"\[Merger\] Merging formats into "(.+)""#, options: .regularExpression) {
            let match = String(line[range])
            return match.replacingOccurrences(of: "[Merger] Merging formats into \"", with: "")
                        .replacingOccurrences(of: "\"", with: "")
        }
        return nil
    }
    
    /// The current user's Downloads folder, where completed videos are saved.
    private var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }
    
    /// Asks yt-dlp for its version string and publishes it to `output`.
    /// Also serves as a quick sanity check that the bundled binary runs.
    func runVersion() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await run(args: ["--version"])
                await MainActor.run {
                    self.output = result
                    self.isLoading = false
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "\(error)"
                    self.isLoading = false
                }
            }
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
                let data = Data(result.utf8)
                let info = try JSONDecoder().decode(VideoInfo.self, from: data)

                await MainActor.run {
                    self.videoInfo = info
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "\(error)"
                    self.isLoading = false
                }
            }
        }
    }
    
    /// Downloads the video at `urlString` into the user's Downloads folder,
    /// updating `downloadProgress` as it goes.
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
                await MainActor.run {
                    self.isDownloading = false
                    self.downloadProgress = 1.0
                    self.downloadPhase = .idle
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "\(error)"
                    self.isDownloading = false
                }
            }
        }
    }
}
