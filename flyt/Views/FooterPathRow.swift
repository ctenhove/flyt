//
//  FooterPathRow.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// "~/Downloads/flyt · Change…", reused in the idle and ready states
/// (README §3.2, §3.4).
///
/// `ytdlpVersion`, when present, appends "· yt-dlp 2026.07.04" — this
/// isn't in the mockup (there's no dedicated build-info surface in this
/// pass, since Preferences/About is deferred), but the footer's existing
/// micro-text row is the closest fit for it rather than inventing a new
/// element. `nil` (the common case: only the bundled fallback binary has
/// ever run) shows nothing extra, matching the version-caption's original
/// "only shown once a self-update has actually installed a copy" behavior.
struct FooterPathRow: View {
    var destinationFolder: URL
    var ytdlpVersion: String?
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(FlytFormat.abbreviatedPath(destinationFolder))
            Text("·").foregroundStyle(.flytBorder)
            Button("Change…", action: onChange)
                .buttonStyle(.plain)
                .foregroundStyle(.flytSky)
            if let ytdlpVersion {
                Text("·").foregroundStyle(.flytBorder)
                Text("yt-dlp \(ytdlpVersion)")
            }
        }
        .flytStyle(.micro)
    }
}
