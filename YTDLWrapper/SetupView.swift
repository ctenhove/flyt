//
//  SetupView.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-08.
//

import SwiftUI

/// First-launch screen shown while the ffmpeg dependency is checked and downloaded.
struct SetupView: View {
    let state: DependencyManager.SetupState
    /// Download completion in 0...1; nil shows an indeterminate spinner.
    let downloadProgress: Double?

    var body: some View {
        VStack(spacing: 20) {
            switch state {
            case .checking:
                ProgressView()
                Text("Checking dependencies…")

            case .downloading:
                if let downloadProgress {
                    ProgressView(value: downloadProgress)
                        .frame(maxWidth: 250)
                    Text("Downloading ffmpeg… \(Int(downloadProgress * 100))%")
                } else {
                    ProgressView()
                    Text("Downloading ffmpeg…")
                }
                Text("This happens once, on first launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .ready:
                // Normally not shown — the app switches away when ready.
                ProgressView()

            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Setup failed")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("ffmpeg is required and couldn't be installed. The app will now quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 400, height: 250)
    }
}
