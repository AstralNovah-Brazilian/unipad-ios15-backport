import SwiftUI
import os.log

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    static let bundledThemePrefix = "bundled://"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.kimjisub.unipad",
        category: "ThemeManager"
    )
    private let preferenceManager = PreferenceManager.shared

    @Published private(set) var activeResources: ThemeResourcesProtocol = DefaultThemeResources()
    @Published private(set) var activeThemeId = "default"
    @Published var lastLoadError: String?

    private init() {
        reloadActiveTheme()
    }

    // MARK: - Active Theme

    func reloadActiveTheme() {
        applyThemeInternal(
            id: preferenceManager.selectedTheme,
            persistSelection: false
        )
    }

    func applyTheme(id: String) {
        applyThemeInternal(
            id: id,
            persistSelection: true
        )
    }

    private func applyThemeInternal(
        id: String,
        persistSelection: Bool
    ) {
        if persistSelection {
            preferenceManager.selectedTheme = id
        }

        lastLoadError = nil
        let resources = loadTheme(id: id, fullLoad: true)

        if activeThemeId != id {
            activeThemeId = id
        }

        activeResources = resources
    }

    // MARK: - Loading

    func loadTheme(
        id: String,
        fullLoad: Bool = false
    ) -> ThemeResourcesProtocol {
        let bundleId = Bundle.main.bundleIdentifier ?? ""

        if id == "default" || id == bundleId {
            return DefaultThemeResources()
        }

        if id.hasPrefix(Self.bundledThemePrefix) {
            return loadBundledTheme(
                id: id,
                fullLoad: fullLoad
            )
        }

        return loadCustomTheme(
            id: id,
            fullLoad: fullLoad
        )
    }

    private func loadBundledTheme(
        id: String,
        fullLoad: Bool
    ) -> ThemeResourcesProtocol {
        let themeName = String(
            id.dropFirst(Self.bundledThemePrefix.count)
        )

        guard
            let bundleURL = Bundle.main.url(
                forResource: "BundledThemes",
                withExtension: "bundle"
            ),
            let bundle = Bundle(url: bundleURL),
            let themeDir = bundle.url(
                forResource: themeName,
                withExtension: nil
            )
        else {
            logger.warning(
                "Bundled theme '\(themeName, privacy: .public)' not found."
            )
            return DefaultThemeResources()
        }

        do {
            return try FolderThemeResources(
                themeDir: themeDir,
                fullLoad: fullLoad
            )
        } catch {
            logger.warning(
                "Failed to load bundled theme '\(themeName, privacy: .public)': \(error.localizedDescription, privacy: .public)"
            )
            lastLoadError =
                "\(NSLocalizedString("skinErr", comment: ""))\n\(themeName)"
            return DefaultThemeResources()
        }
    }

    private func loadCustomTheme(
        id: String,
        fullLoad: Bool
    ) -> ThemeResourcesProtocol {
        guard let themesDir = Self.themesDirectory else {
            logger.warning(
                "No custom theme workspace configured."
            )
            return DefaultThemeResources()
        }

        let themeDir = themesDir.appendingPathComponent(
            id,
            isDirectory: true
        )

        do {
            return try FolderThemeResources(
                themeDir: themeDir,
                fullLoad: fullLoad
            )
        } catch {
            logger.warning(
                "Failed to load theme '\(id, privacy: .public)': \(error.localizedDescription, privacy: .public)"
            )

            lastLoadError =
                "\(NSLocalizedString("skinErr", comment: ""))\n\(id)"

            let fallback =
                Bundle.main.bundleIdentifier
                ?? "com.kimjisub.unipad"

            if preferenceManager.selectedTheme != fallback {
                preferenceManager.selectedTheme = fallback
            }

            return DefaultThemeResources()
        }
    }

    // MARK: - Theme Discovery

    static func bundledThemeNames() -> [String] {
        guard
            let bundleURL = Bundle.main.url(
                forResource: "BundledThemes",
                withExtension: "bundle"
            ),
            let themeBundle = Bundle(url: bundleURL),
            let contents = try? FileManager.default.contentsOfDirectory(
                at: themeBundle.bundleURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return contents.compactMap { url in
            guard
                let values = try? url.resourceValues(
                    forKeys: [.isDirectoryKey]
                ),
                values.isDirectory == true
            else {
                return nil
            }

            return url.lastPathComponent
        }
        .sorted()
    }

    static var customThemesDirectory: URL? {
        themesDirectory
    }

    private static var themesDirectory: URL? {
        WorkspaceManager.shared.themeWorkspace?.url
    }
}

