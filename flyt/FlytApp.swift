//
//  FlytApp.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import SwiftUI

@main
struct FlytApp: App {
    @State private var dependencyManager = DependencyManager()

    init() {
        // Before any download can start: clears hidden scratch folders a
        // previous run left behind by quitting or crashing mid-download.
        ScratchFolderRegistry.sweepStale()
    }

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
                // binary already ships in the bundle either way.
                async let ytdlpRefresh: Void = dependencyManager.refreshYtdlpIfNeeded()
                await dependencyManager.performSetupIfNeeded()
                await ytdlpRefresh
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
}
