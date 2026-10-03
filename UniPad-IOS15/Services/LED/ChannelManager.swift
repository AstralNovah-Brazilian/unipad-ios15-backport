import Foundation

final class ChannelManager {
    static let circularButtonCount = 36
    static let noColor = Int.min
    private static let prioritySlotCount = 5

    enum Channel: Int, CaseIterable {
        case ui = 0
        case uiUnipad = 1
        case guide = 2
        case pressed = 3
        case chain = 4
        case led = 5

        var priority: Int {
            switch self {
            case .ui: return 0
            case .uiUnipad: return 1
            case .guide: return 2
            case .pressed, .chain: return 3
            case .led: return 4
            }
        }
    }

    struct Item {
        let channel: Channel
        let color: UInt32
        let code: Int
    }

    private var btn: [[[Item?]]]
    private var cir: [[Item?]]
    private var btnIgnoreList: [Bool]
    private var cirIgnoreList: [Bool]

    init(x: Int, y: Int) {
        btn = Array(
            repeating: Array(
                repeating: Array(
                    repeating: nil,
                    count: Self.prioritySlotCount
                ),
                count: y
            ),
            count: x
        )
        cir = Array(
            repeating: Array(
                repeating: nil,
                count: Self.prioritySlotCount
            ),
            count: Self.circularButtonCount
        )
        btnIgnoreList = Array(
            repeating: false,
            count: Self.prioritySlotCount
        )
        cirIgnoreList = Array(
            repeating: false,
            count: Self.prioritySlotCount
        )
    }

    func get(x: Int, y: Int) -> Item? {
        if x >= 0 {
            guard
                btn.indices.contains(x),
                btn[x].indices.contains(y)
            else {
                return nil
            }

            for priority in 0..<Self.prioritySlotCount {
                if btnIgnoreList[priority] { continue }
                if let item = btn[x][y][priority] {
                    return item
                }
            }
        } else {
            guard cir.indices.contains(y) else { return nil }

            for priority in 0..<Self.prioritySlotCount {
                if cirIgnoreList[priority] { continue }
                if let item = cir[y][priority] {
                    return item
                }
            }
        }

        return nil
    }

    func add(
        x: Int,
        y: Int,
        channel: Channel,
        color: Int,
        code: Int
    ) {
        let resolvedColor = color == Self.noColor
            ? LaunchpadColor.colorFromCode(code)
            : UInt32(truncatingIfNeeded: color)

        let item = Item(
            channel: channel,
            color: resolvedColor,
            code: code
        )
        let priority = channel.priority

        if x >= 0 {
            guard
                btn.indices.contains(x),
                btn[x].indices.contains(y)
            else {
                return
            }

            btn[x][y][priority] = item
        } else {
            guard cir.indices.contains(y) else { return }
            cir[y][priority] = item
        }
    }

    func get(
        x: Int,
        y: Int,
        channel: Channel
    ) -> Item? {
        let priority = channel.priority

        if x >= 0 {
            guard
                btn.indices.contains(x),
                btn[x].indices.contains(y)
            else {
                return nil
            }

            return btn[x][y][priority]
        }

        guard cir.indices.contains(y) else { return nil }
        return cir[y][priority]
    }

    func remove(
        x: Int,
        y: Int,
        channel: Channel
    ) {
        let priority = channel.priority

        if x >= 0 {
            guard
                btn.indices.contains(x),
                btn[x].indices.contains(y)
            else {
                return
            }

            btn[x][y][priority] = nil
        } else {
            guard cir.indices.contains(y) else { return }
            cir[y][priority] = nil
        }
    }

    func setBtnIgnore(
        channel: Channel,
        ignore: Bool
    ) {
        btnIgnoreList[channel.priority] = ignore
    }

    func setCirIgnore(
        channel: Channel,
        ignore: Bool
    ) {
        cirIgnoreList[channel.priority] = ignore
    }
}
