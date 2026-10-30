//
//  ErrorCard.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// The error state (README §3.8): a plain-language message card plus two
/// equal recovery actions. Copy comes from `FlytError`, never a raw yt-dlp
/// exit code.
struct ErrorCard: View {
    var error: FlytError
    var onTryAgain: () -> Void
    var onPasteDifferentLink: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            messageCard
            buttons
        }
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(error.title)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.flytCoralText)
            Text(error.message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.flytCoralText.opacity(0.85))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.flytCoralWash)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.flytCoralBorder)
        )
    }

    private var buttons: some View {
        HStack(spacing: 9) {
            secondaryButton("Try again", action: onTryAgain)
            secondaryButton("Paste a different link", action: onPasteDifferentLink)
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.flytBodyText)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.flytField, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.flytBorder)
                )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}
