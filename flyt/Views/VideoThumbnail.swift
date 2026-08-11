//
//  VideoThumbnail.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// Async-loaded YouTube thumbnail with the design's Slate-gradient fallback
/// (README §3.4) and an optional bottom-right duration pill. Reused across
/// the ready, options-expanded, downloading, and complete states at each
/// state's own size.
struct VideoThumbnail: View {
    var urlString: String?
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat
    var durationSeconds: Double?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let urlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            gradientFallback
                        }
                    }
                } else {
                    gradientFallback
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            if let durationSeconds {
                Text(FlytFormat.duration(durationSeconds))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                    .padding(5)
            }
        }
    }

    private var gradientFallback: some View {
        LinearGradient(
            colors: [.flytThumbnailGradientStart, .flytThumbnailGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
