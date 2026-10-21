#if canImport(XCTest)
import XCTest
#endif
import Metal
@testable import PixelCraftEngine

final class LayerCompositingTests: XCTestCase, @unchecked Sendable {

    func testPolymorphicLayerStackCoexistence() throws {
        let doc = try Document(canvasSize: CGSize(width: 1024, height: 1024))
        
        let bitmap = BitmapLayer(name: "Photo", canvasSize: doc.canvasSize)
        let text = TextLayer(name: "Headline", text: "PixelCraft", canvasSize: doc.canvasSize)
        let adjustment = AdjustmentLayer(name: "Grading", type: .brightnessContrast, canvasSize: doc.canvasSize)
        let effect = EffectLayer(name: "Vignette", type: .vignette, canvasSize: doc.canvasSize)

        doc.addLayer(bitmap)
        doc.addLayer(text)
        doc.addLayer(adjustment)
        doc.addLayer(effect)

        XCTAssertEqual(doc.layers.count, 5) // Initial background + 4 added
        XCTAssertTrue(doc.layers[1] is BitmapLayer)
        XCTAssertTrue(doc.layers[2] is TextLayer)
        XCTAssertTrue(doc.layers[3] is AdjustmentLayer)
        XCTAssertTrue(doc.layers[4] is EffectLayer)
    }

    func testLayerOpacityClampingAndAttribution() {
        let layer = BitmapLayer(name: "Test", canvasSize: CGSize(width: 512, height: 512))
        layer.opacity = 1.5
        XCTAssertEqual(layer.opacity, 1.0)

        layer.opacity = -0.5
        XCTAssertEqual(layer.opacity, 0.0)

        layer.opacity = 0.42
        XCTAssertEqual(layer.opacity, 0.42, accuracy: 0.001)
    }

    func testLayerVisibilityToggling() throws {
        let doc = try Document()
        let l1 = doc.layers[0]
        XCTAssertTrue(l1.isVisible)

        l1.isVisible = false
        XCTAssertFalse(l1.isVisible)
        XCTAssertEqual(doc.visibleLayers.count, 0)

        let l2 = doc.addLayer()
        XCTAssertTrue(l2.isVisible)
        XCTAssertEqual(doc.visibleLayers.count, 1)
        XCTAssertEqual(doc.visibleLayers[0].id, l2.id)
    }

    func testTextLayerRasterizationAndTileStorage() {
        let textLayer = TextLayer(
            name: "Title",
            text: "Hello World",
            fontSize: 64.0,
            position: CGPoint(x: 50, y: 50),
            canvasSize: CGSize(width: 1024, height: 1024)
        )

        // Force rasterize and check bounding box
        XCTAssertFalse(textLayer.bounds.isEmpty)
        XCTAssertGreaterThan(textLayer.tileGrid.allocatedTileCount, 0)
    }

    func testHeadlessMetalOffscreenCompositing() throws {
        let canvasSize = CGSize(width: 512, height: 512)
        let doc = try Document(canvasSize: canvasSize)

        // Bottom layer: solid red (255, 0, 0, 255)
        let redLayer = doc.layers[0]
        redLayer.tileGrid.fillSolid(color: SIMD4<Float>(1, 0, 0, 1))

        // Top layer: solid green (0, 255, 0, 255) with Multiply blend mode
        let greenLayer = doc.addLayer()
        greenLayer.blendMode = .multiply
        greenLayer.tileGrid.fillSolid(color: SIMD4<Float>(0, 1, 0, 1))

        // Render offscreen using CanvasRenderer
        let outputTexture = try CanvasRenderer.shared.renderOffscreen(
            layers: doc.layers,
            canvasSize: canvasSize
        )

        XCTAssertEqual(outputTexture.width, 512)
        XCTAssertEqual(outputTexture.height, 512)

        // Sample center pixel (256, 256): Red * Green in Multiply should be Black (0, 0, 0, 255)
        var pixel = [UInt8](repeating: 0, count: 4)
        outputTexture.getBytes(
            &pixel,
            bytesPerRow: 4,
            from: MTLRegionMake2D(256, 256, 1, 1),
            mipmapLevel: 0
        )

        XCTAssertEqual(pixel[0], 0, "Red channel after Multiply must be 0")
        XCTAssertEqual(pixel[1], 0, "Green channel after Multiply must be 0")
        XCTAssertEqual(pixel[2], 0, "Blue channel after Multiply must be 0")
        XCTAssertEqual(pixel[3], 255, "Alpha must be 255")
    }

    func testHeadlessScreenBlendModeOffscreen() throws {
        let canvasSize = CGSize(width: 512, height: 512)
        let doc = try Document(canvasSize: canvasSize)

        // Bottom layer: solid red (255, 0, 0, 255)
        let redLayer = doc.layers[0]
        redLayer.tileGrid.fillSolid(color: SIMD4<Float>(1, 0, 0, 1))

        // Top layer: solid green (0, 255, 0, 255) with Screen blend mode
        let greenLayer = doc.addLayer()
        greenLayer.blendMode = .screen
        greenLayer.tileGrid.fillSolid(color: SIMD4<Float>(0, 1, 0, 1))

        let outputTexture = try CanvasRenderer.shared.renderOffscreen(
            layers: doc.layers,
            canvasSize: canvasSize
        )

        // Screen of pure red + pure green = pure yellow (255, 255, 0, 255)
        var pixel = [UInt8](repeating: 0, count: 4)
        outputTexture.getBytes(
            &pixel,
            bytesPerRow: 4,
            from: MTLRegionMake2D(256, 256, 1, 1),
            mipmapLevel: 0
        )

        XCTAssertEqual(pixel[0], 255, "Red channel after Screen must be 255")
        XCTAssertEqual(pixel[1], 255, "Green channel after Screen must be 255")
        XCTAssertEqual(pixel[2], 0, "Blue channel after Screen must be 0")
        XCTAssertEqual(pixel[3], 255, "Alpha must be 255")
    }
}
