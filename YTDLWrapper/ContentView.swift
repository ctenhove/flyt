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
    @State private var selectedFormatID: String?

    let dependencyManager: DependencyManager
    @State private var model: YtDlpModel
    
    init(dependencyManager: DependencyManager) {
        self.dependencyManager = dependencyManager
        _model = State(wrappedValue: YtDlpModel(dependencyManager: dependencyManager))
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
                    selectedFormatID = nil
                    model.fetchInfo(for: urlString)
                }
                .disabled(model.isBusy || urlString.isEmpty)
            }

            if let info = model.videoInfo {
                Text(info.title)
                    .font(.headline)

                if !info.formats.isEmpty {
                    Picker("Format", selection: $selectedFormatID) {
                        ForEach(info.formats.reversed()) { format in
                            Text(format.label).tag(Optional(format.id))
                        }
                    }
                    .onChange(of: info.formats, initial: true) {
                        if selectedFormatID == nil {
                            selectedFormatID = info.formats.last?.id
                        }
                    }
                }
            }

            Button("Download") {
                model.download(urlString: urlString, formatId: selectedFormatID)
            }
            .disabled(model.isBusy || urlString.isEmpty || model.videoInfo == nil)

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
        .frame(width: 480, height: 340)
    }
}
