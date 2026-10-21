import CoreGraphics
import Foundation
import simd

public enum FloodFillMode: String, CaseIterable, Sendable, Codable {
    case contiguous
    case global
}

public enum ColorDistanceMetric: String, CaseIterable, Sendable, Codable {
    case euclidean
    case manhattan
}

public struct FloodFillConfiguration: Sendable, Codable, Equatable {
    public var tolerance: Float        // 0.0 ... 1.0 (0% ... 100%)
    public var fillColor: SIMD4<Float> // Straight RGBA [0.0 ... 1.0]
    public var mode: FloodFillMode
    public var metric: ColorDistanceMetric

    public init(
        tolerance: Float = 0.1,
        fillColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
        mode: FloodFillMode = .contiguous,
        metric: ColorDistanceMetric = .euclidean
    ) {
        self.tolerance = max(0.0, min(1.0, tolerance))
        self.fillColor = fillColor
        self.mode = mode
        self.metric = metric
    }
}

public struct ScanlineSpan: Sendable {
    public let y: Int
    public let xLeft: Int
    public let xRight: Int
    public let parentY: Int

    public init(y: Int, xLeft: Int, xRight: Int, parentY: Int) {
        self.y = y
        self.xLeft = xLeft
        self.xRight = xRight
        self.parentY = parentY
    }
}

private final class MutableTileBuffer {
    var bytes: [UInt8]

    init(data: Data?) {
        var b = [UInt8](repeating: 0, count: SparseTileGrid.bytesPerTile)
        if let d = data {
            d.copyBytes(to: &b, count: SparseTileGrid.bytesPerTile)
        }
        self.bytes = b
    }
}

private final class VisitedTileBitset {
    var words = [UInt64](repeating: 0, count: 4096)
}

public final class FloodFillTool: DrawingTool, @unchecked Sendable {
    public let toolType: ToolType = .floodFill
    public var configuration: FloodFillConfiguration

    public init(configuration: FloodFillConfiguration = FloodFillConfiguration()) {
        self.configuration = configuration
    }

    public func mouseDown(at canvasPoint: CGPoint, document: Document) {
        executeFill(at: canvasPoint, document: document)
    }

    public func mouseDragged(to canvasPoint: CGPoint, document: Document) {
        // Flood fill does not track drag
    }

    public func mouseUp(at canvasPoint: CGPoint, document: Document) {
        // Flood fill is committed on mouseDown
    }

    public func cancel(document: Document) {
        // No-op
    }

    // MARK: - Core Fill Execution

    public func executeFill(at point: CGPoint, document: Document) {
        guard let layer = document.activeLayer as? BitmapLayer, !layer.isLocked else { return }

        let seedX = Int(point.x)
        let seedY = Int(point.y)
        let canvasW = Int(document.canvasSize.width)
        let canvasH = Int(document.canvasSize.height)

        guard seedX >= 0 && seedX < canvasW && seedY >= 0 && seedY < canvasH else { return }

        let mask = document.selectionMask
        let hasMask = mask?.hasActiveSelection ?? false
        if hasMask, let m = mask, !m.contains(x: seedX, y: seedY) {
            return
        }

        let targetColor = layer.tileGrid.readPixel(x: seedX, y: seedY)
        let fillByteColor = SIMD4<UInt8>(
            UInt8(max(0, min(255, Int(configuration.fillColor.x * 255.0 + 0.5)))),
            UInt8(max(0, min(255, Int(configuration.fillColor.y * 255.0 + 0.5)))),
            UInt8(max(0, min(255, Int(configuration.fillColor.z * 255.0 + 0.5)))),
            UInt8(max(0, min(255, Int(configuration.fillColor.w * 255.0 + 0.5))))
        )

        // If target color already equals fill color and tolerance is zero, nothing to do
        if targetColor == fillByteColor && configuration.tolerance < 0.001 {
            return
        }

        // Lock alpha invariant: Cannot fill transparent pixels on locked alpha layer
        if layer.lockAlpha && targetColor.w == 0 {
            return
        }

        var touchedCoords: Set<TileCoord> = []
        var cachedTiles: [TileCoord: MutableTileBuffer] = [:]
        var beforeTiles: [TileCoord: Data?] = [:]

        func getTileBuffer(coord: TileCoord) -> MutableTileBuffer {
            if let existing = cachedTiles[coord] {
                return existing
            }
            touchedCoords.insert(coord)
            let beforeData = layer.tileGrid.extractTileData(coord: coord)
            beforeTiles[coord] = beforeData
            let buffer = MutableTileBuffer(data: beforeData)
            cachedTiles[coord] = buffer
            return buffer
        }

        func readPixelFast(x: Int, y: Int) -> SIMD4<UInt8> {
            let coord = TileCoord(x: x / SparseTileGrid.tileSize, y: y / SparseTileGrid.tileSize)
            let buf = getTileBuffer(coord: coord)
            let localX = x % SparseTileGrid.tileSize
            let localY = y % SparseTileGrid.tileSize
            let idx = (localY * SparseTileGrid.tileSize + localX) * 4
            return SIMD4<UInt8>(buf.bytes[idx], buf.bytes[idx + 1], buf.bytes[idx + 2], buf.bytes[idx + 3])
        }

        func writePixelFast(x: Int, y: Int, color: SIMD4<UInt8>) {
            let coord = TileCoord(x: x / SparseTileGrid.tileSize, y: y / SparseTileGrid.tileSize)
            let buf = getTileBuffer(coord: coord)
            let localX = x % SparseTileGrid.tileSize
            let localY = y % SparseTileGrid.tileSize
            let idx = (localY * SparseTileGrid.tileSize + localX) * 4

            if layer.lockAlpha {
                buf.bytes[idx] = color.x
                buf.bytes[idx + 1] = color.y
                buf.bytes[idx + 2] = color.z
            } else {
                buf.bytes[idx] = color.x
                buf.bytes[idx + 1] = color.y
                buf.bytes[idx + 2] = color.z
                buf.bytes[idx + 3] = color.w
            }
        }

        switch configuration.mode {
        case .contiguous:
            var visitedGrid: [TileCoord: VisitedTileBitset] = [:]

            func isVisited(x: Int, y: Int) -> Bool {
                let coord = TileCoord(x: x / SparseTileGrid.tileSize, y: y / SparseTileGrid.tileSize)
                guard let bitset = visitedGrid[coord] else { return false }
                let localX = x % SparseTileGrid.tileSize
                let localY = y % SparseTileGrid.tileSize
                let bitIndex = localY * SparseTileGrid.tileSize + localX
                return (bitset.words[bitIndex >> 6] & (UInt64(1) << (bitIndex & 63))) != 0
            }

            func markVisited(x: Int, y: Int) {
                let coord = TileCoord(x: x / SparseTileGrid.tileSize, y: y / SparseTileGrid.tileSize)
                let bitset: VisitedTileBitset
                if let existing = visitedGrid[coord] {
                    bitset = existing
                } else {
                    bitset = VisitedTileBitset()
                    visitedGrid[coord] = bitset
                }
                let localX = x % SparseTileGrid.tileSize
                let localY = y % SparseTileGrid.tileSize
                let bitIndex = localY * SparseTileGrid.tileSize + localX
                bitset.words[bitIndex >> 6] |= (UInt64(1) << (bitIndex & 63))
            }

            func matchesTarget(x: Int, y: Int) -> Bool {
                if x < 0 || x >= canvasW || y < 0 || y >= canvasH { return false }
                if isVisited(x: x, y: y) { return false }

                if hasMask, let m = mask, !m.contains(x: x, y: y) {
                    return false
                }

                let px = readPixelFast(x: x, y: y)
                if layer.lockAlpha && px.w == 0 {
                    return false
                }

                return colorDistance(c1: px, c2: targetColor, metric: configuration.metric) <= configuration.tolerance
            }

            var spanStack: [ScanlineSpan] = []

            // Find initial horizontal span on row seedY
            var initLeft = seedX
            while initLeft - 1 >= 0 && matchesTarget(x: initLeft - 1, y: seedY) {
                initLeft -= 1
            }
            var initRight = seedX
            while initRight + 1 < canvasW && matchesTarget(x: initRight + 1, y: seedY) {
                initRight += 1
            }

            for x in initLeft...initRight {
                markVisited(x: x, y: seedY)
                writePixelFast(x: x, y: seedY, color: fillByteColor)
            }
            spanStack.append(ScanlineSpan(y: seedY, xLeft: initLeft, xRight: initRight, parentY: seedY))

            // Non-recursive scanline span fill
            while let span = spanStack.popLast() {
                for nextY in [span.y - 1, span.y + 1] {
                    guard nextY >= 0 && nextY < canvasH else { continue }

                    var x = span.xLeft
                    while x <= span.xRight {
                        if matchesTarget(x: x, y: nextY) {
                            var runLeft = x
                            while runLeft - 1 >= 0 && matchesTarget(x: runLeft - 1, y: nextY) {
                                runLeft -= 1
                            }
                            var runRight = x
                            while runRight + 1 < canvasW && matchesTarget(x: runRight + 1, y: nextY) {
                                runRight += 1
                            }

                            for fillX in runLeft...runRight {
                                markVisited(x: fillX, y: nextY)
                                writePixelFast(x: fillX, y: nextY, color: fillByteColor)
                            }

                            spanStack.append(ScanlineSpan(y: nextY, xLeft: runLeft, xRight: runRight, parentY: span.y))
                            x = runRight + 1
                        } else {
                            x += 1
                        }
                    }
                }
            }

        case .global:
            let tileSize = SparseTileGrid.tileSize
            for ty in 0..<layer.tileGrid.gridRows {
                for tx in 0..<layer.tileGrid.gridColumns {
                    let coord = TileCoord(x: tx, y: ty)

                    if !layer.tileGrid.isTileAllocated(at: coord) && targetColor.w > 0 && configuration.tolerance < 0.5 {
                        continue
                    }
                    if hasMask, let m = mask, !m.maskGrid.isTileAllocated(at: coord) {
                        continue
                    }

                    let tileOriginX = tx * tileSize
                    let tileOriginY = ty * tileSize

                    let endX = min(tileSize, canvasW - tileOriginX)
                    let endY = min(tileSize, canvasH - tileOriginY)
                    guard endX > 0 && endY > 0 else { continue }

                    for ly in 0..<endY {
                        let gy = tileOriginY + ly
                        for lx in 0..<endX {
                            let gx = tileOriginX + lx

                            if hasMask, let m = mask, !m.contains(x: gx, y: gy) {
                                continue
                            }

                            let px = readPixelFast(x: gx, y: gy)
                            if layer.lockAlpha && px.w == 0 {
                                continue
                            }

                            if colorDistance(c1: px, c2: targetColor, metric: configuration.metric) <= configuration.tolerance {
                                writePixelFast(x: gx, y: gy, color: fillByteColor)
                            }
                        }
                    }
                }
            }
        }

        // Commit cached tiles to layer and record undo snapshot
        var afterTiles: [TileCoord: Data?] = [:]
        for coord in touchedCoords {
            if let buf = cachedTiles[coord] {
                let data = Data(buf.bytes)
                layer.tileGrid.loadTileData(coord: coord, data: data)
                afterTiles[coord] = data
            }
        }

        if !touchedCoords.isEmpty {
            let command = TileDeltaUndoCommand(
                actionName: "Flood Fill",
                layerId: layer.id,
                beforeTiles: beforeTiles,
                afterTiles: afterTiles
            )
            document.undoManager.registerCommand(command)
        }
    }

    // MARK: - Color Distance Calculations

    public func colorDistance(c1: SIMD4<UInt8>, c2: SIMD4<UInt8>, metric: ColorDistanceMetric) -> Float {
        let dr = Float(c1.x) - Float(c2.x)
        let dg = Float(c1.y) - Float(c2.y)
        let db = Float(c1.z) - Float(c2.z)
        let da = Float(c1.w) - Float(c2.w)

        switch metric {
        case .euclidean:
            let sumSq = (dr * dr + dg * dg + db * db + da * da) / (4.0 * 255.0 * 255.0)
            return sqrt(sumSq)
        case .manhattan:
            return (abs(dr) + abs(dg) + abs(db) + abs(da)) / (4.0 * 255.0)
        }
    }
}
