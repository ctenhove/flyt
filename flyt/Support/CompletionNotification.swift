//
//  CompletionNotification.swift
//  flyt
//

import AppKit
import UserNotifications

/// Posts a local notification when a download finishes while the user has
/// switched away from the app — the Dock icon alone doesn't call out a
/// completed download the way a pulse-then-gone-unnoticed bounce does.
/// Silently does nothing if notifications were never authorized.
enum CompletionNotification {
    static func postIfInactive(fileName: String?) {
        guard !NSApplication.shared.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download complete"
        content.body = fileName ?? "Your video finished downloading."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
