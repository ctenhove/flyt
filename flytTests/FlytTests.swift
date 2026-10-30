//
//  FlytTests.swift
//  flytTests
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import Foundation
import Testing
@testable import flyt

/// Covers the pure, network-free pieces of the yt-dlp self-update logic
/// in `DependencyManager`. The network/filesystem-heavy pieces (fetching
/// release metadata, downloading, installing) aren't practical to unit
/// test without mock-URLProtocol infrastructure this project doesn't
/// have yet, and are verified manually instead.
struct FlytTests {

    // MARK: isNewerThanInstalled

    @Test func newerTagIsDetectedAsUpdate() {
        #expect(DependencyManager.isNewerThanInstalled("2026.07.10", installedTag: "2026.07.04"))
    }

    @Test func olderTagIsNotAnUpdate() {
        #expect(!DependencyManager.isNewerThanInstalled("2026.06.01", installedTag: "2026.07.04"))
    }

    @Test func equalTagIsNotAnUpdate() {
        #expect(!DependencyManager.isNewerThanInstalled("2026.07.04", installedTag: "2026.07.04"))
    }

    @Test func nothingInstalledYetIsAlwaysAnUpdate() {
        #expect(DependencyManager.isNewerThanInstalled("2026.07.04", installedTag: nil))
    }

    @Test func patchSuffixIsNewerThanBareSameDayTag() {
        #expect(DependencyManager.isNewerThanInstalled("2026.07.04.1", installedTag: "2026.07.04"))
    }

    // MARK: shouldCheckForUpdate

    @Test func neverCheckedBeforeShouldCheck() {
        #expect(DependencyManager.shouldCheckForUpdate(now: Date(), lastCheck: nil))
    }

    @Test func checkedWithinTheLastDayShouldNotRecheck() {
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-2 * 60 * 60)
        #expect(!DependencyManager.shouldCheckForUpdate(now: now, lastCheck: twoHoursAgo))
    }

    @Test func checkedOverADayAgoShouldRecheck() {
        let now = Date()
        let twoDaysAgo = now.addingTimeInterval(-2 * 24 * 60 * 60)
        #expect(DependencyManager.shouldCheckForUpdate(now: now, lastCheck: twoDaysAgo))
    }

    // MARK: parseSHA256(forFilename:fromSumsFileContents:)

    @Test func parsesHashForMatchingFilename() {
        let sums = """
        498bd0dae17855c599d371d68ec5bafc439a9d8640e838be25c765a9792f261b  yt-dlp_macos
        b0724470a0cf6dae5175a87eee05d6e75c5a0c10d2c3015166bd4d34e92b1b7b  yt-dlp_macos.zip
        """
        let hash = DependencyManager.parseSHA256(forFilename: "yt-dlp_macos", fromSumsFileContents: sums)
        #expect(hash == "498bd0dae17855c599d371d68ec5bafc439a9d8640e838be25c765a9792f261b")
    }

    @Test func returnsNilWhenFilenameIsAbsent() {
        let sums = "b0724470a0cf6dae5175a87eee05d6e75c5a0c10d2c3015166bd4d34e92b1b7b  yt-dlp_macos.zip"
        #expect(DependencyManager.parseSHA256(forFilename: "yt-dlp_macos", fromSumsFileContents: sums) == nil)
    }

    @Test func toleratesSingleSpaceSeparator() {
        let sums = "498bd0dae17855c599d371d68ec5bafc439a9d8640e838be25c765a9792f261b yt-dlp_macos"
        let hash = DependencyManager.parseSHA256(forFilename: "yt-dlp_macos", fromSumsFileContents: sums)
        #expect(hash == "498bd0dae17855c599d371d68ec5bafc439a9d8640e838be25c765a9792f261b")
    }

    @Test func returnsNilForEmptyContents() {
        #expect(DependencyManager.parseSHA256(forFilename: "yt-dlp_macos", fromSumsFileContents: "") == nil)
    }

    // MARK: DownloadCoordinator

    @Test func slotIsAvailableInitially() {
        let coordinator = DownloadCoordinator()
        #expect(coordinator.hasAvailableSlot)
        #expect(coordinator.activeCount == 0)
    }

    @Test func reservingUpToMaxSucceeds() {
        let coordinator = DownloadCoordinator()
        for _ in 0..<DownloadCoordinator.maxConcurrentDownloads {
            #expect(coordinator.tryReserveSlot())
        }
        #expect(coordinator.activeCount == DownloadCoordinator.maxConcurrentDownloads)
    }

    @Test func reservingPastMaxFails() {
        let coordinator = DownloadCoordinator()
        for _ in 0..<DownloadCoordinator.maxConcurrentDownloads {
            _ = coordinator.tryReserveSlot()
        }
        #expect(!coordinator.hasAvailableSlot)
        #expect(!coordinator.tryReserveSlot())
        #expect(coordinator.activeCount == DownloadCoordinator.maxConcurrentDownloads)
    }

    @Test func releasingFreesASlot() {
        let coordinator = DownloadCoordinator()
        for _ in 0..<DownloadCoordinator.maxConcurrentDownloads {
            _ = coordinator.tryReserveSlot()
        }
        coordinator.releaseSlot()
        #expect(coordinator.hasAvailableSlot)
        #expect(coordinator.tryReserveSlot())
    }

    @Test func releasingBelowZeroStaysAtZero() {
        let coordinator = DownloadCoordinator()
        coordinator.releaseSlot()
        #expect(coordinator.activeCount == 0)
    }

    // MARK: DownloadHistoryStore

    private static func scratchHistoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("flyt-history-test-\(UUID().uuidString).json")
    }

    @Test func newStoreStartsEmpty() {
        let store = DownloadHistoryStore(fileURL: Self.scratchHistoryURL())
        #expect(store.entries.isEmpty)
    }

    @Test func recordingAddsNewestFirst() {
        let store = DownloadHistoryStore(fileURL: Self.scratchHistoryURL())
        let first = DownloadHistoryEntry(urlString: "https://youtu.be/a", title: "A", fileName: "a.mp4", thumbnailURLString: nil)
        let second = DownloadHistoryEntry(urlString: "https://youtu.be/b", title: "B", fileName: "b.mp4", thumbnailURLString: nil)
        store.record(first)
        store.record(second)
        #expect(store.entries.map(\.title) == ["B", "A"])
    }

    @Test func removingDeletesOnlyThatEntry() {
        let store = DownloadHistoryStore(fileURL: Self.scratchHistoryURL())
        let first = DownloadHistoryEntry(urlString: "https://youtu.be/a", title: "A", fileName: "a.mp4", thumbnailURLString: nil)
        let second = DownloadHistoryEntry(urlString: "https://youtu.be/b", title: "B", fileName: "b.mp4", thumbnailURLString: nil)
        store.record(first)
        store.record(second)
        store.remove(first)
        #expect(store.entries.map(\.title) == ["B"])
    }

    @Test func clearAllEmptiesTheStore() {
        let store = DownloadHistoryStore(fileURL: Self.scratchHistoryURL())
        store.record(DownloadHistoryEntry(urlString: "https://youtu.be/a", title: "A", fileName: "a.mp4", thumbnailURLString: nil))
        store.clearAll()
        #expect(store.entries.isEmpty)
    }

    @Test func persistsAcrossInstancesViaTheSameFile() {
        let url = Self.scratchHistoryURL()
        let first = DownloadHistoryStore(fileURL: url)
        first.record(DownloadHistoryEntry(urlString: "https://youtu.be/a", title: "A", fileName: "a.mp4", thumbnailURLString: nil))

        let second = DownloadHistoryStore(fileURL: url)
        #expect(second.entries.map(\.title) == ["A"])
    }

    @Test func unreadableHistoryFileIsMovedAsideNotOverwritten() throws {
        let url = Self.scratchHistoryURL()
        try Data("not json".utf8).write(to: url)

        let store = DownloadHistoryStore(fileURL: url)
        #expect(store.entries.isEmpty)
        store.record(DownloadHistoryEntry(urlString: "https://youtu.be/a", title: "A", fileName: "a.mp4", thumbnailURLString: nil))

        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        let backups = siblings.filter { $0.hasPrefix("\(url.lastPathComponent).unreadable-") }
        #expect(backups.count == 1)
        let backupURL = url.deletingLastPathComponent().appendingPathComponent(backups[0])
        #expect(try Data(contentsOf: backupURL) == Data("not json".utf8))
    }

    // MARK: ScratchFolderRegistry

    private static func scratchFolder(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func sweepDeletesFoldersFromDeadProcessesOnly() throws {
        let manifest = FileManager.default.temporaryDirectory.appendingPathComponent("flyt-scratch-\(UUID().uuidString).json")
        let stale = try Self.scratchFolder(named: ".flyt-\(UUID().uuidString)")
        let live = try Self.scratchFolder(named: ".flyt-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: stale)
            try? FileManager.default.removeItem(at: live)
        }
        ScratchFolderRegistry.register(stale, pid: Int32.max, manifestURL: manifest)
        ScratchFolderRegistry.register(live, manifestURL: manifest)

        ScratchFolderRegistry.sweepStale(manifestURL: manifest)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: live.path))
    }

    @Test func sweepNeverDeletesFoldersThatAreNotFlytScratchFolders() throws {
        let manifest = FileManager.default.temporaryDirectory.appendingPathComponent("flyt-scratch-\(UUID().uuidString).json")
        let unrelated = try Self.scratchFolder(named: "flyt-unrelated-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: unrelated) }
        ScratchFolderRegistry.register(unrelated, pid: Int32.max, manifestURL: manifest)

        ScratchFolderRegistry.sweepStale(manifestURL: manifest)

        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test func unregisteredFoldersAreLeftAloneBySweep() throws {
        let manifest = FileManager.default.temporaryDirectory.appendingPathComponent("flyt-scratch-\(UUID().uuidString).json")
        let kept = try Self.scratchFolder(named: ".flyt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: kept) }
        ScratchFolderRegistry.register(kept, pid: Int32.max, manifestURL: manifest)
        ScratchFolderRegistry.unregister(kept, manifestURL: manifest)

        ScratchFolderRegistry.sweepStale(manifestURL: manifest)

        #expect(FileManager.default.fileExists(atPath: kept.path))
    }

    // MARK: VideoFormat.isBroadlyCompatibleCodec

    @Test func avcIsBroadlyCompatible() {
        #expect(Self.videoFormat(id: "137", vcodec: "avc1.640028").isBroadlyCompatibleCodec)
    }

    @Test func vp9IsNotBroadlyCompatible() {
        #expect(!Self.videoFormat(id: "248", vcodec: "vp09.00.40.08").isBroadlyCompatibleCodec)
    }

    @Test func av1IsNotBroadlyCompatible() {
        #expect(!Self.videoFormat(id: "399", vcodec: "av01.0.08M.08").isBroadlyCompatibleCodec)
    }

    // MARK: FormatSelection.resolutionOptions codec tie-break

    @Test func tiedQualityPrefersBroadlyCompatibleCodec() {
        let avc = Self.videoFormat(id: "137", height: 1080, vcodec: "avc1.640028")
        let vp9 = Self.videoFormat(id: "248", height: 1080, vcodec: "vp09.00.40.08")
        let av1 = Self.videoFormat(id: "399", height: 1080, vcodec: "av01.0.08M.08")
        // Regardless of input order, the H.264 option should win the tie.
        #expect(FormatSelection.resolutionOptions(in: [vp9, av1, avc]).first?.format.id == "137")
        #expect(FormatSelection.resolutionOptions(in: [avc, vp9, av1]).first?.format.id == "137")
    }

    @Test func noCompatibleCodecStillResolvesToBestQuality() {
        let vp9 = Self.videoFormat(id: "620", height: 1440, fps: 25, vcodec: "vp09.00.50.08")
        let av1 = Self.videoFormat(id: "400", height: 1440, fps: 30, vcodec: "av01.0.12M.08")
        #expect(FormatSelection.resolutionOptions(in: [vp9, av1]).first?.format.id == "400")
    }

    @Test func higherQualityWinsEvenOverCompatibleCodec() {
        let lowerAVC = Self.videoFormat(id: "135", height: 480, vcodec: "avc1.4d401e")
        let higherAV1 = Self.videoFormat(id: "401", height: 2160, vcodec: "av01.0.12M.08")
        #expect(FormatSelection.resolutionOptions(in: [lowerAVC, higherAV1]).first?.format.id == "401")
    }

    private static func videoFormat(id: String, height: Int = 1080, fps: Double = 25, vcodec: String) -> VideoFormat {
        VideoFormat(
            formatId: id,
            ext: "mp4",
            resolution: nil,
            height: height,
            fps: fps,
            vcodec: vcodec,
            acodec: nil,
            abr: nil,
            tbr: nil,
            filesize: nil,
            filesizeApprox: nil
        )
    }

}
