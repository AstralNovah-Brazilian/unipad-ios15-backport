import Foundation

struct Sound {
    static let noWormhole = -1

    private static let idLock = NSLock()
    private static var nextId = 0

    private static func allocateId() -> Int {
        idLock.lock()
        defer { idLock.unlock() }

        let id = nextId
        nextId &+= 1
        return id
    }

    let file: URL
    let loop: Int
    let wormhole: Int
    var num: Int
    let id: Int

    init(
        file: URL,
        loop: Int,
        wormhole: Int = noWormhole,
        num: Int = 0
    ) {
        self.file = file
        self.loop = loop
        self.wormhole = wormhole
        self.num = num
        id = Self.allocateId()
    }
}
