//
//  YTDLWrapperApp.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import SwiftUI

@main
struct YTDLWrapperApp: App {
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
                // binary already ships in the bundle either way.
                async let ytdlpRefresh: Void = dependencyManager.refreshYtdlpIfNeeded()
                await dependencyManager.performSetupIfNeeded()
                await ytdlpRefresh
            }
        }
    }
}
