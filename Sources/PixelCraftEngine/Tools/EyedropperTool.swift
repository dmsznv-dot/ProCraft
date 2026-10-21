import CoreGraphics
import Foundation
import simd

public enum EyedropperSampleMode: String, CaseIterable, Sendable, Codable {
    case pointSample // 1x1
    case average3x3  // 3x3
    case average5x5  // 5x5

    public var kernelRadius: Int {
        switch self {
        case .pointSample: return 0
        case .average3x3: return 1
        case .average5x5: return 2
        }
    }
}

public enum EyedropperSourceMode: String, CaseIterable, Sendable, Codable {
    case currentLayer
    case allVisibleLayers
}

public struct ColorSampleResult: Sendable, Equatable {
    public let color: SIMD4<Float>       // RGBA [0.0 ... 1.0]
    public let colorBytes: SIMD4<UInt8>  // RGBA [0 ... 255]
    public let hexString: String         // e.g. "#FF8000"
    public let rgbString: String         // e.g. "rgb(255, 128, 0)"
    public let rgbaString: String        // e.g. "rgba(255, 128, 0, 1.00)"
    public let hue: Float                // [0.0 ... 1.0]
    public let saturation: Float         // [0.0 ... 1.0]
    public let brightness: Float         // [0.0 ... 1.0]

    public var hsb: (hue: Float, saturation: Float, brightness: Float) {
        (hue, saturation, brightness)
    }

    public static func == (lhs: ColorSampleResult, rhs: ColorSampleResult) -> Bool {
        lhs.colorBytes == rhs.colorBytes && lhs.hexString == rhs.hexString
    }
}

public final class EyedropperTool: DrawingTool, @unchecked Sendable {
    public let toolType: ToolType = .eyedropper
    public var sampleMode: EyedropperSampleMode
    public var sourceMode: EyedropperSourceMode
    public private(set) var sampledColor: ColorSampleResult?

    public var onColorSampled: ((ColorSampleResult) -> Void)?

    public init(
        sampleMode: EyedropperSampleMode = .pointSample,
        sourceMode: EyedropperSourceMode = .allVisibleLayers
    ) {
        self.sampleMode = sampleMode
        self.sourceMode = sourceMode
    }

    public func mouseDown(at canvasPoint: CGPoint, document: Document) {
        sample(at: canvasPoint, document: document)
    }

    public func mouseDragged(to canvasPoint: CGPoint, document: Document) {
        sample(at: canvasPoint, document: document)
    }

    public func mouseUp(at canvasPoint: CGPoint, document: Document) {
        sample(at: canvasPoint, document: document)
    }

    public func cancel(document: Document) {
        // No-op
    }

    // MARK: - Sampling Implementation

    @discardableResult
    public func sample(at point: CGPoint, document: Document) -> ColorSampleResult? {
        let x = Int(point.x)
        let y = Int(point.y)
        let canvasW = Int(document.canvasSize.width)
        let canvasH = Int(document.canvasSize.height)

        guard x >= 0 && x < canvasW && y >= 0 && y < canvasH else {
            return nil
        }

        let radius = sampleMode.kernelRadius
        var totalAlpha: Float = 0.0
        var sumR: Float = 0.0
        var sumG: Float = 0.0
        var sumB: Float = 0.0
        var sampleCount: Float = 0.0

        for dy in -radius...radius {
            let sampleY = y + dy
            guard sampleY >= 0 && sampleY < canvasH else { continue }

            for dx in -radius...radius {
                let sampleX = x + dx
                guard sampleX >= 0 && sampleX < canvasW else { continue }

                let pixel = sampleSinglePixel(at: (sampleX, sampleY), document: document)
                let r = Float(pixel.x) / 255.0
                let g = Float(pixel.y) / 255.0
                let b = Float(pixel.z) / 255.0
                let a = Float(pixel.w) / 255.0

                sumR += r * a
                sumG += g * a
                sumB += b * a
                totalAlpha += a
                sampleCount += 1.0
            }
        }

        guard sampleCount > 0 else { return nil }

        let finalR: Float
        let finalG: Float
        let finalB: Float
        let finalA: Float

        if totalAlpha > 0.0001 {
            finalR = sumR / totalAlpha
            finalG = sumG / totalAlpha
            finalB = sumB / totalAlpha
            finalA = totalAlpha / sampleCount
        } else {
            finalR = 0.0
            finalG = 0.0
            finalB = 0.0
            finalA = 0.0
        }

        let byteR = UInt8(max(0, min(255, Int(finalR * 255.0 + 0.5))))
        let byteG = UInt8(max(0, min(255, Int(finalG * 255.0 + 0.5))))
        let byteB = UInt8(max(0, min(255, Int(finalB * 255.0 + 0.5))))
        let byteA = UInt8(max(0, min(255, Int(finalA * 255.0 + 0.5))))

        let colorFloat = SIMD4<Float>(finalR, finalG, finalB, finalA)
        let colorBytes = SIMD4<UInt8>(byteR, byteG, byteB, byteA)

        let hex = String(format: "#%02X%02X%02X", byteR, byteG, byteB)
        let rgb = "rgb(\(byteR), \(byteG), \(byteB))"
        let rgba = String(format: "rgba(%d, %d, %d, %.2f)", byteR, byteG, byteB, finalA)

        let hsb = Self.rgbToHsb(r: finalR, g: finalG, b: finalB)

        let result = ColorSampleResult(
            color: colorFloat,
            colorBytes: colorBytes,
            hexString: hex,
            rgbString: rgb,
            rgbaString: rgba,
            hue: hsb.hue,
            saturation: hsb.saturation,
            brightness: hsb.brightness
        )

        self.sampledColor = result
        onColorSampled?(result)
        return result
    }

    private func sampleSinglePixel(at pt: (x: Int, y: Int), document: Document) -> SIMD4<UInt8> {
        switch sourceMode {
        case .currentLayer:
            return document.activeLayer.tileGrid.readPixel(x: pt.x, y: pt.y)

        case .allVisibleLayers:
            // Composite bottom to top
            var composited = SIMD4<Float>(0, 0, 0, 0)

            for layer in document.layers where layer.isVisible {
                let px = layer.tileGrid.readPixel(x: pt.x, y: pt.y)
                guard px.w > 0 else { continue }

                let srcColor = SIMD4<Float>(
                    Float(px.x) / 255.0,
                    Float(px.y) / 255.0,
                    Float(px.z) / 255.0,
                    Float(px.w) / 255.0
                )

                composited = layer.blendMode.composite(
                    backdrop: composited,
                    source: srcColor,
                    opacity: layer.opacity,
                    lockAlpha: false
                )
            }

            return SIMD4<UInt8>(
                UInt8(max(0, min(255, Int(composited.x * 255.0 + 0.5)))),
                UInt8(max(0, min(255, Int(composited.y * 255.0 + 0.5)))),
                UInt8(max(0, min(255, Int(composited.z * 255.0 + 0.5)))),
                UInt8(max(0, min(255, Int(composited.w * 255.0 + 0.5))))
            )
        }
    }

    private static func rgbToHsb(r: Float, g: Float, b: Float) -> (hue: Float, saturation: Float, brightness: Float) {
        let maxV = max(r, max(g, b))
        let minV = min(r, min(g, b))
        let delta = maxV - minV

        let brightness = maxV
        let saturation = maxV > 0.0001 ? delta / maxV : 0.0

        var hue: Float = 0.0
        if delta > 0.0001 {
            if maxV == r {
                hue = (g - b) / delta + (g < b ? 6.0 : 0.0)
            } else if maxV == g {
                hue = (b - r) / delta + 2.0
            } else {
                hue = (r - g) / delta + 4.0
            }
            hue /= 6.0
        }

        return (hue, saturation, brightness)
    }
}
