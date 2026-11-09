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
    /// Stretch luminance between the 2nd and 98th percentile before mapping (adaptive contrast).
    public var autoContrast: Bool
    /// Glyph color used when rasterizing (straight RGBA 0...1).
    public var textColor: SIMD4<Float>
    /// Optional solid background when rasterizing; `nil` keeps the layer transparent.
    public var backgroundColor: SIMD4<Float>?

    public init(
        gridColumns: Int = 120,
        gridRows: Int = 60,
        charSet: ASCIICharacterSet = .standard,
        fontName: String = "SF Mono",
        fontSize: CGFloat = 12.0,
        volumeIntensity: Float = 1.0,
        dithering: Bool = true,
        invert: Bool = false,
        autoContrast: Bool = true,
        textColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
        backgroundColor: SIMD4<Float>? = nil
    ) {
        self.autoContrast = autoContrast
        self.textColor = textColor
        self.backgroundColor = backgroundColor
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

        // 1. Luminance map: box-average every cell (single-pixel sampling aliased badly).
        var lumMap = [Float](repeating: 0, count: cols * rows)
        let w = Int(width)
        let h = Int(height)
        if w > 0 && h > 0 {
            let rgba = grid.readRGBA()
            for r in 0..<rows {
                let y0 = min(h - 1, Int(CGFloat(r) * cellH))
                let y1 = max(y0 + 1, min(h, Int(CGFloat(r + 1) * cellH)))
                for c in 0..<cols {
                    let x0 = min(w - 1, Int(CGFloat(c) * cellW))
                    let x1 = max(x0 + 1, min(w, Int(CGFloat(c + 1) * cellW)))
                    // Sub-sample large cells (max ~8x8 samples per cell) to stay fast.
                    let stepX = max(1, (x1 - x0) / 8)
                    let stepY = max(1, (y1 - y0) / 8)
                    var sum: Float = 0
                    var count: Float = 0
                    var y = y0
                    while y < y1 {
                        var x = x0
                        while x < x1 {
                            let o = (y * w + x) * 4
                            let a = Float(rgba[o + 3]) / 255.0
                            // Transparent is treated as dark, as before.
                            let lum = (Float(rgba[o]) * 0.2126 + Float(rgba[o + 1]) * 0.7152 + Float(rgba[o + 2]) * 0.0722) / 255.0
                            sum += lum * a
                            count += 1
                            x += stepX
                        }
                        y += stepY
                    }
                    lumMap[r * cols + c] = count > 0 ? sum / count : 0
                }
            }
        }

        // 1b. Adaptive contrast: stretch the 2nd..98th percentile range to 0...1.
        if params.autoContrast && lumMap.count > 4 {
            let sorted = lumMap.sorted()
            let lo = sorted[Int(Float(sorted.count - 1) * 0.02)]
            let hi = sorted[Int(Float(sorted.count - 1) * 0.98)]
            if hi - lo > 0.05 {
                for i in 0..<lumMap.count {
                    lumMap[i] = max(0, min(1, (lumMap[i] - lo) / (hi - lo)))
                }
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

                if params.dithering && numChars > 0 {
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
    /// Every character is drawn centered in its own grid cell, so the art always covers the whole canvas
    /// and keeps the exact column/row layout (the old path drew everything as one CoreText line).
    public func bakeToBitmapLayer(from grid: SparseTileGrid, params: ASCIIParams, canvasSize: CGSize) -> BitmapLayer {
        let asciiText = generateText(from: grid, params: params)
        let bitmapLayer = BitmapLayer(name: "ASCII Art (Raster)", canvasSize: canvasSize)
        let rgba = Self.rasterize(text: asciiText, params: params, canvasSize: canvasSize)
        bitmapLayer.tileGrid.writeRGBA(rgba)
        return bitmapLayer
    }

    /// Rasterizes ASCII text (one row per line) into a tightly packed RGBA8 buffer (top-left origin).
    public static func rasterize(text: String, params: ASCIIParams, canvasSize: CGSize) -> [UInt8] {
        let w = Int(canvasSize.width)
        let h = Int(canvasSize.height)
        guard w > 0, h > 0 else { return [] }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }
        let rows = max(1, lines.count)
        let cols = max(1, lines.map { $0.count }.max() ?? 1)
        let cellW = CGFloat(w) / CGFloat(cols)
        let cellH = CGFloat(h) / CGFloat(rows)

        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return }

            if let bg = params.backgroundColor {
                ctx.setFillColor(CGColor(srgbRed: CGFloat(bg.x), green: CGFloat(bg.y), blue: CGFloat(bg.z), alpha: CGFloat(bg.w)))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            }

            // Fit the font to the cell: monospaced advance ~0.6 em, line box ~1.0 em for block glyphs.
            let probe = CTFontCreateWithName(params.fontName as CFString, 100, nil)
            var glyph = CGGlyph(0)
            var mChar: UniChar = 77 // "M"
            CTFontGetGlyphsForCharacters(probe, &mChar, &glyph, 1)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(probe, .horizontal, &glyph, &advance, 1)
            let advanceRatio = max(0.3, advance.width / 100.0)
            let heightRatio = max(0.5, (CTFontGetAscent(probe) + CTFontGetDescent(probe)) / 100.0)
            let fontSize = max(1.0, min(cellW / advanceRatio, cellH / heightRatio))
            let font = CTFontCreateWithName(params.fontName as CFString, fontSize, nil)
            let ascent = CTFontGetAscent(font)
            let descent = CTFontGetDescent(font)

            let tc = params.textColor
            let color = CGColor(srgbRed: CGFloat(tc.x), green: CGFloat(tc.y), blue: CGFloat(tc.z), alpha: CGFloat(tc.w))
            let attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: color
            ]

            // Cache one CTLine per distinct character.
            var lineCache: [Character: (line: CTLine, width: CGFloat)] = [:]
            for (r, lineText) in lines.enumerated() {
                // CG origin is bottom-left; row 0 of the art must be at the top of the canvas.
                let cellTop = CGFloat(h) - CGFloat(r) * cellH
                let baselineY = cellTop - (cellH - (ascent + descent)) * 0.5 - ascent
                for (c, ch) in lineText.enumerated() where ch != " " {
                    let entry: (line: CTLine, width: CGFloat)
                    if let cached = lineCache[ch] {
                        entry = cached
                    } else {
                        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(ch), attributes: attributes))
                        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                        entry = (line, width)
                        lineCache[ch] = entry
                    }
                    let x = CGFloat(c) * cellW + (cellW - entry.width) * 0.5
                    ctx.textPosition = CGPoint(x: x, y: baselineY)
                    CTLineDraw(entry.line, ctx)
                }
            }
        }

        // Convert premultiplied -> straight alpha (tiles store straight RGBA).
        var i = 0
        while i < buffer.count {
            let a = buffer[i + 3]
            if a != 0 && a != 255 {
                let af = Float(a) / 255.0
                buffer[i] = UInt8(min(255, Float(buffer[i]) / af + 0.5))
                buffer[i + 1] = UInt8(min(255, Float(buffer[i + 1]) / af + 0.5))
                buffer[i + 2] = UInt8(min(255, Float(buffer[i + 2]) / af + 0.5))
            }
            i += 4
        }
        return buffer
    }
}
