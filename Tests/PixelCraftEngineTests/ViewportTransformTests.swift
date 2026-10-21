#if canImport(XCTest)
import XCTest
#endif
@testable import PixelCraftEngine

final class ViewportTransformTests: XCTestCase, @unchecked Sendable {
    
    // MARK: - Identity & Clamping Tests
    
    func testDefaultTransformIsIdentity() {
        let transform = ViewportTransform()
        XCTAssertEqual(transform.zoom, 1.0)
        XCTAssertEqual(transform.panOffset, .zero)
        
        let canvasPoint = CGPoint(x: 350, y: 720)
        XCTAssertEqual(transform.canvasToScreen(canvasPoint), canvasPoint)
        XCTAssertEqual(transform.screenToCanvas(canvasPoint), canvasPoint)
    }
    
    func testZoomClampingBoundaries() {
        var transform = ViewportTransform(zoom: 0.01)
        XCTAssertEqual(transform.zoom, 0.05, "Zoom below 0.05 must be clamped to 0.05")
        
        transform.zoom = 50.0
        XCTAssertEqual(transform.zoom, 32.0, "Zoom above 32.0 must be clamped to 32.0")
        
        transform.zoom = 2.5
        XCTAssertEqual(transform.zoom, 2.5)
    }

    // MARK: - Bidirectional Coordinate Conversion Roundtrips
    
    func testBidirectionalCoordinateRoundtrip() {
        let testZooms = [0.05, 0.25, 0.5, 1.0, 2.0, 8.0, 16.0, 32.0]
        let testPans = [CGPoint.zero, CGPoint(x: 100, y: -250), CGPoint(x: -800, y: 450)]
        let testPoints = [
            CGPoint.zero,
            CGPoint(x: 1920, y: 1080),
            CGPoint(x: 8192, y: 4320),
            CGPoint(x: 512.5, y: 1024.75)
        ]
        
        for z in testZooms {
            for pan in testPans {
                let transform = ViewportTransform(zoom: z, panOffset: pan)
                for pt in testPoints {
                    let screen = transform.canvasToScreen(pt)
                    let roundtrip = transform.screenToCanvas(screen)
                    
                    XCTAssertEqual(roundtrip.x, pt.x, accuracy: 0.0001, "Failed X roundtrip at zoom \(z), pan \(pan)")
                    XCTAssertEqual(roundtrip.y, pt.y, accuracy: 0.0001, "Failed Y roundtrip at zoom \(z), pan \(pan)")
                }
            }
        }
    }

    // MARK: - Stationary Anchor Zoom Invariant
    
    func testStationaryAnchorZoomInvariant() {
        var transform = ViewportTransform(zoom: 1.0, panOffset: CGPoint(x: 100, y: 100))
        let cursorScreenPoint = CGPoint(x: 500, y: 400)
        
        // Find canvas point under cursor before zoom
        let canvasPointUnderCursor = transform.screenToCanvas(cursorScreenPoint)
        
        // Zoom in by 2.0x around the cursor
        transform.zoom(by: 2.0, aroundScreenPoint: cursorScreenPoint)
        XCTAssertEqual(transform.zoom, 2.0)
        
        // Verify that the exact same canvas point is still directly beneath the cursor in screen space
        let screenPointAfterZoom = transform.canvasToScreen(canvasPointUnderCursor)
        XCTAssertEqual(screenPointAfterZoom.x, cursorScreenPoint.x, accuracy: 0.0001)
        XCTAssertEqual(screenPointAfterZoom.y, cursorScreenPoint.y, accuracy: 0.0001)
        
        // Zoom out by 0.5x around the cursor
        transform.zoom(by: 0.5, aroundScreenPoint: cursorScreenPoint)
        XCTAssertEqual(transform.zoom, 1.0)
        
        let screenPointAfterZoomOut = transform.canvasToScreen(canvasPointUnderCursor)
        XCTAssertEqual(screenPointAfterZoomOut.x, cursorScreenPoint.x, accuracy: 0.0001)
        XCTAssertEqual(screenPointAfterZoomOut.y, cursorScreenPoint.y, accuracy: 0.0001)
    }

    // MARK: - Visible Frustum & Culling Tests
    
    func testVisibleCanvasRectCalculation() {
        let viewportSize = CGSize(width: 800, height: 600)
        let transform = ViewportTransform(zoom: 2.0, panOffset: CGPoint(x: -200, y: -100))
        
        let visibleRect = transform.visibleCanvasRect(viewportSize: viewportSize)
        XCTAssertEqual(visibleRect.origin.x, 100.0, accuracy: 0.0001)
        XCTAssertEqual(visibleRect.origin.y, 50.0, accuracy: 0.0001)
        XCTAssertEqual(visibleRect.width, 400.0, accuracy: 0.0001)
        XCTAssertEqual(visibleRect.height, 300.0, accuracy: 0.0001)
    }
    
    func testClippedVisibleCanvasRectOn8KCanvas() {
        let viewportSize = CGSize(width: 1920, height: 1080)
        let canvasSize = CGSize(width: 8192, height: 4320)
        
        let transform = ViewportTransform(zoom: 1.0, panOffset: CGPoint(x: 500, y: 300))
        
        let clipped = transform.clippedVisibleCanvasRect(viewportSize: viewportSize, canvasSize: canvasSize)
        XCTAssertGreaterThanOrEqual(clipped.minX, 0.0)
        XCTAssertGreaterThanOrEqual(clipped.minY, 0.0)
        XCTAssertLessThanOrEqual(clipped.maxX, canvasSize.width)
        XCTAssertLessThanOrEqual(clipped.maxY, canvasSize.height)
    }

    // MARK: - Framing Utilities Tests
    
    func testFitToViewportCalculations() {
        let canvasSize = CGSize(width: 8192, height: 4320)
        let viewportSize = CGSize(width: 1920, height: 1080)
        let margin: CGFloat = 0.0
        
        let fitTransform = ViewportTransform.fitToViewport(canvasSize: canvasSize, viewportSize: viewportSize, margin: margin)
        
        XCTAssertEqual(fitTransform.zoom, 0.234375, accuracy: 0.0001)
        XCTAssertEqual(fitTransform.panOffset.x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(fitTransform.panOffset.y, 33.75, accuracy: 0.0001)
    }
    
    func testCenterActualSizeCalculations() {
        let canvasSize = CGSize(width: 1000, height: 800)
        let viewportSize = CGSize(width: 1200, height: 1000)
        
        let actual = ViewportTransform.centerActualSize(canvasSize: canvasSize, viewportSize: viewportSize)
        XCTAssertEqual(actual.zoom, 1.0)
        XCTAssertEqual(actual.panOffset.x, 100.0)
        XCTAssertEqual(actual.panOffset.y, 100.0)
    }
}
