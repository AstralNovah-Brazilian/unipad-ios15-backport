import Foundation

final class MatrixDriver: BaseMidiDriver {
    static let circleCode: [[Int]] = [
        [9, -111, 28], [9, -111, 29], [9, -111, 30], [9, -111, 31],
        [9, -111, 32], [9, -111, 33], [9, -111, 34], [9, -111, 35],
        [9, -111, 100], [9, -111, 101], [9, -111, 102], [9, -111, 103],
        [9, -111, 104], [9, -111, 105], [9, -111, 106], [9, -111, 107],
        [9, -111, 123], [9, -111, 122], [9, -111, 121], [9, -111, 120],
        [9, -111, 119], [9, -111, 118], [9, -111, 117], [9, -111, 116],
        [9, -111, 115], [9, -111, 114], [9, -111, 113], [9, -111, 112],
        [9, -111, 111], [9, -111, 110], [9, -111, 109], [9, -111, 108]
    ]

    @inline(__always)
    override func getSignal(cmd: Int, sig: Int, note: Int, velocity: Int) {
        switch cmd {
        case 9:
            switch note {
            case 36...67:
                let offset = 67 - note
                onPadTouch(x: offset / 4, y: 3 - offset % 4, upDown: true, velocity: velocity)
            case 68...99:
                let offset = 99 - note
                onPadTouch(x: offset / 4, y: 7 - offset % 4, upDown: true, velocity: velocity)
            case 100...107:
                let chain = note - 100
                let pressed = velocity != 0
                onChainTouch(c: chain, upDown: pressed)
                onFunctionKeyTouch(f: chain + 8, upDown: pressed)
            case 108...115:
                let function = 132 - note
                onFunctionKeyTouch(f: function, upDown: velocity != 0)
            default:
                break
            }

        case 8:
            switch note {
            case 36...67:
                let offset = 67 - note
                onPadTouch(x: offset / 4, y: 3 - offset % 4, upDown: false, velocity: velocity)
            case 68...99:
                let offset = 99 - note
                onPadTouch(x: offset / 4, y: 7 - offset % 4, upDown: false, velocity: velocity)
            default:
                break
            }

        default:
            break
        }
    }

    @inline(__always)
    override func sendPadLed(x: Int, y: Int, velocity: Int) {
        let padX = x + 1
        let padY = y + 1

        if (1...4).contains(padY) {
            sendSignal(cmd: 9, sig: -111, note: -4 * padX + padY + 67, velocity: velocity)
        } else if (5...8).contains(padY) {
            sendSignal(cmd: 9, sig: -111, note: -4 * padX + padY + 95, velocity: velocity)
        }
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
    }
}
