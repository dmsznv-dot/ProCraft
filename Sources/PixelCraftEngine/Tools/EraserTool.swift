import CoreGraphics
import Foundation
import simd

public final class EraserTool: DrawingTool, @unchecked Sendable {
    public let toolType: ToolType = .eraser
    public var configuration: BrushConfiguration

    // Stroke state
    private var isErasing: Bool = false
    private var inputPoints: [CGPoint] = []
    private var distanceRemainder: Float = 0.0

    // Memory caches
    private var touchedCoords: Set<TileCoord> = []
    private var cachedTiles: [TileCoord: [UInt8]] = [:]
    private var beforeTiles: [TileCoord: Data?] = [:]
    private var pendingPreview: Set<TileCoord> = []

    public init(configuration: BrushConfiguration = BrushConfiguration()) {
        self.configuration = configuration
    }

    public func mouseDown(at canvasPoint: CGPoint, document: Document) {
        guard let layer = document.activeLayer as? BitmapLayer, !layer.isLocked else { return }

        // Invariant: locked alpha prevents any erasing (alpha cannot be changed)
        if layer.lockAlpha { return }

        isErasing = true
        inputPoints = [canvasPoint]
        distanceRemainder = 0.0
        touchedCoords.removeAll()
        cachedTiles.removeAll()
        beforeTiles.removeAll()
        pendingPreview.removeAll()

        renderEraseStamp(at: canvasPoint, document: document, layer: layer)
        flushPreview(layer: layer)
    }

    /// Pushes erased tiles into the layer so the result is visible while dragging.
    private func flushPreview(layer: BitmapLayer) {
        for coord in pendingPreview {
            if let bytes = cachedTiles[coord] {
                layer.tileGrid.writeTileBytes(coord: coord, bytes: bytes)
            }
        }
        pendingPreview.removeAll()
    }

    public func mouseDragged(to canvasPoint: CGPoint, document: Document) {
        guard isErasing, let layer = document.activeLayer as? BitmapLayer else { return }
        if layer.lockAlpha { return }

        guard let lastPt = inputPoints.last else { return }
        let d = hypot(canvasPoint.x - lastPt.x, canvasPoint.y - lastPt.y)
        guard d >= 1.0 else { return }

        inputPoints.append(canvasPoint)

        let stepDist = max(1.0, configuration.size * configuration.spacing)
        interpolateEraseLine(from: lastPt, to: canvasPoint, step: stepDist, document: document, layer: layer)
        flushPreview(layer: layer)
    }

    public func mouseUp(at canvasPoint: CGPoint, document: Document) {
        guard isErasing, let layer = document.activeLayer as? BitmapLayer else { return }

        var afterTiles: [TileCoord: Data?] = [:]

        for coord in touchedCoords {
            if let tileBytes = cachedTiles[coord] {
                // Check if all pixels are completely transparent
                var isCompletelyEmpty = true
                for i in stride(from: 3, to: tileBytes.count, by: 4) {
                    if tileBytes[i] > 0 {
                        isCompletelyEmpty = false
                        break
                    }
                }

                if isCompletelyEmpty {
                    // Prune tile to reclaim 1 MB RAM
                    layer.tileGrid.removeTile(at: coord)
                    // NB: `afterTiles[coord] = nil` would *remove* the key; we need an explicit nil entry
                    // so redo knows to delete this tile again.
                    afterTiles.updateValue(nil, forKey: coord)
                } else {
                    let data = Data(tileBytes)
                    layer.tileGrid.loadTileData(coord: coord, data: data)
                    afterTiles[coord] = data
                }
            }
        }

        if !touchedCoords.isEmpty {
            let command = TileDeltaUndoCommand(
                actionName: "Eraser",
                layerId: layer.id,
                beforeTiles: beforeTiles,
                afterTiles: afterTiles
            )
            document.undoManager.registerCommand(command)
        }

        isErasing = false
        inputPoints.removeAll()
        touchedCoords.removeAll()
        cachedTiles.removeAll()
        beforeTiles.removeAll()
        distanceRemainder = 0.0
    }

    public func cancel(document: Document) {
        if isErasing, let layer = document.activeLayer as? BitmapLayer {
            for (coord, maybeData) in beforeTiles {
                if let data = maybeData {
                    layer.tileGrid.loadTileData(coord: coord, data: data)
                } else {
                    layer.tileGrid.removeTile(at: coord)
                }
            }
        }
        pendingPreview.removeAll()
        isErasing = false
        inputPoints.removeAll()
        touchedCoords.removeAll()
        cachedTiles.removeAll()
        beforeTiles.removeAll()
        distanceRemainder = 0.0
    }

    private func interpolateEraseLine(
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
            renderEraseStamp(at: stampPt, document: document, layer: layer)
            currentDist += step
        }
        distanceRemainder = totalDist - (currentDist - step)
    }

    private func renderEraseStamp(at point: CGPoint, document: Document, layer: BitmapLayer) {
        if layer.lockAlpha { return }

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

                // Culling: If selection active and tile not allocated in mask, skip
                if hasMask, let m = mask, !m.maskGrid.isTileAllocated(at: coord) {
                    continue
                }

                // If tile is not allocated in layer AND not yet cached, nothing to erase in this tile
                if cachedTiles[coord] == nil && !layer.tileGrid.isTileAllocated(at: coord) {
                    continue
                }

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

                guard var tileBytes = cachedTiles.removeValue(forKey: coord) else { continue }

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

                        let currentAlphaByte = tileBytes[byteOffset + 3]
                        guard currentAlphaByte > 0 else { continue }

                        let currentAlpha = Float(currentAlphaByte) / 255.0
                        let eraseAmount = stampAlpha * configuration.flow * configuration.opacity * maskAlpha
                        let newAlpha = max(0.0, currentAlpha * (1.0 - eraseAmount))

                        if newAlpha <= 0.0001 {
                            tileBytes[byteOffset] = 0
                            tileBytes[byteOffset + 1] = 0
                            tileBytes[byteOffset + 2] = 0
                            tileBytes[byteOffset + 3] = 0
                        } else {
                            tileBytes[byteOffset + 3] = UInt8(max(0, min(255, Int(newAlpha * 255.0 + 0.5))))
                        }
                    }
                }

                cachedTiles[coord] = tileBytes
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
