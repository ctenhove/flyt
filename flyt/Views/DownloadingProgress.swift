//
//  DownloadingProgress.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// The downloading state (README §3.6): thumbnail + title, a progress bar
/// with live stats, and Cancel. The mockup also shows a Pause button, but
/// there's no pause/resume capability in this pass — only Cancel is real.
struct DownloadingProgress: View {
    var info: VideoInfo
    var phase: DownloadPhase
    var progress: Double
    var downloadedSizeText: String?
    var totalSizeText: String?
    var speedText: String?
    var etaText: String?
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                VideoThumbnail(urlString: info.thumbnail, width: 120, height: 68, cornerRadius: 7, durationSeconds: nil)
                VStack(alignment: .leading, spacing: 7) {
                    Text(info.title)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(.flytBodyText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if phase == .merging {
                        mergingRow
                    } else {
                        ProgressView(value: progress)
                            .tint(.flytSky)
                            .animation(.linear(duration: 0.25), value: progress)
                        statsRow
                    }
                }
            }

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.flytCoralText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.flytField, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.flytCoralBorder)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var mergingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Merging…")
                .flytStyle(.micro)
        }
    }

    private var statsRow: some View {
        HStack {
            Text(leftStatsText)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.flytSkyHover)
                .monospacedDigit()
            Spacer()
            Text(rightStatsText)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.flytMutedText)
                .monospacedDigit()
        }
    }

    private var leftStatsText: String {
        let percent = "\(Int(progress * 100))%"
        guard let downloadedSizeText, let totalSizeText else { return percent }
        return "\(percent) · \(downloadedSizeText) of \(totalSizeText)"
    }

    private var rightStatsText: String {
        [speedText, etaText.map { "\($0) left" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
