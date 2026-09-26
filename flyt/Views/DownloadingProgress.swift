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
    /// "Video" / "Audio", when this download has two separate streams to
    /// fetch before merging — video and audio are unrelated files with
    /// unrelated sizes, so the bar/percentage restart from 0% partway
    /// through. Without a label marking that restart as a new stream
    /// rather than a stall or a bug, it reads as the download glitching —
    /// finishing, then inexplicably resetting. nil for a single-stream
    /// download (video-only or audio-only), which has nothing to label.
    var phaseLabel: String?
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

                    switch phase {
                    case .merging:
                        indeterminateRow(label: "Merging…")
                    case .trimmingSection:
                        indeterminateRow(label: phase.label)
                    default:
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

    /// A spinner + label for phases yt-dlp reports no incremental progress
    /// for (merging, trimming a section) — a percentage bar would have
    /// nothing real to show.
    private func indeterminateRow(label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label)
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
        var parts: [String] = []
        if let phaseLabel { parts.append(phaseLabel) }
        parts.append("\(Int(progress * 100))%")
        if let downloadedSizeText, let totalSizeText {
            parts.append("\(downloadedSizeText) of \(totalSizeText)")
        }
        return parts.joined(separator: " · ")
    }

    private var rightStatsText: String {
        [speedText, etaText.map { "\($0) left" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
