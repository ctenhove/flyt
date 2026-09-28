//
//  FlytApp.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import SwiftUI
import UserNotifications

@main
struct FlytApp: App {
    @State private var dependencyManager = DependencyManager()

    var body: some Scene {
        WindowGroup {
            Group {
                switch dependencyManager.setupState {
                case .ready:
                    ContentView(dependencyManager: dependencyManager)
                default:
                    SetupView(
                        state: dependencyManager.setupState,
                        downloadProgress: dependencyManager.downloadProgress
                    )
                }
            }
            .task {
                // Runs concurrently with the blocking ffmpeg setup below,
                // not after it — a yt-dlp refresh must never delay
                // startup, since (unlike ffmpeg) a working fallback
                // binary already ships in the bundle either way. Requesting
                // notification authorization up front means it's already
                // resolved by the time a download could finish in the
                // background and need to post one.
                async let ytdlpRefresh: Void = dependencyManager.refreshYtdlpIfNeeded()
                async let notificationAuth: Void = requestNotificationAuthorization()
                await dependencyManager.performSetupIfNeeded()
                await ytdlpRefresh
                await notificationAuth
            }
        }
        // Compact window (README §3): fixed width, height driven by
        // ContentView's own content — no manual NSWindow frame math.
        .windowResizability(.contentSize)
        // flyt is a single-window utility app: drop the "New Window"
        // command (and its ⌘N shortcut) so WindowGroup can't be asked to
        // spawn a second copy of the main window.
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }

    private func requestNotificationAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}
