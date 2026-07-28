//
//  VideoSummaryCard.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// Thumbnail + title + metadata row shown in the ready and options-expanded
/// states (README §3.4–3.5).
struct VideoSummaryCard: View {
    var info: VideoInfo

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VideoThumbnail(
                urlString: info.thumbnail,
                width: 120,
                height: 68,
                cornerRadius: 7,
                durationSeconds: info.duration
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(info.title)
                    .flytStyle(.videoTitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(metadataLine)
                    .flytStyle(.metadata)
            }
        }
    }

    private var metadataLine: String {
        var parts: [String] = []
        if let channel = info.channel { parts.append(channel) }
        if let duration = info.duration { parts.append(FlytFormat.duration(duration)) }
        if let viewCount = info.viewCount { parts.append(FlytFormat.viewCount(viewCount)) }
        return parts.joined(separator: " · ")
    }
}
