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
        /// A one-tap "Paste — youtu.be/…"-style affordance shown in place of
        /// the ⌘V hint when the clipboard already holds a YouTube URL and the
        /// field is empty — a one-time check on render rather than continuous
        /// clipboard watching (see `IdleDropZone`'s doc comment).
        case pasteSuggestion(label: String, action: () -> Void)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: leadingSymbol)
                .foregroundStyle(leadingColor)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(.flytBodyText)
                // Replacing the context menu drops the standard editing
                // commands, so they're rebuilt here. Each acts on the field
                // being edited (the selection / cursor), the way the real
                // commands do.
                .contextMenu {
                    Button("Cut") { sendEditingAction(#selector(NSText.cut(_:))) }
                    Button("Copy") { sendEditingAction(#selector(NSText.copy(_:))) }
                    Button("Paste", action: pasteFromClipboard)
                    Divider()
                    Button("Select All") { sendEditingAction(#selector(NSText.selectAll(_:))) }
                }
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
        case .pasteSuggestion(let label, let action):
            Button(action: action) {
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.flytSky)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        case .none:
            EmptyView()
        }
    }

    /// Sends an editing command to the field being edited; false if no text
    /// field has focus (right-clicking doesn't necessarily give it focus).
    @discardableResult
    private func sendEditingAction(_ action: Selector) -> Bool {
        guard NSApp.keyWindow?.firstResponder is NSText else { return false }
        return NSApp.sendAction(action, to: nil, from: nil)
    }

    /// Pastes at the cursor / over the selection when the field is being
    /// edited; otherwise the field has no cursor to respect, so the
    /// clipboard simply becomes its contents.
    private func pasteFromClipboard() {
        if sendEditingAction(#selector(NSText.paste(_:))) { return }
        if let clipboardString = NSPasteboard.general.string(forType: .string) {
            text = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
