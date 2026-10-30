//
//  FlytTests.swift
//  flytTests
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import Foundation
import Testing
@testable import flyt

/// Covers the pure, network-free logic scattered across the app: the
/// yt-dlp self-update checks in `DependencyManager`, and format/subtitle
/// picker helpers in `Support/`. The network/filesystem-heavy pieces
/// (fetching release metadata, downloading, installing) aren't practical
/// to unit test without mock-URLProtocol infrastructure this project
/// doesn't have yet, and are verified manually instead.
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

    // MARK: YtDlpModel.parseProgressDetail

    @Test func parsesAPlainProgressLine() {
        let detail = YtDlpModel.parseProgressDetail(from: "[download]  46.5% of   74.32MiB at    4.10MiB/s ETA 00:12")
        #expect(detail?.total == "74.32MiB")
        #expect(detail?.speed == "4.10MiB/s")
        #expect(detail?.eta == "00:12")
    }

    @Test func parsesAnEstimatedTotalPaddedAfterTheTilde() {
        let detail = YtDlpModel.parseProgressDetail(from: "[download]  14.0% of ~   1.07GiB at    2.45MiB/s ETA 07:12 (frag 12/80)")
        #expect(detail?.total == "1.07GiB")
        #expect(detail?.speed == "2.45MiB/s")
        #expect(detail?.eta == "07:12")
    }

    @Test func unknownSpeedAndEtaStillYieldTheTotalSize() {
        let detail = YtDlpModel.parseProgressDetail(from: "[download]   0.3% of ~ 512.00MiB at  Unknown B/s ETA Unknown")
        #expect(detail?.total == "512.00MiB")
        #expect(detail?.speed == nil)
        #expect(detail?.eta == nil)
    }

    @Test func aLineWithNoSizeIsNotProgressDetail() {
        #expect(YtDlpModel.parseProgressDetail(from: "[download] Destination: video.mp4") == nil)
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

    // MARK: SubtitleSelection.languageOptions

    @Test func manualAndAutoLanguagesBothAppear() {
        let options = SubtitleSelection.languageOptions(
            subtitles: ["en": [SubtitleTrackInfo(name: "English")]],
            automaticCaptions: ["es": [SubtitleTrackInfo(name: "Spanish")]]
        )
        #expect(options.count == 2)
        #expect(options.contains { $0.code == "en" && !$0.isAutoGenerated })
        #expect(options.contains { $0.code == "es" && $0.isAutoGenerated })
    }

    @Test func manualLanguageTakesPrecedenceOverAutoForSameCode() {
        let options = SubtitleSelection.languageOptions(
            subtitles: ["en": [SubtitleTrackInfo(name: "English")]],
            automaticCaptions: ["en": [SubtitleTrackInfo(name: "English")]]
        )
        #expect(options.count == 1)
        #expect(options.first?.isAutoGenerated == false)
    }

    @Test func noSubtitlesOrCaptionsYieldsNoOptions() {
        #expect(SubtitleSelection.languageOptions(subtitles: nil, automaticCaptions: nil).isEmpty)
    }

    @Test func autoGeneratedLabelIsMarked() {
        let option = SubtitleSelection.LanguageOption(code: "en", isAutoGenerated: true)
        #expect(option.label.hasSuffix("(auto)"))
    }

    // MARK: FormatSelection.resolutionOptions tie-break

    @Test func tiedQualityPrefersReliableProgressProtocol() {
        let https = Self.videoFormat(id: "137", height: 1080, fps: 30, formatProtocol: "https")
        let hls = Self.videoFormat(id: "270", height: 1080, fps: 30, formatProtocol: "m3u8_native")
        let options = FormatSelection.resolutionOptions(in: [hls, https])
        #expect(options.first?.format.id == "137")
    }

    @Test func higherQualityWinsEvenOverReliableProtocol() {
        let lowerHTTPS = Self.videoFormat(id: "135", height: 480, fps: 30, formatProtocol: "https")
        let higherHLS = Self.videoFormat(id: "270", height: 1080, fps: 30, formatProtocol: "m3u8_native")
        let options = FormatSelection.resolutionOptions(in: [lowerHTTPS, higherHLS])
        #expect(options.first?.format.id == "270")
    }

    private static func videoFormat(
        id: String,
        height: Int = 1080,
        fps: Double = 25,
        vcodec: String = "avc1",
        formatProtocol: String? = nil
    ) -> VideoFormat {
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
            filesizeApprox: nil,
            formatProtocol: formatProtocol
        )
    }

    // MARK: FlytFormat.parseDuration

    @Test func parsesMinutesAndSeconds() {
        #expect(FlytFormat.parseDuration("1:30") == 90)
    }

    @Test func parsesHoursMinutesAndSeconds() {
        #expect(FlytFormat.parseDuration("1:02:03") == 3723)
    }

    @Test func toleratesOverflowingSecondsPart() {
        #expect(FlytFormat.parseDuration("1:90") == 150)
    }

    @Test func rejectsNonNumericInput() {
        #expect(FlytFormat.parseDuration("abc") == nil)
    }

    @Test func rejectsWrongPartCount() {
        #expect(FlytFormat.parseDuration("30") == nil)
        #expect(FlytFormat.parseDuration("1:02:03:04") == nil)
    }

    @Test func rejectsNegativeParts() {
        #expect(FlytFormat.parseDuration("-1:30") == nil)
    }

    @Test func durationAndParseDurationRoundTrip() {
        let text = FlytFormat.duration(3723)
        #expect(FlytFormat.parseDuration(text) == 3723)
    }

    // MARK: VideoTimeRange.clamp

    @Test func clampLeavesAlreadyValidRangeUnchanged() {
        var range = VideoTimeRange(start: 10, end: 20)
        range.clamp(to: 100)
        #expect(range.start == 10)
        #expect(range.end == 20)
    }

    @Test func clampPullsBoundsIntoDuration() {
        var range = VideoTimeRange(start: -5, end: 150)
        range.clamp(to: 100)
        #expect(range.start == 0)
        #expect(range.end == 100)
    }

    @Test func clampEnforcesMinimumLengthWhenEndBeforeStart() {
        var range = VideoTimeRange(start: 50, end: 20)
        range.clamp(to: 100)
        #expect(range.end - range.start >= VideoTimeRange.minimumLength)
        #expect(range.start == 50)
    }

    @Test func clampNearDurationEndKeepsRangeInBounds() {
        var range = VideoTimeRange(start: 99.8, end: 99.9)
        range.clamp(to: 100)
        #expect(range.start >= 0)
        #expect(range.end <= 100)
        #expect(range.end - range.start >= VideoTimeRange.minimumLength)
    }

    // MARK: [VideoTimeRange].hasOverlaps

    @Test func adjacentRangesDoNotOverlap() {
        let ranges = [VideoTimeRange(start: 0, end: 10), VideoTimeRange(start: 10, end: 20)]
        #expect(!ranges.hasOverlaps)
    }

    @Test func overlappingRangesAreDetected() {
        let ranges = [VideoTimeRange(start: 0, end: 10), VideoTimeRange(start: 5, end: 15)]
        #expect(ranges.hasOverlaps)
    }

    @Test func fullyContainedRangeIsDetectedAsOverlap() {
        let ranges = [VideoTimeRange(start: 0, end: 20), VideoTimeRange(start: 5, end: 10)]
        #expect(ranges.hasOverlaps)
    }

    @Test func nonOverlappingOutOfOrderRangesAreNotFlagged() {
        let ranges = [VideoTimeRange(start: 20, end: 30), VideoTimeRange(start: 0, end: 10)]
        #expect(!ranges.hasOverlaps)
    }

    @Test func singleRangeNeverOverlaps() {
        #expect(![VideoTimeRange(start: 0, end: 10)].hasOverlaps)
    }

}
