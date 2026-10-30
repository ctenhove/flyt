//
//  HistoryView.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-09-28.
//

import SwiftUI

/// The download history sheet: every video ever downloaded, newest first,
/// each with a one-tap "Redownload" that hands its URL back to the main
/// window's normal fetch flow — the user picks format/quality there fresh
/// each time rather than this silently replaying old settings, since
/// yt-dlp's offered formats for a video can change over time anyway.
struct HistoryView: View {
    var store: DownloadHistoryStore
    var onRedownload: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.flytDivider)
            if store.entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: 480, height: 420)
        .background(Color.flytSurface)
    }

    private var header: some View {
        HStack {
            Text("Download History")
                .flytStyle(.videoTitle)
            Spacer()
            if !store.entries.isEmpty {
                Button("Clear All", action: store.clearAll)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.flytCoralText)
            }
            Button("Done", action: { dismiss() })
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.flytSkyHover)
                .padding(.leading, 14)
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.flytFaintText)
            Text("Nothing downloaded yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.flytBodyTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(store.entries) { entry in
                    HistoryRow(
                        entry: entry,
                        onRedownload: { onRedownload(entry.urlString) },
                        onRemove: { store.remove(entry) }
                    )
                }
            }
            .padding(16)
        }
    }
}

private struct HistoryRow: View {
    var entry: DownloadHistoryEntry
    var onRedownload: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VideoThumbnail(urlString: entry.thumbnailURLString, width: 68, height: 38, cornerRadius: 5, durationSeconds: nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.flytBodyText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(entry.fileName) · \(Self.dateText(entry.completedAt))")
                    .flytStyle(.micro)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Button("Redownload", action: onRedownload)
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.flytSky, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.flytFaintText)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.flytField, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.flytDivider)
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func dateText(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
