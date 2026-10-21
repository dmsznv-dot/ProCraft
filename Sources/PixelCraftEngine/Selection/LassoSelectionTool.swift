import CoreGraphics
import Foundation

public enum LassoType: String, CaseIterable, Sendable, Codable {
    case freehand
    case polygonal
}

public struct LassoConfiguration: Sendable, Codable, Equatable {
    public var type: LassoType
    public var mode: SelectionMode
    public var featherRadius: CGFloat

    public init(
        type: LassoType = .freehand,
        mode: SelectionMode = .newSelection,
        featherRadius: CGFloat = 0.0
    ) {
        self.type = type
        self.mode = mode
        self.featherRadius = max(0.0, min(100.0, featherRadius))
    }
}

public final class LassoSelectionTool: DrawingTool, @unchecked Sendable {
    public let toolType: ToolType = .lasso
    public var configuration: LassoConfiguration

    // State machine
    public private(set) var vertices: [CGPoint] = []
    public private(set) var rubberBandPoint: CGPoint?
    public private(set) var isTracking: Bool = false

    public var isNearOrigin: Bool {
        guard vertices.count >= 3, let current = rubberBandPoint else { return false }
        return hypot(current.x - vertices[0].x, current.y - vertices[0].y) <= 8.0
    }

    public init(configuration: LassoConfiguration = LassoConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - DrawingTool Interface

    public func mouseDown(at canvasPoint: CGPoint, document: Document) {
        switch configuration.type {
        case .freehand:
            isTracking = true
            vertices = [canvasPoint]
            rubberBandPoint = canvasPoint

        case .polygonal:
            if !isTracking {
                isTracking = true
                vertices = [canvasPoint]
                rubberBandPoint = canvasPoint
            } else {
                if vertices.count >= 3 && isNearOrigin {
                    // Closed by clicking near origin
                    commitPolygon(document: document)
                } else {
                    vertices.append(canvasPoint)
                    rubberBandPoint = canvasPoint
                }
            }
        }
    }

    public func mouseDragged(to canvasPoint: CGPoint, document: Document) {
        guard isTracking else { return }

        switch configuration.type {
        case .freehand:
            guard let lastPt = vertices.last else { return }
            if hypot(canvasPoint.x - lastPt.x, canvasPoint.y - lastPt.y) >= 2.0 {
                vertices.append(canvasPoint)
            }
            rubberBandPoint = canvasPoint

        case .polygonal:
            rubberBandPoint = canvasPoint
        }
    }

    public func mouseUp(at canvasPoint: CGPoint, document: Document) {
        switch configuration.type {
        case .freehand:
            guard isTracking else { return }
            if let lastPt = vertices.last, hypot(canvasPoint.x - lastPt.x, canvasPoint.y - lastPt.y) >= 1.0 {
                vertices.append(canvasPoint)
            }
            isTracking = false
            rubberBandPoint = nil

            if vertices.count >= 3 {
                commitPolygon(document: document)
            } else {
                vertices.removeAll()
            }

        case .polygonal:
            // Polygonal lasso remains in tracking state across clicks
            break
        }
    }

    public func cancel(document: Document) {
        isTracking = false
        vertices.removeAll()
        rubberBandPoint = nil
    }

    // MARK: - Polygonal Lasso Controls

    public func removeLastVertex() {
        guard isTracking && !vertices.isEmpty else { return }
        vertices.removeLast()
        if vertices.isEmpty {
            isTracking = false
            rubberBandPoint = nil
        } else {
            rubberBandPoint = vertices.last
        }
    }

    public func handleDoubleClick(document: Document) {
        guard isTracking && vertices.count >= 3 else { return }
        commitPolygon(document: document)
    }

    public func handleEnterKey(document: Document) {
        guard isTracking && vertices.count >= 3 else { return }
        commitPolygon(document: document)
    }

    // MARK: - Polygon Rasterization & Commit

    public func commitPolygon(document: Document) {
        guard vertices.count >= 3, let mask = document.selectionMask else {
            isTracking = false
            vertices.removeAll()
            rubberBandPoint = nil
            return
        }

        let tempGrid = SparseMaskGrid(canvasSize: document.canvasSize)
        rasterizePolygonEvenOdd(points: vertices, into: tempGrid, canvasSize: document.canvasSize)

        if configuration.featherRadius > 0.5 {
            applyFeather(to: tempGrid, radius: configuration.featherRadius, canvasSize: document.canvasSize)
        }

        applySelectionMode(tempGrid: tempGrid, mask: mask, mode: configuration.mode)

        isTracking = false
        vertices.removeAll()
        rubberBandPoint = nil
    }

    private func rasterizePolygonEvenOdd(points: [CGPoint], into grid: SparseMaskGrid, canvasSize: CGSize) {
        let n = points.count
        guard n >= 3 else { return }

        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for p in points {
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }

        let startY = max(0, Int(floor(minY)))
        let endY = min(Int(canvasSize.height) - 1, Int(ceil(maxY)))
        guard startY <= endY else { return }

        let canvasW = Int(canvasSize.width)

        for y in startY...endY {
            let scanY = CGFloat(y) + 0.5
            var nodeX: [CGFloat] = []

            var j = n - 1
            for i in 0..<n {
                let pI = points[i]
                let pJ = points[j]

                if (pI.y < scanY && pJ.y >= scanY) || (pJ.y < scanY && pI.y >= scanY) {
                    let intersectX = pI.x + (scanY - pI.y) / (pJ.y - pI.y) * (pJ.x - pI.x)
                    nodeX.append(intersectX)
                }
                j = i
            }

            guard nodeX.count >= 2 else { continue }
            nodeX.sort()

            // Fill spans between pairs (Even-Odd rule)
            var idx = 0
            while idx < nodeX.count - 1 {
                let xLeft = max(0, Int(floor(nodeX[idx])))
                let xRight = min(canvasW - 1, Int(ceil(nodeX[idx + 1])))

                if xLeft <= xRight {
                    for x in xLeft...xRight {
                        grid.setAlpha(x: x, y: y, value: 255)
                    }
                }
                idx += 2
            }
        }
    }

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
        for i in 0..<weights.count { weights[i] /= sumWeight }

        let canvasW = Int(canvasSize.width)
        let canvasH = Int(canvasSize.height)

        var minX = canvasW, maxX = 0, minY = canvasH, maxY = 0
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
