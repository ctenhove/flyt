//
//  IdleDropZone.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-27.
//

import SwiftUI
import UniformTypeIdentifiers

/// The idle state's dashed drop zone (README §3.2), with real drag-and-drop
/// of a URL or plain text. Clipboard watching isn't built this pass (it
/// needs a Preferences toggle that doesn't exist yet), so the copy below
/// only promises what actually works — drop or paste — not clipboard watching.
struct IdleDropZone: View {
    var onDropURL: (String) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            FlytMark(size: 30)
                .opacity(0.45)
            Text("Drop a link, or paste one above")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.flytBodyTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.flytSky : Color.flytBorder,
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        )
        .onDrop(of: [.url, .plainText], isTargeted: $isTargeted, perform: handleDrop)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { onDropURL(url.absoluteString) }
            }
            return true
        }
        if provider.canLoadObject(ofClass: String.self) {
            _ = provider.loadObject(ofClass: String.self) { string, _ in
                guard let string else { return }
                DispatchQueue.main.async { onDropURL(string) }
            }
            return true
        }
        return false
    }
}
