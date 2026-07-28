//
//  MainWindowChrome.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// The main window's centred mark+wordmark titlebar (README §3.1), via the
/// native toolbar rather than a hand-drawn 40pt bar — the handoff explicitly
/// prefers native metrics here. No gear/Preferences button: Preferences
/// doesn't exist yet in this pass, so there's nowhere for it to go.
///
/// `pulse`, when toggled true then back to false inside a `withAnimation`,
/// plays a scale pulse on the mark — a simplified stand-in for the mockup's
/// "triangle drops onto the bar" animation (README §3.7), which would need
/// the mark decomposed into independently-offsettable triangle/bar layers.
/// This is the redesign's one sanctioned mark animation either way: it only
/// fires on download completion, nowhere else.
struct MainWindowTitlebar: ToolbarContent {
    var pulse: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                FlytMark(size: 14)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                Text("flyt")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.flytBodyText)
            }
        }
    }
}
