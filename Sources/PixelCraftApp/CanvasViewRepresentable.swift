import SwiftUI
import AppKit
import MetalKit
import PixelCraftEngine

public final class InteractiveCanvasView: NSView, MTKViewDelegate {
    public var document: Document
    public var activeToolType: ActiveToolType = .brush
    public var brushColor: NSColor = .black
    public var brushSize: CGFloat = 20.0
    public var brushOpacity: Float = 1.0
    public var brushFlow: Float = 1.0
    public var brushHardness: Float = 0.8
    public var onColorSampled: ((NSColor) -> Void)?
    public var onSelectionChanged: (() -> Void)?
    public var onFileDropped: ((URL, Bool) -> Void)?

    private var mtkView: MTKView!
    private var renderer: CanvasRenderer?
    private var isSpacePressed = false
    private var lastMouseLocation: NSPoint = .zero

    // Active tool instance
    private var currentTool: (any DrawingTool)?

    public init(document: Document) {
        self.document = document
        super.init(frame: .zero)
        setupMTKView()
        setupEventMonitoring()
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupMTKView() {
        let device = MetalContext.shared.device
        mtkView = MTKView(frame: bounds, device: device)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
        mtkView.autoresizingMask = [.width, .height]
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false
        mtkView.delegate = self

        renderer = CanvasRenderer(context: .shared)
        addSubview(mtkView)
    }

    public override func layout() {
        super.layout()
        mtkView.frame = bounds
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        setNeedsDisplayCanvas()
    }

    @MainActor
    public func draw(in view: MTKView) {
        renderer?.render(
            layers: document.layers,
            canvasSize: document.canvasSize,
            in: view,
            transform: document.viewportTransform
        )
    }

    // MARK: - Drag & Drop

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = extractFileURL(from: sender), ImageImporter.isSupported(url: url) else {
            return []
        }
        return .copy
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = extractFileURL(from: sender) else { return false }
        let isOption = NSEvent.modifierFlags.contains(.option)
        onFileDropped?(url, isOption)
        return true
    }

    private func extractFileURL(from sender: NSDraggingInfo) -> URL? {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = urls.first {
            return first
        }
        return nil
    }

    private func setupEventMonitoring() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 49 { // Space bar
                self.isSpacePressed = (event.type == .keyDown)
                if self.isSpacePressed {
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            } else if event.keyCode == 53 && event.type == .keyDown { // Escape
                self.currentTool?.cancel(document: self.document)
                self.currentTool = nil
                self.setNeedsDisplayCanvas()
            }
            return event
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    // MARK: - Mouse & Touch Input

    public override func mouseDown(with event: NSEvent) {
        lastMouseLocation = convert(event.locationInWindow, from: nil)

        if isSpacePressed || activeToolType == .pan {
            NSCursor.closedHand.set()
            return
        }

        let canvasPt = document.viewportTransform.screenToCanvas(lastMouseLocation)
        let tool = createToolInstance()
        currentTool = tool
        tool.mouseDown(at: canvasPt, document: document)
        setNeedsDisplayCanvas()
    }

    public override func mouseDragged(with event: NSEvent) {
        let currentLocation = convert(event.locationInWindow, from: nil)
        let delta = CGPoint(x: currentLocation.x - lastMouseLocation.x, y: currentLocation.y - lastMouseLocation.y)
        lastMouseLocation = currentLocation

        if isSpacePressed || activeToolType == .pan {
            document.viewportTransform.pan(by: delta)
            setNeedsDisplayCanvas()
            return
        }

        let canvasPt = document.viewportTransform.screenToCanvas(currentLocation)
        currentTool?.mouseDragged(to: canvasPt, document: document)
        setNeedsDisplayCanvas()
    }

    public override func mouseUp(with event: NSEvent) {
        if isSpacePressed || activeToolType == .pan {
            NSCursor.openHand.set()
            return
        }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let canvasPt = document.viewportTransform.screenToCanvas(currentLocation)
        currentTool?.mouseUp(at: canvasPt, document: document)
        currentTool = nil
        onSelectionChanged?()
        setNeedsDisplayCanvas()
    }

    public override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY
            let zoomFactor: Double = delta > 0 ? 1.05 : 0.95
            let mousePt = convert(event.locationInWindow, from: nil)
            document.viewportTransform.zoom(by: zoomFactor, aroundScreenPoint: mousePt)
        } else {
            let delta = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
            document.viewportTransform.pan(by: delta)
        }
        setNeedsDisplayCanvas()
    }

    public override func magnify(with event: NSEvent) {
        let zoomFactor = Double(1.0 + event.magnification)
        let mousePt = convert(event.locationInWindow, from: nil)
        document.viewportTransform.zoom(by: zoomFactor, aroundScreenPoint: mousePt)
        setNeedsDisplayCanvas()
    }

    private func createToolInstance() -> any DrawingTool {
        let rgb = brushColor.usingColorSpace(.deviceRGB) ?? .black
        let simColor = SIMD4<Float>(Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent), Float(rgb.alphaComponent))

        switch activeToolType {
        case .pan:
            return BrushTool()

        case .brush:
            let config = BrushConfiguration(
                shape: brushHardness > 0.5 ? .round : .soft,
                size: Float(brushSize),
                opacity: brushOpacity,
                flow: brushFlow,
                hardness: brushHardness,
                color: simColor
            )
            return BrushTool(configuration: config)

        case .eraser:
            let config = BrushConfiguration(
                shape: brushHardness > 0.5 ? .round : .soft,
                size: Float(brushSize),
                opacity: brushOpacity,
                flow: brushFlow,
                hardness: brushHardness
            )
            return EraserTool(configuration: config)

        case .fill:
            return FloodFillTool()

        case .gradient:
            return GradientTool()

        case .eyedropper:
            return EyedropperTool()

        case .marquee:
            return MarqueeSelectionTool()

        case .lasso:
            return LassoSelectionTool()

        case .crop:
            return CropTool()

        default:
            return BrushTool()
        }
    }

    public func setNeedsDisplayCanvas() {
        mtkView.setNeedsDisplay(mtkView.bounds)
    }
}

public enum ActiveToolType: String, CaseIterable, Identifiable, Sendable {
    case pan
    case brush
    case eraser
    case fill
    case gradient
    case eyedropper
    case marquee
    case lasso
    case crop
    case transform
    case liquify
    case backgroundRemoval
    case chromaKey
    case asciiArt

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .pan: return "hand.raised.fill"
        case .brush: return "paintbrush.pointed.fill"
        case .eraser: return "eraser.fill"
        case .fill: return "drop.fill"
        case .gradient: return "circle.lefthalf.filled"
        case .eyedropper: return "eyedropper.halffull"
        case .marquee: return "rectangle.dashed"
        case .lasso: return "lasso"
        case .crop: return "crop"
        case .transform: return "arrow.up.left.and.arrow.down.right"
        case .liquify: return "scribble.variable"
        case .backgroundRemoval: return "person.crop.circle.badge.minus"
        case .chromaKey: return "sparkles"
        case .asciiArt: return "character.textbox"
        }
    }

    public var title: String {
        switch self {
        case .pan: return "Hand / Pan"
        case .brush: return "Brush"
        case .eraser: return "Eraser"
        case .fill: return "Flood Fill"
        case .gradient: return "Gradient"
        case .eyedropper: return "Eyedropper"
        case .marquee: return "Marquee Selection"
        case .lasso: return "Lasso Selection"
        case .crop: return "Crop Tool"
        case .transform: return "Free Transform"
        case .liquify: return "GPU Liquify"
        case .backgroundRemoval: return "AI Background"
        case .chromaKey: return "Chroma Key"
        case .asciiArt: return "ASCII Generator"
        }
    }
}

public struct CanvasViewRepresentable: NSViewRepresentable {
    public var document: Document
    public var activeTool: ActiveToolType
    public var brushColor: NSColor
    public var brushSize: CGFloat
    public var brushOpacity: Float
    public var brushFlow: Float
    public var brushHardness: Float
    public var onColorSampled: ((NSColor) -> Void)?
    public var onFileDropped: ((URL, Bool) -> Void)?

    public init(
        document: Document,
        activeTool: ActiveToolType,
        brushColor: NSColor,
        brushSize: CGFloat,
        brushOpacity: Float,
        brushFlow: Float,
        brushHardness: Float,
        onColorSampled: ((NSColor) -> Void)? = nil,
        onFileDropped: ((URL, Bool) -> Void)? = nil
    ) {
        self.document = document
        self.activeTool = activeTool
        self.brushColor = brushColor
        self.brushSize = brushSize
        self.brushOpacity = brushOpacity
        self.brushFlow = brushFlow
        self.brushHardness = brushHardness
        self.onColorSampled = onColorSampled
        self.onFileDropped = onFileDropped
    }

    public func makeNSView(context: Context) -> InteractiveCanvasView {
        let view = InteractiveCanvasView(document: document)
        updateView(view)
        return view
    }

    public func updateNSView(_ nsView: InteractiveCanvasView, context: Context) {
        nsView.document = document
        updateView(nsView)
        nsView.setNeedsDisplayCanvas()
    }

    private func updateView(_ view: InteractiveCanvasView) {
        view.activeToolType = activeTool
        view.brushColor = brushColor
        view.brushSize = brushSize
        view.brushOpacity = brushOpacity
        view.brushFlow = brushFlow
        view.brushHardness = brushHardness
        view.onColorSampled = onColorSampled
        view.onFileDropped = onFileDropped
    }
}
