//
//  DownloadItemCard.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-09-28.
//

import SwiftUI

/// One video's entire fetch → configure → download → complete/error
/// lifecycle, independent of any other card the window is showing at the
/// same time. This is almost exactly what the pre-multi-download
/// `ContentView` did for its single video — that logic (format selection,
/// filename handling, the phase state machine) moves here essentially
/// unchanged, just re-homed to a per-card `@State` instead of the window's.
struct DownloadItemCard: View {
    let originalURLString: String
    var model: YtDlpModel
    /// Snapshot of the destination in effect when this item was created —
    /// intentionally not live, so changing the app-wide default later
    /// doesn't retroactively move where an already-in-flight download saves to.
    let destinationFolder: URL
    var coordinator: DownloadCoordinator
    var historyStore: DownloadHistoryStore
    var onRemove: () -> Void
    var onComplete: () -> Void

    private enum ItemPhase {
        case fetching, ready, queued, downloading, complete, error
    }

    @State private var selectedVideoFormatID: String?
    @State private var selectedAudioFormatID: String?
    @State private var selectedOutputContainer: OutputContainer = .mp4
    @State private var filename: String = ""
    @State private var filenameIsCustom = false
    @State private var optionsExpanded = false
    @State private var audioOnly = false
    @State private var lastVideoFormatID: String?
    @State private var subtitlesEnabled = false
    @State private var selectedSubtitleLanguageCode: String?
    /// Mux subtitles into the video file instead of writing a sidecar file.
    /// Defaults on: embedding is what most people expect from "download
    /// subtitles" — a loose .srt/.vtt file alongside the video is the
    /// opt-out, not the default.
    @State private var embedSubtitles = true
    /// Name for the sidecar subtitle file (no extension). Follows the video
    /// filename until the user types their own.
    @State private var subtitleFilename = ""
    @State private var subtitleFilenameIsCustom = false
    @State private var trimEnabled = false
    @State private var timeRanges: [VideoTimeRange] = []
    /// Only meaningful with more than one range: concatenate them into a
    /// single output file instead of one file per range.
    @State private var mergeSections = false

    @State private var videoFormats: [VideoFormat] = []
    @State private var audioFormats: [VideoFormat] = []
    @State private var resolutionOptions: [FormatSelection.ResolutionOption] = []
    @State private var audioOptions: [FormatSelection.AudioOption] = []
    @State private var subtitleLanguageOptions: [SubtitleSelection.LanguageOption] = []

    @State private var showingComplete = false
    @State private var downloadStartedAt: Date?
    @State private var lastCompletedElapsed: Double?

    /// True while waiting for `coordinator` to free a slot rather than
    /// actually downloading yet.
    @State private var isQueued = false
    /// Whether this card currently holds a slot it must release exactly
    /// once — guards against double-releasing if `dismiss()` and the
    /// natural completion handler could otherwise both try to.
    @State private var hasReservedSlot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        .padding(14)
        .background(Color.flytField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.flytDivider)
        )
        .onAppear {
            guard model.videoInfo == nil, !model.isLoading, model.errorMessage == nil else { return }
            model.fetchInfo(for: originalURLString)
        }
        .onChange(of: model.videoInfo) { _, info in
            guard let info else { return }
            videoFormats = Self.sortedFormats(info.formats) { $0.hasVideo }
            audioFormats = Self.sortedFormats(info.formats) { $0.isAudioOnly }
            resolutionOptions = FormatSelection.resolutionOptions(in: videoFormats)
            audioOptions = FormatSelection.audioOptions(in: audioFormats)
            subtitleLanguageOptions = SubtitleSelection.languageOptions(
                subtitles: info.subtitles,
                automaticCaptions: info.automaticCaptions
            )
            if selectedVideoFormatID == nil {
                selectedVideoFormatID = videoFormats.first?.id
            }
            if selectedAudioFormatID == nil {
                selectedAudioFormatID = audioFormats.first?.id
            }
            // A code left over from a previous fetch may no longer be on
            // offer; an unmatched code would silently download no subtitles.
            if !subtitleLanguageOptions.contains(where: { $0.code == selectedSubtitleLanguageCode }) {
                selectedSubtitleLanguageCode = subtitleLanguageOptions.first?.code
            }
            if subtitleLanguageOptions.isEmpty {
                subtitlesEnabled = false
            }
            if !filenameIsCustom {
                filename = FilenamePolicy.sanitize(info.title)
            }
        }
        .onChange(of: audioOnly) { _, isOn in
            // embedSubtitles is left as-is while audioOnly is on: the toggle
            // is hidden (there's no video track to embed into) and
            // attemptStart() already gates on `&& !audioOnly`, so its
            // stored value only matters again once a video track returns.
            if isOn {
                lastVideoFormatID = selectedVideoFormatID
                selectedVideoFormatID = nil
            } else {
                selectedVideoFormatID = lastVideoFormatID ?? videoFormats.first?.id
            }
        }
        .onChange(of: trimEnabled) { _, isOn in
            guard isOn, timeRanges.isEmpty, let duration = model.videoInfo?.duration else { return }
            var range = VideoTimeRange(start: 0, end: 30)
            range.clamp(to: duration)
            timeRanges = [range]
        }
        .onChange(of: coordinator.activeCount) {
            guard isQueued else { return }
            attemptStart()
        }
        .onChange(of: model.isDownloading) { wasDownloading, isDownloading in
            guard wasDownloading, !isDownloading else { return }
            if hasReservedSlot {
                coordinator.releaseSlot()
                hasReservedSlot = false
            }
            defer { downloadStartedAt = nil }
            // A cancelled download also leaves errorMessage nil, so that
            // check alone can't tell a genuine completion apart from a cancel.
            guard model.errorMessage == nil, !model.wasCancelled else { return }
            if let downloadStartedAt {
                lastCompletedElapsed = Date().timeIntervalSince(downloadStartedAt)
            }
            showingComplete = true
            if let file = model.downloadedFiles.first ?? model.lastDownloadedFile, let info = model.videoInfo {
                historyStore.record(DownloadHistoryEntry(
                    urlString: originalURLString,
                    title: info.title,
                    fileName: file.lastPathComponent,
                    thumbnailURLString: info.thumbnail
                ))
            }
            onComplete()
        }
    }

    // MARK: Phase

    private var phase: ItemPhase {
        if showingComplete { return .complete }
        if model.errorMessage != nil { return .error }
        if model.isDownloading { return .downloading }
        if isQueued { return .queued }
        if model.videoInfo != nil { return .ready }
        return .fetching
    }

    /// A small dismiss control in every phase, not just complete/error
    /// (which already have their own "Download another"/"Paste a different
    /// link" actions that do the same thing) — otherwise there'd be no way
    /// to drop a card while it's still fetching, ready, queued, or downloading.
    private var header: some View {
        HStack {
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.flytFaintText)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .fetching:
            FetchingSkeleton()

        case .ready:
            if let info = model.videoInfo {
                VideoSummaryCard(info: info)

                if optionsExpanded {
                    OptionsCard(
                        filename: filenameBinding,
                        fileExtension: previewExtension,
                        filenameIsCustom: filenameIsCustom,
                        onResetFilename: resetFilenameToTitle,
                        resolutionOptions: resolutionOptions,
                        selectedHeight: heightBinding,
                        selectedContainer: $selectedOutputContainer,
                        audioOptions: audioOptions,
                        selectedAudioExt: audioExtBinding,
                        audioOnly: $audioOnly,
                        subtitleLanguageOptions: subtitleLanguageOptions,
                        subtitlesEnabled: $subtitlesEnabled,
                        selectedSubtitleLanguageCode: $selectedSubtitleLanguageCode,
                        embedSubtitles: $embedSubtitles,
                        subtitleFilename: subtitleFilenameBinding,
                        subtitleFilenameIsCustom: subtitleFilenameIsCustom,
                        onResetSubtitleFilename: { subtitleFilenameIsCustom = false },
                        duration: info.duration,
                        trimEnabled: $trimEnabled,
                        timeRanges: $timeRanges,
                        mergeSections: $mergeSections,
                        onCollapse: { optionsExpanded = false }
                    )
                } else {
                    FilenameField(
                        filename: filenameBinding,
                        fileExtension: previewExtension,
                        isCustom: filenameIsCustom,
                        onReset: resetFilenameToTitle,
                        style: .main
                    )
                    OptionsSummaryRow(
                        segments: summarySegments,
                        estimatedSizeText: estimatedSizeText,
                        onTap: { optionsExpanded = true }
                    )
                }

                DownloadPrimaryButton(trailingText: estimatedSizeText, action: requestDownload)
            }

        case .queued:
            if let info = model.videoInfo {
                VideoSummaryCard(info: info)
                queuedRow
            }

        case .downloading:
            if let info = model.videoInfo {
                DownloadingProgress(
                    info: info,
                    phase: model.downloadPhase,
                    progress: model.downloadProgress,
                    downloadedSizeText: model.downloadedSizeText,
                    totalSizeText: model.totalSizeText,
                    speedText: model.speedText,
                    etaText: model.etaText,
                    phaseLabel: downloadPhaseLabel,
                    onCancel: model.cancel
                )
            }

        case .complete:
            if !model.downloadedFiles.isEmpty {
                CompleteCard(
                    savedFiles: model.downloadedFiles,
                    thumbnailURLString: model.videoInfo?.thumbnail,
                    resolutionLabel: resolutionSummaryLabel,
                    containerLabel: willMerge ? selectedOutputContainer.label : nil,
                    audioLabel: selectedAudioFormat?.ext,
                    destinationFolder: destinationFolder,
                    savedSizeBytes: estimatedSizeBytes,
                    elapsedSeconds: lastCompletedElapsed,
                    onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting(model.downloadedFiles) },
                    onDownloadAnother: dismiss
                )
            }

        case .error:
            if let raw = model.errorMessage {
                ErrorCard(
                    error: FlytError(rawMessage: raw),
                    onTryAgain: retryFetch,
                    onPasteDifferentLink: dismiss
                )
            }
        }
    }

    private var queuedRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Waiting for another download to finish…")
                .flytStyle(.micro)
        }
    }

    // MARK: Derived selection state

    /// Filters and sorts `formats` best-quality-first. When two formats tie
    /// on quality (a common case: YouTube often offers the same resolution
    /// in H.264, VP9, and AV1), prefers H.264 — the codec reliably playable
    /// in QuickTime once muxed into MP4; VP9/AV1 can produce a file
    /// QuickTime opens but won't show any video from. Still tied after that
    /// (say, the same stream over plain HTTP and HLS), prefers reliable
    /// progress reporting — see `VideoFormat.hasReliableProgress` — so the
    /// download UI doesn't show a jumpy size estimate for no quality
    /// benefit. This is what
    /// `selectedVideoFormatID`/`selectedAudioFormatID` default to
    /// (`.first` on the result) before the user ever opens the options
    /// card, so it's the tie-break that actually matters most.
    private static func sortedFormats(_ formats: [VideoFormat], where predicate: (VideoFormat) -> Bool) -> [VideoFormat] {
        formats.filter(predicate).sorted {
            if $0.qualityRank != $1.qualityRank { return $0.qualityRank > $1.qualityRank }
            if $0.isBroadlyCompatibleCodec != $1.isBroadlyCompatibleCodec { return $0.isBroadlyCompatibleCodec }
            return $0.hasReliableProgress && !$1.hasReliableProgress
        }
    }

    private var selectedVideoFormat: VideoFormat? {
        videoFormats.first { $0.id == selectedVideoFormatID }
    }

    private var selectedAudioFormat: VideoFormat? {
        audioFormats.first { $0.id == selectedAudioFormatID }
    }

    private var selectedSubtitleLanguage: SubtitleSelection.LanguageOption? {
        guard subtitlesEnabled else { return nil }
        return subtitleLanguageOptions.first { $0.code == selectedSubtitleLanguageCode }
    }

    private var willMerge: Bool {
        selectedVideoFormatID != nil && selectedAudioFormatID != nil
    }

    /// "Video"/"Audio" while a two-stream (merged) download is fetching one
    /// of its tracks, or "Section N of M" while trimming — in both cases
    /// the progress bar's restart from 100% back to 0% needs a label or it
    /// reads as a glitch rather than a new stream/section starting.
    private var downloadPhaseLabel: String? {
        switch model.downloadPhase {
        case .downloadingVideo: return willMerge ? "Video" : nil
        case .downloadingAudio: return willMerge ? "Audio" : nil
        case .trimmingSection(let index, let total): return total > 1 ? "Section \(index) of \(total)" : nil
        case .idle, .merging: return nil
        }
    }

    private var previewExtension: String {
        if willMerge { return selectedOutputContainer.rawValue }
        if let format = selectedVideoFormat { return format.ext }
        if let format = selectedAudioFormat { return format.ext }
        return selectedOutputContainer.rawValue
    }

    private var resolutionSummaryLabel: String? {
        selectedVideoFormat?.height.map { "\($0)p" }
    }

    private var summarySegments: [String] {
        var segments: [String] = []
        if let resolutionSummaryLabel { segments.append(resolutionSummaryLabel) }
        if selectedVideoFormatID != nil { segments.append(selectedOutputContainer.label.uppercased()) }
        if let ext = selectedAudioFormat?.ext { segments.append(ext.uppercased()) }
        if let selectedSubtitleLanguage { segments.append("\(selectedSubtitleLanguage.code.uppercased()) CC") }
        if trimEnabled, !timeRanges.isEmpty {
            segments.append(timeRanges.count > 1 ? "\(timeRanges.count) CLIPS" : "TRIMMED")
        }
        return segments
    }

    /// The full-video estimate scaled down to the trimmed portion when
    /// trimming is active: a known `filesize`/`filesizeApprox` is for the
    /// *whole* stream, so without this a 10-second clip out of an hour-long
    /// video would still show the full video's size.
    private var estimatedSizeBytes: Int64? {
        guard let fullEstimate = FormatSelection.estimatedSizeBytes(
            video: selectedVideoFormat,
            audio: selectedAudioFormat,
            durationSeconds: model.videoInfo?.duration
        ) else { return nil }
        guard trimEnabled, !timeRanges.isEmpty,
              let fullDuration = model.videoInfo?.duration, fullDuration > 0 else {
            return fullEstimate
        }
        let trimmedDuration = timeRanges.reduce(0) { $0 + max(0, $1.end - $1.start) }
        return Int64(Double(fullEstimate) * (trimmedDuration / fullDuration))
    }

    private var estimatedSizeText: String? {
        estimatedSizeBytes.map { "≈ \(FlytFormat.fileSize($0))" }
    }

    private var heightBinding: Binding<Int?> {
        Binding(
            get: { selectedVideoFormat?.height },
            set: { newHeight in
                guard let newHeight, let match = resolutionOptions.first(where: { $0.height == newHeight }) else { return }
                selectedVideoFormatID = match.format.id
            }
        )
    }

    private var audioExtBinding: Binding<String?> {
        Binding(
            get: { selectedAudioFormat?.ext },
            set: { newExt in
                guard let newExt, let match = audioOptions.first(where: { $0.ext == newExt }) else { return }
                selectedAudioFormatID = match.format.id
            }
        )
    }

    private var filenameBinding: Binding<String> {
        Binding(
            get: { filename },
            set: { newValue in
                filename = newValue
                filenameIsCustom = true
            }
        )
    }

    /// Shows the video filename until the user edits it, so the two stay in
    /// step by default; typing latches `subtitleFilenameIsCustom`.
    private var subtitleFilenameBinding: Binding<String> {
        Binding(
            get: { subtitleFilenameIsCustom ? subtitleFilename : filename },
            set: {
                subtitleFilename = $0
                subtitleFilenameIsCustom = true
            }
        )
    }

    // MARK: Actions

    private func resetFilenameToTitle() {
        filenameIsCustom = false
        if let title = model.videoInfo?.title {
            filename = FilenamePolicy.sanitize(title)
        }
    }

    private func retryFetch() {
        model.errorMessage = nil
        model.fetchInfo(for: originalURLString)
    }

    /// Cancels anything in flight, releases a held download slot, and asks
    /// the parent to drop this card from the list.
    private func dismiss() {
        model.cancel()
        if hasReservedSlot {
            coordinator.releaseSlot()
            hasReservedSlot = false
        }
        onRemove()
    }

    private func requestDownload() {
        guard !isQueued, !model.isDownloading else { return }
        attemptStart()
    }

    /// Starts the download immediately if a slot is free; otherwise marks
    /// this card as queued so the `coordinator.activeCount` observer above
    /// retries once one frees up.
    private func attemptStart() {
        // Checked before a slot is claimed: returning early afterwards
        // would hold the slot for a download that never runs.
        guard let info = model.videoInfo else {
            isQueued = false
            return
        }
        guard coordinator.tryReserveSlot() else {
            isQueued = true
            return
        }
        isQueued = false
        hasReservedSlot = true
        let base = filename.isEmpty ? FilenamePolicy.sanitize(info.title) : FilenamePolicy.sanitize(filename)
        let uniqueBase = FilenamePolicy.uniqueFilename(
            base: base.isEmpty ? "download" : base,
            in: destinationFolder,
            sectioned: trimEnabled && timeRanges.count > 1
        )
        let sidecarBase = FilenamePolicy.sanitize(subtitleFilenameIsCustom ? subtitleFilename : "")
        let uniqueSubtitleBase = sidecarBase.isEmpty
            ? ""
            : FilenamePolicy.uniqueFilename(base: sidecarBase, in: destinationFolder)
        downloadStartedAt = Date()
        let started = model.download(
            urlString: originalURLString,
            videoFormatId: selectedVideoFormatID,
            audioFormatId: selectedAudioFormatID,
            outputContainer: selectedOutputContainer,
            destinationFolder: destinationFolder,
            fileName: uniqueBase,
            subtitleLanguage: selectedSubtitleLanguage,
            embedSubtitles: embedSubtitles && !audioOnly,
            subtitleFileName: uniqueSubtitleBase,
            timeRanges: trimEnabled ? timeRanges : [],
            mergeSections: mergeSections
        )
        // No download means isDownloading never flips, so the observer
        // that normally releases the slot would never fire.
        if !started {
            coordinator.releaseSlot()
            hasReservedSlot = false
            downloadStartedAt = nil
        }
    }
}
