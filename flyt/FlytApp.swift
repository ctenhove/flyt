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
                await dependencyManager.performSetupIfNeeded()
            }
        }
        // Compact window (README §3): fixed width, height driven by
        // ContentView's own content — no manual NSWindow frame math.
        .windowResizability(.contentSize)
    }
}
