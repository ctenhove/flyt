//
//  LanguageCode.swift
//  flyt
//

import Foundation

/// Helpers for comparing the language codes yt-dlp reports ("en", "en-US",
/// "zh-Hans", "es-419", …) against each other and against the user's system
/// language preferences.
enum LanguageCode {
    /// YouTube's marker for the speech-recognition track in a video's own
    /// language (e.g. "en-orig").
    static let originalSuffix = "-orig"

    /// YouTube's marker for a descriptive-audio track (e.g. "en-desc"):
    /// narration for blind users that isn't what anyone wants by default.
    static let descriptiveSuffix = "-desc"

    /// Lowercased, "_" as "-", and without the "-orig"/"-desc" markers.
    static func normalized(_ code: String) -> String {
        var text = code.lowercased().replacingOccurrences(of: "_", with: "-")
        for suffix in [originalSuffix, descriptiveSuffix] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        return text
    }

    /// "en" for "en-GB", "zh" for "zh-Hans-CN".
    static func base(_ code: String) -> String {
        normalized(code).split(separator: "-").first.map(String.init) ?? normalized(code)
    }

    /// A readable name for `code` in the user's language, without the
    /// "-orig"/"-desc" markers. Keeps the region or script, so "es-US" and
    /// "es-419" (or "zh-Hans" and "zh-Hant") don't come out identical.
    static func displayName(_ code: String) -> String {
        var bare = code
        for suffix in [originalSuffix, descriptiveSuffix] where bare.lowercased().hasSuffix(suffix) {
            bare.removeLast(suffix.count)
        }
        return Locale.current.localizedString(forIdentifier: bare)
            ?? Locale.current.localizedString(forLanguageCode: bare)
            ?? bare
    }

    /// How well `code` serves a wish for `preferred`, best first: 0 an exact
    /// match, 1 a more general code ("en" for "en-GB"), 2 the same base
    /// language, nil unrelated.
    static func matchTier(code: String, preferred: String) -> Int? {
        let have = normalized(code)
        let wanted = normalized(preferred)
        if have == wanted { return 0 }
        if wanted.hasPrefix(have + "-") { return 1 }
        if base(have) == base(wanted) { return 2 }
        return nil
    }
}
