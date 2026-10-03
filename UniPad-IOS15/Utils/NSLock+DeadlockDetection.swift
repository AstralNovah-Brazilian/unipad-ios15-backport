import Foundation
import os

private let deadlockLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "UniPad",
    category: "DeadlockDetection"
)

extension NSLock {
    /// Debug builds trap when a lock takes longer than `timeout`.
    /// Release builds log the fault and keep waiting.
    func lockWithDeadlockDetection(
        timeout: TimeInterval = 5,
        file: String = #fileID,
        line: Int = #line
    ) {
        guard !lock(before: Date(timeIntervalSinceNow: timeout)) else { return }

        deadlockLogger.fault(
            "Deadlock suspected: NSLock not acquired within \(timeout)s at \(file):\(line)"
        )

        #if DEBUG
        fatalError(
            "Deadlock detected: NSLock not acquired within \(timeout)s at \(file):\(line)"
        )
        #else
        lock()
        #endif
    }
}
