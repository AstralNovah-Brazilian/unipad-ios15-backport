import Foundation

/// Runs `body` and returns the Objective-C exception description, or `nil` when no exception occurs.
@inline(__always)
func runCatchingObjCException(_ body: () -> Void) -> String? {
    guard let exception = UPRunCatchingObjCException(body) else { return nil }
    return "\(exception.name.rawValue): \(exception.reason ?? "no reason given")"
}
