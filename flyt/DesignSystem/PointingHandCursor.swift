//
//  PointingHandCursor.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-09-28.
//

import SwiftUI

extension View {
    /// Shows the pointing-hand cursor while hovering over this view.
    /// `.onHover` alone (used throughout the app for hover-tint effects)
    /// doesn't touch `NSCursor` — nothing in the app calls it otherwise, so
    /// every chip, toggle, and button falls back to the default arrow even
    /// though it's clickable. Uses an AppKit cursor rect rather than
    /// pushing/popping the cursor on hover: the window owns a cursor rect's
    /// lifetime, so a hovered view that disappears (Download turning into
    /// the progress view, say) can't leave the hand stuck on the cursor stack.
    func pointingHandCursor() -> some View {
        overlay(PointingHandCursorArea())
    }
}

private struct PointingHandCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        CursorAreaView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }

    private final class CursorAreaView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }

        /// Never intercepts clicks or hovers meant for the control underneath;
        /// cursor rects are tracked by the window, independent of hit testing.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }
    }
}
