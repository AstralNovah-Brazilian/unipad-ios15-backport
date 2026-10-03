import SwiftUI
import UIKit

struct PadGridView: View {
    let columns: Int
    let rows: Int
    let isSquareButton: Bool
    let padColors: [[Color]]
    let padLedColors: [[Color]]
    let padItems: [[ChannelManager.Item?]]

    var btnImage: PlatformImage?
    var btnPressedImage: PlatformImage?
    var phantomImage: PlatformImage?
    var phantomVariantImage: PlatformImage?
    var renderVersion = 0
    var padGuideTargets: [[Int64]] = []
    var traceLogSequence: [(x: Int, y: Int)]?
    var traceLogColor: Color = .white
    var traceLogClassic = false
    var onPadTouch: (Int, Int, Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            let safeColumns = max(columns, 1)
            let safeRows = max(rows, 1)
            let squareSize = min(
                geometry.size.width / CGFloat(safeColumns),
                geometry.size.height / CGFloat(safeRows)
            )
            let cellWidth = isSquareButton
                ? squareSize
                : geometry.size.width / CGFloat(safeColumns)
            let cellHeight = isSquareButton
                ? squareSize
                : geometry.size.height / CGFloat(safeRows)
            let gridWidth = cellWidth * CGFloat(columns)
            let gridHeight = cellHeight * CGFloat(rows)
            let offsetX = (geometry.size.width - gridWidth) / 2
            let offsetY = (geometry.size.height - gridHeight) / 2

            ZStack {
                PadGridRendererRepresentable(
                    columns: columns,
                    rows: rows,
                    isSquareButton: isSquareButton,
                    padColors: padColors,
                    padLedColors: padLedColors,
                    padItems: padItems,
                    btnImage: btnImage,
                    btnPressedImage: btnPressedImage,
                    phantomImage: phantomImage,
                    phantomVariantImage: phantomVariantImage,
                    renderVersion: renderVersion,
                    padGuideTargets: padGuideTargets,
                    onPadTouch: onPadTouch
                )

                if let sequence = traceLogSequence, !sequence.isEmpty {
                    if traceLogClassic {
                        classicTraceLog(
                            sequence: sequence,
                            cellWidth: cellWidth,
                            cellHeight: cellHeight,
                            offsetX: offsetX,
                            offsetY: offsetY
                        )
                    } else {
                        pathTraceLog(
                            sequence: sequence,
                            cellWidth: cellWidth,
                            cellHeight: cellHeight,
                            offsetX: offsetX,
                            offsetY: offsetY
                        )
                    }
                }
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func classicTraceLog(
        sequence: [(x: Int, y: Int)],
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat
    ) -> some View {
        Canvas { context, _ in
            let cellMin = min(cellWidth, cellHeight)
            let font = Font.system(
                size: max(9, cellMin * 0.14),
                weight: .medium
            )

            for (key, label) in TraceLogText.perPad(
                sequence,
                columns: columns,
                rows: rows
            ) {
                let row = key / columns
                let col = key % columns
                let cell = CGRect(
                    x: offsetX + CGFloat(col) * cellWidth + 2,
                    y: offsetY + CGFloat(row) * cellHeight + 2,
                    width: cellWidth - 4,
                    height: cellHeight - 4
                )
                let resolved = context.resolve(
                    Text(label)
                        .font(font)
                        .foregroundColor(traceLogColor)
                )
                let measured = resolved.measure(in: cell.size)
                let drawSize = CGSize(
                    width: min(measured.width, cell.width),
                    height: min(measured.height, cell.height)
                )
                var cellContext = context
                cellContext.clip(to: Path(cell))
                cellContext.draw(
                    resolved,
                    in: CGRect(
                        x: cell.midX - drawSize.width / 2,
                        y: cell.midY - drawSize.height / 2,
                        width: drawSize.width,
                        height: drawSize.height
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func pathTraceLog(
        sequence: [(x: Int, y: Int)],
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat
    ) -> some View {
        Canvas { context, _ in
            let cellMin = min(cellWidth, cellHeight)
            let maxOffset = cellMin * 0.3
            let strokeWidth = max(1.5, cellMin * 0.04)
            let dotRadius = max(2.5, cellMin * 0.06)

            var visitTotal: [Int: Int] = [:]
            visitTotal.reserveCapacity(sequence.count)

            for point in sequence {
                let key = point.x * columns + point.y
                visitTotal[key, default: 0] += 1
            }

            var visitIndex: [Int: Int] = [:]
            visitIndex.reserveCapacity(visitTotal.count)

            var points: [CGPoint] = []
            points.reserveCapacity(sequence.count)

            for point in sequence {
                let key = point.x * columns + point.y
                let total = visitTotal[key, default: 1]
                let index = visitIndex[key, default: 0]
                visitIndex[key] = index + 1

                var ox: CGFloat = 0
                var oy: CGFloat = 0

                if total > 1 {
                    let t = CGFloat(index) / CGFloat(total - 1) - 0.5
                    ox = t * maxOffset
                    oy = t * maxOffset
                }

                points.append(
                    CGPoint(
                        x: offsetX + CGFloat(point.y) * cellWidth + cellWidth / 2 + ox,
                        y: offsetY + CGFloat(point.x) * cellHeight + cellHeight / 2 + oy
                    )
                )
            }

            if points.count >= 2 {
                var path = Path()
                path.move(to: points[0])

                for point in points.dropFirst() {
                    path.addLine(to: point)
                }

                context.stroke(
                    path,
                    with: .color(traceLogColor.opacity(0.85)),
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            for point in points {
                let dotRect = CGRect(
                    x: point.x - dotRadius,
                    y: point.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(traceLogColor.opacity(0.95))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PadGridRendererRepresentable: UIViewRepresentable {
    let columns: Int
    let rows: Int
    let isSquareButton: Bool
    let padColors: [[Color]]
    let padLedColors: [[Color]]
    let padItems: [[ChannelManager.Item?]]
    let btnImage: PlatformImage?
    let btnPressedImage: PlatformImage?
    let phantomImage: PlatformImage?
    let phantomVariantImage: PlatformImage?
    let renderVersion: Int
    let padGuideTargets: [[Int64]]
    let onPadTouch: (Int, Int, Bool) -> Void

    func makeUIView(context: Context) -> PadGridUIView {
        let view = PadGridUIView()
        view.onPadTouch = onPadTouch
        return view
    }

    func updateUIView(_ uiView: PadGridUIView, context: Context) {
        uiView.onPadTouch = onPadTouch
        uiView.update(
            columns: columns,
            rows: rows,
            isSquareButton: isSquareButton,
            padColors: padColors,
            padLedColors: padLedColors,
            padItems: padItems,
            btnImage: btnImage,
            btnPressedImage: btnPressedImage,
            phantomImage: phantomImage,
            phantomVariantImage: phantomVariantImage,
            renderVersion: renderVersion,
            padGuideTargets: padGuideTargets
        )
    }
}
