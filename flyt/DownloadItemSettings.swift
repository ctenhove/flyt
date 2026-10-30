//
//  DownloadItemSettings.swift
//  flyt
//

import Observation

/// Everything a `DownloadItemCard` has configured or derived for its video,
/// kept in a reference object owned by the list item instead of in the
/// card's own `@State`. SwiftUI throws away a view's `@State` whenever the
/// view is rebuilt from scratch — which happens to every existing card the
/// moment the list around them changes shape (for instance when a second
/// card turns it into a scroll view). Nothing would then refill the
/// formats, filename and options, because `model.videoInfo` hasn't changed
/// and so never fires the `onChange` that populates them. State held here
/// survives that rebuild.
@Observable
final class DownloadItemSettings {
    var selectedVideoFormatID: String?
    var selectedAudioFormatID: String?
    var selectedOutputContainer: OutputContainer = .mp4
    var filename: String = ""
    var filenameIsCustom = false
    var optionsExpanded = false
    var audioOnly = false
    var lastVideoFormatID: String?
    var subtitlesEnabled = false
    var selectedSubtitleLanguageCode: String?
    /// Mux subtitles into the video file instead of writing a sidecar file.
    /// Defaults on: embedding is what most people expect from "download
    /// subtitles" — a loose .srt/.vtt file alongside the video is the
    /// opt-out, not the default.
    var embedSubtitles = true
    /// Name for the sidecar subtitle file (no extension). Follows the video
    /// filename until the user types their own.
    var subtitleFilename = ""
    var subtitleFilenameIsCustom = false
    var trimEnabled = false
    var timeRanges: [VideoTimeRange] = []
    /// Only meaningful with more than one range: concatenate them into a
    /// single output file instead of one file per range.
    var mergeSections = false

    var videoFormats: [VideoFormat] = []
    var audioFormats: [VideoFormat] = []
    var resolutionOptions: [FormatSelection.ResolutionOption] = []
    var audioOptions: [FormatSelection.AudioOption] = []
    var subtitleLanguageOptions: [SubtitleSelection.LanguageOption] = []

    var showingComplete = false
    var downloadStartedAt: Date?
    var lastCompletedElapsed: Double?

    /// True while waiting for `coordinator` to free a slot rather than
    /// actually downloading yet.
    var isQueued = false
    /// Whether this card currently holds a slot it must release exactly
    /// once — guards against double-releasing if `dismiss()` and the
    /// natural completion handler could otherwise both try to.
    var hasReservedSlot = false
}
