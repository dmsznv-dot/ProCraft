import Foundation
import CoreGraphics
import ImageIO
import Accelerate
import UniformTypeIdentifiers
import Metal

public enum ImageImportError: LocalizedError, Equatable {
    case fileNotFound(String)
    case unsupportedFormat(String)
    case failedToCreateImageSource
    case failedToDecodeCGImage
    case canvasExceedsMaximumSize(width: Int, height: Int, maxWidth: Int, maxHeight: Int)
    case cannotAllocateMemory

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Image file not found at path: \(path)"
        case .unsupportedFormat(let ext):
            return "Unsupported image format '.\(ext)'. Supported formats: PNG, JPEG, TIFF, HEIC, WebP, BMP, GIF."
        case .failedToCreateImageSource:
            return "Failed to initialize ImageIO image source."
        case .failedToDecodeCGImage:
            return "Failed to decode raster image data into CGImage."
        case .canvasExceedsMaximumSize(let w, let h, let maxW, let maxH):
            return "Image dimensions (\(w)x\(h)) exceed maximum canvas resolution (\(maxW)x\(maxH))."
        case .cannotAllocateMemory:
            return "Cannot allocate memory buffer for decoded image pixels."
        }
    }
}

/// Represents an in-memory decoded raster image ready for ingestion into SparseTileGrid.
public struct DecodedImage: Sendable {
    public let width: Int
    public let height: Int
    public let hasAlpha: Bool
    public let pixelData: Data // RGBA8 32-bit straight alpha (width * height * 4 bytes)
    public let title: String

    public var size: CGSize {
        CGSize(width: width, height: height)
    }

    public var aspectRatio: CGFloat {
        guard height > 0 else { return 1.0 }
        return CGFloat(width) / CGFloat(height)
    }

    public init(
        width: Int,
        height: Int,
        hasAlpha: Bool,
        pixelData: Data,
        title: String = "Imported Image"
    ) {
        self.width = width
        self.height = height
        self.hasAlpha = hasAlpha
        self.pixelData = pixelData
        self.title = title
    }
}

/// High-performance Apple Silicon native image importer for PNG, JPEG, TIFF, HEIC, WebP, BMP, and GIF.
public final class ImageImporter: @unchecked Sendable {
    public static let shared = ImageImporter()

    public static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tiff", "tif", "heic", "heif", "webp", "bmp", "gif"
    ]

    public static func isSupported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext) || ext == "psd" || ext == "pcpro"
    }

    public static func isImageFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    public init() {}

    // MARK: - Decoding

    /// Decodes an image file at URL into standard straight RGBA8 format.
    public func decode(from url: URL) throws -> DecodedImage {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageImportError.fileNotFound(url.path)
        }

        guard let data = try? Data(contentsOf: url) else {
            throw ImageImportError.fileNotFound(url.path)
        }

        let title = url.deletingPathExtension().lastPathComponent
        return try decode(from: data, titleHint: title)
    }

    /// Decodes raw image data into standard straight RGBA8 format.
    public func decode(from data: Data, titleHint: String = "Imported Image") throws -> DecodedImage {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldAllowFloat: true
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            throw ImageImportError.failedToCreateImageSource
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            throw ImageImportError.failedToDecodeCGImage
        }

        return try decode(cgImage: cgImage, titleHint: titleHint)
    }

    /// Decodes a CGImage into straight RGBA8 pixel data.
    public func decode(cgImage: CGImage, titleHint: String = "Imported Image") throws -> DecodedImage {
        let width = cgImage.width
        let height = cgImage.height

        guard width >= Document.minDimension && height >= Document.minDimension else {
            throw ImageImportError.failedToDecodeCGImage
        }

        guard width <= Document.maxDimensionWidth && height <= Document.maxDimensionHeight else {
            throw ImageImportError.canvasExceedsMaximumSize(
                width: width,
                height: height,
                maxWidth: Document.maxDimensionWidth,
                maxHeight: Document.maxDimensionHeight
            )
        }

        let byteCount = width * height * 4
        var rawBytes = [UInt8](repeating: 0, count: byteCount)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // CoreGraphics requires premultipliedLast for 32-bit RGBA context
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &rawBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ImageImportError.cannotAllocateMemory
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let hasAlpha = cgImage.alphaInfo != .none &&
                       cgImage.alphaInfo != .noneSkipLast &&
                       cgImage.alphaInfo != .noneSkipFirst

        // Unpremultiply alpha in-place using Accelerate vImage for straight RGBA
        if hasAlpha {
            rawBytes.withUnsafeMutableBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                var buffer = vImage_Buffer(
                    data: base,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * 4
                )
                vImageUnpremultiplyData_RGBA8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags))
            }
        }

        return DecodedImage(
            width: width,
            height: height,
            hasAlpha: hasAlpha,
            pixelData: Data(rawBytes),
            title: titleHint
        )
    }

    // MARK: - Document & Layer Creation

    /// Creates a complete Document matching the exact dimensions and aspect ratio of the image.
    public func createDocument(from url: URL) throws -> Document {
        let decoded = try decode(from: url)
        return try createDocument(from: decoded)
    }

    /// Creates a complete Document from a DecodedImage.
    public func createDocument(from decoded: DecodedImage) throws -> Document {
        let canvasSize = CGSize(width: decoded.width, height: decoded.height)
        let layer = BitmapLayer(
            name: decoded.title,
            canvasSize: canvasSize
        )

        populate(grid: layer.tileGrid, with: decoded, destinationOrigin: .zero)

        let document = try Document(
            title: decoded.title,
            canvasSize: canvasSize,
            initialLayer: layer
        )

        // Frame viewport to fit screen nicely
        document.viewportTransform = ViewportTransform.fitToViewport(
            canvasSize: canvasSize,
            viewportSize: CGSize(width: 1200, height: 800)
        )

        return document
    }

    /// Creates a BitmapLayer from an image suitable for insertion into an existing canvas.
    public func createLayer(
        from url: URL,
        targetCanvasSize: CGSize,
        centerInCanvas: Bool = true
    ) throws -> BitmapLayer {
        let decoded = try decode(from: url)
        return createLayer(from: decoded, targetCanvasSize: targetCanvasSize, centerInCanvas: centerInCanvas)
    }

    /// Creates a BitmapLayer from a DecodedImage for an existing canvas.
    public func createLayer(
        from decoded: DecodedImage,
        targetCanvasSize: CGSize,
        centerInCanvas: Bool = true
    ) -> BitmapLayer {
        let layer = BitmapLayer(
            name: decoded.title,
            canvasSize: targetCanvasSize
        )

        let origin: CGPoint
        if centerInCanvas {
            let ox = max(0.0, floor((targetCanvasSize.width - CGFloat(decoded.width)) * 0.5))
            let oy = max(0.0, floor((targetCanvasSize.height - CGFloat(decoded.height)) * 0.5))
            origin = CGPoint(x: ox, y: oy)
        } else {
            origin = .zero
        }

        populate(grid: layer.tileGrid, with: decoded, destinationOrigin: origin)
        return layer
    }

    // MARK: - Fast Metal Tile Upload

    /// Uploads decoded pixel data into a SparseTileGrid using fast hardware Metal texture operations.
    public func populate(
        grid: SparseTileGrid,
        with decoded: DecodedImage,
        destinationOrigin: CGPoint = .zero
    ) {
        let ox = Int(round(destinationOrigin.x))
        let oy = Int(round(destinationOrigin.y))

        let canvasW = Int(grid.canvasSize.width)
        let canvasH = Int(grid.canvasSize.height)

        let minX = max(0, ox)
        let maxX = min(canvasW, ox + decoded.width)
        let minY = max(0, oy)
        let maxY = min(canvasH, oy + decoded.height)

        guard minX < maxX && minY < maxY else { return }

        let minCol = minX / SparseTileGrid.tileSize
        let maxCol = (maxX - 1) / SparseTileGrid.tileSize
        let minRow = minY / SparseTileGrid.tileSize
        let maxRow = (maxY - 1) / SparseTileGrid.tileSize

        decoded.pixelData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

            for ty in minRow...maxRow {
                for tx in minCol...maxCol {
                    let tileCanvasMinX = tx * SparseTileGrid.tileSize
                    let tileCanvasMaxX = (tx + 1) * SparseTileGrid.tileSize
                    let tileCanvasMinY = ty * SparseTileGrid.tileSize
                    let tileCanvasMaxY = (ty + 1) * SparseTileGrid.tileSize

                    let cMinX = max(minX, tileCanvasMinX)
                    let cMaxX = min(maxX, tileCanvasMaxX)
                    let cMinY = max(minY, tileCanvasMinY)
                    let cMaxY = min(maxY, tileCanvasMaxY)

                    guard cMinX < cMaxX && cMinY < cMaxY else { continue }

                    let destX = cMinX - tileCanvasMinX
                    let destY = cMinY - tileCanvasMinY
                    let destW = cMaxX - cMinX
                    let destH = cMaxY - cMinY

                    let srcX = cMinX - ox
                    let srcY = cMinY - oy

                    let coord = TileCoord(x: tx, y: ty)
                    let sourceRowBytes = decoded.width * 4
                    let sourcePtr = UnsafeRawPointer(baseAddress + (srcY * decoded.width + srcX) * 4)

                    grid.writeRegion(
                        coord: coord,
                        x: destX,
                        y: destY,
                        width: destW,
                        height: destH,
                        from: sourcePtr,
                        sourceBytesPerRow: sourceRowBytes
                    )
                }
            }
        }
    }
}
