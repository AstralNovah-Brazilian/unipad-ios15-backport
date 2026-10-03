import Foundation

/// Text for the classic trace log, where each pad shows the order of every tap on it.
enum TraceLogText {
    /// Returns, per pad key (`x * columns + y`), the 1-based index of every tap on that pad
    /// joined by spaces ("1 5"), which is the format the pre-4.1 trace log used.
    /// Pads that were never tapped are absent; taps outside the grid are skipped but still counted.
    static func perPad(
        _ sequence: [(x: Int, y: Int)],
        columns: Int,
        rows: Int
    ) -> [Int: String] {
        guard columns > 0, rows > 0, !sequence.isEmpty else { return [:] }

        var indicesByPad: [Int: [Int]] = [:]
        indicesByPad.reserveCapacity(min(sequence.count, columns * rows))

        for (index, point) in sequence.enumerated() {
            guard
                point.x >= 0,
                point.x < rows,
                point.y >= 0,
                point.y < columns
            else {
                continue
            }

            let key = point.x * columns + point.y
            indicesByPad[key, default: []].append(index + 1)
        }

        var labels: [Int: String] = [:]
        labels.reserveCapacity(indicesByPad.count)

        for (key, indices) in indicesByPad {
            labels[key] = indices.map(String.init).joined(separator: " ")
        }

        return labels
    }
}
