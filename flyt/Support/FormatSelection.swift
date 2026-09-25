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
    /// its best (highest `qualityRank`, ties broken toward reliable
    /// progress reporting) format.
    static func resolutionOptions(in formats: [VideoFormat]) -> [ResolutionOption] {
        let videoFormats = formats.filter { $0.hasVideo && $0.height != nil }
        let byHeight = Dictionary(grouping: videoFormats) { $0.height! }
        return byHeight
            .compactMap { height, formats in
                formats.max(by: byQualityThenReliability).map { ResolutionOption(height: height, format: $0) }
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
