import CoreGraphics
import Foundation

// MARK: - SparseMaskGrid

/// 512x512 tiled 1-channel 8-bit alpha mask representation.
/// Matches SparseTileGrid architecture while consuming only 256 KB per allocated tile (1/4 of RGBA8).
public final class SparseMaskGrid: @unchecked Sendable {
    public static let tileSize: Int = 512
    public static let bytesPerTile: Int = 512 * 512 // 256 KB

    public let canvasSize: CGSize
    public let gridColumns: Int
    public let gridRows: Int

    private let lock = NSLock()
    private var tiles: [TileCoord: [UInt8]] = [:]

    public init(canvasSize: CGSize) {
        self.canvasSize = canvasSize
        self.gridColumns = max(1, Int(ceil(canvasSize.width / CGFloat(Self.tileSize))))
        self.gridRows = max(1, Int(ceil(canvasSize.height / CGFloat(Self.tileSize))))
    }

    public var allocatedTileCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return tiles.count
    }

    public var memoryUsageBytes: Int {
        allocatedTileCount * Self.bytesPerTile
    }

    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tiles.isEmpty
    }

    public func isTileAllocated(at coord: TileCoord) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tiles[coord] != nil
    }

    public func getTile(at coord: TileCoord) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        return tiles[coord]
    }

    public func getOrCreateTile(at coord: TileCoord) -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        if let existing = tiles[coord] {
            return existing
        }
        let newTile = [UInt8](repeating: 0, count: Self.bytesPerTile)
        tiles[coord] = newTile
        return newTile
    }

    public func setTile(at coord: TileCoord, data: [UInt8]) {
        guard data.count == Self.bytesPerTile else { return }
        lock.lock()
        defer { lock.unlock() }
        tiles[coord] = data
    }

    public func removeTile(at coord: TileCoord) {
        lock.lock()
        defer { lock.unlock() }
        tiles.removeValue(forKey: coord)
    }

    public func removeAllTiles() {
        lock.lock()
        defer { lock.unlock() }
        tiles.removeAll()
    }

    public func allTiles() -> [TileCoord: [UInt8]] {
        lock.lock()
        defer { lock.unlock() }
        return tiles
    }

    public func allAllocatedCoordinates() -> [TileCoord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tiles.keys)
    }

    public func alphaAt(x: Int, y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < Int(canvasSize.width), y < Int(canvasSize.height) else {
            return 0
        }
        let coord = TileCoord(x: x / Self.tileSize, y: y / Self.tileSize)
        lock.lock()
        guard let tile = tiles[coord] else {
            lock.unlock()
            return 0
        }
        let localX = x % Self.tileSize
        let localY = y % Self.tileSize
        let val = tile[localY * Self.tileSize + localX]
        lock.unlock()
        return val
    }

    public func setAlpha(x: Int, y: Int, value: UInt8) {
        guard x >= 0, y >= 0, x < Int(canvasSize.width), y < Int(canvasSize.height) else { return }
        let coord = TileCoord(x: x / Self.tileSize, y: y / Self.tileSize)
        let localX = x % Self.tileSize
        let localY = y % Self.tileSize
        let index = localY * Self.tileSize + localX

        lock.lock()
        defer { lock.unlock() }
        if var tile = tiles[coord] {
            tile[index] = value
            tiles[coord] = tile
        } else if value > 0 {
            var newTile = [UInt8](repeating: 0, count: Self.bytesPerTile)
            newTile[index] = value
            tiles[coord] = newTile
        }
    }

    public func duplicate() -> SparseMaskGrid {
        let copy = SparseMaskGrid(canvasSize: self.canvasSize)
        lock.lock()
        copy.tiles = self.tiles
        lock.unlock()
        return copy
    }
}

// MARK: - SelectionMask

/// Manages selection state, bounds calculations, boolean mask algebra, and marching ants contour path generation.
public final class SelectionMask: @unchecked Sendable {
    public private(set) var canvasSize: CGSize
    public let maskGrid: SparseMaskGrid
    private let lock = NSLock()

    public init(canvasSize: CGSize) {
        self.canvasSize = canvasSize
        self.maskGrid = SparseMaskGrid(canvasSize: canvasSize)
    }

    public var hasActiveSelection: Bool {
        !maskGrid.isEmpty
    }

    public var isEmpty: Bool {
        maskGrid.isEmpty
    }

    /// Returns the minimal bounding box enclosing all non-zero mask pixels.
    public var selectionBounds: CGRect? {
        lock.lock()
        defer { lock.unlock() }
        guard !maskGrid.isEmpty else { return nil }

        var minX = Int.max
        var minY = Int.max
        var maxX = Int.min
        var maxY = Int.min

        let tileSize = SparseMaskGrid.tileSize
        for (coord, tile) in maskGrid.allTiles() {
            for ly in 0..<tileSize {
                let rowOffset = ly * tileSize
                for lx in 0..<tileSize {
                    if tile[rowOffset + lx] > 0 {
                        let gx = coord.x * tileSize + lx
                        let gy = coord.y * tileSize + ly
                        if gx < minX { minX = gx }
                        if gy < minY { minY = gy }
                        if gx > maxX { maxX = gx }
                        if gy > maxY { maxY = gy }
                    }
                }
            }
        }

        guard minX <= maxX && minY <= maxY else { return nil }
        return CGRect(
            x: minX,
            y: minY,
            width: (maxX - minX + 1),
            height: (maxY - minY + 1)
        )
    }

    public func contains(x: Int, y: Int) -> Bool {
        maskGrid.alphaAt(x: x, y: y) >= 128
    }

    public func alphaAt(x: Int, y: Int) -> UInt8 {
        maskGrid.alphaAt(x: x, y: y)
    }

    public func setAlpha(x: Int, y: Int, value: UInt8) {
        maskGrid.setAlpha(x: x, y: y, value: value)
    }

    public func deselect() {
        maskGrid.removeAllTiles()
    }

    public func selectAll() {
        let solidTile = [UInt8](repeating: 255, count: SparseMaskGrid.bytesPerTile)
        for ty in 0..<maskGrid.gridRows {
            for tx in 0..<maskGrid.gridColumns {
                maskGrid.setTile(at: TileCoord(x: tx, y: ty), data: solidTile)
            }
        }
    }

    public func invert() {
        let solidTile = [UInt8](repeating: 255, count: SparseMaskGrid.bytesPerTile)

        for ty in 0..<maskGrid.gridRows {
            for tx in 0..<maskGrid.gridColumns {
                let coord = TileCoord(x: tx, y: ty)
                if var tile = maskGrid.getTile(at: coord) {
                    var allZero = true
                    for i in 0..<tile.count {
                        tile[i] = 255 - tile[i]
                        if tile[i] > 0 { allZero = false }
                    }
                    if allZero {
                        maskGrid.removeTile(at: coord)
                    } else {
                        maskGrid.setTile(at: coord, data: tile)
                    }
                } else {
                    // Unallocated tile (was 0) becomes 255
                    maskGrid.setTile(at: coord, data: solidTile)
                }
            }
        }
    }

    public func duplicate() -> SelectionMask {
        let copy = SelectionMask(canvasSize: self.canvasSize)
        for (coord, tile) in self.maskGrid.allTiles() {
            copy.maskGrid.setTile(at: coord, data: tile)
        }
        return copy
    }

    // MARK: - Marching Squares Contour Path Generation

    /// Generates vector marching ants iso-contour paths at the specified threshold (default 128)
    /// using Marching Squares cell tracing and Ramer-Douglas-Peucker (RDP) polyline simplification.
    public func marchingSquaresContourPath(threshold: UInt8 = 128, rdpEpsilon: CGFloat = 0.5) -> CGPath {
        guard !maskGrid.isEmpty, let bounds = selectionBounds else {
            return CGMutablePath()
        }

        let minX = max(0, Int(floor(bounds.minX)) - 1)
        let minY = max(0, Int(floor(bounds.minY)) - 1)
        let maxX = min(Int(canvasSize.width) - 1, Int(ceil(bounds.maxX)) + 1)
        let maxY = min(Int(canvasSize.height) - 1, Int(ceil(bounds.maxY)) + 1)

        guard minX < maxX && minY < maxY else {
            return CGMutablePath()
        }

        struct LineSegment {
            let p1: CGPoint
            let p2: CGPoint
        }

        var segments: [LineSegment] = []
        let T = Float(threshold)

        for y in minY..<maxY {
            for x in minX..<maxX {
                let v0 = Float(maskGrid.alphaAt(x: x, y: y))
                let v1 = Float(maskGrid.alphaAt(x: x + 1, y: y))
                let v2 = Float(maskGrid.alphaAt(x: x + 1, y: y + 1))
                let v3 = Float(maskGrid.alphaAt(x: x, y: y + 1))

                let b0 = v0 >= T ? 1 : 0
                let b1 = v1 >= T ? 2 : 0
                let b2 = v2 >= T ? 4 : 0
                let b3 = v3 >= T ? 8 : 0
                let caseIndex = b0 | b1 | b2 | b3

                if caseIndex == 0 || caseIndex == 15 {
                    continue
                }

                // Interpolated edge points
                let topFraction: Float = (v1 - v0).magnitude > 0.001 ? (T - v0) / (v1 - v0) : 0.5
                let rightFraction: Float = (v2 - v1).magnitude > 0.001 ? (T - v1) / (v2 - v1) : 0.5
                let bottomFraction: Float = (v2 - v3).magnitude > 0.001 ? (T - v3) / (v2 - v3) : 0.5
                let leftFraction: Float = (v3 - v0).magnitude > 0.001 ? (T - v0) / (v3 - v0) : 0.5

                let topPt = CGPoint(
                    x: CGFloat(x) + CGFloat(topFraction),
                    y: CGFloat(y)
                )
                let rightPt = CGPoint(
                    x: CGFloat(x + 1),
                    y: CGFloat(y) + CGFloat(rightFraction)
                )
                let bottomPt = CGPoint(
                    x: CGFloat(x) + CGFloat(bottomFraction),
                    y: CGFloat(y + 1)
                )
                let leftPt = CGPoint(
                    x: CGFloat(x),
                    y: CGFloat(y) + CGFloat(leftFraction)
                )

                switch caseIndex {
                case 1: // v0 inside
                    segments.append(LineSegment(p1: leftPt, p2: topPt))
                case 2: // v1 inside
                    segments.append(LineSegment(p1: topPt, p2: rightPt))
                case 3: // v0, v1 inside
                    segments.append(LineSegment(p1: leftPt, p2: rightPt))
                case 4: // v2 inside
                    segments.append(LineSegment(p1: rightPt, p2: bottomPt))
                case 5: // v0, v2 inside (saddle point)
                    let center = (v0 + v1 + v2 + v3) * 0.25
                    if center >= T {
                        segments.append(LineSegment(p1: leftPt, p2: topPt))
                        segments.append(LineSegment(p1: rightPt, p2: bottomPt))
                    } else {
                        segments.append(LineSegment(p1: leftPt, p2: bottomPt))
                        segments.append(LineSegment(p1: topPt, p2: rightPt))
                    }
                case 6: // v1, v2 inside
                    segments.append(LineSegment(p1: topPt, p2: bottomPt))
                case 7: // v0, v1, v2 inside
                    segments.append(LineSegment(p1: leftPt, p2: bottomPt))
                case 8: // v3 inside
                    segments.append(LineSegment(p1: bottomPt, p2: leftPt))
                case 9: // v0, v3 inside
                    segments.append(LineSegment(p1: bottomPt, p2: topPt))
                case 10: // v1, v3 inside (saddle point)
                    let center = (v0 + v1 + v2 + v3) * 0.25
                    if center >= T {
                        segments.append(LineSegment(p1: topPt, p2: rightPt))
                        segments.append(LineSegment(p1: bottomPt, p2: leftPt))
                    } else {
                        segments.append(LineSegment(p1: topPt, p2: leftPt))
                        segments.append(LineSegment(p1: bottomPt, p2: rightPt))
                    }
                case 11: // v0, v1, v3 inside
                    segments.append(LineSegment(p1: bottomPt, p2: rightPt))
                case 12: // v2, v3 inside
                    segments.append(LineSegment(p1: rightPt, p2: leftPt))
                case 13: // v0, v2, v3 inside
                    segments.append(LineSegment(p1: rightPt, p2: topPt))
                case 14: // v1, v2, v3 inside
                    segments.append(LineSegment(p1: topPt, p2: leftPt))
                default:
                    break
                }
            }
        }

        guard !segments.isEmpty else {
            return CGMutablePath()
        }

        // Stitch segments into closed loops
        let loops = Self.stitchSegmentsIntoLoops(segments)

        // Simplify loops with Ramer-Douglas-Peucker and build CGPath
        let path = CGMutablePath()
        for loop in loops {
            guard loop.count >= 3 else { continue }
            let simplified = Self.simplifyRDP(points: loop, epsilon: rdpEpsilon)
            guard simplified.count >= 3 else { continue }

            path.move(to: simplified[0])
            for i in 1..<simplified.count {
                path.addLine(to: simplified[i])
            }
            path.closeSubpath()
        }

        return path
    }

    private static func stitchSegmentsIntoLoops(_ segments: [Any]) -> [[CGPoint]] {
        // Concrete LineSegment unpacking
        struct Segment {
            let p1: CGPoint
            let p2: CGPoint
        }
        var segList: [Segment] = []
        for s in segments {
            if let mirror = Mirror(reflecting: s).children.first(where: { $0.label == "p1" })?.value as? CGPoint,
               let p2 = Mirror(reflecting: s).children.first(where: { $0.label == "p2" })?.value as? CGPoint {
                segList.append(Segment(p1: mirror, p2: p2))
            }
        }

        var loops: [[CGPoint]] = []
        var remaining = segList
        let tolerance: CGFloat = 0.05

        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            hypot(a.x - b.x, a.y - b.y)
        }

        while !remaining.isEmpty {
            let first = remaining.removeFirst()
            var currentLoop = [first.p1, first.p2]

            var found = true
            while found && !remaining.isEmpty {
                found = false
                let end = currentLoop.last!
                let start = currentLoop.first!

                // Check if loop is already closed
                if currentLoop.count > 2 && dist(end, start) < tolerance {
                    break
                }

                for i in 0..<remaining.count {
                    let seg = remaining[i]
                    if dist(end, seg.p1) < tolerance {
                        currentLoop.append(seg.p2)
                        remaining.remove(at: i)
                        found = true
                        break
                    } else if dist(end, seg.p2) < tolerance {
                        currentLoop.append(seg.p1)
                        remaining.remove(at: i)
                        found = true
                        break
                    }
                }
            }

            if currentLoop.count >= 3 {
                loops.append(currentLoop)
            }
        }

        return loops
    }

    private static func simplifyRDP(points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        var maxDist: CGFloat = 0.0
        var maxIndex = 0

        let start = points.first!
        let end = points.last!

        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(point: points[i], lineStart: start, lineEnd: end)
            if d > maxDist {
                maxDist = d
                maxIndex = i
            }
        }

        if maxDist > epsilon {
            let left = simplifyRDP(points: Array(points[0...maxIndex]), epsilon: epsilon)
            let right = simplifyRDP(points: Array(points[maxIndex..<points.count]), epsilon: epsilon)
            return left.dropLast() + right
        } else {
            return [start, end]
        }
    }

    private static func perpendicularDistance(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 0.0001 {
            return hypot(point.x - lineStart.x, point.y - lineStart.y)
        }
        let t = max(0.0, min(1.0, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lenSq))
        let projX = lineStart.x + t * dx
        let projY = lineStart.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }
}
