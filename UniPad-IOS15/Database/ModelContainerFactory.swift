import Foundation

final class ModelContainer {
    let storeURL: URL?
    let isStoredInMemoryOnly: Bool

    init(storeURL: URL?, isStoredInMemoryOnly: Bool) {
        self.storeURL = storeURL
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
    }
}

struct ModelStoreOpenResult {
    let container: ModelContainer
    let persistentStoreError: Error?

    var isTemporary: Bool {
        persistentStoreError != nil
    }
}

enum ModelContainerFactory {
    static func make(storeURL: URL? = nil) -> ModelStoreOpenResult {
        do {
            return ModelStoreOpenResult(
                container: try openPersistent(storeURL: storeURL),
                persistentStoreError: nil
            )
        } catch {
            NSLog(
                "Could not open metadata store, using temporary in-memory mode: %@",
                error.localizedDescription
            )

            return ModelStoreOpenResult(
                container: openInMemory(),
                persistentStoreError: error
            )
        }
    }

    static func openPersistent(storeURL: URL? = nil) throws -> ModelContainer {
        let url = try storeURL ?? defaultStoreURL()
        let directory = url.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        guard FileManager.default.isWritableFile(
            atPath: directory.path
        ) else {
            throw CocoaError(.fileWriteNoPermission)
        }

        return ModelContainer(
            storeURL: url,
            isStoredInMemoryOnly: false
        )
    }

    static func openInMemory() -> ModelContainer {
        ModelContainer(
            storeURL: nil,
            isStoredInMemoryOnly: true
        )
    }

    private static func defaultStoreURL() throws -> URL {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        return base
            .appendingPathComponent("UniPad", isDirectory: true)
            .appendingPathComponent("metadata.store")
    }
}
