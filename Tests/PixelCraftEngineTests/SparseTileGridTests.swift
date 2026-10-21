#if canImport(XCTest)
import XCTest
#endif
@testable import PixelCraftEngine

final class SparseTileGridTests: XCTestCase, @unchecked Sendable {

    func testSparseTileGridMemoryConservation() {
        let size8K = CGSize(width: 8192, height: 4320)
        let grid = SparseTileGrid(canvasSize: size8K)

        XCTAssertEqual(grid.allocatedTileCount, 0)
        XCTAssertEqual(grid.memoryUsageBytes, 0)
        XCTAssertTrue(grid.isEmpty)

        // Write a single pixel at (4000, 2000)
        grid.writePixel(x: 4000, y: 2000, color: SIMD4<UInt8>(255, 128, 0, 255))

        XCTAssertEqual(grid.allocatedTileCount, 1)
        XCTAssertEqual(grid.memoryUsageBytes, 1048576) // Exactly 1 MB
        XCTAssertFalse(grid.isEmpty)
    }

    func testSparseTileGridBoundaryCalculations() {
        let size8K = CGSize(width: 8192, height: 4320)
        let grid = SparseTileGrid(canvasSize: size8K)

        XCTAssertEqual(grid.gridColumns, 16)
        XCTAssertEqual(grid.gridRows, 9)

        // Test boundary on partial row 8
        let bounds = grid.effectiveTileBounds(coord: TileCoord(x: 15, y: 8))
        XCTAssertEqual(bounds.width, 512.0)
        XCTAssertEqual(bounds.height, 224.0)
        XCTAssertEqual(bounds.maxU, 1.0)
        XCTAssertEqual(bounds.maxV, 224.0 / 512.0, accuracy: 0.0001)
    }

    func testPixelReadWriteFidelity() {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 1920, height: 1080))
        let testColor = SIMD4<UInt8>(255, 128, 64, 255)

        grid.writePixel(x: 1024, y: 768, color: testColor)
        let readColor = grid.readPixel(x: 1024, y: 768)

        XCTAssertEqual(readColor.x, testColor.x)
        XCTAssertEqual(readColor.y, testColor.y)
        XCTAssertEqual(readColor.z, testColor.z)
        XCTAssertEqual(readColor.w, testColor.w)

        // Unwritten pixel returns zero
        let unwritten = grid.readPixel(x: 0, y: 0)
        XCTAssertEqual(unwritten, SIMD4<UInt8>(0, 0, 0, 0))
    }

    func testDirtyTileTracking() {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 1024, height: 1024))
        XCTAssertTrue(grid.dirtyTiles.isEmpty)

        grid.writePixel(x: 10, y: 10, color: SIMD4<UInt8>(100, 100, 100, 255))
        XCTAssertTrue(grid.dirtyTiles.contains(TileCoord(x: 0, y: 0)))

        grid.clearDirty()
        XCTAssertTrue(grid.dirtyTiles.isEmpty)
    }

    func testDeepCopyTileGrid() {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 1024, height: 1024))
        grid.writePixel(x: 100, y: 100, color: SIMD4<UInt8>(200, 50, 25, 255))

        let copy = grid.duplicate()
        XCTAssertEqual(copy.allocatedTileCount, 1)

        let copyPixel = copy.readPixel(x: 100, y: 100)
        XCTAssertEqual(copyPixel, SIMD4<UInt8>(200, 50, 25, 255))

        // Mutate original
        grid.writePixel(x: 100, y: 100, color: SIMD4<UInt8>(0, 0, 0, 255))
        let afterMutateCopyPixel = copy.readPixel(x: 100, y: 100)
        XCTAssertEqual(afterMutateCopyPixel, SIMD4<UInt8>(200, 50, 25, 255), "Deep copy should be unaffected by mutation of original")
    }

    func testExtractAndLoadTileData() {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 512, height: 512))
        grid.writePixel(x: 256, y: 256, color: SIMD4<UInt8>(12, 34, 56, 78))

        let coord = TileCoord(x: 0, y: 0)
        let data = grid.extractTileData(coord: coord)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, SparseTileGrid.bytesPerTile)

        let grid2 = SparseTileGrid(canvasSize: CGSize(width: 512, height: 512))
        grid2.loadTileData(coord: coord, data: data!)

        let readPixel = grid2.readPixel(x: 256, y: 256)
        XCTAssertEqual(readPixel, SIMD4<UInt8>(12, 34, 56, 78))
    }

    func testSolidFill() {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 512, height: 512))
        grid.fillSolid(color: SIMD4<Float>(1.0, 0.0, 0.0, 1.0)) // Red

        XCTAssertEqual(grid.allocatedTileCount, 1)
        let pixel = grid.readPixel(x: 100, y: 100)
        XCTAssertEqual(pixel.x, 255)
        XCTAssertEqual(pixel.y, 0)
        XCTAssertEqual(pixel.z, 0)
        XCTAssertEqual(pixel.w, 255)
    }

    func testContentBounds() {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 2048, height: 2048))
        XCTAssertEqual(grid.contentBounds, .zero)

        grid.writePixel(x: 600, y: 600, color: SIMD4<UInt8>(255, 255, 255, 255))
        // Touches tile (1, 1), which spans [512, 1024) x [512, 1024)
        let bounds = grid.contentBounds
        XCTAssertEqual(bounds.minX, 512.0)
        XCTAssertEqual(bounds.minY, 512.0)
        XCTAssertEqual(bounds.width, 512.0)
        XCTAssertEqual(bounds.height, 512.0)
    }
}
