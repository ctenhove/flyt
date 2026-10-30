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

    /// The saved destination, or nil if none is saved or it's no longer a
    /// usable folder (deleted, renamed, an unplugged drive, no write access)
    /// — callers then fall back to the default instead of starting a
    /// download that can only fail. The saved value itself is left alone,
    /// so a drive that's merely not mounted this launch works again next time.
    static var destinationFolder: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: destinationFolderKey) else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  FileManager.default.isWritableFile(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
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
