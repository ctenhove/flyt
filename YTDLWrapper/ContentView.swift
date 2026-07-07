//
//  ContentView.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
            Text("Hello, world!")
        }
        .padding()
        .onAppear {
            testYtDlp()
        }
    }

    func testYtDlp() {
        guard let toolURL = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) else {
            print("Binary not found in bundle")
            return
        }

        let process = Process()
        process.executableURL = toolURL
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            print(String(data: data, encoding: .utf8) ?? "no output")
        } catch {
            print("Failed to launch: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
