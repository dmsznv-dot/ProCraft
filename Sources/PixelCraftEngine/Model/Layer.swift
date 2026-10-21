import Foundation
import CoreGraphics
import Metal
import simd

public enum LayerError: LocalizedError, Equatable {
    case cannotMergeBottomLayer
    case layerIsLocked(name: String)
    case noVisibleLayersToMerge
    case layerIndexOutOfBounds(index: Int, count: Int)

    public var errorDescription: String? {
        switch self {
        case .cannotMergeBottomLayer:
            return "Cannot merge down from the bottom-most layer."
        case .layerIsLocked(let name):
            return "Layer '\(name)' is locked and cannot be modified."
        case .noVisibleLayersToMerge:
            return "No visible layers found to merge."
        case .layerIndexOutOfBounds(let index, let count):
            return "Layer index \(index) out of bounds for stack of size \(count)."
        }
    }
}

/// Rendering context holding Metal commands, encoders, and viewport state for rendering layers.
public struct MetalRenderContext {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let commandBuffer: MTLCommandBuffer
    public let renderCommandEncoder: MTLRenderCommandEncoder?
    public let computeCommandEncoder: MTLComputeCommandEncoder?
    public let viewportTransform: simd_float3x3
    public let canvasSize: CGSize
    public let targetTexture: MTLTexture?
    public let isLinearBlending: Bool
    
    public init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        commandBuffer: MTLCommandBuffer,
        renderCommandEncoder: MTLRenderCommandEncoder? = nil,
        computeCommandEncoder: MTLComputeCommandEncoder? = nil,
        viewportTransform: simd_float3x3 = matrix_identity_float3x3,
        canvasSize: CGSize,
        targetTexture: MTLTexture? = nil,
        isLinearBlending: Bool = false
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.commandBuffer = commandBuffer
        self.renderCommandEncoder = renderCommandEncoder
        self.computeCommandEncoder = computeCommandEncoder
        self.viewportTransform = viewportTransform
        self.canvasSize = canvasSize
        self.targetTexture = targetTexture
        self.isLinearBlending = isLinearBlending
    }
}

/// The foundational interface for all layers in PixelCraft Pro.
public protocol Layer: AnyObject, Identifiable, Sendable {
    /// Unique identifier for layer selection and UI tracking
    var id: UUID { get }
    
    /// Display name in the layer panel
    var name: String { get set }
    
    /// Visibility toggle (hidden layers are skipped during compositing)
    var isVisible: Bool { get set }
    
    /// Opacity factor in range [0.0, 1.0]
    var opacity: Float { get set }
    
    /// Blend mode for compositing onto lower layers
    var blendMode: BlendMode { get set }
    
    /// Lock Alpha: When true, drawing and merging cannot alter pixel alpha channels
    var lockAlpha: Bool { get set }
    
    /// User lock: Prevents all modifications, moves, or edits
    var isLocked: Bool { get set }
    
    /// Sparse 512x512 tile grid backing this layer
    var tileGrid: SparseTileGrid { get }
    
    /// Layer bounding box in canvas coordinates
    var bounds: CGRect { get }
    
    /// Deep copy of the layer and all its data
    func duplicate() -> any Layer
    
    /// GPU rendering pass into the specified Metal context
    func render(into context: MetalRenderContext)
    
    /// Composites another layer's content onto this layer (used in merge/flatten)
    func composite(layer: any Layer, canvasSize: CGSize)
    
    /// Merges another layer into this layer destructively
    func merge(layer: any Layer, canvasSize: CGSize)
}

public extension Layer {
    var blendModeRawValue: UInt32 {
        blendMode.rawValue
    }
}
