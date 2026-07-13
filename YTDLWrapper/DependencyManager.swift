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

    // MARK: Public API

    /// Path of the installed ffmpeg binary; passed to yt-dlp via `--ffmpeg-location`.
    nonisolated var ffmpegURL: URL {
        binDirectory.appendingPathComponent("ffmpeg")
    }

    nonisolated func isFFmpegInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: ffmpegURL.path)
    }

    /// Installs ffmpeg unless it is already present, driving `setupState`
    /// through the stages so views can react.
    func performSetupIfNeeded() async {
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

    /// The pinned ffmpeg release build and the SHA-256 of its zip.
    ///
    /// Hardcoding the hash means a tampered download fails verification even
    /// if the server itself is compromised. To update: pick a new release at
    /// https://ffmpeg.martin-riedl.de, then update the build ID and hash for
    /// both architectures (compute with `shasum -a 256 ffmpeg.zip`).
    private nonisolated var pinnedRelease: (buildID: String, sha256: String) {
        #if arch(arm64)
        ("1783011502_8.1.2", "ef1aa60006c7b77ce170c1608c08d8e4ba1c30c5746f2ac986ded932d0ac2c3c")
        #else
        ("1783018342_8.1.2", "a52ef43883f44c219766d4b3bdde4e635b35465d0b704c01c3a0566b59775df9")
        #endif
    }

    /// The architecture segment used in download URLs — "amd64" is the
    /// build server's name for Intel.
    private nonisolated var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }

    private nonisolated var ffmpegDownloadURL: URL {
        URL(string: "https://ffmpeg.martin-riedl.de/download/macos/\(architecture)/\(pinnedRelease.buildID)/ffmpeg.zip")!
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

        let tempZipURL = try await downloadWithProgress(from: ffmpegDownloadURL)
        try verifyChecksum(of: tempZipURL)
        try unzip(at: tempZipURL, to: binDirectory)

        guard FileManager.default.fileExists(atPath: ffmpegURL.path) else {
            throw DependencyError.binaryNotFound
        }

        // Extraction doesn't reliably preserve the execute bit, so set it explicitly.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: ffmpegURL.path
        )
    }

    /// Streams the download to a temporary file, publishing `downloadProgress`
    /// along the way.
    ///
    /// URLSession's one-shot `download(from:)` can't report progress with
    /// async/await, so this consumes the response body as a byte stream instead.
    @concurrent
    private func downloadWithProgress(from url: URL) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DependencyError.downloadFailed
        }

        let tempZipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("zip")
        FileManager.default.createFile(atPath: tempZipURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempZipURL)
        defer { try? handle.close() }

        let expectedLength = httpResponse.expectedContentLength
        let chunkSize = 256 * 1024
        var buffer = Data(capacity: chunkSize)
        var bytesReceived: Int64 = 0
        var lastPublishedProgress = 0.0

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count == chunkSize {
                try handle.write(contentsOf: buffer)
                bytesReceived += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                // Only publish whole-percent steps so the UI isn't flooded with updates.
                if expectedLength > 0 {
                    let progress = min(Double(bytesReceived) / Double(expectedLength), 1.0)
                    if progress - lastPublishedProgress >= 0.01 {
                        lastPublishedProgress = progress
                        await MainActor.run { downloadProgress = progress }
                    }
                }
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        await MainActor.run { downloadProgress = 1.0 }

        return tempZipURL
    }

    /// Throws unless the file's SHA-256 matches the pinned hash for this architecture.
    private nonisolated func verifyChecksum(of fileURL: URL) throws {
        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let actualHash = SHA256.hash(data: fileData)
            .map { String(format: "%02x", $0) }
            .joined()

        guard actualHash == pinnedRelease.sha256 else {
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
