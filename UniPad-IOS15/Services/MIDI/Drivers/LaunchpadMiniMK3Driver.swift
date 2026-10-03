import Foundation

final class LaunchpadMiniMK3Driver: LaunchpadXDriver {
    override func getInitSysEx() -> (messages: [[UInt8]], cableNumber: Int)? {
        (
            messages: [
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x10, 0x00, 0xF7],
                [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, 0xF7]
            ],
            cableNumber: 1
        )
    }
}
