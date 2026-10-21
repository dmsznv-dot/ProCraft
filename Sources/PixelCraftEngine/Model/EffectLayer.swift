import Foundation
import CoreGraphics
import Metal
import simd

public enum EffectType: String, Codable, CaseIterable, Sendable {
    case gaussianBlur
    case sharpen
    case vignette
    case bloom
    case pixelate
}

public struct EffectParameters: Equatable, Sendable {
    public var radius: Float = 10.0         // [0.1 ... 100.0]
    public var intensity: Float = 1.0       // [0.0 ... 5.0]
    public var blockSize: Float = 16.0      // [2.0 ... 512.0] for pixelate
    public var center: CGPoint = .zero
    public var color: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)

    public init() {}
}

/// Non-destructive filter/effect layer (blur, sharpen, vignette, pixelate) applied to lower composite.
public final class EffectLayer: Layer, @unchecked Sendable {
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
    public let tileGrid: SparseTileGrid // Optional effect mask

    public var effectType: EffectType
    public var parameters: EffectParameters

    public init(
        id: UUID = UUID(),
        name: String = "Effect Layer",
        type: EffectType = .gaussianBlur,
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
        self.effectType = type
        self.parameters = EffectParameters()
        self.isVisible = isVisible
        self.opacity = max(0.0, min(1.0, opacity))
        self.blendMode = blendMode
        self.lockAlpha = lockAlpha
        self.isLocked = isLocked
        self.tileGrid = SparseTileGrid(canvasSize: canvasSize, device: device)
    }

    public convenience init(
        id: UUID = UUID(),
        name: String = "Effect Layer",
        type: EffectType = .gaussianBlur,
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
            type: type,
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
        CGRect(origin: .zero, size: tileGrid.canvasSize)
    }

    public func duplicate() -> any Layer {
        let cloned = EffectLayer(
            name: "\(name) Copy",
            type: effectType,
            canvasSize: tileGrid.canvasSize,
            device: tileGrid.device,
            isVisible: isVisible,
            opacity: opacity,
            blendMode: blendMode,
            lockAlpha: lockAlpha,
            isLocked: isLocked
        )
        cloned.parameters = parameters
        cloned.tileGrid.copyFrom(tileGrid)
        return cloned
    }

    public func render(into context: MetalRenderContext) {
        guard isVisible, opacity > 0.001 else { return }
    }

    public func composite(layer: any Layer, canvasSize: CGSize) {
        // Effects composite by processing underlying tiles
    }

    public func merge(layer: any Layer, canvasSize: CGSize) {
        composite(layer: layer, canvasSize: canvasSize)
    }
}
