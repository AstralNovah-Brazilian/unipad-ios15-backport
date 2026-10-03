import Foundation
import os
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "UniPad", category: "AudioSessionGate")

final class AudioSessionGate {

    enum State: Equatable {
        case ready
        case interrupted
        case needsRecovery
        case shutDown
    }
    enum Recovery: Equatable {
        case recovered
        case stillSuppressed
    }
    struct Hooks {
        var isEngineRunning: () -> Bool
        var activateSession: () throws -> Void
        var startEngine: () throws -> Void
    }
    private let hooks: Hooks
    private(set) var state: State = .ready
    private(set) var suppressionLogCount = 0
    private(set) var mediaServicesResetCount = 0
    var isPlaybackSuppressed: Bool { state != .ready }

    init(hooks: Hooks) {
        self.hooks = hooks
    }

    // MARK: - Notifications
    func interruptionBegan() {
        guard state != .shutDown else { return }
        state = .interrupted
        suppressionLogCount = 0
        logSuppressionOnce("audio session interrupted; playback suppressed")
    }
    @discardableResult
    func interruptionEnded(shouldResume: Bool) -> Recovery {
        guard state != .shutDown else { return .stillSuppressed }
        state = .needsRecovery
        guard shouldResume else { return .stillSuppressed }
        return attemptRecovery()
    }
    @discardableResult
    func mediaServicesWereReset() -> Recovery {
        guard state != .shutDown else { return .stillSuppressed }
        mediaServicesResetCount += 1
        state = .needsRecovery
        suppressionLogCount = 0
        logSuppressionOnce("media services were reset; rebuilding the audio session before playing")
        return attemptRecovery()
    }
    @discardableResult
    func configurationChanged() -> Recovery {
        switch state {
        case .shutDown, .interrupted:
            return .stillSuppressed
        case .ready:
            if hooks.isEngineRunning() { return .recovered }
            state = .needsRecovery
            return attemptRecovery()
        case .needsRecovery:
            return attemptRecovery()
        }
    }
    func shutDown() {
        state = .shutDown
    }

    // MARK: - Hot Path
    func ensureEngineRunning() -> Bool {
        switch state {
        case .ready:
            if hooks.isEngineRunning() { return true }
            state = .needsRecovery
            return attemptRecovery() == .recovered
        case .interrupted:
            logSuppressionOnce("pad ignored: the audio session is interrupted")
            return false
        case .needsRecovery:
            return attemptRecovery() == .recovered
        case .shutDown:
            return false
        }
    }
    func playbackFailed(reason: String) {
        guard state != .shutDown else { return }
        state = .needsRecovery
        suppressionLogCount = 0
        logSuppressionOnce("play() failed (\(reason)); the engine will be restarted before the next pad")
    }

    // MARK: - Recovery
    private func attemptRecovery() -> Recovery {
        do {
            try hooks.activateSession()
        } catch {
            logSuppressionOnce("could not activate the audio session: \(error.localizedDescription)")
            return .stillSuppressed
        }
        if !hooks.isEngineRunning() {
            do {
                try hooks.startEngine()
            } catch {
                logSuppressionOnce("could not restart the audio engine: \(error.localizedDescription)")
                return .stillSuppressed
            }
        }
        guard hooks.isEngineRunning() else {
            logSuppressionOnce("the audio engine still does not report running")
            return .stillSuppressed
        }
        state = .ready
        suppressionLogCount = 0
        logger.info("audio engine recovered; playback resumed")
        return .recovered
    }
    private func logSuppressionOnce(_ message: String) {
        guard suppressionLogCount == 0 else { return }
        suppressionLogCount += 1
        logger.error("\(message, privacy: .public)")
    }
}
