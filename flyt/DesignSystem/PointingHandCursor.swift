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
    /// though it's clickable. Push/pop rather than set/reset so this nests
    /// correctly alongside AppKit's own cursor management (e.g. text fields).
    func pointingHandCursor() -> some View {
        onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
