//
//  FlytMark.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// flyt's "Downplay" mark: a downward play triangle resting above a landing
/// bar, the gap between them standing for a file still in flight (README §1).
///
/// Coordinates are the handoff's 32px-size-ladder geometry (bar at full
/// opacity), not the ≥128px master (85%-opacity bar) or the <16px bar-less
/// variant — this view only ever renders small in-app (titlebar, buttons,
/// drop zone), so neither of those other two rungs of the size ladder apply.
/// Callers dim the whole mark via `.opacity(_:)` for treatments like the
/// drop zone's 45%-opacity glyph; that's independent of the bar's own
/// opacity, which this view always draws at 100%.
struct FlytMark: View {
    var size: CGFloat
    var color: Color = .flytSky

    /// The coordinate space the path/rect literals below are authored in,
    /// matching the design handoff so this math reads the same as the spec.
    private static let canvas: CGFloat = 100

    var body: some View {
        Canvas { context, _ in
            let scale = size / Self.canvas
            let transform = CGAffineTransform(scaleX: scale, y: scale)

            var triangle = Path()
            triangle.move(to: CGPoint(x: 28, y: 32))
            triangle.addLine(to: CGPoint(x: 72, y: 32))
            triangle.addLine(to: CGPoint(x: 50, y: 66))
            triangle.closeSubpath()

            let bar = Path(
                roundedRect: CGRect(x: 29, y: 73, width: 42, height: 9),
                cornerRadius: 4.5
            )

            context.fill(triangle.applying(transform), with: .color(color))
            context.fill(bar.applying(transform), with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        FlytMark(size: 14)
        FlytMark(size: 24)
        FlytMark(size: 30).opacity(0.45)
        FlytMark(size: 48, color: .flytSlate)
    }
    .padding()
}
