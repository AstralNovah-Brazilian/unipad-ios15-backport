import SwiftUI

@MainActor
final class AppRouter: ObservableObject {
    @Published private(set) var routeStack: [Route] = []
    @Published var showSplash = true

    private static let externalImportSucceeded = NSNotification.Name("UniPadExternalFileImported")
    private static let externalImportFailed = NSNotification.Name("UniPadExternalFileImportFailed")

    var currentRoute: Route {
        routeStack.last ?? .main
    }

    var isShowingMidiSelect: Bool {
        if case .midiSelect = currentRoute { return true }
        return false
    }

    func navigate(to route: Route) {
        routeStack.append(route)
    }

    func navigateToMidiSelectIfNeeded() {
        guard !isShowingMidiSelect else { return }
        navigate(to: .midiSelect)
    }

    func pop() {
        guard !routeStack.isEmpty else { return }
        routeStack.removeLast()
    }

    func popToRoot() {
        guard !routeStack.isEmpty else { return }
        routeStack.removeAll(keepingCapacity: true)
    }

    func dismissSplash() {
        guard showSplash else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            showSplash = false
        }
    }

    func handleDeepLink(_ url: URL) {
        switch url.scheme?.lowercased() {
        case "file":
            handleFileOpen(url)
        case "unipad":
            handleUnipadScheme(url)
        default:
            break
        }
    }

    // MARK: - External File Import

    private func handleFileOpen(_ url: URL) {
        guard url.pathExtension.lowercased() == "zip" else { return }

        Task { [weak self] in
            guard let self else { return }
            await importExternalFile(url)
        }
    }

    private func importExternalFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let workspace = WorkspaceManager.shared.downloadWorkspace?.url else {
            let error = NSError(
                domain: "UniPad",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Choose a UniPack folder before importing."
                ]
            )
            reportImportFailure(error)
            return
        }

        let importer = UniPackImporter()

        do {
            try await importer.importPack(
                from: url,
                to: workspace,
                delegate: nil
            )

            UsageAnalytics.shared.packImportSucceeded(source: .openIn)

            NotificationCenter.default.post(
                name: Self.externalImportSucceeded,
                object: nil
            )
        } catch {
            reportImportFailure(error)
        }
    }

    private func reportImportFailure(_ error: Error) {
        UsageAnalytics.shared.packImportFailed(
            source: .openIn,
            error: error
        )

        NotificationCenter.default.post(
            name: Self.externalImportFailed,
            object: nil,
            userInfo: ["error": error.localizedDescription]
        )
    }

    // MARK: - UniPad Deep Links

    private func handleUnipadScheme(_ url: URL) {
        guard url.scheme?.lowercased() == "unipad",
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              )
        else {
            return
        }

        switch url.host?.lowercased() {
        case "play":
            guard let path = components.queryItems?
                .first(where: { $0.name == "path" })?
                .value,
                !path.isEmpty
            else {
                return
            }

            navigate(to: .play(packPath: path))

        case "unipack":
            guard let code = components.queryItems?
                .first(where: { $0.name == "code" })?
                .value,
                !code.isEmpty
            else {
                return
            }

            navigate(to: .importByUrl(code: code))

        default:
            break
        }
    }
}
