//
//  DownloadPrimaryButton.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// The full-width Sky "Download" call to action, reused for the single-video
/// ready state and (in a later pass) the playlist footer. `⌘Return`
/// triggers it from anywhere in the window (README §4).
struct DownloadPrimaryButton: View {
    var title: String = "Download"
    var trailingText: String?
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                FlytMark(size: 17, color: .white)
                Text(title)
                    .flytStyle(.primaryButton)
                    .foregroundStyle(.white)
                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                isHovering ? Color.flytSkyHover : Color.flytSky,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .keyboardShortcut(.return, modifiers: .command)
    }
}
