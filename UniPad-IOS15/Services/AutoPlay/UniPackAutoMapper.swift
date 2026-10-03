import Foundation
import AVFoundation

protocol UniPackAutoMapperListener: AnyObject {
    func onStart()
    func onGetWorkSize(_ size: Int)
    func onProgress(_ progress: Int)
    func onDone()
    func onException(_ error: Error)
}

final class UniPackAutoMapper {
    private let unipack: UniPackFolder
    private weak var listener: UniPackAutoMapperListener?
    private var task: Task<Void, Never>?

    init(unipack: UniPackFolder, listener: UniPackAutoMapperListener) {
        self.unipack = unipack
        self.listener = listener
    }

    func start() {
        guard task == nil || task?.isCancelled == true else { return }

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            do {
                try await self.run()
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.listener?.onException(error)
                }
            }

            self.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - Mapping

    private func run() async throws {
        await MainActor.run {
            listener?.onStart()
        }

        guard let elements = unipack.autoPlayTable?.elements else {
            throw AutoMapperError.noAutoPlay
        }

        var workSize = 0
        for element in elements {
            try Task.checkCancellation()

            if case .on(let x, let y, let chain, _) = element,
               unipack.autoMapHasSound(c: chain, x: x, y: y)
                || unipack.autoMapHasLed(c: chain, x: x, y: y) {
                workSize += 1
            }
        }

        let totalWorkSize = workSize
        await MainActor.run {
            listener?.onGetWorkSize(totalWorkSize)
        }

        var result: [String] = []
        result.reserveCapacity(elements.count)

        var durationCache: [URL: Int] = [:]
        durationCache.reserveCapacity(totalWorkSize)

        var progress = 0

        for element in elements {
            try Task.checkCancellation()

            switch element {
            case .chain(let chain):
                result.append("c \(chain + 1)")

            case .delay:
                break

            case .on(let x, let y, let chain, let num):
                let hasSound = unipack.autoMapHasSound(c: chain, x: x, y: y)
                let hasLed = unipack.autoMapHasLed(c: chain, x: x, y: y)

                guard hasSound || hasLed else { continue }

                var duration = 0
                if let sound = unipack.autoMapSound(c: chain, x: x, y: y, num: num) {
                    if let cached = durationCache[sound.file] {
                        duration = cached
                    } else {
                        duration = (try? audioDurationMs(url: sound.file)) ?? 0
                        durationCache[sound.file] = duration
                    }
                }

                result.append("t \(x + 1) \(y + 1)")

                if duration > 0 {
                    result.append("d \(duration)")
                }

                progress += 1
                let currentProgress = progress

                await MainActor.run {
                    listener?.onProgress(currentProgress)
                }

            case .off:
                break
            }
        }

        try Task.checkCancellation()

        let newContent = result.joined(separator: "\n") + "\n"
        try backupAndWrite(newContent: newContent)

        try Task.checkCancellation()

        await MainActor.run {
            unipack.reloadAutoPlay()
            listener?.onDone()
        }
    }

    private func audioDurationMs(url: URL) throws -> Int {
        let audioFile = try AVAudioFile(forReading: url)
        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else { return 0 }

        let durationMs = Double(audioFile.length) / sampleRate * 1000
        return max(0, Int(durationMs.rounded()))
    }

    private func backupAndWrite(newContent: String) throws {
        guard let autoPlayFile = unipack.autoPlayFile else {
            throw AutoMapperError.noAutoPlay
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy_MM_dd-HH_mm_ss"

        let backupURL = autoPlayFile
            .deletingLastPathComponent()
            .appendingPathComponent("autoPlay_\(formatter.string(from: Date()))")

        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.copyItem(at: autoPlayFile, to: backupURL)
        }

        try newContent.write(to: autoPlayFile, atomically: true, encoding: .utf8)
    }
}

enum AutoMapperError: LocalizedError {
    case noAutoPlay

    var errorDescription: String? {
        switch self {
        case .noAutoPlay:
            return "AutoPlay file not found"
        }
    }
}
