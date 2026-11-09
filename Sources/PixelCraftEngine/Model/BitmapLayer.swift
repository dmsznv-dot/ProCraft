import Foundation
import CoreGraphics
import Metal
import simd

/// Standard raster layer backed by a SparseTileGrid.
public final class BitmapLayer: Layer, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isVisible: Bool
    public var opacity: Float {
        didSet {
            opacity = max(0.0, min(1.0, opacity))
        }
    }
    public var blendMode: BlendMode
    public var lockAlpha: Bool
    public var isLocked: Bool
    public let tileGrid: SparseTileGrid

    public init(
        id: UUID = UUID(),
        name: String = "Bitmap Layer",
        canvasSize: CGSize,
        device: MTLDevice? = nil,
        isVisible: Bool = true,
        opacity: Float = 1.0,
        blendMode: BlendMode = .normal,
        lockAlpha: Bool = false,
        isLocked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.opacity = max(0.0, min(1.0, opacity))
        self.blendMode = blendMode
        self.lockAlpha = lockAlpha
        self.isLocked = isLocked
        self.tileGrid = SparseTileGrid(canvasSize: canvasSize, device: device)
    }

    public convenience init(
        id: UUID = UUID(),
        name: String = "Bitmap Layer",
        bounds: CGRect,
        device: MTLDevice? = nil,
        isVisible: Bool = true,
        opacity: Float = 1.0,
        blendMode: BlendMode = .normal,
        lockAlpha: Bool = false,
        isLocked: Bool = false
    ) {
        self.init(
            id: id,
            name: name,
            canvasSize: bounds.size,
            device: device,
            isVisible: isVisible,
            opacity: opacity,
            blendMode: blendMode,
            lockAlpha: lockAlpha,
            isLocked: isLocked
        )
    }

    public var bounds: CGRect {
        let content = tileGrid.contentBounds
        if content == .zero {
            return CGRect(origin: .zero, size: tileGrid.canvasSize)
        }
        return content
    }

    public func duplicate() -> any Layer {
        let cloned = BitmapLayer(
            name: "\(name) Copy",
            canvasSize: tileGrid.canvasSize,
            device: tileGrid.device,
            isVisible: isVisible,
            opacity: opacity,
            blendMode: blendMode,
            lockAlpha: lockAlpha,
            isLocked: isLocked
        )
        cloned.tileGrid.copyFrom(tileGrid)
        return cloned
    }

    public func render(into context: MetalRenderContext) {
        guard isVisible, opacity > 0.001 else { return }
        // Render pass is driven via CanvasRenderer drawLayerStack
    }

    public func fillSolid(color: SIMD4<Float>, canvasSize: CGSize) {
        tileGrid.fillSolid(color: color)
    }

    public func composite(layer: any Layer, canvasSize: CGSize) {
        guard layer.isVisible, layer.opacity > 0.001 else { return }
        
        let sourceCoords = layer.tileGrid.allAllocatedCoordinates()
        guard !sourceCoords.isEmpty else { return }
        
        let sourceMode = layer.blendMode
        let sourceOpacity = layer.opacity
        let dstLockAlpha = self.lockAlpha

        for coord in sourceCoords {
            guard let srcBytes = layer.tileGrid.readTileBytes(coord: coord) else { continue }
            var dstBytes = self.tileGrid.readTileBytes(coord: coord)
                ?? [UInt8](repeating: 0, count: SparseTileGrid.bytesPerTile)

            for i in stride(from: 0, to: SparseTileGrid.bytesPerTile, by: 4) {
                // Fully transparent source pixels never change the backdrop.
                if srcBytes[i + 3] == 0 { continue }
                let db = SIMD4<Float>(
                    Float(dstBytes[i]) / 255.0,
                    Float(dstBytes[i + 1]) / 255.0,
                    Float(dstBytes[i + 2]) / 255.0,
                    Float(dstBytes[i + 3]) / 255.0
                )
                let sb = SIMD4<Float>(
                    Float(srcBytes[i]) / 255.0,
                    Float(srcBytes[i + 1]) / 255.0,
                    Float(srcBytes[i + 2]) / 255.0,
                    Float(srcBytes[i + 3]) / 255.0
                )

                let res = sourceMode.composite(backdrop: db, source: sb, opacity: sourceOpacity, lockAlpha: dstLockAlpha)

                dstBytes[i] = UInt8(max(0, min(255, round(res.x * 255.0))))
                dstBytes[i + 1] = UInt8(max(0, min(255, round(res.y * 255.0))))
                dstBytes[i + 2] = UInt8(max(0, min(255, round(res.z * 255.0))))
                dstBytes[i + 3] = UInt8(max(0, min(255, round(res.w * 255.0))))
            }

            self.tileGrid.writeTileBytes(coord: coord, bytes: dstBytes)
        }
    }

    public func merge(layer: any Layer, canvasSize: CGSize) {
        composite(layer: layer, canvasSize: canvasSize)
    }
}
