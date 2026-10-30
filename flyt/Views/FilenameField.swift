//
//  FilenameField.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// The editable filename field (README §3.4–3.5, §5): defaults to the video
/// title, latches "custom" once the user types, and shows a non-editable
/// extension suffix derived from the selected format. Two visual variants —
/// the main body's version (collapsed options) and the options card's
/// version (expanded) — are the same component restyled, not a duplicate,
/// since the design only ever shows one of them at a time.
struct FilenameField: View {
    @Binding var filename: String
    var fileExtension: String
    var isCustom: Bool
    var onReset: () -> Void
    var style: Style
    var label = "Filename"
    var resetTitle = "Reset to video title"

    enum Style { case main, card }

    private var isEmpty: Bool {
        filename.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .main ? 6 : 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .flytStyle(.sectionLabel)
                    .textCase(.uppercase)
                Spacer()
                if isCustom {
                    Button(resetTitle, action: onReset)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.flytSkyHover)
                        .pointingHandCursor()
                }
            }
            HStack(spacing: 8) {
                TextField("", text: $filename)
                    .textFieldStyle(.plain)
                    .font(.system(size: style == .main ? 13 : 12.5))
                    .foregroundStyle(.flytBodyText)
                Text(".\(fileExtension)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.flytFaintText)
            }
            .padding(.horizontal, style == .main ? 11 : 10)
            .frame(height: style == .main ? 38 : 36)
            .background(fieldBackground, in: RoundedRectangle(cornerRadius: fieldRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: fieldRadius, style: .continuous)
                    .strokeBorder(isEmpty ? Color.flytCoral : Color.flytBorder, lineWidth: isEmpty ? 1.5 : 1)
            )
        }
    }

    private var fieldBackground: Color {
        style == .main ? .flytField : .flytSurface
    }

    private var fieldRadius: CGFloat {
        style == .main ? 8 : 7
    }
}
