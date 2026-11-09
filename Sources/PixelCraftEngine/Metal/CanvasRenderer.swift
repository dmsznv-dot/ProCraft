import Metal
import MetalKit
import CoreGraphics
import Foundation
import simd

/// High-performance GPU-accelerated Metal renderer for PixelCraft Pro.
/// Implements frustum culling, triple-buffering, programmable blending, and offscreen export.
public final class CanvasRenderer: @unchecked Sendable {
    public static let shared = CanvasRenderer()

    public let context: MetalContext
    private let inFlightSemaphore = DispatchSemaphore(value: 3)

    private var tileRenderPipeline: MTLRenderPipelineState?
    private var checkerboardPipeline: MTLRenderPipelineState?
    private let lock = NSLock()

    public init(context: MetalContext = .shared) {
        self.context = context
        setupPipelines()
    }

    private func setupPipelines() {
        do {
            let lib = try context.library(source: CanvasRenderer.embeddedShaderSource, key: "canvas_shaders")
            guard let vFunc = lib.makeFunction(name: "canvas_tile_vertex"),
                  let fFunc = lib.makeFunction(name: "canvas_tile_fragment"),
                  let cFunc = lib.makeFunction(name: "checkerboard_fragment") else {
                fatalError("Canvas shader functions missing.")
            }

            // Layer Tile Pipeline (BGRA8 for MTKView)
            let tileDesc = MTLRenderPipelineDescriptor()
            tileDesc.vertexFunction = vFunc
            tileDesc.fragmentFunction = fFunc
            tileDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            tileRenderPipeline = try context.renderPipelineState(descriptor: tileDesc, cacheKey: "canvas_tile_bgra8")

            // Checkerboard Pipeline
            let checkDesc = MTLRenderPipelineDescriptor()
            checkDesc.vertexFunction = vFunc
            checkDesc.fragmentFunction = cFunc
            checkDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            checkerboardPipeline = try context.renderPipelineState(descriptor: checkDesc, cacheKey: "canvas_checkerboard_bgra8")
        } catch {
            print("Failed to initialize CanvasRenderer pipelines: \(error)")
        }
    }

    // MARK: - Frustum Culling
    
    public func visibleTileRange(
        canvasSize: CGSize,
        viewportSize: CGSize,
        transform: ViewportTransform
    ) -> (minCol: Int, maxCol: Int, minRow: Int, maxRow: Int)? {
        guard transform.zoom > 0 else { return nil }

        let z = Float(transform.zoom)
        let pan = transform.panSIMD
        
        let minX = -pan.x / z
        let maxX = (Float(viewportSize.width) - pan.x) / z
        let minY = -pan.y / z
        let maxY = (Float(viewportSize.height) - pan.y) / z

        let cols = max(1, Int(ceil(canvasSize.width / 512.0)))
        let rows = max(1, Int(ceil(canvasSize.height / 512.0)))

        let minCol = max(0, Int(floor(minX / 512.0)))
        let maxCol = min(cols - 1, Int(floor(maxX / 512.0)))
        let minRow = max(0, Int(floor(minY / 512.0)))
        let maxRow = min(rows - 1, Int(floor(maxY / 512.0)))

        guard minCol <= maxCol && minRow <= maxRow else {
            return nil // Canvas is completely outside viewport
        }
        return (minCol, maxCol, minRow, maxRow)
    }

    // MARK: - MTKView Render Pass
    
    @MainActor
    public func render(
        layers: [any Layer],
        canvasSize: CGSize,
        in view: MTKView,
        transform: ViewportTransform
    ) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        _ = inFlightSemaphore.wait(timeout: .distantFuture)
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return
        }
        commandBuffer.addCompletedHandler { [weak inFlightSemaphore] _ in
            inFlightSemaphore?.signal()
        }

        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.18, 0.18, 0.18, 1.0)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            commandBuffer.commit()
            return
        }

        // Pan/zoom and mouse coordinates live in view *points*; the drawable is in *pixels*
        // (2x on Retina). Using points here keeps the canvas aligned with the cursor.
        let viewportSize = view.bounds.size.width > 0 ? view.bounds.size : view.drawableSize

        // 1. Draw Checkerboard background over canvas rect
        drawCheckerboard(encoder: encoder, canvasSize: canvasSize, viewportSize: viewportSize, transform: transform)

        // 2. Draw Layer Tiles
        drawLayerStack(
            encoder: encoder,
            layers: layers,
            canvasSize: canvasSize,
            viewportSize: viewportSize,
            transform: transform
        )

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Headless Offscreen Rendering (Export & Testing)
    
    public func renderOffscreen(
        layers: [any Layer],
        canvasSize: CGSize,
        clearColor: MTLClearColor = MTLClearColorMake(0, 0, 0, 0)
    ) throws -> MTLTexture {
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        guard let targetTexture = context.makeTexture(
            width: width,
            height: height,
            pixelFormat: .rgba8Unorm,
            usage: [.renderTarget, .shaderRead]
        ) else {
            throw MetalContextError.pipelineStateCreationFailed("Failed to allocate offscreen export texture.")
        }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = targetTexture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = clearColor
        passDesc.colorAttachments[0].storeAction = .store

        guard let cmd = context.commandQueue.makeCommandBuffer(),
              let encoder = cmd.makeRenderCommandEncoder(descriptor: passDesc) else {
            throw MetalContextError.commandQueueCreationFailed
        }

        // Offscreen identity transform: zoom = 1.0, pan = 0, viewport = canvasSize
        let identityTransform = ViewportTransform(zoom: 1.0, panOffset: .zero)
        let rgbaPipeline = try getTilePipeline(for: .rgba8Unorm)

        drawLayerStack(
            encoder: encoder,
            layers: layers,
            canvasSize: canvasSize,
            viewportSize: canvasSize,
            transform: identityTransform,
            pipelineOverride: rgbaPipeline
        )

        encoder.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        return targetTexture
    }

    // MARK: - Layer Stack Drawing Implementation
    
    private func drawLayerStack(
        encoder: MTLRenderCommandEncoder,
        layers: [any Layer],
        canvasSize: CGSize,
        viewportSize: CGSize,
        transform: ViewportTransform,
        pipelineOverride: MTLRenderPipelineState? = nil
    ) {
        guard let (minCol, maxCol, minRow, maxRow) = visibleTileRange(
            canvasSize: canvasSize,
            viewportSize: viewportSize,
            transform: transform
        ) else {
            return
        }

        guard let tilePipeline = pipelineOverride ?? self.tileRenderPipeline else { return }
        encoder.setRenderPipelineState(tilePipeline)

        struct TileFragUniforms {
            var opacity: Float
            var blendMode: UInt32
            var lockAlpha: UInt32
        }

        struct TileVertUniforms {
            var tileOffset: SIMD2<Float>
            var quadSize: SIMD2<Float>
            var maxUV: SIMD2<Float>
            var viewportSize: SIMD2<Float>
            var pan: SIMD2<Float>
            var zoom: Float
        }

        for layer in layers {
            guard layer.isVisible, layer.opacity > 0.001 else { continue }
            let grid = layer.tileGrid

            var fragUniforms = TileFragUniforms(
                opacity: layer.opacity,
                blendMode: layer.blendModeRawValue,
                lockAlpha: layer.lockAlpha ? 1 : 0
            )
            encoder.setFragmentBytes(&fragUniforms, length: MemoryLayout<TileFragUniforms>.stride, index: 0)

            for ty in minRow...maxRow {
                for tx in minCol...maxCol {
                    let coord = TileCoord(x: tx, y: ty)
                    guard let tileTexture = grid.getTile(at: coord) else { continue }

                    let bounds = grid.effectiveTileBounds(coord: coord)
                    var vertUniforms = TileVertUniforms(
                        tileOffset: SIMD2<Float>(Float(tx * 512), Float(ty * 512)),
                        quadSize: SIMD2<Float>(bounds.width, bounds.height),
                        maxUV: SIMD2<Float>(bounds.maxU, bounds.maxV),
                        viewportSize: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
                        pan: transform.panSIMD,
                        zoom: transform.zoomFloat
                    )

                    encoder.setVertexBytes(&vertUniforms, length: MemoryLayout<TileVertUniforms>.stride, index: 0)
                    encoder.setFragmentTexture(tileTexture, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
            }
        }
    }

    private func drawCheckerboard(
        encoder: MTLRenderCommandEncoder,
        canvasSize: CGSize,
        viewportSize: CGSize,
        transform: ViewportTransform
    ) {
        guard let pipeline = checkerboardPipeline else { return }
        encoder.setRenderPipelineState(pipeline)

        struct TileVertUniforms {
            var tileOffset: SIMD2<Float>
            var quadSize: SIMD2<Float>
            var maxUV: SIMD2<Float>
            var viewportSize: SIMD2<Float>
            var pan: SIMD2<Float>
            var zoom: Float
        }

        var vertUniforms = TileVertUniforms(
            tileOffset: .zero,
            quadSize: SIMD2<Float>(Float(canvasSize.width), Float(canvasSize.height)),
            maxUV: SIMD2<Float>(1.0, 1.0),
            viewportSize: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
            pan: transform.panSIMD,
            zoom: transform.zoomFloat
        )
        encoder.setVertexBytes(&vertUniforms, length: MemoryLayout<TileVertUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func getTilePipeline(for format: MTLPixelFormat) throws -> MTLRenderPipelineState {
        let key = "canvas_tile_\(format.rawValue)"
        lock.lock()
        defer { lock.unlock() }
        
        let dummyDesc = MTLRenderPipelineDescriptor()
        dummyDesc.colorAttachments[0].pixelFormat = format
        
        let lib = try context.library(source: CanvasRenderer.embeddedShaderSource, key: "canvas_shaders")
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "canvas_tile_vertex")
        desc.fragmentFunction = lib.makeFunction(name: "canvas_tile_fragment")
        desc.colorAttachments[0].pixelFormat = format
        return try context.renderPipelineState(descriptor: desc, cacheKey: key)
    }

    // MARK: - Embedded MSL Source
    
    public static let embeddedShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    enum BlendModeIndex : uint {
        Normal = 0,
        Multiply = 1,
        Screen = 2,
        Overlay = 3,
        SoftLight = 4,
        HardLight = 5,
        Difference = 6,
        Darken = 7,
        Lighten = 8,
        ColorDodge = 9,
        ColorBurn = 10,
        LinearDodge = 11,
        LinearBurn = 12,
        Exclusion = 13
    };

    struct TileVertexUniforms {
        float2 tileOffset;
        float2 quadSize;
        float2 maxUV;
        float2 viewportSize;
        float2 pan;
        float zoom;
    };

    struct TileFragmentUniforms {
        float opacity;
        uint blendMode;
        uint lockAlpha;
    };

    struct LayerUniforms {
        uint blendMode;
        float opacity;
        bool lockAlpha;
        bool isLinear;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    inline float3 blend_normal(float3 cb, float3 cs) { return cs; }
    inline float3 blend_multiply(float3 cb, float3 cs) { return cb * cs; }
    inline float3 blend_screen(float3 cb, float3 cs) { return 1.0f - (1.0f - cb) * (1.0f - cs); }
    inline float3 blend_overlay(float3 cb, float3 cs) {
        return select(2.0f * cb * cs, 1.0f - 2.0f * (1.0f - cb) * (1.0f - cs), cb > 0.5f);
    }
    inline float3 blend_hard_light(float3 cb, float3 cs) {
        return select(2.0f * cb * cs, 1.0f - 2.0f * (1.0f - cb) * (1.0f - cs), cs > 0.5f);
    }
    inline float3 blend_soft_light(float3 cb, float3 cs) {
        float3 d = select(sqrt(cb), ((16.0f * cb - 12.0f) * cb + 4.0f) * cb, cb <= 0.25f);
        return select(cb - (1.0f - 2.0f * cs) * cb * (1.0f - cb),
                      cb + (2.0f * cs - 1.0f) * (d - cb),
                      cs > 0.5f);
    }
    inline float3 blend_difference(float3 cb, float3 cs) { return abs(cb - cs); }
    inline float3 blend_darken(float3 cb, float3 cs) { return min(cb, cs); }
    inline float3 blend_lighten(float3 cb, float3 cs) { return max(cb, cs); }
    inline float3 blend_color_dodge(float3 cb, float3 cs) {
        float3 res;
        for (int i = 0; i < 3; ++i) {
            if (cb[i] <= 0.0f) res[i] = 0.0f;
            else if (cs[i] >= 1.0f) res[i] = 1.0f;
            else res[i] = min(1.0f, cb[i] / (1.0f - cs[i]));
        }
        return res;
    }
    inline float3 blend_color_burn(float3 cb, float3 cs) {
        float3 res;
        for (int i = 0; i < 3; ++i) {
            if (cb[i] >= 1.0f) res[i] = 1.0f;
            else if (cs[i] <= 0.0f) res[i] = 0.0f;
            else res[i] = 1.0f - min(1.0f, (1.0f - cb[i]) / cs[i]);
        }
        return res;
    }
    inline float3 blend_linear_dodge(float3 cb, float3 cs) { return min(1.0f, cb + cs); }
    inline float3 blend_linear_burn(float3 cb, float3 cs) { return max(0.0f, cb + cs - 1.0f); }
    inline float3 blend_exclusion(float3 cb, float3 cs) { return cb + cs - 2.0f * cb * cs; }

    inline float3 evaluate_blend(uint mode, float3 cb, float3 cs) {
        switch (mode) {
            case Normal: return blend_normal(cb, cs);
            case Multiply: return blend_multiply(cb, cs);
            case Screen: return blend_screen(cb, cs);
            case Overlay: return blend_overlay(cb, cs);
            case SoftLight: return blend_soft_light(cb, cs);
            case HardLight: return blend_hard_light(cb, cs);
            case Difference: return blend_difference(cb, cs);
            case Darken: return blend_darken(cb, cs);
            case Lighten: return blend_lighten(cb, cs);
            case ColorDodge: return blend_color_dodge(cb, cs);
            case ColorBurn: return blend_color_burn(cb, cs);
            case LinearDodge: return blend_linear_dodge(cb, cs);
            case LinearBurn: return blend_linear_burn(cb, cs);
            case Exclusion: return blend_exclusion(cb, cs);
            default: return blend_normal(cb, cs);
        }
    }

    vertex VertexOut canvas_tile_vertex(uint vertexID [[vertex_id]],
                                        constant TileVertexUniforms &u [[buffer(0)]]) {
        float2 unitPos = float2(float(vertexID & 1), float(vertexID >> 1));
        float2 canvasPos = u.tileOffset + unitPos * u.quadSize;
        float2 viewportPos = canvasPos * u.zoom + u.pan;

        float2 ndc;
        ndc.x = (2.0f * viewportPos.x / u.viewportSize.x) - 1.0f;
        ndc.y = 1.0f - (2.0f * viewportPos.y / u.viewportSize.y);

        VertexOut out;
        out.position = float4(ndc, 0.0f, 1.0f);
        out.texCoord = unitPos * u.maxUV;
        return out;
    }

    fragment float4 checkerboard_fragment(VertexOut in [[stage_in]]) {
        uint2 screenPos = uint2(in.position.xy);
        bool check = ((screenPos.x / 16) ^ (screenPos.y / 16)) & 1;
        float c = check ? 0.90f : 0.75f;
        return float4(c, c, c, 1.0f);
    }

    fragment float4 canvas_tile_fragment(VertexOut in [[stage_in]],
                                         float4 dstColor [[color(0)]],
                                         texture2d<float> tileTexture [[texture(0)]],
                                         constant TileFragmentUniforms &u [[buffer(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float4 srcSample = tileTexture.sample(s, in.texCoord);

        float srcA = srcSample.a * u.opacity;
        if (srcA <= 0.0001f) {
            return dstColor;
        }

        float dstA = dstColor.a;
        float3 blended = evaluate_blend(u.blendMode, dstColor.rgb, srcSample.rgb);

        if (u.lockAlpha != 0) {
            if (dstA <= 0.00001f) {
                return float4(0.0f);
            }
            float3 outRGB = mix(dstColor.rgb, blended, srcA);
            return float4(outRGB, dstA);
        } else {
            float outA = srcA + dstA * (1.0f - srcA);
            if (outA <= 0.0001f) {
                return float4(0.0f);
            }

            float3 outRGB = (srcA * (1.0f - dstA) * srcSample.rgb +
                             srcA * dstA * blended +
                             (1.0f - srcA) * dstA * dstColor.rgb) / outA;

            return float4(outRGB, outA);
        }
    }

    kernel void composite_layers_kernel(
        texture2d<float, access::read_write> backdrop [[texture(0)]],
        texture2d<float, access::read> source [[texture(1)]],
        constant LayerUniforms &uniforms [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= backdrop.get_width() || gid.y >= backdrop.get_height()) {
            return;
        }

        float4 c_b = backdrop.read(gid);
        float4 c_s = source.read(gid);

        float alpha_b = c_b.a;
        float alpha_s = c_s.a * uniforms.opacity;

        if (uniforms.lockAlpha) {
            if (alpha_b <= 0.00001f) {
                backdrop.write(float4(0.0f, 0.0f, 0.0f, 0.0f), gid);
                return;
            }
            float3 b = evaluate_blend(uniforms.blendMode, c_b.rgb, c_s.rgb);
            float3 cr = mix(c_b.rgb, b, alpha_s);
            backdrop.write(float4(cr, alpha_b), gid);
        } else {
            float alpha_r = alpha_s + alpha_b * (1.0f - alpha_s);
            if (alpha_r <= 0.00001f) {
                backdrop.write(float4(0.0f, 0.0f, 0.0f, 0.0f), gid);
                return;
            }

            float3 cs_prem = c_s.rgb * alpha_s;
            float3 cb_prem = c_b.rgb * alpha_b;
            float3 b = evaluate_blend(uniforms.blendMode, c_b.rgb, c_s.rgb);
            float3 cr_prem = cs_prem * (1.0f - alpha_b) + cb_prem * (1.0f - alpha_s) + alpha_s * alpha_b * b;
            float3 cr = cr_prem / alpha_r;

            backdrop.write(float4(cr, alpha_r), gid);
        }
    }
    """
}
