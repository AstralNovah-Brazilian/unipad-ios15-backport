import SwiftUI
import Combine

@MainActor
final class StoreViewModel: ObservableObject {
    struct StoreItem: Identifiable {
        let id: String
        var title: String
        var producerName: String
        var downloadURL = ""
        var fileSize: Int64 = 0
        var downloadCount: Int
        var isLED: Bool
        var isAutoPlay: Bool
        var downloaded: Bool
        var downloading = false
        var isToggle = false
        var playText = ""
        var flagColorOverride: Color?
    }

    @Published var storeItems: [StoreItem] = []
    @Published var isLoading = true

    var selectedItem: StoreItem? {
        storeItems.first { $0.isToggle }
    }

    var downloadedCount: Int {
        storeItems.lazy.filter(\.downloaded).count
    }

    private let firebaseManager = FirebaseManager.shared
    private let workspaceManager = WorkspaceManager.shared
    private var loadTask: Task<Void, Never>?
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Actions

    func loadStore() {
        loadTask?.cancel()
        isLoading = true

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let firestoreItems = try await firebaseManager.firestore.fetchStoreItems()
                guard !Task.isCancelled else { return }

                let downloadedPackIds: Set<String>
                if let workspace = workspaceManager.downloadWorkspace {
                    downloadedPackIds = Set(
                        workspaceManager
                            .getUnipackFolders(workspace: workspace)
                            .map { folderURL in
                                let pack = UniPackFolder(rootFolder: folderURL)
                                pack.load()
                                return pack.id
                            }
                    )
                } else {
                    downloadedPackIds = []
                }

                guard !Task.isCancelled else { return }

                storeItems = firestoreItems.map { item in
                    let downloaded = downloadedPackIds.contains(item.id)

                    return StoreItem(
                        id: item.id,
                        title: item.title,
                        producerName: item.producer,
                        downloadURL: item.downloadURL,
                        fileSize: item.fileSize,
                        downloadCount: item.downloadCount,
                        isLED: item.isLED,
                        isAutoPlay: item.isAutoPlay,
                        downloaded: downloaded,
                        playText: downloaded
                            ? NSLocalizedString("downloaded", comment: "")
                            : "",
                        flagColorOverride: downloaded
                            ? AppColors.green
                            : nil
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                storeItems = []
            }

            if !Task.isCancelled {
                isLoading = false
            }
        }
    }

    func toggleSelection(_ item: StoreItem) {
        withAnimation(.easeInOut(duration: 0.5)) {
            for index in storeItems.indices {
                storeItems[index].isToggle =
                    storeItems[index].id == item.id
                    ? !storeItems[index].isToggle
                    : false
            }
        }
    }

    func startDownload(_ item: StoreItem) {
        guard let index = storeItems.firstIndex(where: { $0.id == item.id }),
              !storeItems[index].downloaded,
              !storeItems[index].downloading
        else {
            return
        }

        guard let workspace = workspaceManager.downloadWorkspace?.url else {
            storeItems[index].downloading = false
            storeItems[index].playText = NSLocalizedString("failed", comment: "")
            storeItems[index].flagColorOverride = AppColors.red
            return
        }

        storeItems[index].downloading = true
        storeItems[index].flagColorOverride = AppColors.textPrimary
        storeItems[index].playText = "0%"

        let itemId = item.id
        let title = item.title
        let downloadURL = item.downloadURL
        let fileSize = item.fileSize

        downloadTasks[itemId]?.cancel()
        downloadTasks[itemId] = Task { [weak self] in
            guard let self else { return }

            let downloader = UniPackDownloader()
            let delegate = StoreDownloadDelegate(
                viewModel: self,
                itemId: itemId
            )

            await downloader.download(
                title: title,
                url: downloadURL,
                workspace: workspace,
                folderName: itemId,
                preKnownFileSize: fileSize,
                delegate: delegate
            )

            downloadTasks[itemId] = nil
        }
    }

    func openYouTubeSearch(for item: StoreItem) {
        let query = "UniPad \(item.title) \(item.producerName)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        guard let url = URL(
            string: "https://www.youtube.com/results?search_query=\(query)"
        ) else {
            return
        }

        PlatformHelpers.openURL(url)
    }
}

// MARK: - Store Download Delegate

private final class StoreDownloadDelegate: UniPackDownloaderDelegate, @unchecked Sendable {
    private weak var viewModel: StoreViewModel?
    private let itemId: String

    init(viewModel: StoreViewModel, itemId: String) {
        self.viewModel = viewModel
        self.itemId = itemId
    }

    @MainActor
    private func updateItem(
        _ block: (inout StoreViewModel.StoreItem) -> Void
    ) {
        guard let vm = viewModel,
              let index = vm.storeItems.firstIndex(where: { $0.id == itemId })
        else {
            return
        }

        block(&vm.storeItems[index])
    }

    @MainActor
    func onInstallStart() {
        updateItem {
            $0.playText = NSLocalizedString("downloading", comment: "")
        }
    }

    @MainActor
    func onGetFileSize(
        fileSize: Int64,
        contentLength: Int64,
        preKnownFileSize: Int64
    ) {
        let totalMB = String(
            format: "%.2f",
            Double(fileSize) / 1_048_576.0
        )

        updateItem {
            $0.playText = "0%\n0.00 / \(totalMB) MB"
        }
    }

    @MainActor
    func onDownloadProgress(
        percent: Int,
        downloadedSize: Int64,
        fileSize: Int64
    ) {
        let dlMB = String(
            format: "%.2f",
            Double(downloadedSize) / 1_048_576.0
        )
        let totalMB = String(
            format: "%.2f",
            Double(fileSize) / 1_048_576.0
        )

        updateItem {
            $0.playText = "\(percent)%\n\(dlMB) / \(totalMB) MB"
        }
    }

    @MainActor
    func onImportStart() {
        updateItem {
            $0.playText = NSLocalizedString("importing", comment: "")
            $0.flagColorOverride = AppColors.orange
        }
    }

    @MainActor
    func onInstallComplete(folder: URL) {
        UsageAnalytics.shared.packImportSucceeded(source: .store)

        updateItem {
            $0.downloading = false
            $0.downloaded = true
            $0.playText = NSLocalizedString("downloaded", comment: "")
            $0.flagColorOverride = AppColors.green
        }
    }

    @MainActor
    func onError(_ error: Error) {
        UsageAnalytics.shared.packImportFailed(
            source: .store,
            error: error
        )

        updateItem {
            $0.downloading = false
            $0.playText = NSLocalizedString("failed", comment: "")
            $0.flagColorOverride = AppColors.red
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
