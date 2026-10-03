import Foundation
import Combine

@MainActor
final class PreferenceManager: ObservableObject {
    static let shared = PreferenceManager()

    private let defaults: UserDefaults

    enum Keys {
        static let launchpadConnectMethod = "LaunchpadConnectMethod"
        static let selectedTheme = "SelectedTheme"
        static let prevStoreCount = "PrevStoreCount"
        static let sortMethod = "SortMethod"
        static let sortOrder = "SortOrder"
        static let downloadStoragePath = "download_storage_path"
        static let workspaceBookmark = "workspace_bookmark"
        static let themeStoragePath = "theme_storage_path"
        static let themeWorkspaceBookmark = "theme_workspace_bookmark"
        static let traceLogClassic = "TraceLogClassic"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.launchpadConnectMethod: 0,
            Keys.selectedTheme: Bundle.main.bundleIdentifier ?? "com.kimjisub.unipad",
            Keys.prevStoreCount: Int64(0),
            Keys.sortMethod: 4,
            Keys.sortOrder: true,
            Keys.traceLogClassic: false
        ])
    }

    // MARK: - General

    var launchpadConnectMethod: Int {
        get { defaults.integer(forKey: Keys.launchpadConnectMethod) }
        set {
            guard newValue != defaults.integer(forKey: Keys.launchpadConnectMethod) else { return }
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.launchpadConnectMethod)
        }
    }

    var selectedTheme: String {
        get {
            defaults.string(forKey: Keys.selectedTheme)
                ?? Bundle.main.bundleIdentifier
                ?? "com.kimjisub.unipad"
        }
        set {
            guard newValue != selectedTheme else { return }
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.selectedTheme)
        }
    }

    var prevStoreCount: Int64 {
        get {
            (defaults.object(forKey: Keys.prevStoreCount) as? NSNumber)?.int64Value ?? 0
        }
        set {
            guard newValue != prevStoreCount else { return }
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.prevStoreCount)
        }
    }

    var sortMethod: Int {
        get { defaults.integer(forKey: Keys.sortMethod) }
        set {
            guard newValue != defaults.integer(forKey: Keys.sortMethod) else { return }
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.sortMethod)
        }
    }

    var sortOrder: Bool {
        get { defaults.bool(forKey: Keys.sortOrder) }
        set {
            guard newValue != defaults.bool(forKey: Keys.sortOrder) else { return }
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.sortOrder)
        }
    }

    var traceLogClassic: Bool {
        get { defaults.bool(forKey: Keys.traceLogClassic) }
        set {
            guard newValue != defaults.bool(forKey: Keys.traceLogClassic) else { return }
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.traceLogClassic)
        }
    }

    // MARK: - UniPack Storage

    var downloadStoragePath: String? {
        get { defaults.string(forKey: Keys.downloadStoragePath) }
        set {
            guard newValue != defaults.string(forKey: Keys.downloadStoragePath) else { return }
            objectWillChange.send()
            setOptional(newValue, forKey: Keys.downloadStoragePath)
        }
    }

    var workspaceBookmark: Data? {
        get { defaults.data(forKey: Keys.workspaceBookmark) }
        set {
            guard newValue != defaults.data(forKey: Keys.workspaceBookmark) else { return }
            objectWillChange.send()
            setOptional(newValue, forKey: Keys.workspaceBookmark)
        }
    }

    // MARK: - Theme Storage

    var themeStoragePath: String? {
        get { defaults.string(forKey: Keys.themeStoragePath) }
        set {
            guard newValue != defaults.string(forKey: Keys.themeStoragePath) else { return }
            objectWillChange.send()
            setOptional(newValue, forKey: Keys.themeStoragePath)
        }
    }

    var themeWorkspaceBookmark: Data? {
        get { defaults.data(forKey: Keys.themeWorkspaceBookmark) }
        set {
            guard newValue != defaults.data(forKey: Keys.themeWorkspaceBookmark) else { return }
            objectWillChange.send()
            setOptional(newValue, forKey: Keys.themeWorkspaceBookmark)
        }
    }

    // MARK: - Helpers

    @inline(__always)
    private func setOptional(_ value: Any?, forKey key: String) {
        if let value = value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
