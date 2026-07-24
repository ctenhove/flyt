//
//  DependencyManager.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-08.
//

import CryptoKit
import Foundation
import Observation

enum DependencyError: LocalizedError {
    case downloadFailed
    case unzipFailed
    case binaryNotFound
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return "Failed to download ffmpeg."
        case .unzipFailed: return "Failed to unzip the ffmpeg archive."
        case .binaryNotFound: return "ffmpeg binary not found after extraction."
        case .checksumMismatch: return "Downloaded file failed verification."
        }
    }
}

/// Installs the ffmpeg binary that yt-dlp needs for merging streams, and
/// exposes setup progress as observable state for the first-launch UI.
@Observable
final class DependencyManager {

    enum SetupState {
        case checking
        case downloading
        case ready
        case failed(String)
    }

    // MARK: Observable state

    var setupState: SetupState = .checking

    /// Fraction of the ffmpeg download completed (0...1);
    /// nil while the total size is still unknown.
    private(set) var downloadProgress: Double?

    /// The in-flight setup run, if any. Guards against a second WindowGroup
    /// scene (e.g. Cmd+N) re-entering `performSetupIfNeeded()` while
    /// `installFFmpeg()` is still writing into `binDirectory` — without this,
    /// two concurrent `unzip` calls could race into the same directory.
    private var setupTask: Task<Void, Never>?

    // MARK: Public API

    /// Path of the installed ffmpeg binary; passed to yt-dlp via `--ffmpeg-location`.
    nonisolated var ffmpegURL: URL {
        binDirectory.appendingPathComponent("ffmpeg")
    }

    /// Records the SHA-256 of the zip that produced the currently installed
    /// `ffmpeg`, so a later bump of `pinnedRelease` can be detected even
    /// though the extracted binary itself carries no version marker.
    private nonisolated var installedReleaseMarkerURL: URL {
        binDirectory.appendingPathComponent("ffmpeg.version")
    }

    /// True only if the binary exists *and* matches the currently pinned
    /// release — an install from a since-superseded `pinnedRelease` is
    /// treated as not installed so it gets replaced.
    nonisolated func isFFmpegInstalled() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: ffmpegURL.path) else { return false }
        let installedSHA256 = try? String(contentsOf: installedReleaseMarkerURL, encoding: .utf8)
        return installedSHA256 == pinnedRelease.sha256
    }

    /// Installs ffmpeg unless it is already present, driving `setupState`
    /// through the stages so views can react. Safe to call from multiple
    /// windows at once: if a run is already in flight, this just awaits it
    /// instead of starting a second `installFFmpeg()`.
    func performSetupIfNeeded() async {
        if let setupTask {
            await setupTask.value
            return
        }

        let task = Task { await self.runSetup() }
        setupTask = task
        await task.value
        setupTask = nil
    }

    private func runSetup() async {
        setupState = .checking

        if isFFmpegInstalled() {
            setupState = .ready
            return
        }

        downloadProgress = nil
        setupState = .downloading

        do {
            try await installFFmpeg()
            setupState = .ready
        } catch {
            setupState = .failed(error.localizedDescription)
        }
    }

    // MARK: Locations

    private nonisolated var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("YTDLWrapper", isDirectory: true)
    }

    private nonisolated var binDirectory: URL {
        appSupportDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    // MARK: Pinned release

    /// The pinned ffmpeg release tag and the SHA-256 of its zip, hosted on
    /// our own GitHub releases.
    ///
    /// Hardcoding the hash means a tampered download fails verification even
    /// if the server itself is compromised. To update: publish a new release
    /// at https://github.com/ctenhove/YTDLPWrapper-Dependencies/releases,
    /// then update the tag and hash for both architectures
    /// (compute with `shasum -a 256 ffmpeg-<arch>.zip`).
    private nonisolated var pinnedRelease: (tag: String, sha256: String) {
        #if arch(arm64)
        ("v8.1.2", "ef1aa60006c7b77ce170c1608c08d8e4ba1c30c5746f2ac986ded932d0ac2c3c")
        #else
        ("v8.1.2", "a52ef43883f44c219766d4b3bdde4e635b35465d0b704c01c3a0566b59775df9")
        #endif
    }

    /// The architecture segment used in the release asset's filename.
    private nonisolated var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }

    private nonisolated var ffmpegDownloadURL: URL {
        URL(string: "https://github.com/ctenhove/YTDLPWrapper-Dependencies/releases/download/\(pinnedRelease.tag)/ffmpeg-\(architecture).zip")!
    }

    // MARK: Installation

    /// Downloads the pinned ffmpeg build, verifies it, and unpacks it into the
    /// bin directory. Runs off the main actor: unzipping blocks on a child
    /// process and hashing reads the whole archive.
    @concurrent
    private func installFFmpeg() async throws {
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )

        let tempZipURL = try await download(from: ffmpegDownloadURL) { [weak self] fraction in
            Task { @MainActor in self?.downloadProgress = fraction }
        }
        defer { try? FileManager.default.removeItem(at: tempZipURL) }

        try verifyChecksum(of: tempZipURL, expectedSHA256: pinnedRelease.sha256)
        try unzip(at: tempZipURL, to: binDirectory)

        guard FileManager.default.fileExists(atPath: ffmpegURL.path) else {
            throw DependencyError.binaryNotFound
        }

        // Extraction doesn't reliably preserve the execute bit, so set it explicitly.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: ffmpegURL.path
        )

        // Record what's now installed so a future pinnedRelease bump can be detected.
        try pinnedRelease.sha256.write(to: installedReleaseMarkerURL, atomically: true, encoding: .utf8)
    }

    /// Downloads `url` to a temporary file, invoking `onProgress` with a
    /// 0...1 fraction a few times a second while the transfer is in flight.
    /// Generic over the source URL so it can back both ffmpeg installation
    /// today and a yt-dlp self-update later — this function doesn't know or
    /// care what it's downloading.
    ///
    /// `URLSessionTask.progress` is safe to read from any thread, so a plain
    /// polling loop reports progress without needing a delegate class.
    @concurrent
    private func download(from url: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        var progressPoller: Task<Void, Never>?
        defer { progressPoller?.cancel() }

        let (location, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let location, let response {
                    continuation.resume(returning: (location, response))
                } else {
                    continuation.resume(throwing: DependencyError.downloadFailed)
                }
            }
            progressPoller = Task {
                while !Task.isCancelled {
                    onProgress(task.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            task.resume()
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw DependencyError.downloadFailed
        }

        // URLSession deletes its temp file as soon as the completion handler
        // returns, so move it somewhere durable before this function returns.
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: location, to: dest)
        onProgress(1.0)
        return dest
    }

    /// Throws unless `fileURL`'s SHA-256 matches `expectedSHA256`.
    private nonisolated func verifyChecksum(of fileURL: URL, expectedSHA256: String) throws {
        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let actualHash = SHA256.hash(data: fileData)
            .map { String(format: "%02x", $0) }
            .joined()

        guard actualHash == expectedSHA256 else {
            throw DependencyError.checksumMismatch
        }
    }

    /// Extracts a zip archive with the system `unzip` tool; Foundation has
    /// no built-in zip support.
    private nonisolated func unzip(at sourceURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", sourceURL.path, "-d", destinationURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DependencyError.unzipFailed
        }
    }
}
