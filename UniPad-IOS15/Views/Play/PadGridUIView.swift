import UIKit
import SwiftUI
import QuartzCore
/// Renderer da grade de pads para iOS.
///
/// A grade não usa TimelineView nem Canvas para o Guide.
/// PNGs/LEDs ficam em CALayer e o Guide é interpolado pelo Core Animation.
final class PadGridUIView: UIView {
    var onPadTouch: ((Int, Int, Bool) -> Void)?
    private final class CellLayers {
        let container = CALayer()
        let pad = CALayer()
        let led = CALayer()
        let guide = CAShapeLayer()
        let phantom = CALayer()
        init() {
            container.masksToBounds = false
            pad.contentsGravity = .resize
            phantom.contentsGravity = .resize
            // Mantém o redimensionamento suave, mas sem antialiasing de borda
            // entre células adjacentes.
            pad.minificationFilter = .linear
            pad.magnificationFilter = .linear
            phantom.minificationFilter = .linear
            phantom.magnificationFilter = .linear
            pad.allowsEdgeAntialiasing = false
            phantom.allowsEdgeAntialiasing = false
            led.allowsEdgeAntialiasing = false
            guide.allowsEdgeAntialiasing = false
            led.backgroundColor = UIColor.clear.cgColor
            guide.fillColor = UIColor.black.withAlphaComponent(0.867).cgColor
            guide.strokeColor = nil
            container.addSublayer(pad)
            container.addSublayer(led)
            container.addSublayer(guide)
            container.addSublayer(phantom)
        }
    }
    private var columns = 0
    private var rows = 0
    private var isSquareButton = false
    private var padColors: [[Color]] = []
    private var padLedColors: [[Color]] = []
    private var padItems: [[ChannelManager.Item?]] = []
    private var btnImage: PlatformImage?
    private var btnPressedImage: PlatformImage?
    private var phantomImage: PlatformImage?
    private var phantomVariantImage: PlatformImage?
    private var renderVersion = 0
    private var padGuideTargets: [[Int64]] = []
    private var cells: [CellLayers] = []
    private var lastGuideTargets: [Int64] = []
    private var lastLayoutSize: CGSize = .zero
    private var gridOrigin: CGPoint = .zero
    private var cellWidth: CGFloat = 0
    private var cellHeight: CGFloat = 0
    // Limites reais das células em points, derivados de coordenadas inteiras
    // em pixels físicos. O mesmo limite é compartilhado por dois pads vizinhos.
    private var xBoundaries: [CGFloat] = []
    private var yBoundaries: [CGFloat] = []
    private var activeTouches: [UITouch: (Int, Int)] = [:]
    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isOpaque = false
        layer.masksToBounds = true
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isOpaque = false
        layer.masksToBounds = true
    }
    func update(
        columns: Int,
        rows: Int,
        isSquareButton: Bool,
        padColors: [[Color]],
        padLedColors: [[Color]],
        padItems: [[ChannelManager.Item?]],
        btnImage: PlatformImage?,
        btnPressedImage: PlatformImage?,
        phantomImage: PlatformImage?,
        phantomVariantImage: PlatformImage?,
        renderVersion: Int,
        padGuideTargets: [[Int64]]
    ) {
        let dimensionsChanged =
            self.columns != columns ||
            self.rows != rows ||
            self.isSquareButton != isSquareButton
        self.columns = max(columns, 0)
        self.rows = max(rows, 0)
        self.isSquareButton = isSquareButton
        self.padColors = padColors
        self.padLedColors = padLedColors
        self.padItems = padItems
        self.btnImage = btnImage
        self.btnPressedImage = btnPressedImage
        self.phantomImage = phantomImage
        self.phantomVariantImage = phantomVariantImage
        self.renderVersion = renderVersion
        self.padGuideTargets = padGuideTargets
        rebuildCellsIfNeeded()
        if dimensionsChanged {
            lastLayoutSize = .zero
            setNeedsLayout()
            layoutIfNeeded()
        } else if bounds.size != .zero && lastLayoutSize != bounds.size {
            setNeedsLayout()
            layoutIfNeeded()
        }
        updatePadAndLEDLayers()
        updatePhantomLayers()
        // O Core Animation só é reiniciado quando o target daquele pad mudou.
        updateGuideLayers(force: false)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard rows > 0, columns > 0, !cells.isEmpty else {
            xBoundaries.removeAll(keepingCapacity: true)
            yBoundaries.removeAll(keepingCapacity: true)
            return
        }
        let sizeChanged = lastLayoutSize != bounds.size
        lastLayoutSize = bounds.size
        let screenScale = window?.screen.scale ?? UIScreen.main.scale
        // Trabalhamos primeiro em pixels físicos inteiros.
        // Isso evita bordas em subpixel e elimina "costuras" de 1 px.
        let viewWidthPx = max(0, Int((bounds.width * screenScale).rounded()))
        let viewHeightPx = max(0, Int((bounds.height * screenScale).rounded()))
        let gridWidthPx: Int
        let gridHeightPx: Int
        let originXPx: Int
        let originYPx: Int
        if isSquareButton {
            // Para pads quadrados, cada célula recebe exatamente a mesma
            // quantidade inteira de pixels.
            let cellPx = max(
                1,
                min(
                    viewWidthPx / max(columns, 1),
                    viewHeightPx / max(rows, 1)
                )
            )
            gridWidthPx = cellPx * columns
            gridHeightPx = cellPx * rows
            originXPx = (viewWidthPx - gridWidthPx) / 2
            originYPx = (viewHeightPx - gridHeightPx) / 2
            xBoundaries = (0...columns).map {
                CGFloat(originXPx + $0 * cellPx) / screenScale
            }
            yBoundaries = (0...rows).map {
                CGFloat(originYPx + $0 * cellPx) / screenScale
            }
        } else {
            // Para células retangulares, distribuímos os pixels restantes
            // entre as células sem nunca criar gaps ou overlaps.
            gridWidthPx = viewWidthPx
            gridHeightPx = viewHeightPx
            originXPx = 0
            originYPx = 0
            xBoundaries = (0...columns).map { index in
                let px = originXPx + Int(
                    (Double(index) * Double(gridWidthPx) / Double(columns)).rounded()
                )
                return CGFloat(px) / screenScale
            }
            yBoundaries = (0...rows).map { index in
                let px = originYPx + Int(
                    (Double(index) * Double(gridHeightPx) / Double(rows)).rounded()
                )
                return CGFloat(px) / screenScale
            }
        }
        gridOrigin = CGPoint(
            x: CGFloat(originXPx) / screenScale,
            y: CGFloat(originYPx) / screenScale
        )
        // Mantidos por compatibilidade com qualquer lógica externa,
        // mas o touch usa os limites exatos abaixo.
        cellWidth = CGFloat(gridWidthPx) / CGFloat(columns) / screenScale
        cellHeight = CGFloat(gridHeightPx) / CGFloat(rows) / screenScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let x0 = xBoundaries[column]
                let x1 = xBoundaries[column + 1]
                let y0 = yBoundaries[row]
                let y1 = yBoundaries[row + 1]
                let frame = CGRect(
                    x: x0,
                    y: y0,
                    width: max(0, x1 - x0),
                    height: max(0, y1 - y0)
                )
                let cell = cells[index]
                // Anchor padrão em 0.5 continua correto porque frame e size
                // já estão presos à malha de pixels físicos.
                cell.container.frame = frame
                let localBounds = CGRect(origin: .zero, size: frame.size)
                cell.pad.frame = localBounds
                cell.led.frame = localBounds
                cell.guide.frame = localBounds
                cell.phantom.frame = localBounds
                cell.container.contentsScale = screenScale
                cell.pad.contentsScale = screenScale
                cell.led.contentsScale = screenScale
                cell.guide.contentsScale = screenScale
                cell.phantom.contentsScale = screenScale
                cell.led.cornerRadius = min(
                    4,
                    min(frame.width, frame.height) / 2
                )
            }
        }
        CATransaction.commit()
        if sizeChanged {
            // O path do Guide depende do tamanho exato da célula.
            updateGuideLayers(force: true)
        }
    }

    // MARK: - Layers

    private func rebuildCellsIfNeeded() {
        let wantedCount = rows * columns
        guard cells.count != wantedCount else {
            return
        }
        for cell in cells {
            cell.container.removeFromSuperlayer()
        }
        cells.removeAll(keepingCapacity: true)
        if wantedCount > 0 {
            cells.reserveCapacity(wantedCount)
        }
        for _ in 0..<wantedCount {
            let cell = CellLayers()
            layer.addSublayer(cell.container)
            cells.append(cell)
        }
        lastGuideTargets = Array(repeating: Int64.min, count: wantedCount)
        lastLayoutSize = .zero
    }
    private func updatePadAndLEDLayers() {
        guard rows > 0, columns > 0 else {
            return
        }
        let normalCG = btnImage?.cgImage
        let pressedCG = btnPressedImage?.cgImage ?? normalCG
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let cell = cells[index]
                let item: ChannelManager.Item? =
                    row < padItems.count && column < padItems[row].count
                    ? padItems[row][column]
                    : nil
                if item?.channel == .pressed {
                    cell.pad.contents = pressedCG
                } else {
                    cell.pad.contents = normalCG
                }
                // Mantém o mesmo fallback visual do Canvas original.
                if cell.pad.contents == nil {
                    cell.pad.backgroundColor = UIColor(
                        red: 42.0 / 255.0,
                        green: 42.0 / 255.0,
                        blue: 42.0 / 255.0,
                        alpha: 1
                    ).cgColor
                    cell.pad.cornerRadius = 4
                } else {
                    cell.pad.backgroundColor = nil
                    cell.pad.cornerRadius = 0
                }
                let ledColor: Color =
                    row < padLedColors.count && column < padLedColors[row].count
                    ? padLedColors[row][column]
                    : .clear
                if ledColor == .clear {
                    cell.led.backgroundColor = UIColor.clear.cgColor
                } else {
                    cell.led.backgroundColor = UIColor(ledColor).cgColor
                }
            }
        }
        CATransaction.commit()
    }
    private func updatePhantomLayers() {
        guard rows > 0, columns > 0 else {
            return
        }
        let phantomEnabled = rows < 16 && columns < 16
        let centerX = rows / 2 - 1
        let centerY = columns / 2 - 1
        let phantomCG = phantomImage?.cgImage
        let variantCG = phantomVariantImage?.cgImage
        let shouldUseVariant =
            phantomEnabled &&
            isSquareButton &&
            rows % 2 == 0 &&
            columns % 2 == 0 &&
            variantCG != nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let layer = cells[index].phantom
                guard phantomEnabled else {
                    layer.contents = nil
                    layer.setAffineTransform(.identity)
                    continue
                }
                var rotation: CGFloat?
                if shouldUseVariant {
                    if row == centerX && column == centerY {
                        rotation = 0
                    } else if row == centerX + 1 && column == centerY {
                        rotation = -.pi / 2
                    } else if row == centerX && column == centerY + 1 {
                        rotation = .pi / 2
                    } else if row == centerX + 1 && column == centerY + 1 {
                        rotation = .pi
                    }
                }
                if let rotation, let variantCG {
                    layer.contents = variantCG
                    layer.setAffineTransform(
                        CGAffineTransform(rotationAngle: rotation)
                    )
                } else {
                    layer.contents = phantomCG
                    layer.setAffineTransform(.identity)
                }
            }
        }
        CATransaction.commit()
    }

    // MARK: - Guide / Core Animation

    private func updateGuideLayers(force: Bool) {
        guard rows > 0, columns > 0, cells.count == rows * columns else {
            return
        }
        if lastGuideTargets.count != cells.count {
            lastGuideTargets = Array(repeating: Int64.min, count: cells.count)
        }
        let nowMs = Int64(CACurrentMediaTime() * 1000)
        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let target: Int64 =
                    row < padGuideTargets.count && column < padGuideTargets[row].count
                    ? padGuideTargets[row][column]
                    : 0
                if !force && lastGuideTargets[index] == target {
                    continue
                }
                lastGuideTargets[index] = target
                let guide = cells[index].guide
                guide.removeAnimation(forKey: "unipad-guide-path")
                guard
                    target > 0,
                    target > nowMs,
                    guide.bounds.width > 0,
                    guide.bounds.height > 0
                else {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    guide.path = nil
                    CATransaction.commit()
                    continue
                }
                startGuideAnimation(
                    guide,
                    target: target,
                    nowMs: nowMs
                )
            }
        }
    }
    private func startGuideAnimation(
        _ guide: CAShapeLayer,
        target: Int64,
        nowMs: Int64
    ) {
        let rect = guide.bounds
        let remaining = max(Int64(0), target - nowMs)
        // Mesma matemática usada pelo PadGridView funcional.
        let durationBase = max(
            Int64(100),
            target - (nowMs - Int64(AutoPlayRunner.guideLookaheadMs))
        )
        let progress = CGFloat(
            1.0 - Double(remaining) / Double(durationBase)
        )
        let clampedProgress = min(max(progress, 0), 1)
        let maxBorder = min(rect.width, rect.height) / 2
        let currentInset = maxBorder * clampedProgress
        let startRect = rect.insetBy(
            dx: currentInset,
            dy: currentInset
        )
        let endRect = CGRect(
            x: rect.midX,
            y: rect.midY,
            width: 0,
            height: 0
        )
        let cornerRadius = min(4, min(rect.width, rect.height) / 2)
        let startPath = UIBezierPath(
            roundedRect: startRect,
            cornerRadius: cornerRadius
        ).cgPath
        let endPath = UIBezierPath(
            roundedRect: endRect,
            cornerRadius: 0
        ).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Modelo termina no estado final; a animação visual roda no compositor.
        guide.path = endPath
        guide.fillColor = UIColor.black.withAlphaComponent(0.867).cgColor
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = startPath
        animation.toValue = endPath
        animation.duration = Double(remaining) / 1000.0
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = true
        guide.add(animation, forKey: "unipad-guide-path")
    }

    // MARK: - Touch

    private func padAt(_ point: CGPoint) -> (Int, Int)? {
        guard
            columns > 0,
            rows > 0,
            xBoundaries.count == columns + 1,
            yBoundaries.count == rows + 1
        else {
            return nil
        }
        guard
            point.x >= xBoundaries[0],
            point.x < xBoundaries[columns],
            point.y >= yBoundaries[0],
            point.y < yBoundaries[rows]
        else {
            return nil
        }
        // 8x8 normalmente: uma busca linear aqui é minúscula e só acontece
        // durante touch, nunca no loop de animação/render.
        guard let col = (0..<columns).first(where: {
            point.x >= xBoundaries[$0] && point.x < xBoundaries[$0 + 1]
        }) else {
            return nil
        }
        guard let row = (0..<rows).first(where: {
            point.y >= yBoundaries[$0] && point.y < yBoundaries[$0 + 1]
        }) else {
            return nil
        }
        return (row, col)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let (row, col) = padAt(point) else {
                continue
            }
            activeTouches[touch] = (row, col)
            onPadTouch?(row, col, true)
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            let next = padAt(point)
            let previous = activeTouches[touch]
            if let previous, next == nil {
                onPadTouch?(previous.0, previous.1, false)
                activeTouches.removeValue(forKey: touch)
                continue
            }
            guard let (row, col) = next else {
                continue
            }
            if let previous, previous != (row, col) {
                onPadTouch?(previous.0, previous.1, false)
                activeTouches[touch] = (row, col)
                onPadTouch?(row, col, true)
            } else if previous == nil {
                activeTouches[touch] = (row, col)
                onPadTouch?(row, col, true)
            }
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let (row, col) = activeTouches.removeValue(forKey: touch) {
                onPadTouch?(row, col, false)
            }
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
