//
//  DependencyManager.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-08.
//

import Foundation

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

class DependencyManager {
    
    // The app's dedicated folder inside Application Support
    private var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("YTDLWrapper", isDirectory: true)
    }

    // Where our downloaded binaries live
    private var binDirectory: URL {
        appSupportDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    // The full path to the ffmpeg binary specifically
    var ffmpegURL: URL {
        binDirectory.appendingPathComponent("ffmpeg")
    }
    
    // Detect whether we're on Apple Silicon or Intel
    var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }
    
    private var ffmpegDownloadURL: URL {
        URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(architecture)/release/ffmpeg.zip")!
    }
    
    private func createBinDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
    }
    
    // Is ffmpeg already downloaded and available?
    func isFFmpegInstalled() -> Bool {
        FileManager.default.fileExists(atPath: ffmpegURL.path)
    }
    
    func installFFmpeg() async throws {
        try createBinDirectoryIfNeeded()

        // 1. Download the zip to a temporary location
        let (tempZipURL, response) = try await URLSession.shared.download(from: ffmpegDownloadURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DependencyError.downloadFailed
        }

        // 2. Unzip into the bin directory
        try unzip(at: tempZipURL, to: binDirectory)

        // 3. Confirm the binary actually landed
        guard FileManager.default.fileExists(atPath: ffmpegURL.path) else {
            throw DependencyError.binaryNotFound
        }

        // 4. Make it executable
        try makeExecutable(at: ffmpegURL)
    }
    
    private func unzip(at sourceURL: URL, to destinationURL: URL) throws {
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
    
    private func makeExecutable(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
