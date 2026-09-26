//
//  TimeRangeEditor.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-09-26.
//

import SwiftUI

/// Lets the user trim a download to one or more time ranges: a slider plus
/// start/end timestamp fields per range, an "Add range" button, and — once
/// there's more than one range — a toggle to merge them into a single file
/// instead of one file per range.
struct TimeRangeEditor: View {
    var duration: Double
    @Binding var ranges: [VideoTimeRange]
    @Binding var mergeSections: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach($ranges) { $range in
                TimeRangeRow(
                    duration: duration,
                    range: $range,
                    onRemove: ranges.count > 1 ? { remove(range.id) } : nil
                )
            }

            Button(action: addRange) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add range")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.flytSkyHover)
            }
            .buttonStyle(.plain)

            if ranges.count > 1 {
                Toggle("Merge into one file", isOn: $mergeSections)
                    .toggleStyle(.switch)
                    .tint(.flytSky)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.flytBodyTextSecondary)
            }
        }
    }

    /// Starts the new range where the last one ended, so successive ranges
    /// default to covering different parts of the video rather than all
    /// stacking on the same span.
    private func addRange() {
        let lastEnd = ranges.last?.end ?? 0
        var next = VideoTimeRange(start: lastEnd, end: lastEnd + 30)
        next.clamp(to: duration)
        ranges.append(next)
    }

    private func remove(_ id: VideoTimeRange.ID) {
        ranges.removeAll { $0.id == id }
    }
}

/// One range's slider and its synced start/end timestamp fields.
private struct TimeRangeRow: View {
    var duration: Double
    @Binding var range: VideoTimeRange
    var onRemove: (() -> Void)?

    @State private var startText = ""
    @State private var endText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RangeSlider(bounds: 0...max(duration, VideoTimeRange.minimumLength), start: $range.start, end: $range.end)

            HStack(spacing: 8) {
                timestampField(text: $startText, onCommit: commitStart)
                Text("–")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.flytFaintText)
                timestampField(text: $endText, onCommit: commitEnd)

                Spacer()

                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.flytFaintText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear(perform: syncText)
        .onChange(of: range.start) { syncText() }
        .onChange(of: range.end) { syncText() }
    }

    private func timestampField(text: Binding<String>, onCommit: @escaping () -> Void) -> some View {
        TextField("0:00", text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.flytBodyText)
            .multilineTextAlignment(.center)
            .frame(width: 56, height: 26)
            .background(Color.flytSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.flytBorder))
            .onSubmit(onCommit)
    }

    /// Parses the typed timestamp and clamps it into the range; an
    /// unparseable value (or one clamp pushes back) is reverted to the
    /// last valid text via `syncText()` rather than left showing garbage.
    private func commitStart() {
        if let parsed = FlytFormat.parseDuration(startText) {
            range.start = parsed
            range.clamp(to: duration)
        }
        syncText()
    }

    private func commitEnd() {
        if let parsed = FlytFormat.parseDuration(endText) {
            range.end = parsed
            range.clamp(to: duration)
        }
        syncText()
    }

    private func syncText() {
        startText = FlytFormat.duration(range.start)
        endText = FlytFormat.duration(range.end)
    }
}
