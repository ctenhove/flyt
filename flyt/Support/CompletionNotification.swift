//
//  CompletionNotification.swift
//  flyt
//

import AppKit
import UserNotifications

/// Posts a local notification when a download finishes while the user has
/// switched away from the app — the Dock icon alone doesn't call out a
/// completed download the way a pulse-then-gone-unnoticed bounce does.
/// Does nothing if the user hasn't allowed notifications.
enum CompletionNotification {
    /// Asks for permission the first time a download starts, rather than at
    /// launch: the prompt then arrives with something the user just did,
    /// and only if they ever download anything. A no-op once the user has
    /// answered.
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, error in
                if let error { print("Notification authorization failed: \(error)") }
            }
        }
    }

    static func postIfInactive(fileName: String?) {
        guard !NSApplication.shared.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = "Download complete"
        content.body = fileName ?? "Your video finished downloading."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Couldn't post completion notification: \(error)") }
        }
    }
}
