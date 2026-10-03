import Foundation

final class LaunchpadMK2Driver: BaseMidiDriver {
    static let circleCode: [[Int]] = [
        [11, -80, 104], [11, -80, 105], [11, -80, 106], [11, -80, 107],
        [11, -80, 108], [11, -80, 109], [11, -80, 110], [11, -80, 111],
        [9, -112, 89], [9, -112, 79], [9, -112, 69], [9, -112, 59],
        [9, -112, 49], [9, -112, 39], [9, -112, 29], [9, -112, 19]
    ]

    @inline(__always)
    override func getSignal(cmd: Int, sig: Int, note: Int, velocity: Int) {
        let pressed = velocity != 0

        if cmd == 9 {
            let x = 9 - note / 10
            let y = note % 10

            if (1...8).contains(x), (1...8).contains(y) {
                onPadTouch(x: x - 1, y: y - 1, upDown: pressed, velocity: velocity)
            } else if (1...8).contains(x), y == 9 {
                let chain = x - 1
                onChainTouch(c: chain, upDown: pressed)
                onFunctionKeyTouch(f: chain + 8, upDown: pressed)
            }
            return
        }

        if cmd == 11, (104...111).contains(note) {
            onFunctionKeyTouch(f: note - 104, upDown: pressed)
            return
        }

        onUnknownReceived(cmd: cmd, sig: sig, note: note, velocity: velocity)
    }

    @inline(__always)
    override func sendPadLed(x: Int, y: Int, velocity: Int) {
        guard (0...7).contains(x), (0...7).contains(y) else { return }
        sendSignal(cmd: 9, sig: -112, note: 10 * (8 - x) + y + 1, velocity: velocity)
    }

    @inline(__always)
    override func sendChainLed(c: Int, velocity: Int) {
        guard (0...7).contains(c) else { return }
        sendFunctionKeyLed(f: c + 8, velocity: velocity)
    }

    @inline(__always)
    override func sendFunctionKeyLed(f: Int, velocity: Int) {
        guard Self.circleCode.indices.contains(f) else { return }
        let code = Self.circleCode[f]
        sendSignal(cmd: code[0], sig: code[1], note: code[2], velocity: velocity)
    }

    override func sendClearLed() {
        for x in 0..<8 {
            for y in 0..<8 {
                sendPadLed(x: x, y: y, velocity: 0)
            }
        }
        for f in Self.circleCode.indices {
            sendFunctionKeyLed(f: f, velocity: 0)
        }
    }
}
