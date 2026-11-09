import CoreGraphics
import Foundation
import simd

public enum BrushShape: String, CaseIterable, Sendable, Codable {
    case round
    case square
    case soft
}

public struct BrushConfiguration: Sendable, Codable, Equatable {
    public var shape: BrushShape
    public var size: Float       // 1.0 ... 500.0 px
    public var opacity: Float    // 0.0 ... 1.0
    public var flow: Float       // 0.0 ... 1.0
    public var spacing: Float    // 0.05 ... 1.0 (fraction of diameter)
    public var hardness: Float   // 0.0 ... 1.0
    public var color: SIMD4<Float> // Straight RGBA [0.0 ... 1.0]
    public var blendMode: BlendMode

    public init(
        shape: BrushShape = .round,
        size: Float = 20.0,
        opacity: Float = 1.0,
        flow: Float = 1.0,
        spacing: Float = 0.15,
        hardness: Float = 0.8,
        color: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
        blendMode: BlendMode = .normal
    ) {
        self.shape = shape
        self.size = max(1.0, min(500.0, size))
        self.opacity = max(0.0, min(1.0, opacity))
        self.flow = max(0.0, min(1.0, flow))
        self.spacing = max(0.05, min(1.0, spacing))
        self.hardness = max(0.0, min(1.0, hardness))
        self.color = color
        self.blendMode = blendMode
    }
}

public final class BrushTool: DrawingTool, @unchecked Sendable {
    public let toolType: ToolType = .brush
    public var configuration: BrushConfiguration

    // Stroke state
    private var isDrawing: Bool = false
    private var inputPoints: [CGPoint] = []
    private var distanceRemainder: Float = 0.0
    private var lastInterpolatedPoint: CGPoint?

    // Per-stroke memory caches
    private var touchedCoords: Set<TileCoord> = []
    private var cachedTiles: [TileCoord: [UInt8]] = [:]
    private var beforeTiles: [TileCoord: Data?] = [:]
    private var strokeCoverage: [TileCoord: [Float]] = [:]
    /// Tiles modified since the last live-preview flush.
    private var pendingPreview: Set<TileCoord> = []

    public init(configuration: BrushConfiguration = BrushConfiguration()) {
        self.configuration = configuration
    }

    public func mouseDown(at canvasPoint: CGPoint, document: Document) {
        guard let layer = document.activeLayer as? BitmapLayer, !layer.isLocked else { return }

        isDrawing = true
        inputPoints = [canvasPoint]
        distanceRemainder = 0.0
        lastInterpolatedPoint = canvasPoint
        touchedCoords.removeAll()
        cachedTiles.removeAll()
        beforeTiles.removeAll()
        strokeCoverage.removeAll()
        pendingPreview.removeAll()

        // Immediate single stamp at click position
        renderStamp(at: canvasPoint, document: document, layer: layer)
        flushPreview(layer: layer)
    }

    public func mouseDragged(to canvasPoint: CGPoint, document: Document) {
        guard isDrawing, let layer = document.activeLayer as? BitmapLayer else { return }

        guard let lastPt = inputPoints.last else { return }
        let d = hypot(canvasPoint.x - lastPt.x, canvasPoint.y - lastPt.y)
        guard d >= 1.0 else { return }

        inputPoints.append(canvasPoint)

        let stepDist = max(1.0, configuration.size * configuration.spacing)

        if inputPoints.count == 2 {
            // Linear interpolate between first 2 points
            interpolateLine(from: inputPoints[0], to: inputPoints[1], step: stepDist, document: document, layer: layer)
        } else {
            // Catmull-Rom spline on the last segment
            let n = inputPoints.count
            let p0 = n >= 4 ? inputPoints[n - 4] : inputPoints[0]
            let p1 = inputPoints[n - 3]
            let p2 = inputPoints[n - 2]
            let p3 = inputPoints[n - 1]

            interpolateCatmullRom(p0: p0, p1: p1, p2: p2, p3: p3, step: stepDist, document: document, layer: layer)
        }
        flushPreview(layer: layer)
    }

    /// Pushes the tiles touched by the latest stamps into the layer so the stroke is visible while drawing.
    private func flushPreview(layer: BitmapLayer) {
        for coord in pendingPreview {
            if let bytes = cachedTiles[coord] {
                layer.tileGrid.writeTileBytes(coord: coord, bytes: bytes)
            }
        }
        pendingPreview.removeAll()
    }

    public func mouseUp(at canvasPoint: CGPoint, document: Document) {
        guard isDrawing, let layer = document.activeLayer as? BitmapLayer else { return }

        let stepDist = max(1.0, configuration.size * configuration.spacing)
        if inputPoints.count >= 2 {
            let lastPt = inputPoints[inputPoints.count - 1]
            let prevPt = inputPoints[inputPoints.count - 2]
            interpolateLine(from: prevPt, to: lastPt, step: stepDist, document: document, layer: layer)
            renderStamp(at: lastPt, document: document, layer: layer)
        }
        renderStamp(at: canvasPoint, document: document, layer: layer)

        // Commit cached tiles to layer's SparseTileGrid
        var afterTiles: [TileCoord: Data?] = [:]
        for coord in touchedCoords {
            if let tileBytes = cachedTiles[coord] {
                let data = Data(tileBytes)
                layer.tileGrid.loadTileData(coord: coord, data: data)
                afterTiles[coord] = data
            }
        }

        if !touchedCoords.isEmpty {
            let command = TileDeltaUndoCommand(
                actionName: "Brush Stroke",
                layerId: layer.id,
                beforeTiles: beforeTiles,
                afterTiles: afterTiles
            )
            document.undoManager.registerCommand(command)
        }

        // Cleanup
        isDrawing = false
        inputPoints.removeAll()
        touchedCoords.removeAll()
        cachedTiles.removeAll()
        beforeTiles.removeAll()
        strokeCoverage.removeAll()
        distanceRemainder = 0.0
        lastInterpolatedPoint = nil
    }

    public func cancel(document: Document) {
        // Roll back the live preview of the unfinished stroke.
        if isDrawing, let layer = document.activeLayer as? BitmapLayer {
            for (coord, maybeData) in beforeTiles {
                if let data = maybeData {
                    layer.tileGrid.loadTileData(coord: coord, data: data)
                } else {
                    layer.tileGrid.removeTile(at: coord)
                }
            }
        }
        pendingPreview.removeAll()
        isDrawing = false
        inputPoints.removeAll()
        touchedCoords.removeAll()
        cachedTiles.removeAll()
        beforeTiles.removeAll()
        strokeCoverage.removeAll()
        distanceRemainder = 0.0
        lastInterpolatedPoint = nil
    }

    // MARK: - Catmull-Rom Interpolation

    private func interpolateLine(
        from p1: CGPoint,
        to p2: CGPoint,
        step: Float,
        document: Document,
        layer: BitmapLayer
    ) {
        let totalDist = Float(hypot(p2.x - p1.x, p2.y - p1.y))
        guard totalDist > 0.0001 else { return }

        var currentDist = step - distanceRemainder
        while currentDist <= totalDist {
            let u = CGFloat(currentDist / totalDist)
            let stampPt = CGPoint(
                x: p1.x + u * (p2.x - p1.x),
                y: p1.y + u * (p2.y - p1.y)
            )
            renderStamp(at: stampPt, document: document, layer: layer)
            lastInterpolatedPoint = stampPt
            currentDist += step
        }
        distanceRemainder = totalDist - (currentDist - step)
    }

    private func interpolateCatmullRom(
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        step: Float,
        document: Document,
        layer: BitmapLayer
    ) {
        let subSteps = 20
        var prevPt = p1

        for i in 1...subSteps {
            let t = Float(i) / Float(subSteps)
            let currPt = evaluateCatmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
            let segDist = Float(hypot(currPt.x - prevPt.x, currPt.y - prevPt.y))

            var subDist = step - distanceRemainder
            while subDist <= segDist {
                let u = CGFloat(subDist / max(0.0001, segDist))
                let stampPt = CGPoint(
                    x: prevPt.x + u * (currPt.x - prevPt.x),
                    y: prevPt.y + u * (currPt.y - prevPt.y)
                )
                renderStamp(at: stampPt, document: document, layer: layer)
                lastInterpolatedPoint = stampPt
                subDist += step
            }
            distanceRemainder = segDist - (subDist - step)
            prevPt = currPt
        }
    }

    private func evaluateCatmullRom(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, t: Float) -> CGPoint {
        // Centripetal Catmull-Rom alpha = 0.5
        func getKnot(pA: CGPoint, pB: CGPoint, tA: Float) -> Float {
            let d = hypot(pB.x - pA.x, pB.y - pA.y)
            return tA + pow(Float(d), 0.5)
        }

        let t0: Float = 0.0
        let t1 = getKnot(pA: p0, pB: p1, tA: t0)
        let t2 = getKnot(pA: p1, pB: p2, tA: t1)
        let t3 = getKnot(pA: p2, pB: p3, tA: t2)

        let targetT = t1 + t * (t2 - t1)

        func lerp(pA: CGPoint, pB: CGPoint, tA: Float, tB: Float, target: Float) -> CGPoint {
            if abs(tB - tA) < 0.0001 { return pA }
            let f = CGFloat((target - tA) / (tB - tA))
            return CGPoint(x: pA.x + f * (pB.x - pA.x), y: pA.y + f * (pB.y - pA.y))
        }

        let a1 = lerp(pA: p0, pB: p1, tA: t0, tB: t1, target: targetT)
        let a2 = lerp(pA: p1, pB: p2, tA: t1, tB: t2, target: targetT)
        let a3 = lerp(pA: p2, pB: p3, tA: t2, tB: t3, target: targetT)

        let b1 = lerp(pA: a1, pB: a2, tA: t0, tB: t2, target: targetT)
        let b2 = lerp(pA: a2, pB: a3, tA: t1, tB: t3, target: targetT)

        return lerp(pA: b1, pB: b2, tA: t1, tB: t2, target: targetT)
    }

    // MARK: - Stamp Rasterization & Blitting

    private func renderStamp(at point: CGPoint, document: Document, layer: BitmapLayer) {
        let cx = Float(point.x)
        let cy = Float(point.y)
        let radius = configuration.size * 0.5
        let tileSize = SparseTileGrid.tileSize

        let minX = Int(floor(cx - radius))
        let maxX = Int(ceil(cx + radius))
        let minY = Int(floor(cy - radius))
        let maxY = Int(ceil(cy + radius))

        let canvasW = Int(document.canvasSize.width)
        let canvasH = Int(document.canvasSize.height)

        guard minX < canvasW && maxX >= 0 && minY < canvasH && maxY >= 0 else { return }

        let startTx = max(0, minX / tileSize)
        let endTx = min(layer.tileGrid.gridColumns - 1, maxX / tileSize)
        let startTy = max(0, minY / tileSize)
        let endTy = min(layer.tileGrid.gridRows - 1, maxY / tileSize)

        let mask = document.selectionMask
        let hasMask = mask?.hasActiveSelection ?? false

        for ty in startTy...endTy {
            for tx in startTx...endTx {
                let coord = TileCoord(x: tx, y: ty)

                // Selection tile culling
                if hasMask, let m = mask, !m.maskGrid.isTileAllocated(at: coord) {
                    continue
                }

                // Ensure tile is cached
                if cachedTiles[coord] == nil {
                    let beforeData = layer.tileGrid.extractTileData(coord: coord)
                    beforeTiles[coord] = beforeData
                    if let d = beforeData {
                        var bytes = [UInt8](repeating: 0, count: SparseTileGrid.bytesPerTile)
                        d.copyBytes(to: &bytes, count: SparseTileGrid.bytesPerTile)
                        cachedTiles[coord] = bytes
                    } else {
                        cachedTiles[coord] = [UInt8](repeating: 0, count: SparseTileGrid.bytesPerTile)
                    }
                    strokeCoverage[coord] = [Float](repeating: 0.0, count: tileSize * tileSize)
                }

                touchedCoords.insert(coord)
                pendingPreview.insert(coord)

                let tileOriginX = tx * tileSize
                let tileOriginY = ty * tileSize

                let localX0 = max(0, minX - tileOriginX)
                let localX1 = min(tileSize - 1, maxX - tileOriginX)
                let localY0 = max(0, minY - tileOriginY)
                let localY1 = min(tileSize - 1, maxY - tileOriginY)

                guard localX0 <= localX1 && localY0 <= localY1 else { continue }

                // Move the buffers out of the dictionaries so they are uniquely referenced and mutated
                // in place (subscript-copy here used to duplicate 2 MB on every single stamp).
                guard var tileBytes = cachedTiles.removeValue(forKey: coord),
                      var coverage = strokeCoverage.removeValue(forKey: coord) else { continue }

                for ly in localY0...localY1 {
                    let gy = tileOriginY + ly
                    let dy = (Float(gy) + 0.5) - cy
                    let rowOffset = ly * tileSize

                    for lx in localX0...localX1 {
                        let gx = tileOriginX + lx
                        let dx = (Float(gx) + 0.5) - cx

                        let stampAlpha = stampShapeAlpha(dx: dx, dy: dy, radius: radius)
                        guard stampAlpha > 0.0001 else { continue }

                        let maskAlpha: Float
                        if hasMask, let m = mask {
                            maskAlpha = Float(m.alphaAt(x: gx, y: gy)) / 255.0
                            guard maskAlpha > 0.0001 else { continue }
                        } else {
                            maskAlpha = 1.0
                        }

                        let pixelIndex = rowOffset + lx
                        let byteOffset = pixelIndex * 4

                        let oldCover = coverage[pixelIndex]
                        let stampDeposit = stampAlpha * configuration.flow * maskAlpha
                        let newCover = oldCover + stampDeposit * (1.0 - oldCover)
                        let maxOpacity = configuration.opacity

                        let oldEffective = min(maxOpacity, oldCover)
                        let newEffective = min(maxOpacity, newCover)
                        let deltaAlpha = newEffective - oldEffective
                        coverage[pixelIndex] = newCover

                        guard deltaAlpha > 0.0001 else { continue }

                        // Effective blending alpha
                        let depositAlpha = deltaAlpha / max(0.0001, (1.0 - oldEffective))

                        let bgR = Float(tileBytes[byteOffset]) / 255.0
                        let bgG = Float(tileBytes[byteOffset + 1]) / 255.0
                        let bgB = Float(tileBytes[byteOffset + 2]) / 255.0
                        let bgA = Float(tileBytes[byteOffset + 3]) / 255.0

                        if layer.lockAlpha {
                            // Invariant: locked alpha cannot change, transparent pixels cannot be painted
                            guard bgA > 0.0001 else { continue }

                            let brushR = configuration.color.x
                            let brushG = configuration.color.y
                            let brushB = configuration.color.z

                            let blended = configuration.blendMode.evaluate(
                                backdrop: SIMD3<Float>(bgR, bgG, bgB),
                                source: SIMD3<Float>(brushR, brushG, brushB)
                            )

                            let outR = bgR + (blended.x - bgR) * depositAlpha
                            let outG = bgG + (blended.y - bgG) * depositAlpha
                            let outB = bgB + (blended.z - bgB) * depositAlpha

                            tileBytes[byteOffset] = UInt8(max(0, min(255, Int(outR * 255.0 + 0.5))))
                            tileBytes[byteOffset + 1] = UInt8(max(0, min(255, Int(outG * 255.0 + 0.5))))
                            tileBytes[byteOffset + 2] = UInt8(max(0, min(255, Int(outB * 255.0 + 0.5))))
                            // bgA byte strictly unchanged
                        } else {
                            let srcColor = SIMD4<Float>(
                                configuration.color.x,
                                configuration.color.y,
                                configuration.color.z,
                                depositAlpha * configuration.color.w
                            )
                            let backdropColor = SIMD4<Float>(bgR, bgG, bgB, bgA)

                            let composited = configuration.blendMode.composite(
                                backdrop: backdropColor,
                                source: srcColor,
                                opacity: 1.0,
                                lockAlpha: false
                            )

                            tileBytes[byteOffset] = UInt8(max(0, min(255, Int(composited.x * 255.0 + 0.5))))
                            tileBytes[byteOffset + 1] = UInt8(max(0, min(255, Int(composited.y * 255.0 + 0.5))))
                            tileBytes[byteOffset + 2] = UInt8(max(0, min(255, Int(composited.z * 255.0 + 0.5))))
                            tileBytes[byteOffset + 3] = UInt8(max(0, min(255, Int(composited.w * 255.0 + 0.5))))
                        }
                    }
                }

                cachedTiles[coord] = tileBytes
                strokeCoverage[coord] = coverage
            }
        }
    }

    private func stampShapeAlpha(dx: Float, dy: Float, radius: Float) -> Float {
        switch configuration.shape {
        case .round:
            let d = hypot(dx, dy)
            return max(0.0, min(1.0, radius - d + 0.5))
        case .square:
            let mux = max(0.0, min(1.0, radius - abs(dx) + 0.5))
            let muy = max(0.0, min(1.0, radius - abs(dy) + 0.5))
            return mux * muy
        case .soft:
            let d = hypot(dx, dy)
            let rInner = radius * configuration.hardness
            let rOuter = radius
            if d <= rInner { return 1.0 }
            if d >= rOuter { return 0.0 }
            let xi = (d - rInner) / (rOuter - rInner)
            return (1.0 - xi) * (1.0 - xi) * (1.0 + 2.0 * xi)
        }
    }
}
