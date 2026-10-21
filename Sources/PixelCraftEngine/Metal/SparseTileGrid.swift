import Metal
import CoreGraphics
import Foundation
import simd

/// Coordinate identifier for a 512x512 tile in the sparse grid.
public struct TileCoord: Hashable, Equatable, Sendable, Codable {
    public let x: Int // Column index (0 ..< cols)
    public let y: Int // Row index (0 ..< rows)

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public var tileOrigin: CGPoint {
        CGPoint(x: x * 512, y: y * 512)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}

/// A sparse 512x512 tile grid supporting canvases up to 8K (8192x4320 px) with minimal memory footprint.
/// Unallocated tiles consume 0 bytes of memory.
public final class SparseTileGrid: @unchecked Sendable {
    public static let tileSize: Int = 512
    public static let bytesPerPixel: Int = 4
    public static let bytesPerTile: Int = 512 * 512 * 4 // 1 MB

    public let canvasSize: CGSize
    public let gridColumns: Int
    public let gridRows: Int
    public let device: MTLDevice

    private let lock = NSLock()
    private var tiles: [TileCoord: MTLTexture] = [:]
    public private(set) var dirtyTiles: Set<TileCoord> = []

    public init(canvasSize: CGSize, device: MTLDevice? = nil) {
        self.canvasSize = canvasSize
        self.gridColumns = max(1, Int(ceil(canvasSize.width / CGFloat(Self.tileSize))))
        self.gridRows = max(1, Int(ceil(canvasSize.height / CGFloat(Self.tileSize))))
        self.device = device ?? MetalContext.shared.device
    }

    // MARK: - Tile Query & Allocation
    
    public var allocatedTileCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return tiles.count
    }

    public var memoryUsageBytes: Int {
        allocatedTileCount * Self.bytesPerTile
    }
    
    public var isEmpty: Bool {
        allocatedTileCount == 0
    }

    public func isTileAllocated(at coord: TileCoord) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tiles[coord] != nil
    }

    public func getTile(at coord: TileCoord) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        return tiles[coord]
    }

    public func getOrCreateTile(at coord: TileCoord) -> MTLTexture {
        lock.lock()
        defer { lock.unlock() }

        if let existing = tiles[coord] {
            return existing
        }

        let desc = MetalContext.shared.makeTileTextureDescriptor()
        guard let newTexture = device.makeTexture(descriptor: desc) else {
            fatalError("Failed to allocate 512x512 tile texture.")
        }
        tiles[coord] = newTexture
        dirtyTiles.insert(coord)
        return newTexture
    }

    public func allAllocatedCoordinates() -> [TileCoord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tiles.keys)
    }

    public func removeTile(at coord: TileCoord) {
        lock.lock()
        defer { lock.unlock() }
        tiles.removeValue(forKey: coord)
        dirtyTiles.insert(coord)
    }

    public func removeAllTiles() {
        lock.lock()
        defer { lock.unlock() }
        for coord in tiles.keys {
            dirtyTiles.insert(coord)
        }
        tiles.removeAll()
    }

    // MARK: - Dirty Tracking
    
    public func markDirty(coord: TileCoord) {
        lock.lock()
        defer { lock.unlock() }
        dirtyTiles.insert(coord)
    }

    public func markAllDirty() {
        lock.lock()
        defer { lock.unlock() }
        for coord in tiles.keys {
            dirtyTiles.insert(coord)
        }
    }

    public func clearDirty() {
        lock.lock()
        defer { lock.unlock() }
        dirtyTiles.removeAll()
    }

    // MARK: - Pixel Read & Write
    
    public func readPixel(x: Int, y: Int) -> SIMD4<UInt8> {
        guard x >= 0, y >= 0, x < Int(canvasSize.width), y < Int(canvasSize.height) else {
            return SIMD4<UInt8>(0, 0, 0, 0)
        }

        let coord = TileCoord(x: x / Self.tileSize, y: y / Self.tileSize)
        lock.lock()
        guard let texture = tiles[coord] else {
            lock.unlock()
            return SIMD4<UInt8>(0, 0, 0, 0)
        }
        lock.unlock()

        let localX = x % Self.tileSize
        let localY = y % Self.tileSize
        var pixel = SIMD4<UInt8>(repeating: 0)
        texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(localX, localY, 1, 1), mipmapLevel: 0)
        return pixel
    }

    public func writePixel(x: Int, y: Int, color: SIMD4<UInt8>) {
        guard x >= 0, y >= 0, x < Int(canvasSize.width), y < Int(canvasSize.height) else { return }

        let coord = TileCoord(x: x / Self.tileSize, y: y / Self.tileSize)
        let texture = getOrCreateTile(at: coord)
        let localX = x % Self.tileSize
        let localY = y % Self.tileSize
        var pixel = color
        texture.replace(region: MTLRegionMake2D(localX, localY, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)

        lock.lock()
        dirtyTiles.insert(coord)
        lock.unlock()
    }

    // MARK: - Raw Buffer & Undo Operations
    
    public func extractTileData(coord: TileCoord) -> Data? {
        lock.lock()
        guard let texture = tiles[coord] else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        var buffer = [UInt8](repeating: 0, count: Self.bytesPerTile)
        texture.getBytes(&buffer, bytesPerRow: Self.tileSize * Self.bytesPerPixel, from: MTLRegionMake2D(0, 0, Self.tileSize, Self.tileSize), mipmapLevel: 0)
        return Data(buffer)
    }

    public func loadTileData(coord: TileCoord, data: Data) {
        guard data.count == Self.bytesPerTile else { return }
        let texture = getOrCreateTile(at: coord)
        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, Self.tileSize, Self.tileSize),
                    mipmapLevel: 0,
                    withBytes: baseAddress,
                    bytesPerRow: Self.tileSize * Self.bytesPerPixel
                )
            }
        }
        lock.lock()
        dirtyTiles.insert(coord)
        lock.unlock()
    }

    // MARK: - Boundary Geometry Helpers
    
    public func effectiveTileBounds(coord: TileCoord) -> (width: Float, height: Float, maxU: Float, maxV: Float) {
        let originX = Float(coord.x * Self.tileSize)
        let originY = Float(coord.y * Self.tileSize)
        let effW = min(Float(Self.tileSize), Float(canvasSize.width) - originX)
        let effH = min(Float(Self.tileSize), Float(canvasSize.height) - originY)
        return (
            width: max(0, effW),
            height: max(0, effH),
            maxU: max(0, effW) / Float(Self.tileSize),
            maxV: max(0, effH) / Float(Self.tileSize)
        )
    }
    
    public var contentBounds: CGRect {
        lock.lock()
        let coords = Array(tiles.keys)
        lock.unlock()
        
        guard !coords.isEmpty else { return .zero }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        
        for coord in coords {
            let bounds = effectiveTileBounds(coord: coord)
            let tx = CGFloat(coord.x * Self.tileSize)
            let ty = CGFloat(coord.y * Self.tileSize)
            minX = min(minX, tx)
            minY = min(minY, ty)
            maxX = max(maxX, tx + CGFloat(bounds.width))
            maxY = max(maxY, ty + CGFloat(bounds.height))
        }
        
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    // MARK: - Deep Copy / Clone
    
    public func copyFrom(_ other: SparseTileGrid) {
        lock.lock()
        tiles.removeAll()
        dirtyTiles.removeAll()
        lock.unlock()

        let otherCoords = other.allAllocatedCoordinates()
        guard !otherCoords.isEmpty else { return }

        let queue = MetalContext.shared.commandQueue
        if let cmd = queue.makeCommandBuffer(), let blit = cmd.makeBlitCommandEncoder() {
            for coord in otherCoords {
                if let srcTex = other.getTile(at: coord) {
                    let dstTex = getOrCreateTile(at: coord)
                    blit.copy(from: srcTex, to: dstTex)
                }
            }
            blit.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
        } else {
            for coord in otherCoords {
                if let data = other.extractTileData(coord: coord) {
                    loadTileData(coord: coord, data: data)
                }
            }
        }
    }

    public func duplicate() -> SparseTileGrid {
        let copy = SparseTileGrid(canvasSize: self.canvasSize, device: self.device)
        copy.copyFrom(self)
        return copy
    }
    
    // MARK: - Solid Fill
    
    public func fillSolid(color: SIMD4<Float>) {
        let r = UInt8(max(0, min(255, color.x * 255.0)))
        let g = UInt8(max(0, min(255, color.y * 255.0)))
        let b = UInt8(max(0, min(255, color.z * 255.0)))
        let a = UInt8(max(0, min(255, color.w * 255.0)))
        
        var tileBytes = [UInt8](repeating: 0, count: Self.bytesPerTile)
        for i in stride(from: 0, to: Self.bytesPerTile, by: 4) {
            tileBytes[i] = r
            tileBytes[i + 1] = g
            tileBytes[i + 2] = b
            tileBytes[i + 3] = a
        }
        
        for ty in 0..<gridRows {
            for tx in 0..<gridColumns {
                let coord = TileCoord(x: tx, y: ty)
                let texture = getOrCreateTile(at: coord)
                tileBytes.withUnsafeBytes { rawBuffer in
                    if let ptr = rawBuffer.baseAddress {
                        texture.replace(
                            region: MTLRegionMake2D(0, 0, Self.tileSize, Self.tileSize),
                            mipmapLevel: 0,
                            withBytes: ptr,
                            bytesPerRow: Self.tileSize * Self.bytesPerPixel
                        )
                    }
                }
                markDirty(coord: coord)
            }
        }
    }
}

extension SparseTileGrid {
    @inlinable
    public func getPixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let p = readPixel(x: x, y: y)
        return (p.x, p.y, p.z, p.w)
    }

    @inlinable
    public func setPixel(x: Int, y: Int, color: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) {
        writePixel(x: x, y: y, color: SIMD4<UInt8>(color.r, color.g, color.b, color.a))
    }

    @inlinable
    public func clone() -> SparseTileGrid {
        return duplicate()
    }
}

