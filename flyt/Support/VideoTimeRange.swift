//
//  VideoTimeRange.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-09-26.
//

import Foundation

/// One user-selected time range to trim a download to, in seconds within
/// the video's total duration. `YtDlpModel.download` turns each range into
/// a yt-dlp `--download-sections "*start-end"` argument.
struct VideoTimeRange: Identifiable, Hashable {
    let id = UUID()
    var start: Double
    var end: Double

    /// The smallest gap allowed between `start` and `end` — keeps a range
    /// from being dragged/typed down to zero (or negative) width.
    static let minimumLength: Double = 1

    /// Clamps `start`/`end` into `0...duration`, keeping at least
    /// `minimumLength` between them. Applied whenever a slider drag or a
    /// typed timestamp could otherwise produce an inverted or out-of-bounds
    /// range, so a `VideoTimeRange` in view state is always valid by
    /// construction rather than needing a separate error state.
    mutating func clamp(to duration: Double) {
        start = min(max(start, 0), duration)
        end = min(max(end, 0), duration)
        if end - start < Self.minimumLength {
            if start + Self.minimumLength <= duration {
                end = start + Self.minimumLength
            } else {
                start = max(0, duration - Self.minimumLength)
                end = duration
            }
        }
    }
}

extension [VideoTimeRange] {
    /// True if any two ranges share footage. Overlapping ranges aren't
    /// prevented — each is fetched as its own independent yt-dlp section,
    /// and nothing (here or in yt-dlp/ffmpeg's concat) deduplicates the
    /// shared span, so a "merge into one file" would play it twice. Used to
    /// warn rather than silently produce that duplicate footage.
    var hasOverlaps: Bool {
        for i in indices {
            for j in indices where j > i {
                if self[i].start < self[j].end && self[j].start < self[i].end {
                    return true
                }
            }
        }
        return false
    }
}
