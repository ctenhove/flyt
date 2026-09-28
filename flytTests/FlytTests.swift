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

    // MARK: ClipboardYouTubeURL.isYouTubeURL

    @Test func recognizesYoutubeDotBeLink() {
        #expect(ClipboardYouTubeURL.isYouTubeURL("https://youtu.be/dQw4w9WgXcQ"))
    }

    @Test func recognizesWwwYoutubeLink() {
        #expect(ClipboardYouTubeURL.isYouTubeURL("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    @Test func rejectsNonYoutubeLink() {
        #expect(!ClipboardYouTubeURL.isYouTubeURL("https://example.com/watch?v=dQw4w9WgXcQ"))
    }

    @Test func rejectsPlainText() {
        #expect(!ClipboardYouTubeURL.isYouTubeURL("not a url"))
    }

    @Test func rejectsNonHTTPScheme() {
        #expect(!ClipboardYouTubeURL.isYouTubeURL("ftp://youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    // MARK: ClipboardYouTubeURL.label(for:)

    @Test func labelShowsHostAndPathForShortURL() {
        #expect(ClipboardYouTubeURL.label(for: "https://youtu.be/dQw4w9WgXcQ") == "Paste — youtu.be/dQw4w9WgXcQ")
    }

    @Test func labelDropsWwwPrefix() {
        #expect(ClipboardYouTubeURL.label(for: "https://www.youtube.com/x") == "Paste — youtube.com/x")
    }

}
