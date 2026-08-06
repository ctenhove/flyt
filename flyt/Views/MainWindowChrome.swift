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
        // Liquid Glass toolbars (macOS 26+) draw a pill-shaped glass
        // background behind toolbar items by default, as if this were a
        // grouped control — it isn't one, it's the brand mark, so opt this
        // specific item out. Only available from 26 on, hence the guard;
        // pre-26 never had that background to begin with.
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) {
                titlebarContent
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) {
                titlebarContent
            }
        }
    }

    private var titlebarContent: some View {
        HStack(spacing: 6) {
            FlytMark(size: 14)
                .scaleEffect(pulse ? 1.15 : 1.0)
            Text("flyt")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.flytBodyText)
        }
    }
}
