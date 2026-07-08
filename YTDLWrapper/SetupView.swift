//
//  SetupView.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-08.
//

import SwiftUI

struct SetupView: View {
    let state: DependencyManager.SetupState
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            switch state {
            case .checking:
                ProgressView()
                Text("Checking dependencies…")

            case .downloading:
                ProgressView()
                Text("Downloading ffmpeg…")
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
                Button("Try Again", action: onRetry)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
    }
}
