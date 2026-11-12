//
//  AppUpdater.swift
//  flyt
//

import Combine
import Foundation
import Sparkle
import SwiftUI

/// Wraps Sparkle's standard updater: checks the appcast named by the app's
/// `SUFeedURL` for a newer build, and shows Sparkle's own update UI.
///
/// The updater only starts when `SUPublicEDKey` is set in the Info.plist,
/// since Sparkle refuses to install anything it can't verify and would
/// otherwise show an error dialog on every launch of a build that has no
/// signing key yet — see RELEASING.md for generating one.
@MainActor
final class AppUpdater: ObservableObject {
    /// False while a check is already running, and always false when the
    /// updater was never started for want of a signing key.
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        let hasSigningKey = !(publicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        controller = SPUStandardUpdaterController(
            startingUpdater: hasSigningKey,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        guard hasSigningKey else { return }
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// The "Check for Updates…" menu item. A view of its own, observing the
/// updater, so its enabled state follows `canCheckForUpdates` — the menu's
/// `commands` builder isn't reliably re-run when that changes.
struct CheckForUpdatesButton: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
