import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ExportFormat: String, CaseIterable, Sendable {
    case png8
    case png16
    case jpeg
    case tiff
    case heic

    public var fileExtension: String {
        switch self {
        case .png8, .png16: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        case .heic: return "heic"
        }
    }

    public var utType: CFString {
        switch self {
        case .png8, .png16: return UTType.png.identifier as CFString
        case .jpeg: return UTType.jpeg.identifier as CFString
        case .tiff: return UTType.tiff.identifier as CFString
        case .heic: return UTType.heic.identifier as CFString
        }
    }
}

public struct ExportOptions: Sendable {
    public var format: ExportFormat
    public var quality: Float // 0.0 to 1.0 (for JPEG/HEIC)
    public var preserveAlpha: Bool

    public init(format: ExportFormat = .png8, quality: Float = 0.9, preserveAlpha: Bool = true) {
        self.format = format
        self.quality = quality
        self.preserveAlpha = preserveAlpha
    }
}

public final class ImageExporter: @unchecked Sendable {
    public init() {}

    /// Exports a SparseTileGrid into encoded image data in the specified format.
    public func export(grid: SparseTileGrid, options: ExportOptions = ExportOptions()) -> Data? {
        let width = Int(grid.canvasSize.width)
        let height = Int(grid.canvasSize.height)

        if options.format == .png16 {
            return exportPNG16(grid: grid, width: width, height: height)
        }

        guard let cgImage = createCGImage(from: grid, width: width, height: height, preserveAlpha: options.preserveAlpha) else {
            return nil
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, options.format.utType, 1, nil) else {
            return nil
        }

        var imageProperties: [CFString: Any] = [:]
        if options.format == .jpeg || options.format == .heic {
            imageProperties[kCGImageDestinationLossyCompressionQuality] = options.quality
        }

        CGImageDestinationAddImage(destination, cgImage, imageProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

    /// Exports 16-bit per channel PNG preserving high dynamic range alpha.
    private func exportPNG16(grid: SparseTileGrid, width: Int, height: Int) -> Data? {
        var rgba16 = [UInt16](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let p = grid.getPixel(x: x, y: y)
                let idx = (y * width + x) * 4
                // Scale 8-bit to 16-bit: (v * 65535) / 255 = v * 257
                rgba16[idx] = UInt16(p.r) * 257
                rgba16[idx + 1] = UInt16(p.g) * 257
                rgba16[idx + 2] = UInt16(p.b) * 257
                rgba16[idx + 3] = UInt16(p.a) * 257
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder16Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let dataSize = width * height * 8

        guard let provider = CGDataProvider(data: Data(bytes: rgba16, count: dataSize) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 16,
                bitsPerPixel: 64,
                bytesPerRow: width * 8,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return mutableData as Data
    }

    private func createCGImage(from grid: SparseTileGrid, width: Int, height: Int, preserveAlpha: Bool) -> CGImage? {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let p = grid.getPixel(x: x, y: y)
                let idx = (y * width + x) * 4
                rgba[idx] = p.r
                rgba[idx + 1] = p.g
                rgba[idx + 2] = p.b
                rgba[idx + 3] = preserveAlpha ? p.a : 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo = preserveAlpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | alphaInfo.rawValue

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
}
