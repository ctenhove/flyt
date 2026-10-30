//
//  ClipboardYouTubeURL.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-09-28.
//

import AppKit

/// A one-time check of the general pasteboard for a YouTube link, backing
/// the idle URL field's "Paste — youtu.be/…" affordance. Deliberately not
/// continuous clipboard watching — see `IdleDropZone`'s doc comment on why
/// that's out of scope without a Preferences toggle to gate it behind.
enum ClipboardYouTubeURL {
    private static let youtubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"
    ]

    /// The clipboard's current string, if it parses as an http(s) YouTube URL.
    static func current() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              isYouTubeURL(raw) else {
            return nil
        }
        return raw
    }

    /// True if `raw` parses as an http(s) URL whose host is a known YouTube
    /// domain. Pure, so it's unit-testable without touching the actual
    /// pasteboard.
    static func isYouTubeURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return youtubeHosts.contains(host)
    }

    /// A short label for the paste affordance, e.g. "Paste — youtu.be/dQw4w9WgXcQ".
    static func label(for urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "Paste" }
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? ""
        var display = host + url.path
        // A watch link's path is always just "/watch"; the video is in the
        // `v` parameter, so show that or every link would read the same.
        if url.path == "/watch",
           let videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
               .queryItems?.first(where: { $0.name == "v" })?.value {
            display += "?v=" + videoID
        }
        if display.count > 36 {
            display = String(display.prefix(33)) + "…"
        }
        return "Paste — \(display)"
    }
}
