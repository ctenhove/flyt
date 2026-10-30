//
//  WindowActivity.swift
//  flyt
//

import SwiftUI

extension View {
    /// Softens this view while its window isn't the focused one, so it's
    /// obvious at a glance that focus is elsewhere. Apply it once to a
    /// window's content rather than to individual controls: the app's own
    /// accent colours (blue fills, links, the progress bar) otherwise look
    /// identical whether or not the window is active, while native controls
    /// grey out on their own.
    func fadesWhenWindowInactive(opacity: Double = 0.7) -> some View {
        modifier(InactiveWindowFade(opacity: opacity))
    }
}

private struct InactiveWindowFade: ViewModifier {
    var opacity: Double
    @Environment(\.controlActiveState) private var controlActiveState

    func body(content: Content) -> some View {
        content
            .opacity(controlActiveState == .inactive ? opacity : 1)
            .animation(.easeOut(duration: 0.15), value: controlActiveState == .inactive)
    }
}

/// The app's on/off switch. The native macOS switch turns grey whenever its
/// window loses focus — even while on — which reads as "off". This one stays
/// blue; the window-wide fade (`fadesWhenWindowInactive`) is what signals focus loss.
struct FlytSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? Color.flytSky : Color.flytBorder)
                    .frame(width: 38, height: 22)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                            .padding(2)
                    }
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

extension ToggleStyle where Self == FlytSwitchToggleStyle {
    static var flytSwitch: FlytSwitchToggleStyle { FlytSwitchToggleStyle() }
}
