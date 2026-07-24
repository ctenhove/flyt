//
//  ContentView.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import SwiftUI

/// The app's main window: paste a video URL, fetch its metadata, and download
/// it to the Downloads folder with live progress.
struct ContentView: View {
    
    @State private var urlString: String = ""
    /// nil means "don't download this track".
    @State private var selectedVideoFormatID: String?
    /// nil means "don't download this track".
    @State private var selectedAudioFormatID: String?
    @State private var selectedOutputContainer: OutputContainer = .mp4
    @State private var destinationFolder: URL = YtDlpModel.defaultDownloadsDirectory
    /// The file name without its extension; the real extension is appended by yt-dlp.
    @State private var fileName: String = ""

    @State private var model: YtDlpModel

    init(dependencyManager: DependencyManager) {
        _model = State(wrappedValue: YtDlpModel(dependencyManager: dependencyManager))
    }

    /// Video-capable formats, best quality first.
    private var videoFormats: [VideoFormat] {
        (model.videoInfo?.formats ?? [])
            .filter { $0.hasVideo }
            .sorted { $0.qualityRank > $1.qualityRank }
    }

    /// Audio-only formats, best quality first.
    private var audioFormats: [VideoFormat] {
        (model.videoInfo?.formats ?? [])
            .filter { $0.isAudioOnly }
            .sorted { $0.qualityRank > $1.qualityRank }
    }

    /// True when both a video and an audio track are selected, meaning
    /// yt-dlp will actually mux them — the only time the container choice matters.
    private var willMerge: Bool {
        selectedVideoFormatID != nil && selectedAudioFormatID != nil
    }

    /// A best-effort preview of the final file extension, shown next to the
    /// file name field. yt-dlp determines the real one at download time.
    private var previewExtension: String {
        if willMerge {
            return selectedOutputContainer.rawValue
        }
        if let format = videoFormats.first(where: { $0.id == selectedVideoFormatID }) {
            return format.ext
        }
        if let format = audioFormats.first(where: { $0.id == selectedAudioFormatID }) {
            return format.ext
        }
        return ""
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

    /// Clears the previously fetched video and its dependent selections, so
    /// stale state from one video can't be sent alongside a different URL.
    private func resetFetchedState() {
        model.videoInfo = nil
        selectedVideoFormatID = nil
        selectedAudioFormatID = nil
        fileName = ""
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("yt-dlp Downloader")
                .font(.largeTitle)
                .bold()

            HStack {
                TextField("Paste video URL", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: urlString) {
                        // Editing the URL invalidates any previously fetched
                        // video — otherwise Download could send format IDs
                        // from the old video against the new URL.
                        resetFetchedState()
                    }

                Button("Fetch Info") {
                    resetFetchedState()
                    model.fetchInfo(for: urlString)
                }
                .disabled(model.isBusy || !isValidURL)
            }

            if !urlString.isEmpty && !isValidURL {
                Text("Enter a valid http(s) URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let info = model.videoInfo {
                Text(info.title)
                    .font(.headline)
                    .onChange(of: info.formats, initial: true) {
                        if selectedVideoFormatID == nil {
                            selectedVideoFormatID = videoFormats.first?.id
                        }
                        if selectedAudioFormatID == nil {
                            selectedAudioFormatID = audioFormats.first?.id
                        }
                        if fileName.isEmpty {
                            fileName = info.title
                        }
                    }

                if !videoFormats.isEmpty {
                    Picker("Video", selection: $selectedVideoFormatID) {
                        Text("None").tag(nil as String?)
                        ForEach(videoFormats) { format in
                            Text(format.label).tag(format.id as String?)
                        }
                    }
                }

                if !audioFormats.isEmpty {
                    Picker("Audio", selection: $selectedAudioFormatID) {
                        Text("None").tag(nil as String?)
                        ForEach(audioFormats) { format in
                            Text(format.label).tag(format.id as String?)
                        }
                    }
                }

                if willMerge {
                    Picker("Output", selection: $selectedOutputContainer) {
                        ForEach(OutputContainer.allCases) { container in
                            Text(container.label).tag(container)
                        }
                    }
                }

                HStack {
                    TextField("File name", text: $fileName)
                        .textFieldStyle(.roundedBorder)
                    if !previewExtension.isEmpty {
                        Text(".\(previewExtension)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.videoInfo != nil {
                HStack {
                    Text(destinationFolder.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose Folder…") {
                        chooseDestinationFolder()
                    }

                    Spacer()

                    Button("Download") {
                        model.download(
                            urlString: urlString,
                            videoFormatId: selectedVideoFormatID,
                            audioFormatId: selectedAudioFormatID,
                            outputContainer: selectedOutputContainer,
                            destinationFolder: destinationFolder,
                            fileName: fileName
                        )
                    }
                    .disabled(model.isBusy || !isValidURL || model.videoInfo == nil)
                }
            }

            if model.isBusy {
                Button("Cancel") {
                    model.cancel()
                }
            }

            if model.isLoading {
                ProgressView()
            }

            if model.isDownloading {
                Text(model.downloadPhase.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.downloadPhase == .merging {
                    // Merging reports no percentage, so fall back to a spinner.
                    ProgressView()
                } else {
                    ProgressView(value: model.downloadProgress, total: 1.0)
                    Text("\(Int(model.downloadProgress * 100))%")
                        .font(.caption)
                }
            }

            if let file = model.lastDownloadedFile, !model.isDownloading {
                HStack {
                    Text("Saved: \(file.lastPathComponent)")
                        .font(.caption)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([file])
                    }
                }
            }

            if let error = model.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
        .frame(width: 480, height: 420)
    }
}
