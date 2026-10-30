//
//  ScratchFolderRegistry.swift
//  flyt
//

import Darwin
import Foundation

/// Remembers every hidden per-download scratch folder (`.flyt-<UUID>`) that
/// currently exists, in a small manifest in Application Support, so a
/// folder left behind by a quit or crash mid-download can be found and
/// deleted on the next launch. The folders live inside whatever destination
/// the user picked, so there's no single place to sweep for them without
/// keeping a record like this.
enum ScratchFolderRegistry {

    private struct Entry: Codable, Equatable {
        let path: String
        /// The app instance that created the folder. A sweep leaves
        /// folders of any process that's still running, so a second
        /// instance can't delete a download the first is in the middle of.
        let pid: Int32
    }

    private static let lock = NSLock()
    private static let folderPrefix = ".flyt-"

    static var defaultManifestURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("flyt", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("scratch-folders.json")
    }

    /// `pid` is injectable so tests can simulate a folder left by a dead process.
    static func register(_ folder: URL, pid: Int32 = getpid(), manifestURL: URL = defaultManifestURL) {
        update(manifestURL) { entries in
            entries.append(Entry(path: folder.path, pid: pid))
        }
    }

    /// Call once the folder is gone, or deliberately being kept (a failed
    /// move leaves the finished download there, which a later sweep must not delete).
    static func unregister(_ folder: URL, manifestURL: URL = defaultManifestURL) {
        update(manifestURL) { entries in
            entries.removeAll { $0.path == folder.path }
        }
    }

    /// Deletes scratch folders recorded by processes that are no longer
    /// running. Meant to run once at launch, before any download starts.
    static func sweepStale(manifestURL: URL = defaultManifestURL) {
        update(manifestURL) { entries in
            entries.removeAll { entry in
                if entry.pid == getpid() || isRunning(entry.pid) { return false }
                let url = URL(fileURLWithPath: entry.path)
                // Only ever delete something this app created, even if the
                // manifest was edited or is stale in some unexpected way.
                if url.lastPathComponent.hasPrefix(folderPrefix) {
                    try? FileManager.default.removeItem(at: url)
                }
                return true
            }
        }
    }

    private static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func update(_ manifestURL: URL, _ change: (inout [Entry]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var entries = (try? Data(contentsOf: manifestURL))
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        let before = entries
        change(&entries)
        guard entries != before, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
