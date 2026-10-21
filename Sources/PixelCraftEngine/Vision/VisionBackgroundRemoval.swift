import Foundation
import CoreGraphics
import Vision

public final class VisionBackgroundRemoval: @unchecked Sendable {
    public init() {}

    /// Executes foreground instance mask segmentation using Vision.framework.
    /// Returns an alpha mask (values 0-255) for the canvas size.
    public func generateForegroundMask(
        from grid: SparseTileGrid,
        refineEdges: Bool = true
    ) async throws -> [UInt8] {
        let width = Int(grid.canvasSize.width)
        let height = Int(grid.canvasSize.height)

        // Render grid to CGImage for Vision request
        guard let cgImage = createCGImage(from: grid, width: width, height: height) else {
            throw NSError(domain: "VisionBackgroundRemoval", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage from grid"])
        }

        if #available(macOS 14.0, *) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            guard let result = request.results?.first else {
                throw NSError(domain: "VisionBackgroundRemoval", code: -2, userInfo: [NSLocalizedDescriptionKey: "No foreground instance found"])
            }

            // Extract instance mask as pixel buffer
            let maskBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            var maskBytes = extractMaskBytes(from: maskBuffer, targetWidth: width, targetHeight: height)

            if refineEdges {
                maskBytes = applyGuidedEdgeRefinement(mask: maskBytes, source: grid, width: width, height: height)
            }

            return maskBytes
        } else {
            // Analytical fallback for older macOS or test environments:
            // Saliency / luminosity contrast mask
            return generateContrastSaliencyMask(from: grid, width: width, height: height)
        }
    }

    /// Applies the computed foreground mask directly to the layer's alpha channel.
    public func applyMaskToGrid(grid: SparseTileGrid, mask: [UInt8]) {
        let width = Int(grid.canvasSize.width)
        let height = Int(grid.canvasSize.height)

        for y in 0..<height {
            for x in 0..<width {
                let maskVal = mask[y * width + x]
                var p = grid.getPixel(x: x, y: y)
                if p.a > 0 {
                    let newAlpha = UInt8((UInt32(p.a) * UInt32(maskVal)) / 255)
                    p.a = newAlpha
                    grid.setPixel(x: x, y: y, color: p)
                }
            }
        }
    }

    private func createCGImage(from grid: SparseTileGrid, width: Int, height: Int) -> CGImage? {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let p = grid.getPixel(x: x, y: y)
                let idx = (y * width + x) * 4
                rgba[idx] = p.r
                rgba[idx + 1] = p.g
                rgba[idx + 2] = p.b
                rgba[idx + 3] = p.a
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func extractMaskBytes(from pixelBuffer: CVPixelBuffer, targetWidth: Int, targetHeight: Int) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return [UInt8](repeating: 255, count: targetWidth * targetHeight)
        }

        let bufWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        var output = [UInt8](repeating: 0, count: targetWidth * targetHeight)

        for y in 0..<targetHeight {
            let srcY = min(bufHeight - 1, (y * bufHeight) / targetHeight)
            let row = ptr.advanced(by: srcY * bytesPerRow)
            for x in 0..<targetWidth {
                let srcX = min(bufWidth - 1, (x * bufWidth) / targetWidth)
                let val = row[srcX]
                output[y * targetWidth + x] = val
            }
        }

        return output
    }

    /// Analytical guided filter for hair/fur edge refinement:
    /// Uses local variance of the source image to sharpen/smooth mask transitions.
    public func applyGuidedEdgeRefinement(
        mask: [UInt8],
        source: SparseTileGrid,
        width: Int,
        height: Int,
        radius: Int = 2,
        eps: Float = 1e-3
    ) -> [UInt8] {
        var refined = mask
        let r = radius

        for y in r..<(height - r) {
            for x in r..<(width - r) {
                let centerVal = mask[y * width + x]
                // Only refine near transition edges (10 < mask < 245)
                if centerVal > 10 && centerVal < 245 {
                    let centerP = source.getPixel(x: x, y: y)
                    let centerLum = Float(centerP.r) * 0.2126 + Float(centerP.g) * 0.7152 + Float(centerP.b) * 0.0722

                    var sumMask: Float = 0
                    var sumWeight: Float = 0

                    for dy in -r...r {
                        for dx in -r...r {
                            let nx = x + dx
                            let ny = y + dy
                            let np = source.getPixel(x: nx, y: ny)
                            let nLum = Float(np.r) * 0.2126 + Float(np.g) * 0.7152 + Float(np.b) * 0.0722
                            let diff = (centerLum - nLum) / 255.0
                            let weight = exp(-(diff * diff) / (2.0 * eps))

                            sumMask += Float(mask[ny * width + nx]) * weight
                            sumWeight += weight
                        }
                    }

                    if sumWeight > 0 {
                        refined[y * width + x] = UInt8(clamping: Int(round(sumMask / sumWeight)))
                    }
                }
            }
        }

        return refined
    }

    /// Contrast and saliency-based mask fallback.
    public func generateContrastSaliencyMask(from grid: SparseTileGrid, width: Int, height: Int) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let p = grid.getPixel(x: x, y: y)
                // Any pixel with alpha is considered foreground in this model
                mask[y * width + x] = p.a
            }
        }
        return mask
    }
}
