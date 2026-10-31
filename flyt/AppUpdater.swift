//
//  AppUpdater.swift
//  flyt
//

import Combine
import Foundation
import Sparkle

/// Wraps Sparkle's standard updater: checks the appcast named by the app's
/// `SUFeedURL` for a newer build, and shows Sparkle's own update UI.
///
/// The updater only starts when `SUPublicEDKey` is set in the Info.plist,
/// since Sparkle refuses to install anything it can't verify and would
/// otherwise show an error dialog on every launch of a build that has no
/// signing key yet — see RELEASING.md for generating one.
@MainActor
final class AppUpdater: ObservableObject {
    /// True once a public signing key is configured and the updater is running.
    let isConfigured: Bool

    /// False while a check is already running (or the updater isn't running).
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isConfigured = !(publicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        controller = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
