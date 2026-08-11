//
//  ContentView.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import SwiftUI

/// The app's main window: paste a video URL, fetch its metadata, and download
/// it to the destination folder with live progress. Composes the redesigned
/// per-state views (README §3.2–3.8); this file owns state and wiring, not
/// layout — each state's actual UI lives in `Views/`.
struct ContentView: View {

    private enum Phase {
        case idle, fetching, ready, downloading, complete, error
    }

    @State private var urlString: String = ""
    /// nil means "don't download this track".
    @State private var selectedVideoFormatID: String?
    /// nil means "don't download this track".
    @State private var selectedAudioFormatID: String?
    @State private var selectedOutputContainer: OutputContainer = .mp4
    @State private var destinationFolder: URL = YtDlpModel.defaultDownloadsDirectory
    /// The filename without its extension; the real extension is appended by yt-dlp.
    @State private var filename: String = ""
    /// Latches true once the user edits `filename` directly; only "Reset to
    /// video title" clears it. Prevents a metadata/format change from
    /// clobbering a name the user chose on purpose.
    @State private var filenameIsCustom = false
    @State private var optionsExpanded = false
    @State private var audioOnly = false
    /// The video format to restore when "Audio only" is turned back off.
    @State private var lastVideoFormatID: String?

    @State private var showingComplete = false
    @State private var downloadStartedAt: Date?
    @State private var lastCompletedElapsed: Double?
    /// Drives the titlebar mark's one-shot completion pulse (see `MainWindowChrome`).
    @State private var markPulse = false

    @State private var model: YtDlpModel
    private let dependencyManager: DependencyManager

    /// Video-capable formats for the current video, in yt-dlp's own order.
    /// Cached rather than recomputed on every body evaluation — SwiftUI
    /// re-evaluates body many times a second while downloadProgress updates,
    /// and re-filtering the full formats list on every one of those ticks
    /// would be wasted work, since the list only actually changes once per fetch.
    @State private var videoFormats: [VideoFormat] = []
    @State private var audioFormats: [VideoFormat] = []

    /// Debounces auto-fetch so a pasted/dropped link fetches automatically
    /// (README §4) without spawning a yt-dlp process on every keystroke
    /// while a URL is still being typed out by hand.
    @State private var pendingFetchTask: Task<Void, Never>?

    init(dependencyManager: DependencyManager) {
        _model = State(wrappedValue: YtDlpModel(dependencyManager: dependencyManager))
        self.dependencyManager = dependencyManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            urlField
            phaseContent
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(width: 560)
        .background(Color.flytSurface)
        .toolbar {
            MainWindowTitlebar(pulse: markPulse)
        }
        .animation(.easeOut(duration: 0.2), value: optionsExpanded)
        .onChange(of: urlString) {
            resetFetchedState()
            scheduleAutoFetch()
        }
        .onChange(of: model.videoInfo) { _, info in
            guard let info else { return }
            videoFormats = Self.sortedFormats(info.formats) { $0.hasVideo }
            audioFormats = Self.sortedFormats(info.formats) { $0.isAudioOnly }
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
        .onChange(of: model.isDownloading) { wasDownloading, isDownloading in
            guard wasDownloading, !isDownloading else { return }
            defer { downloadStartedAt = nil }
            // A cancelled download also leaves errorMessage nil (see
            // YtDlpModel.download's cancellation branch), so that check
            // alone can't tell a genuine completion apart from a cancel.
            guard model.errorMessage == nil, !model.wasCancelled else { return }
            if let downloadStartedAt {
                lastCompletedElapsed = Date().timeIntervalSince(downloadStartedAt)
            }
            showingComplete = true
            pulseMark()
        }
    }

    // MARK: Phase

    private var phase: Phase {
        if showingComplete { return .complete }
        if model.errorMessage != nil { return .error }
        if model.isDownloading { return .downloading }
        if model.isLoading { return .fetching }
        if model.videoInfo != nil { return .ready }
        return .idle
    }

    @ViewBuilder
    private var urlField: some View {
        switch phase {
        case .idle:
            URLField(text: $urlString, tone: .neutral, trailing: urlString.isEmpty ? .hint : .none)
                .onSubmit(fetchNow)
        case .fetching:
            URLField(text: $urlString, tone: .focused, trailing: .fetching)
        case .ready, .complete:
            URLField(text: $urlString, tone: .focused, trailing: .none)
        case .downloading:
            // Disabled rather than just visually focused: editing the URL
            // mid-download used to blank the progress view without
            // actually stopping the download running underneath it.
            URLField(text: $urlString, tone: .focused, trailing: .none)
                .disabled(true)
                .opacity(0.6)
        case .error:
            URLField(text: $urlString, tone: .error, trailing: .none)
                .onSubmit(fetchNow)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .idle:
            IdleDropZone(onDropURL: handleIncomingURL)
            FooterPathRow(destinationFolder: destinationFolder, ytdlpVersion: dependencyManager.installedYtdlpVersion, onChange: chooseDestinationFolder)
                .frame(maxWidth: .infinity, alignment: .center)

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

                DownloadPrimaryButton(trailingText: estimatedSizeText, action: startDownload)
                FooterPathRow(destinationFolder: destinationFolder, ytdlpVersion: dependencyManager.installedYtdlpVersion, onChange: chooseDestinationFolder)
                    .frame(maxWidth: .infinity, alignment: .center)
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
                    onDownloadAnother: resetForNewDownload
                )
            }

        case .error:
            if let raw = model.errorMessage {
                ErrorCard(
                    error: FlytError(rawMessage: raw),
                    onTryAgain: retryFetch,
                    onPasteDifferentLink: resetForNewDownload
                )
            }
        }
    }

    // MARK: Derived selection state

    /// Filters and sorts `formats` best-quality-first.
    private static func sortedFormats(_ formats: [VideoFormat], where predicate: (VideoFormat) -> Bool) -> [VideoFormat] {
        formats.filter(predicate).sorted { $0.qualityRank > $1.qualityRank }
    }

    private var resolutionOptions: [FormatSelection.ResolutionOption] {
        FormatSelection.resolutionOptions(in: videoFormats)
    }

    private var audioOptions: [FormatSelection.AudioOption] {
        FormatSelection.audioOptions(in: audioFormats)
    }

    private var selectedVideoFormat: VideoFormat? {
        videoFormats.first { $0.id == selectedVideoFormatID }
    }

    private var selectedAudioFormat: VideoFormat? {
        audioFormats.first { $0.id == selectedAudioFormatID }
    }

    /// True when both a video and an audio track are selected, meaning
    /// yt-dlp will actually mux them — the only time the container choice matters.
    private var willMerge: Bool {
        selectedVideoFormatID != nil && selectedAudioFormatID != nil
    }

    /// "Video"/"Audio" while a two-stream (merged) download is fetching
    /// one of its tracks, so the progress bar's restart from 100% back to
    /// 0% between them reads as a new stream starting rather than a
    /// glitch. nil for a single-stream download, and during merging
    /// itself (which has its own dedicated row, not a percentage).
    private var downloadPhaseLabel: String? {
        guard willMerge else { return nil }
        switch model.downloadPhase {
        case .downloadingVideo: return "Video"
        case .downloadingAudio: return "Audio"
        case .idle, .merging: return nil
        }
    }

    /// A best-effort preview of the final file extension, shown next to the
    /// filename field. yt-dlp determines the real one at download time.
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

    /// Translates the simplified resolution-chip/audio-segment selections
    /// back to the specific `format_id`s `YtDlpModel.download` expects.
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

    /// Wraps `filename` so an edit made *through this binding* (i.e. by the
    /// user typing) latches `filenameIsCustom`, while programmatic updates
    /// elsewhere (new metadata, "Reset to video title") can still set
    /// `filename` directly without tripping the latch.
    private var filenameBinding: Binding<String> {
        Binding(
            get: { filename },
            set: { newValue in
                filename = newValue
                filenameIsCustom = true
            }
        )
    }

    /// True if `urlString` parses as an http(s) URL with a host — cheap
    /// client-side validation before handing it to yt-dlp, which otherwise
    /// only reports a malformed URL after a slow subprocess round-trip.
    private var isValidURL: Bool {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return false
        }
        return true
    }

    // MARK: Actions

    /// Clears the previously fetched video and its dependent selections, so
    /// stale state from one video can't be sent alongside a different URL.
    /// Also cancels an in-flight fetch, since it's for a URL the field no
    /// longer shows, and drops out of the complete/error screens back to
    /// the normal fetch flow — entering a new URL anywhere, including on
    /// the completed-download screen, should behave the same way: fetch
    /// the new video and let the user download it, not get stuck showing
    /// the previous one.
    private func resetFetchedState() {
        if model.isLoading { model.cancel() }
        model.videoInfo = nil
        model.errorMessage = nil
        showingComplete = false
        lastCompletedElapsed = nil
        selectedVideoFormatID = nil
        selectedAudioFormatID = nil
        lastVideoFormatID = nil
        filename = ""
        filenameIsCustom = false
        videoFormats = []
        audioFormats = []
        optionsExpanded = false
        audioOnly = false
    }

    private func resetFilenameToTitle() {
        filenameIsCustom = false
        if let title = model.videoInfo?.title {
            filename = FilenamePolicy.sanitize(title)
        }
    }

    /// Debounces ~500ms after the last edit before fetching, so a pasted or
    /// dropped link (a single field mutation) fetches automatically without
    /// spawning a yt-dlp process on every keystroke of manual typing.
    private func scheduleAutoFetch() {
        pendingFetchTask?.cancel()
        guard isValidURL else { return }
        let snapshot = urlString
        pendingFetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, snapshot == urlString else { return }
            fetchNow()
        }
    }

    private func fetchNow() {
        pendingFetchTask?.cancel()
        guard isValidURL, !model.isBusy else { return }
        model.fetchInfo(for: urlString)
    }

    private func retryFetch() {
        model.errorMessage = nil
        fetchNow()
    }

    private func handleIncomingURL(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        urlString = trimmed
    }

    private func resetForNewDownload() {
        showingComplete = false
        urlString = ""
    }

    /// Opens a native folder picker defaulted to `destinationFolder`.
    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = destinationFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            destinationFolder = url
        }
    }

    private func startDownload() {
        guard let info = model.videoInfo else { return }
        let base = filename.isEmpty ? FilenamePolicy.sanitize(info.title) : FilenamePolicy.sanitize(filename)
        let uniqueBase = FilenamePolicy.uniqueFilename(
            base: base.isEmpty ? "download" : base,
            in: destinationFolder
        )
        downloadStartedAt = Date()
        model.download(
            urlString: urlString,
            videoFormatId: selectedVideoFormatID,
            audioFormatId: selectedAudioFormatID,
            outputContainer: selectedOutputContainer,
            destinationFolder: destinationFolder,
            fileName: uniqueBase
        )
    }

    private func pulseMark() {
        withAnimation(.easeOut(duration: 0.16)) {
            markPulse = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.easeOut(duration: 0.16)) {
                markPulse = false
            }
        }
    }
}
