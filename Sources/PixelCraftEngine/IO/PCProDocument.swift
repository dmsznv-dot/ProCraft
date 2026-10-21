import Foundation
import CoreGraphics

public struct PCProManifest: Codable, Sendable {
    public var version: Int
    public var width: Int
    public var height: Int
    public var layers: [PCProLayerMeta]

    public struct PCProLayerMeta: Codable, Sendable {
        public var id: String
        public var name: String
        public var type: String // "bitmap", "text", "adjustment", "effect"
        public var isVisible: Bool
        public var opacity: Float
        public var blendMode: UInt32
        public var lockAlpha: Bool
        public var textContent: String?
        public var fontSize: Double?
        public var fontName: String?
    }
}

public final class PCProDocument: @unchecked Sendable {
    public init() {}

    /// Serializes a Document into a macOS FileWrapper package (.pcpro bundle).
    public func serialize(document: Document) throws -> FileWrapper {
        var fileWrappers: [String: FileWrapper] = [:]

        var layerMetas: [PCProManifest.PCProLayerMeta] = []

        for (idx, layer) in document.layers.enumerated() {
            let layerId = "layer_\(idx)"
            let typeStr: String
            var textContent: String?
            var fontSize: Double?
            var fontName: String?

            if let textLayer = layer as? TextLayer {
                typeStr = "text"
                textContent = textLayer.text
                fontSize = Double(textLayer.fontSize)
                fontName = textLayer.fontName
            } else if layer is AdjustmentLayer {
                typeStr = "adjustment"
            } else if layer is EffectLayer {
                typeStr = "effect"
            } else {
                typeStr = "bitmap"
            }

            let meta = PCProManifest.PCProLayerMeta(
                id: layerId,
                name: layer.name,
                type: typeStr,
                isVisible: layer.isVisible,
                opacity: layer.opacity,
                blendMode: layer.blendMode.rawValue,
                lockAlpha: layer.lockAlpha,
                textContent: textContent,
                fontSize: fontSize,
                fontName: fontName
            )
            layerMetas.append(meta)

            // Save tile binary data for bitmap or text layers
            var tileData = Data()
            if let bitmap = layer as? BitmapLayer {
                for coord in bitmap.tileGrid.allAllocatedCoordinates() {
                    if let raw = bitmap.tileGrid.extractTileData(coord: coord) {
                        var cx = Int32(coord.x)
                        var cy = Int32(coord.y)
                        tileData.append(Data(bytes: &cx, count: 4))
                        tileData.append(Data(bytes: &cy, count: 4))
                        var len = Int32(raw.count)
                        tileData.append(Data(bytes: &len, count: 4))
                        tileData.append(raw)
                    }
                }
            }

            if !tileData.isEmpty {
                fileWrappers["\(layerId).bin"] = FileWrapper(regularFileWithContents: tileData)
            }
        }

        let manifest = PCProManifest(
            version: 1,
            width: document.width,
            height: document.height,
            layers: layerMetas
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let manifestData = try encoder.encode(manifest)
        fileWrappers["manifest.json"] = FileWrapper(regularFileWithContents: manifestData)

        return FileWrapper(directoryWithFileWrappers: fileWrappers)
    }

    /// Deserializes a Document from a macOS FileWrapper package (.pcpro bundle).
    public func deserialize(wrapper: FileWrapper) throws -> Document {
        guard let files = wrapper.fileWrappers,
              let manifestWrapper = files["manifest.json"],
              let manifestData = manifestWrapper.regularFileContents else {
            throw NSError(domain: "PCProDocument", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid .pcpro bundle: manifest.json missing"])
        }

        let manifest = try JSONDecoder().decode(PCProManifest.self, from: manifestData)
        let doc = try Document(canvasSize: CGSize(width: manifest.width, height: manifest.height))

        let canvasSize = CGSize(width: manifest.width, height: manifest.height)

        for meta in manifest.layers {
            let blend = BlendMode(rawValue: meta.blendMode) ?? .normal

            if meta.type == "text" {
                let textLayer = TextLayer(
                    name: meta.name,
                    text: meta.textContent ?? "",
                    fontName: meta.fontName ?? "SF Mono",
                    fontSize: CGFloat(meta.fontSize ?? 12.0),
                    canvasSize: canvasSize,
                    isVisible: meta.isVisible,
                    opacity: meta.opacity,
                    blendMode: blend,
                    lockAlpha: meta.lockAlpha
                )
                doc.addLayer(textLayer)
            } else {
                let bitmapLayer = BitmapLayer(
                    name: meta.name,
                    canvasSize: canvasSize,
                    isVisible: meta.isVisible,
                    opacity: meta.opacity,
                    blendMode: blend,
                    lockAlpha: meta.lockAlpha
                )

                // Load tile data if present
                if let tileWrapper = files["\(meta.id).bin"],
                   let tileData = tileWrapper.regularFileContents {
                    loadTiles(into: bitmapLayer.tileGrid, from: tileData)
                }

                doc.addLayer(bitmapLayer)
            }
        }

        // Remove the default initial template layer
        if doc.layers.count > manifest.layers.count {
            try doc.deleteLayer(at: 0)
        }

        return doc
    }

    private func loadTiles(into grid: SparseTileGrid, from data: Data) {
        var offset = 0
        let total = data.count

        while offset + 12 <= total {
            let cx = Int32(bitPattern: UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24))
            let cy = Int32(bitPattern: UInt32(data[offset + 4]) | (UInt32(data[offset + 5]) << 8) | (UInt32(data[offset + 6]) << 16) | (UInt32(data[offset + 7]) << 24))
            let len = Int(UInt32(data[offset + 8]) | (UInt32(data[offset + 9]) << 8) | (UInt32(data[offset + 10]) << 16) | (UInt32(data[offset + 11]) << 24))
            offset += 12

            if offset + len <= total {
                let payload = data.subdata(in: offset..<(offset + len))
                grid.loadTileData(coord: TileCoord(x: Int(cx), y: Int(cy)), data: payload)
                offset += len
            } else {
                break
            }
        }
    }
}
