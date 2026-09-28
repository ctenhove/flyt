//
//  DockProgress.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-09-28.
//

import AppKit

/// Draws a thin progress bar across the bottom of the Dock tile while a
/// download is in flight, so progress is glanceable without switching back
/// to the window — handy once multi-file downloads make a single run take
/// longer.
enum DockProgress {
    private static let tileView = TileView()

    /// Shows the Dock tile's progress bar at `fraction` (0...1).
    static func update(fraction: Double) {
        let dockTile = NSApplication.shared.dockTile
        if dockTile.contentView !== tileView {
            dockTile.contentView = tileView
        }
        // The Dock doesn't auto-size a custom contentView to the tile's own
        // bounds, so this has to be kept in sync explicitly — otherwise the
        // view stays at its zero-size default and draws nothing.
        tileView.frame = NSRect(origin: .zero, size: dockTile.size)
        tileView.fraction = fraction
        dockTile.display()
    }

    /// Restores the plain app icon, e.g. once a download finishes or is cancelled.
    static func clear() {
        let dockTile = NSApplication.shared.dockTile
        guard dockTile.contentView === tileView else { return }
        dockTile.contentView = nil
        dockTile.display()
    }

    private final class TileView: NSView {
        var fraction: Double = 0 {
            didSet { needsDisplay = true }
        }

        override func draw(_ dirtyRect: NSRect) {
            NSApplication.shared.applicationIconImage?.draw(in: bounds)

            let barHeight = bounds.height * 0.09
            let inset = bounds.width * 0.07
            let railRect = NSRect(x: inset, y: inset * 0.7, width: bounds.width - inset * 2, height: barHeight)

            NSColor.black.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: railRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

            let fillWidth = railRect.width * CGFloat(fraction.clamped(to: 0...1))
            guard fillWidth > 0.5 else { return }
            let fillRect = NSRect(x: railRect.minX, y: railRect.minY, width: fillWidth, height: railRect.height)
            (NSColor(named: "FlytSky") ?? .controlAccentColor).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
