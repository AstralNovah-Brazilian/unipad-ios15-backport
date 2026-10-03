import Foundation
import Combine
import os.log

@MainActor
final class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    private let logger = Logger(subsystem: "com.kimjisub.unipad", category: "Workspace")
    private let preferenceManager = PreferenceManager.shared

    private var activeUniPackSecurityScopedURL: URL?
    private var activeThemeSecurityScopedURL: URL?

    private var cachedUniPackURL: URL?
    private var cachedThemeURL: URL?
    private var didResolveUniPackWorkspace = false
    private var didResolveThemeWorkspace = false

    struct Workspace: Identifiable, Equatable {
        let id: String
        let name: String
        let url: URL

        init(name: String, url: URL) {
            self.url = url
            self.name = name
            self.id = url.standardizedFileURL.path
        }
    }

    private init() {}

    // MARK: - App Storage Utilities

    static var documentsDirectory: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
    }

    static func ensureDirectoryExists(at url: URL) {
        var isDirectory: ObjCBool = false
        let fm = FileManager.default

        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return
        }

        do {
            try fm.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch {
            Logger(
                subsystem: "com.kimjisub.unipad",
                category: "Workspace"
            ).error("Failed to create directory: \(error.localizedDescription)")
        }
    }

    // MARK: - UniPack Workspace

    var hasConfiguredWorkspace: Bool {
        currentWorkspace != nil
    }

    var currentWorkspace: Workspace? {
        guard let url = uniPackWorkspaceURL() else { return nil }
        return Workspace(name: url.lastPathComponent, url: url)
    }

    var availableWorkspaces: [Workspace] {
        currentWorkspace.map { [$0] } ?? []
    }

    var downloadWorkspace: Workspace? {
        currentWorkspace
    }

    func setWorkspace(url: URL) throws {
        let normalizedURL = url.standardizedFileURL
        let bookmark = try makeBookmark(for: normalizedURL)

        preferenceManager.workspaceBookmark = bookmark
        preferenceManager.downloadStoragePath = normalizedURL.path

        activateUniPackSecurityScope(for: normalizedURL)
        cachedUniPackURL = normalizedURL
        didResolveUniPackWorkspace = true

        objectWillChange.send()
    }

    func resetWorkspace() {
        releaseUniPackSecurityScope()

        cachedUniPackURL = nil
        didResolveUniPackWorkspace = true

        preferenceManager.workspaceBookmark = nil
        preferenceManager.downloadStoragePath = nil

        objectWillChange.send()
    }

    func validateWorkspace() {
        guard let workspace = currentWorkspace else {
            if preferenceManager.downloadStoragePath != nil {
                preferenceManager.downloadStoragePath = nil
            }
            return
        }

        if preferenceManager.downloadStoragePath != workspace.url.path {
            preferenceManager.downloadStoragePath = workspace.url.path
        }
    }

    // MARK: - Theme Workspace

    var hasConfiguredThemeWorkspace: Bool {
        themeWorkspace != nil
    }

    var themeWorkspace: Workspace? {
        guard let url = themeWorkspaceURL() else { return nil }
        return Workspace(name: url.lastPathComponent, url: url)
    }

    func setThemeWorkspace(url: URL) throws {
        let normalizedURL = url.standardizedFileURL
        let bookmark = try makeBookmark(for: normalizedURL)

        preferenceManager.themeWorkspaceBookmark = bookmark
        preferenceManager.themeStoragePath = normalizedURL.path

        activateThemeSecurityScope(for: normalizedURL)
        cachedThemeURL = normalizedURL
        didResolveThemeWorkspace = true

        objectWillChange.send()
    }

    func resetThemeWorkspace() {
        releaseThemeSecurityScope()

        cachedThemeURL = nil
        didResolveThemeWorkspace = true

        preferenceManager.themeWorkspaceBookmark = nil
        preferenceManager.themeStoragePath = nil

        objectWillChange.send()
    }

    func validateThemeWorkspace() {
        guard let workspace = themeWorkspace else {
            if preferenceManager.themeStoragePath != nil {
                preferenceManager.themeStoragePath = nil
            }
            return
        }

        if preferenceManager.themeStoragePath != workspace.url.path {
            preferenceManager.themeStoragePath = workspace.url.path
        }
    }

    // MARK: - Bookmark Helpers

    private func makeBookmark(for url: URL) throws -> Data {
        let didAccess = url.startAccessingSecurityScopedResource()

        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func uniPackWorkspaceURL() -> URL? {
        if didResolveUniPackWorkspace {
            return cachedUniPackURL
        }

        didResolveUniPackWorkspace = true
        cachedUniPackURL = resolveWorkspace(
            bookmark: preferenceManager.workspaceBookmark,
            saveRefreshedBookmark: { preferenceManager.workspaceBookmark = $0 },
            activateScope: activateUniPackSecurityScope(for:)
        )

        if cachedUniPackURL == nil {
            preferenceManager.downloadStoragePath = nil
        }

        return cachedUniPackURL
    }

    private func themeWorkspaceURL() -> URL? {
        if didResolveThemeWorkspace {
            return cachedThemeURL
        }

        didResolveThemeWorkspace = true
        cachedThemeURL = resolveWorkspace(
            bookmark: preferenceManager.themeWorkspaceBookmark,
            saveRefreshedBookmark: { preferenceManager.themeWorkspaceBookmark = $0 },
            activateScope: activateThemeSecurityScope(for:)
        )

        if cachedThemeURL == nil {
            preferenceManager.themeStoragePath = nil
        }

        return cachedThemeURL
    }

    private func resolveWorkspace(
        bookmark: Data?,
        saveRefreshedBookmark: (Data) -> Void,
        activateScope: (URL) -> Void
    ) -> URL? {
        guard let bookmark else { return nil }

        var stale = false

        do {
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ).standardizedFileURL

            activateScope(resolvedURL)

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: resolvedURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                logger.error("Configured workspace is unavailable: \(resolvedURL.path)")
                return nil
            }

            if stale {
                let refreshedBookmark = try resolvedURL.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                saveRefreshedBookmark(refreshedBookmark)
            }

            return resolvedURL
        } catch {
            logger.error("Failed to resolve workspace bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Security Scope

    private func activateUniPackSecurityScope(for url: URL) {
        let normalizedURL = url.standardizedFileURL

        if activeUniPackSecurityScopedURL?.standardizedFileURL.path == normalizedURL.path {
            return
        }

        releaseUniPackSecurityScope()

        if normalizedURL.startAccessingSecurityScopedResource() {
            activeUniPackSecurityScopedURL = normalizedURL
        } else {
            logger.warning("Could not activate UniPack security scope: \(normalizedURL.path)")
        }
    }

    private func releaseUniPackSecurityScope() {
        activeUniPackSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeUniPackSecurityScopedURL = nil
    }

    private func activateThemeSecurityScope(for url: URL) {
        let normalizedURL = url.standardizedFileURL

        if activeThemeSecurityScopedURL?.standardizedFileURL.path == normalizedURL.path {
            return
        }

        releaseThemeSecurityScope()

        if normalizedURL.startAccessingSecurityScopedResource() {
            activeThemeSecurityScopedURL = normalizedURL
        } else {
            logger.warning("Could not activate Theme security scope: \(normalizedURL.path)")
        }
    }

    private func releaseThemeSecurityScope() {
        activeThemeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeThemeSecurityScopedURL = nil
    }

    // MARK: - UniPack Listing

    func getUnipackCount(workspace: Workspace) -> Int {
        directoryFolders(at: workspace.url).count
    }

    func getUnipackFolders(workspace: Workspace) -> [URL] {
        directoryFolders(at: workspace.url)
    }

    private func directoryFolders(at rootURL: URL) -> [URL] {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.filter { url in
            guard url.lastPathComponent != ".nomedia" else { return false }

            return (try? url.resourceValues(
                forKeys: [.isDirectoryKey]
            ).isDirectory) == true
        }
    }

    // MARK: - Workspace Size

    func getAvailableWorkspacesSize() async -> Int64 {
        guard let workspace = currentWorkspace else { return 0 }
        return await FileManagerExtensions.getFolderSize(at: workspace.url)
    }
}
