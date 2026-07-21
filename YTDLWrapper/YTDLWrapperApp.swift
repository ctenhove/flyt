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
                        downloadProgress: dependencyManager.downloadProgress,
                        onRetry: {
                            Task { await dependencyManager.performSetupIfNeeded() }
                        }
                    )
                }
            }
            .task {
                await dependencyManager.performSetupIfNeeded()
            }
        }
    }
}
