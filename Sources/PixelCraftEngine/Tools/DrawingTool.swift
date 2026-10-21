import CoreGraphics
import Foundation

public enum ToolType: String, CaseIterable, Sendable, Codable {
    case brush
    case eraser
    case floodFill
    case gradient
    case eyedropper
    case marqueeRect
    case marqueeEllipse
    case lasso
    case crop
}

public protocol DrawingTool: AnyObject {
    var toolType: ToolType { get }

    /// Triggered on primary mouse down (canvas coordinates)
    func mouseDown(at canvasPoint: CGPoint, document: Document)

    /// Triggered on continuous mouse drag
    func mouseDragged(to canvasPoint: CGPoint, document: Document)

    /// Triggered on mouse up, committing changes and recording undo command
    func mouseUp(at canvasPoint: CGPoint, document: Document)

    /// Optional cancellation (e.g. Escape pressed during interaction)
    func cancel(document: Document)
}

public extension DrawingTool {
    func cancel(document: Document) {
        // Default empty implementation
    }
}
