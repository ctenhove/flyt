//
//  FilenamePolicy.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import Foundation

/// Filename rules for the editable filename field (README §5): sanitize for
/// the filesystem, and avoid silently overwriting an existing file by
/// appending " (2)", " (3)"… instead of clobbering it.
enum FilenamePolicy {

    /// Strips characters that can't safely appear in a macOS filename,
    /// collapses whitespace, and caps the length well under typical
    /// filesystem limits. `YtDlpModel`'s own output-template sanitization
    /// builds on this and adds `%`-escaping on top — that escaping is
    /// specific to yt-dlp's `-o` template syntax and would corrupt the name
    /// if applied here, since this value is also used as-is to check for
    /// filename collisions on disk.
    static func sanitize(_ name: String) -> String {
        var sanitized = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        for character in ["/", ":", "\\"] {
            sanitized = sanitized.replacingOccurrences(of: character, with: "-")
        }
        sanitized = sanitized
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        while sanitized.utf8.count > 255 {
            sanitized.removeLast()
        }
        return sanitized
    }

    /// Returns `base` unchanged unless a file already exists in `directory`
    /// whose name (before its extension) matches `base` exactly, in which
    /// case appends " (2)", " (3)"… until no such file exists.
    ///
    /// Checks against *any* extension rather than a specific guessed one:
    /// the caller only knows what extension yt-dlp is likely to write the
    /// file with, not what it definitely will (yt-dlp determines the real
    /// one at download time). Matching on any extension is the only way to
    /// guarantee this never silently overwrites an existing file just
    /// because that guess turned out wrong — at the cost of occasionally
    /// adding a "(2)" that a perfectly accurate guess wouldn't have needed,
    /// which is the safer direction to be wrong in.
    ///
    /// With `sectioned`, also treats " [" after `base` as a collision: trimmed
    /// multi-range downloads write `base [start-end].ext`, which the plain
    /// `base.` check would never see.
    static func uniqueFilename(base: String, in directory: URL, sectioned: Bool = false) -> String {
        let existingNames = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var candidate = base
        var suffix = 1
        while existingNames.contains(where: {
            $0.hasPrefix("\(candidate).") || (sectioned && $0.hasPrefix("\(candidate) ["))
        }) {
            suffix += 1
            candidate = "\(base) (\(suffix))"
        }
        return candidate
    }
}
