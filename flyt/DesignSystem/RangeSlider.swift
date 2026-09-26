//
//  RangeSlider.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-09-26.
//

import SwiftUI

/// A two-handle slider for picking a sub-range of `bounds` — used by the
/// trim editor to choose a video's start/end cut points. SwiftUI has no
/// built-in range slider, so this drives `start`/`end` directly from each
/// handle's absolute drag position rather than an incremental delta.
struct RangeSlider: View {
    var bounds: ClosedRange<Double>
    @Binding var start: Double
    @Binding var end: Double

    private let trackHeight: CGFloat = 4
    private let thumbDiameter: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let usableWidth = geo.size.width - thumbDiameter
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.flytSurface)
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Color.flytSky)
                    .frame(width: max(0, x(for: end, in: usableWidth) - x(for: start, in: usableWidth)), height: trackHeight)
                    .offset(x: x(for: start, in: usableWidth))
                handle(value: $start, otherValue: end, isStart: true, usableWidth: usableWidth)
                handle(value: $end, otherValue: start, isStart: false, usableWidth: usableWidth)
            }
        }
        .frame(height: thumbDiameter)
    }

    private func x(for value: Double, in usableWidth: CGFloat) -> CGFloat {
        guard bounds.upperBound > bounds.lowerBound else { return 0 }
        let fraction = (value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
        return CGFloat(fraction) * usableWidth + thumbDiameter / 2
    }

    private func handle(value: Binding<Double>, otherValue: Double, isStart: Bool, usableWidth: CGFloat) -> some View {
        Circle()
            .fill(.white)
            .frame(width: thumbDiameter, height: thumbDiameter)
            .overlay(Circle().strokeBorder(Color.flytSky, lineWidth: 2))
            .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
            .position(x: x(for: value.wrappedValue, in: usableWidth), y: thumbDiameter / 2)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    guard usableWidth > 0 else { return }
                    let fraction = min(max((drag.location.x - thumbDiameter / 2) / usableWidth, 0), 1)
                    let raw = bounds.lowerBound + fraction * (bounds.upperBound - bounds.lowerBound)
                    let minimumGap = VideoTimeRange.minimumLength
                    let constrained = isStart
                        ? min(raw, otherValue - minimumGap)
                        : max(raw, otherValue + minimumGap)
                    value.wrappedValue = min(max(constrained, bounds.lowerBound), bounds.upperBound)
                }
            )
    }
}
