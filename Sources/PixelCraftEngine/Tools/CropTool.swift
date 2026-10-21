import CoreGraphics
import Foundation

public enum CropAnchor: String, CaseIterable, Sendable, Codable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case center
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    public func contentOffset(oldSize: CGSize, newSize: CGSize) -> (dx: Int, dy: Int) {
        let dw = Int(newSize.width - oldSize.width)
        let dh = Int(newSize.height - oldSize.height)

        let dx: Int
        switch self {
        case .topLeft, .centerLeft, .bottomLeft:
            dx = 0
        case .topCenter, .center, .bottomCenter:
            dx = dw / 2
        case .topRight, .centerRight, .bottomRight:
            dx = dw
        }

        let dy: Int
        switch self {
        case .topLeft, .topCenter, .topRight:
            dy = 0
        case .centerLeft, .center, .centerRight:
            dy = dh / 2
        case .bottomLeft, .bottomCenter, .bottomRight:
            dy = dh
        }

        return (dx, dy)
    }
}

// MARK: - CropUndoCommand

public final class CropUndoCommand: UndoCommand, @unchecked Sendable {
    public let actionName: String = "Crop Canvas"
    public let oldCanvasSize: CGSize
    public let newCanvasSize: CGSize
    public let oldLayerGrids: [UUID: SparseTileGrid]
    public let newLayerGrids: [UUID: SparseTileGrid]

    public init(
        oldSize: CGSize,
        newSize: CGSize,
        oldGrids: [UUID: SparseTileGrid],
        newGrids: [UUID: SparseTileGrid]
    ) {
        self.oldCanvasSize = oldSize
        self.newCanvasSize = newSize
        self.oldLayerGrids = oldGrids
        self.newLayerGrids = newGrids
    }

    public var estimatedMemoryBytes: Int {
        var bytes = 0
        for g in oldLayerGrids.values { bytes += g.memoryUsageBytes }
        for g in newLayerGrids.values { bytes += g.memoryUsageBytes }
        return bytes
    }

    public func undo(in document: Document) {
        document.resizeCanvasDirect(newSize: oldCanvasSize)
        for layer in document.layers {
            if let oldGrid = oldLayerGrids[layer.id] {
                layer.tileGrid.copyFrom(oldGrid)
            }
        }
    }

    public func redo(in document: Document) {
        document.resizeCanvasDirect(newSize: newCanvasSize)
        for layer in document.layers {
            if let newGrid = newLayerGrids[layer.id] {
                layer.tileGrid.copyFrom(newGrid)
            }
        }
    }
}

// MARK: - CropTool

public final class CropTool: DrawingTool, @unchecked Sendable {
    public let toolType: ToolType = .crop

    private var isDragging: Bool = false
    private var startPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero

    public init() {}

    public func mouseDown(at canvasPoint: CGPoint, document: Document) {
        isDragging = true
        startPoint = canvasPoint
        currentPoint = canvasPoint
    }

    public func mouseDragged(to canvasPoint: CGPoint, document: Document) {
        guard isDragging else { return }
        currentPoint = canvasPoint
    }

    public func mouseUp(at canvasPoint: CGPoint, document: Document) {
        guard isDragging else { return }
        currentPoint = canvasPoint
        isDragging = false

        let x = min(startPoint.x, currentPoint.x)
        let y = min(startPoint.y, currentPoint.y)
        let w = abs(currentPoint.x - startPoint.x)
        let h = abs(currentPoint.y - startPoint.y)

        guard w >= 1.0 && h >= 1.0 else { return }
        let cropRect = CGRect(x: x, y: y, width: w, height: h).intersection(document.bounds)
        guard !cropRect.isNull && cropRect.width >= 1.0 && cropRect.height >= 1.0 else { return }

        try? applyCrop(to: cropRect, document: document)
    }

    public func cancel(document: Document) {
        isDragging = false
    }

    // MARK: - Crop Executions

    public func applyCrop(to rect: CGRect, document: Document) throws {
        let newWidth = Int(floor(rect.width))
        let newHeight = Int(floor(rect.height))

        guard newWidth >= Document.minDimension && newHeight >= Document.minDimension else {
            throw DocumentError.invalidDimensions(width: newWidth, height: newHeight)
        }
        guard newWidth <= Document.maxDimensionWidth && newHeight <= Document.maxDimensionHeight else {
            throw DocumentError.canvasExceedsMaximumSize(
                width: newWidth,
                height: newHeight,
                maxWidth: Document.maxDimensionWidth,
                maxHeight: Document.maxDimensionHeight
            )
        }

        let newSize = CGSize(width: newWidth, height: newHeight)
        let shift = (dx: -Int(floor(rect.minX)), dy: -Int(floor(rect.minY)))

        executeResizeAndRemap(newSize: newSize, shift: shift, document: document)
    }

    public func resizeCanvas(newSize: CGSize, anchor: CropAnchor, document: Document) throws {
        let newW = Int(newSize.width)
        let newH = Int(newSize.height)

        guard newW >= Document.minDimension && newH >= Document.minDimension else {
            throw DocumentError.invalidDimensions(width: newW, height: newH)
        }
        guard newW <= Document.maxDimensionWidth && newH <= Document.maxDimensionHeight else {
            throw DocumentError.canvasExceedsMaximumSize(
                width: newW,
                height: newH,
                maxWidth: Document.maxDimensionWidth,
                maxHeight: Document.maxDimensionHeight
            )
        }

        let shift = anchor.contentOffset(oldSize: document.canvasSize, newSize: newSize)
        executeResizeAndRemap(newSize: newSize, shift: shift, document: document)
    }

    private func executeResizeAndRemap(newSize: CGSize, shift: (dx: Int, dy: Int), document: Document) {
        let oldSize = document.canvasSize
        var oldGrids: [UUID: SparseTileGrid] = [:]
        var newGrids: [UUID: SparseTileGrid] = [:]

        for layer in document.layers {
            oldGrids[layer.id] = layer.tileGrid.duplicate()
            let remapped = Self.remapTileGrid(oldGrid: layer.tileGrid, newSize: newSize, shift: shift)
            newGrids[layer.id] = remapped
        }

        // Apply new grids to layers
        document.resizeCanvasDirect(newSize: newSize)
        for layer in document.layers {
            if let newGrid = newGrids[layer.id] {
                layer.tileGrid.copyFrom(newGrid)
            }
        }

        let undoCmd = CropUndoCommand(
            oldSize: oldSize,
            newSize: newSize,
            oldGrids: oldGrids,
            newGrids: newGrids
        )
        document.undoManager.registerCommand(undoCmd)
    }

    // MARK: - Sparse Tile Coordinate Remapping Algorithm

    public static func remapTileGrid(
        oldGrid: SparseTileGrid,
        newSize: CGSize,
        shift: (dx: Int, dy: Int)
    ) -> SparseTileGrid {
        let newGrid = SparseTileGrid(canvasSize: newSize, device: oldGrid.device)
        let tileSize = SparseTileGrid.tileSize
        let dx = shift.dx
        let dy = shift.dy

        // Fast Path: Aligned coordinate shift (zero pixel blit)
        if dx % tileSize == 0 && dy % tileSize == 0 {
            let shiftTilesX = dx / tileSize
            let shiftTilesY = dy / tileSize

            for coord in oldGrid.allAllocatedCoordinates() {
                let targetCoord = TileCoord(x: coord.x + shiftTilesX, y: coord.y + shiftTilesY)
                if targetCoord.x >= 0 && targetCoord.x < newGrid.gridColumns &&
                   targetCoord.y >= 0 && targetCoord.y < newGrid.gridRows {
                    if let data = oldGrid.extractTileData(coord: coord) {
                        newGrid.loadTileData(coord: targetCoord, data: data)
                    }
                }
            }
            return newGrid
        }

        // General Path: Sub-tile pixel shift
        let newW = Int(newSize.width)
        let newH = Int(newSize.height)

        for coord in oldGrid.allAllocatedCoordinates() {
            guard let oldData = oldGrid.extractTileData(coord: coord) else { continue }

            let oldTileOriginX = coord.x * tileSize
            let oldTileOriginY = coord.y * tileSize

            // Old tile rect in new canvas space
            let mappedX = oldTileOriginX + dx
            let mappedY = oldTileOriginY + dy

            // Intersect with new canvas bounds
            let interX0 = max(0, mappedX)
            let interY0 = max(0, mappedY)
            let interX1 = min(newW, mappedX + tileSize)
            let interY1 = min(newH, mappedY + tileSize)

            guard interX0 < interX1 && interY0 < interY1 else {
                continue // Tile is entirely outside new canvas bounds (pruned)
            }

            // Target tiles overlapped
            let targetTx0 = interX0 / tileSize
            let targetTx1 = (interX1 - 1) / tileSize
            let targetTy0 = interY0 / tileSize
            let targetTy1 = (interY1 - 1) / tileSize

            oldData.withUnsafeBytes { oldBytes in
                guard let oldPtr = oldBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

                for ty in targetTy0...targetTy1 {
                    for tx in targetTx0...targetTx1 {
                        let targetCoord = TileCoord(x: tx, y: ty)
                        var targetData = newGrid.extractTileData(coord: targetCoord) ?? Data(repeating: 0, count: SparseTileGrid.bytesPerTile)

                        targetData.withUnsafeMutableBytes { targetBytes in
                            guard let targetPtr = targetBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

                            let subX0 = max(interX0, tx * tileSize)
                            let subX1 = min(interX1, (tx + 1) * tileSize)
                            let subY0 = max(interY0, ty * tileSize)
                            let subY1 = min(interY1, (ty + 1) * tileSize)
                            let copyW = subX1 - subX0

                            for y in subY0..<subY1 {
                                let srcLocalX = subX0 - mappedX
                                let srcLocalY = y - mappedY
                                let dstLocalX = subX0 - tx * tileSize
                                let dstLocalY = y - ty * tileSize

                                let srcOffset = (srcLocalY * tileSize + srcLocalX) * 4
                                let dstOffset = (dstLocalY * tileSize + dstLocalX) * 4

                                memcpy(targetPtr + dstOffset, oldPtr + srcOffset, copyW * 4)
                            }
                        }

                        newGrid.loadTileData(coord: targetCoord, data: targetData)
                    }
                }
            }
        }

        return newGrid
    }
}
