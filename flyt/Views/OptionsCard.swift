//
//  OptionsCard.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// The expanded options card (README §3.5): filename, resolution chips,
/// video-container / audio-track segmented controls, and the "Audio only"
/// toggle. "Embed thumbnail & chapters" and "Download subtitles" aren't
/// here — those need yt-dlp flags this pass doesn't wire up.
struct OptionsCard: View {
    @Binding var filename: String
    var fileExtension: String
    var filenameIsCustom: Bool
    var onResetFilename: () -> Void

    var resolutionOptions: [FormatSelection.ResolutionOption]
    @Binding var selectedHeight: Int?

    @Binding var selectedContainer: OutputContainer

    var audioOptions: [FormatSelection.AudioOption]
    @Binding var selectedAudioExt: String?

    @Binding var audioOnly: Bool

    var onCollapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            FilenameField(
                filename: $filename,
                fileExtension: fileExtension,
                isCustom: filenameIsCustom,
                onReset: onResetFilename,
                style: .card
            )

            if !resolutionOptions.isEmpty {
                resolutionSection
                    .disabled(audioOnly)
                    .opacity(audioOnly ? 0.5 : 1)
            }

            HStack(alignment: .top, spacing: 22) {
                if !resolutionOptions.isEmpty {
                    containerSection
                        .disabled(audioOnly)
                        .opacity(audioOnly ? 0.5 : 1)
                }
                if audioOptions.count > 1 {
                    audioSection
                }
            }

            Rectangle()
                .fill(Color.flytDividerLight)
                .frame(height: 1)

            Toggle("Audio only", isOn: $audioOnly)
                .toggleStyle(.switch)
                .tint(.flytSky)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.flytBodyTextSecondary)
        }
        .padding(14)
        .background(Color.flytField)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.flytDivider)
        )
    }

    private var header: some View {
        HStack {
            Text("Options")
                .flytStyle(.sectionLabel)
                .textCase(.uppercase)
            Spacer()
            Button(action: onCollapse) {
                HStack(spacing: 6) {
                    Text("Collapse")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.flytSkyHover)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.flytSkyHover)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Resolution")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.flytBodyTextSecondary)
            FlowLayout(spacing: 7) {
                ForEach(resolutionOptions) { option in
                    ChipButton(label: option.label, isSelected: selectedHeight == option.height) {
                        selectedHeight = option.height
                    }
                }
            }
        }
    }

    private var containerSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Video")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.flytBodyTextSecondary)
            SegmentedRow(
                items: OutputContainer.allCases,
                label: { $0.label.uppercased() },
                isSelected: { $0 == selectedContainer },
                onSelect: { selectedContainer = $0 }
            )
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Audio")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.flytBodyTextSecondary)
            SegmentedRow(
                items: audioOptions,
                label: { $0.label },
                isSelected: { $0.ext == selectedAudioExt },
                onSelect: { selectedAudioExt = $0.ext }
            )
        }
    }
}

/// A single unselected/selected pill, used for the resolution chips (which
/// wrap and have gaps between them — unlike `SegmentedRow`'s joined pill).
private struct ChipButton: View {
    var label: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? .white : Color.flytBodyTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.flytSky : Color.flytSurface,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isSelected ? Color.flytSky : Color.flytBorder)
                )
        }
        .buttonStyle(.plain)
    }
}

/// A joined segmented control (Video/Audio format pickers): one continuous
/// pill with hairlines between segments, the selected one filled Sky/white.
private struct SegmentedRow<Item: Identifiable>: View {
    var items: [Item]
    var label: (Item) -> String
    var isSelected: (Item) -> Bool
    var onSelect: (Item) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button(action: { onSelect(item) }) {
                    Text(label(item))
                        .font(.system(size: 12.5, weight: isSelected(item) ? .bold : .semibold))
                        .foregroundStyle(isSelected(item) ? .white : Color.flytBodyTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected(item) ? Color.flytSky : Color.flytSurface)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .leading) {
                    if index > 0 {
                        Rectangle().fill(Color.flytDivider).frame(width: 1)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.flytBorder)
        )
    }
}
