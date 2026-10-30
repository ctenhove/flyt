//
//  FormatSelection.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import Foundation

/// Pure helpers that turn a video's full `VideoFormat` list into the
/// simplified resolution/audio-extension pickers the design handoff shows
/// (README §3.5) — the real per-video ladder rather than the handoff's
/// fixed 2160/1440/1080/720/480 list, since not every video offers every
/// rung, and whatever audio extensions (m4a/webm/opus…) YouTube actually
/// serves rather than the handoff's illustrative M4A/MP3/Opus (YouTube
/// never serves MP3; transcoding to it isn't something this pass adds).
enum FormatSelection {

    /// One selectable resolution: its height and the best-ranked format
    /// available at that height (a video can offer several codecs per height).
    struct ResolutionOption: Identifiable {
        let height: Int
        let format: VideoFormat
        var id: Int { height }
        var label: String { "\(height)p" }
    }

    /// One selectable audio track: its extension and the best-ranked format
    /// with that extension.
    struct AudioOption: Identifiable {
        let ext: String
        let format: VideoFormat
        var id: String { ext }
        var label: String { ext.uppercased() }
    }

    /// Distinct resolutions actually offered, highest first, each mapped to
    /// its best (highest `qualityRank`, ties broken toward a broadly
    /// compatible codec, then toward reliable progress reporting) format.
    static func resolutionOptions(in formats: [VideoFormat]) -> [ResolutionOption] {
        let videoFormats = formats.filter { $0.hasVideo && $0.height != nil }
        let byHeight = Dictionary(grouping: videoFormats) { $0.height! }
        return byHeight
            .compactMap { height, formats in
                formats.max(by: byQualityThenCodecCompatibility).map { ResolutionOption(height: height, format: $0) }
            }
            .sorted { $0.height > $1.height }
    }

    /// Distinct audio extensions actually offered, best quality first, each
    /// mapped to its best format. Fewer than two means there's nothing to
    /// choose between — callers should hide the picker in that case rather
    /// than show a single, unselectable-feeling chip.
    static func audioOptions(in formats: [VideoFormat]) -> [AudioOption] {
        let audioFormats = formats.filter { $0.isAudioOnly }
        let byExt = Dictionary(grouping: audioFormats) { $0.ext }
        return byExt
            .compactMap { ext, formats in
                formats.max(by: byQualityThenReliability).map { AudioOption(ext: ext, format: $0) }
            }
            .sorted { $0.format.qualityRank > $1.format.qualityRank }
    }

    /// One audio language a video offers. Videos with dubbed audio list a
    /// separate audio-only format per language; `id` is the language code,
    /// or "und" for formats yt-dlp couldn't label.
    struct AudioLanguageOption: Identifiable, Hashable {
        let id: String
        /// True for the video's own (original/default) audio, as opposed to a dub.
        let isOriginal: Bool

        /// A descriptive-audio track: extra narration for blind users, which
        /// should never be what a video silently defaults to.
        var isDescriptive: Bool { id.lowercased().hasSuffix(LanguageCode.descriptiveSuffix) }

        var label: String {
            guard id != Self.unknownID else { return "Unknown" }
            let base = id.lowercased().hasSuffix(LanguageCode.descriptiveSuffix)
                ? String(id.dropLast(LanguageCode.descriptiveSuffix.count))
                : id
            let name = Locale.current.localizedString(forLanguageCode: base) ?? base
            var label = isDescriptive ? "\(name) (audio description)" : name
            if isOriginal { label += " (original)" }
            return label
        }

        static let unknownID = "und"
    }

    static func audioLanguageID(of format: VideoFormat) -> String {
        format.language.flatMap { $0.isEmpty ? nil : $0 } ?? AudioLanguageOption.unknownID
    }

    /// The audio languages offered, original first, then by name. Fewer than
    /// two means there's nothing to choose between — callers should hide the
    /// picker in that case.
    static func audioLanguageOptions(in formats: [VideoFormat]) -> [AudioLanguageOption] {
        let audioFormats = formats.filter { $0.isAudioOnly }
        let byLanguage = Dictionary(grouping: audioFormats, by: audioLanguageID(of:))
        let options = byLanguage.map { id, formats in
            AudioLanguageOption(id: id, isOriginal: formats.contains { $0.isOriginalAudio })
        }
        return options
            .map { (option: $0, label: $0.label) }
            .sorted {
                if $0.option.isOriginal != $1.option.isOriginal { return $0.option.isOriginal }
                return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
            .map(\.option)
    }

    /// The audio language to preselect: the video's own original track, so a
    /// download sounds like the video does by default and never silently
    /// comes out dubbed; failing that the user's language, then English,
    /// then whatever comes first. Descriptive-audio tracks are skipped
    /// unless they're all there is.
    static func defaultAudioLanguageID(
        in options: [AudioLanguageOption],
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String? {
        let candidates = options.filter { !$0.isDescriptive }
        let pool = candidates.isEmpty ? options : candidates
        if let original = pool.first(where: \.isOriginal) { return original.id }
        for preferred in preferredLanguages + ["en"] {
            let best = pool
                .compactMap { option in
                    LanguageCode.matchTier(code: option.id, preferred: preferred).map { (option, $0) }
                }
                .min { $0.1 < $1.1 }
            if let best { return best.0.id }
        }
        return pool.first?.id
    }

    /// `formats` narrowed to the audio-only formats in `languageID`; all of
    /// the audio-only formats when no language is chosen.
    static func audioFormats(_ formats: [VideoFormat], inLanguage languageID: String?) -> [VideoFormat] {
        let audioFormats = formats.filter { $0.isAudioOnly }
        guard let languageID else { return audioFormats }
        return audioFormats.filter { audioLanguageID(of: $0) == languageID }
    }

    /// Orders two video formats by quality first; when a resolution ladder
    /// has several formats tied on `qualityRank` (a common case: YouTube
    /// often offers the same resolution in H.264, VP9, and AV1), prefers
    /// the one with a broadly compatible codec, so the picker doesn't
    /// default to VP9/AV1 over an equally-good H.264 option just because
    /// yt-dlp happened to list it first. Only matters when there's an
    /// actual choice — a quality tier with no H.264 option still resolves
    /// to whatever *is* offered there.
    private static func byQualityThenCodecCompatibility(_ a: VideoFormat, _ b: VideoFormat) -> Bool {
        if a.qualityRank != b.qualityRank { return a.qualityRank < b.qualityRank }
        if a.isBroadlyCompatibleCodec != b.isBroadlyCompatibleCodec { return !a.isBroadlyCompatibleCodec }
        // Still tied: same preference the audio ladder uses.
        return !a.hasReliableProgress && b.hasReliableProgress
    }

    /// Orders two formats by quality first; when a video/audio ladder has
    /// several formats tied on `qualityRank` (a common case: the same
    /// resolution/bitrate offered over both plain HTTP and HLS), prefers
    /// the one with reliable progress reporting so the download UI doesn't
    /// show a jumpy size estimate for no quality benefit.
    private static func byQualityThenReliability(_ a: VideoFormat, _ b: VideoFormat) -> Bool {
        if a.qualityRank != b.qualityRank { return a.qualityRank < b.qualityRank }
        return !a.hasReliableProgress && b.hasReliableProgress
    }

    /// Best-effort combined download size for the currently selected
    /// tracks: sums each format's own reported size where yt-dlp provides
    /// one, and only falls back to a bitrate×duration estimate for a track
    /// that reports neither `filesize` nor `filesizeApprox`.
    static func estimatedSizeBytes(video: VideoFormat?, audio: VideoFormat?, durationSeconds: Double?) -> Int64? {
        let tracks = [video, audio].compactMap { $0 }
        guard !tracks.isEmpty else { return nil }

        var total: Int64 = 0
        var sawAnySize = false
        for track in tracks {
            if let size = track.filesize ?? track.filesizeApprox {
                total += size
                sawAnySize = true
            } else if let duration = durationSeconds, let bitrateKbps = track.tbr ?? track.abr {
                total += Int64(bitrateKbps * duration * 1000 / 8)
                sawAnySize = true
            }
        }
        return sawAnySize ? total : nil
    }
}
