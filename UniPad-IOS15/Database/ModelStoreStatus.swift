import Foundation
import Combine

@MainActor
final class ModelStoreStatus: ObservableObject {
    let isTemporary: Bool

    @Published private(set) var isNoticeDismissed = false

    private let openError: Error?
    private var hasReported = false

    init(openError: Error?) {
        self.openError = openError
        isTemporary = openError != nil
    }

    var showsNotice: Bool {
        isTemporary && !isNoticeDismissed
    }

    func dismissNotice() {
        isNoticeDismissed = true
    }

    func reportIfNeeded(
        to crashlytics: CrashlyticsServiceProtocol
    ) {
        guard let openError, !hasReported else { return }

        hasReported = true
        crashlytics.log(
            "Metadata store could not be opened; running in temporary in-memory mode: \(openError)"
        )
        crashlytics.record(openError)
    }
}
