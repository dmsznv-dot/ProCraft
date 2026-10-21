import Foundation
import CoreGraphics
import Metal
import simd

public enum AdjustmentType: String, Codable, CaseIterable, Sendable {
    case brightnessContrast
    case levels
    case curves
    case hueSaturation
    case exposure
    case colorBalance
    case invert
}

public struct AdjustmentParameters: Equatable, Sendable {
    public var brightness: Float = 0.0       // [-1.0 ... 1.0]
    public var contrast: Float = 0.0         // [-1.0 ... 1.0]
    public var levelsBlack: Float = 0.0      // [0.0 ... 1.0]
    public var levelsWhite: Float = 1.0      // [0.0 ... 1.0]
    public var levelsGamma: Float = 1.0      // [0.1 ... 10.0]
    public var hueShift: Float = 0.0         // [-180.0 ... 180.0] degrees
    public var saturation: Float = 0.0       // [-1.0 ... 1.0]
    public var lightness: Float = 0.0        // [-1.0 ... 1.0]
    public var exposureEV: Float = 0.0       // [-5.0 ... 5.0]

    public init() {}
}

/// Non-destructive tonal adjustment layer that modifies underlying composite layers.
public final class AdjustmentLayer: Layer, @unchecked Sendable {
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
    public let tileGrid: SparseTileGrid // Optional layer mask

    public var adjustmentType: AdjustmentType
    public var parameters: AdjustmentParameters

    public init(
        id: UUID = UUID(),
        name: String = "Adjustment Layer",
        type: AdjustmentType = .brightnessContrast,
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
        self.adjustmentType = type
        self.parameters = AdjustmentParameters()
        self.isVisible = isVisible
        self.opacity = max(0.0, min(1.0, opacity))
        self.blendMode = blendMode
        self.lockAlpha = lockAlpha
        self.isLocked = isLocked
        self.tileGrid = SparseTileGrid(canvasSize: canvasSize, device: device)
    }

    public convenience init(
        id: UUID = UUID(),
        name: String = "Adjustment Layer",
        type: AdjustmentType = .brightnessContrast,
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
        let cloned = AdjustmentLayer(
            name: "\(name) Copy",
            type: adjustmentType,
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
        // Adjustments composite by modifying target tile grid or applying tone curve
    }

    public func merge(layer: any Layer, canvasSize: CGSize) {
        composite(layer: layer, canvasSize: canvasSize)
    }
}
