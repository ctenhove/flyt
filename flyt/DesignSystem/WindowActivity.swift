//
//  WindowActivity.swift
//  flyt
//

import SwiftUI

extension View {
    /// Softens this view while the window isn't the focused one, so the
    /// accent blue still reads as "this app's blue" but signals that focus
    /// is elsewhere. Native controls go grey in that state; the app's own
    /// blue fills have nothing doing it for them. Pass `false` for `when`
    /// to leave a view alone (e.g. an unselected chip).
    func fadesWhenWindowInactive(when applies: Bool = true) -> some View {
        modifier(InactiveWindowFade(applies: applies))
    }
}

private struct InactiveWindowFade: ViewModifier {
    var applies: Bool
    @Environment(\.controlActiveState) private var controlActiveState

    func body(content: Content) -> some View {
        content.opacity(applies && controlActiveState == .inactive ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: controlActiveState == .inactive)
    }
}

/// The app's on/off switch. The native macOS switch turns grey whenever its
/// window loses focus — even while on — which reads as "off". This one stays
/// blue and fades along with the rest of the accent colour instead.
struct FlytSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? Color.flytSky : Color.flytBorder)
                    .fadesWhenWindowInactive(when: configuration.isOn)
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
