import Foundation
import Combine

@MainActor
final class StorageSetupViewModel: ObservableObject {
    @Published private(set) var selectedFolderName = ""
    @Published private(set) var selectedFolderPath = ""
    @Published private(set) var isReady = false
    @Published var errorMessage: String?

    private let workspaceManager: WorkspaceManager

    init(workspaceManager: WorkspaceManager = .shared) {
        self.workspaceManager = workspaceManager
        refresh()
    }

    func selectFolder(_ url: URL) {
        do {
            try workspaceManager.setWorkspace(url: url)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        refresh()
    }

    func refresh() {
        guard let workspace = workspaceManager.currentWorkspace else {
            applyEmptyState()
            return
        }

        let name = workspace.name
        let path = workspace.url.path

        if selectedFolderName != name {
            selectedFolderName = name
        }

        if selectedFolderPath != path {
            selectedFolderPath = path
        }

        if !isReady {
            isReady = true
        }
    }

    func reset() {
        workspaceManager.resetWorkspace()
        errorMessage = nil
        applyEmptyState()
    }

    private func applyEmptyState() {
        if !selectedFolderName.isEmpty {
            selectedFolderName = ""
        }

        if !selectedFolderPath.isEmpty {
            selectedFolderPath = ""
        }

        if isReady {
            isReady = false
        }
    }
}
