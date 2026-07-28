//
//  FooterPathRow.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI

/// "~/Downloads/flyt · Change…", reused in the idle and ready states
/// (README §3.2, §3.4).
struct FooterPathRow: View {
    var destinationFolder: URL
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(FlytFormat.abbreviatedPath(destinationFolder))
            Text("·").foregroundStyle(.flytBorder)
            Button("Change…", action: onChange)
                .buttonStyle(.plain)
                .foregroundStyle(.flytSky)
        }
        .flytStyle(.micro)
    }
}
