import Foundation
import QuartzCore

enum LedRunnerEvent {
    case padOn(x: Int, y: Int, color: Int, velocity: Int)
    case padOff(x: Int, y: Int)
    case chainOn(c: Int, color: Int, velocity: Int)
    case chainOff(c: Int)
}

protocol LedRunnerListener: AnyObject {
    func onLedBatch(_ events: [LedRunnerEvent])
}

final class LedRunner {
    static let circularLedCount = 36

    typealias LedEvent = LedRunnerEvent
    typealias Listener = LedRunnerListener

    private let unipack: UniPack
    private let chain: ChainObserver
    private let loopDelay: TimeInterval
    private weak var listener: Listener?

    private var btnLed: [[Led?]]
    private var cirLed: [Led?]
    private var ledAnimationStates: [LedAnimationState] = []
    private var ledAnimationStatesAdd: [LedAnimationState] = []

    private let lock = NSLock()
    private var pendingLedEventsBuffer: [LedEvent] = []
    private var pendingChainSetsBuffer: [Int] = []
    private var loopTask: Task<Void, Never>?

    var active: Bool { loopTask != nil }

    @inline(__always)
    private func lockState() {
        #if DEBUG
        lock.lockWithDeadlockDetection()
        #else
        lock.lock()
        #endif
    }

    @inline(__always)
    private func unlockState() {
        lock.unlock()
    }

    init(
        unipack: UniPack,
        listener: Listener,
        chain: ChainObserver,
        loopDelay: TimeInterval = 0.004
    ) {
        self.unipack = unipack
        self.listener = listener
        self.chain = chain
        self.loopDelay = loopDelay

        btnLed = Array(
            repeating: Array(
                repeating: nil,
                count: unipack.buttonY
            ),
            count: unipack.buttonX
        )
        cirLed = Array(
            repeating: nil,
            count: Self.circularLedCount
        )

        ledAnimationStates.reserveCapacity(32)
        ledAnimationStatesAdd.reserveCapacity(8)
        pendingLedEventsBuffer.reserveCapacity(64)
        pendingChainSetsBuffer.reserveCapacity(8)
    }

    // MARK: - Lifecycle

    func launch() {
        guard loopTask == nil else { return }

        lockState()
        for state in ledAnimationStates {
            state.delay = 0
        }
        unlockState()

        let intervalNs = UInt64(
            max(loopDelay, 0.001) * 1_000_000_000
        )

        loopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                let start = CACurrentMediaTime()
                self.loop()

                let elapsed = CACurrentMediaTime() - start
                let elapsedNs = UInt64(
                    max(0, elapsed) * 1_000_000_000
                )

                if elapsedNs < intervalNs {
                    try? await Task.sleep(
                        nanoseconds: intervalNs - elapsedNs
                    )
                } else {
                    await Task.yield()
                }
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - Main Loop

    private func loop() {
        pendingLedEventsBuffer.removeAll(keepingCapacity: true)
        pendingChainSetsBuffer.removeAll(keepingCapacity: true)

        lockState()

        let currTime = Self.currentTimeMillis()
        var hasRemovals = false

        for state in ledAnimationStates {
            if state.isPlaying && !state.isShutdown {
                if state.delay == 0 {
                    state.delay = currTime
                }

                guard
                    let animation = state.ledAnimation,
                    !animation.ledEvents.isEmpty
                else {
                    state.isPlaying = false
                    continue
                }

                let events = animation.ledEvents
                let budget = events.count * max(1, animation.loop) + 1
                var processed = 0

                while true {
                    if state.index >= events.count {
                        state.loopProgress += 1
                        state.index = 0
                    }

                    if animation.loop != 0 &&
                        animation.loop <= state.loopProgress {
                        state.isPlaying = false
                        break
                    }

                    processed += 1
                    if processed > budget {
                        state.isPlaying = false
                        break
                    }

                    guard state.delay <= currTime else { break }

                    let event = events[state.index]

                    switch event {
                    case .on(let x, let y, let color, let velocity):
                        if x != -1 {
                            guard isValidPadIndex(x: x, y: y) else {
                                state.index += 1
                                continue
                            }

                            pendingLedEventsBuffer.append(
                                .padOn(
                                    x: x,
                                    y: y,
                                    color: color,
                                    velocity: velocity
                                )
                            )
                            btnLed[x][y] = Led(
                                buttonX: state.buttonX,
                                buttonY: state.buttonY,
                                chain: state.chainAtCreation
                            )
                        } else {
                            guard isValidCircularIndex(y) else {
                                state.index += 1
                                continue
                            }

                            pendingLedEventsBuffer.append(
                                .chainOn(
                                    c: y,
                                    color: color,
                                    velocity: velocity
                                )
                            )
                            cirLed[y] = Led(
                                buttonX: state.buttonX,
                                buttonY: state.buttonY,
                                chain: state.chainAtCreation
                            )
                        }

                    case .off(let x, let y):
                        if x != -1 {
                            guard isValidPadIndex(x: x, y: y) else {
                                state.index += 1
                                continue
                            }

                            if btnLed[x][y]?.isEqual(
                                bx: state.buttonX,
                                by: state.buttonY,
                                chain: state.chainAtCreation
                            ) == true {
                                pendingLedEventsBuffer.append(
                                    .padOff(x: x, y: y)
                                )
                                btnLed[x][y] = nil
                            }
                        } else {
                            guard isValidCircularIndex(y) else {
                                state.index += 1
                                continue
                            }

                            if cirLed[y]?.isEqual(
                                bx: state.buttonX,
                                by: state.buttonY,
                                chain: state.chainAtCreation
                            ) == true {
                                pendingLedEventsBuffer.append(
                                    .chainOff(c: y)
                                )
                                cirLed[y] = nil
                            }
                        }

                    case .delay(let delay):
                        state.delay += Int64(delay)

                    case .chain(let chainValue):
                        pendingChainSetsBuffer.append(chainValue)
                    }

                    state.index += 1
                }
            } else if state.isShutdown {
                clearLightsOwned(by: state)
                state.remove = true
                hasRemovals = true
            } else {
                state.remove = true
                hasRemovals = true
            }
        }

        if !ledAnimationStatesAdd.isEmpty {
            ledAnimationStates.append(
                contentsOf: ledAnimationStatesAdd
            )
            ledAnimationStatesAdd.removeAll(
                keepingCapacity: true
            )
        }

        if hasRemovals {
            ledAnimationStates.removeAll {
                $0.remove
            }
        }

        let chainSets = pendingChainSetsBuffer
        let ledEvents = pendingLedEventsBuffer

        unlockState()

        if !chainSets.isEmpty {
            let chain = self.chain
            Task { @MainActor in
                for value in chainSets {
                    chain.setValue(value)
                }
            }
        }

        if !ledEvents.isEmpty {
            listener?.onLedBatch(ledEvents)
        }
    }

    private func clearLightsOwned(by state: LedAnimationState) {
        for x in btnLed.indices {
            for y in btnLed[x].indices {
                if btnLed[x][y]?.isEqual(
                    bx: state.buttonX,
                    by: state.buttonY,
                    chain: state.chainAtCreation
                ) == true {
                    pendingLedEventsBuffer.append(
                        .padOff(x: x, y: y)
                    )
                    btnLed[x][y] = nil
                }
            }
        }

        for y in cirLed.indices {
            if cirLed[y]?.isEqual(
                bx: state.buttonX,
                by: state.buttonY,
                chain: state.chainAtCreation
            ) == true {
                pendingLedEventsBuffer.append(
                    .chainOff(c: y)
                )
                cirLed[y] = nil
            }
        }
    }

    // MARK: - Event Control

    func isEventExist(
        x: Int,
        y: Int,
        chain: Int
    ) -> Bool {
        lockState()
        defer { unlockState() }

        return ledAnimationStates.contains {
            $0.isEqual(
                bx: x,
                by: y,
                chain: chain
            )
        }
    }

    func isEventExist(x: Int, y: Int) -> Bool {
        lockState()
        defer { unlockState() }

        return ledAnimationStates.contains {
            $0.buttonX == x && $0.buttonY == y
        }
    }

    func eventOn(x: Int, y: Int) {
        guard active else { return }

        let currentChain = chain.value

        let state = LedAnimationState(
            buttonX: x,
            buttonY: y,
            chainValue: currentChain,
            unipack: unipack
        )

        lockState()
        defer { unlockState() }

        for existing in ledAnimationStates where existing.isEqual(
            bx: x,
            by: y,
            chain: currentChain
        ) {
            existing.isShutdown = true
        }

        if state.noError {
            ledAnimationStatesAdd.append(state)
        }
    }

    func eventOff(x: Int, y: Int) {
        guard active else { return }

        let currentChain = chain.value

        lockState()
        defer { unlockState() }

        for state in ledAnimationStates where state.isEqual(
            bx: x,
            by: y,
            chain: currentChain
        ) {
            if state.ledAnimation?.loop == 0 {
                state.isShutdown = true
            }
        }
    }

    func eventOffAll(x: Int, y: Int) {
        lockState()
        defer { unlockState() }

        for state in ledAnimationStates where
            state.buttonX == x &&
            state.buttonY == y {
            if state.ledAnimation?.loop == 0 {
                state.isShutdown = true
            }
        }
    }

    // MARK: - Helpers

    private struct Led {
        let buttonX: Int
        let buttonY: Int
        let chain: Int

        @inline(__always)
        func isEqual(
            bx: Int,
            by: Int,
            chain: Int
        ) -> Bool {
            buttonX == bx &&
            buttonY == by &&
            self.chain == chain
        }
    }

    private final class LedAnimationState {
        let buttonX: Int
        let buttonY: Int
        let chainAtCreation: Int
        var index = 0
        var delay: Int64 = 0
        var isPlaying = true
        var isShutdown = false
        var remove = false
        var loopProgress = 0
        let ledAnimation: LedAnimation?

        var noError: Bool {
            ledAnimation != nil
        }

        @inline(__always)
        func isEqual(
            bx: Int,
            by: Int,
            chain: Int
        ) -> Bool {
            buttonX == bx &&
            buttonY == by &&
            chainAtCreation == chain
        }

        init(
            buttonX: Int,
            buttonY: Int,
            chainValue: Int,
            unipack: UniPack
        ) {
            self.buttonX = buttonX
            self.buttonY = buttonY
            self.chainAtCreation = chainValue
            self.ledAnimation = unipack.ledGet(
                c: chainValue,
                x: buttonX,
                y: buttonY
            )
            unipack.ledPush(
                c: chainValue,
                x: buttonX,
                y: buttonY
            )
        }
    }

    @inline(__always)
    private static func currentTimeMillis() -> Int64 {
        Int64(CACurrentMediaTime() * 1000)
    }

    @inline(__always)
    private func isValidPadIndex(
        x: Int,
        y: Int
    ) -> Bool {
        x >= 0 &&
        x < btnLed.count &&
        y >= 0 &&
        y < btnLed[x].count
    }

    @inline(__always)
    private func isValidCircularIndex(_ y: Int) -> Bool {
        y >= 0 && y < cirLed.count
    }
}
