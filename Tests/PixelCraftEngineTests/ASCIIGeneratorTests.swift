#if canImport(XCTest)
import XCTest
#endif
@testable import PixelCraftEngine

final class ASCIIGeneratorTests: XCTestCase, @unchecked Sendable {

    func testStandardCharacterMapping() throws {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 100, height: 100))
        // Top half black, bottom half white
        for y in 0..<50 {
            for x in 0..<100 {
                grid.setPixel(x: x, y: y, color: (0, 0, 0, 255))
            }
        }
        for y in 50..<100 {
            for x in 0..<100 {
                grid.setPixel(x: x, y: y, color: (255, 255, 255, 255))
            }
        }

        let generator = ASCIIGenerator()
        let params = ASCIIParams(gridColumns: 20, gridRows: 10, charSet: .standard, volumeIntensity: 0.0, dithering: false)
        let text = generator.generateText(from: grid, params: params)

        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 10)

        // Top line should be dark (' ')
        XCTAssertEqual(lines[0].first, " ")

        // Bottom line should be bright ('@')
        XCTAssertEqual(lines[9].first, "@")
    }

    func testExtendedUnicodeCharacterSet() throws {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 50, height: 50))
        for y in 0..<50 {
            for x in 0..<50 {
                grid.setPixel(x: x, y: y, color: (255, 255, 255, 255))
            }
        }

        let generator = ASCIIGenerator()
        let params = ASCIIParams(gridColumns: 10, gridRows: 5, charSet: .extendedUnicode, dithering: false)
        let text = generator.generateText(from: grid, params: params)
        XCTAssertTrue(text.contains("█"))
    }

    func testCustomCharacterSet() throws {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 50, height: 50))
        for y in 0..<50 {
            for x in 0..<50 {
                grid.setPixel(x: x, y: y, color: (255, 255, 255, 255))
            }
        }

        let generator = ASCIIGenerator()
        let params = ASCIIParams(gridColumns: 10, gridRows: 5, charSet: .custom("X"), dithering: false)
        let text = generator.generateText(from: grid, params: params)
        XCTAssertTrue(text.contains("X"))
    }

    func testBakeToLayers() throws {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 100, height: 100))
        for y in 0..<100 {
            for x in 0..<100 {
                grid.setPixel(x: x, y: y, color: (200, 200, 200, 255))
            }
        }

        let generator = ASCIIGenerator()
        let params = ASCIIParams(gridColumns: 20, gridRows: 10, charSet: .standard)

        let textLayer = generator.bakeToTextLayer(from: grid, params: params)
        XCTAssertFalse(textLayer.text.isEmpty)

        let bitmapLayer = generator.bakeToBitmapLayer(from: grid, params: params, canvasSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(bitmapLayer.name, "ASCII Art (Raster)")
        XCTAssertNotNil(bitmapLayer.tileGrid)
    }
}
