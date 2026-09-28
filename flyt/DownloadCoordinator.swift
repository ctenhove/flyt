//
//  DownloadCoordinator.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-09-28.
//

import Observation

/// Caps how many downloads can actually be transferring at once, so
/// starting several at the same time doesn't launch unlimited concurrent
/// yt-dlp/ffmpeg processes fighting over the same bandwidth and CPU.
/// Fetching metadata (`YtDlpModel.fetchInfo`) isn't gated by this — it's a
/// light webpage/API call, nothing like the transfer+merge a real download
/// does — only the transfer itself is.
@Observable
final class DownloadCoordinator {
    /// How many downloads can run at once. Not user-configurable — there's
    /// no Preferences surface in the app to put a setting like this on —
    /// just a fixed, reasonable default.
    static let maxConcurrentDownloads = 3

    private(set) var activeCount = 0

    var hasAvailableSlot: Bool {
        activeCount < Self.maxConcurrentDownloads
    }

    /// Claims a slot if one's free. Every call that returns `true` must be
    /// matched by exactly one later call to `releaseSlot()`, once that
    /// download finishes — success, failure, or cancellation all count.
    func tryReserveSlot() -> Bool {
        guard hasAvailableSlot else { return false }
        activeCount += 1
        return true
    }

    func releaseSlot() {
        activeCount = max(0, activeCount - 1)
    }
}
