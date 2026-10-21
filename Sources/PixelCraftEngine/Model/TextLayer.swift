import Foundation
import CoreGraphics
import CoreText
import Metal
import simd

#if canImport(AppKit)
import AppKit
#endif

/// Dynamic vector text layer that rasterizes CoreText typography into a SparseTileGrid.
public final class TextLayer: Layer, @unchecked Sendable {
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

    // Typography Properties
    public var text: String { didSet { isDirty = true } }
    public var fontName: String { didSet { isDirty = true } }
    public var fontSize: CGFloat { didSet { isDirty = true } }
    public var textColor: SIMD4<Float> { didSet { isDirty = true } }
    public var position: CGPoint { didSet { isDirty = true } }
    public var tracking: CGFloat { didSet { isDirty = true } }
    public var leading: CGFloat { didSet { isDirty = true } }

    private var isDirty: Bool = true

    public init(
        id: UUID = UUID(),
        name: String = "Text Layer",
        text: String = "PixelCraft",
        fontName: String = "Helvetica",
        fontSize: CGFloat = 48.0,
        textColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        position: CGPoint = CGPoint(x: 100, y: 100),
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
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.position = position
        self.tracking = 0.0
        self.leading = 0.0
        self.isVisible = isVisible
        self.opacity = max(0.0, min(1.0, opacity))
        self.blendMode = blendMode
        self.lockAlpha = lockAlpha
        self.isLocked = isLocked
        self.tileGrid = SparseTileGrid(canvasSize: canvasSize, device: device)
        rasterizeIfNeeded()
    }

    public convenience init(
        id: UUID = UUID(),
        name: String = "Text Layer",
        text: String = "PixelCraft",
        fontName: String = "Helvetica",
        fontSize: CGFloat = 48.0,
        textColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        position: CGPoint = CGPoint(x: 100, y: 100),
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
            text: text,
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            position: position,
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
        rasterizeIfNeeded()
        let b = tileGrid.contentBounds
        return b == .zero ? CGRect(origin: position, size: CGSize(width: 200, height: fontSize * 1.5)) : b
    }

    public func markDirty() {
        isDirty = true
    }

    public func rasterizeIfNeeded() {
        guard isDirty else { return }
        tileGrid.removeAllTiles()
        
        guard !text.isEmpty else {
            isDirty = false
            return
        }

        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let color = CGColor(
            srgbRed: CGFloat(textColor.x),
            green: CGFloat(textColor.y),
            blue: CGFloat(textColor.z),
            alpha: CGFloat(textColor.w)
        )
        
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let imageBounds = CTLineGetImageBounds(line, nil)
        let textBounds = CGRect(
            x: position.x + imageBounds.origin.x,
            y: position.y + imageBounds.origin.y,
            width: max(1.0, imageBounds.width),
            height: max(1.0, imageBounds.height)
        )

        guard textBounds.width > 0 && textBounds.height > 0 else {
            isDirty = false
            return
        }

        // Determine which tiles intersect textBounds
        let minCol = max(0, Int(floor(textBounds.minX / 512.0)))
        let maxCol = min(tileGrid.gridColumns - 1, Int(floor(textBounds.maxX / 512.0)))
        let minRow = max(0, Int(floor(textBounds.minY / 512.0)))
        let maxRow = min(tileGrid.gridRows - 1, Int(floor(textBounds.maxY / 512.0)))

        guard minCol <= maxCol && minRow <= maxRow else {
            isDirty = false
            return
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        for ty in minRow...maxRow {
            for tx in minCol...maxCol {
                let coord = TileCoord(x: tx, y: ty)
                var rawData = [UInt8](repeating: 0, count: SparseTileGrid.bytesPerTile)

                if let ctx = CGContext(
                    data: &rawData,
                    width: SparseTileGrid.tileSize,
                    height: SparseTileGrid.tileSize,
                    bitsPerComponent: 8,
                    bytesPerRow: SparseTileGrid.tileSize * 4,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                ) {
                    let tileOriginX: CGFloat = CGFloat(tx * SparseTileGrid.tileSize)
                    let tileOriginY: CGFloat = CGFloat(ty * SparseTileGrid.tileSize)
                    
                    ctx.textPosition = CGPoint(x: position.x - tileOriginX, y: position.y - tileOriginY)
                    CTLineDraw(line, ctx)

                    // Check if tile has any non-zero alpha pixels
                    var hasContent = false
                    for i in stride(from: 3, to: SparseTileGrid.bytesPerTile, by: 4) {
                        if rawData[i] > 0 {
                            hasContent = true
                            break
                        }
                    }

                    if hasContent {
                        tileGrid.loadTileData(coord: coord, data: Data(rawData))
                    }
                }
            }
        }

        isDirty = false
    }

    public func duplicate() -> any Layer {
        rasterizeIfNeeded()
        let cloned = TextLayer(
            name: "\(name) Copy",
            text: text,
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            position: position,
            canvasSize: tileGrid.canvasSize,
            device: tileGrid.device,
            isVisible: isVisible,
            opacity: opacity,
            blendMode: blendMode,
            lockAlpha: lockAlpha,
            isLocked: isLocked
        )
        cloned.tracking = tracking
        cloned.leading = leading
        cloned.tileGrid.copyFrom(tileGrid)
        cloned.isDirty = false
        return cloned
    }

    public func render(into context: MetalRenderContext) {
        guard isVisible, opacity > 0.001 else { return }
        rasterizeIfNeeded()
    }

    public func composite(layer: any Layer, canvasSize: CGSize) {
        rasterizeIfNeeded()
        let bitmap = BitmapLayer(name: name, canvasSize: canvasSize, device: tileGrid.device)
        bitmap.tileGrid.copyFrom(tileGrid)
        bitmap.composite(layer: layer, canvasSize: canvasSize)
        tileGrid.copyFrom(bitmap.tileGrid)
    }

    public func merge(layer: any Layer, canvasSize: CGSize) {
        composite(layer: layer, canvasSize: canvasSize)
    }
}
