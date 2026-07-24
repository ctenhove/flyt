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
    
    /// Sentinel selection meaning "don't download this track".
    private static let skipOption = "none"

    @State private var urlString: String = ""
    @State private var selectedVideoFormatID: String = ContentView.skipOption
    @State private var selectedAudioFormatID: String = ContentView.skipOption
    @State private var selectedOutputContainer: OutputContainer = .mp4
    @State private var destinationFolder: URL = YtDlpModel.defaultDownloadsDirectory
    /// The file name without its extension; the real extension is appended by yt-dlp.
    @State private var fileName: String = ""

    let dependencyManager: DependencyManager
    @State private var model: YtDlpModel

    init(dependencyManager: DependencyManager) {
        self.dependencyManager = dependencyManager
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
        selectedVideoFormatID != Self.skipOption && selectedAudioFormatID != Self.skipOption
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

                Button("Fetch Info") {
                    selectedVideoFormatID = Self.skipOption
                    selectedAudioFormatID = Self.skipOption
                    fileName = ""
                    model.fetchInfo(for: urlString)
                }
                .disabled(model.isBusy || urlString.isEmpty)
            }

            if let info = model.videoInfo {
                Text(info.title)
                    .font(.headline)
                    .onChange(of: info.formats, initial: true) {
                        if selectedVideoFormatID == Self.skipOption {
                            selectedVideoFormatID = videoFormats.first?.id ?? Self.skipOption
                        }
                        if selectedAudioFormatID == Self.skipOption {
                            selectedAudioFormatID = audioFormats.first?.id ?? Self.skipOption
                        }
                        if fileName.isEmpty {
                            fileName = info.title
                        }
                    }

                if !videoFormats.isEmpty {
                    Picker("Video", selection: $selectedVideoFormatID) {
                        Text("None").tag(Self.skipOption)
                        ForEach(videoFormats) { format in
                            Text(format.label).tag(format.id)
                        }
                    }
                }

                if !audioFormats.isEmpty {
                    Picker("Audio", selection: $selectedAudioFormatID) {
                        Text("None").tag(Self.skipOption)
                        ForEach(audioFormats) { format in
                            Text(format.label).tag(format.id)
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

            if selectedVideoFormatID != Self.skipOption || selectedAudioFormatID != Self.skipOption {
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
                            videoFormatId: selectedVideoFormatID == Self.skipOption ? nil : selectedVideoFormatID,
                            audioFormatId: selectedAudioFormatID == Self.skipOption ? nil : selectedAudioFormatID,
                            outputContainer: selectedOutputContainer,
                            destinationFolder: destinationFolder,
                            fileName: fileName
                        )
                    }
                    .disabled(model.isBusy || urlString.isEmpty || model.videoInfo == nil)
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
