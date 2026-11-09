import SwiftUI
import AppKit
import MetalKit
import PixelCraftEngine

// MARK: - Interactive Canvas

public final class InteractiveCanvasView: NSView, MTKViewDelegate {
    let document: Document
    let state: EditorState
    var onFileDropped: ((URL, Bool) -> Void)?

    private var mtkView: MTKView!
    private var overlay: CanvasOverlayView!
    private var renderer: CanvasRenderer?

    private var isSpacePressed = false
    private var isPanning = false
    private var lastMouseLocation: NSPoint = .zero
    private var currentTool: (any DrawingTool)?
    private var keyMonitor: Any?
    private var didInitialFit = false
    private var antsTimer: Timer?
    private var trackingAreaRef: NSTrackingArea?

    // Feedback for the overlay (canvas coordinates)
    private(set) var dragStartCanvas: CGPoint?
    private(set) var dragCurrentCanvas: CGPoint?
    private(set) var hoverCanvasPoint: CGPoint?
    private(set) var antsPhase: CGFloat = 0

    // Move tool session
    private var moveBefore: SparseTileGrid?
    private var moveLayer: BitmapLayer?
    private var moveStartCanvas: CGPoint = .zero
    private var moveLastShift: (dx: Int, dy: Int) = (0, 0)

    init(document: Document, state: EditorState) {
        self.document = document
        self.state = state
        super.init(frame: .zero)
        setupMTKView()
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Top-left origin, matching canvas pixel coordinates and the Metal vertex shader.
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    private func setupMTKView() {
        let device = MetalContext.shared.device
        mtkView = MTKView(frame: bounds, device: device)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
        mtkView.autoresizingMask = [.width, .height]
        // Draw only on demand (setNeedsDisplay), never in a continuous 60/120 Hz loop.
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true
        mtkView.delegate = self
        renderer = CanvasRenderer(context: .shared)
        addSubview(mtkView)

        overlay = CanvasOverlayView(frame: bounds)
        overlay.canvas = self
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)
    }

    public override func layout() {
        super.layout()
        handleResize()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        handleResize()
    }

    private func handleResize() {
        guard mtkView != nil, overlay != nil else { return } // may run before setup finishes
        mtkView.frame = bounds
        overlay.frame = bounds
        if bounds.width > 10 && bounds.height > 10 {
            state.viewportSize = bounds.size
            if !didInitialFit {
                didInitialFit = true
                // Defer: publishing state changes from inside a layout pass upsets SwiftUI.
                Task { @MainActor [weak self] in
                    self?.state.fitToScreen()
                }
            }
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installKeyMonitor()
            state.canvasView = self
            window?.makeFirstResponder(self)
        } else if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
            antsTimer?.invalidate()
            antsTimer = nil
        }
    }

    // MARK: Rendering

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

    public func setNeedsDisplayCanvas() {
        mtkView.needsDisplay = true
        overlay.needsDisplay = true
        updateAntsTimer()
    }

    /// Called when the tool or the open generator changes.
    func toolDidChange() {
        if let tool = currentTool {
            tool.cancel(document: document)
            currentTool = nil
        }
        dragStartCanvas = nil
        dragCurrentCanvas = nil
        window?.invalidateCursorRects(for: self)
        updateCursor()
        setNeedsDisplayCanvas()
    }

    private func updateAntsTimer() {
        let needsTimer = state.selectionOutline != nil
        if needsTimer && antsTimer == nil {
            let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.antsPhase = (self.antsPhase + 1).truncatingRemainder(dividingBy: 8)
                    self.overlay.needsDisplay = true
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            antsTimer = timer
        } else if !needsTimer, let timer = antsTimer {
            timer.invalidate()
            antsTimer = nil
        }
    }

    // MARK: Interaction mode

    enum Mode {
        case pan
        case liquify
        case chromaSample
        case tool(CanvasTool)
    }

    var mode: Mode {
        if isSpacePressed { return .pan }
        switch state.openGenerator {
        case .liquify: return .liquify
        case .chromaKey: return .chromaSample
        default: break
        }
        return state.tool == .hand ? .pan : .tool(state.tool)
    }

    /// Radius (canvas px) of the circular brush cursor, if the current mode has one.
    var brushCursorRadius: CGFloat? {
        switch mode {
        case .liquify: return CGFloat(state.liquifySize / 2)
        case .tool(.brush): return CGFloat(state.brushSize / 2)
        case .tool(.eraser): return CGFloat(state.eraserSize / 2)
        default: return nil
        }
    }

    private func updateCursor() {
        switch mode {
        case .pan: (isPanning ? NSCursor.closedHand : NSCursor.openHand).set()
        case .liquify, .tool(.brush), .tool(.eraser): NSCursor.crosshair.set()
        case .chromaSample, .tool(.eyedropper), .tool(.fill): NSCursor.crosshair.set()
        case .tool(.move): NSCursor.openHand.set()
        default: NSCursor.crosshair.set()
        }
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    /// Returns true when the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window = self.window, event.window === window else { return false }
        // Never steal keys from text fields.
        if window.firstResponder is NSText { return false }

        if event.keyCode == 49 { // Space
            let down = event.type == .keyDown
            if down != isSpacePressed {
                isSpacePressed = down
                updateCursor()
            }
            return true
        }

        guard event.type == .keyDown else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 53: // Escape
            if let tool = currentTool {
                tool.cancel(document: document)
                currentTool = nil
                dragStartCanvas = nil
                setNeedsDisplayCanvas()
                return true
            }
            if state.hasPendingChanges {
                state.cancelPending()
                return true
            }
            if state.openGenerator != nil {
                state.closeGenerator()
                return true
            }
            return false
        case 36, 76: // Return / Enter
            if let lasso = currentTool as? LassoSelectionTool {
                lasso.handleEnterKey(document: document)
                currentTool = nil
                state.refreshSelectionOutline()
                return true
            }
            if state.hasPendingChanges {
                state.commitPending()
                return true
            }
            return false
        case 51, 117: // Delete / Forward delete: clear selection pixels on the active layer
            if mods.isEmpty, let mask = document.selectionMask, mask.hasActiveSelection {
                clearSelectedPixels()
                return true
            }
            return false
        default:
            break
        }

        // Single-letter tool shortcuts, [ / ] brush size, X swaps colors.
        guard mods.subtracting([.shift, .capsLock]).isEmpty,
              let chars = event.charactersIgnoringModifiers?.lowercased(),
              let ch = chars.first else { return false }

        if ch == "x" {
            state.swapColors()
            return true
        }
        if ch == "[" || ch == "]" {
            let factor = ch == "]" ? 1.15 : 1 / 1.15
            switch mode {
            case .liquify: state.liquifySize = max(10, min(600, state.liquifySize * factor))
            case .tool(.eraser): state.eraserSize = max(1, min(500, state.eraserSize * factor))
            default: state.brushSize = max(1, min(500, state.brushSize * factor))
            }
            overlay.needsDisplay = true
            return true
        }
        if let tool = CanvasTool.allCases.first(where: { $0.shortcut == ch }) {
            if state.openGenerator != nil { state.closeGenerator() }
            state.tool = tool
            return true
        }
        return false
    }

    private func clearSelectedPixels() {
        guard let layer = document.activeLayer as? BitmapLayer, !layer.isLocked,
              let mask = document.selectionMask else { return }
        let result = layer.tileGrid.duplicate()
        for coord in result.allAllocatedCoordinates() where mask.maskGrid.isTileAllocated(at: coord) {
            let ox = coord.x * SparseTileGrid.tileSize
            let oy = coord.y * SparseTileGrid.tileSize
            for ly in 0..<SparseTileGrid.tileSize {
                for lx in 0..<SparseTileGrid.tileSize {
                    let x = ox + lx, y = oy + ly
                    let m = mask.alphaAt(x: x, y: y)
                    guard m > 0 else { continue }
                    var p = result.readPixel(x: x, y: y)
                    guard p.w > 0 else { continue }
                    p.w = UInt8((UInt32(p.w) * UInt32(255 - m)) / 255)
                    result.writePixel(x: x, y: y, color: p)
                }
            }
        }
        document.commitGridEdit(layer: layer, newGrid: result, actionName: "Clear")
        setNeedsDisplayCanvas()
    }

    // MARK: Drag & Drop

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

    // MARK: Tracking (brush cursor)

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingAreaRef {
            removeTrackingArea(old)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    public override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        hoverCanvasPoint = document.viewportTransform.screenToCanvas(p)
        if let lasso = currentTool as? LassoSelectionTool, lasso.isTracking {
            lasso.mouseDragged(to: hoverCanvasPoint!, document: document)
        }
        updateCursor()
        overlay.needsDisplay = true
    }

    public override func mouseEntered(with event: NSEvent) {
        updateCursor()
    }

    public override func mouseExited(with event: NSEvent) {
        hoverCanvasPoint = nil
        NSCursor.arrow.set()
        overlay.needsDisplay = true
    }

    // MARK: Mouse Input

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        lastMouseLocation = location
        let canvasPt = document.viewportTransform.screenToCanvas(location)

        switch mode {
        case .pan:
            isPanning = true
            NSCursor.closedHand.set()
            return

        case .liquify:
            state.liquifyBegin(at: canvasPt)
            setNeedsDisplayCanvas()
            return

        case .chromaSample:
            state.sampleChromaKey(at: canvasPt)
            return

        case .tool(let tool):
            // Painting over an un-applied preview would be wiped by Cancel, so apply it first.
            if state.hasPendingChanges { state.commitPending() }
            dragStartCanvas = canvasPt
            dragCurrentCanvas = canvasPt

            switch tool {
            case .hand:
                return
            case .move:
                beginMove(at: canvasPt)
                return
            case .eyedropper:
                pickColor(at: canvasPt, secondary: event.modifierFlags.contains(.option))
                return
            case .lasso:
                // Polygonal lasso keeps its tool instance between clicks.
                if let lasso = currentTool as? LassoSelectionTool, lasso.isTracking {
                    if event.clickCount >= 2 {
                        lasso.handleDoubleClick(document: document)
                        currentTool = nil
                        state.refreshSelectionOutline()
                    } else {
                        lasso.mouseDown(at: canvasPt, document: document)
                        if !lasso.isTracking {
                            currentTool = nil
                            state.refreshSelectionOutline()
                        }
                    }
                    setNeedsDisplayCanvas()
                    return
                }
            default:
                break
            }

            let instance = makeTool(tool, modifiers: event.modifierFlags)
            currentTool = instance
            instance.mouseDown(at: canvasPt, document: document)
            setNeedsDisplayCanvas()
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let delta = CGPoint(x: location.x - lastMouseLocation.x, y: location.y - lastMouseLocation.y)
        lastMouseLocation = location
        let canvasPt = document.viewportTransform.screenToCanvas(location)
        hoverCanvasPoint = canvasPt

        if isPanning {
            document.viewportTransform.pan(by: delta)
            setNeedsDisplayCanvas()
            return
        }

        switch mode {
        case .pan:
            return
        case .liquify:
            state.liquifyDrag(to: canvasPt)
            setNeedsDisplayCanvas()
        case .chromaSample:
            return
        case .tool(let tool):
            dragCurrentCanvas = canvasPt
            switch tool {
            case .move:
                updateMove(to: canvasPt)
            case .eyedropper:
                pickColor(at: canvasPt, secondary: event.modifierFlags.contains(.option))
            default:
                currentTool?.mouseDragged(to: canvasPt, document: document)
            }
            setNeedsDisplayCanvas()
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let canvasPt = document.viewportTransform.screenToCanvas(location)

        if isPanning {
            isPanning = false
            updateCursor()
            document.markDirty()
            return
        }

        switch mode {
        case .pan, .chromaSample:
            break
        case .liquify:
            state.liquifyEnd()
        case .tool(let tool):
            switch tool {
            case .move:
                endMove()
            case .eyedropper, .hand:
                break
            default:
                if let instance = currentTool {
                    instance.mouseUp(at: canvasPt, document: document)
                    if let lasso = instance as? LassoSelectionTool, lasso.isTracking {
                        // Polygonal lasso: keep collecting points.
                    } else {
                        currentTool = nil
                    }
                }
            }

            switch tool {
            case .marquee, .ellipseMarquee, .lasso:
                if currentTool == nil { state.refreshSelectionOutline() }
            case .crop:
                state.refreshSelectionOutline()
                state.fitToScreen()
            default:
                break
            }
            dragStartCanvas = nil
            dragCurrentCanvas = nil
        }

        // Let SwiftUI refresh undo/redo state, history, etc. (once per stroke, not per event).
        document.markDirty()
        setNeedsDisplayCanvas()
    }

    public override func scrollWheel(with event: NSEvent) {
        let mousePt = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
            let zoomFactor = max(0.5, min(2.0, 1.0 + delta))
            document.viewportTransform.zoom(by: zoomFactor, aroundScreenPoint: mousePt)
        } else {
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
            document.viewportTransform.pan(by: CGPoint(x: event.scrollingDeltaX * scale, y: event.scrollingDeltaY * scale))
        }
        setNeedsDisplayCanvas()
    }

    public override func magnify(with event: NSEvent) {
        let zoomFactor = Double(1.0 + event.magnification)
        let mousePt = convert(event.locationInWindow, from: nil)
        document.viewportTransform.zoom(by: zoomFactor, aroundScreenPoint: mousePt)
        setNeedsDisplayCanvas()
    }

    // MARK: Tools

    private func selectionMode(for flags: NSEvent.ModifierFlags) -> SelectionMode {
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        if shift && option { return .intersect }
        if shift { return .add }
        if option { return .subtract }
        return .newSelection
    }

    private func makeTool(_ tool: CanvasTool, modifiers: NSEvent.ModifierFlags) -> any DrawingTool {
        let primary = EditorState.simdColor(state.primaryColor)
        let secondary = EditorState.simdColor(state.secondaryColor)

        switch tool {
        case .brush:
            let hardness = Float(state.brushHardness)
            return BrushTool(configuration: BrushConfiguration(
                shape: hardness >= 0.98 ? .round : .soft,
                size: Float(state.brushSize),
                opacity: Float(state.brushOpacity),
                flow: Float(state.brushFlow),
                hardness: hardness,
                color: primary
            ))

        case .eraser:
            let hardness = Float(state.brushHardness)
            return EraserTool(configuration: BrushConfiguration(
                shape: hardness >= 0.98 ? .round : .soft,
                size: Float(state.eraserSize),
                opacity: Float(state.brushOpacity),
                flow: Float(state.brushFlow),
                hardness: hardness
            ))

        case .fill:
            return FloodFillTool(configuration: FloodFillConfiguration(
                tolerance: Float(state.fillTolerance),
                fillColor: primary,
                mode: state.fillContiguous ? .contiguous : .global
            ))

        case .gradient:
            var end = secondary
            if state.gradientToTransparent {
                end = SIMD4<Float>(primary.x, primary.y, primary.z, 0)
            }
            return GradientTool(configuration: GradientConfiguration(
                type: state.gradientType,
                stops: [
                    GradientStop(offset: 0, color: primary),
                    GradientStop(offset: 1, color: end)
                ]
            ))

        case .marquee, .ellipseMarquee:
            let shape: MarqueeShape = tool == .marquee ? .rectangle : .ellipse
            return MarqueeSelectionTool(
                shape: shape,
                configuration: MarqueeConfiguration(
                    shape: shape,
                    mode: selectionMode(for: modifiers),
                    featherRadius: CGFloat(state.selectionFeather)
                )
            )

        case .lasso:
            return LassoSelectionTool(configuration: LassoConfiguration(
                type: state.lassoPolygonal ? .polygonal : .freehand,
                mode: selectionMode(for: modifiers),
                featherRadius: CGFloat(state.selectionFeather)
            ))

        case .crop:
            return CropTool()

        case .eyedropper, .move, .hand:
            // Handled directly by the canvas; never instantiated.
            return EyedropperTool()
        }
    }

    private func pickColor(at canvasPt: CGPoint, secondary: Bool) {
        let dropper = EyedropperTool(sampleMode: .pointSample, sourceMode: .allVisibleLayers)
        guard let result = dropper.sample(at: canvasPt, document: document), result.colorBytes.w > 0 else { return }
        let color = EditorState.color(from: SIMD4<UInt8>(result.colorBytes.x, result.colorBytes.y, result.colorBytes.z, 255))
        if secondary {
            state.secondaryColor = color
        } else {
            state.primaryColor = color
        }
    }

    // Move tool: shifts whole tiles with memcpy (CropTool.remapTileGrid), so it is fast even on 8K.
    private func beginMove(at canvasPt: CGPoint) {
        guard let layer = document.activeLayer as? BitmapLayer, !layer.isLocked else { return }
        moveLayer = layer
        moveBefore = layer.tileGrid.duplicate()
        moveStartCanvas = canvasPt
        moveLastShift = (0, 0)
    }

    private func updateMove(to canvasPt: CGPoint) {
        guard let layer = moveLayer, let before = moveBefore else { return }
        let shift = (dx: Int((canvasPt.x - moveStartCanvas.x).rounded()), dy: Int((canvasPt.y - moveStartCanvas.y).rounded()))
        guard shift != moveLastShift else { return }
        moveLastShift = shift
        let moved = CropTool.remapTileGrid(oldGrid: before, newSize: before.canvasSize, shift: shift)
        layer.tileGrid.copyFrom(moved)
    }

    private func endMove() {
        defer {
            moveLayer = nil
            moveBefore = nil
        }
        guard let layer = moveLayer, let before = moveBefore, moveLastShift != (0, 0) else { return }
        document.commitGridEdit(layer: layer, before: before, newGrid: layer.tileGrid.duplicate(), actionName: "Move")
    }

    // MARK: Overlay data

    var rubberBandRect: CGRect? {
        guard let start = dragStartCanvas, let current = dragCurrentCanvas else { return nil }
        switch mode {
        case .tool(.marquee), .tool(.ellipseMarquee), .tool(.crop):
            return CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
        default:
            return nil
        }
    }

    var gradientLine: (CGPoint, CGPoint)? {
        guard case .tool(.gradient) = mode, let start = dragStartCanvas, let current = dragCurrentCanvas else { return nil }
        return (start, current)
    }

    var lassoPoints: [CGPoint]? {
        guard let lasso = currentTool as? LassoSelectionTool, lasso.isTracking, !lasso.vertices.isEmpty else { return nil }
        var pts = lasso.vertices
        if let rb = lasso.rubberBandPoint { pts.append(rb) }
        return pts
    }
}

// MARK: - Overlay (selection outline, rubber bands, brush cursor)

final class CanvasOverlayView: NSView {
    weak var canvas: InteractiveCanvasView?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Mouse events go straight through to the canvas.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let canvas, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let vt = canvas.document.viewportTransform
        let z = CGFloat(vt.zoom)
        var toScreen = CGAffineTransform(translationX: vt.panOffset.x, y: vt.panOffset.y).scaledBy(x: z, y: z)

        func strokeAnts(_ path: CGPath, phase: CGFloat) {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setLineWidth(1)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.strokePath()
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineDash(phase: phase, lengths: [4, 4])
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Committed selection
        if let outline = canvas.state.selectionOutline, let screenPath = outline.copy(using: &toScreen) {
            strokeAnts(screenPath, phase: canvas.antsPhase)
        }

        // Marquee / crop rubber band
        if let rect = canvas.rubberBandRect {
            let r = rect.applying(toScreen)
            let path: CGPath
            if case .tool(.ellipseMarquee) = canvas.mode {
                path = CGPath(ellipseIn: r, transform: nil)
            } else {
                path = CGPath(rect: r, transform: nil)
            }
            if case .tool(.crop) = canvas.mode {
                // Dim everything outside the crop rect.
                ctx.saveGState()
                ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
                ctx.addRect(bounds)
                ctx.addRect(r)
                ctx.fillPath(using: .evenOdd)
                ctx.restoreGState()
            }
            strokeAnts(path, phase: 0)
        }

        // Lasso in progress
        if let pts = canvas.lassoPoints, pts.count >= 2 {
            let path = CGMutablePath()
            path.addLines(between: pts.map { $0.applying(toScreen) })
            strokeAnts(path, phase: 0)
        }

        // Gradient direction
        if let line = canvas.gradientLine {
            let sa = line.0.applying(toScreen), sb = line.1.applying(toScreen)
            ctx.saveGState()
            ctx.setLineWidth(2)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.move(to: sa)
            ctx.addLine(to: sb)
            ctx.strokePath()
            ctx.setLineWidth(1)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.move(to: sa)
            ctx.addLine(to: sb)
            ctx.strokePath()
            for p in [sa, sb] {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.strokeEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            }
            ctx.restoreGState()
        }

        // Brush / liquify size cursor
        if let radius = canvas.brushCursorRadius, let hover = canvas.hoverCanvasPoint {
            let c = hover.applying(toScreen)
            let r = max(2, radius * z)
            let circle = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.saveGState()
            ctx.setLineWidth(1.5)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            ctx.strokeEllipse(in: circle)
            ctx.setLineWidth(0.75)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.strokeEllipse(in: circle.insetBy(dx: 1, dy: 1))
            ctx.restoreGState()
        }
    }
}

// MARK: - SwiftUI Bridge

public struct CanvasViewRepresentable: NSViewRepresentable {
    @ObservedObject var state: EditorState
    /// Observed so that any document change (layers, visibility, undo…) triggers a redraw.
    @ObservedObject var document: Document
    var onFileDropped: ((URL, Bool) -> Void)?

    public func makeNSView(context: Context) -> InteractiveCanvasView {
        let view = InteractiveCanvasView(document: state.document, state: state)
        view.onFileDropped = onFileDropped
        return view
    }

    public func updateNSView(_ nsView: InteractiveCanvasView, context: Context) {
        nsView.onFileDropped = onFileDropped
        nsView.setNeedsDisplayCanvas()
    }
}
