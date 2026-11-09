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

/// Backing storage for one 512x512 tile.
///
/// The texture is created *on top of* a shared `MTLBuffer` (linear texture), so on Apple Silicon
/// unified memory the CPU and the GPU see the very same bytes. Pixel reads/writes are plain memory
/// accesses through `pixels` instead of one `MTLTexture.replace/getBytes` call per pixel, which was
/// the main source of lag in every tool and filter.
final class TileStorage: @unchecked Sendable {
    let buffer: MTLBuffer
    let texture: MTLTexture
    let pixels: UnsafeMutablePointer<UInt8>

    init(device: MTLDevice) {
        let tileSize = SparseTileGrid.tileSize
        let bytesPerRow = tileSize * SparseTileGrid.bytesPerPixel
        guard let buffer = device.makeBuffer(length: SparseTileGrid.bytesPerTile, options: .storageModeShared) else {
            fatalError("Failed to allocate 512x512 tile buffer.")
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: tileSize,
            height: tileSize,
            mipmapped: false
        )
        // Tiles are only sampled by the renderer; all writes happen on the CPU through `pixels`.
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let texture = buffer.makeTexture(descriptor: desc, offset: 0, bytesPerRow: bytesPerRow) else {
            fatalError("Failed to create linear tile texture from buffer.")
        }
        self.buffer = buffer
        self.texture = texture
        self.pixels = buffer.contents().bindMemory(to: UInt8.self, capacity: SparseTileGrid.bytesPerTile)
        memset(self.pixels, 0, SparseTileGrid.bytesPerTile)
    }
}

/// A sparse 512x512 tile grid supporting canvases up to 8K (8192x4320 px) with minimal memory footprint.
/// Unallocated tiles consume 0 bytes of memory.
public final class SparseTileGrid: @unchecked Sendable {
    public static let tileSize: Int = 512
    public static let bytesPerPixel: Int = 4
    public static let bytesPerTile: Int = 512 * 512 * 4 // 1 MB

    /// Canvas geometry. Mutable only through `copyFrom(_:)`, which adopts the source grid's size
    /// (needed so crop / canvas resize actually resize every layer).
    public private(set) var canvasSize: CGSize
    public private(set) var gridColumns: Int
    public private(set) var gridRows: Int
    public let device: MTLDevice

    private var canvasWidth: Int
    private var canvasHeight: Int

    private let lock = NSLock()
    private var tiles: [TileCoord: TileStorage] = [:]
    public private(set) var dirtyTiles: Set<TileCoord> = []

    public init(canvasSize: CGSize, device: MTLDevice? = nil) {
        self.canvasSize = canvasSize
        self.canvasWidth = Int(canvasSize.width)
        self.canvasHeight = Int(canvasSize.height)
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
        return tiles[coord]?.texture
    }

    public func getOrCreateTile(at coord: TileCoord) -> MTLTexture {
        lock.lock()
        defer { lock.unlock() }
        return storageLocked(at: coord, create: true)!.texture
    }

    /// Must be called with `lock` held.
    private func storageLocked(at coord: TileCoord, create: Bool) -> TileStorage? {
        if let existing = tiles[coord] {
            return existing
        }
        guard create else { return nil }
        let storage = TileStorage(device: device)
        tiles[coord] = storage
        dirtyTiles.insert(coord)
        return storage
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
        lock.lock()
        defer { lock.unlock() }
        guard x >= 0, y >= 0, x < canvasWidth, y < canvasHeight else {
            return SIMD4<UInt8>(0, 0, 0, 0)
        }

        let coord = TileCoord(x: x / Self.tileSize, y: y / Self.tileSize)
        guard let storage = tiles[coord] else {
            return SIMD4<UInt8>(0, 0, 0, 0)
        }
        let offset = ((y % Self.tileSize) * Self.tileSize + (x % Self.tileSize)) * 4
        let p = storage.pixels
        return SIMD4<UInt8>(p[offset], p[offset + 1], p[offset + 2], p[offset + 3])
    }

    public func writePixel(x: Int, y: Int, color: SIMD4<UInt8>) {
        lock.lock()
        defer { lock.unlock() }
        guard x >= 0, y >= 0, x < canvasWidth, y < canvasHeight else { return }

        let coord = TileCoord(x: x / Self.tileSize, y: y / Self.tileSize)
        // Writing a fully transparent pixel into an unallocated tile is a no-op (tile is already 0).
        if color.w == 0 && color.x == 0 && color.y == 0 && color.z == 0 && tiles[coord] == nil {
            return
        }
        let storage = storageLocked(at: coord, create: true)!
        let offset = ((y % Self.tileSize) * Self.tileSize + (x % Self.tileSize)) * 4
        let p = storage.pixels
        p[offset] = color.x
        p[offset + 1] = color.y
        p[offset + 2] = color.z
        p[offset + 3] = color.w
        dirtyTiles.insert(coord)
    }

    // MARK: - Raw Buffer & Undo Operations

    public func extractTileData(coord: TileCoord) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let storage = tiles[coord] else { return nil }
        return Data(bytes: storage.pixels, count: Self.bytesPerTile)
    }

    public func loadTileData(coord: TileCoord, data: Data) {
        guard data.count == Self.bytesPerTile else { return }
        lock.lock()
        defer { lock.unlock() }
        let storage = storageLocked(at: coord, create: true)!
        data.withUnsafeBytes { rawBuffer in
            if let base = rawBuffer.baseAddress {
                memcpy(storage.pixels, base, Self.bytesPerTile)
            }
        }
        dirtyTiles.insert(coord)
    }

    /// Copies a full 512x512 RGBA tile straight from a byte array (no intermediate `Data`).
    public func writeTileBytes(coord: TileCoord, bytes: [UInt8]) {
        guard bytes.count == Self.bytesPerTile else { return }
        lock.lock()
        defer { lock.unlock() }
        let storage = storageLocked(at: coord, create: true)!
        bytes.withUnsafeBytes { rawBuffer in
            if let base = rawBuffer.baseAddress {
                memcpy(storage.pixels, base, Self.bytesPerTile)
            }
        }
        dirtyTiles.insert(coord)
    }

    /// Copies a rectangle of RGBA8 rows into one tile (local tile coordinates), allocating it if needed.
    public func writeRegion(
        coord: TileCoord,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        from source: UnsafeRawPointer,
        sourceBytesPerRow: Int
    ) {
        guard x >= 0, y >= 0, width > 0, height > 0,
              x + width <= Self.tileSize, y + height <= Self.tileSize else { return }
        lock.lock()
        defer { lock.unlock() }
        let storage = storageLocked(at: coord, create: true)!
        for row in 0..<height {
            let dst = storage.pixels + ((y + row) * Self.tileSize + x) * 4
            memcpy(dst, source + row * sourceBytesPerRow, width * 4)
        }
        dirtyTiles.insert(coord)
    }

    /// Reads a full 512x512 RGBA tile into a byte array, or `nil` if the tile is not allocated.
    public func readTileBytes(coord: TileCoord) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        guard let storage = tiles[coord] else { return nil }
        return Array(UnsafeBufferPointer(start: storage.pixels, count: Self.bytesPerTile))
    }

    // MARK: - Bulk Canvas Access

    /// Returns the whole canvas as a tightly packed RGBA8 buffer (width * height * 4 bytes, row-major, top-left origin).
    public func readRGBA() -> [UInt8] {
        lock.lock()
        let w = canvasWidth
        let h = canvasHeight
        let snapshot = tiles
        lock.unlock()

        var out = [UInt8](repeating: 0, count: max(0, w * h * 4))
        guard w > 0, h > 0 else { return out }

        out.withUnsafeMutableBufferPointer { dst in
            guard let dstBase = dst.baseAddress else { return }
            for (coord, storage) in snapshot {
                let originX = coord.x * Self.tileSize
                let originY = coord.y * Self.tileSize
                let copyW = min(Self.tileSize, w - originX)
                let copyH = min(Self.tileSize, h - originY)
                guard copyW > 0, copyH > 0 else { continue }
                for ly in 0..<copyH {
                    let src = storage.pixels + ly * Self.tileSize * 4
                    let dstRow = dstBase + ((originY + ly) * w + originX) * 4
                    memcpy(dstRow, src, copyW * 4)
                }
            }
        }
        return out
    }

    /// Replaces the whole grid content from a tightly packed RGBA8 buffer (width * height * 4 bytes).
    /// Fully transparent tiles are left unallocated to keep the grid sparse.
    public func writeRGBA(_ data: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        let w = canvasWidth
        let h = canvasHeight
        guard w > 0, h > 0, data.count >= w * h * 4 else { return }
        for coord in tiles.keys { dirtyTiles.insert(coord) }
        tiles.removeAll()

        data.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            for ty in 0..<gridRows {
                for tx in 0..<gridColumns {
                    let originX = tx * Self.tileSize
                    let originY = ty * Self.tileSize
                    let copyW = min(Self.tileSize, w - originX)
                    let copyH = min(Self.tileSize, h - originY)
                    guard copyW > 0, copyH > 0 else { continue }

                    // Skip tiles whose alpha is entirely zero.
                    var hasContent = false
                    rowScan: for ly in 0..<copyH {
                        let row = srcBase + ((originY + ly) * w + originX) * 4
                        var i = 3
                        while i < copyW * 4 {
                            if row[i] != 0 { hasContent = true; break rowScan }
                            i += 4
                        }
                    }
                    guard hasContent else { continue }

                    let coord = TileCoord(x: tx, y: ty)
                    let storage = storageLocked(at: coord, create: true)!
                    for ly in 0..<copyH {
                        let row = srcBase + ((originY + ly) * w + originX) * 4
                        memcpy(storage.pixels + ly * Self.tileSize * 4, row, copyW * 4)
                    }
                    dirtyTiles.insert(coord)
                }
            }
        }
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

    /// Exact bounding box of pixels with non-zero alpha (or `nil` if the grid is fully transparent).
    public var opaquePixelBounds: CGRect? {
        lock.lock()
        let snapshot = tiles
        let canvasWidth = self.canvasWidth
        let canvasHeight = self.canvasHeight
        lock.unlock()

        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for (coord, storage) in snapshot {
            let originX = coord.x * Self.tileSize
            let originY = coord.y * Self.tileSize
            let effW = min(Self.tileSize, canvasWidth - originX)
            let effH = min(Self.tileSize, canvasHeight - originY)
            guard effW > 0, effH > 0 else { continue }
            let p = storage.pixels
            for ly in 0..<effH {
                let rowBase = ly * Self.tileSize * 4
                for lx in 0..<effW where p[rowBase + lx * 4 + 3] != 0 {
                    let gx = originX + lx
                    let gy = originY + ly
                    if gx < minX { minX = gx }
                    if gx > maxX { maxX = gx }
                    if gy < minY { minY = gy }
                    if gy > maxY { maxY = gy }
                }
            }
        }
        guard minX <= maxX, minY <= maxY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: - Deep Copy / Clone

    public func copyFrom(_ other: SparseTileGrid) {
        guard other !== self else { return }

        other.lock.lock()
        let sourceTiles = other.tiles
        let sourceSize = other.canvasSize
        other.lock.unlock()

        lock.lock()
        defer { lock.unlock() }
        for coord in tiles.keys { dirtyTiles.insert(coord) }
        tiles.removeAll()

        // Adopt the source geometry so a crop/resize really resizes the layer.
        canvasSize = sourceSize
        canvasWidth = Int(sourceSize.width)
        canvasHeight = Int(sourceSize.height)
        gridColumns = max(1, Int(ceil(sourceSize.width / CGFloat(Self.tileSize))))
        gridRows = max(1, Int(ceil(sourceSize.height / CGFloat(Self.tileSize))))

        for (coord, srcStorage) in sourceTiles {
            guard coord.x < gridColumns, coord.y < gridRows else { continue }
            let dst = storageLocked(at: coord, create: true)!
            memcpy(dst.pixels, srcStorage.pixels, Self.bytesPerTile)
            dirtyTiles.insert(coord)
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
                writeTileBytes(coord: TileCoord(x: tx, y: ty), bytes: tileBytes)
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

