import Foundation
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "UniPad",
    category: "UniPack"
)

class UniPack: Equatable, Hashable {
    private var errors: [String] = []

    var errorDetail: String? {
        errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    var criticalError = false
    var id: String { fatalError("Subclasses must override id") }

    var title = ""
    var producerName = ""
    var buttonX = 0
    var buttonY = 0
    var chain = 0
    var squareButton = true
    var website: String?

    var soundCount = 0
    var ledTableCount = 0

    let tableLock = NSLock()
    var soundTable: [[[Deque<Sound>?]]]?
    var ledAnimationTable: [[[Deque<LedAnimation>?]]]?
    var autoPlayTable: AutoPlay?

    var keyLedExist: Bool { false }
    var autoPlayExist: Bool { false }

    func lastModified() -> TimeInterval {
        fatalError("Subclasses must override")
    }

    var detailLoaded = false

    func loadInfo() -> UniPack {
        fatalError("Subclasses must override")
    }

    func loadDetail() -> UniPack {
        fatalError("Subclasses must override")
    }

    func loadDetailWithProgress(
        onPhase: (String, Int, Int) -> Void
    ) -> UniPack {
        loadDetail()
    }

    func checkFile() {
        fatalError("Subclasses must override")
    }

    func delete() {
        fatalError("Subclasses must override")
    }

    func getPathString() -> String {
        fatalError("Subclasses must override")
    }

    func getByteSize() -> Int64 {
        fatalError("Subclasses must override")
    }

    private(set) var loaded = false

    @discardableResult
    func load() -> UniPack {
        if !loaded {
            checkFile()
        }

        loadInfo()
        loaded = true
        return self
    }

    // MARK: - Circular Queue Operations

    func soundGet(c: Int, x: Int, y: Int) -> Sound? {
        tableLock.lock()
        defer { tableLock.unlock() }

        guard let sounds = soundTable?[safe: c]?[safe: x]?[safe: y] ?? nil
        else {
            return nil
        }

        return sounds.first
    }

    func soundGet(c: Int, x: Int, y: Int, num: Int) -> Sound? {
        tableLock.lock()
        defer { tableLock.unlock() }

        guard let sounds = soundTable?[safe: c]?[safe: x]?[safe: y] ?? nil,
              !sounds.isEmpty
        else {
            return nil
        }

        let index = Self.normalizedIndex(num, count: sounds.count)
        return sounds[index]
    }

    func soundPush(c: Int, x: Int, y: Int) {
        tableLock.lock()
        defer { tableLock.unlock() }

        guard var sounds = soundTable?[safe: c]?[safe: x]?[safe: y] ?? nil,
              !sounds.isEmpty
        else {
            return
        }

        let item = sounds.removeFirst()
        sounds.append(item)
        soundTable?[c][x][y] = sounds
    }

    func soundPush(c: Int, x: Int, y: Int, num: Int) {
        tableLock.lock()
        defer { tableLock.unlock() }

        guard var sounds = soundTable?[safe: c]?[safe: x]?[safe: y] ?? nil,
              !sounds.isEmpty
        else {
            return
        }

        let targetNum = Self.normalizedIndex(num, count: sounds.count)
        guard sounds.first?.num != targetNum else { return }

        for _ in 0..<sounds.count {
            let item = sounds.removeFirst()
            sounds.append(item)

            if sounds.first?.num == targetNum {
                break
            }
        }

        soundTable?[c][x][y] = sounds
    }

    func ledGet(c: Int, x: Int, y: Int) -> LedAnimation? {
        tableLock.lock()
        defer { tableLock.unlock() }

        guard let leds = ledAnimationTable?[safe: c]?[safe: x]?[safe: y] ?? nil
        else {
            return nil
        }

        return leds.first
    }

    func ledPush(c: Int, x: Int, y: Int) {
        tableLock.lock()
        defer { tableLock.unlock() }

        guard var leds = ledAnimationTable?[safe: c]?[safe: x]?[safe: y] ?? nil,
              !leds.isEmpty
        else {
            return
        }

        let item = leds.removeFirst()
        leds.append(item)
        ledAnimationTable?[c][x][y] = leds
    }

    func ledPush(c: Int, x: Int, y: Int, num: Int) {
        tableLock.lock()
        defer { tableLock.unlock() }

        guard var leds = ledAnimationTable?[safe: c]?[safe: x]?[safe: y] ?? nil,
              !leds.isEmpty
        else {
            return
        }

        let targetNum = Self.normalizedIndex(num, count: leds.count)
        guard leds.first?.num != targetNum else { return }

        for _ in 0..<leds.count {
            let item = leds.removeFirst()
            leds.append(item)

            if leds.first?.num == targetNum {
                break
            }
        }

        ledAnimationTable?[c][x][y] = leds
    }

    private static func normalizedIndex(_ index: Int, count: Int) -> Int {
        let value = index % count
        return value >= 0 ? value : value + count
    }

    // MARK: - Error Management

    func addErr(_ content: String) {
        errors.append(content)
        logger.error("\(content, privacy: .public)")
    }

    func infoString() -> String {
        let sizeMB = String(
            format: "%.2f",
            Double(getByteSize()) / 1_048_576.0
        )

        return """
        Title : \(title)
        Producer : \(producerName)
        Pad Size : \(buttonX) x \(buttonY)
        Chain : \(chain)
        File Size : \(sizeMB) MB
        """
    }

    static func == (lhs: UniPack, rhs: UniPack) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var description: String {
        "UniPack(id=\(id))"
    }
}

// MARK: - Deque

struct Deque<Element>: Sequence {
    private var storage: [Element] = []
    private var head = 0

    var isEmpty: Bool {
        count == 0
    }

    var count: Int {
        storage.count - head
    }

    var first: Element? {
        guard head < storage.count else { return nil }
        return storage[head]
    }

    subscript(index: Int) -> Element {
        get {
            precondition(index >= 0 && index < count, "Deque index out of range")
            return storage[head + index]
        }
        set {
            precondition(index >= 0 && index < count, "Deque index out of range")
            storage[head + index] = newValue
        }
    }

    mutating func append(_ element: Element) {
        storage.append(element)
    }

    @discardableResult
    mutating func removeFirst() -> Element {
        precondition(!isEmpty, "Can't removeFirst from an empty Deque")

        let element = storage[head]
        head += 1

        if head >= 32 && head * 2 >= storage.count {
            storage.removeFirst(head)
            head = 0
        }

        return element
    }

    func makeIterator() -> IndexingIterator<[Element]> {
        Array(storage[head...]).makeIterator()
    }
}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
