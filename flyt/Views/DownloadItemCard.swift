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
/// unchanged, just re-homed to a per-card `DownloadItemSettings` instead of the window's.
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

    @Bindable var settings: DownloadItemSettings

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
            settings.videoFormats = Self.sortedFormats(info.formats) { $0.hasVideo }
            settings.audioFormats = Self.sortedFormats(info.formats) { $0.isAudioOnly }
            settings.resolutionOptions = FormatSelection.resolutionOptions(in: settings.videoFormats)
            settings.audioOptions = FormatSelection.audioOptions(in: settings.audioFormats)
            settings.subtitleLanguageOptions = SubtitleSelection.languageOptions(
                subtitles: info.subtitles,
                automaticCaptions: info.automaticCaptions
            )
            if settings.selectedVideoFormatID == nil {
                settings.selectedVideoFormatID = settings.videoFormats.first?.id
            }
            if settings.selectedAudioFormatID == nil {
                settings.selectedAudioFormatID = settings.audioFormats.first?.id
            }
            // A code left over from a previous fetch may no longer be on
            // offer; an unmatched code would silently download no subtitles.
            if !settings.subtitleLanguageOptions.contains(where: { $0.code == settings.selectedSubtitleLanguageCode }) {
                settings.selectedSubtitleLanguageCode = SubtitleSelection.defaultLanguageCode(in: settings.subtitleLanguageOptions)
            }
            if settings.subtitleLanguageOptions.isEmpty {
                settings.subtitlesEnabled = false
            }
            if !settings.filenameIsCustom {
                settings.filename = FilenamePolicy.sanitize(info.title)
            }
        }
        .onChange(of: settings.audioOnly) { _, isOn in
            // embedSubtitles is left as-is while audioOnly is on: the toggle
            // is hidden (there's no video track to embed into) and
            // attemptStart() already gates on `&& !audioOnly`, so its
            // stored value only matters again once a video track returns.
            if isOn {
                settings.lastVideoFormatID = settings.selectedVideoFormatID
                settings.selectedVideoFormatID = nil
            } else {
                settings.selectedVideoFormatID = settings.lastVideoFormatID ?? settings.videoFormats.first?.id
            }
        }
        .onChange(of: settings.trimEnabled) { _, isOn in
            guard isOn, settings.timeRanges.isEmpty, let duration = model.videoInfo?.duration else { return }
            var range = VideoTimeRange(start: 0, end: 30)
            range.clamp(to: duration)
            settings.timeRanges = [range]
        }
        .onChange(of: coordinator.activeCount) {
            guard settings.isQueued else { return }
            attemptStart()
        }
        .onChange(of: model.isDownloading) { wasDownloading, isDownloading in
            guard wasDownloading, !isDownloading else { return }
            if settings.hasReservedSlot {
                coordinator.releaseSlot()
                settings.hasReservedSlot = false
            }
            defer { settings.downloadStartedAt = nil }
            // A cancelled download also leaves errorMessage nil, so that
            // check alone can't tell a genuine completion apart from a cancel.
            guard model.errorMessage == nil, !model.wasCancelled else { return }
            if let startedAt = settings.downloadStartedAt {
                settings.lastCompletedElapsed = Date().timeIntervalSince(startedAt)
            }
            settings.showingComplete = true
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
        if settings.showingComplete { return .complete }
        if model.errorMessage != nil { return .error }
        if model.isDownloading { return .downloading }
        if settings.isQueued { return .queued }
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

                if settings.optionsExpanded {
                    OptionsCard(
                        filename: filenameBinding,
                        fileExtension: previewExtension,
                        filenameIsCustom: settings.filenameIsCustom,
                        onResetFilename: resetFilenameToTitle,
                        resolutionOptions: settings.resolutionOptions,
                        selectedHeight: heightBinding,
                        selectedContainer: $settings.selectedOutputContainer,
                        audioOptions: settings.audioOptions,
                        selectedAudioExt: audioExtBinding,
                        audioOnly: $settings.audioOnly,
                        subtitleLanguageOptions: settings.subtitleLanguageOptions,
                        subtitlesEnabled: $settings.subtitlesEnabled,
                        selectedSubtitleLanguageCode: $settings.selectedSubtitleLanguageCode,
                        embedSubtitles: $settings.embedSubtitles,
                        subtitleFilename: subtitleFilenameBinding,
                        subtitleFilenameIsCustom: settings.subtitleFilenameIsCustom,
                        onResetSubtitleFilename: { settings.subtitleFilenameIsCustom = false },
                        duration: info.duration,
                        trimEnabled: $settings.trimEnabled,
                        timeRanges: $settings.timeRanges,
                        mergeSections: $settings.mergeSections,
                        onCollapse: { settings.optionsExpanded = false }
                    )
                } else {
                    FilenameField(
                        filename: filenameBinding,
                        fileExtension: previewExtension,
                        isCustom: settings.filenameIsCustom,
                        onReset: resetFilenameToTitle,
                        style: .main
                    )
                    OptionsSummaryRow(
                        segments: summarySegments,
                        estimatedSizeText: estimatedSizeText,
                        onTap: { settings.optionsExpanded = true }
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
                    containerLabel: willMerge ? settings.selectedOutputContainer.label : nil,
                    audioLabel: selectedAudioFormat?.ext,
                    destinationFolder: destinationFolder,
                    savedSizeBytes: estimatedSizeBytes,
                    elapsedSeconds: settings.lastCompletedElapsed,
                    noticeText: model.subtitleFailureNote,
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
        settings.videoFormats.first { $0.id == settings.selectedVideoFormatID }
    }

    private var selectedAudioFormat: VideoFormat? {
        settings.audioFormats.first { $0.id == settings.selectedAudioFormatID }
    }

    private var selectedSubtitleLanguage: SubtitleSelection.LanguageOption? {
        guard settings.subtitlesEnabled else { return nil }
        return settings.subtitleLanguageOptions.first { $0.code == settings.selectedSubtitleLanguageCode }
    }

    private var willMerge: Bool {
        settings.selectedVideoFormatID != nil && settings.selectedAudioFormatID != nil
    }

    /// "Video"/"Audio" while a two-stream (merged) download is fetching one
    /// of its tracks, or "Section N of M" while trimming — in both cases
    /// the progress bar's restart from 100% back to 0% needs a label or it
    /// reads as a glitch rather than a new stream/section starting.
    private var downloadPhaseLabel: String? {
        switch model.downloadPhase {
        case .downloadingVideo: return willMerge ? "Video" : nil
        case .downloadingAudio: return willMerge ? "Audio" : nil
        case .trimmingSection(let index, let total): return total > 1 ? "Section \(index) of \(total)" : "Trimming"
        case .idle, .merging: return nil
        }
    }

    private var previewExtension: String {
        if willMerge { return settings.selectedOutputContainer.rawValue }
        if let format = selectedVideoFormat { return format.ext }
        if let format = selectedAudioFormat { return format.ext }
        return settings.selectedOutputContainer.rawValue
    }

    private var resolutionSummaryLabel: String? {
        selectedVideoFormat?.height.map { "\($0)p" }
    }

    private var summarySegments: [String] {
        var segments: [String] = []
        if let resolutionSummaryLabel { segments.append(resolutionSummaryLabel) }
        if settings.selectedVideoFormatID != nil { segments.append(settings.selectedOutputContainer.label.uppercased()) }
        if let ext = selectedAudioFormat?.ext { segments.append(ext.uppercased()) }
        if let selectedSubtitleLanguage { segments.append("\(selectedSubtitleLanguage.code.uppercased()) CC") }
        if settings.trimEnabled, !settings.timeRanges.isEmpty {
            segments.append(settings.timeRanges.count > 1 ? "\(settings.timeRanges.count) CLIPS" : "TRIMMED")
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
        guard settings.trimEnabled, !settings.timeRanges.isEmpty,
              let fullDuration = model.videoInfo?.duration, fullDuration > 0 else {
            return fullEstimate
        }
        let trimmedDuration = settings.timeRanges.reduce(0) { $0 + max(0, $1.end - $1.start) }
        return Int64(Double(fullEstimate) * (trimmedDuration / fullDuration))
    }

    private var estimatedSizeText: String? {
        estimatedSizeBytes.map { "≈ \(FlytFormat.fileSize($0))" }
    }

    private var heightBinding: Binding<Int?> {
        Binding(
            get: { selectedVideoFormat?.height },
            set: { newHeight in
                guard let newHeight, let match = settings.resolutionOptions.first(where: { $0.height == newHeight }) else { return }
                settings.selectedVideoFormatID = match.format.id
            }
        )
    }

    private var audioExtBinding: Binding<String?> {
        Binding(
            get: { selectedAudioFormat?.ext },
            set: { newExt in
                guard let newExt, let match = settings.audioOptions.first(where: { $0.ext == newExt }) else { return }
                settings.selectedAudioFormatID = match.format.id
            }
        )
    }

    private var filenameBinding: Binding<String> {
        Binding(
            get: { settings.filename },
            set: { newValue in
                settings.filename = newValue
                settings.filenameIsCustom = true
            }
        )
    }

    /// Shows the video filename until the user edits it, so the two stay in
    /// step by default; typing latches `subtitleFilenameIsCustom`.
    private var subtitleFilenameBinding: Binding<String> {
        Binding(
            get: { settings.subtitleFilenameIsCustom ? settings.subtitleFilename : settings.filename },
            set: {
                settings.subtitleFilename = $0
                settings.subtitleFilenameIsCustom = true
            }
        )
    }

    // MARK: Actions

    private func resetFilenameToTitle() {
        settings.filenameIsCustom = false
        if let title = model.videoInfo?.title {
            settings.filename = FilenamePolicy.sanitize(title)
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
        if settings.hasReservedSlot {
            coordinator.releaseSlot()
            settings.hasReservedSlot = false
        }
        onRemove()
    }

    private func requestDownload() {
        guard !settings.isQueued, !model.isDownloading else { return }
        attemptStart()
    }

    /// Starts the download immediately if a slot is free; otherwise marks
    /// this card as queued so the `coordinator.activeCount` observer above
    /// retries once one frees up.
    private func attemptStart() {
        // Checked before a slot is claimed: returning early afterwards
        // would hold the slot for a download that never runs.
        guard let info = model.videoInfo else {
            settings.isQueued = false
            return
        }
        guard coordinator.tryReserveSlot() else {
            settings.isQueued = true
            return
        }
        settings.isQueued = false
        settings.hasReservedSlot = true
        let base = settings.filename.isEmpty ? FilenamePolicy.sanitize(info.title) : FilenamePolicy.sanitize(settings.filename)
        let uniqueBase = FilenamePolicy.uniqueFilename(
            base: base.isEmpty ? "download" : base,
            in: destinationFolder,
            sectioned: settings.trimEnabled && settings.timeRanges.count > 1
        )
        let sidecarBase = FilenamePolicy.sanitize(settings.subtitleFilenameIsCustom ? settings.subtitleFilename : "")
        let uniqueSubtitleBase = sidecarBase.isEmpty
            ? ""
            : FilenamePolicy.uniqueFilename(base: sidecarBase, in: destinationFolder)
        settings.downloadStartedAt = Date()
        let started = model.download(
            urlString: originalURLString,
            videoFormatId: settings.selectedVideoFormatID,
            audioFormatId: settings.selectedAudioFormatID,
            outputContainer: settings.selectedOutputContainer,
            destinationFolder: destinationFolder,
            fileName: uniqueBase,
            subtitleLanguage: selectedSubtitleLanguage,
            embedSubtitles: settings.embedSubtitles && !settings.audioOnly,
            subtitleFileName: uniqueSubtitleBase,
            timeRanges: settings.trimEnabled ? settings.timeRanges : [],
            mergeSections: settings.mergeSections
        )
        // No download means isDownloading never flips, so the observer
        // that normally releases the slot would never fire.
        if !started {
            coordinator.releaseSlot()
            settings.hasReservedSlot = false
            settings.downloadStartedAt = nil
        }
    }
}
