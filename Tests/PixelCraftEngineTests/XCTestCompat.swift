@_exported import Foundation
@_exported import CoreGraphics
@_exported import simd

#if canImport(XCTest)
@_exported import XCTest
#else

open class XCTestCase: @unchecked Sendable {
    public init() {}
    open func setUp() {}
    open func tearDown() {}
}

public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let va = try a()
        let vb = try b()
        if va != vb {
            let msg = message()
            fatalError("XCTAssertEqual failed: (\(va)) is not equal to (\(vb)) \(msg) at \(file):\(line)")
        }
    } catch {
        fatalError("XCTAssertEqual threw error: \(error) at \(file):\(line)")
    }
}

public func XCTAssertEqual<T: FloatingPoint>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, accuracy: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let va = try a()
        let vb = try b()
        if abs(va - vb) > accuracy {
            let msg = message()
            fatalError("XCTAssertEqual failed: (\(va)) is not equal to (\(vb)) within accuracy \(accuracy) \(msg) at \(file):\(line)")
        }
    } catch {
        fatalError("XCTAssertEqual threw error: \(error) at \(file):\(line)")
    }
}

public func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let va = try a()
        let vb = try b()
        if va == vb {
            let msg = message()
            fatalError("XCTAssertNotEqual failed: (\(va)) is equal to (\(vb)) \(msg) at \(file):\(line)")
        }
    } catch {
        fatalError("XCTAssertNotEqual threw error: \(error) at \(file):\(line)")
    }
}

public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let val = try expression()
        if !val {
            let msg = message()
            fatalError("XCTAssertTrue failed: \(msg) at \(file):\(line)")
        }
    } catch {
        fatalError("XCTAssertTrue threw error: \(error) at \(file):\(line)")
    }
}

public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let val = try expression()
        if val {
            let msg = message()
            fatalError("XCTAssertFalse failed: \(msg) at \(file):\(line)")
        }
    } catch {
        fatalError("XCTAssertFalse threw error: \(error) at \(file):\(line)")
    }
}

public func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let va = try a()
        let vb = try b()
        if !(va > vb) {
            fatalError("XCTAssertGreaterThan failed: (\(va)) not > (\(vb)) at \(file):\(line)")
        }
    } catch {
        fatalError("XCTAssertGreaterThan threw error: \(error) at \(file):\(line)")
    }
}

public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let va = try a()
        let vb = try b()
        if !(va >= vb) {
            fatalError("XCTAssertGreaterThanOrEqual failed: (\(va)) not >= (\(vb)) at \(file):\(line)")
        }
    } catch {
        fatalError("XCTAssertGreaterThanOrEqual threw error: \(error) at \(file):\(line)")
    }
}

public func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let va = try a()
        let vb = try b()
        if !(va <= vb) {
            fatalError("XCTAssertLessThanOrEqual failed: (\(va)) not <= (\(vb)) at \(file):\(line)")
        }
    } catch {
        fatalError("XCTAssertLessThanOrEqual threw error: \(error) at \(file):\(line)")
    }
}

public func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let va = try a()
        let vb = try b()
        if !(va < vb) {
            fatalError("XCTAssertLessThan failed: (\(va)) not < (\(vb)) at \(file):\(line)")
        }
    } catch {
        fatalError("XCTAssertLessThan threw error: \(error) at \(file):\(line)")
    }
}

public func XCTAssertNotNil(_ a: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let val = try a()
        if val == nil {
            fatalError("XCTAssertNotNil failed: \(message()) at \(file):\(line)")
        }
    } catch {
        fatalError("XCTAssertNotNil threw error: \(error) at \(file):\(line)")
    }
}

public func XCTAssertNil(_ a: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let val = try a()
        if val != nil {
            fatalError("XCTAssertNil failed: \(message()) at \(file):\(line)")
        }
    } catch {
        fatalError("XCTAssertNil threw error: \(error) at \(file):\(line)")
    }
}

public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", _ errorHandler: (Error) -> Void = { _ in }, file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try expression()
        fatalError("XCTAssertThrowsError failed: did not throw error at \(file):\(line)")
    } catch {
        errorHandler(error)
    }
}

public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    fatalError("XCTFail: \(message) at \(file):\(line)")
}

public struct XCTUnwrapError: Error {}
public func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    if let val = try expression() {
        return val
    }
    fatalError("XCTUnwrap failed: expected non-nil value. \(message()) at \(file):\(line)")
}

@objc(PixelCraftTestDriver)
public final class PixelCraftTestDriver: NSObject, @unchecked Sendable {
    @objc public static func runTests() {
        _ = runAllEngineTests()
    }
}

@discardableResult
public func runAllEngineTests() -> Bool {
    print("Running PixelCraftEngine test suite (CommandLineTools environment)...")
    let start = Date()
    var count = 0
    
    func run(_ name: String, _ testBlock: () throws -> Void) {
        do {
            try testBlock()
            count += 1
            print("  Test Case '-\(name)' passed.")
        } catch {
            fatalError("Test \(name) failed with error: \(error)")
        }
    }
    
    // DocumentTests
    let docTests = DocumentTests()
    run("DocumentTests.testDefaultDocumentCreation") { try docTests.testDefaultDocumentCreation() }
    run("DocumentTests.test8KCanvasResolutionSupport") { try docTests.test8KCanvasResolutionSupport() }
    run("DocumentTests.testBoundaryValidationRejectsInvalidDimensions") { docTests.testBoundaryValidationRejectsInvalidDimensions() }
    run("DocumentTests.testAddLayerIncrementsCountAndUpdatesActiveIndex") { try docTests.testAddLayerIncrementsCountAndUpdatesActiveIndex() }
    run("DocumentTests.testDuplicateLayerClonesPropertiesAndInsertsAbove") { try docTests.testDuplicateLayerClonesPropertiesAndInsertsAbove() }
    run("DocumentTests.testDeleteLayerSafetyInvariantNeverAllowsZeroLayers") { try docTests.testDeleteLayerSafetyInvariantNeverAllowsZeroLayers() }
    run("DocumentTests.testDeleteLayerWithMultipleLayers") { try docTests.testDeleteLayerWithMultipleLayers() }
    run("DocumentTests.testMoveLayerReordering") { try docTests.testMoveLayerReordering() }
    run("DocumentTests.testLayerStackCapacity10PlusLayers") { try docTests.testLayerStackCapacity10PlusLayers() }
    run("DocumentTests.testMergeDownOperation") { try docTests.testMergeDownOperation() }
    run("DocumentTests.testMergeVisibleOperation") { try docTests.testMergeVisibleOperation() }
    run("DocumentTests.testFlattenOperation") { try docTests.testFlattenOperation() }

    // ViewportTransformTests
    let vpTests = ViewportTransformTests()
    run("ViewportTransformTests.testDefaultTransformIsIdentity") { vpTests.testDefaultTransformIsIdentity() }
    run("ViewportTransformTests.testZoomClampingBoundaries") { vpTests.testZoomClampingBoundaries() }
    run("ViewportTransformTests.testBidirectionalCoordinateRoundtrip") { vpTests.testBidirectionalCoordinateRoundtrip() }
    run("ViewportTransformTests.testStationaryAnchorZoomInvariant") { vpTests.testStationaryAnchorZoomInvariant() }
    run("ViewportTransformTests.testVisibleCanvasRectCalculation") { vpTests.testVisibleCanvasRectCalculation() }
    run("ViewportTransformTests.testClippedVisibleCanvasRectOn8KCanvas") { vpTests.testClippedVisibleCanvasRectOn8KCanvas() }
    run("ViewportTransformTests.testFitToViewportCalculations") { vpTests.testFitToViewportCalculations() }
    run("ViewportTransformTests.testCenterActualSizeCalculations") { vpTests.testCenterActualSizeCalculations() }

    // SparseTileGridTests
    let gridTests = SparseTileGridTests()
    run("SparseTileGridTests.testSparseTileGridMemoryConservation") { gridTests.testSparseTileGridMemoryConservation() }
    run("SparseTileGridTests.testSparseTileGridBoundaryCalculations") { gridTests.testSparseTileGridBoundaryCalculations() }
    run("SparseTileGridTests.testPixelReadWriteFidelity") { gridTests.testPixelReadWriteFidelity() }
    run("SparseTileGridTests.testDirtyTileTracking") { gridTests.testDirtyTileTracking() }
    run("SparseTileGridTests.testDeepCopyTileGrid") { gridTests.testDeepCopyTileGrid() }
    run("SparseTileGridTests.testExtractAndLoadTileData") { gridTests.testExtractAndLoadTileData() }
    run("SparseTileGridTests.testSolidFill") { gridTests.testSolidFill() }
    run("SparseTileGridTests.testContentBounds") { gridTests.testContentBounds() }

    // BlendModeTests
    let blendTests = BlendModeTests()
    run("BlendModeTests.testMidGrayCoreBlendModes") { blendTests.testMidGrayCoreBlendModes() }
    run("BlendModeTests.testAsymmetricBlendVectors") { blendTests.testAsymmetricBlendVectors() }
    run("BlendModeTests.testOverlayHardLightDuality") { blendTests.testOverlayHardLightDuality() }
    run("BlendModeTests.testExtendedBlendModes") { blendTests.testExtendedBlendModes() }
    run("BlendModeTests.testSemiTransparentCompositingVectors") { blendTests.testSemiTransparentCompositingVectors() }
    run("BlendModeTests.testLockAlphaPreservesBackdropAlpha") { blendTests.testLockAlphaPreservesBackdropAlpha() }

    // LayerCompositingTests
    let compTests = LayerCompositingTests()
    run("LayerCompositingTests.testPolymorphicLayerStackCoexistence") { try compTests.testPolymorphicLayerStackCoexistence() }
    run("LayerCompositingTests.testLayerOpacityClampingAndAttribution") { compTests.testLayerOpacityClampingAndAttribution() }
    run("LayerCompositingTests.testLayerVisibilityToggling") { try compTests.testLayerVisibilityToggling() }
    run("LayerCompositingTests.testTextLayerRasterizationAndTileStorage") { compTests.testTextLayerRasterizationAndTileStorage() }
    run("LayerCompositingTests.testHeadlessMetalOffscreenCompositing") { try compTests.testHeadlessMetalOffscreenCompositing() }
    run("LayerCompositingTests.testHeadlessScreenBlendModeOffscreen") { try compTests.testHeadlessScreenBlendModeOffscreen() }

    // DrawingToolsTests
    let drawTests = DrawingToolsTests()
    run("DrawingToolsTests.testRoundBrushStampGeometry") { try drawTests.testRoundBrushStampGeometry() }
    run("DrawingToolsTests.testSquareBrushStampGeometry") { try drawTests.testSquareBrushStampGeometry() }
    run("DrawingToolsTests.testSoftBrushRadialFalloff") { try drawTests.testSoftBrushRadialFalloff() }
    run("DrawingToolsTests.testCatmullRomSplineSmoothing") { try drawTests.testCatmullRomSplineSmoothing() }
    run("DrawingToolsTests.testBrushSpacingAccumulator") { try drawTests.testBrushSpacingAccumulator() }
    run("DrawingToolsTests.testBrushLockAlphaInvariant") { try drawTests.testBrushLockAlphaInvariant() }
    run("DrawingToolsTests.testBrushSelectionConstraint") { try drawTests.testBrushSelectionConstraint() }
    run("DrawingToolsTests.testBrushCrossTileBoundary") { try drawTests.testBrushCrossTileBoundary() }
    run("DrawingToolsTests.testEraserAttenuatesAlpha") { try drawTests.testEraserAttenuatesAlpha() }
    run("DrawingToolsTests.testEraserLockAlphaInvariant") { try drawTests.testEraserLockAlphaInvariant() }
    run("DrawingToolsTests.testEraserTilePruning") { try drawTests.testEraserTilePruning() }
    run("DrawingToolsTests.testContiguousScanlineFill") { try drawTests.testContiguousScanlineFill() }
    run("DrawingToolsTests.testFillColorToleranceEuclidean") { try drawTests.testFillColorToleranceEuclidean() }
    run("DrawingToolsTests.testGlobalFillNonContiguous") { try drawTests.testGlobalFillNonContiguous() }
    run("DrawingToolsTests.testFillNoCallStackOverflow") { try drawTests.testFillNoCallStackOverflow() }
    run("DrawingToolsTests.testFillSelectionBoundary") { try drawTests.testFillSelectionBoundary() }
    run("DrawingToolsTests.testLinearGradienttParam") { try drawTests.testLinearGradienttParam() }
    run("DrawingToolsTests.testRadialGradienttParam") { try drawTests.testRadialGradienttParam() }
    run("DrawingToolsTests.testSpreadModesPadRepeatReflect") { drawTests.testSpreadModesPadRepeatReflect() }
    run("DrawingToolsTests.testBayerDitheringEliminatesBanding") { try drawTests.testBayerDitheringEliminatesBanding() }
    run("DrawingToolsTests.testPointSampleSingleLayer") { try drawTests.testPointSampleSingleLayer() }
    run("DrawingToolsTests.testPointSampleComposited") { try drawTests.testPointSampleComposited() }
    run("DrawingToolsTests.testAverage3x3AlphaWeighted") { try drawTests.testAverage3x3AlphaWeighted() }
    run("DrawingToolsTests.testColorFormatStrings") { try drawTests.testColorFormatStrings() }

    // SelectionAndUndoTests
    let selTests = SelectionAndUndoTests()
    run("SelectionAndUndoTests.testRectangularMarqueeGeometry") { try selTests.testRectangularMarqueeGeometry() }
    run("SelectionAndUndoTests.testEllipticalMarqueeGeometry") { try selTests.testEllipticalMarqueeGeometry() }
    run("SelectionAndUndoTests.testMarqueeShiftAspectRatioConstraint") { try selTests.testMarqueeShiftAspectRatioConstraint() }
    run("SelectionAndUndoTests.testMarqueeOptionCenterExpansion") { try selTests.testMarqueeOptionCenterExpansion() }
    run("SelectionAndUndoTests.testMarqueeSingleClickDeselect") { try selTests.testMarqueeSingleClickDeselect() }
    run("SelectionAndUndoTests.testFreehandLassoClosure") { try selTests.testFreehandLassoClosure() }
    run("SelectionAndUndoTests.testPolygonalLassoClosureEvents") { try selTests.testPolygonalLassoClosureEvents() }
    run("SelectionAndUndoTests.testPolygonalLassoEscapeCancellation") { try selTests.testPolygonalLassoEscapeCancellation() }
    run("SelectionAndUndoTests.testPolygonalLassoDeleteVertex") { try selTests.testPolygonalLassoDeleteVertex() }
    run("SelectionAndUndoTests.testSelectionModeUnion") { try selTests.testSelectionModeUnion() }
    run("SelectionAndUndoTests.testSelectionModeSubtract") { try selTests.testSelectionModeSubtract() }
    run("SelectionAndUndoTests.testSelectionModeIntersect") { try selTests.testSelectionModeIntersect() }
    run("SelectionAndUndoTests.testSelectionModeDisjointIntersect") { try selTests.testSelectionModeDisjointIntersect() }
    run("SelectionAndUndoTests.testGaussianFeatherSeparable") { try selTests.testGaussianFeatherSeparable() }
    run("SelectionAndUndoTests.testSparseMaskGridMemoryEfficiency") { selTests.testSparseMaskGridMemoryEfficiency() }
    run("SelectionAndUndoTests.testSelectAllAndDeselect") { selTests.testSelectAllAndDeselect() }
    run("SelectionAndUndoTests.testSelectionInversion") { selTests.testSelectionInversion() }
    run("SelectionAndUndoTests.testSelectionBounds") { selTests.testSelectionBounds() }
    run("SelectionAndUndoTests.testMarchingSquaresContourClosedPath") { selTests.testMarchingSquaresContourClosedPath() }
    run("SelectionAndUndoTests.testMarchingSquaresMultipleIslands") { selTests.testMarchingSquaresMultipleIslands() }
    run("SelectionAndUndoTests.testTileDeltaMemorySavings") { try selTests.testTileDeltaMemorySavings() }
    run("SelectionAndUndoTests.testUndoRedoStrokeFidelity") { try selTests.testUndoRedoStrokeFidelity() }
    run("SelectionAndUndoTests.testUndoTileAllocationRecovery") { try selTests.testUndoTileAllocationRecovery() }
    run("SelectionAndUndoTests.testUndoStackCapacityLimit") { selTests.testUndoStackCapacityLimit() }
    run("SelectionAndUndoTests.testUndoGroupingAtomic") { try selTests.testUndoGroupingAtomic() }
    run("SelectionAndUndoTests.testDocumentDirtyStateTracking") { try selTests.testDocumentDirtyStateTracking() }
    run("SelectionAndUndoTests.testCrop9AnchorPositioning") { selTests.testCrop9AnchorPositioning() }
    run("SelectionAndUndoTests.testCropSparseTileRemapping") { try selTests.testCropSparseTileRemapping() }
    run("SelectionAndUndoTests.testCropAlignedShiftFastPath") { try selTests.testCropAlignedShiftFastPath() }
    run("SelectionAndUndoTests.testCropPruningOutOfBoundsTiles") { try selTests.testCropPruningOutOfBoundsTiles() }
    run("SelectionAndUndoTests.testCropUndoRoundTrip") { try selTests.testCropUndoRoundTrip() }
    run("SelectionAndUndoTests.testInactiveLayerDeletionTracking") { try selTests.testInactiveLayerDeletionTracking() }

    let transTests = TransformAndLiquifyTests()
    run("TransformAndLiquifyTests.testAffineTransformMatrix") { try transTests.testAffineTransformMatrix() }
    run("TransformAndLiquifyTests.testBicubicInterpolationAccuracy") { try transTests.testBicubicInterpolationAccuracy() }
    run("TransformAndLiquifyTests.testPerspectiveHomographySquareToQuad") { try transTests.testPerspectiveHomographySquareToQuad() }
    run("TransformAndLiquifyTests.testWarpMeshEvaluation") { try transTests.testWarpMeshEvaluation() }
    run("TransformAndLiquifyTests.testPixelateFilterSquareAndHexagonal") { try transTests.testPixelateFilterSquareAndHexagonal() }
    run("TransformAndLiquifyTests.testLiquifyDisplacementMapAndRender") { try transTests.testLiquifyDisplacementMapAndRender() }

    let vkTests = VisionAndChromaKeyTests()
    run("VisionAndChromaKeyTests.testRGBToCIELABConversion") { try vkTests.testRGBToCIELABConversion() }
    run("VisionAndChromaKeyTests.testChromaKeyGreenScreenRemoval") { try vkTests.testChromaKeyGreenScreenRemoval() }
    run("VisionAndChromaKeyTests.testChromaKeySpillSuppression") { try vkTests.testChromaKeySpillSuppression() }
    run("VisionAndChromaKeyTests.testVisionGuidedFilterEdgeRefinement") { try vkTests.testVisionGuidedFilterEdgeRefinement() }

    let asciiTests = ASCIIGeneratorTests()
    run("ASCIIGeneratorTests.testStandardCharacterMapping") { try asciiTests.testStandardCharacterMapping() }
    run("ASCIIGeneratorTests.testExtendedUnicodeCharacterSet") { try asciiTests.testExtendedUnicodeCharacterSet() }
    run("ASCIIGeneratorTests.testCustomCharacterSet") { try asciiTests.testCustomCharacterSet() }
    run("ASCIIGeneratorTests.testBakeToLayers") { try asciiTests.testBakeToLayers() }

    let ioTests = FileIOAndExportTests()
    run("FileIOAndExportTests.testPSDEncodingAndHeader") { try ioTests.testPSDEncodingAndHeader() }
    run("FileIOAndExportTests.testPCProFileWrapperRoundtrip") { try ioTests.testPCProFileWrapperRoundtrip() }
    run("FileIOAndExportTests.testImageExportsPNGAndJPEG") { try ioTests.testImageExportsPNGAndJPEG() }
    run("FileIOAndExportTests.testImageImporterDecodePNG") { try ioTests.testImageImporterDecodePNG() }
    run("FileIOAndExportTests.testImageImporterCreateDocumentAdaptsCanvasSizeAndAspectRatio") { try ioTests.testImageImporterCreateDocumentAdaptsCanvasSizeAndAspectRatio() }
    run("FileIOAndExportTests.testImageImporterCreateLayerCentered") { try ioTests.testImageImporterCreateLayerCentered() }
    run("FileIOAndExportTests.testDocumentReplaceInPlace") { try ioTests.testDocumentReplaceInPlace() }

    let elapsed = Date().timeIntervalSince(start)
    print("Executed \(count) tests, with 0 failures (0 unexpected) in \(String(format: "%.3f", elapsed)) seconds")
    return true
}

#endif
