//
//  FlytError.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import Foundation

/// Presentation-layer copy for a failed fetch/download, mapped from
/// yt-dlp's raw stderr text (`YtDlpModel.errorMessage`) to the plain-language
/// title/body the design handoff specifies (README §3.8): name what
/// happened, then the one action that helps — never a yt-dlp exit code.
struct FlytError {
    let title: String
    let message: String

    /// Matches on substrings of yt-dlp's known error phrasing. This is
    /// heuristic, not a stable API — yt-dlp's own wording can change as
    /// extractors are updated, so it may need retuning against real-world
    /// output over time.
    init(rawMessage: String) {
        let lowered = rawMessage.lowercased()

        if lowered.contains("private video") {
            title = "This video is private"
            message = "flyt can only fetch videos that are publicly viewable."
        } else if lowered.contains("confirm your age") || lowered.contains("age-restricted") {
            title = "This video is age-restricted"
            message = "flyt can't fetch age-restricted videos without signing in, which isn't supported yet."
        } else if lowered.contains("available in your country") || lowered.contains("not available in your country") {
            title = "Not available in your region"
            message = "The uploader has restricted this video in your country. There's no way around this from flyt."
        } else if lowered.contains("members-only") || lowered.contains("join this channel") {
            title = "This video is members-only"
            message = "Only channel members can watch this video. flyt doesn't support member-gated content."
        } else if lowered.contains("unsupported url") {
            title = "That link isn't supported"
            message = "flyt only downloads individual YouTube videos — double-check the link and try again."
        } else if Self.looksLikeNetworkFailure(lowered) {
            title = "Connection lost"
            message = "flyt couldn't reach the internet partway through. Check your connection and try again."
        } else if lowered.contains("no space left on device") {
            title = "Not enough disk space"
            message = "There isn't enough free space at the download destination. Free up some space and try again."
        } else if Self.isRawExitCode(rawMessage) {
            // YtDlpModel's own last-resort fallback ("yt-dlp exited with
            // code N") for a failure with no "ERROR" line to draw a
            // message from at all — exactly the internal-tool text this
            // type exists to keep off screen, so it gets its own generic
            // copy rather than falling through to strippingErrorPrefix,
            // which only strips a leading "ERROR:" and would otherwise
            // pass this straight through unchanged.
            title = "Something went wrong"
            message = "flyt couldn't finish this. Try again in a moment."
        } else {
            title = "Something went wrong"
            message = Self.strippingErrorPrefix(rawMessage)
        }
    }

    private static func looksLikeNetworkFailure(_ lowered: String) -> Bool {
        lowered.contains("network is unreachable")
            || lowered.contains("could not connect")
            || lowered.contains("connection reset")
            || lowered.contains("timed out")
            || lowered.contains("offline")
    }

    /// Matches YtDlpModel.failureMessage's own fallback text exactly, so
    /// only that specific string is intercepted — any other message
    /// mentioning an exit code as incidental detail still passes through
    /// strippingErrorPrefix as before.
    private static func isRawExitCode(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).firstMatch(of: /^yt-dlp exited with code -?\d+$/) != nil
    }

    /// yt-dlp prefixes its own error lines with "ERROR:"; that prefix reads
    /// as internal-tool noise once it's the headline of a friendly card, so
    /// the generic fallback drops it.
    private static func strippingErrorPrefix(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ERROR:") {
            trimmed = String(trimmed.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}
