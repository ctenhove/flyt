//
//  CompleteCard.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// The complete state (README §3.7): a saved-file summary and two actions.
/// The mockup's mark-drop animation plays on the titlebar mark instead of
/// here — see `MainWindowChrome`.
struct CompleteCard: View {
    var savedFileURL: URL
    var thumbnailURLString: String?
    var resolutionLabel: String?
    /// nil when no merge happened (audio-only, or video with no audio
    /// track) — the container picker only determines anything when yt-dlp
    /// actually muxes two streams together; showing it otherwise would
    /// claim a container the saved file was never written into.
    var containerLabel: String?
    var audioLabel: String?
    var destinationFolder: URL
    var savedSizeBytes: Int64?
    var elapsedSeconds: Double?
    var onShowInFinder: () -> Void
    var onDownloadAnother: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header
            card
            buttons
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.flytCoral)
                .frame(width: 9, height: 9)
            Text(headerText)
                .flytStyle(.videoTitle)
        }
    }

    private var headerText: String {
        guard let savedSizeBytes else { return "Saved" }
        let sizeText = FlytFormat.fileSize(savedSizeBytes)
        guard let elapsedSeconds else { return "Saved · \(sizeText)" }
        return "Saved · \(sizeText) in \(Int(elapsedSeconds))s"
    }

    private var card: some View {
        HStack(spacing: 13) {
            VideoThumbnail(urlString: thumbnailURLString, width: 104, height: 59, cornerRadius: 6, durationSeconds: nil)
            VStack(alignment: .leading, spacing: 4) {
                Text(savedFileURL.lastPathComponent)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.flytBodyText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detailLine)
                    .flytStyle(.micro)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(Color.flytField)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.flytDivider)
        )
    }

    private var detailLine: String {
        var parts: [String] = []
        if let resolutionLabel { parts.append(resolutionLabel) }
        if let containerLabel { parts.append(containerLabel.uppercased()) }
        if let audioLabel { parts.append(audioLabel.uppercased()) }
        parts.append(FlytFormat.abbreviatedPath(destinationFolder))
        return parts.joined(separator: " · ")
    }

    private var buttons: some View {
        HStack(spacing: 9) {
            Button(action: onShowInFinder) {
                Text("Show in Finder")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.flytSky, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onDownloadAnother) {
                Text("Download another")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.flytBodyText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.flytField, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.flytBorder)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
