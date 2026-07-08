//
//  YtDlpModel.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-07.
//

import Foundation
import Observation

@Observable
class YtDlpModel {
    var isLoading = false
    var output: String = ""
    var errorMessage: String?
    
    private func run(args: [String]) async throws -> String {
        guard let toolURL = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) else {
            throw NSError(domain: "YtDlpModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Binary not found"])
        }
        
        return try await Task.detached {
            let process = Process()
            process.executableURL = toolURL
            process.arguments = args
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
    
    func runVersion() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await run(args: ["--version"])
                await MainActor.run {
                    self.output = result
                    self.isLoading = false
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "\(error)"
                    self.isLoading = false
                }
            }
        }
    }
}
