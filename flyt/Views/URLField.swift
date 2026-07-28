//
//  URLField.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// The URL input row shared across idle/fetching/ready/error (README §3.2–3.3, 3.8)
/// — one component, restyled per state rather than four near-duplicates.
struct URLField: View {
    @Binding var text: String
    var tone: Tone = .neutral
    var trailing: Trailing = .none
    var placeholder: String = "Paste a YouTube link…"

    enum Tone {
        case neutral, focused, error
    }

    enum Trailing {
        case hint, fetching, none
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: leadingSymbol)
                .foregroundStyle(leadingColor)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(.flytBodyText)
            trailingView
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Color.flytField, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .shadow(color: tone == .neutral ? .clear : .flytSky.opacity(0.12), radius: 3)
    }

    private var leadingSymbol: String {
        tone == .error ? "exclamationmark.circle" : "link"
    }

    private var leadingColor: Color {
        switch tone {
        case .neutral: .flytFaintText
        case .focused: .flytSky
        case .error: .flytCoral
        }
    }

    private var borderColor: Color {
        switch tone {
        case .neutral: .flytBorder
        case .focused: .flytSky
        case .error: .flytCoral
        }
    }

    private var borderWidth: CGFloat {
        tone == .neutral ? 1 : 1.5
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .hint:
            Text("⌘V")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.flytBorder)
        case .fetching:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("FETCHING")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.flytSkyHover)
            }
        case .none:
            EmptyView()
        }
    }
}
