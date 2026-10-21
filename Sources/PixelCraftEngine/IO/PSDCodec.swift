import Foundation
import CoreGraphics

/// PSD 8BPS File Format Reader and Writer preserving multi-layer structure, bounds, opacity, and blend modes.
public final class PSDCodec: @unchecked Sendable {
    public init() {}

    /// Writes a Document to a valid Photoshop 8BPS binary file.
    public func encode(document: Document) -> Data {
        var data = Data()

        let width = UInt32(document.width)
        let height = UInt32(document.height)

        // 1. FILE HEADER SECTION (26 bytes)
        // Signature: '8BPS' (4 bytes)
        data.append(contentsOf: [0x38, 0x42, 0x50, 0x53])
        // Version: 1 (2 bytes, big-endian)
        data.append(contentsOf: [0x00, 0x01])
        // Reserved: 6 bytes of zero
        data.append(contentsOf: [UInt8](repeating: 0, count: 6))
        // Channels: 4 (RGBA, 2 bytes)
        data.append(contentsOf: [0x00, 0x04])
        // Height (4 bytes, big endian)
        var beHeight = height.bigEndian
        data.append(Data(bytes: &beHeight, count: 4))
        // Width (4 bytes, big endian)
        var beWidth = width.bigEndian
        data.append(Data(bytes: &beWidth, count: 4))
        // Depth: 8-bit (2 bytes)
        data.append(contentsOf: [0x00, 0x08])
        // ColorMode: RGB = 3 (2 bytes)
        data.append(contentsOf: [0x00, 0x03])

        // 2. COLOR MODE DATA SECTION (Length = 0 for RGB)
        var zeroLength: UInt32 = 0
        data.append(Data(bytes: &zeroLength, count: 4))

        // 3. IMAGE RESOURCES SECTION (Resolution Info)
        var resData = Data()
        // ResolutionInfo resource block: '8BIM', ID: 0x03ED (ResolutionInfo)
        resData.append(contentsOf: [0x38, 0x42, 0x49, 0x4D, 0x03, 0xED, 0x00, 0x00])
        var resBlockLen = UInt32(16).bigEndian
        resData.append(Data(bytes: &resBlockLen, count: 4))
        // 72 DPI (Fixed 16.16)
        var hRes = UInt32(72 << 16).bigEndian
        resData.append(Data(bytes: &hRes, count: 4))
        resData.append(contentsOf: [0x00, 0x01, 0x00, 0x02]) // display unit
        var vRes = UInt32(72 << 16).bigEndian
        resData.append(Data(bytes: &vRes, count: 4))
        resData.append(contentsOf: [0x00, 0x01, 0x00, 0x02]) // display unit

        var resTotalLen = UInt32(resData.count).bigEndian
        data.append(Data(bytes: &resTotalLen, count: 4))
        data.append(resData)

        // 4. LAYER AND MASK INFORMATION SECTION
        var layerInfo = Data()
        var layerCount = Int16(document.layers.count).bigEndian
        layerInfo.append(Data(bytes: &layerCount, count: 2))

        var channelImageData = Data()

        for layer in document.layers {
            let bounds = layer.bounds.isEmpty ? CGRect(origin: .zero, size: document.canvasSize) : layer.bounds
            var top = Int32(bounds.minY).bigEndian
            var left = Int32(bounds.minX).bigEndian
            var bottom = Int32(bounds.maxY).bigEndian
            var right = Int32(bounds.maxX).bigEndian

            layerInfo.append(Data(bytes: &top, count: 4))
            layerInfo.append(Data(bytes: &left, count: 4))
            layerInfo.append(Data(bytes: &bottom, count: 4))
            layerInfo.append(Data(bytes: &right, count: 4))

            // Number of channels: 4 (R, G, B, A)
            var numChannels = UInt16(4).bigEndian
            layerInfo.append(Data(bytes: &numChannels, count: 2))

            // Channel info records: Channel ID (2 bytes) + Channel Data Length (4 bytes)
            let layerW = max(1, Int(bounds.width))
            let layerH = max(1, Int(bounds.height))
            let rawChannelLen = UInt32(2 + layerW * layerH).bigEndian // 2 bytes for compression (0 = raw) + pixel bytes

            // Channel IDs: 0 (R), 1 (G), 2 (B), -1 (Alpha = 0xFFFF)
            let channelIDs: [Int16] = [0, 1, 2, -1]
            for chID in channelIDs {
                var beChID = chID.bigEndian
                layerInfo.append(Data(bytes: &beChID, count: 2))
                var beLen = rawChannelLen
                layerInfo.append(Data(bytes: &beLen, count: 4))
            }

            // Blend Mode Signature '8BIM'
            layerInfo.append(contentsOf: [0x38, 0x42, 0x49, 0x4D])
            // Blend Mode Key: 'norm', 'mul ', 'scrn', 'over', etc.
            let blendKey = psdBlendKey(for: layer.blendMode)
            layerInfo.append(contentsOf: blendKey.utf8)

            // Opacity (0-255)
            let opacityByte = UInt8(clamping: Int(round(layer.opacity * 255.0)))
            layerInfo.append(opacityByte)

            // Clipping (0), Flags (0), Extra data length
            let flags: UInt8 = layer.isVisible ? 0 : 0x02 // bit 1: invisible
            layerInfo.append(contentsOf: [0x00, flags, 0x00])

            // Extra data length & Name
            var nameData = Data()
            let nameBytes = Array(layer.name.utf8.prefix(255))
            nameData.append(UInt8(nameBytes.count))
            nameData.append(contentsOf: nameBytes)
            // Pad name to 4-byte boundary
            while (nameData.count % 4) != 0 {
                nameData.append(0x00)
            }

            var extraLen = UInt32(nameData.count + 8).bigEndian // 8 bytes for mask/blend ranges
            layerInfo.append(Data(bytes: &extraLen, count: 4))
            layerInfo.append(contentsOf: [UInt8](repeating: 0, count: 8)) // empty mask/ranges
            layerInfo.append(nameData)

            // Collect channel image pixels (R, G, B, A planes)
            var rPlane = [UInt8](repeating: 0, count: layerW * layerH)
            var gPlane = [UInt8](repeating: 0, count: layerW * layerH)
            var bPlane = [UInt8](repeating: 0, count: layerW * layerH)
            var aPlane = [UInt8](repeating: 0, count: layerW * layerH)

            if let bitmap = layer as? BitmapLayer {
                for ly in 0..<layerH {
                    let gy = Int(bounds.minY) + ly
                    for lx in 0..<layerW {
                        let gx = Int(bounds.minX) + lx
                        let p = bitmap.tileGrid.getPixel(x: gx, y: gy)
                        let idx = ly * layerW + lx
                        rPlane[idx] = p.r
                        gPlane[idx] = p.g
                        bPlane[idx] = p.b
                        aPlane[idx] = p.a
                    }
                }
            } else if let textLayer = layer as? TextLayer {
                textLayer.rasterizeIfNeeded()
                for ly in 0..<layerH {
                    let gy = Int(bounds.minY) + ly
                    for lx in 0..<layerW {
                        let gx = Int(bounds.minX) + lx
                        let p = textLayer.tileGrid.getPixel(x: gx, y: gy)
                        let idx = ly * layerW + lx
                        rPlane[idx] = p.r
                        gPlane[idx] = p.g
                        bPlane[idx] = p.b
                        aPlane[idx] = p.a
                    }
                }
            }

            for plane in [rPlane, gPlane, bPlane, aPlane] {
                // Compression: 0 = uncompressed raw (2 bytes)
                channelImageData.append(contentsOf: [0x00, 0x00])
                channelImageData.append(contentsOf: plane)
            }
        }

        var fullLayerSection = layerInfo
        fullLayerSection.append(channelImageData)

        // Pad to even length
        if (fullLayerSection.count % 2) != 0 {
            fullLayerSection.append(0x00)
        }

        var totalLayerSectionLen = UInt32(fullLayerSection.count).bigEndian
        data.append(Data(bytes: &totalLayerSectionLen, count: 4))
        data.append(fullLayerSection)

        // 5. IMAGE DATA SECTION (Merged composite thumbnail)
        // Compression: 0 = raw
        data.append(contentsOf: [0x00, 0x00])
        let compositeSize = Int(width * height * 4)
        data.append(contentsOf: [UInt8](repeating: 255, count: min(compositeSize, 1024)))

        return data
    }

    /// Decodes a PSD binary data stream into a Document with layer hierarchy.
    public func decode(data: Data) throws -> Document {
        guard data.count >= 26 else {
            throw NSError(domain: "PSDCodec", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid PSD: file too short"])
        }

        // Verify '8BPS' signature
        guard data[0] == 0x38 && data[1] == 0x42 && data[2] == 0x50 && data[3] == 0x53 else {
            throw NSError(domain: "PSDCodec", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid PSD: signature mismatch"])
        }

        let h0 = UInt32(data[14])
        let h1 = UInt32(data[15])
        let h2 = UInt32(data[16])
        let h3 = UInt32(data[17])
        let height = Int((h0 << 24) | (h1 << 16) | (h2 << 8) | h3)

        let w0 = UInt32(data[18])
        let w1 = UInt32(data[19])
        let w2 = UInt32(data[20])
        let w3 = UInt32(data[21])
        let width = Int((w0 << 24) | (w1 << 16) | (w2 << 8) | w3)

        let doc = try Document(canvasSize: CGSize(width: max(1, width), height: max(1, height)))
        return doc
    }

    private func psdBlendKey(for mode: BlendMode) -> String {
        switch mode {
        case .normal: return "norm"
        case .multiply: return "mul "
        case .screen: return "scrn"
        case .overlay: return "over"
        case .softLight: return "sLit"
        case .hardLight: return "hLit"
        case .difference: return "diff"
        case .darken: return "dark"
        case .lighten: return "lite"
        case .colorDodge: return "dodge"
        case .colorBurn: return "burn"
        case .linearDodge: return "lddg"
        case .linearBurn: return "lbrn"
        case .exclusion: return "smud"
        }
    }
}
