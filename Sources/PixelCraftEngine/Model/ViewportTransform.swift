import Foundation
import CoreGraphics
import simd

/// ViewportTransform manages pan, zoom, and coordinate projections between screen and canvas spaces.
public struct ViewportTransform: Sendable, Equatable {
    // MARK: - Constants
    
    public static let minZoom: Double = 0.05   // 5% zoom
    public static let maxZoom: Double = 32.0   // 3200% zoom
    public static let defaultZoom: Double = 1.0

    // MARK: - Properties
    
    /// Zoom scale factor, strictly clamped to [0.05, 32.0].
    public var zoom: Double {
        didSet {
            zoom = ViewportTransform.clampZoom(zoom)
        }
    }
    
    /// Pan translation offset in screen points.
    public var panOffset: CGPoint

    // MARK: - Initializer
    
    public init(zoom: Double = ViewportTransform.defaultZoom, panOffset: CGPoint = .zero) {
        self.zoom = ViewportTransform.clampZoom(zoom)
        self.panOffset = panOffset
    }
    
    public init(zoom: Float, pan: SIMD2<Float> = .zero) {
        self.zoom = ViewportTransform.clampZoom(Double(zoom))
        self.panOffset = CGPoint(x: CGFloat(pan.x), y: CGFloat(pan.y))
    }

    // MARK: - Zoom Clamping
    
    public static func clampZoom(_ value: Double) -> Double {
        min(max(value, minZoom), maxZoom)
    }
    
    public var zoomFloat: Float {
        Float(zoom)
    }
    
    public var panSIMD: SIMD2<Float> {
        SIMD2<Float>(Float(panOffset.x), Float(panOffset.y))
    }

    // MARK: - Coordinate Conversions
    
    /// Converts a point from canvas pixel coordinates to screen points.
    public func canvasToScreen(_ canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x * CGFloat(zoom) + panOffset.x,
            y: canvasPoint.y * CGFloat(zoom) + panOffset.y
        )
    }
    
    /// Converts a point from screen points to canvas pixel coordinates.
    public func screenToCanvas(_ screenPoint: CGPoint) -> CGPoint {
        let z = CGFloat(zoom)
        return CGPoint(
            x: (screenPoint.x - panOffset.x) / z,
            y: (screenPoint.y - panOffset.y) / z
        )
    }
    
    /// Converts a rectangle from canvas space to screen space.
    public func canvasToScreen(_ canvasRect: CGRect) -> CGRect {
        let origin = canvasToScreen(canvasRect.origin)
        let z = CGFloat(zoom)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: canvasRect.width * z,
            height: canvasRect.height * z
        )
    }
    
    /// Converts a rectangle from screen space to canvas space.
    public func screenToCanvas(_ screenRect: CGRect) -> CGRect {
        let origin = screenToCanvas(screenRect.origin)
        let z = CGFloat(zoom)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: screenRect.width / z,
            height: screenRect.height / z
        )
    }

    // MARK: - Interactive Transformations
    
    /// Zooms by multiplying the current scale by `factor`, maintaining the canvas position under `anchorScreenPoint`.
    public mutating func zoom(by factor: Double, aroundScreenPoint anchorScreenPoint: CGPoint) {
        let targetZoom = ViewportTransform.clampZoom(zoom * factor)
        guard targetZoom != zoom else { return }
        
        let oldZoom = zoom
        let sRatio = targetZoom / oldZoom
        
        panOffset = CGPoint(
            x: anchorScreenPoint.x - (anchorScreenPoint.x - panOffset.x) * CGFloat(sRatio),
            y: anchorScreenPoint.y - (anchorScreenPoint.y - panOffset.y) * CGFloat(sRatio)
        )
        zoom = targetZoom
    }
    
    /// Sets an absolute zoom scale, maintaining the canvas position under `anchorScreenPoint`.
    public mutating func setZoom(_ newZoom: Double, aroundScreenPoint anchorScreenPoint: CGPoint) {
        let targetZoom = ViewportTransform.clampZoom(newZoom)
        guard targetZoom != zoom else { return }
        
        let oldZoom = zoom
        let sRatio = targetZoom / oldZoom
        
        panOffset = CGPoint(
            x: anchorScreenPoint.x - (anchorScreenPoint.x - panOffset.x) * CGFloat(sRatio),
            y: anchorScreenPoint.y - (anchorScreenPoint.y - panOffset.y) * CGFloat(sRatio)
        )
        zoom = targetZoom
    }
    
    /// Pans the canvas by a screen-space delta.
    public mutating func pan(by delta: CGPoint) {
        panOffset.x += delta.x
        panOffset.y += delta.y
    }

    // MARK: - Visible Frustum Calculations
    
    /// Computes the unclipped canvas rectangle currently visible within the viewport dimensions.
    public func visibleCanvasRect(viewportSize: CGSize) -> CGRect {
        let screenRect = CGRect(origin: .zero, size: viewportSize)
        return screenToCanvas(screenRect)
    }
    
    /// Computes the canvas rectangle visible in the viewport, clipped to the canvas boundary.
    public func clippedVisibleCanvasRect(viewportSize: CGSize, canvasSize: CGSize) -> CGRect {
        let visible = visibleCanvasRect(viewportSize: viewportSize)
        let canvasBounds = CGRect(origin: .zero, size: canvasSize)
        return visible.intersection(canvasBounds)
    }

    // MARK: - Framing Utilities
    
    /// Configures zoom and pan to fit the entire canvas within `viewportSize` with an optional margin.
    public static func fitToViewport(canvasSize: CGSize, viewportSize: CGSize, margin: CGFloat = 20.0) -> ViewportTransform {
        guard canvasSize.width > 0 && canvasSize.height > 0 else {
            return ViewportTransform()
        }
        
        let availW = max(10.0, viewportSize.width - margin * 2.0)
        let availH = max(10.0, viewportSize.height - margin * 2.0)
        
        let scaleX = Double(availW / canvasSize.width)
        let scaleY = Double(availH / canvasSize.height)
        let fitZoom = ViewportTransform.clampZoom(min(scaleX, scaleY))
        
        let renderedW = canvasSize.width * CGFloat(fitZoom)
        let renderedH = canvasSize.height * CGFloat(fitZoom)
        
        let centeredPan = CGPoint(
            x: (viewportSize.width - renderedW) * 0.5,
            y: (viewportSize.height - renderedH) * 0.5
        )
        
        return ViewportTransform(zoom: fitZoom, panOffset: centeredPan)
    }
    
    /// Centers the canvas in the viewport at 100% zoom (1:1 pixel scale).
    public static func centerActualSize(canvasSize: CGSize, viewportSize: CGSize) -> ViewportTransform {
        let fitZoom: Double = 1.0
        let centeredPan = CGPoint(
            x: (viewportSize.width - canvasSize.width) * 0.5,
            y: (viewportSize.height - canvasSize.height) * 0.5
        )
        return ViewportTransform(zoom: fitZoom, panOffset: centeredPan)
    }

    // MARK: - Matrix Representations
    
    /// Returns a 3x3 affine transformation matrix representing this viewport transform for Metal shaders.
    public var metalMatrix: simd_float3x3 {
        let s = Float(zoom)
        let tx = Float(panOffset.x)
        let ty = Float(panOffset.y)
        
        return simd_float3x3(
            simd_float3(s,   0.0, 0.0),
            simd_float3(0.0, s,   0.0),
            simd_float3(tx,  ty,  1.0)
        )
    }
    
    /// Returns a CoreGraphics CGAffineTransform matching the viewport transform.
    public var affineTransform: CGAffineTransform {
        CGAffineTransform(translationX: panOffset.x, y: panOffset.y)
            .scaledBy(x: CGFloat(zoom), y: CGFloat(zoom))
    }
}
