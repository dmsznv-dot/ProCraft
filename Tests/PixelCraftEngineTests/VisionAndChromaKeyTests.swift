#if canImport(XCTest)
import XCTest
#endif
@testable import PixelCraftEngine

final class VisionAndChromaKeyTests: XCTestCase, @unchecked Sendable {

    func testRGBToCIELABConversion() throws {
        // Pure White: L* should be ~100, a* ~ 0, b* ~ 0
        let whiteLab = LabColor.fromRGB(r: 255, g: 255, b: 255)
        XCTAssertEqual(whiteLab.L, 100.0, accuracy: 1.0)
        XCTAssertEqual(whiteLab.a, 0.0, accuracy: 2.0)
        XCTAssertEqual(whiteLab.b, 0.0, accuracy: 2.0)

        // Pure Black: L* should be 0
        let blackLab = LabColor.fromRGB(r: 0, g: 0, b: 0)
        XCTAssertEqual(blackLab.L, 0.0, accuracy: 0.1)

        // Delta E between white and white is 0
        XCTAssertEqual(whiteLab.deltaE(to: whiteLab), 0.0, accuracy: 1e-4)

        // Delta E between white and black is ~100
        let dist = whiteLab.deltaE(to: blackLab)
        XCTAssertGreaterThan(dist, 90.0)
    }

    func testChromaKeyGreenScreenRemoval() throws {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 32, height: 32))
        // Left half green (0, 255, 0), right half skin tone/red (220, 100, 80)
        for y in 0..<32 {
            for x in 0..<16 {
                grid.setPixel(x: x, y: y, color: (0, 255, 0, 255))
            }
            for x in 16..<32 {
                grid.setPixel(x: x, y: y, color: (220, 100, 80, 255))
            }
        }

        let filter = ChromaKeyFilter()
        let params = ChromaKeyParams(keyColor: (0, 255, 0), tolerance: 30.0, feather: 5.0, spillSuppression: 0.8)
        let keyed = filter.apply(grid: grid, params: params)

        // Green side should be transparent
        let greenSample = keyed.getPixel(x: 5, y: 5)
        XCTAssertEqual(greenSample.a, 0)

        // Subject side should remain opaque
        let subjectSample = keyed.getPixel(x: 25, y: 25)
        XCTAssertEqual(subjectSample.a, 255)
        XCTAssertEqual(subjectSample.r, 220)
    }

    func testChromaKeySpillSuppression() throws {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 10, height: 10))
        // Subject edge with green spill: red=180, green=210, blue=160
        grid.setPixel(x: 5, y: 5, color: (180, 210, 160, 255))

        let filter = ChromaKeyFilter()
        // High tolerance so it doesn't get deleted, but spill suppression kicks in
        let params = ChromaKeyParams(keyColor: (0, 255, 0), tolerance: 5.0, feather: 1.0, spillSuppression: 1.0)
        let processed = filter.apply(grid: grid, params: params)

        let p = processed.getPixel(x: 5, y: 5)
        // Green should be attenuated to match max(r, b) = 180
        XCTAssertLessThanOrEqual(p.g, 185)
        XCTAssertEqual(p.a, 255)
    }

    func testVisionGuidedFilterEdgeRefinement() throws {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 20, height: 20))
        for y in 0..<20 {
            for x in 0..<20 {
                grid.setPixel(x: x, y: y, color: (x < 10 ? 255 : 50, 50, 50, 255))
            }
        }

        // Mock a noisy mask around the boundary (x = 10)
        var mask = [UInt8](repeating: 255, count: 400)
        for y in 0..<20 {
            for x in 10..<20 {
                mask[y * 20 + x] = 50 // Soft edge
            }
        }

        let vision = VisionBackgroundRemoval()
        let refined = vision.applyGuidedEdgeRefinement(mask: mask, source: grid, width: 20, height: 20, radius: 2)
        XCTAssertEqual(refined.count, 400)
    }
}
