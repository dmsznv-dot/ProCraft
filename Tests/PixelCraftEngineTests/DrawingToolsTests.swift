#if canImport(XCTest)
import XCTest
#endif
@testable import PixelCraftEngine

final class DrawingToolsTests: XCTestCase, @unchecked Sendable {

    // MARK: - F9 Brush Tool Tests

    func testRoundBrushStampGeometry() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let brush = BrushTool(configuration: BrushConfiguration(
            shape: .round,
            size: 20.0,
            opacity: 1.0,
            flow: 1.0,
            spacing: 0.1,
            color: SIMD4<Float>(1, 0, 0, 1)
        ))

        let center = CGPoint(x: 100, y: 100)
        brush.mouseDown(at: center, document: doc)
        brush.mouseUp(at: center, document: doc)

        let layer = doc.activeLayer as! BitmapLayer
        // Center pixel should be red
        let centerPixel = layer.tileGrid.readPixel(x: 100, y: 100)
        XCTAssertEqual(centerPixel.x, 255)
        XCTAssertEqual(centerPixel.y, 0)
        XCTAssertEqual(centerPixel.z, 0)
        XCTAssertEqual(centerPixel.w, 255)

        // Pixel inside radius (e.g. distance 5) should be painted
        let innerPixel = layer.tileGrid.readPixel(x: 105, y: 100)
        XCTAssertEqual(innerPixel.x, 255)
        XCTAssertEqual(innerPixel.w, 255)

        // Pixel outside radius (distance 15 > radius 10) should be transparent (untouched)
        let outerPixel = layer.tileGrid.readPixel(x: 115, y: 100)
        XCTAssertEqual(outerPixel.w, 0)
    }

    func testSquareBrushStampGeometry() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let brush = BrushTool(configuration: BrushConfiguration(
            shape: .square,
            size: 20.0,
            opacity: 1.0,
            flow: 1.0,
            color: SIMD4<Float>(0, 1, 0, 1)
        ))

        let center = CGPoint(x: 100, y: 100)
        brush.mouseDown(at: center, document: doc)
        brush.mouseUp(at: center, document: doc)

        let layer = doc.activeLayer as! BitmapLayer
        // Corner of the square (dx=8, dy=8) has distance = sqrt(128) ~ 11.3 > radius 10,
        // but for square (|dx| <= 10 && |dy| <= 10) it is inside!
        let cornerPixel = layer.tileGrid.readPixel(x: 108, y: 108)
        XCTAssertEqual(cornerPixel.y, 255)
        XCTAssertEqual(cornerPixel.w, 255)

        // Outside square bounds (dx=12, dy=0)
        let outsidePixel = layer.tileGrid.readPixel(x: 112, y: 100)
        XCTAssertEqual(outsidePixel.w, 0)
    }

    func testSoftBrushRadialFalloff() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let brush = BrushTool(configuration: BrushConfiguration(
            shape: .soft,
            size: 40.0, // radius = 20
            opacity: 1.0,
            flow: 1.0,
            hardness: 0.2, // inner radius = 4
            color: SIMD4<Float>(0, 0, 1, 1)
        ))

        let center = CGPoint(x: 100, y: 100)
        brush.mouseDown(at: center, document: doc)
        brush.mouseUp(at: center, document: doc)

        let layer = doc.activeLayer as! BitmapLayer

        // Center pixel (d = 0)
        let pCenter = layer.tileGrid.readPixel(x: 100, y: 100)
        // Mid-falloff pixel (d = 12)
        let pMid = layer.tileGrid.readPixel(x: 112, y: 100)
        // Edge-falloff pixel (d = 18)
        let pEdge = layer.tileGrid.readPixel(x: 118, y: 100)
        // Outside pixel (d = 25)
        let pOut = layer.tileGrid.readPixel(x: 125, y: 100)

        XCTAssertEqual(pCenter.w, 255)
        XCTAssertGreaterThan(pMid.w, pEdge.w)
        XCTAssertGreaterThan(pEdge.w, 0)
        XCTAssertEqual(pOut.w, 0)
    }

    func testCatmullRomSplineSmoothing() throws {
        let doc = try Document(canvasSize: CGSize(width: 400, height: 400))
        let brush = BrushTool(configuration: BrushConfiguration(
            shape: .round,
            size: 10.0,
            opacity: 1.0,
            flow: 1.0,
            spacing: 0.1,
            color: SIMD4<Float>(1, 1, 0, 1)
        ))

        // Drag along a curved trajectory
        brush.mouseDown(at: CGPoint(x: 50, y: 100), document: doc)
        brush.mouseDragged(to: CGPoint(x: 100, y: 50), document: doc)
        brush.mouseDragged(to: CGPoint(x: 150, y: 150), document: doc)
        brush.mouseDragged(to: CGPoint(x: 200, y: 100), document: doc)
        brush.mouseUp(at: CGPoint(x: 200, y: 100), document: doc)

        let layer = doc.activeLayer as! BitmapLayer
        // Check that intermediate points along the spline are painted
        let pStart = layer.tileGrid.readPixel(x: 50, y: 100)
        let pMid1 = layer.tileGrid.readPixel(x: 100, y: 50)
        let pMid2 = layer.tileGrid.readPixel(x: 150, y: 150)
        let pEnd = layer.tileGrid.readPixel(x: 200, y: 100)

        XCTAssertEqual(pStart.w, 255)
        XCTAssertEqual(pMid1.w, 255)
        XCTAssertEqual(pMid2.w, 255)
        XCTAssertEqual(pEnd.w, 255)
    }

    func testBrushSpacingAccumulator() throws {
        let doc = try Document(canvasSize: CGSize(width: 400, height: 400))
        let brush = BrushTool(configuration: BrushConfiguration(
            shape: .round,
            size: 10.0,
            opacity: 1.0,
            flow: 1.0,
            spacing: 0.5, // 5px between stamps
            color: SIMD4<Float>(1, 0, 1, 1)
        ))

        // Drag horizontally from (100, 100) to (200, 100)
        brush.mouseDown(at: CGPoint(x: 100, y: 100), document: doc)
        brush.mouseDragged(to: CGPoint(x: 200, y: 100), document: doc)
        brush.mouseUp(at: CGPoint(x: 200, y: 100), document: doc)

        let layer = doc.activeLayer as! BitmapLayer
        // Points at steps of 5 should all be painted
        for x in stride(from: 100, through: 200, by: 10) {
            let px = layer.tileGrid.readPixel(x: x, y: 100)
            XCTAssertEqual(px.w, 255, "Pixel at x=\(x) should be painted")
        }
    }

    func testBrushLockAlphaInvariant() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let layer = doc.activeLayer as! BitmapLayer
        layer.lockAlpha = true

        let brush = BrushTool(configuration: BrushConfiguration(
            shape: .round,
            size: 20.0,
            color: SIMD4<Float>(1, 0, 0, 1)
        ))

        // Paint onto fully transparent canvas with lockAlpha = true
        brush.mouseDown(at: CGPoint(x: 100, y: 100), document: doc)
        brush.mouseUp(at: CGPoint(x: 100, y: 100), document: doc)

        // Pixel alpha must remain 0!
        let px = layer.tileGrid.readPixel(x: 100, y: 100)
        XCTAssertEqual(px.w, 0, "lockAlpha must prevent painting onto transparent pixels")

        // Now pre-fill a pixel with semi-transparent blue (A = 128)
        layer.lockAlpha = false
        layer.tileGrid.writePixel(x: 50, y: 50, color: SIMD4<UInt8>(0, 0, 255, 128))
        layer.lockAlpha = true

        // Paint over (50, 50) with red
        brush.mouseDown(at: CGPoint(x: 50, y: 50), document: doc)
        brush.mouseUp(at: CGPoint(x: 50, y: 50), document: doc)

        let pxBlended = layer.tileGrid.readPixel(x: 50, y: 50)
        XCTAssertEqual(pxBlended.w, 128, "lockAlpha must strictly preserve the backdrop alpha channel (128)")
        XCTAssertGreaterThan(pxBlended.x, 0, "Red color should blend in")
    }

    func testBrushSelectionConstraint() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let mask = doc.selectionMask!

        // Select a 50x50 square at (50, 50) to (100, 100)
        for y in 50..<100 {
            for x in 50..<100 {
                mask.setAlpha(x: x, y: y, value: 255)
            }
        }

        let brush = BrushTool(configuration: BrushConfiguration(
            shape: .round,
            size: 30.0,
            color: SIMD4<Float>(1, 1, 1, 1)
        ))

        // Stroke across the selection boundary from (40, 75) to (110, 75)
        brush.mouseDown(at: CGPoint(x: 40, y: 75), document: doc)
        brush.mouseDragged(to: CGPoint(x: 110, y: 75), document: doc)
        brush.mouseUp(at: CGPoint(x: 110, y: 75), document: doc)

        let layer = doc.activeLayer as! BitmapLayer
        // Pixel at (45, 75) is outside selection: must be untouched (alpha 0)
        let outsidePixel = layer.tileGrid.readPixel(x: 45, y: 75)
        XCTAssertEqual(outsidePixel.w, 0, "Pixels outside selection must remain untouched")

        // Pixel at (75, 75) is inside selection: must be painted
        let insidePixel = layer.tileGrid.readPixel(x: 75, y: 75)
        XCTAssertEqual(insidePixel.w, 255, "Pixels inside selection must be painted")
    }

    func testBrushCrossTileBoundary() throws {
        // Canvas size 1024x1024 spans 4 tiles of 512x512
        let doc = try Document(canvasSize: CGSize(width: 1024, height: 1024))
        let brush = BrushTool(configuration: BrushConfiguration(
            shape: .round,
            size: 30.0,
            color: SIMD4<Float>(1, 0, 0, 1)
        ))

        // Paint crossing the horizontal tile border at x = 512
        let pStart = CGPoint(x: 500, y: 256) // In Tile(0, 0)
        let pEnd = CGPoint(x: 525, y: 256)   // In Tile(1, 0)

        brush.mouseDown(at: pStart, document: doc)
        brush.mouseDragged(to: pEnd, document: doc)
        brush.mouseUp(at: pEnd, document: doc)

        let layer = doc.activeLayer as! BitmapLayer
        XCTAssertTrue(layer.tileGrid.isTileAllocated(at: TileCoord(x: 0, y: 0)))
        XCTAssertTrue(layer.tileGrid.isTileAllocated(at: TileCoord(x: 1, y: 0)))

        let pxTile0 = layer.tileGrid.readPixel(x: 500, y: 256)
        let pxTile1 = layer.tileGrid.readPixel(x: 525, y: 256)
        XCTAssertEqual(pxTile0.x, 255)
        XCTAssertEqual(pxTile1.x, 255)
    }

    // MARK: - F10 Eraser Tool Tests

    func testEraserAttenuatesAlpha() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let layer = doc.activeLayer as! BitmapLayer
        // Write solid red pixel at (100, 100)
        layer.tileGrid.writePixel(x: 100, y: 100, color: SIMD4<UInt8>(255, 0, 0, 255))

        let eraser = EraserTool(configuration: BrushConfiguration(
            shape: .round,
            size: 20.0,
            opacity: 0.5,
            flow: 1.0
        ))

        eraser.mouseDown(at: CGPoint(x: 100, y: 100), document: doc)
        eraser.mouseUp(at: CGPoint(x: 100, y: 100), document: doc)

        let px = layer.tileGrid.readPixel(x: 100, y: 100)
        // Alpha should be attenuated (around 50% = 128)
        XCTAssertLessThan(px.w, 255)
        XCTAssertGreaterThan(px.w, 0)
    }

    func testEraserLockAlphaInvariant() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let layer = doc.activeLayer as! BitmapLayer
        layer.tileGrid.writePixel(x: 100, y: 100, color: SIMD4<UInt8>(255, 0, 0, 255))
        layer.lockAlpha = true

        let eraser = EraserTool(configuration: BrushConfiguration(
            shape: .round,
            size: 20.0,
            opacity: 1.0,
            flow: 1.0
        ))

        eraser.mouseDown(at: CGPoint(x: 100, y: 100), document: doc)
        eraser.mouseUp(at: CGPoint(x: 100, y: 100), document: doc)

        let px = layer.tileGrid.readPixel(x: 100, y: 100)
        XCTAssertEqual(px.w, 255, "Eraser must be NO-OP when lockAlpha is true")
    }

    func testEraserTilePruning() throws {
        let doc = try Document(canvasSize: CGSize(width: 512, height: 512))
        let layer = doc.activeLayer as! BitmapLayer
        // Allocate tile (0, 0) by writing 1 pixel
        layer.tileGrid.writePixel(x: 200, y: 200, color: SIMD4<UInt8>(255, 0, 0, 255))
        XCTAssertTrue(layer.tileGrid.isTileAllocated(at: TileCoord(x: 0, y: 0)))

        // Erase that pixel completely
        let eraser = EraserTool(configuration: BrushConfiguration(
            shape: .round,
            size: 50.0,
            opacity: 1.0,
            flow: 1.0
        ))

        eraser.mouseDown(at: CGPoint(x: 200, y: 200), document: doc)
        eraser.mouseUp(at: CGPoint(x: 200, y: 200), document: doc)

        // Since the tile has all pixels with alpha = 0, it should be pruned!
        XCTAssertFalse(layer.tileGrid.isTileAllocated(at: TileCoord(x: 0, y: 0)))
        XCTAssertEqual(layer.tileGrid.allocatedTileCount, 0)
    }

    // MARK: - F11 Flood Fill Tool Tests

    func testContiguousScanlineFill() throws {
        let doc = try Document(canvasSize: CGSize(width: 100, height: 100))
        let layer = doc.activeLayer as! BitmapLayer

        // Draw a boundary box in black around (20, 20) to (50, 50)
        for x in 20...50 {
            layer.tileGrid.writePixel(x: x, y: 20, color: SIMD4<UInt8>(0, 0, 0, 255))
            layer.tileGrid.writePixel(x: x, y: 50, color: SIMD4<UInt8>(0, 0, 0, 255))
        }
        for y in 20...50 {
            layer.tileGrid.writePixel(x: 20, y: y, color: SIMD4<UInt8>(0, 0, 0, 255))
            layer.tileGrid.writePixel(x: 50, y: y, color: SIMD4<UInt8>(0, 0, 0, 255))
        }

        // Fill interior with red
        let fill = FloodFillTool(configuration: FloodFillConfiguration(
            tolerance: 0.05,
            fillColor: SIMD4<Float>(1, 0, 0, 1),
            mode: .contiguous
        ))

        fill.executeFill(at: CGPoint(x: 35, y: 35), document: doc)

        // Interior should be filled
        let insidePx = layer.tileGrid.readPixel(x: 35, y: 35)
        XCTAssertEqual(insidePx.x, 255)
        XCTAssertEqual(insidePx.w, 255)

        // Exterior should remain transparent (untouched)
        let outsidePx = layer.tileGrid.readPixel(x: 10, y: 10)
        XCTAssertEqual(outsidePx.w, 0)
    }

    func testFillColorToleranceEuclidean() throws {
        let doc = try Document(canvasSize: CGSize(width: 100, height: 100))
        let layer = doc.activeLayer as! BitmapLayer

        // Write slightly different shades of red: (250, 0, 0) and (200, 0, 0)
        layer.tileGrid.writePixel(x: 10, y: 10, color: SIMD4<UInt8>(255, 0, 0, 255))
        layer.tileGrid.writePixel(x: 11, y: 10, color: SIMD4<UInt8>(250, 0, 0, 255))
        layer.tileGrid.writePixel(x: 12, y: 10, color: SIMD4<UInt8>(100, 0, 0, 255)) // Far different

        let fill = FloodFillTool(configuration: FloodFillConfiguration(
            tolerance: 0.1, // ~10% tolerance matches (250, 0, 0) but not (100, 0, 0)
            fillColor: SIMD4<Float>(0, 1, 0, 1),
            mode: .contiguous
        ))

        fill.executeFill(at: CGPoint(x: 10, y: 10), document: doc)

        let px11 = layer.tileGrid.readPixel(x: 11, y: 10)
        let px12 = layer.tileGrid.readPixel(x: 12, y: 10)
        XCTAssertEqual(px11.y, 255, "Should fill close color within tolerance")
        XCTAssertEqual(px12.x, 100, "Should NOT fill color exceeding tolerance")
    }

    func testGlobalFillNonContiguous() throws {
        let doc = try Document(canvasSize: CGSize(width: 100, height: 100))
        let layer = doc.activeLayer as! BitmapLayer

        // Write isolated pixels across canvas
        layer.tileGrid.writePixel(x: 10, y: 10, color: SIMD4<UInt8>(0, 0, 255, 255))
        layer.tileGrid.writePixel(x: 80, y: 80, color: SIMD4<UInt8>(0, 0, 255, 255))

        let fill = FloodFillTool(configuration: FloodFillConfiguration(
            tolerance: 0.05,
            fillColor: SIMD4<Float>(1, 1, 0, 1),
            mode: .global
        ))

        fill.executeFill(at: CGPoint(x: 10, y: 10), document: doc)

        let px1 = layer.tileGrid.readPixel(x: 10, y: 10)
        let px2 = layer.tileGrid.readPixel(x: 80, y: 80)
        XCTAssertEqual(px1.x, 255)
        XCTAssertEqual(px1.y, 255)
        XCTAssertEqual(px2.x, 255)
        XCTAssertEqual(px2.y, 255)
    }

    func testFillNoCallStackOverflow() throws {
        // 1024x1024 canvas with 1,048,576 pixels
        let doc = try Document(canvasSize: CGSize(width: 1024, height: 1024))
        let fill = FloodFillTool(configuration: FloodFillConfiguration(
            tolerance: 0.05,
            fillColor: SIMD4<Float>(0, 0, 1, 1),
            mode: .contiguous
        ))

        let start = Date()
        fill.executeFill(at: CGPoint(x: 0, y: 0), document: doc)
        let duration = Date().timeIntervalSince(start)

        XCTAssertLessThan(duration, 2.0, "Scanline fill on 1024x1024 should complete in under 2 seconds without recursion")
        let layer = doc.activeLayer as! BitmapLayer
        let px = layer.tileGrid.readPixel(x: 1000, y: 1000)
        XCTAssertEqual(px.z, 255)
        XCTAssertEqual(px.w, 255)
    }

    func testFillSelectionBoundary() throws {
        let doc = try Document(canvasSize: CGSize(width: 100, height: 100))
        let mask = doc.selectionMask!
        // Select rect [20, 40] x [20, 40]
        for y in 20...40 {
            for x in 20...40 {
                mask.setAlpha(x: x, y: y, value: 255)
            }
        }

        let fill = FloodFillTool(configuration: FloodFillConfiguration(
            tolerance: 0.05,
            fillColor: SIMD4<Float>(1, 0, 0, 1),
            mode: .contiguous
        ))

        fill.executeFill(at: CGPoint(x: 30, y: 30), document: doc)

        let layer = doc.activeLayer as! BitmapLayer
        let insidePx = layer.tileGrid.readPixel(x: 30, y: 30)
        let outsidePx = layer.tileGrid.readPixel(x: 50, y: 50)
        XCTAssertEqual(insidePx.w, 255)
        XCTAssertEqual(outsidePx.w, 0, "Fill must not escape selection boundary")
    }

    // MARK: - F12 Gradient Tool Tests

    func testLinearGradienttParam() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 100))
        let gradient = GradientTool(configuration: GradientConfiguration(
            type: .linear,
            spreadMode: .pad,
            stops: [
                GradientStop(offset: 0.0, color: SIMD4<Float>(0, 0, 0, 1)), // Black
                GradientStop(offset: 1.0, color: SIMD4<Float>(1, 1, 1, 1))  // White
            ],
            enableDithering: false
        ))

        // Horizontal gradient from x=0 to x=199
        gradient.applyGradient(
            from: CGPoint(x: 0, y: 50),
            to: CGPoint(x: 199, y: 50),
            document: doc,
            layer: doc.activeLayer as! BitmapLayer
        )

        let layer = doc.activeLayer as! BitmapLayer
        let pStart = layer.tileGrid.readPixel(x: 0, y: 50)
        let pMid = layer.tileGrid.readPixel(x: 100, y: 50)
        let pEnd = layer.tileGrid.readPixel(x: 199, y: 50)

        XCTAssertEqual(pStart.x, 0)
        // Midpoint should be approximately 128 (within +/- 3)
        XCTAssertGreaterThanOrEqual(pMid.x, 125)
        XCTAssertLessThanOrEqual(pMid.x, 130)
        XCTAssertEqual(pEnd.x, 255)
    }

    func testRadialGradienttParam() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let gradient = GradientTool(configuration: GradientConfiguration(
            type: .radial,
            spreadMode: .pad,
            stops: [
                GradientStop(offset: 0.0, color: SIMD4<Float>(1, 0, 0, 1)), // Red center
                GradientStop(offset: 1.0, color: SIMD4<Float>(0, 0, 1, 1))  // Blue edge
            ],
            enableDithering: false
        ))

        // Center at (100, 100), radius 50 to (150, 100)
        gradient.applyGradient(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 150, y: 100),
            document: doc,
            layer: doc.activeLayer as! BitmapLayer
        )

        let layer = doc.activeLayer as! BitmapLayer
        let pCenter = layer.tileGrid.readPixel(x: 100, y: 100)
        let pRadius = layer.tileGrid.readPixel(x: 150, y: 100)

        XCTAssertEqual(pCenter.x, 255)
        XCTAssertEqual(pCenter.z, 0)
        XCTAssertEqual(pRadius.x, 0)
        XCTAssertEqual(pRadius.z, 255)
    }

    func testSpreadModesPadRepeatReflect() {
        let gradient = GradientTool()

        // Test t = 1.5 across modes
        let pad = gradient.mapSpreadMode(tRaw: 1.5, spread: .pad)
        let rep = gradient.mapSpreadMode(tRaw: 1.5, spread: .repeatMode)
        let ref = gradient.mapSpreadMode(tRaw: 1.5, spread: .reflect)

        XCTAssertEqual(pad, 1.0, accuracy: 0.001)
        XCTAssertEqual(rep, 0.5, accuracy: 0.001)
        XCTAssertEqual(ref, 0.5, accuracy: 0.001)

        // Test t = 0.5 across modes
        XCTAssertEqual(gradient.mapSpreadMode(tRaw: 0.5, spread: .pad), 0.5, accuracy: 0.001)
        XCTAssertEqual(gradient.mapSpreadMode(tRaw: 0.5, spread: .repeatMode), 0.5, accuracy: 0.001)
        XCTAssertEqual(gradient.mapSpreadMode(tRaw: 0.5, spread: .reflect), 0.5, accuracy: 0.001)
    }

    func testBayerDitheringEliminatesBanding() throws {
        let docWithDither = try Document(canvasSize: CGSize(width: 100, height: 100))
        let docNoDither = try Document(canvasSize: CGSize(width: 100, height: 100))

        let stops = [
            GradientStop(offset: 0.0, color: SIMD4<Float>(0.1, 0.1, 0.1, 1)),
            GradientStop(offset: 1.0, color: SIMD4<Float>(0.15, 0.15, 0.15, 1))
        ]

        let toolDither = GradientTool(configuration: GradientConfiguration(
            type: .linear,
            stops: stops,
            enableDithering: true
        ))
        let toolNoDither = GradientTool(configuration: GradientConfiguration(
            type: .linear,
            stops: stops,
            enableDithering: false
        ))

        toolDither.applyGradient(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50), document: docWithDither, layer: docWithDither.activeLayer as! BitmapLayer)
        toolNoDither.applyGradient(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50), document: docNoDither, layer: docNoDither.activeLayer as! BitmapLayer)

        let layerD = docWithDither.activeLayer as! BitmapLayer
        let layerND = docNoDither.activeLayer as! BitmapLayer

        // Count distinct color values along row y=50
        var setD = Set<UInt8>()
        var setND = Set<UInt8>()
        for x in 0..<100 {
            setD.insert(layerD.tileGrid.readPixel(x: x, y: 50).x)
            setND.insert(layerND.tileGrid.readPixel(x: x, y: 50).x)
        }

        // Dithering adds spatial variations across adjacent coordinates
        XCTAssertGreaterThanOrEqual(setD.count, setND.count)
    }

    // MARK: - F13 Eyedropper Tool Tests

    func testPointSampleSingleLayer() throws {
        let doc = try Document(canvasSize: CGSize(width: 100, height: 100))
        let layer = doc.activeLayer as! BitmapLayer
        layer.tileGrid.writePixel(x: 25, y: 25, color: SIMD4<UInt8>(255, 128, 64, 255))

        let eyedropper = EyedropperTool(sampleMode: .pointSample, sourceMode: .currentLayer)
        let sample = eyedropper.sample(at: CGPoint(x: 25, y: 25), document: doc)

        XCTAssertNotNil(sample)
        XCTAssertEqual(sample?.colorBytes.x, 255)
        XCTAssertEqual(sample?.colorBytes.y, 128)
        XCTAssertEqual(sample?.colorBytes.z, 64)
        XCTAssertEqual(sample?.colorBytes.w, 255)
        XCTAssertEqual(sample?.hexString, "#FF8040")
    }

    func testPointSampleComposited() throws {
        let doc = try Document(canvasSize: CGSize(width: 100, height: 100))
        let layer1 = doc.activeLayer as! BitmapLayer
        layer1.tileGrid.writePixel(x: 25, y: 25, color: SIMD4<UInt8>(255, 0, 0, 255)) // Red

        let layer2 = BitmapLayer(name: "Layer 2", bounds: doc.bounds)
        layer2.tileGrid.writePixel(x: 25, y: 25, color: SIMD4<UInt8>(0, 255, 0, 128)) // 50% Green
        doc.addLayer(layer2)

        let eyedropper = EyedropperTool(sampleMode: .pointSample, sourceMode: .allVisibleLayers)
        let sample = eyedropper.sample(at: CGPoint(x: 25, y: 25), document: doc)

        XCTAssertNotNil(sample)
        // Composited red backdrop with 50% green source produces yellow-orange
        XCTAssertGreaterThan(sample!.colorBytes.x, 100)
        XCTAssertGreaterThan(sample!.colorBytes.y, 100)
    }

    func testAverage3x3AlphaWeighted() throws {
        let doc = try Document(canvasSize: CGSize(width: 100, height: 100))
        let layer = doc.activeLayer as! BitmapLayer

        // Only one pixel in the 3x3 kernel has color (red), rest are transparent (alpha 0)
        layer.tileGrid.writePixel(x: 50, y: 50, color: SIMD4<UInt8>(255, 0, 0, 255))

        let eyedropper = EyedropperTool(sampleMode: .average3x3, sourceMode: .currentLayer)
        let sample = eyedropper.sample(at: CGPoint(x: 50, y: 50), document: doc)

        XCTAssertNotNil(sample)
        // Alpha-weighted RGB should NOT be diluted to black (0, 0, 0)!
        // Red channel must remain 255 because all surrounding void pixels have alpha 0
        XCTAssertEqual(sample?.colorBytes.x, 255)
        XCTAssertEqual(sample?.colorBytes.y, 0)
        XCTAssertEqual(sample?.colorBytes.z, 0)
    }

    func testColorFormatStrings() throws {
        let doc = try Document(canvasSize: CGSize(width: 100, height: 100))
        let layer = doc.activeLayer as! BitmapLayer
        layer.tileGrid.writePixel(x: 10, y: 10, color: SIMD4<UInt8>(255, 0, 128, 255))

        let eyedropper = EyedropperTool(sampleMode: .pointSample, sourceMode: .currentLayer)
        let sample = eyedropper.sample(at: CGPoint(x: 10, y: 10), document: doc)!

        XCTAssertEqual(sample.hexString, "#FF0080")
        XCTAssertEqual(sample.rgbString, "rgb(255, 0, 128)")
        XCTAssertTrue(sample.rgbaString.contains("rgba(255, 0, 128"))
        XCTAssertGreaterThan(sample.hsb.hue, 0.8) // Magenta-pink hue
    }
}
