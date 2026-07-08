//
//  ContentView.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import SwiftUI

/// The app's main window: a URL field plus buttons for checking the yt-dlp
/// version and fetching video metadata, with results shown below.
struct ContentView: View {
    let dependencyManager: DependencyManager
    /// Model that runs the yt-dlp binary; observed so results update the UI.
    @State private var model = YtDlpModel()
    /// The video URL typed or pasted by the user.
    @State private var urlString: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("yt-dlp Downloader")
                .font(.largeTitle)
                .bold()

            HStack {
                TextField("Paste video URL", text: $urlString)
                    .textFieldStyle(.roundedBorder)

                Button("Fetch Info") {
                    model.fetchInfo(for: urlString)
                }
                .disabled(model.isBusy || urlString.isEmpty)
            }

            if let info = model.videoInfo {
                Text(info.title)
                    .font(.headline)
            }

            Button("Download") {
                model.download(urlString: urlString)
            }
            .disabled(model.isBusy || urlString.isEmpty)

            if model.isLoading {
                ProgressView()
            }

            if model.isDownloading {
                ProgressView(value: model.downloadProgress, total: 1.0)
                Text("\(Int(model.downloadProgress * 100))%")
                    .font(.caption)
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
