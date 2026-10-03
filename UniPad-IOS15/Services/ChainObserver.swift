import Foundation

final class ChainObserver {
    var range: ClosedRange<Int> = Int.min...Int.max

    private let lock = NSLock()
    private var _value = 0
    private var observers: [
        (id: UUID, handler: (_ curr: Int, _ prev: Int) -> Void)
    ] = []

    private(set) var value: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            _value = newValue
            lock.unlock()
        }
    }

    func setValue(_ newValue: Int) {
        let clamped = min(
            max(newValue, range.lowerBound),
            range.upperBound
        )

        lock.lock()
        let previous = _value

        guard previous != clamped else {
            lock.unlock()
            return
        }

        _value = clamped
        let snapshot = observers
        lock.unlock()

        for observer in snapshot {
            observer.handler(clamped, previous)
        }
    }

    func refresh(curr: Int? = nil, prev: Int? = nil) {
        lock.lock()
        let current = _value
        let snapshot = observers
        lock.unlock()

        let currentValue = curr ?? current
        let previousValue = prev ?? current

        for observer in snapshot {
            observer.handler(currentValue, previousValue)
        }
    }

    @discardableResult
    func addObserver(
        _ observer: @escaping (_ curr: Int, _ prev: Int) -> Void
    ) -> UUID {
        let id = UUID()

        lock.lock()
        observers.append(
            (id: id, handler: observer)
        )
        lock.unlock()

        return id
    }

    func removeObserver(id: UUID) {
        lock.lock()

        if let index = observers.firstIndex(
            where: { $0.id == id }
        ) {
            observers.remove(at: index)
        }

        lock.unlock()
    }

    func clearObservers() {
        lock.lock()
        observers.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
