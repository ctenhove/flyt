//
//  DownloadHistory.swift
//  flyt
//
//  Created by Colin Ten Hove on 2026-09-28.
//

import Foundation
import Observation

/// One past download, kept so the user can see what they've downloaded
/// before and re-download it. Only the source URL is remembered, not the
/// exact format/track choices used — those could no longer even be valid
/// (yt-dlp's offered formats for a video can change over time), and
/// re-downloading is meant to let the user pick the same or different
/// settings via the normal fetch flow, not silently replay old ones.
struct DownloadHistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let urlString: String
    let title: String
    let fileName: String
    let thumbnailURLString: String?
    let completedAt: Date

    init(urlString: String, title: String, fileName: String, thumbnailURLString: String?, completedAt: Date = Date()) {
        self.id = UUID()
        self.urlString = urlString
        self.title = title
        self.fileName = fileName
        self.thumbnailURLString = thumbnailURLString
        self.completedAt = completedAt
    }
}

/// Persists every completed download to a JSON file in Application Support
/// (`~/Library/Application Support/flyt/history.json`, alongside
/// `DependencyManager`'s `bin/`) so it survives the app quitting. There's
/// no database anywhere in this project, and a JSON array is plenty for
/// what's realistically at most a few thousand entries over a user's
/// lifetime with the app.
@Observable
final class DownloadHistoryStore {
    /// Newest first.
    private(set) var entries: [DownloadHistoryEntry] = []

    private let fileURL: URL

    /// `fileURL` is injectable (rather than always resolving the real
    /// Application Support path) so tests can point a store at a scratch
    /// file instead of the user's real history.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        load()
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("flyt", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("history.json")
    }

    func record(_ entry: DownloadHistoryEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func remove(_ entry: DownloadHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries = []
        save()
    }

    private func load() {
        // No file yet is the normal first-run case, not a failure.
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([DownloadHistoryEntry].self, from: data)
        } catch {
            // Unreadable, corrupt, or written by a newer version. Starting
            // empty is fine, but the next record() would overwrite this
            // file with a single entry — so move it aside first.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("\(fileURL.lastPathComponent).unreadable-\(stamp)")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
