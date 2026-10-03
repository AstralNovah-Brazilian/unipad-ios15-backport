import AVFoundation
import Foundation
import os
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "UniPad", category: "SoundEngine")
protocol SoundEngineLoadingListener: AnyObject {
    func onStart(soundCount: Int)
    func onProgressTick()
    func onEnd()
    func onException(_ error: Error)
}
final class SoundEngine {
    static let maxStreams = 64
    private static func recommendedPlayerCount() -> Int {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        if cores <= 3 { return 32 }
        if cores <= 6 { return 48 }
        return maxStreams
    }
    private let engine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "com.unipad.SoundEngine.playback", qos: .userInteractive)
    private let lifecycleLock = NSLock()
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var destroyed = false
    private let isUsable: Bool
    private var observerTokens: [NSObjectProtocol] = []
    private let playbackFormat: AVAudioFormat
    private var playerNodes: [AVAudioPlayerNode] = []
    private var nodeIsLoop: [Bool] = []
    private var nodeStartOrder: [Int] = []
    private var nodePlayID: [Int]
    private var stopID: [[[Int]]]
    private var startCounter = 0
    private var nextPlayID = 1
    private let playerCount: Int
    private let unipack: UniPack
    private let chain: ChainObserver
    private var loadingListener: LoadingListener?
    private let gate: AudioSessionGate
    private let repeatScheduler = FiniteRepeatScheduler()
    var isPlaybackSuppressed: Bool { gate.isPlaybackSuppressed }
    private(set) var playsStarted = 0
    var repeatedBuffersScheduled: Int { repeatScheduler.buffersScheduled }
    typealias LoadingListener = SoundEngineLoadingListener
    init(unipack: UniPack, chain: ChainObserver, loadingListener: LoadingListener) {
        self.unipack = unipack
        self.chain = chain
        self.loadingListener = loadingListener
        let engine = self.engine
        self.gate = AudioSessionGate(
            hooks: AudioSessionGate.Hooks(
                isEngineRunning: { engine.isRunning },
                activateSession: { try Self.configureSession() },
                startEngine: { try engine.start() }
            )
        )
        #if canImport(UIKit)
        do {
            try Self.configureSession()
        } catch {
            self.playbackFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            self.playerCount = 1
            self.stopID = []
            self.nodePlayID = []
            self.isUsable = false
            loadingListener.onException(error)
            return
        }
        #endif
        self.playbackFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        self.playerCount = Self.recommendedPlayerCount()
        self.isUsable = true
        stopID = Array(
            repeating: Array(
                repeating: Array(repeating: 0, count: unipack.buttonY),
                count: unipack.buttonX
            ),
            count: unipack.chain
        )
        nodePlayID = Array(repeating: 0, count: playerCount)
        nodeIsLoop = Array(repeating: false, count: playerCount)
        nodeStartOrder = Array(repeating: 0, count: playerCount)
        playerNodes.reserveCapacity(playerCount)
        for _ in 0..<playerCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: playbackFormat)
            playerNodes.append(node)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            logger.error("Failed to start AVAudioEngine: \(error.localizedDescription, privacy: .public)")
            loadingListener.onException(error)
            return
        }
        installObservers()
        let table = unipack.soundTable
        let soundCount = Self.countSounds(
            table: table,
            chainCount: unipack.chain,
            buttonX: unipack.buttonX,
            buttonY: unipack.buttonY
        )
        loadingListener.onStart(soundCount: soundCount)
        loadBuffers(table: table, soundCount: soundCount)
    }
    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Loading
    private static func countSounds(
        table: [[[Deque<Sound>?]]]?,
        chainCount: Int,
        buttonX: Int,
        buttonY: Int
    ) -> Int {
        guard let table = table else { return 0 }
        var count = 0
        for c in 0..<min(chainCount, table.count) {
            for x in 0..<min(buttonX, table[c].count) {
                for y in 0..<min(buttonY, table[c][x].count) {
                    count += table[c][x][y]?.count ?? 0
                }
            }
        }
        return count
    }
    private func loadBuffers(table: [[[Deque<Sound>?]]]?, soundCount: Int) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            guard let table = table else {
                DispatchQueue.main.async { [weak self] in
                    self?.loadingListener?.onEnd()
                }
                return
            }
            var byFile: [URL: AVAudioPCMBuffer] = [:]
            byFile.reserveCapacity(soundCount)
            var loaded = 0
            var firstError: Error?
            outer: for c in 0..<min(self.unipack.chain, table.count) {
                for x in 0..<min(self.unipack.buttonX, table[c].count) {
                    for y in 0..<min(self.unipack.buttonY, table[c][x].count) {
                        guard let sounds = table[c][x][y] else { continue }
                        for sound in sounds {
                            if self.isDestroyed() { break outer }
                            do {
                                let playBuffer: AVAudioPCMBuffer
                                if let cached = byFile[sound.file] {
                                    playBuffer = cached
                                } else {
                                    let raw = try Self.loadAudioBuffer(from: sound.file)
                                    playBuffer = try Self.convertIfNeeded(raw, to: self.playbackFormat)
                                    byFile[sound.file] = playBuffer
                                }
                                self.audioQueue.sync {
                                    guard !self.isDestroyed() else { return }
                                    self.buffers[sound.id] = playBuffer
                                }
                                loaded += 1
                            } catch {
                                if firstError == nil { firstError = error }
                                logger.error(
                                    "Sound load failed: \(sound.file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                                )
                            }
                            DispatchQueue.main.async { [weak self] in
                                self?.loadingListener?.onProgressTick()
                            }
                        }
                    }
                }
            }
            guard !self.isDestroyed() else { return }
            if loaded == 0, let firstError = firstError {
                DispatchQueue.main.async { [weak self] in
                    self?.loadingListener?.onException(firstError)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.loadingListener?.onEnd()
                }
            }
        }
    }
    private func isDestroyed() -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return destroyed
    }
    private static func loadAudioBuffer(from url: URL) throws -> AVAudioPCMBuffer {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw SoundEngineError.bufferCreationFailed
        }
        try audioFile.read(into: buffer)
        return buffer
    }
    private static func convertIfNeeded(_ input: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if input.format.sampleRate == targetFormat.sampleRate,
           input.format.channelCount == targetFormat.channelCount,
           input.format.commonFormat == targetFormat.commonFormat,
           input.format.isInterleaved == targetFormat.isInterleaved {
            return input
        }
        guard let converter = AVAudioConverter(from: input.format, to: targetFormat) else {
            throw SoundEngineError.converterCreationFailed
        }
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw SoundEngineError.bufferCreationFailed
        }
        var consumed = false
        var convertError: NSError?
        let status = converter.convert(to: output, error: &convertError) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }
        if let convertError = convertError { throw convertError }
        guard status == .haveData || status == .endOfStream else {
            throw SoundEngineError.conversionFailed
        }
        return output
    }

    // MARK: - Voice Pool
    private func acquirePlayerNode() -> (AVAudioPlayerNode, Int) {
        let index: Int
        if let idle = nodePlayID.firstIndex(of: 0) {
            index = idle
        } else {
            var victim: Int?
            for i in nodePlayID.indices where !nodeIsLoop[i] {
                if victim == nil || nodeStartOrder[i] < nodeStartOrder[victim!] {
                    victim = i
                }
            }
            if victim == nil {
                victim = nodePlayID.indices.min {
                    nodeStartOrder[$0] < nodeStartOrder[$1]
                }
            }
            index = victim ?? 0
        }
        let node = playerNodes[index]
        repeatScheduler.stop(node)
        nodePlayID[index] = 0
        nodeIsLoop[index] = false
        return (node, index)
    }
    private func stopByPlayID(_ playID: Int) {
        guard playID > 0, let index = nodePlayID.firstIndex(of: playID) else { return }
        repeatScheduler.stop(playerNodes[index])
        nodePlayID[index] = 0
        nodeIsLoop[index] = false
    }

    // MARK: - Session
    #if canImport(UIKit)
    private static func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.004)
        try session.setActive(true)
    }
    #else
    private static func configureSession() throws {}
    #endif
    private func installObservers() {
        #if canImport(UIKit)
        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleInterruption(notification)
            }
        )
        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleMediaServicesReset()
            }
        )
        #endif
        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { [weak self] _ in
                self?.gate.configurationChanged()
            }
        )
    }
    #if canImport(UIKit)
    func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            gate.interruptionBegan()
            releaseAllVoices()
        case .ended:
            let optionsValue = (info[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            gate.interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            gate.interruptionBegan()
            releaseAllVoices()
        }
    }
    func handleMediaServicesReset() {
        releaseAllVoices()
        gate.mediaServicesWereReset()
    }
    #endif
    private func releaseAllVoices() {
        audioQueue.sync {
            releaseAllVoicesOnAudioQueue()
        }
    }
    private func releaseAllVoicesOnAudioQueue() {
        let nodes = playerNodes
        _ = runCatchingObjCException {
            for node in nodes { repeatScheduler.stop(node) }
        }
        for index in nodePlayID.indices {
            nodePlayID[index] = 0
            nodeIsLoop[index] = false
        }
        for c in stopID.indices {
            for x in stopID[c].indices {
                for y in stopID[c][x].indices {
                    stopID[c][x][y] = 0
                }
            }
        }
    }

    // MARK: - Playback
    func soundOn(x: Int, y: Int) {
        guard isUsable else { return }
        let c = chain.value
        guard
            c >= 0, c < unipack.chain,
            x >= 0, x < unipack.buttonX,
            y >= 0, y < unipack.buttonY
        else { return }
        guard gate.ensureEngineRunning() else { return }
        audioQueue.async { [weak self] in
            self?.soundOnAudioQueue(x: x, y: y, chainIndex: c)
        }
    }
    private func soundOnAudioQueue(x: Int, y: Int, chainIndex c: Int) {
        guard
            !isDestroyed(),
            stopID.indices.contains(c),
            stopID[c].indices.contains(x),
            stopID[c][x].indices.contains(y)
        else { return }
        stopByPlayID(stopID[c][x][y])
        guard
            let sound = unipack.soundGet(c: c, x: x, y: y),
            let buffer = buffers[sound.id]
        else { return }
        let (node, nodeIndex) = acquirePlayerNode()
        let playID = nextPlayIdentifier()
        stopID[c][x][y] = playID
        nodePlayID[nodeIndex] = playID
        nodeIsLoop[nodeIndex] = sound.loop == -1
        startCounter &+= 1
        nodeStartOrder[nodeIndex] = startCounter
        let release: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.audioQueue.async { [weak self] in
                guard
                    let self = self,
                    self.nodePlayID.indices.contains(nodeIndex),
                    self.nodePlayID[nodeIndex] == playID
                else { return }
                self.nodePlayID[nodeIndex] = 0
                self.nodeIsLoop[nodeIndex] = false
            }
        }
        var repeatFailure: String?
        let failure = runCatchingObjCException {
            if node.engine == nil {
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
            }
            if sound.loop == -1 {
                node.scheduleBuffer(buffer, at: nil, options: .loops)
            } else if sound.loop > 0 {
                repeatFailure = repeatScheduler.start(buffer, node: node, totalPlays: sound.loop + 1) { [weak self] failure in
                    guard let self = self else { return }
                    self.audioQueue.async { [weak self] in
                        guard let self = self,
                              self.nodePlayID.indices.contains(nodeIndex),
                              self.nodePlayID[nodeIndex] == playID else { return }
                        self.nodePlayID[nodeIndex] = 0
                        self.nodeIsLoop[nodeIndex] = false
                        if let failure = failure { self.gate.playbackFailed(reason: failure) }
                    }
                }
            } else {
                node.scheduleBuffer(buffer, at: nil, options: []) { release() }
            }
            if sound.loop <= 0 { node.play() }
        }
        if let failure = failure ?? repeatFailure {
            logger.error("play() raised: \(failure, privacy: .public)")
            repeatScheduler.stop(node)
            nodePlayID[nodeIndex] = 0
            nodeIsLoop[nodeIndex] = false
            stopID[c][x][y] = 0
            gate.playbackFailed(reason: failure)
            return
        }
        playsStarted &+= 1
        unipack.soundPush(c: c, x: x, y: y)
        if sound.wormhole != Sound.noWormhole {
            let wormhole = sound.wormhole
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self = self else { return }
                self.chain.setValue(wormhole)
            }
        }
    }
    private func nextPlayIdentifier() -> Int {
        if nextPlayID == Int.max {
            nextPlayID = 1
        }
        let id = nextPlayID
        nextPlayID += 1
        return id
    }
    func soundOff(x: Int, y: Int) {
        guard isUsable else { return }
        let c = chain.value
        guard
            c >= 0, c < unipack.chain,
            x >= 0, x < unipack.buttonX,
            y >= 0, y < unipack.buttonY
        else { return }
        audioQueue.async { [weak self] in
            guard
                let self = self,
                !self.isDestroyed(),
                self.stopID.indices.contains(c),
                self.stopID[c].indices.contains(x),
                self.stopID[c][x].indices.contains(y),
                let sound = self.unipack.soundGet(c: c, x: x, y: y),
                sound.loop == -1
            else { return }
            self.stopByPlayID(self.stopID[c][x][y])
            self.stopID[c][x][y] = 0
        }
    }

    // MARK: - Lifecycle
    func destroy() {
        gate.shutDown()
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
        lifecycleLock.lock()
        guard !destroyed else {
            lifecycleLock.unlock()
            return
        }
        destroyed = true
        lifecycleLock.unlock()
        audioQueue.sync {
            releaseAllVoicesOnAudioQueue()
            engine.stop()
            for node in playerNodes {
                repeatScheduler.stop(node)
                engine.detach(node)
            }
            playerNodes.removeAll(keepingCapacity: false)
            buffers.removeAll(keepingCapacity: false)
        }
        loadingListener = nil
    }
    enum SoundEngineError: Error {
        case bufferCreationFailed
        case converterCreationFailed
        case conversionFailed
    }
}

final class FiniteRepeatScheduler {
    private let queue = DispatchQueue(label: "UniPad.finiteRepeats", qos: .userInteractive)
    private var voices: [ObjectIdentifier: Voice] = [:]
    private var scheduled = 0
    var buffersScheduled: Int { queue.sync { scheduled } }
    private final class Voice {
        let node: AVAudioPlayerNode
        let buffer: AVAudioPCMBuffer
        var remaining: Int
        let completion: (String?) -> Void
        init(node: AVAudioPlayerNode, buffer: AVAudioPCMBuffer, totalPlays: Int, completion: @escaping (String?) -> Void) {
            self.node = node
            self.buffer = buffer
            remaining = totalPlays
            self.completion = completion
        }
    }
    func start(_ buffer: AVAudioPCMBuffer, node: AVAudioPlayerNode, totalPlays: Int, completion: @escaping (String?) -> Void) -> String? {
        queue.sync {
            let voice = Voice(node: node, buffer: buffer, totalPlays: totalPlays, completion: completion)
            let key = ObjectIdentifier(node)
            voices[key] = voice
            let seconds = Double(max(1, buffer.frameLength)) / buffer.format.sampleRate
            let lookahead = min(128, max(2, Int(ceil(0.1 / seconds))))
            let failure = runCatchingObjCException {
                for _ in 0..<min(totalPlays, lookahead) { schedule(voice) }
                node.play()
            }
            if failure != nil { voices.removeValue(forKey: key) }
            return failure
        }
    }
    func stop(_ node: AVAudioPlayerNode) {
        queue.sync {
            voices.removeValue(forKey: ObjectIdentifier(node))
            _ = runCatchingObjCException { node.stop() }
        }
    }
    private func schedule(_ voice: Voice) {
        voice.remaining -= 1
        let final = voice.remaining == 0
        scheduled += 1
        voice.node.scheduleBuffer(
            voice.buffer,
            at: nil,
            options: [],
            completionCallbackType: final ? .dataPlayedBack : .dataConsumed
        ) { [weak self, weak voice] _ in
            self?.queue.async { [weak self, weak voice] in
                guard let self = self, let voice = voice else { return }
                let key = ObjectIdentifier(voice.node)
                guard self.voices[key] === voice else { return }
                if final {
                    self.voices.removeValue(forKey: key)
                    voice.completion(nil)
                } else if voice.remaining > 0 {
                    if let failure = runCatchingObjCException({ self.schedule(voice) }) {
                        self.voices.removeValue(forKey: key)
                        _ = runCatchingObjCException { voice.node.stop() }
                        voice.completion(failure)
                    }
                }
            }
        }
    }
}
