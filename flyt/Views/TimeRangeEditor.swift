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
            // Capped rather than left to grow with the range count: an
            // uncapped list is what made the window balloon past the
            // screen with several ranges added (the window has no height
            // limit of its own — see FlytApp's .windowResizability). Below
            // the cap this just reports its natural (shorter) height, so
            // one or two ranges never show a scroll indicator at all.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach($ranges) { $range in
                        TimeRangeRow(
                            duration: duration,
                            range: $range,
                            onRemove: ranges.count > 1 ? { remove(range.id) } : nil
                        )
                    }
                }
            }
            .frame(maxHeight: 170)

            if ranges.hasOverlaps {
                overlapWarning
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

    private var overlapWarning: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .padding(.top, 1)
            Text("Ranges overlap — the shared footage will be downloaded twice.")
                .font(.system(size: 11, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.flytCoralText)
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
