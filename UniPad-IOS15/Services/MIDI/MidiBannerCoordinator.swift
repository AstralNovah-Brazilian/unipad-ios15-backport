import SwiftUI
import Combine

@MainActor
final class MidiBannerCoordinator: ObservableObject {
    @Published var isVisible = false
    @Published var message = ""

    private var announceOnNextActive = false
    private var lastAnnouncedDeviceName: String?
    private var dismissTask: Task<Void, Never>?
    private var started = false

    deinit {
        dismissTask?.cancel()
    }

    func start() {
        guard !started else { return }
        started = true
        MidiManager.shared.start()
    }

    func handleConnectionStateChanged(
        _ connected: Bool,
        scenePhase: ScenePhase,
        router: AppRouter
    ) {
        if connected {
            if scenePhase == .active {
                presentIfNeeded(router: router, force: false)
            } else {
                announceOnNextActive = true
            }
            return
        }

        if let deviceName = lastAnnouncedDeviceName, scenePhase == .active {
            presentDisconnected(deviceName: deviceName)
        }

        announceOnNextActive = false
        lastAnnouncedDeviceName = nil
    }

    func handleScenePhaseChanged(
        _ scenePhase: ScenePhase,
        router: AppRouter
    ) {
        switch scenePhase {
        case .active:
            MidiManager.shared.scanForDevices()

            if announceOnNextActive, MidiManager.shared.isConnected {
                presentIfNeeded(router: router, force: true)
            }

            announceOnNextActive = false

        case .inactive, .background:
            if MidiManager.shared.isConnected {
                announceOnNextActive = true
            }

        @unknown default:
            break
        }
    }

    func openMidiPanel(router: AppRouter) {
        dismiss()
        router.navigateToMidiSelectIfNeeded()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard isVisible else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible = false
        }
    }

    private func presentDisconnected(deviceName: String) {
        message = String(
            format: NSLocalizedString("midi_disconnected_banner %@", comment: ""),
            deviceName
        )
        showAndScheduleDismiss()
    }

    private func presentIfNeeded(
        router: AppRouter,
        force: Bool
    ) {
        guard !router.isShowingMidiSelect else { return }

        let deviceName = MidiManager.shared.connectedDeviceName
            ?? NSLocalizedString("launchpadConnecting", comment: "")

        guard force || lastAnnouncedDeviceName != deviceName else { return }

        message = String(
            format: NSLocalizedString("midi_connected_banner %@", comment: ""),
            deviceName
        )

        lastAnnouncedDeviceName = deviceName
        showAndScheduleDismiss()
    }

    private func showAndScheduleDismiss() {
        dismissTask?.cancel()

        if !isVisible {
            withAnimation(.easeInOut(duration: 0.2)) {
                isVisible = true
            }
        }

        dismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}
