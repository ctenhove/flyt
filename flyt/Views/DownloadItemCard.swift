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

    @State private var videoFormats: [VideoFormat] = []
    @State private var audioFormats: [VideoFormat] = []
    @State private var resolutionOptions: [FormatSelection.ResolutionOption] = []
    @State private var audioOptions: [FormatSelection.AudioOption] = []

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
            if selectedVideoFormatID == nil {
                selectedVideoFormatID = videoFormats.first?.id
            }
            if selectedAudioFormatID == nil {
                selectedAudioFormatID = audioFormats.first?.id
            }
            if !filenameIsCustom {
                filename = FilenamePolicy.sanitize(info.title)
            }
        }
        .onChange(of: audioOnly) { _, isOn in
            if isOn {
                lastVideoFormatID = selectedVideoFormatID
                selectedVideoFormatID = nil
            } else {
                selectedVideoFormatID = lastVideoFormatID ?? videoFormats.first?.id
            }
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
            if let file = model.lastDownloadedFile, let info = model.videoInfo {
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
            if let file = model.lastDownloadedFile {
                CompleteCard(
                    savedFileURL: file,
                    thumbnailURLString: model.videoInfo?.thumbnail,
                    resolutionLabel: resolutionSummaryLabel,
                    containerLabel: willMerge ? selectedOutputContainer.label : nil,
                    audioLabel: selectedAudioFormat?.ext,
                    destinationFolder: destinationFolder,
                    savedSizeBytes: estimatedSizeBytes,
                    elapsedSeconds: lastCompletedElapsed,
                    onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([file]) },
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

    private static func sortedFormats(_ formats: [VideoFormat], where predicate: (VideoFormat) -> Bool) -> [VideoFormat] {
        formats.filter(predicate).sorted { $0.qualityRank > $1.qualityRank }
    }

    private var selectedVideoFormat: VideoFormat? {
        videoFormats.first { $0.id == selectedVideoFormatID }
    }

    private var selectedAudioFormat: VideoFormat? {
        audioFormats.first { $0.id == selectedAudioFormatID }
    }

    private var willMerge: Bool {
        selectedVideoFormatID != nil && selectedAudioFormatID != nil
    }

    private var downloadPhaseLabel: String? {
        guard willMerge else { return nil }
        switch model.downloadPhase {
        case .downloadingVideo: return "Video"
        case .downloadingAudio: return "Audio"
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
        return segments
    }

    private var estimatedSizeBytes: Int64? {
        FormatSelection.estimatedSizeBytes(
            video: selectedVideoFormat,
            audio: selectedAudioFormat,
            durationSeconds: model.videoInfo?.duration
        )
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
        guard coordinator.tryReserveSlot() else {
            isQueued = true
            return
        }
        isQueued = false
        hasReservedSlot = true
        guard let info = model.videoInfo else { return }
        let base = filename.isEmpty ? FilenamePolicy.sanitize(info.title) : FilenamePolicy.sanitize(filename)
        let uniqueBase = FilenamePolicy.uniqueFilename(
            base: base.isEmpty ? "download" : base,
            in: destinationFolder
        )
        downloadStartedAt = Date()
        model.download(
            urlString: originalURLString,
            videoFormatId: selectedVideoFormatID,
            audioFormatId: selectedAudioFormatID,
            outputContainer: selectedOutputContainer,
            destinationFolder: destinationFolder,
            fileName: uniqueBase
        )
    }
}
