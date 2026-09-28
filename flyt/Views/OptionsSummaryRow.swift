//
//  OptionsSummaryRow.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// The collapsed options disclosure row (README §3.4): the whole row is the
/// disclosure control, e.g. "1080p / MP4 / M4A / ≈ 74 MB" → Options ⌄.
struct OptionsSummaryRow: View {
    var segments: [String]
    var estimatedSizeText: String?
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                summaryLabel
                Spacer()
                HStack(spacing: 6) {
                    Text("Options")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.flytSkyHover)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.flytSkyHover)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                isHovering ? Color.flytDivider : Color.flytChrome,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .help("Expand options")
    }

    private var summaryLabel: some View {
        HStack(spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Text("/").foregroundStyle(.flytBorder)
                }
                Text(segment).flytStyle(.controlLabel)
            }
            if let estimatedSizeText {
                Text(estimatedSizeText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.flytMutedText)
                    .monospacedDigit()
                    .padding(.leading, 2)
            }
        }
    }
}
