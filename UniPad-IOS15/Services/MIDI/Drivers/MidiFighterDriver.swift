import Foundation

final class MidiFighterDriver: BaseMidiDriver {
    @inline(__always)
    override func getSignal(cmd: Int, sig: Int, note: Int, velocity: Int) {
        guard cmd == 8 || cmd == 9 else {
            onUnknownReceived(cmd: cmd, sig: sig, note: note, velocity: velocity)
            return
        }

        let pressed = cmd == 9 && velocity != 0
        let x: Int
        let y: Int

        if (36...67).contains(note) {
            let offset = 67 - note
            x = offset / 4
            y = 3 - offset % 4
        } else if (68...99).contains(note) {
            let offset = 99 - note
            x = offset / 4
            y = 7 - offset % 4
        } else {
            onUnknownReceived(cmd: cmd, sig: sig, note: note, velocity: velocity)
            return
        }

        onPadTouch(x: x, y: y, upDown: pressed, velocity: velocity)
    }

    @inline(__always)
    override func sendPadLed(x: Int, y: Int, velocity: Int) {
        guard (0...7).contains(x), (0...7).contains(y) else { return }

        let padX = x + 1
        let padY = y + 1

        if padY <= 4 {
            sendSignal(cmd: 9, sig: -110, note: -4 * padX + padY + 67, velocity: velocity)
        } else {
            sendSignal(cmd: 9, sig: -110, note: -4 * padX + padY + 95, velocity: velocity)
        }
    }

    override func sendClearLed() {
        for x in 0..<8 {
            for y in 0..<8 {
                sendPadLed(x: x, y: y, velocity: 0)
            }
        }
    }
}
