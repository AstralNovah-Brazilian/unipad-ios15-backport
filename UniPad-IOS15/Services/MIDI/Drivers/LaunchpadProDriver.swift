import Foundation

final class LaunchpadProDriver: BaseMidiDriver {
    static let circleCode: [[Int]] = [
        [11, -80, 91], [11, -80, 92], [11, -80, 93], [11, -80, 94],
        [11, -80, 95], [11, -80, 96], [11, -80, 97], [11, -80, 98],
        [11, -80, 89], [11, -80, 79], [11, -80, 69], [11, -80, 59],
        [11, -80, 49], [11, -80, 39], [11, -80, 29], [11, -80, 19],
        [11, -80, 8], [11, -80, 7], [11, -80, 6], [11, -80, 5],
        [11, -80, 4], [11, -80, 3], [11, -80, 2], [11, -80, 1],
        [11, -80, 10], [11, -80, 20], [11, -80, 30], [11, -80, 40],
        [11, -80, 50], [11, -80, 60], [11, -80, 70], [11, -80, 80]
    ]

    override func getInitSysEx() -> (messages: [[UInt8]], cableNumber: Int)? {
        (
            messages: [
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x21, 0x00, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x22, 0x00, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0B, 0x63, 0x00, 0x00, 0x00, 0xF7]
            ],
            cableNumber: 0
        )
    }

    override func initialize() {
        guard let initData = getInitSysEx() else { return }
        for cable in 0...1 {
            sendRawSignals(
                messages: initData.messages,
                cableNumber: cable
            )
        }
    }

    @inline(__always)
    override func getSignal(cmd: Int, sig: Int, note: Int, velocity: Int) {
        let pressed = velocity != 0

        if cmd == 9 {
            let x = 9 - note / 10
            let y = note % 10

            if (1...8).contains(x), (1...8).contains(y) {
                onPadTouch(
                    x: x - 1,
                    y: y - 1,
                    upDown: pressed,
                    velocity: velocity
                )
                return
            }
        }

        if cmd == 11, sig == -80 {
            if (91...98).contains(note) {
                onFunctionKeyTouch(
                    f: note - 91,
                    upDown: pressed
                )
                return
            }

            if note == 99 {
                onFunctionKeyTouch(
                    f: 32,
                    upDown: pressed
                )
                return
            }

            if (19...89).contains(note), note % 10 == 9 {
                let chain = 8 - note / 10
                onChainTouch(c: chain, upDown: pressed)
                onFunctionKeyTouch(
                    f: chain + 8,
                    upDown: pressed
                )
                return
            }

            if (1...8).contains(note) {
                let chain = 16 - note
                onChainTouch(c: chain, upDown: pressed)
                onFunctionKeyTouch(
                    f: chain + 8,
                    upDown: pressed
                )
                return
            }

            if (10...80).contains(note), note % 10 == 0 {
                let chain = note / 10 + 15
                onChainTouch(c: chain, upDown: pressed)
                onFunctionKeyTouch(
                    f: chain + 8,
                    upDown: pressed
                )
                return
            }
        }

        onUnknownReceived(
            cmd: cmd,
            sig: sig,
            note: note,
            velocity: velocity
        )
    }

    @inline(__always)
    override func sendPadLed(x: Int, y: Int, velocity: Int) {
        guard (0...7).contains(x), (0...7).contains(y) else { return }
        sendSignal(
            cmd: 9,
            sig: -112,
            note: 10 * (8 - x) + y + 1,
            velocity: velocity
        )
    }

    @inline(__always)
    override func sendChainLed(c: Int, velocity: Int) {
        guard (0...7).contains(c) else { return }
        sendFunctionKeyLed(
            f: c + 8,
            velocity: velocity
        )
    }

    @inline(__always)
    override func sendFunctionKeyLed(f: Int, velocity: Int) {
        if Self.circleCode.indices.contains(f) {
            let code = Self.circleCode[f]
            sendSignal(
                cmd: code[0],
                sig: code[1],
                note: code[2],
                velocity: velocity
            )
            return
        }

        guard f == 32 || f == 99 else { return }

        if velocity == 0 {
            sendRawSignal(
                bytes: [
                    0xF0, 0x00, 0x20, 0x29, 0x02, 0x10,
                    0x0B, 0x63, 0x00, 0x00, 0x00, 0xF7
                ]
            )
            sendRawSignal(
                bytes: [
                    0xF0, 0x00, 0x20, 0x29, 0x02, 0x10,
                    0x0A, 0x63, 0x00, 0xF7
                ]
            )
        } else {
            sendRawSignal(
                bytes: [
                    0xF0, 0x00, 0x20, 0x29, 0x02, 0x10,
                    0x0A, 0x63, UInt8(velocity & 0x7F), 0xF7
                ]
            )
        }
    }

    override func sendClearLed() {
        for x in 0..<8 {
            for y in 0..<8 {
                sendPadLed(
                    x: x,
                    y: y,
                    velocity: 0
                )
            }
        }

        for f in 0...32 {
            sendFunctionKeyLed(
                f: f,
                velocity: 0
            )
        }
    }
}
