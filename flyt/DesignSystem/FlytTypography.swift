//
//  FlytTypography.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// Text roles from the design handoff's type scale (README §2), each
/// bundling the font size/weight, tracking, and default colour that role
/// always uses together — so call sites state *what* a piece of text is
/// rather than restating the same three values everywhere it repeats.
///
/// Weight mapping follows the handoff's HTML→native table: 600→semibold,
/// 700→bold. Numeric values (percentages, sizes, speeds) aren't a style
/// here — chain the standard `.monospacedDigit()` modifier at the call site.
enum FlytTextStyle {
    case videoTitle
    case primaryButton
    case secondaryButton
    case controlLabel
    case sectionLabel
    case metadata
    case micro

    var font: Font {
        switch self {
        case .videoTitle: .system(size: 14, weight: .bold)
        case .primaryButton: .system(size: 15, weight: .bold)
        case .secondaryButton: .system(size: 13.5, weight: .semibold)
        case .controlLabel: .system(size: 12.5, weight: .semibold)
        case .sectionLabel: .system(size: 10, weight: .bold)
        case .metadata: .system(size: 12, weight: .medium)
        case .micro: .system(size: 11.5, weight: .semibold)
        }
    }

    /// Letter-spacing in points. Only the all-caps section label carries
    /// tracking in the handoff (0.11em at 10pt ≈ 1.1pt).
    var tracking: CGFloat {
        switch self {
        case .sectionLabel: 1.1
        default: 0
        }
    }

    /// The colour this role uses absent a more specific state (error,
    /// selected, etc.) — callers override with `.foregroundStyle(_:)` after
    /// applying the style when a state colour applies.
    var defaultColor: Color {
        switch self {
        case .videoTitle, .primaryButton, .secondaryButton, .controlLabel: .flytBodyText
        case .sectionLabel, .metadata: .flytMutedText
        case .micro: .flytFaintText
        }
    }
}

private struct FlytTextStyleModifier: ViewModifier {
    let style: FlytTextStyle

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .tracking(style.tracking)
            .foregroundStyle(style.defaultColor)
    }
}

extension View {
    /// Applies a `FlytTextStyle`'s font, tracking, and default colour
    /// together. Section labels are rendered as typed (not force-uppercased)
    /// since not every call site sources its text pre-uppercased — add
    /// `.textCase(.uppercase)` at the call site when it isn't.
    func flytStyle(_ style: FlytTextStyle) -> some View {
        modifier(FlytTextStyleModifier(style: style))
    }
}
