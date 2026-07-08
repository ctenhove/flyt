//
//  ContentView.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import SwiftUI

struct ContentView: View {
    @State private var model = YtDlpModel()
    
    var body: some View {
        VStack(spacing: 16) {
            Button("Check yt-dlp version") {
                model.runVersion()
            }

            if model.isLoading {
                ProgressView()
            }

            Text(model.output)

            if let error = model.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}

#Preview {
    ContentView()
}
