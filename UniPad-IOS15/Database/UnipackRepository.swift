import Foundation

@MainActor
final class UnipackRepository {
    enum RepositoryError: LocalizedError {
        case applicationSupportUnavailable
        case invalidStore

        var errorDescription: String? {
            switch self {
            case .applicationSupportUnavailable:
                return "Could not access the Application Support directory."
            case .invalidStore:
                return "The UniPack metadata store is invalid."
            }
        }
    }

    private struct Store: Codable {
        var version: Int
        var entities: [UnipackEntity]

        init(version: Int = 1, entities: [UnipackEntity] = []) {
            self.version = version
            self.entities = entities
        }
    }

    static let shared = UnipackRepository()

    private let fileManager: FileManager
    private let storeURL: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var entitiesByID: [String: UnipackEntity] = [:]
    private var loaded = false

    init(
        fileManager: FileManager = .default,
        storeURL: URL? = nil
    ) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()

        if let storeURL {
            self.storeURL = storeURL
        } else if let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            self.storeURL = baseURL
                .appendingPathComponent("UniPad", isDirectory: true)
                .appendingPathComponent("unipack_metadata.json")
        } else {
            self.storeURL = nil
        }
    }

    // MARK: - Public API

    func find(id: String) throws -> UnipackEntity? {
        try ensureLoaded()
        return entitiesByID[id]
    }

    @discardableResult
    func getOrCreate(id: String) throws -> UnipackEntity {
        try ensureLoaded()

        if let existing = entitiesByID[id] {
            return existing
        }

        let entity = UnipackEntity.create(id: id)
        entitiesByID[id] = entity

        do {
            try save()
            return entity
        } catch {
            entitiesByID.removeValue(forKey: id)
            throw error
        }
    }

    func toggleBookmark(id: String) throws {
        try ensureLoaded()
        guard let entity = entitiesByID[id] else { return }

        entity.bookmark.toggle()

        do {
            try save()
        } catch {
            entity.bookmark.toggle()
            throw error
        }
    }

    func totalOpenCount() throws -> Int64 {
        try ensureLoaded()
        return entitiesByID.values.reduce(into: Int64(0)) {
            $0 &+= $1.openCount
        }
    }

    func openCount(id: String) throws -> Int64 {
        try find(id: id)?.openCount ?? 0
    }

    func lastOpenedAt(id: String) throws -> Date? {
        try find(id: id)?.lastOpenedAt
    }

    func recordOpen(id: String) throws {
        try ensureLoaded()
        guard let entity = entitiesByID[id] else { return }

        let previousCount = entity.openCount
        let previousDate = entity.lastOpenedAt

        entity.openCount &+= 1
        entity.lastOpenedAt = Date()

        do {
            try save()
        } catch {
            entity.openCount = previousCount
            entity.lastOpenedAt = previousDate
            throw error
        }
    }

    // MARK: - Persistence

    private func ensureLoaded() throws {
        guard !loaded else { return }
        guard let storeURL else {
            throw RepositoryError.applicationSupportUnavailable
        }

        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard fileManager.fileExists(atPath: storeURL.path) else {
            loaded = true
            return
        }

        let data = try Data(contentsOf: storeURL)
        guard !data.isEmpty else {
            loaded = true
            return
        }

        let store: Store
        do {
            store = try decoder.decode(Store.self, from: data)
        } catch {
            throw RepositoryError.invalidStore
        }

        guard store.version == 1 else {
            throw RepositoryError.invalidStore
        }

        var loadedEntities: [String: UnipackEntity] = [:]
        loadedEntities.reserveCapacity(store.entities.count)

        for entity in store.entities {
            loadedEntities[entity.id] = entity
        }

        entitiesByID = loadedEntities
        loaded = true
    }

    private func save() throws {
        guard let storeURL else {
            throw RepositoryError.applicationSupportUnavailable
        }

        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let entities = entitiesByID.values.sorted {
            let comparison = $0.id.localizedStandardCompare($1.id)
            if comparison == .orderedSame {
                return $0.id < $1.id
            }
            return comparison == .orderedAscending
        }

        let data = try encoder.encode(
            Store(entities: entities)
        )

        try data.write(
            to: storeURL,
            options: .atomic
        )
    }
}
