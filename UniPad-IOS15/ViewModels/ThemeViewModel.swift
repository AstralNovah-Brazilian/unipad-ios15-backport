import SwiftUI
import Combine

@MainActor
final class ThemeViewModel: ObservableObject {
    enum ThemeType {
        case builtin
        case zip
    }

    struct ThemeItem: Identifiable {
        let id: String
        var name: String
        var author: String
        var version: String?
        var type: ThemeType
        var isDeletable: Bool
        var icon: PlatformImage?
    }

    @Published var themes: [ThemeItem] = []
    @Published var selectedIndex = 0
    @Published var appliedIndex = 0
    @Published var importResultMessage: String?

    private let preferenceManager = PreferenceManager.shared
    private let themeManager = ThemeManager.shared

    private static var themesDirectory: URL? {
        ThemeManager.customThemesDirectory
    }

    init() {
        loadThemes()
    }

    // MARK: - Loading

    func loadThemes() {
        var items: [ThemeItem] = [
            ThemeItem(
                id: "default",
                name: DefaultThemeResources.displayName,
                author: DefaultThemeResources.displayAuthor,
                version: nil,
                type: .builtin,
                isDeletable: false,
                icon: nil
            )
        ]

        if let bundleURL = Bundle.main.url(
            forResource: "BundledThemes",
            withExtension: "bundle"
        ),
        let bundle = Bundle(url: bundleURL) {
            for themeName in ThemeManager.bundledThemeNames() {
                guard
                    let themeDir = bundle.url(
                        forResource: themeName,
                        withExtension: nil
                    ),
                    let resources = try? FolderThemeResources(
                        themeDir: themeDir,
                        fullLoad: false
                    )
                else {
                    continue
                }

                items.append(
                    ThemeItem(
                        id: "\(ThemeManager.bundledThemePrefix)\(themeName)",
                        name: resources.name,
                        author: resources.author,
                        version: resources.version,
                        type: .builtin,
                        isDeletable: false,
                        icon: resources.icon
                    )
                )
            }
        }

        if let themesDir = Self.themesDirectory,
           let contents = try? FileManager.default.contentsOfDirectory(
                at: themesDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
           ) {
            for themeURL in contents {
                guard
                    (try? themeURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                    let resources = try? FolderThemeResources(
                        themeDir: themeURL,
                        fullLoad: false
                    )
                else {
                    continue
                }

                items.append(
                    ThemeItem(
                        id: themeURL.lastPathComponent,
                        name: resources.name,
                        author: resources.author,
                        version: resources.version,
                        type: .zip,
                        isDeletable: true,
                        icon: resources.icon
                    )
                )
            }
        }

        themes = items

        let index = items.firstIndex {
            $0.id == preferenceManager.selectedTheme
        } ?? 0

        appliedIndex = index
        selectedIndex = index
    }

    var selectedThemeResources: ThemeResourcesProtocol? {
        guard themes.indices.contains(selectedIndex) else { return nil }
        return themeManager.loadTheme(
            id: themes[selectedIndex].id,
            fullLoad: true
        )
    }

    func applyTheme(at index: Int) {
        guard themes.indices.contains(index) else { return }
        appliedIndex = index
        themeManager.applyTheme(id: themes[index].id)
    }

    // MARK: - Import

    func importTheme(from url: URL) {
        guard let themesDir = Self.themesDirectory else {
            importResultMessage = "Choose a Themes folder before importing."
            return
        }

        guard url.pathExtension.lowercased() == "zip" else {
            importResultMessage = NSLocalizedString(
                "theme_import_invalid",
                comment: ""
            )
            return
        }

        let fm = FileManager.default
        let sourceName = FileManagerExtensions.filterFilename(
            url.deletingPathExtension().lastPathComponent
        )
        let destDir = FileManagerExtensions.makeNextPath(
            dir: themesDir,
            name: sourceName,
            extension: ""
        )

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fm.createDirectory(
                at: destDir,
                withIntermediateDirectories: true
            )

            try fm.unzipItem(
                at: url,
                to: destDir
            )

            FileManagerExtensions.removeDoubleFolder(at: destDir)

            try normalizeThemeResources(at: destDir)

            _ = try FolderThemeResources(
                themeDir: destDir,
                fullLoad: false
            )

            loadThemes()

            importResultMessage = NSLocalizedString(
                "theme_import_success",
                comment: ""
            )
        } catch {
            try? fm.removeItem(at: destDir)

            importResultMessage =
                "\(NSLocalizedString("theme_import_failed", comment: ""))\n\(error.localizedDescription)"
        }
    }

    private func normalizeThemeResources(at dir: URL) throws {
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var filesByName: [String: URL] = [:]
        filesByName.reserveCapacity(24)

        for case let url as URL in enumerator {
            guard
                (try? url.resourceValues(
                    forKeys: [.isRegularFileKey]
                ).isRegularFile) == true
            else {
                continue
            }

            let key = url.lastPathComponent.lowercased()

            if filesByName[key] == nil {
                filesByName[key] = url
            }
        }

        func copyAlias(
            _ aliases: [String],
            to canonical: String
        ) {
            let target = dir.appendingPathComponent(canonical)

            guard !fm.fileExists(atPath: target.path) else {
                return
            }

            for alias in aliases {
                guard let source = filesByName[alias.lowercased()] else {
                    continue
                }

                try? fm.copyItem(
                    at: source,
                    to: target
                )
                return
            }
        }

        copyAlias(["theme.json"], to: "theme.json")
        copyAlias(["colors.json"], to: "colors.json")
        copyAlias(["theme_ic.png", "theme_ic.webp"], to: "theme_ic.png")
        copyAlias(["playbg.png", "play_bg.png"], to: "playbg.png")
        copyAlias(["custom_logo.png", "customlogo.png"], to: "custom_logo.png")
        copyAlias(["btn.png"], to: "btn.png")
        copyAlias(["btn_.png", "btn_pressed.png", "btn-pressed.png"], to: "btn_.png")
        copyAlias(["chainled.png"], to: "chainled.png")
        copyAlias(["chain.png"], to: "chain.png")
        copyAlias(["chain_.png", "chain_selected.png"], to: "chain_.png")
        copyAlias(["chain__.png", "chain_guide.png"], to: "chain__.png")
        copyAlias(["phantom.png"], to: "phantom.png")
        copyAlias(["phantom_.png", "phantom_variant.png"], to: "phantom_.png")
    }

    // MARK: - Deletion

    func deleteTheme(_ item: ThemeItem) {
        guard
            item.isDeletable,
            let themesDir = Self.themesDirectory
        else {
            return
        }

        let themePath = themesDir.appendingPathComponent(
            item.id,
            isDirectory: true
        )

        try? FileManager.default.removeItem(at: themePath)

        if themeManager.activeThemeId == item.id {
            themeManager.applyTheme(id: "default")
        }

        loadThemes()
    }
}
