import CoreGraphics
import Foundation
import simd

public enum GradientType: String, CaseIterable, Sendable, Codable {
    case linear
    case radial
}

public enum GradientSpreadMode: String, CaseIterable, Sendable, Codable {
    case pad        // Clamped to [0, 1]
    case repeatMode // Wrapped periodic [0, 1)
    case reflect    // Ping-pong mirrored [0, 1]
}

public struct GradientStop: Equatable, Sendable, Codable {
    public var offset: Float        // 0.0 ... 1.0
    public var color: SIMD4<Float>  // Straight RGBA [0.0 ... 1.0]

    public init(offset: Float, color: SIMD4<Float>) {
        self.offset = max(0.0, min(1.0, offset))
        self.color = color
    }
}

public struct GradientConfiguration: Sendable, Codable, Equatable {
    public var type: GradientType
    public var spreadMode: GradientSpreadMode
    public var stops: [GradientStop]
    public var enableDithering: Bool
    public var opacity: Float
    public var blendMode: BlendMode

    public init(
        type: GradientType = .linear,
        spreadMode: GradientSpreadMode = .pad,
        stops: [GradientStop] = [
            GradientStop(offset: 0.0, color: SIMD4<Float>(0, 0, 0, 1)),
            GradientStop(offset: 1.0, color: SIMD4<Float>(1, 1, 1, 1))
        ],
        enableDithering: Bool = true,
        opacity: Float = 1.0,
        blendMode: BlendMode = .normal
    ) {
        self.type = type
        self.spreadMode = spreadMode
        self.stops = stops.sorted { $0.offset < $1.offset }
        self.enableDithering = enableDithering
        self.opacity = max(0.0, min(1.0, opacity))
        self.blendMode = blendMode
    }
}

public final class GradientTool: DrawingTool, @unchecked Sendable {
    public let toolType: ToolType = .gradient
    public var configuration: GradientConfiguration

    private var isDragging: Bool = false
    private var startPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero

    // Bayer 4x4 matrix normalized to [-0.5, 0.5] / 255.0
    private static let bayerMatrix: [[Float]] = [
        [0.0/16.0 - 0.5,  8.0/16.0 - 0.5,  2.0/16.0 - 0.5, 10.0/16.0 - 0.5],
        [12.0/16.0 - 0.5, 4.0/16.0 - 0.5, 14.0/16.0 - 0.5,  6.0/16.0 - 0.5],
        [3.0/16.0 - 0.5, 11.0/16.0 - 0.5,  1.0/16.0 - 0.5,  9.0/16.0 - 0.5],
        [15.0/16.0 - 0.5, 7.0/16.0 - 0.5, 13.0/16.0 - 0.5,  5.0/16.0 - 0.5]
    ]

    public init(configuration: GradientConfiguration = GradientConfiguration()) {
        self.configuration = configuration
    }

    public func mouseDown(at canvasPoint: CGPoint, document: Document) {
        guard let layer = document.activeLayer as? BitmapLayer, !layer.isLocked else { return }
        isDragging = true
        startPoint = canvasPoint
        currentPoint = canvasPoint
    }

    public func mouseDragged(to canvasPoint: CGPoint, document: Document) {
        guard isDragging else { return }
        currentPoint = canvasPoint
    }

    public func mouseUp(at canvasPoint: CGPoint, document: Document) {
        guard isDragging, let layer = document.activeLayer as? BitmapLayer, !layer.isLocked else { return }
        currentPoint = canvasPoint
        isDragging = false

        applyGradient(from: startPoint, to: currentPoint, document: document, layer: layer)
    }

    public func cancel(document: Document) {
        isDragging = false
    }

    // MARK: - Gradient Application

    public func applyGradient(
        from p0: CGPoint,
        to p1: CGPoint,
        document: Document,
        layer: BitmapLayer
    ) {
        let tileSize = SparseTileGrid.tileSize

        let mask = document.selectionMask
        let hasMask = mask?.hasActiveSelection ?? false

        // Determine bounding box to process
        let bounds: CGRect
        if hasMask, let m = mask, let selBounds = m.selectionBounds {
            bounds = selBounds.intersection(document.bounds)
        } else {
            bounds = document.bounds
        }

        guard !bounds.isNull && bounds.width > 0 && bounds.height > 0 else { return }

        let minTx = max(0, Int(floor(bounds.minX)) / tileSize)
        let maxTx = min(layer.tileGrid.gridColumns - 1, Int(ceil(bounds.maxX) - 1) / tileSize)
        let minTy = max(0, Int(floor(bounds.minY)) / tileSize)
        let maxTy = min(layer.tileGrid.gridRows - 1, Int(ceil(bounds.maxY) - 1) / tileSize)

        var touchedCoords: Set<TileCoord> = []
        var beforeTiles: [TileCoord: Data?] = [:]
        var afterTiles: [TileCoord: Data?] = [:]

        let x0 = Float(p0.x)
        let y0 = Float(p0.y)
        let x1 = Float(p1.x)
        let y1 = Float(p1.y)

        let vx = x1 - x0
        let vy = y1 - y0
        let lenSq = vx * vx + vy * vy
        let radius = sqrt(lenSq)

        for ty in minTy...maxTy {
            for tx in minTx...maxTx {
                let coord = TileCoord(x: tx, y: ty)

                if hasMask, let m = mask, !m.maskGrid.isTileAllocated(at: coord) {
                    continue
                }

                touchedCoords.insert(coord)
                let beforeData = layer.tileGrid.extractTileData(coord: coord)
                beforeTiles[coord] = beforeData

                var tileBytes = [UInt8](repeating: 0, count: SparseTileGrid.bytesPerTile)
                if let d = beforeData {
                    d.copyBytes(to: &tileBytes, count: SparseTileGrid.bytesPerTile)
                }

                let tileOriginX = tx * tileSize
                let tileOriginY = ty * tileSize

                let localX0 = max(0, Int(floor(bounds.minX)) - tileOriginX)
                let localX1 = min(tileSize - 1, Int(ceil(bounds.maxX) - 1) - tileOriginX)
                let localY0 = max(0, Int(floor(bounds.minY)) - tileOriginY)
                let localY1 = min(tileSize - 1, Int(ceil(bounds.maxY) - 1) - tileOriginY)

                guard localX0 <= localX1 && localY0 <= localY1 else { continue }

                for ly in localY0...localY1 {
                    let gy = tileOriginY + ly
                    let rowOffset = ly * tileSize

                    for lx in localX0...localX1 {
                        let gx = tileOriginX + lx

                        let maskAlpha: Float
                        if hasMask, let m = mask {
                            maskAlpha = Float(m.alphaAt(x: gx, y: gy)) / 255.0
                            guard maskAlpha > 0.0001 else { continue }
                        } else {
                            maskAlpha = 1.0
                        }

                        // Calculate raw t parameter
                        let tRaw: Float
                        switch configuration.type {
                        case .linear:
                            if lenSq < 0.0001 {
                                tRaw = 0.0
                            } else {
                                let dx = Float(gx) - x0
                                let dy = Float(gy) - y0
                                tRaw = (dx * vx + dy * vy) / lenSq
                            }
                        case .radial:
                            if radius < 0.0001 {
                                tRaw = 0.0
                            } else {
                                let dx = Float(gx) - x0
                                let dy = Float(gy) - y0
                                tRaw = sqrt(dx * dx + dy * dy) / radius
                            }
                        }

                        let t = mapSpreadMode(tRaw: tRaw, spread: configuration.spreadMode)
                        var color = evaluateColorRamp(t: t, stops: configuration.stops)

                        if configuration.enableDithering {
                            let dither = Self.bayerMatrix[gy & 3][gx & 3] * (1.0 / 255.0)
                            color.x = max(0.0, min(1.0, color.x + dither))
                            color.y = max(0.0, min(1.0, color.y + dither))
                            color.z = max(0.0, min(1.0, color.z + dither))
                        }

                        let effectiveOpacity = configuration.opacity * maskAlpha
                        guard effectiveOpacity > 0.0001 else { continue }

                        let byteOffset = (rowOffset + lx) * 4
                        let bgR = Float(tileBytes[byteOffset]) / 255.0
                        let bgG = Float(tileBytes[byteOffset + 1]) / 255.0
                        let bgB = Float(tileBytes[byteOffset + 2]) / 255.0
                        let bgA = Float(tileBytes[byteOffset + 3]) / 255.0

                        if layer.lockAlpha {
                            guard bgA > 0.0001 else { continue }

                            let blended = configuration.blendMode.evaluate(
                                backdrop: SIMD3<Float>(bgR, bgG, bgB),
                                source: SIMD3<Float>(color.x, color.y, color.z)
                            )
                            let outR = bgR + (blended.x - bgR) * effectiveOpacity * color.w
                            let outG = bgG + (blended.y - bgG) * effectiveOpacity * color.w
                            let outB = bgB + (blended.z - bgB) * effectiveOpacity * color.w

                            tileBytes[byteOffset] = UInt8(max(0, min(255, Int(outR * 255.0 + 0.5))))
                            tileBytes[byteOffset + 1] = UInt8(max(0, min(255, Int(outG * 255.0 + 0.5))))
                            tileBytes[byteOffset + 2] = UInt8(max(0, min(255, Int(outB * 255.0 + 0.5))))
                            // bgA strictly unchanged
                        } else {
                            let srcColor = SIMD4<Float>(color.x, color.y, color.z, color.w * effectiveOpacity)
                            let backdrop = SIMD4<Float>(bgR, bgG, bgB, bgA)
                            let composited = configuration.blendMode.composite(
                                backdrop: backdrop,
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

                let finalData = Data(tileBytes)
                layer.tileGrid.loadTileData(coord: coord, data: finalData)
                afterTiles[coord] = finalData
            }
        }

        if !touchedCoords.isEmpty {
            let command = TileDeltaUndoCommand(
                actionName: "Gradient",
                layerId: layer.id,
                beforeTiles: beforeTiles,
                afterTiles: afterTiles
            )
            document.undoManager.registerCommand(command)
        }
    }

    // MARK: - Mathematical Helpers

    public func mapSpreadMode(tRaw: Float, spread: GradientSpreadMode) -> Float {
        switch spread {
        case .pad:
            return max(0.0, min(1.0, tRaw))
        case .repeatMode:
            let fract = tRaw - floor(tRaw)
            return fract < 0.0 ? fract + 1.0 : fract
        case .reflect:
            let m = tRaw - 2.0 * floor(tRaw / 2.0)
            let normM = m < 0.0 ? m + 2.0 : m
            return normM <= 1.0 ? normM : (2.0 - normM)
        }
    }

    public func evaluateColorRamp(t: Float, stops: [GradientStop]) -> SIMD4<Float> {
        guard !stops.isEmpty else {
            return SIMD4<Float>(0, 0, 0, 1)
        }
        if stops.count == 1 || t <= stops.first!.offset {
            return stops.first!.color
        }
        if t >= stops.last!.offset {
            return stops.last!.color
        }

        for i in 0..<(stops.count - 1) {
            let s0 = stops[i]
            let s1 = stops[i + 1]
            if t >= s0.offset && t <= s1.offset {
                let range = s1.offset - s0.offset
                if range < 0.0001 { return s0.color }
                let u = (t - s0.offset) / range
                return s0.color * (1.0 - u) + s1.color * u
            }
        }

        return stops.last!.color
    }
}
