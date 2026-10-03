import Foundation

final class LaunchpadCoreCFWDriver: BaseMidiDriver {
    private static let channelLed = 0
    private static let statusNoteOn = 0x90 | channelLed
    private static let cinNoteOn = 0x09

    override func getInitSysEx() -> (messages: [[UInt8]], cableNumber: Int)? {
        (
            messages: [
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x22, 0x03, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x10, 0x0E, 0x00, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x18, 0x22, 0x01, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x18, 0x0E, 0x00, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C, 0x00, 0x7E, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C, 0x12, 0x01, 0x01, 0x01, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x00, 0x7E, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x12, 0x01, 0x00, 0x01, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x00, 0x14, 0x00, 0x00, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0E, 0x0E, 0x00, 0xF7]
            ],
            cableNumber: 0
        )
    }

    override func initialize() {
        guard let initData = getInitSysEx() else { return }
        sendRawSignals(
            messages: initData.messages,
            cableNumber: initData.cableNumber
        )
    }

    @inline(__always)
    override func getSignal(cmd: Int, sig: Int, note: Int, velocity: Int) {
        let cin = cmd & 0x0F
        guard cin == 8 || cin == 9 else {
            onUnknownReceived(cmd: cmd, sig: sig, note: note, velocity: velocity)
            return
        }

        let pressed = cin == 9 && velocity > 0

        switch note {
        case 36...99:
            let index = note - 36
            let row = 7 - (index % 32) / 4
            let column = index < 32 ? index % 4 : index % 4 + 4
            onPadTouch(x: row, y: column, upDown: pressed, velocity: velocity)

        case 28...35:
            onFunctionKeyTouch(f: note - 28, upDown: pressed)

        case 100...107:
            let chain = note - 100
            onChainTouch(c: chain, upDown: pressed)
            onFunctionKeyTouch(f: chain + 8, upDown: pressed)

        case 116...123:
            let chain = 15 - (note - 116)
            onChainTouch(c: chain, upDown: pressed)
            onFunctionKeyTouch(f: chain + 8, upDown: pressed)

        case 108...115:
            let chain = 23 - (note - 108)
            onChainTouch(c: chain, upDown: pressed)
            onFunctionKeyTouch(f: chain + 8, upDown: pressed)

        case 27:
            onFunctionKeyTouch(f: 32, upDown: pressed)

        default:
            onUnknownReceived(cmd: cmd, sig: sig, note: note, velocity: velocity)
        }
    }

    @inline(__always)
    override func sendPadLed(x: Int, y: Int, velocity: Int) {
        guard (0...7).contains(x), (0...7).contains(y) else { return }

        let row = 7 - x
        let note = y < 4
            ? 36 + row * 4 + y
            : 68 + row * 4 + y - 4

        sendSignal(
            cmd: Self.cinNoteOn,
            sig: Self.statusNoteOn,
            note: note,
            velocity: velocity
        )
    }

    @inline(__always)
    override func sendChainLed(c: Int, velocity: Int) {
        guard (0...23).contains(c) else { return }
        sendFunctionKeyLed(f: c + 8, velocity: velocity)
    }

    @inline(__always)
    override func sendFunctionKeyLed(f: Int, velocity: Int) {
        let note: Int

        switch f {
        case 0...7:
            note = 28 + f
        case 8...15:
            note = 100 + f - 8
        case 16...23:
            note = 123 - (f - 16)
        case 24...31:
            note = 115 - (f - 24)
        case 32:
            note = 27
        default:
            return
        }

        sendSignal(
            cmd: Self.cinNoteOn,
            sig: Self.statusNoteOn,
            note: note,
            velocity: velocity
        )
    }

    override func sendClearLed() {
        for x in 0..<8 {
            for y in 0..<8 {
                sendPadLed(x: x, y: y, velocity: 0)
            }
        }

        for f in 0...32 {
            sendFunctionKeyLed(f: f, velocity: 0)
        }
    }
}
