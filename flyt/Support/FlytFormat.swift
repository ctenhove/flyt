//
//  FlytFormat.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import Foundation

/// Small display-formatting helpers shared across the redesigned main
/// window's views, so duration/size/count/path formatting stays consistent
/// wherever it repeats (thumbnail duration pill, metadata line, progress
/// stats, options summary, complete card, footer path row).
enum FlytFormat {
    /// "m:ss" under an hour, "h:mm:ss" at or above one.
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// The inverse of `duration(_:)`: parses "m:ss" or "h:mm:ss" (colon-
    /// separated, each part a non-negative number) into seconds. Lenient
    /// about a minutes/seconds part being 60 or over (e.g. "1:90" → 150s)
    /// rather than rejecting it — the caller clamps the result into the
    /// video's actual duration anyway, so there's nothing to gain from a
    /// stricter parse here. Returns nil for anything else (empty string,
    /// wrong number of parts, non-numeric part, negative number).
    static func parseDuration(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        return numbers.reduce(0) { total, part in total * 60 + part }
    }

    /// "1.2M views", "48K views", or "812 views".
    static func viewCount(_ count: Int) -> String {
        switch count {
        case 1_000_000...: "\(String(format: "%.1f", Double(count) / 1_000_000))M views"
        case 1_000...: "\(String(format: "%.1f", Double(count) / 1_000))K views"
        default: "\(count) views"
        }
    }

    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Abbreviates the user's home directory to "~", matching the footer
    /// path row and complete-card detail line's "~/Downloads/flyt" style.
    static func abbreviatedPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
