import Foundation

struct UnipadSchemaVersion: Equatable, Hashable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

enum UnipadSchemaV1 {
    static let versionIdentifier = UnipadSchemaVersion(1, 0, 0)
    static let models: [Any.Type] = [UnipackEntity.self]
}

enum UnipadMigrationPlan {
    static let schemas: [Any.Type] = [UnipadSchemaV1.self]
    static let stages: [String] = []
}
