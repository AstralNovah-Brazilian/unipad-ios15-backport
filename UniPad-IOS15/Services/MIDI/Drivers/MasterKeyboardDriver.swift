import Foundation

final class MasterKeyboardDriver: BaseMidiDriver {
    @inline(__always)
    override func getSignal(cmd: Int, sig: Int, note: Int, velocity: Int) {
        guard (36...99).contains(note) else {
            onUnknownReceived(cmd: cmd, sig: sig, note: note, velocity: velocity)
            return
        }

        let pressed: Bool
        if cmd == 9 {
            pressed = velocity != 0
        } else if cmd == 8 || velocity == 0 {
            pressed = false
        } else {
            onUnknownReceived(cmd: cmd, sig: sig, note: note, velocity: velocity)
            return
        }

        let x: Int
        let y: Int

        if note <= 67 {
            let offset = 67 - note
            x = offset / 4
            y = 3 - offset % 4
        } else {
            let offset = 99 - note
            x = offset / 4
            y = 7 - offset % 4
        }

        onPadTouch(
            x: x,
            y: y,
            upDown: pressed,
            velocity: pressed ? velocity : 0
        )
    }
}
