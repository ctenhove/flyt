//
//  OptionsCard.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// The expanded options card (README §3.5): filename, resolution chips,
/// video-container / audio-track segmented controls, subtitle language +
/// embed toggle, trim-to-section(s), and the "Audio only" toggle. "Embed
/// thumbnail & chapters" still isn't here — that needs a yt-dlp flag this
/// pass doesn't wire up.
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

    var subtitleLanguageOptions: [SubtitleSelection.LanguageOption]
    @Binding var subtitlesEnabled: Bool
    @Binding var selectedSubtitleLanguageCode: String?
    @Binding var embedSubtitles: Bool
    @Binding var subtitleFilename: String
    var subtitleFilenameIsCustom: Bool
    var onResetSubtitleFilename: () -> Void
    /// nil (e.g. a live stream with no known length) hides trimming
    /// entirely — there's no duration to bound the range picker with.
    var duration: Double?
    @Binding var trimEnabled: Bool
    @Binding var timeRanges: [VideoTimeRange]
    @Binding var mergeSections: Bool

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
                .pointingHandCursor()

            if !subtitleLanguageOptions.isEmpty {
                Rectangle()
                    .fill(Color.flytDividerLight)
                    .frame(height: 1)

                subtitlesSection
            }

            if let duration {
                Rectangle()
                    .fill(Color.flytDividerLight)
                    .frame(height: 1)

                trimSection(duration: duration)
            }
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
            .pointingHandCursor()
            .help("Collapse options")
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

    private var subtitlesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle("Download subtitles", isOn: $subtitlesEnabled)
                .toggleStyle(.switch)
                .tint(.flytSky)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.flytBodyTextSecondary)

            if subtitlesEnabled {
                HStack(spacing: 10) {
                    subtitleLanguagePicker
                    // Embedding mixes subtitles into the video file itself,
                    // so it's meaningless once "Audio only" drops the video
                    // track entirely.
                    if !audioOnly {
                        Toggle("Embed", isOn: $embedSubtitles)
                            .toggleStyle(.switch)
                            .tint(.flytSky)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.flytBodyTextSecondary)
                    }
                }
                // Only a sidecar file has a name of its own to choose.
                if audioOnly || !embedSubtitles, let code = selectedSubtitleLanguageCode {
                    FilenameField(
                        filename: $subtitleFilename,
                        fileExtension: "\(code).srt",
                        isCustom: subtitleFilenameIsCustom,
                        onReset: onResetSubtitleFilename,
                        style: .card,
                        label: "Subtitle filename",
                        resetTitle: "Reset to video name"
                    )
                }
            }
        }
    }

    private var subtitleLanguagePicker: some View {
        Menu {
            ForEach(subtitleLanguageOptions) { option in
                Button(option.label) { selectedSubtitleLanguageCode = option.code }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedSubtitleLanguageLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.flytBodyTextSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.flytMutedText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.flytSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.flytBorder)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var selectedSubtitleLanguageLabel: String {
        subtitleLanguageOptions.first { $0.code == selectedSubtitleLanguageCode }?.label ?? "Select language"
    }

    private func trimSection(duration: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Trim to section(s)", isOn: $trimEnabled)
                .toggleStyle(.switch)
                .tint(.flytSky)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.flytBodyTextSecondary)

            if trimEnabled {
                TimeRangeEditor(duration: duration, ranges: $timeRanges, mergeSections: $mergeSections)
            }
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
        .pointingHandCursor()
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
                .pointingHandCursor()
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
