import Metal
import Foundation

public enum MetalContextError: LocalizedError {
    case deviceInitializationFailed
    case commandQueueCreationFailed
    case shaderCompilationFailed(String)
    case functionNotFound(String)
    case pipelineStateCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deviceInitializationFailed:
            return "Failed to initialize default Metal device (MTLCreateSystemDefaultDevice)."
        case .commandQueueCreationFailed:
            return "Failed to create MTLCommandQueue."
        case .shaderCompilationFailed(let details):
            return "MSL shader compilation error: \(details)"
        case .functionNotFound(let name):
            return "Metal library function '\(name)' not found."
        case .pipelineStateCreationFailed(let reason):
            return "Failed to build Metal pipeline state: \(reason)"
        }
    }
}

/// Central thread-safe gateway to Metal GPU resources on Apple Silicon.
public final class MetalContext: @unchecked Sendable {
    public static let shared = MetalContext()

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue

    private let lock = NSLock()
    private var libraryCache: [String: MTLLibrary] = [:]
    private var renderPipelineCache: [String: MTLRenderPipelineState] = [:]
    private var computePipelineCache: [String: MTLComputePipelineState] = [:]
    private var samplerStateCache: [String: MTLSamplerState] = [:]

    public init(device: MTLDevice? = nil) {
        guard let mtlDevice = device ?? MTLCreateSystemDefaultDevice() else {
            fatalError("PixelCraft Pro requires an Apple Silicon Metal-capable GPU.")
        }
        guard let queue = mtlDevice.makeCommandQueue() else {
            fatalError("Failed to initialize MTLCommandQueue.")
        }
        self.device = mtlDevice
        self.commandQueue = queue
    }

    // MARK: - Texture Factory
    
    public func makeTileTextureDescriptor() -> MTLTextureDescriptor {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 512,
            height: 512,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        desc.storageMode = .shared
        return desc
    }

    public func makeTileTexture() -> MTLTexture {
        guard let texture = device.makeTexture(descriptor: makeTileTextureDescriptor()) else {
            fatalError("Failed to allocate 512x512 tile texture.")
        }
        return texture
    }

    public func makeTexture(
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat = .rgba8Unorm,
        usage: MTLTextureUsage = [.shaderRead, .renderTarget]
    ) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = usage
        desc.storageMode = .shared
        return device.makeTexture(descriptor: desc)
    }

    // MARK: - Shader Library Caching
    
    public func library(source: String, key: String? = nil) throws -> MTLLibrary {
        let cacheKey = key ?? "\(source.hashValue)"
        lock.lock()
        defer { lock.unlock() }

        if let cached = libraryCache[cacheKey] {
            return cached
        }

        do {
            let library = try device.makeLibrary(source: source, options: nil)
            libraryCache[cacheKey] = library
            return library
        } catch {
            throw MetalContextError.shaderCompilationFailed(error.localizedDescription)
        }
    }

    // MARK: - Render Pipeline Caching
    
    public func renderPipelineState(
        descriptor: MTLRenderPipelineDescriptor,
        cacheKey: String
    ) throws -> MTLRenderPipelineState {
        lock.lock()
        defer { lock.unlock() }

        if let cached = renderPipelineCache[cacheKey] {
            return cached
        }

        do {
            let pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            renderPipelineCache[cacheKey] = pipelineState
            return pipelineState
        } catch {
            throw MetalContextError.pipelineStateCreationFailed(error.localizedDescription)
        }
    }

    // MARK: - Compute Pipeline Caching
    
    public func computePipelineState(
        functionName: String,
        source: String
    ) throws -> MTLComputePipelineState {
        let cacheKey = "\(functionName)_\(source.hashValue)"
        lock.lock()
        defer { lock.unlock() }

        if let cached = computePipelineCache[cacheKey] {
            return cached
        }

        let lib = try library(source: source, key: "\(source.hashValue)")
        guard let function = lib.makeFunction(name: functionName) else {
            throw MetalContextError.functionNotFound(functionName)
        }

        do {
            let pipeline = try device.makeComputePipelineState(function: function)
            computePipelineCache[cacheKey] = pipeline
            return pipeline
        } catch {
            throw MetalContextError.pipelineStateCreationFailed(error.localizedDescription)
        }
    }

    // MARK: - Sampler State
    
    public func samplerState(
        minFilter: MTLSamplerMinMagFilter = .linear,
        magFilter: MTLSamplerMinMagFilter = .linear,
        addressMode: MTLSamplerAddressMode = .clampToEdge
    ) -> MTLSamplerState {
        let key = "\(minFilter.rawValue)_\(magFilter.rawValue)_\(addressMode.rawValue)"
        lock.lock()
        defer { lock.unlock() }

        if let cached = samplerStateCache[key] {
            return cached
        }

        let desc = MTLSamplerDescriptor()
        desc.minFilter = minFilter
        desc.magFilter = magFilter
        desc.sAddressMode = addressMode
        desc.tAddressMode = addressMode
        guard let sampler = device.makeSamplerState(descriptor: desc) else {
            fatalError("Failed to create MTLSamplerState")
        }
        samplerStateCache[key] = sampler
        return sampler
    }
}
