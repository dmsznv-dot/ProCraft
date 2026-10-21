#if canImport(XCTest)
import XCTest
#endif
@testable import PixelCraftEngine

final class TransformAndLiquifyTests: XCTestCase, @unchecked Sendable {

    func testAffineTransformMatrix() throws {
        var state = TransformState()
        state.translation = CGPoint(x: 100, y: 50)
        state.scale = CGSize(width: 2.0, height: 2.0)
        state.rotation = .pi / 2.0
        state.pivot = CGPoint(x: 10, y: 10)

        let fwd = state.forwardMatrix()
        let inv = state.inverseMatrix()

        XCTAssertNotNil(inv)

        let testPt = CGPoint(x: 20, y: 30)
        let transformed = testPt.applying(fwd)
        let back = transformed.applying(inv!)

        XCTAssertEqual(back.x, testPt.x, accuracy: 1e-4)
        XCTAssertEqual(back.y, testPt.y, accuracy: 1e-4)
    }

    func testBicubicInterpolationAccuracy() throws {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 100, height: 100))
        // Set a 2x2 white square
        grid.setPixel(x: 10, y: 10, color: (255, 255, 255, 255))
        grid.setPixel(x: 11, y: 10, color: (255, 255, 255, 255))
        grid.setPixel(x: 10, y: 11, color: (255, 255, 255, 255))
        grid.setPixel(x: 11, y: 11, color: (255, 255, 255, 255))

        let engine = TransformEngine()
        let sampleCenter = engine.sample(grid: grid, point: CGPoint(x: 11.0, y: 11.0), mode: .bicubic)
        XCTAssertGreaterThan(sampleCenter.r, 200)
        XCTAssertEqual(sampleCenter.a, 255)

        let sampleFar = engine.sample(grid: grid, point: CGPoint(x: 50.0, y: 50.0), mode: .bicubic)
        XCTAssertEqual(sampleFar.a, 0)
    }

    func testPerspectiveHomographySquareToQuad() throws {
        let quad = PerspectiveQuad(
            topLeft: CGPoint(x: 10, y: 10),
            topRight: CGPoint(x: 90, y: 15),
            bottomRight: CGPoint(x: 80, y: 85),
            bottomLeft: CGPoint(x: 20, y: 80)
        )

        let h = PerspectiveHomography.squareToQuad(quad)
        XCTAssertNotNil(h)

        let tl = h?.map(point: CGPoint(x: 0, y: 0))
        let br = h?.map(point: CGPoint(x: 1, y: 1))

        XCTAssertNotNil(tl)
        XCTAssertNotNil(br)
        XCTAssertEqual(tl!.x, quad.topLeft.x, accuracy: 1e-3)
        XCTAssertEqual(tl!.y, quad.topLeft.y, accuracy: 1e-3)
        XCTAssertEqual(br!.x, quad.bottomRight.x, accuracy: 1e-3)
        XCTAssertEqual(br!.y, quad.bottomRight.y, accuracy: 1e-3)
    }

    func testWarpMeshEvaluation() throws {
        let mesh = WarpMesh(rows: 3, cols: 3, rect: CGRect(x: 0, y: 0, width: 100, height: 100))
        let center = mesh.evaluate(u: 0.5, v: 0.5)

        XCTAssertEqual(center.x, 50.0, accuracy: 1e-3)
        XCTAssertEqual(center.y, 50.0, accuracy: 1e-3)

        let corner = mesh.evaluate(u: 1.0, v: 1.0)
        XCTAssertEqual(corner.x, 100.0, accuracy: 1e-3)
        XCTAssertEqual(corner.y, 100.0, accuracy: 1e-3)
    }

    func testPixelateFilterSquareAndHexagonal() throws {
        let grid = SparseTileGrid(canvasSize: CGSize(width: 64, height: 64))
        // Fill 16x16 with red
        for y in 0..<16 {
            for x in 0..<16 {
                grid.setPixel(x: x, y: y, color: (255, 0, 0, 255))
            }
        }

        let filter = PixelateFilter()
        let pixelatedSq = filter.apply(grid: grid, blockSize: 8, shape: .square, sampling: .average)
        let sample = pixelatedSq.getPixel(x: 4, y: 4)
        XCTAssertEqual(sample.r, 255)
        XCTAssertEqual(sample.g, 0)
        XCTAssertEqual(sample.b, 0)
        XCTAssertEqual(sample.a, 255)

        let pixelatedHex = filter.apply(grid: grid, blockSize: 8, shape: .hexagonal, sampling: .center)
        let sampleHex = pixelatedHex.getPixel(x: 4, y: 4)
        XCTAssertEqual(sampleHex.r, 255)
        XCTAssertEqual(sampleHex.a, 255)
    }

    func testLiquifyDisplacementMapAndRender() throws {
        let engine = LiquifyEngine(width: 64, height: 64)
        let params = LiquifyBrushParams(size: 32, pressure: 0.8)

        // Apply push rightwards at center
        engine.applyBrush(mode: .push, center: CGPoint(x: 32, y: 32), delta: CGPoint(x: 10, y: 0), params: params)

        let idx = 32 * 64 + 32
        let disp = engine.displacementMap[idx]
        XCTAssertGreaterThan(disp.x, 0.0)

        // Apply reconstruct
        engine.applyBrush(mode: .reconstruct, center: CGPoint(x: 32, y: 32), delta: .zero, params: params)
        let dispReconstructed = engine.displacementMap[idx]
        XCTAssertLessThan(dispReconstructed.x, disp.x)

        // Test render output
        let src = SparseTileGrid(canvasSize: CGSize(width: 64, height: 64))
        src.setPixel(x: 32, y: 32, color: (0, 255, 0, 255))
        let rendered = engine.render(source: src)
        XCTAssertNotNil(rendered)
    }
}
