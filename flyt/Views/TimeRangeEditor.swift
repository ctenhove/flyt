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

    /// Ranges beyond this many switch the list into a fixed-height,
    /// scrollable box instead of growing freely — the window has no
    /// height cap of its own (see FlytApp's .windowResizability), so an
    /// uncapped list is what made it balloon past the screen with several
    /// ranges added. Below the threshold there's no ScrollView at all: one
    /// with only a `maxHeight` has nothing concrete to size itself against
    /// in this content-driven-sizing window and collapses to zero height —
    /// a plain `.frame(height:)` doesn't have that ambiguity, but only
    /// actually needs to apply once the list would otherwise grow unbounded.
    /// Kept small (rather than fitting ~3 rows) because the rest of the
    /// options card — filename, resolution, container/audio, audio-only —
    /// already claims a fair amount of height on its own before this box
    /// adds anything on top of it.
    private static let scrollThreshold = 2
    private static let scrollHeight: CGFloat = 116

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if ranges.count > Self.scrollThreshold {
                ScrollView {
                    rangeRows
                }
                .frame(height: Self.scrollHeight)
            } else {
                rangeRows
            }

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
                    .toggleStyle(.flytSwitch)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.flytBodyTextSecondary)
            }
        }
    }

    private var rangeRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ForEach($ranges) would hand each row a Binding subscripted
            // by array index under the hood. If the array is cleared out
            // from under it — e.g. resetFetchedState() setting timeRanges
            // = [] on "Download another" — a row that hasn't finished
            // tearing down yet can still read that binding and trip an
            // index-out-of-range crash. Looking each row's binding up by
            // ID instead means a stale reference just degrades to a
            // harmless fallback instead of crashing.
            ForEach(ranges) { range in
                TimeRangeRow(
                    duration: duration,
                    range: binding(for: range.id),
                    onRemove: ranges.count > 1 ? { remove(range.id) } : nil
                )
            }
        }
        // Applied unconditionally — not just once the list is actually
        // scrollable — so a row's layout never changes shape at the
        // moment the scrollbar appears. Applying this only inside the
        // ScrollView branch made every row visibly jump left the instant
        // a range was added past the threshold.
        .padding(.trailing, 14)
    }

    private func binding(for id: VideoTimeRange.ID) -> Binding<VideoTimeRange> {
        Binding(
            get: { ranges.first { $0.id == id } ?? VideoTimeRange(start: 0, end: VideoTimeRange.minimumLength) },
            set: { newValue in
                guard let index = ranges.firstIndex(where: { $0.id == id }) else { return }
                ranges[index] = newValue
            }
        )
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
