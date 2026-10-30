//
//  Preferences.swift
//  flyt
//

import Foundation

/// The launch-to-launch preferences kept in `UserDefaults` (destination
/// folder, output container, preferred resolution) — plain `UserDefaults`
/// rather than security-scoped bookmarks, since the app isn't sandboxed.
enum Preferences {
    private static let destinationFolderKey = "lastDestinationFolderPath"
    private static let outputContainerKey = "lastOutputContainer"
    private static let preferredResolutionHeightKey = "lastPreferredResolutionHeight"

    static var destinationFolder: URL? {
        get { UserDefaults.standard.string(forKey: destinationFolderKey).map { URL(fileURLWithPath: $0) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: destinationFolderKey) }
    }

    static var outputContainer: OutputContainer? {
        get { UserDefaults.standard.string(forKey: outputContainerKey).flatMap(OutputContainer.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: outputContainerKey) }
    }

    /// The last resolution the user picked on any video, so the next video
    /// starts on the same one if it offers it.
    static var preferredResolutionHeight: Int? {
        get { UserDefaults.standard.object(forKey: preferredResolutionHeightKey) as? Int }
        set { UserDefaults.standard.set(newValue, forKey: preferredResolutionHeightKey) }
    }
}
