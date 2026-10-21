import Foundation
import CoreGraphics
import CoreText

public enum ASCIICharacterSet: Sendable {
    case standard
    case extendedUnicode
    case custom(String)

    public var characters: [Character] {
        switch self {
        case .standard:
            return Array(" .:-=+*#%@")
        case .extendedUnicode:
            return Array(" ░▒▓█")
        case .custom(let str):
            let chars = Array(str)
            return chars.isEmpty ? Array(" .:-=+*#%@") : chars
        }
    }
}

public struct ASCIIParams: Sendable {
    public var gridColumns: Int
    public var gridRows: Int
    public var charSet: ASCIICharacterSet
    public var fontName: String
    public var fontSize: CGFloat
    public var volumeIntensity: Float // 0.0 to 2.0 (boosts edge contrast)
    public var dithering: Bool
    public var invert: Bool

    public init(
        gridColumns: Int = 120,
        gridRows: Int = 60,
        charSet: ASCIICharacterSet = .standard,
        fontName: String = "SF Mono",
        fontSize: CGFloat = 12.0,
        volumeIntensity: Float = 1.0,
        dithering: Bool = true,
        invert: Bool = false
    ) {
        self.gridColumns = gridColumns
        self.gridRows = gridRows
        self.charSet = charSet
        self.fontName = fontName
        self.fontSize = fontSize
        self.volumeIntensity = volumeIntensity
        self.dithering = dithering
        self.invert = invert
    }
}

public final class ASCIIGenerator: @unchecked Sendable {
    public init() {}

    /// Generates plain text ASCII representation of the sparse tile grid.
    public func generateText(from grid: SparseTileGrid, params: ASCIIParams) -> String {
        let cols = max(10, params.gridColumns)
        let rows = max(5, params.gridRows)

        let width = grid.canvasSize.width
        let height = grid.canvasSize.height

        let cellW = width / CGFloat(cols)
        let cellH = height / CGFloat(rows)

        let chars = params.charSet.characters
        let numChars = Float(chars.count - 1)

        // 1. Calculate luminance map and Sobel edge intensity
        var lumMap = [Float](repeating: 0, count: cols * rows)

        for r in 0..<rows {
            for c in 0..<cols {
                let cx = Int(CGFloat(c) * cellW + cellW * 0.5)
                let cy = Int(CGFloat(r) * cellH + cellH * 0.5)
                let p = grid.getPixel(x: min(Int(width) - 1, cx), y: min(Int(height) - 1, cy))

                // Standard perceptual luminance
                var lum = (Float(p.r) * 0.2126 + Float(p.g) * 0.7152 + Float(p.b) * 0.0722) / 255.0
                if p.a < 128 {
                    lum = 0.0 // transparent is dark
                }
                lumMap[r * cols + c] = lum
            }
        }

        // 2. Sobel edge gradient computation for volume depth
        var volumeMap = lumMap
        if params.volumeIntensity > 0 {
            for r in 1..<(rows - 1) {
                for c in 1..<(cols - 1) {
                    let gx = -lumMap[(r - 1) * cols + (c - 1)] + lumMap[(r - 1) * cols + (c + 1)]
                           - 2.0 * lumMap[r * cols + (c - 1)] + 2.0 * lumMap[r * cols + (c + 1)]
                           - lumMap[(r + 1) * cols + (c - 1)] + lumMap[(r + 1) * cols + (c + 1)]

                    let gy = -lumMap[(r - 1) * cols + (c - 1)] - 2.0 * lumMap[(r - 1) * cols + c] - lumMap[(r - 1) * cols + (c + 1)]
                           + lumMap[(r + 1) * cols + (c - 1)] + 2.0 * lumMap[(r + 1) * cols + c] + lumMap[(r + 1) * cols + (c + 1)]

                    let edge = sqrt(gx * gx + gy * gy) * params.volumeIntensity * 0.5
                    volumeMap[r * cols + c] = min(1.0, max(0.0, lumMap[r * cols + c] + edge))
                }
            }
        }

        // 3. Map to characters with optional error diffusion (Floyd-Steinberg)
        var text = ""
        text.reserveCapacity((cols + 1) * rows)

        var errorMap = volumeMap

        for r in 0..<rows {
            for c in 0..<cols {
                let idx = r * cols + c
                var v = errorMap[idx]
                if params.invert {
                    v = 1.0 - v
                }
                v = max(0.0, min(1.0, v))

                let charIdxFloat = v * numChars
                let charIdx = Int(round(charIdxFloat))
                let clampedIdx = max(0, min(chars.count - 1, charIdx))
                text.append(chars[clampedIdx])

                if params.dithering {
                    let quantError = v - (Float(clampedIdx) / numChars)
                    // Distribute error
                    if c + 1 < cols {
                        errorMap[r * cols + (c + 1)] += quantError * (7.0 / 16.0)
                    }
                    if r + 1 < rows {
                        if c > 0 {
                            errorMap[(r + 1) * cols + (c - 1)] += quantError * (3.0 / 16.0)
                        }
                        errorMap[(r + 1) * cols + c] += quantError * (5.0 / 16.0)
                        if c + 1 < cols {
                            errorMap[(r + 1) * cols + (c + 1)] += quantError * (1.0 / 16.0)
                        }
                    }
                }
            }
            text.append("\n")
        }

        return text
    }

    /// Bakes the ASCII representation into a TextLayer.
    public func bakeToTextLayer(from grid: SparseTileGrid, params: ASCIIParams) -> TextLayer {
        let asciiText = generateText(from: grid, params: params)
        let textLayer = TextLayer(name: "ASCII Art", text: asciiText, fontName: params.fontName, fontSize: params.fontSize, canvasSize: grid.canvasSize)
        return textLayer
    }

    /// Bakes the ASCII representation into a new BitmapLayer.
    public func bakeToBitmapLayer(from grid: SparseTileGrid, params: ASCIIParams, canvasSize: CGSize) -> BitmapLayer {
        let asciiText = generateText(from: grid, params: params)
        let textLayer = TextLayer(name: "ASCII Art", text: asciiText, fontName: params.fontName, fontSize: params.fontSize, canvasSize: canvasSize)
        let bitmapLayer = BitmapLayer(name: "ASCII Art (Raster)", canvasSize: canvasSize)
        textLayer.rasterizeIfNeeded()
        bitmapLayer.tileGrid.copyFrom(textLayer.tileGrid)
        return bitmapLayer
    }
}
