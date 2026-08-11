//
//  DependencyManager.swift
//  flyt
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
    case releaseAssetNotFound
    case releaseMetadataInvalid

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return "Failed to download ffmpeg."
        case .unzipFailed: return "Failed to unzip the ffmpeg archive."
        case .binaryNotFound: return "ffmpeg binary not found after extraction."
        case .checksumMismatch: return "Downloaded file failed verification."
        case .releaseAssetNotFound: return "Could not find the expected yt-dlp release files on GitHub."
        case .releaseMetadataInvalid: return "GitHub's yt-dlp release information couldn't be read."
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

    /// The GitHub release tag of the currently installed self-updated
    /// yt-dlp binary (e.g. "2026.07.04"), or nil if only the bundled
    /// fallback binary has ever been used. Populated from
    /// `installedYtdlpVersionMarkerURL` at init and kept in sync by
    /// `refreshYtdlpIfNeeded()`, so a SwiftUI view showing it updates live
    /// when a background update finishes, without needing a relaunch.
    private(set) var installedYtdlpVersion: String?

    init() {
        installedYtdlpVersion = try? String(contentsOf: installedYtdlpVersionMarkerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
        return base.appendingPathComponent("flyt", isDirectory: true)
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
    ///
    /// Streams the file in fixed-size chunks rather than loading it whole:
    /// hashing has to fault in every page regardless, so `Data(contentsOf:)`
    /// bought nothing but held the entire (tens-of-MB) file in memory at once.
    private nonisolated func verifyChecksum(of fileURL: URL, expectedSHA256: String) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1 << 20 // 1 MB
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        let actualHash = hasher.finalize()
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

    // MARK: yt-dlp self-update

    /// Path of the installed yt-dlp binary, if a self-updated copy has
    /// been downloaded. `YtDlpModel.locateBinary()` prefers this over the
    /// bundled resource, falling back to the bundled copy when nothing
    /// has been installed here yet.
    nonisolated var ytdlpURL: URL {
        binDirectory.appendingPathComponent("yt-dlp")
    }

    /// Records the GitHub release tag (e.g. "2026.07.04") of the
    /// currently installed `yt-dlp`, so `refreshYtdlpIfNeeded()` can tell
    /// whether a newer release exists without re-downloading just to check.
    private nonisolated var installedYtdlpVersionMarkerURL: URL {
        binDirectory.appendingPathComponent("yt-dlp.version")
    }

    private static let lastYtdlpUpdateCheckDateKey = "lastYtdlpUpdateCheckDate"

    /// When `refreshYtdlpIfNeeded()` last actually ran a check (successful
    /// or not) — stored in `UserDefaults` rather than a marker file
    /// alongside the binary because it's disposable rate-limiting
    /// metadata, not a fact about what's installed.
    private nonisolated var lastYtdlpUpdateCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastYtdlpUpdateCheckDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastYtdlpUpdateCheckDateKey) }
    }

    private nonisolated static let ytdlpLatestReleaseURL = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!

    /// One fetched GitHub release's tag and the two asset URLs
    /// `installYtdlp` needs.
    private struct YtdlpRelease {
        let tag: String
        let binaryURL: URL
        let sumsURL: URL
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [GitHubReleaseAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private struct GitHubReleaseAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    /// Checks GitHub once a day (regardless of how many times the app is
    /// relaunched in between) for a newer yt-dlp release, and installs it
    /// in the background if found.
    ///
    /// Entirely best-effort: unlike ffmpeg, yt-dlp always has a working
    /// fallback available (the bundled resource, or a previously
    /// installed copy), so any failure here — offline, GitHub
    /// unreachable/rate-limited, a bad checksum — is swallowed rather
    /// than surfaced. This must never block startup or make the app
    /// unusable; call it unawaited alongside `performSetupIfNeeded()`,
    /// not in place of it.
    func refreshYtdlpIfNeeded() async {
        guard Self.shouldCheckForUpdate(now: Date(), lastCheck: lastYtdlpUpdateCheckDate) else { return }
        lastYtdlpUpdateCheckDate = Date()

        do {
            let release = try await fetchLatestYtdlpRelease()
            guard Self.isNewerThanInstalled(release.tag, installedTag: installedYtdlpVersion) else { return }
            try await installYtdlp(release)
            installedYtdlpVersion = release.tag
        } catch {
            print("yt-dlp update check failed: \(error)")
        }
    }

    /// Only true once ~a day has passed since the last check (or none has
    /// ever run), so relaunching the app repeatedly doesn't hammer
    /// GitHub's API. `now`/`lastCheck` are explicit parameters — rather
    /// than reading `Date()`/`lastYtdlpUpdateCheckDate` directly — so this
    /// stays pure and deterministic to unit test.
    nonisolated static func shouldCheckForUpdate(now: Date, lastCheck: Date?) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) > 24 * 60 * 60
    }

    /// True if `latestTag` is newer than `installedTag` — or if nothing
    /// is installed yet, in which case any successful release fetch is
    /// worth installing once, to get off whatever `yt-dlp_macos` happened
    /// to ship in the build.
    ///
    /// yt-dlp tags are always zero-padded `YYYY.MM.DD`, optionally with a
    /// `.N` suffix for same-day re-releases — a fixed-width format that
    /// sorts correctly under plain string comparison, so there's no need
    /// to parse into a date or version type. (The one known edge case:
    /// double-digit `.N` suffixes, e.g. `.10` vs `.2`, would compare
    /// incorrectly — but that's vanishingly rare, and self-corrects the
    /// next time a distinctly newer date tag ships, given the daily
    /// check cadence.)
    nonisolated static func isNewerThanInstalled(_ latestTag: String, installedTag: String?) -> Bool {
        guard let installedTag else { return true }
        return latestTag > installedTag
    }

    /// Fetches yt-dlp's latest GitHub release metadata and locates the
    /// two assets `installYtdlp` needs: the macOS binary and its
    /// checksum file. yt-dlp can't be pinned like ffmpeg — the whole
    /// point of this feature is picking up whatever the newest release
    /// fixes — so this always asks GitHub for "latest" rather than
    /// comparing against a hardcoded tag.
    @concurrent
    private func fetchLatestYtdlpRelease() async throws -> YtdlpRelease {
        let (data, response) = try await URLSession.shared.data(from: Self.ytdlpLatestReleaseURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw DependencyError.downloadFailed
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw DependencyError.releaseMetadataInvalid
        }

        guard let binaryAsset = release.assets.first(where: { $0.name == "yt-dlp_macos" }),
              let sumsAsset = release.assets.first(where: { $0.name == "SHA2-256SUMS" }) else {
            throw DependencyError.releaseAssetNotFound
        }

        return YtdlpRelease(tag: release.tagName, binaryURL: binaryAsset.browserDownloadURL, sumsURL: sumsAsset.browserDownloadURL)
    }

    /// Downloads `release`'s binary and checksum file, verifies the
    /// binary against the checksum, strips quarantine, and atomically
    /// installs it into `binDirectory` — mirroring `installFFmpeg`'s
    /// download/verify pipeline, but swapping the file in explicitly
    /// (see below) instead of unzipping in place, since there's no zip
    /// step here to make the swap atomic for free.
    @concurrent
    private func installYtdlp(_ release: YtdlpRelease) async throws {
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let tempBinaryURL = try await download(from: release.binaryURL) { _ in }
        defer { try? FileManager.default.removeItem(at: tempBinaryURL) }

        let (sumsData, sumsResponse) = try await URLSession.shared.data(from: release.sumsURL)
        guard let httpResponse = sumsResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let sumsContents = String(data: sumsData, encoding: .utf8) else {
            throw DependencyError.downloadFailed
        }
        guard let expectedSHA256 = Self.parseSHA256(forFilename: "yt-dlp_macos", fromSumsFileContents: sumsContents) else {
            throw DependencyError.releaseAssetNotFound
        }

        try verifyChecksum(of: tempBinaryURL, expectedSHA256: expectedSHA256)
        try stripQuarantine(at: tempBinaryURL)

        // Extraction doesn't reliably preserve the execute bit for
        // ffmpeg's zip; a raw downloaded file never has it set either.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: tempBinaryURL.path
        )

        // `replaceItemAt` only applies to an existing destination, so the
        // first-ever install (no prior `ytdlpURL`) has to go through
        // `moveItem` instead; both are atomic renames as long as the temp
        // directory and `binDirectory` are on the same volume, which
        // holds in practice since both live under the user's home volume.
        if FileManager.default.fileExists(atPath: ytdlpURL.path) {
            _ = try FileManager.default.replaceItemAt(ytdlpURL, withItemAt: tempBinaryURL, options: [.usingNewMetadataOnly])
        } else {
            try FileManager.default.moveItem(at: tempBinaryURL, to: ytdlpURL)
        }

        // Written only now that the binary swap has actually succeeded —
        // writing it any earlier could leave the marker claiming a
        // version that isn't the one actually on disk if a later step
        // in this function had failed instead.
        try release.tag.write(to: installedYtdlpVersionMarkerURL, atomically: true, encoding: .utf8)
    }

    /// Extracts the SHA-256 hash for `filename` from a `SHA2-256SUMS`
    /// style file, whose lines look like `<64-hex-char hash>  <filename>`
    /// (format confirmed against yt-dlp's actual release asset). Pure and
    /// nonisolated so it's trivially unit-testable without any network
    /// or filesystem access.
    nonisolated static func parseSHA256(forFilename filename: String, fromSumsFileContents contents: String) -> String? {
        for line in contents.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[1] == Substring(filename) else { continue }
            return String(fields[0])
        }
        return nil
    }

    /// Removes the `com.apple.quarantine` extended attribute a raw
    /// binary download picks up, so Gatekeeper doesn't intercept its
    /// first execution. Unlike ffmpeg — extracted from a zip via
    /// `/usr/bin/unzip`, which happens not to propagate the quarantine
    /// flag to the extracted files — yt-dlp is downloaded as a
    /// standalone executable with no such step to strip it along the
    /// way, so this has no equivalent elsewhere in this file; don't
    /// remove it as "redundant" with the ffmpeg flow.
    private nonisolated func stripQuarantine(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()
        // A non-zero exit here almost always just means the attribute
        // wasn't present in the first place — not a real failure — so
        // it's intentionally not thrown.
    }
}
