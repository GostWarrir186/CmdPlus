import Foundation

/// Migration: versions up to 0.2.0 ran in the App Sandbox, so their settings and
/// history live inside the sandbox container. Copy them to the regular
/// locations once, on the first launch without the sandbox.
enum SandboxMigration {
    static let doneKey = "migration.leftSandbox"

    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        container: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.azam.CmdPlus/Data", directoryHint: .isDirectory),
        applicationSupport: URL = URL.applicationSupportDirectory
    ) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: container.path) else { return }

        // Settings: only fill in what isn't set yet, never overwrite.
        let oldPreferences = container.appending(path: "Library/Preferences/com.azam.CmdPlus.plist")
        if let old = NSDictionary(contentsOf: oldPreferences) as? [String: Any] {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        // History and images.
        let oldData = container.appending(path: "Library/Application Support/CmdPlus", directoryHint: .isDirectory)
        let newData = applicationSupport.appending(path: "CmdPlus", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: oldData.path), !fileManager.fileExists(atPath: newData.path) {
            try? fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
            try? fileManager.copyItem(at: oldData, to: newData)
        }
    }
}
