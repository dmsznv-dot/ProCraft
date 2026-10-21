#if canImport(XCTest)
import XCTest
#endif
@testable import PixelCraftEngine

final class SelectionAndUndoTests: XCTestCase, @unchecked Sendable {

    // MARK: - F14 Marquee Selection Tests

    func testRectangularMarqueeGeometry() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let marquee = MarqueeSelectionTool(shape: .rectangle)

        // Select rectangle from (40, 40) to (80, 80)
        marquee.mouseDown(at: CGPoint(x: 40, y: 40), document: doc)
        marquee.mouseDragged(to: CGPoint(x: 80, y: 80), document: doc)
        marquee.mouseUp(at: CGPoint(x: 80, y: 80), document: doc)

        let mask = doc.selectionMask!
        XCTAssertTrue(mask.hasActiveSelection)

        // Interior pixel (60, 60) should have alpha 255
        XCTAssertEqual(mask.alphaAt(x: 60, y: 60), 255)
        XCTAssertTrue(mask.contains(x: 60, y: 60))

        // Exterior pixel (20, 20) should have alpha 0
        XCTAssertEqual(mask.alphaAt(x: 20, y: 20), 0)
        XCTAssertFalse(mask.contains(x: 20, y: 20))
    }

    func testEllipticalMarqueeGeometry() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let marquee = MarqueeSelectionTool(shape: .ellipse)

        // Select ellipse from (50, 50) to (150, 150) -> Center at (100, 100), radius 50
        marquee.mouseDown(at: CGPoint(x: 50, y: 50), document: doc)
        marquee.mouseDragged(to: CGPoint(x: 150, y: 150), document: doc)
        marquee.mouseUp(at: CGPoint(x: 150, y: 150), document: doc)

        let mask = doc.selectionMask!
        XCTAssertTrue(mask.hasActiveSelection)

        // Center pixel (100, 100) inside ellipse
        XCTAssertEqual(mask.alphaAt(x: 100, y: 100), 255)

        // Corner pixel of bounding box (52, 52) is outside ellipse (distance ~ 67 > 50)
        XCTAssertEqual(mask.alphaAt(x: 52, y: 52), 0)
    }

    func testMarqueeShiftAspectRatioConstraint() throws {
        let doc = try Document(canvasSize: CGSize(width: 400, height: 400))
        let marquee = MarqueeSelectionTool(shape: .rectangle)
        marquee.isConstrained = true // Shift key pressed

        marquee.mouseDown(at: CGPoint(x: 50, y: 50), document: doc)
        marquee.mouseDragged(to: CGPoint(x: 150, y: 200), document: doc) // dx=100, dy=150
        marquee.mouseUp(at: CGPoint(x: 150, y: 200), document: doc)

        let mask = doc.selectionMask!
        guard let bounds = mask.selectionBounds else {
            XCTFail("Bounds should not be nil")
            return
        }

        // With Shift constraint, min(dx, dy) = 100, so width == height == 100
        XCTAssertEqual(bounds.width, 100.0, accuracy: 1.0)
        XCTAssertEqual(bounds.height, 100.0, accuracy: 1.0)
    }

    func testMarqueeOptionCenterExpansion() throws {
        let doc = try Document(canvasSize: CGSize(width: 400, height: 400))
        let marquee = MarqueeSelectionTool(shape: .rectangle)
        marquee.isFromCenter = true // Option key pressed

        marquee.mouseDown(at: CGPoint(x: 100, y: 100), document: doc)
        marquee.mouseDragged(to: CGPoint(x: 150, y: 130), document: doc) // dx=50, dy=30
        marquee.mouseUp(at: CGPoint(x: 150, y: 130), document: doc)

        let mask = doc.selectionMask!
        guard let bounds = mask.selectionBounds else {
            XCTFail("Bounds should not be nil")
            return
        }

        // Centered at (100, 100): origin = (50, 70), width = 100, height = 60
        XCTAssertEqual(bounds.midX, 100.0, accuracy: 1.0)
        XCTAssertEqual(bounds.midY, 100.0, accuracy: 1.0)
        XCTAssertEqual(bounds.width, 100.0, accuracy: 1.0)
        XCTAssertEqual(bounds.height, 60.0, accuracy: 1.0)
    }

    func testMarqueeSingleClickDeselect() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        doc.selectionMask?.selectAll()
        XCTAssertTrue(doc.selectionMask!.hasActiveSelection)

        // Single click without drag deselects
        let marquee = MarqueeSelectionTool(shape: .rectangle)
        marquee.mouseDown(at: CGPoint(x: 50, y: 50), document: doc)
        marquee.mouseUp(at: CGPoint(x: 50, y: 50), document: doc)

        XCTAssertFalse(doc.selectionMask!.hasActiveSelection)
        XCTAssertTrue(doc.selectionMask!.isEmpty)
    }

    // MARK: - F15 Lasso Selection Tests

    func testFreehandLassoClosure() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let lasso = LassoSelectionTool(configuration: LassoConfiguration(type: .freehand))

        // Draw a triangle loop: (50, 50) -> (100, 50) -> (75, 100)
        lasso.mouseDown(at: CGPoint(x: 50, y: 50), document: doc)
        lasso.mouseDragged(to: CGPoint(x: 100, y: 50), document: doc)
        lasso.mouseDragged(to: CGPoint(x: 75, y: 100), document: doc)
        lasso.mouseUp(at: CGPoint(x: 75, y: 100), document: doc)

        let mask = doc.selectionMask!
        XCTAssertTrue(mask.hasActiveSelection)

        // Center of triangle (75, 65) should be selected
        XCTAssertEqual(mask.alphaAt(x: 75, y: 65), 255)

        // Outside point (10, 10) should be unselected
        XCTAssertEqual(mask.alphaAt(x: 10, y: 10), 0)
    }

    func testPolygonalLassoClosureEvents() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let lasso = LassoSelectionTool(configuration: LassoConfiguration(type: .polygonal))

        // Click 4 vertices of a rectangle
        lasso.mouseDown(at: CGPoint(x: 30, y: 30), document: doc)
        lasso.mouseDown(at: CGPoint(x: 80, y: 30), document: doc)
        lasso.mouseDown(at: CGPoint(x: 80, y: 80), document: doc)
        lasso.mouseDown(at: CGPoint(x: 30, y: 80), document: doc)

        // Close via Enter key
        lasso.handleEnterKey(document: doc)

        let mask = doc.selectionMask!
        XCTAssertTrue(mask.hasActiveSelection)
        XCTAssertEqual(mask.alphaAt(x: 50, y: 50), 255)
        XCTAssertEqual(mask.alphaAt(x: 10, y: 10), 0)
    }

    func testPolygonalLassoEscapeCancellation() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let lasso = LassoSelectionTool(configuration: LassoConfiguration(type: .polygonal))

        lasso.mouseDown(at: CGPoint(x: 30, y: 30), document: doc)
        lasso.mouseDown(at: CGPoint(x: 80, y: 30), document: doc)
        XCTAssertTrue(lasso.isTracking)

        // Cancel with Escape
        lasso.cancel(document: doc)
        XCTAssertFalse(lasso.isTracking)
        XCTAssertTrue(lasso.vertices.isEmpty)
        XCTAssertFalse(doc.selectionMask!.hasActiveSelection)
    }

    func testPolygonalLassoDeleteVertex() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let lasso = LassoSelectionTool(configuration: LassoConfiguration(type: .polygonal))

        lasso.mouseDown(at: CGPoint(x: 30, y: 30), document: doc)
        lasso.mouseDown(at: CGPoint(x: 80, y: 30), document: doc)
        lasso.mouseDown(at: CGPoint(x: 90, y: 90), document: doc)
        XCTAssertEqual(lasso.vertices.count, 3)

        // Delete last vertex
        lasso.removeLastVertex()
        XCTAssertEqual(lasso.vertices.count, 2)
        XCTAssertEqual(lasso.vertices.last?.x, 80)
    }

    // MARK: - Combinatorial Selection Algebra Tests

    func testSelectionModeUnion() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))

        // Step 1: Base selection [20, 60] x [20, 60]
        let tool1 = MarqueeSelectionTool(configuration: MarqueeConfiguration(mode: .newSelection))
        tool1.mouseDown(at: CGPoint(x: 20, y: 20), document: doc)
        tool1.mouseDragged(to: CGPoint(x: 60, y: 60), document: doc)
        tool1.mouseUp(at: CGPoint(x: 60, y: 60), document: doc)

        // Step 2: Union (Add) selection [40, 80] x [40, 80]
        let tool2 = MarqueeSelectionTool(configuration: MarqueeConfiguration(mode: .add))
        tool2.mouseDown(at: CGPoint(x: 40, y: 40), document: doc)
        tool2.mouseDragged(to: CGPoint(x: 80, y: 80), document: doc)
        tool2.mouseUp(at: CGPoint(x: 80, y: 80), document: doc)

        let mask = doc.selectionMask!
        // (30, 30) from rect 1
        XCTAssertEqual(mask.alphaAt(x: 30, y: 30), 255)
        // (50, 50) overlap
        XCTAssertEqual(mask.alphaAt(x: 50, y: 50), 255)
        // (70, 70) from rect 2
        XCTAssertEqual(mask.alphaAt(x: 70, y: 70), 255)
    }

    func testSelectionModeSubtract() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))

        // Step 1: Base solid selection [20, 80] x [20, 80]
        let tool1 = MarqueeSelectionTool(configuration: MarqueeConfiguration(mode: .newSelection))
        tool1.mouseDown(at: CGPoint(x: 20, y: 20), document: doc)
        tool1.mouseDragged(to: CGPoint(x: 80, y: 80), document: doc)
        tool1.mouseUp(at: CGPoint(x: 80, y: 80), document: doc)

        // Step 2: Subtract inner box [40, 60] x [40, 60]
        let tool2 = MarqueeSelectionTool(configuration: MarqueeConfiguration(mode: .subtract))
        tool2.mouseDown(at: CGPoint(x: 40, y: 40), document: doc)
        tool2.mouseDragged(to: CGPoint(x: 60, y: 60), document: doc)
        tool2.mouseUp(at: CGPoint(x: 60, y: 60), document: doc)

        let mask = doc.selectionMask!
        // Outer border (30, 30) remains 255
        XCTAssertEqual(mask.alphaAt(x: 30, y: 30), 255)
        // Inner hole (50, 50) is cleared to 0
        XCTAssertEqual(mask.alphaAt(x: 50, y: 50), 0)
    }

    func testSelectionModeIntersect() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))

        // Step 1: Box [20, 60] x [20, 60]
        let tool1 = MarqueeSelectionTool(configuration: MarqueeConfiguration(mode: .newSelection))
        tool1.mouseDown(at: CGPoint(x: 20, y: 20), document: doc)
        tool1.mouseDragged(to: CGPoint(x: 60, y: 60), document: doc)
        tool1.mouseUp(at: CGPoint(x: 60, y: 60), document: doc)

        // Step 2: Intersect with [40, 80] x [40, 80]
        let tool2 = MarqueeSelectionTool(configuration: MarqueeConfiguration(mode: .intersect))
        tool2.mouseDown(at: CGPoint(x: 40, y: 40), document: doc)
        tool2.mouseDragged(to: CGPoint(x: 80, y: 80), document: doc)
        tool2.mouseUp(at: CGPoint(x: 80, y: 80), document: doc)

        let mask = doc.selectionMask!
        // Only intersection [40, 60] x [40, 60] survives
        XCTAssertEqual(mask.alphaAt(x: 30, y: 30), 0)
        XCTAssertEqual(mask.alphaAt(x: 50, y: 50), 255)
        XCTAssertEqual(mask.alphaAt(x: 70, y: 70), 0)
    }

    func testSelectionModeDisjointIntersect() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))

        let tool1 = MarqueeSelectionTool(configuration: MarqueeConfiguration(mode: .newSelection))
        tool1.mouseDown(at: CGPoint(x: 10, y: 10), document: doc)
        tool1.mouseDragged(to: CGPoint(x: 30, y: 30), document: doc)
        tool1.mouseUp(at: CGPoint(x: 30, y: 30), document: doc)

        let tool2 = MarqueeSelectionTool(configuration: MarqueeConfiguration(mode: .intersect))
        tool2.mouseDown(at: CGPoint(x: 60, y: 60), document: doc)
        tool2.mouseDragged(to: CGPoint(x: 80, y: 80), document: doc)
        tool2.mouseUp(at: CGPoint(x: 80, y: 80), document: doc)

        let mask = doc.selectionMask!
        XCTAssertTrue(mask.isEmpty)
        XCTAssertFalse(mask.hasActiveSelection)
    }

    // MARK: - Feathering Tests

    func testGaussianFeatherSeparable() throws {
        let doc = try Document(canvasSize: CGSize(width: 100, height: 100))
        let tool = MarqueeSelectionTool(configuration: MarqueeConfiguration(
            shape: .rectangle,
            featherRadius: 4.0
        ))

        tool.mouseDown(at: CGPoint(x: 20, y: 20), document: doc)
        tool.mouseDragged(to: CGPoint(x: 80, y: 80), document: doc)
        tool.mouseUp(at: CGPoint(x: 80, y: 80), document: doc)

        let mask = doc.selectionMask!
        // Deep inside selection (50, 50)
        let deepInside = mask.alphaAt(x: 50, y: 50)
        // Transition edge pixel (20, 50)
        let edge = mask.alphaAt(x: 20, y: 50)
        // Soft transition exterior pixel (17, 50)
        let softExterior = mask.alphaAt(x: 17, y: 50)

        XCTAssertEqual(deepInside, 255)
        XCTAssertLessThan(edge, 255)
        XCTAssertGreaterThan(edge, softExterior)
        XCTAssertGreaterThan(softExterior, 0)
    }

    // MARK: - SparseMaskGrid & SelectionMask Core Tests

    func testSparseMaskGridMemoryEfficiency() {
        // 8K UHD canvas
        let maskGrid = SparseMaskGrid(canvasSize: CGSize(width: 8192, height: 4320))
        XCTAssertEqual(maskGrid.allocatedTileCount, 0)
        XCTAssertEqual(maskGrid.memoryUsageBytes, 0)

        // Set a small 100x100 selection in tile (0, 0)
        for y in 0..<100 {
            for x in 0..<100 {
                maskGrid.setAlpha(x: x, y: y, value: 255)
            }
        }

        XCTAssertEqual(maskGrid.allocatedTileCount, 1)
        XCTAssertEqual(maskGrid.memoryUsageBytes, 256 * 1024, "Consumes exactly 256 KB on 8K canvas")
    }

    func testSelectAllAndDeselect() {
        let mask = SelectionMask(canvasSize: CGSize(width: 1024, height: 1024))
        XCTAssertTrue(mask.isEmpty)

        mask.selectAll()
        XCTAssertFalse(mask.isEmpty)
        XCTAssertEqual(mask.alphaAt(x: 500, y: 500), 255)
        XCTAssertEqual(mask.alphaAt(x: 1000, y: 1000), 255)

        mask.deselect()
        XCTAssertTrue(mask.isEmpty)
        XCTAssertEqual(mask.maskGrid.allocatedTileCount, 0)
    }

    func testSelectionInversion() {
        let mask = SelectionMask(canvasSize: CGSize(width: 1024, height: 1024))
        // Inverting empty mask selects the whole canvas
        mask.invert()
        XCTAssertFalse(mask.isEmpty)
        XCTAssertEqual(mask.alphaAt(x: 10, y: 10), 255)
        XCTAssertEqual(mask.alphaAt(x: 800, y: 800), 255)

        // Inverting full mask deselects everything
        mask.invert()
        XCTAssertTrue(mask.isEmpty)
        XCTAssertEqual(mask.maskGrid.allocatedTileCount, 0)
    }

    func testSelectionBounds() {
        let mask = SelectionMask(canvasSize: CGSize(width: 1000, height: 1000))
        XCTAssertNil(mask.selectionBounds)

        // Set 4 corner pixels of a [100, 200] x [150, 300] box
        mask.setAlpha(x: 100, y: 150, value: 255)
        mask.setAlpha(x: 200, y: 300, value: 255)

        let bounds = mask.selectionBounds
        XCTAssertNotNil(bounds)
        XCTAssertEqual(bounds?.origin.x, 100.0)
        XCTAssertEqual(bounds?.origin.y, 150.0)
        XCTAssertEqual(bounds?.width, 101.0)
        XCTAssertEqual(bounds?.height, 151.0)
    }

    // MARK: - Marching Squares Tests

    func testMarchingSquaresContourClosedPath() {
        let mask = SelectionMask(canvasSize: CGSize(width: 200, height: 200))
        for y in 40...80 {
            for x in 40...80 {
                mask.setAlpha(x: x, y: y, value: 255)
            }
        }

        let path = mask.marchingSquaresContourPath()
        XCTAssertFalse(path.isEmpty)
        let bounds = path.boundingBox
        XCTAssertGreaterThanOrEqual(bounds.minX, 39.0)
        XCTAssertLessThanOrEqual(bounds.maxX, 81.5)
        XCTAssertGreaterThanOrEqual(bounds.minY, 39.0)
        XCTAssertLessThanOrEqual(bounds.maxY, 81.5)
    }

    func testMarchingSquaresMultipleIslands() {
        let mask = SelectionMask(canvasSize: CGSize(width: 400, height: 400))
        // Island 1: [20, 40] x [20, 40]
        for y in 20...40 {
            for x in 20...40 { mask.setAlpha(x: x, y: y, value: 255) }
        }
        // Island 2: [200, 240] x [200, 240]
        for y in 200...240 {
            for x in 200...240 { mask.setAlpha(x: x, y: y, value: 255) }
        }

        let path = mask.marchingSquaresContourPath()
        XCTAssertFalse(path.isEmpty)
        // Path should encompass both islands
        let bounds = path.boundingBox
        XCTAssertLessThanOrEqual(bounds.minX, 21.0)
        XCTAssertGreaterThanOrEqual(bounds.maxX, 239.0)
    }

    // MARK: - F17 TileUndoManager Tests

    func testTileDeltaMemorySavings() throws {
        let doc = try Document(canvasSize: CGSize(width: 8192, height: 4320))
        let brush = BrushTool(configuration: BrushConfiguration(
            size: 50.0,
            color: SIMD4<Float>(1, 0, 0, 1)
        ))

        // Draw a 100px stroke in tile (0, 0)
        brush.mouseDown(at: CGPoint(x: 100, y: 100), document: doc)
        brush.mouseDragged(to: CGPoint(x: 200, y: 100), document: doc)
        brush.mouseUp(at: CGPoint(x: 200, y: 100), document: doc)

        XCTAssertTrue(doc.undoManager.canUndo)
        XCTAssertEqual(doc.undoManager.undoCount, 1)

        // Check memory of command: touches 1 tile = 1 MB snapshot, NOT 141 MB layer!
        let undoCmd = doc.undoManager.undoActionName
        XCTAssertEqual(undoCmd, "Brush Stroke")
    }

    func testUndoRedoStrokeFidelity() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let layer = doc.activeLayer as! BitmapLayer

        let brush = BrushTool(configuration: BrushConfiguration(
            size: 20.0,
            color: SIMD4<Float>(0, 1, 0, 1)
        ))

        // Initial state: pixel (100, 100) is transparent
        XCTAssertEqual(layer.tileGrid.readPixel(x: 100, y: 100).w, 0)

        // Stroke
        brush.mouseDown(at: CGPoint(x: 100, y: 100), document: doc)
        brush.mouseUp(at: CGPoint(x: 100, y: 100), document: doc)
        XCTAssertEqual(layer.tileGrid.readPixel(x: 100, y: 100).y, 255)

        // Undo
        doc.undoManager.undo(in: doc)
        XCTAssertEqual(layer.tileGrid.readPixel(x: 100, y: 100).w, 0, "Pixel must be transparent after undo")

        // Redo
        doc.undoManager.redo(in: doc)
        XCTAssertEqual(layer.tileGrid.readPixel(x: 100, y: 100).y, 255, "Pixel must be restored after redo")
    }

    func testUndoTileAllocationRecovery() throws {
        let doc = try Document(canvasSize: CGSize(width: 512, height: 512))
        let layer = doc.activeLayer as! BitmapLayer
        XCTAssertEqual(layer.tileGrid.allocatedTileCount, 0)

        let brush = BrushTool(configuration: BrushConfiguration(size: 20.0))
        brush.mouseDown(at: CGPoint(x: 100, y: 100), document: doc)
        brush.mouseUp(at: CGPoint(x: 100, y: 100), document: doc)
        XCTAssertEqual(layer.tileGrid.allocatedTileCount, 1)

        // Undoing should deallocate the tile completely!
        doc.undoManager.undo(in: doc)
        XCTAssertEqual(layer.tileGrid.allocatedTileCount, 0, "Tile memory must be recovered on undo")
    }

    func testUndoStackCapacityLimit() {
        let manager = TileUndoManager(maxSteps: 5)
        let dummyID = UUID()

        for i in 1...10 {
            let cmd = TileDeltaUndoCommand(
                actionName: "Action \(i)",
                layerId: dummyID,
                beforeTiles: [:],
                afterTiles: [:]
            )
            manager.registerCommand(cmd)
        }

        XCTAssertEqual(manager.undoCount, 5)
        XCTAssertEqual(manager.undoActionName, "Action 10")
    }

    func testUndoGroupingAtomic() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        let layer = doc.activeLayer as! BitmapLayer

        doc.undoManager.beginUndoGrouping(name: "Three Stamps")

        let brush = BrushTool(configuration: BrushConfiguration(size: 10.0))
        brush.mouseDown(at: CGPoint(x: 20, y: 20), document: doc)
        brush.mouseUp(at: CGPoint(x: 20, y: 20), document: doc)

        brush.mouseDown(at: CGPoint(x: 50, y: 50), document: doc)
        brush.mouseUp(at: CGPoint(x: 50, y: 50), document: doc)

        brush.mouseDown(at: CGPoint(x: 80, y: 80), document: doc)
        brush.mouseUp(at: CGPoint(x: 80, y: 80), document: doc)

        doc.undoManager.endUndoGrouping()

        // Should count as 1 user-level undo command
        XCTAssertEqual(doc.undoManager.undoCount, 1)
        XCTAssertEqual(doc.undoManager.undoActionName, "Three Stamps")

        // Single undo reverses all 3 stamps
        doc.undoManager.undo(in: doc)
        XCTAssertEqual(layer.tileGrid.readPixel(x: 20, y: 20).w, 0)
        XCTAssertEqual(layer.tileGrid.readPixel(x: 50, y: 50).w, 0)
        XCTAssertEqual(layer.tileGrid.readPixel(x: 80, y: 80).w, 0)
    }

    func testDocumentDirtyStateTracking() throws {
        let doc = try Document(canvasSize: CGSize(width: 100, height: 100))
        XCTAssertFalse(doc.undoManager.isDirty)

        let brush = BrushTool(configuration: BrushConfiguration(size: 10.0))
        brush.mouseDown(at: CGPoint(x: 20, y: 20), document: doc)
        brush.mouseUp(at: CGPoint(x: 20, y: 20), document: doc)
        XCTAssertTrue(doc.undoManager.isDirty)

        doc.undoManager.markSaved()
        XCTAssertFalse(doc.undoManager.isDirty)

        brush.mouseDown(at: CGPoint(x: 50, y: 50), document: doc)
        brush.mouseUp(at: CGPoint(x: 50, y: 50), document: doc)
        XCTAssertTrue(doc.undoManager.isDirty)

        // Undo back to save point
        doc.undoManager.undo(in: doc)
        XCTAssertFalse(doc.undoManager.isDirty)
    }

    // MARK: - F18 / Crop Tool Tests

    func testCrop9AnchorPositioning() {
        let oldSize = CGSize(width: 1000, height: 1000)
        let newSize = CGSize(width: 1200, height: 1400) // dw = 200, dh = 400

        let offsetTopLeft = CropAnchor.topLeft.contentOffset(oldSize: oldSize, newSize: newSize)
        XCTAssertEqual(offsetTopLeft.dx, 0)
        XCTAssertEqual(offsetTopLeft.dy, 0)

        let offsetCenter = CropAnchor.center.contentOffset(oldSize: oldSize, newSize: newSize)
        XCTAssertEqual(offsetCenter.dx, 100)
        XCTAssertEqual(offsetCenter.dy, 200)

        let offsetBottomRight = CropAnchor.bottomRight.contentOffset(oldSize: oldSize, newSize: newSize)
        XCTAssertEqual(offsetBottomRight.dx, 200)
        XCTAssertEqual(offsetBottomRight.dy, 400)
    }

    func testCropSparseTileRemapping() throws {
        let doc = try Document(canvasSize: CGSize(width: 600, height: 600))
        let layer = doc.activeLayer as! BitmapLayer
        layer.tileGrid.writePixel(x: 100, y: 100, color: SIMD4<UInt8>(255, 0, 0, 255))

        // Crop rect [50, 50] x [300, 300] -> pixel at (100, 100) should shift to (50, 50)
        let cropTool = CropTool()
        try cropTool.applyCrop(to: CGRect(x: 50, y: 50, width: 300, height: 300), document: doc)

        XCTAssertEqual(doc.width, 300)
        XCTAssertEqual(doc.height, 300)

        let shiftedPx = layer.tileGrid.readPixel(x: 50, y: 50)
        XCTAssertEqual(shiftedPx.x, 255)
        XCTAssertEqual(shiftedPx.w, 255)
    }

    func testCropAlignedShiftFastPath() throws {
        let doc = try Document(canvasSize: CGSize(width: 1024, height: 1024))
        let layer = doc.activeLayer as! BitmapLayer
        layer.tileGrid.writePixel(x: 100, y: 100, color: SIMD4<UInt8>(0, 255, 0, 255))

        // Expand canvas by exactly 512 in x with aligned shift dx = 512, dy = 0
        let remapped = CropTool.remapTileGrid(oldGrid: layer.tileGrid, newSize: CGSize(width: 1536, height: 1024), shift: (dx: 512, dy: 0))

        // Original tile (0, 0) should now be tile (1, 0)
        XCTAssertTrue(remapped.isTileAllocated(at: TileCoord(x: 1, y: 0)))
        let px = remapped.readPixel(x: 612, y: 100)
        XCTAssertEqual(px.y, 255)
    }

    func testCropPruningOutOfBoundsTiles() throws {
        let doc = try Document(canvasSize: CGSize(width: 1024, height: 1024))
        let layer = doc.activeLayer as! BitmapLayer
        // Allocate tile (1, 1) by writing at (800, 800)
        layer.tileGrid.writePixel(x: 800, y: 800, color: SIMD4<UInt8>(0, 0, 255, 255))
        XCTAssertTrue(layer.tileGrid.isTileAllocated(at: TileCoord(x: 1, y: 1)))

        // Crop canvas to 400x400 from top-left (leaving out (800, 800))
        let cropTool = CropTool()
        try cropTool.applyCrop(to: CGRect(x: 0, y: 0, width: 400, height: 400), document: doc)

        XCTAssertEqual(doc.width, 400)
        XCTAssertEqual(doc.height, 400)
        // Tile (1, 1) was completely pruned from memory
        XCTAssertFalse(layer.tileGrid.isTileAllocated(at: TileCoord(x: 1, y: 1)))
        XCTAssertEqual(layer.tileGrid.allocatedTileCount, 0)
    }

    func testCropUndoRoundTrip() throws {
        let doc = try Document(canvasSize: CGSize(width: 600, height: 600))
        let layer = doc.activeLayer as! BitmapLayer
        layer.tileGrid.writePixel(x: 100, y: 100, color: SIMD4<UInt8>(255, 128, 0, 255))

        let cropTool = CropTool()
        try cropTool.applyCrop(to: CGRect(x: 50, y: 50, width: 200, height: 200), document: doc)

        XCTAssertEqual(doc.width, 200)
        XCTAssertEqual(doc.height, 200)

        // Undo crop
        doc.undoManager.undo(in: doc)
        XCTAssertEqual(doc.width, 600)
        XCTAssertEqual(doc.height, 600)

        let originalPx = layer.tileGrid.readPixel(x: 100, y: 100)
        XCTAssertEqual(originalPx.x, 255)
        XCTAssertEqual(originalPx.y, 128)
    }

    func testInactiveLayerDeletionTracking() throws {
        let doc = try Document(canvasSize: CGSize(width: 200, height: 200))
        // doc starts with 1 layer (index 0)
        _ = doc.addLayer(BitmapLayer(name: "L1", bounds: doc.bounds)) // index 1
        _ = doc.addLayer(BitmapLayer(name: "L2", bounds: doc.bounds)) // index 2
        let l3 = doc.addLayer(BitmapLayer(name: "L3", bounds: doc.bounds)) // index 3

        doc.selectLayer(at: 3) // Active layer is L3 at index 3
        XCTAssertEqual(doc.activeLayerIndex, 3)

        // Delete INACTIVE layer at index 1
        try doc.deleteLayer(at: 1)

        // Since layer 1 was deleted, L3 should now be at index 2
        XCTAssertEqual(doc.activeLayerIndex, 2)
        XCTAssertEqual(doc.activeLayer.id, l3.id)
    }
}
