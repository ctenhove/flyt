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
    
    let dependencyManager: DependencyManager
    @State private var model: YtDlpModel
    
    init(dependencyManager: DependencyManager) {
        self.dependencyManager = dependencyManager
        _model = State(wrappedValue: YtDlpModel(dependencyManager: dependencyManager))
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
            }

            HStack {
                Button("Download") {
                    model.download(urlString: urlString)
                }
                .disabled(model.isBusy || !isValidURL)

                if model.isBusy {
                    Button("Cancel") {
                        model.cancel()
                    }
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
        .frame(width: 480, height: 340)
    }
}
