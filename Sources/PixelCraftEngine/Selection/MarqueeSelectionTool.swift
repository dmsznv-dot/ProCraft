import CoreGraphics
import Foundation

public enum MarqueeShape: String, CaseIterable, Sendable, Codable {
    case rectangle
    case ellipse
}

public enum SelectionMode: String, CaseIterable, Sendable, Codable {
    case newSelection // Replaces active selection
    case add          // Union (Shift)
    case subtract     // Difference (Option/Alt)
    case intersect    // Intersection (Shift + Option)
}

public struct MarqueeConfiguration: Sendable, Codable, Equatable {
    public var shape: MarqueeShape
    public var mode: SelectionMode
    public var featherRadius: CGFloat // 0.0 ... 100.0 px
    public var antiAliased: Bool

    public init(
        shape: MarqueeShape = .rectangle,
        mode: SelectionMode = .newSelection,
        featherRadius: CGFloat = 0.0,
        antiAliased: Bool = true
    ) {
        self.shape = shape
        self.mode = mode
        self.featherRadius = max(0.0, min(100.0, featherRadius))
        self.antiAliased = antiAliased
    }
}

public final class MarqueeSelectionTool: DrawingTool, @unchecked Sendable {
    public let toolType: ToolType
    public var configuration: MarqueeConfiguration

    public var isConstrained: Bool = false  // Shift key (1:1 aspect)
    public var isFromCenter: Bool = false   // Option key (origin as center)

    private var isDragging: Bool = false
    private var startPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero

    public init(
        shape: MarqueeShape = .rectangle,
        configuration: MarqueeConfiguration? = nil
    ) {
        self.toolType = (shape == .rectangle) ? .marqueeRect : .marqueeEllipse
        self.configuration = configuration ?? MarqueeConfiguration(shape: shape)
    }

    public func mouseDown(at canvasPoint: CGPoint, document: Document) {
        isDragging = true
        startPoint = canvasPoint
        currentPoint = canvasPoint
    }

    public func mouseDragged(to canvasPoint: CGPoint, document: Document) {
        guard isDragging else { return }
        currentPoint = canvasPoint
    }

    public func mouseUp(at canvasPoint: CGPoint, document: Document) {
        guard isDragging else { return }
        currentPoint = canvasPoint
        isDragging = false

        commitSelection(document: document)
    }

    public func cancel(document: Document) {
        isDragging = false
    }

    // MARK: - Selection Commit

    public func commitSelection(document: Document) {
        let rect = calculateSelectionRect(canvasSize: document.canvasSize)

        // Single click without drag: deselects in newSelection mode
        if rect.width < 1.0 && rect.height < 1.0 {
            if configuration.mode == .newSelection {
                document.selectionMask?.deselect()
            }
            return
        }

        guard let mask = document.selectionMask else { return }

        // Rasterize new shape into temporary SparseMaskGrid
        let tempGrid = SparseMaskGrid(canvasSize: document.canvasSize)
        rasterizeShape(into: tempGrid, rect: rect, canvasSize: document.canvasSize)

        // Apply feathering if radius > 0
        if configuration.featherRadius > 0.5 {
            applyFeather(to: tempGrid, radius: configuration.featherRadius, canvasSize: document.canvasSize)
        }

        // Combine tempGrid into document.selectionMask according to SelectionMode
        applySelectionMode(tempGrid: tempGrid, mask: mask, mode: configuration.mode)
    }

    public func calculateSelectionRect(canvasSize: CGSize) -> CGRect {
        var dx = currentPoint.x - startPoint.x
        var dy = currentPoint.y - startPoint.y

        if isConstrained {
            let s = min(abs(dx), abs(dy))
            dx = (dx >= 0 ? 1 : -1) * s
            dy = (dy >= 0 ? 1 : -1) * s
        }

        let originX: CGFloat
        let originY: CGFloat
        let width: CGFloat
        let height: CGFloat

        if isFromCenter {
            originX = startPoint.x - abs(dx)
            originY = startPoint.y - abs(dy)
            width = abs(dx) * 2.0
            height = abs(dy) * 2.0
        } else {
            originX = min(startPoint.x, startPoint.x + dx)
            originY = min(startPoint.y, startPoint.y + dy)
            width = abs(dx)
            height = abs(dy)
        }

        let unconstrainedRect = CGRect(x: originX, y: originY, width: width, height: height)
        return unconstrainedRect.intersection(CGRect(origin: .zero, size: canvasSize))
    }

    // MARK: - Rasterization

    private func rasterizeShape(into grid: SparseMaskGrid, rect: CGRect, canvasSize: CGSize) {
        guard !rect.isNull && rect.width > 0 && rect.height > 0 else { return }

        let minX = Int(floor(rect.minX))
        let maxX = Int(ceil(rect.maxX))
        let minY = Int(floor(rect.minY))
        let maxY = Int(ceil(rect.maxY))

        let canvasW = Int(canvasSize.width)
        let canvasH = Int(canvasSize.height)

        let clampedMinX = max(0, minX)
        let clampedMaxX = min(canvasW, maxX)
        let clampedMinY = max(0, minY)
        let clampedMaxY = min(canvasH, maxY)

        guard clampedMinX < clampedMaxX && clampedMinY < clampedMaxY else { return }

        switch configuration.shape {
        case .rectangle:
            let X0 = Float(rect.minX)
            let X1 = Float(rect.maxX)
            let Y0 = Float(rect.minY)
            let Y1 = Float(rect.maxY)

            for y in clampedMinY..<clampedMaxY {
                let fy = Float(y)
                let muy: Float
                if configuration.antiAliased {
                    muy = max(0.0, min(1.0, min(fy + 1.0, Y1) - max(fy, Y0)))
                } else {
                    muy = (fy + 0.5 >= Y0 && fy + 0.5 <= Y1) ? 1.0 : 0.0
                }
                guard muy > 0.0001 else { continue }

                for x in clampedMinX..<clampedMaxX {
                    let fx = Float(x)
                    let mux: Float
                    if configuration.antiAliased {
                        mux = max(0.0, min(1.0, min(fx + 1.0, X1) - max(fx, X0)))
                    } else {
                        mux = (fx + 0.5 >= X0 && fx + 0.5 <= X1) ? 1.0 : 0.0
                    }
                    let alpha = mux * muy
                    if alpha > 0.0001 {
                        let val = UInt8(max(0, min(255, Int(alpha * 255.0 + 0.5))))
                        grid.setAlpha(x: x, y: y, value: val)
                    }
                }
            }

        case .ellipse:
            let cx = Float(rect.midX)
            let cy = Float(rect.midY)
            let a = Float(rect.width * 0.5)
            let b = Float(rect.height * 0.5)

            guard a > 0.001 && b > 0.001 else { return }

            for y in clampedMinY..<clampedMaxY {
                let py = Float(y) + 0.5 - cy
                let normY = py / b
                let normYSq = normY * normY

                for x in clampedMinX..<clampedMaxX {
                    let px = Float(x) + 0.5 - cx
                    let normX = px / a
                    let rho = sqrt(normX * normX + normYSq)

                    let alpha: Float
                    if configuration.antiAliased {
                        let theta = atan2(py, px)
                        let cosT = cos(theta)
                        let sinT = sin(theta)
                        let denom = sqrt(b * b * cosT * cosT + a * a * sinT * sinT)
                        let boundaryDist = (rho - 1.0) * (a * b / max(0.001, denom))
                        alpha = max(0.0, min(1.0, 0.5 - boundaryDist))
                    } else {
                        alpha = rho <= 1.0 ? 1.0 : 0.0
                    }

                    if alpha > 0.0001 {
                        let val = UInt8(max(0, min(255, Int(alpha * 255.0 + 0.5))))
                        grid.setAlpha(x: x, y: y, value: val)
                    }
                }
            }
        }
    }

    // MARK: - Feathering

    private func applyFeather(to grid: SparseMaskGrid, radius: CGFloat, canvasSize: CGSize) {
        let sigma = Float(radius * 0.5)
        let kernelRadius = max(1, Int(ceil(3.0 * sigma)))
        let twoSigmaSq = 2.0 * sigma * sigma

        var weights = [Float](repeating: 0, count: kernelRadius * 2 + 1)
        var sumWeight: Float = 0.0
        for k in -kernelRadius...kernelRadius {
            let w = exp(-Float(k * k) / twoSigmaSq)
            weights[k + kernelRadius] = w
            sumWeight += w
        }
        for i in 0..<weights.count {
            weights[i] /= sumWeight
        }

        let canvasW = Int(canvasSize.width)
        let canvasH = Int(canvasSize.height)

        // Find bounding box of active pixels to blur
        var minX = canvasW
        var maxX = 0
        var minY = canvasH
        var maxY = 0

        for coord in grid.allAllocatedCoordinates() {
            let tx = coord.x * SparseMaskGrid.tileSize
            let ty = coord.y * SparseMaskGrid.tileSize
            minX = min(minX, tx)
            maxX = max(maxX, tx + SparseMaskGrid.tileSize)
            minY = min(minY, ty)
            maxY = max(maxY, ty + SparseMaskGrid.tileSize)
        }

        minX = max(0, minX - kernelRadius)
        maxX = min(canvasW, maxX + kernelRadius)
        minY = max(0, minY - kernelRadius)
        maxY = min(canvasH, maxY + kernelRadius)

        guard minX < maxX && minY < maxY else { return }

        // Horizontal pass
        var hPass = [Float](repeating: 0.0, count: (maxX - minX) * (maxY - minY))
        let strideW = maxX - minX

        for y in minY..<maxY {
            let rowOffset = (y - minY) * strideW
            for x in minX..<maxX {
                var sum: Float = 0.0
                for k in -kernelRadius...kernelRadius {
                    let sx = max(0, min(canvasW - 1, x + k))
                    let a = Float(grid.alphaAt(x: sx, y: y))
                    sum += a * weights[k + kernelRadius]
                }
                hPass[rowOffset + (x - minX)] = sum
            }
        }

        // Vertical pass directly into grid
        for y in minY..<maxY {
            for x in minX..<maxX {
                var sum: Float = 0.0
                for k in -kernelRadius...kernelRadius {
                    let sy = max(0, min(canvasH - 1, y + k))
                    if sy >= minY && sy < maxY {
                        let sampleVal = hPass[(sy - minY) * strideW + (x - minX)]
                        sum += sampleVal * weights[k + kernelRadius]
                    }
                }
                let val = UInt8(max(0, min(255, Int(sum + 0.5))))
                grid.setAlpha(x: x, y: y, value: val)
            }
        }
    }

    // MARK: - Combinatorial Selection Algebra

    private func applySelectionMode(tempGrid: SparseMaskGrid, mask: SelectionMask, mode: SelectionMode) {
        switch mode {
        case .newSelection:
            mask.deselect()
            for (coord, tile) in tempGrid.allTiles() {
                mask.maskGrid.setTile(at: coord, data: tile)
            }

        case .add:
            let allCoords = Set(mask.maskGrid.allAllocatedCoordinates()).union(tempGrid.allAllocatedCoordinates())
            for coord in allCoords {
                var baseTile = mask.maskGrid.getTile(at: coord) ?? [UInt8](repeating: 0, count: SparseMaskGrid.bytesPerTile)
                guard let newTile = tempGrid.getTile(at: coord) else { continue }

                for i in 0..<SparseMaskGrid.bytesPerTile {
                    let mOld = Int(baseTile[i])
                    let mNew = Int(newTile[i])
                    let mRes = min(255, mOld + mNew - (mOld * mNew) / 255)
                    baseTile[i] = UInt8(mRes)
                }
                mask.maskGrid.setTile(at: coord, data: baseTile)
            }

        case .subtract:
            for coord in tempGrid.allAllocatedCoordinates() {
                guard var baseTile = mask.maskGrid.getTile(at: coord),
                      let subTile = tempGrid.getTile(at: coord) else { continue }

                var allZero = true
                for i in 0..<SparseMaskGrid.bytesPerTile {
                    let mOld = Float(baseTile[i])
                    let mSub = Float(subTile[i]) / 255.0
                    let mRes = max(0.0, mOld * (1.0 - mSub))
                    let byteVal = UInt8(max(0, min(255, Int(mRes + 0.5))))
                    baseTile[i] = byteVal
                    if byteVal > 0 { allZero = false }
                }

                if allZero {
                    mask.maskGrid.removeTile(at: coord)
                } else {
                    mask.maskGrid.setTile(at: coord, data: baseTile)
                }
            }

        case .intersect:
            for coord in mask.maskGrid.allAllocatedCoordinates() {
                guard var baseTile = mask.maskGrid.getTile(at: coord) else { continue }
                if let newTile = tempGrid.getTile(at: coord) {
                    var allZero = true
                    for i in 0..<SparseMaskGrid.bytesPerTile {
                        let mOld = Int(baseTile[i])
                        let mNew = Int(newTile[i])
                        let mRes = (mOld * mNew + 127) / 255
                        baseTile[i] = UInt8(mRes)
                        if mRes > 0 { allZero = false }
                    }
                    if allZero {
                        mask.maskGrid.removeTile(at: coord)
                    } else {
                        mask.maskGrid.setTile(at: coord, data: baseTile)
                    }
                } else {
                    mask.maskGrid.removeTile(at: coord)
                }
            }
        }
    }
}
