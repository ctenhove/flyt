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

    /// Returns `base` unchanged if `base.ext` doesn't already exist in
    /// `directory`, otherwise appends " (2)", " (3)"… until it finds a name
    /// that doesn't collide.
    static func uniqueFilename(base: String, extension ext: String, in directory: URL) -> String {
        var candidate = base
        var suffix = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(candidate).\(ext)").path) {
            suffix += 1
            candidate = "\(base) (\(suffix))"
        }
        return candidate
    }
}
