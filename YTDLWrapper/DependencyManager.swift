//
//  DependencyManager.swift
//  YTDLWrapper
//
//  Created by Colin Ten Hove on 2026-07-08.
//

import Foundation

class DependencyManager {
    
    // The app's dedicated folder inside Application Support
    private var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("YTDLWrapper", isDirectory: true)
    }

    // Where our downloaded binaries live
    private var binDirectory: URL {
        appSupportDirectory.appendingPathComponent("bin", isDirectory: true)
    }

    // The full path to the ffmpeg binary specifically
    var ffmpegURL: URL {
        binDirectory.appendingPathComponent("ffmpeg")
    }
    
    // Detect whether we're on Apple Silicon or Intel
    var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }
    
    // Is ffmpeg already downloaded and available?
    func isFFmpegInstalled() -> Bool {
        FileManager.default.fileExists(atPath: ffmpegURL.path)
    }
    
    
}
