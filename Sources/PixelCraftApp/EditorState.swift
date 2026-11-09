import SwiftUI
import AppKit
import PixelCraftEngine

// MARK: - Canvas Tools (bottom toolbar)

/// Basic tools that act directly on the canvas. Everything that *generates* or *distorts* pixels
/// lives in `Generator` and is shown in the right-hand dock instead.
public enum CanvasTool: String, CaseIterable, Identifiable, Sendable {
    case move
    case hand
    case marquee
    case ellipseMarquee
    case lasso
    case crop
    case brush
    case eraser
    case fill
    case gradient
    case eyedropper

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .move: return "Move"
        case .hand: return "Hand"
        case .marquee: return "Rectangle Select"
        case .ellipseMarquee: return "Ellipse Select"
        case .lasso: return "Lasso"
        case .crop: return "Crop"
        case .brush: return "Brush"
        case .eraser: return "Eraser"
        case .fill: return "Paint Bucket"
        case .gradient: return "Gradient"
        case .eyedropper: return "Eyedropper"
        }
    }

    /// Short caption shown under the icon in the toolbar.
    public var shortLabel: String {
        switch self {
        case .move: return "Move"
        case .hand: return "Hand"
        case .marquee: return "Select"
        case .ellipseMarquee: return "Ellipse"
        case .lasso: return "Lasso"
        case .crop: return "Crop"
        case .brush: return "Brush"
        case .eraser: return "Eraser"
        case .fill: return "Fill"
        case .gradient: return "Gradient"
        case .eyedropper: return "Picker"
        }
    }

    public var iconName: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .hand: return "hand.raised"
        case .marquee: return "rectangle.dashed"
        case .ellipseMarquee: return "circle.dashed"
        case .lasso: return "lasso"
        case .crop: return "crop"
        case .brush: return "paintbrush.pointed"
        case .eraser: return "eraser"
        case .fill: return "drop"
        case .gradient: return "circle.lefthalf.filled"
        case .eyedropper: return "eyedropper"
        }
    }

    /// Single-key shortcut (Photoshop-like where possible).
    public var shortcut: Character {
        switch self {
        case .move: return "v"
        case .hand: return "h"
        case .marquee: return "m"
        case .ellipseMarquee: return "o"
        case .lasso: return "l"
        case .crop: return "c"
        case .brush: return "b"
        case .eraser: return "e"
        case .fill: return "k"
        case .gradient: return "g"
        case .eyedropper: return "i"
        }
    }

    public var hint: String {
        switch self {
        case .move: return "Drag to move the content of the active layer"
        case .hand: return "Drag to pan the canvas (or hold Space with any tool)"
        case .marquee: return "Drag to select a rectangle. Click without dragging to deselect"
        case .ellipseMarquee: return "Drag to select an ellipse"
        case .lasso: return "Draw a free-hand selection"
        case .crop: return "Drag a rectangle to crop the canvas"
        case .brush: return "Paint with the primary color"
        case .eraser: return "Erase pixels of the active layer"
        case .fill: return "Fill a similar-colored area with the primary color"
        case .gradient: return "Drag to draw a gradient from primary to secondary color"
        case .eyedropper: return "Click to pick a color from the canvas"
        }
    }

    /// Visual grouping in the toolbar.
    public var group: Int {
        switch self {
        case .move, .hand: return 0
        case .marquee, .ellipseMarquee, .lasso, .crop: return 1
        case .brush, .eraser, .fill, .gradient, .eyedropper: return 2
        }
    }
}

// MARK: - Generators (right dock)

public enum Generator: String, CaseIterable, Identifiable, Sendable {
    case transform
    case liquify
    case pixelate
    case chromaKey
    case removeBackground
    case ascii

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .transform: return "Transform"
        case .liquify: return "Liquify"
        case .pixelate: return "Pixelate"
        case .chromaKey: return "Chroma Key"
        case .removeBackground: return "Remove Background"
        case .ascii: return "ASCII Art"
        }
    }

    public var shortTitle: String {
        switch self {
        case .transform: return "Transform"
        case .liquify: return "Liquify"
        case .pixelate: return "Pixelate"
        case .chromaKey: return "Chroma"
        case .removeBackground: return "Remove BG"
        case .ascii: return "ASCII"
        }
    }

    public var iconName: String {
        switch self {
        case .transform: return "arrow.up.left.and.arrow.down.right"
        case .liquify: return "scribble.variable"
        case .pixelate: return "square.grid.3x3.fill"
        case .chromaKey: return "wand.and.stars"
        case .removeBackground: return "person.and.background.dotted"
        case .ascii: return "character.textbox"
        }
    }

    public var summary: String {
        switch self {
        case .transform: return "Scale, rotate, flip and move the active layer around its content center."
        case .liquify: return "Paint on the canvas to push, twirl, pinch or bloat pixels."
        case .pixelate: return "Turn the active layer into square, hexagonal or circular cells."
        case .chromaKey: return "Click the canvas to sample a backdrop color and remove it."
        case .removeBackground: return "Isolate the main subject with Apple Vision and erase the rest."
        case .ascii: return "Convert the active layer into ASCII / block-character art on a new layer."
        }
    }

    /// Generators whose result is previewed live on the layer and then applied/cancelled.
    public var usesLivePreview: Bool {
        switch self {
        case .transform, .pixelate, .chromaKey: return true
        case .liquify, .removeBackground, .ascii: return false
        }
    }
}

public enum ASCIIStyle: String, CaseIterable, Identifiable, Sendable {
    case darkOnLight
    case lightOnDark
    case primaryColor

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .darkOnLight: return "Black on white"
        case .lightOnDark: return "White on black"
        case .primaryColor: return "Primary color, transparent"
        }
    }
}

// MARK: - Editor State

/// Single source of truth for UI state shared by the canvas, the toolbars and the generator panels.
/// The canvas reads it at event time, so it can never hold stale tool settings.
@MainActor
public final class EditorState: ObservableObject {
    public let document: Document

    /// Weak link to the canvas so menu commands can trigger redraws / fit-to-screen.
    weak var canvasView: InteractiveCanvasView?

    /// Last known canvas viewport size in points (updated by the canvas on layout).
    var viewportSize: CGSize = CGSize(width: 1200, height: 800)

    // MARK: Tools

    @Published public var tool: CanvasTool = .brush {
        didSet {
            if oldValue != tool { canvasView?.toolDidChange() }
        }
    }
    @Published public var primaryColor: Color = .black
    @Published public var secondaryColor: Color = .white

    @Published public var brushSize: Double = 24
    @Published public var brushOpacity: Double = 1.0
    @Published public var brushFlow: Double = 1.0
    @Published public var brushHardness: Double = 0.8
    @Published public var eraserSize: Double = 40

    @Published public var fillTolerance: Double = 0.15
    @Published public var fillContiguous: Bool = true

    @Published public var gradientType: GradientType = .linear
    @Published public var gradientToTransparent: Bool = false

    @Published public var selectionFeather: Double = 0
    @Published public var lassoPolygonal: Bool = false

    /// Outline of the current selection in canvas coordinates (drawn as marching ants).
    @Published public private(set) var selectionOutline: CGPath?

    // MARK: Dialogs

    @Published public var isNewDocumentSheetPresented = false
    @Published public var isExportSheetPresented = false

    // MARK: Generators

    @Published public private(set) var openGenerator: Generator?
    @Published public private(set) var hasPendingChanges: Bool = false
    @Published public private(set) var isBusy: Bool = false
    @Published public var statusMessage: String?

    // Transform
    @Published public var transformScaleX: Double = 100 { didSet { schedulePreview(.transform) } }
    @Published public var transformScaleY: Double = 100 { didSet { schedulePreview(.transform) } }
    @Published public var transformLockAspect: Bool = true
    @Published public var transformRotation: Double = 0 { didSet { schedulePreview(.transform) } }
    @Published public var transformOffsetX: Double = 0 { didSet { schedulePreview(.transform) } }
    @Published public var transformOffsetY: Double = 0 { didSet { schedulePreview(.transform) } }
    @Published public var transformFlipH: Bool = false { didSet { schedulePreview(.transform) } }
    @Published public var transformFlipV: Bool = false { didSet { schedulePreview(.transform) } }
    @Published public var transformInterpolation: InterpolationMode = .bilinear { didSet { schedulePreview(.transform) } }

    // Liquify
    @Published public var liquifyMode: LiquifyToolMode = .push
    @Published public var liquifySize: Double = 120
    @Published public var liquifyPressure: Double = 0.5

    // Pixelate
    @Published public var pixelBlockSize: Double = 16 { didSet { schedulePreview(.pixelate) } }
    @Published public var pixelShape: PixelateGridShape = .square { didSet { schedulePreview(.pixelate) } }
    @Published public var pixelSampling: PixelateSamplingMode = .average { didSet { schedulePreview(.pixelate) } }

    // Chroma key
    @Published public var chromaKeyColor: Color = Color(red: 0, green: 1, blue: 0) { didSet { schedulePreview(.chromaKey) } }
    @Published public var chromaTolerance: Double = 25 { didSet { schedulePreview(.chromaKey) } }
    @Published public var chromaFeather: Double = 10 { didSet { schedulePreview(.chromaKey) } }
    @Published public var chromaSpill: Double = 0.75 { didSet { schedulePreview(.chromaKey) } }

    // Background removal
    @Published public var aiRefineEdges: Bool = true

    // ASCII
    @Published public var asciiColumns: Double = 120
    @Published public var asciiRows: Double = 60
    @Published public var asciiAutoRows: Bool = true
    @Published public var asciiCharSet: Int = 0 // 0 standard, 1 blocks, 2 custom
    @Published public var asciiCustomChars: String = " .:-=+*#%@"
    @Published public var asciiDithering: Bool = true
    @Published public var asciiInvert: Bool = false
    @Published public var asciiVolume: Double = 1.0
    @Published public var asciiStyle: ASCIIStyle = .darkOnLight

    // MARK: Pending edit session (live preview / liquify)

    private var pendingBefore: SparseTileGrid?
    private var pendingLayerID: UUID?
    private var pendingActionName: String = ""
    private var previewGeneration: Int = 0
    private var previewRunning = false
    private var previewQueued = false
    private var previewDebounce: Task<Void, Never>?
    private var suppressPreview = false

    private var liquifyEngine: LiquifyEngine?
    private var liquifyLastPoint: CGPoint?

    public init(document: Document) {
        self.document = document
    }

    // MARK: - Helpers

    var activeBitmapLayer: BitmapLayer? {
        document.activeLayer as? BitmapLayer
    }

    func redrawCanvas() {
        canvasView?.setNeedsDisplayCanvas()
    }

    func fitToScreen() {
        document.viewportTransform = ViewportTransform.fitToViewport(
            canvasSize: document.canvasSize,
            viewportSize: viewportSize
        )
        document.markDirty()
        redrawCanvas()
    }

    func zoom(by factor: Double) {
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        document.viewportTransform.zoom(by: factor, aroundScreenPoint: center)
        redrawCanvas()
    }

    func actualSize() {
        document.viewportTransform = ViewportTransform.centerActualSize(
            canvasSize: document.canvasSize,
            viewportSize: viewportSize
        )
        redrawCanvas()
    }

    static func simdColor(_ color: Color) -> SIMD4<Float> {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        return SIMD4<Float>(
            Float(ns.redComponent),
            Float(ns.greenComponent),
            Float(ns.blueComponent),
            Float(ns.alphaComponent)
        )
    }

    static func color(from bytes: SIMD4<UInt8>) -> Color {
        Color(
            .sRGB,
            red: Double(bytes.x) / 255.0,
            green: Double(bytes.y) / 255.0,
            blue: Double(bytes.z) / 255.0,
            opacity: Double(bytes.w) / 255.0
        )
    }

    func swapColors() {
        let p = primaryColor
        primaryColor = secondaryColor
        secondaryColor = p
    }

    // MARK: - Selection

    func refreshSelectionOutline() {
        guard let mask = document.selectionMask, mask.hasActiveSelection else {
            selectionOutline = nil
            redrawCanvas()
            return
        }
        let path = mask.marchingSquaresContourPath()
        if path.isEmpty, let bounds = mask.selectionBounds {
            selectionOutline = CGPath(rect: bounds, transform: nil)
        } else {
            selectionOutline = path
        }
        redrawCanvas()
    }

    func selectAll() {
        document.selectionMask?.selectAll()
        refreshSelectionOutline()
    }

    func deselect() {
        document.selectionMask?.deselect()
        refreshSelectionOutline()
    }

    func invertSelection() {
        document.selectionMask?.invert()
        refreshSelectionOutline()
    }

    // MARK: - Undo / Redo (aware of pending previews)

    func undo() {
        if hasPendingChanges {
            cancelPending()
            return
        }
        document.undo()
        refreshSelectionOutline()
    }

    func redo() {
        guard !hasPendingChanges else { return }
        document.redo()
        refreshSelectionOutline()
    }

    // MARK: - Generator Panel Management

    func toggleGenerator(_ generator: Generator) {
        if openGenerator == generator {
            closeGenerator()
        } else {
            openGeneratorPanel(generator)
        }
    }

    func openGeneratorPanel(_ generator: Generator) {
        commitPending()
        statusMessage = nil
        openGenerator = generator
        canvasView?.toolDidChange()
        if generator == .pixelate {
            schedulePreview(.pixelate, immediate: true)
        }
    }

    /// Closing a panel keeps (applies) whatever was previewed; use Cancel to revert.
    func closeGenerator() {
        commitPending()
        openGenerator = nil
        statusMessage = nil
        canvasView?.toolDidChange()
    }

    func resetTransformParameters() {
        transformScaleX = 100
        transformScaleY = 100
        transformRotation = 0
        transformOffsetX = 0
        transformOffsetY = 0
        transformFlipH = false
        transformFlipV = false
    }

    // MARK: - Pending Session Commit / Cancel

    /// Turns the currently previewed result into a regular undoable edit.
    func commitPending() {
        previewDebounce?.cancel()
        previewGeneration += 1
        defer {
            pendingBefore = nil
            pendingLayerID = nil
            liquifyEngine = nil
            liquifyLastPoint = nil
            hasPendingChanges = false
            isBusy = false
        }
        guard hasPendingChanges,
              let before = pendingBefore,
              let layerID = pendingLayerID,
              let layer = document.layers.first(where: { $0.id == layerID }) as? BitmapLayer else { return }
        document.commitGridEdit(
            layer: layer,
            before: before,
            newGrid: layer.tileGrid.duplicate(),
            actionName: pendingActionName
        )
        // Transform parameters are relative to the pre-edit image: start from identity again.
        if pendingActionName == Generator.transform.title {
            resetTransformParametersSilently()
        }
        redrawCanvas()
    }

    /// Reverts the layer to the state before the preview / liquify session.
    func cancelPending() {
        previewDebounce?.cancel()
        previewGeneration += 1
        if let before = pendingBefore,
           let layerID = pendingLayerID,
           let layer = document.layers.first(where: { $0.id == layerID }) as? BitmapLayer {
            layer.tileGrid.copyFrom(before)
        }
        pendingBefore = nil
        pendingLayerID = nil
        liquifyEngine = nil
        liquifyLastPoint = nil
        hasPendingChanges = false
        isBusy = false
        if openGenerator == .transform { resetTransformParametersSilently() }
        document.markDirty()
        redrawCanvas()
    }

    private func resetTransformParametersSilently() {
        // Each assignment triggers didSet -> schedulePreview; suppress that while resetting.
        suppressPreview = true
        resetTransformParameters()
        suppressPreview = false
    }

    /// Starts (or continues) a pending session on the active bitmap layer.
    private func beginPendingSession(actionName: String) -> BitmapLayer? {
        guard let layer = activeBitmapLayer else {
            statusMessage = "Select a bitmap (pixel) layer first."
            return nil
        }
        guard !layer.isLocked else {
            statusMessage = "The active layer is locked."
            return nil
        }
        if let id = pendingLayerID, id != layer.id {
            // Active layer changed mid-session: keep what was done on the previous one.
            commitPending()
        }
        if pendingBefore == nil {
            pendingBefore = layer.tileGrid.duplicate()
            pendingLayerID = layer.id
        }
        pendingActionName = actionName
        return layer
    }

    // MARK: - Live Preview (transform / pixelate / chroma key)

    func schedulePreview(_ generator: Generator, immediate: Bool = false) {
        guard !suppressPreview, openGenerator == generator else { return }
        previewDebounce?.cancel()
        previewDebounce = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard !Task.isCancelled else { return }
            self?.runPreview()
        }
    }

    private func runPreview() {
        guard let generator = openGenerator, generator.usesLivePreview else { return }
        if previewRunning {
            previewQueued = true
            return
        }
        guard let layer = beginPendingSession(actionName: generator.title),
              let before = pendingBefore else { return }

        let job = makePreviewJob(for: generator)
        previewGeneration += 1
        let generation = previewGeneration
        previewRunning = true
        isBusy = true

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { job(before) }.value
            guard let self else { return }
            self.previewRunning = false
            if generation == self.previewGeneration, self.pendingLayerID == layer.id {
                layer.tileGrid.copyFrom(result)
                self.hasPendingChanges = true
                self.document.markDirty()
                self.redrawCanvas()
            }
            self.isBusy = self.previewQueued
            if self.previewQueued {
                self.previewQueued = false
                self.runPreview()
            }
        }
    }

    private func makePreviewJob(for generator: Generator) -> @Sendable (SparseTileGrid) -> SparseTileGrid {
        switch generator {
        case .transform:
            let sx = transformScaleX / 100.0
            let sy = (transformLockAspect ? transformScaleX : transformScaleY) / 100.0
            let rotation = transformRotation * .pi / 180.0
            let flipH = transformFlipH
            let flipV = transformFlipV
            let offset = CGPoint(x: transformOffsetX, y: transformOffsetY)
            let interpolation = transformInterpolation
            return { source in
                let content = source.opaquePixelBounds
                    ?? CGRect(origin: .zero, size: source.canvasSize)
                var state = TransformState()
                state.scale = CGSize(width: max(0.01, sx), height: max(0.01, sy))
                state.rotation = CGFloat(rotation)
                state.flipHorizontal = flipH
                state.flipVertical = flipV
                state.translation = offset
                state.pivot = CGPoint(x: content.midX, y: content.midY)
                return TransformEngine().transform(
                    source: source,
                    state: state,
                    canvasSize: source.canvasSize,
                    interpolation: interpolation
                )
            }

        case .pixelate:
            let block = Int(pixelBlockSize.rounded())
            let shape = pixelShape
            let sampling = pixelSampling
            let bounds = document.selectionMask?.selectionBounds
            return { source in
                PixelateFilter().apply(grid: source, blockSize: block, shape: shape, sampling: sampling, bounds: bounds)
            }

        case .chromaKey:
            let c = Self.simdColor(chromaKeyColor)
            let params = ChromaKeyParams(
                keyColor: (
                    UInt8(max(0, min(255, (c.x * 255).rounded()))),
                    UInt8(max(0, min(255, (c.y * 255).rounded()))),
                    UInt8(max(0, min(255, (c.z * 255).rounded())))
                ),
                tolerance: Float(chromaTolerance),
                feather: Float(chromaFeather),
                spillSuppression: Float(chromaSpill)
            )
            return { source in
                ChromaKeyFilter().apply(grid: source, params: params)
            }

        case .liquify, .removeBackground, .ascii:
            return { source in source.duplicate() }
        }
    }

    /// Chroma key: pick the key color from the *original* (un-keyed) pixels of the active layer.
    func sampleChromaKey(at canvasPoint: CGPoint) {
        guard let layer = activeBitmapLayer else { return }
        let source = (pendingLayerID == layer.id ? pendingBefore : nil) ?? layer.tileGrid
        let px = source.readPixel(x: Int(canvasPoint.x), y: Int(canvasPoint.y))
        guard px.w > 0 else {
            statusMessage = "That pixel is transparent — click on the backdrop color."
            return
        }
        statusMessage = nil
        chromaKeyColor = Self.color(from: SIMD4<UInt8>(px.x, px.y, px.z, 255))
    }

    // MARK: - Liquify (interactive)

    func liquifyBegin(at point: CGPoint) {
        guard let layer = beginPendingSession(actionName: "Liquify") else { return }
        if liquifyEngine == nil {
            liquifyEngine = LiquifyEngine(width: document.width, height: document.height)
        }
        liquifyLastPoint = point
        liquifyStamp(at: point, delta: .zero, layer: layer)
    }

    func liquifyDrag(to point: CGPoint) {
        guard let last = liquifyLastPoint,
              let layerID = pendingLayerID,
              let layer = document.layers.first(where: { $0.id == layerID }) as? BitmapLayer else { return }
        let delta = CGPoint(x: point.x - last.x, y: point.y - last.y)
        // Push needs movement; the other modes act while the mouse is held anywhere.
        if liquifyMode == .push && hypot(delta.x, delta.y) < 0.5 { return }
        liquifyLastPoint = point
        liquifyStamp(at: point, delta: delta, layer: layer)
    }

    func liquifyEnd() {
        liquifyLastPoint = nil
    }

    private func liquifyStamp(at point: CGPoint, delta: CGPoint, layer: BitmapLayer) {
        guard let engine = liquifyEngine, let before = pendingBefore else { return }
        let params = LiquifyBrushParams(size: liquifySize, pressure: liquifyPressure)
        engine.applyBrush(mode: liquifyMode, center: point, delta: delta, params: params)
        let r = liquifySize / 2 + 2
        let dirty = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
        engine.renderRegion(source: before, into: layer.tileGrid, rect: dirty)
        hasPendingChanges = true
    }

    func resetLiquify() {
        guard pendingBefore != nil else { return }
        cancelPending()
    }

    // MARK: - One-shot Generators

    func runRemoveBackground() {
        guard !isBusy else { return }
        guard let layer = activeBitmapLayer else {
            statusMessage = "Select a bitmap (pixel) layer first."
            return
        }
        isBusy = true
        statusMessage = "Detecting the main subject…"
        let source = layer.tileGrid.duplicate()
        let refine = aiRefineEdges

        Task { [weak self] in
            do {
                let vision = VisionBackgroundRemoval()
                let mask = try await vision.generateForegroundMask(from: source, refineEdges: refine)
                let output = await Task.detached(priority: .userInitiated) { () -> SparseTileGrid in
                    let out = source.duplicate()
                    vision.applyMaskToGrid(grid: out, mask: mask)
                    return out
                }.value
                guard let self else { return }
                self.document.commitGridEdit(layer: layer, before: source, newGrid: output, actionName: "Remove Background")
                self.isBusy = false
                self.statusMessage = "Background removed. Press ⌘Z to undo."
                self.redrawCanvas()
            } catch {
                guard let self else { return }
                self.isBusy = false
                self.statusMessage = "Could not isolate a subject: \(error.localizedDescription)"
            }
        }
    }

    func updateAutoASCIIRows() {
        guard asciiAutoRows, document.width > 0 else { return }
        // Monospace cells are roughly twice as tall as they are wide.
        let rows = asciiColumns * Double(document.height) / Double(document.width) * 0.5
        asciiRows = max(5, min(300, rows.rounded()))
    }

    private func currentASCIIParams() -> ASCIIParams {
        let charSet: ASCIICharacterSet
        switch asciiCharSet {
        case 1: charSet = .extendedUnicode
        case 2: charSet = .custom(asciiCustomChars)
        default: charSet = .standard
        }
        // Dense glyphs mean "bright" in the generator; on light paper dense glyphs must mean "dark".
        let invert: Bool
        let textColor: SIMD4<Float>
        let background: SIMD4<Float>?
        switch asciiStyle {
        case .darkOnLight:
            invert = !asciiInvert
            textColor = SIMD4<Float>(0, 0, 0, 1)
            background = SIMD4<Float>(1, 1, 1, 1)
        case .lightOnDark:
            invert = asciiInvert
            textColor = SIMD4<Float>(1, 1, 1, 1)
            background = SIMD4<Float>(0, 0, 0, 1)
        case .primaryColor:
            invert = asciiInvert
            textColor = Self.simdColor(primaryColor)
            background = nil
        }
        return ASCIIParams(
            gridColumns: Int(asciiColumns.rounded()),
            gridRows: Int(asciiRows.rounded()),
            charSet: charSet,
            fontName: "Menlo",
            volumeIntensity: Float(asciiVolume),
            dithering: asciiDithering,
            invert: invert,
            autoContrast: true,
            textColor: textColor,
            backgroundColor: background
        )
    }

    func runASCIIRaster() {
        guard !isBusy else { return }
        guard let layer = activeBitmapLayer else {
            statusMessage = "Select a bitmap (pixel) layer first."
            return
        }
        updateAutoASCIIRows()
        let params = currentASCIIParams()
        let source = layer.tileGrid.duplicate()
        let canvasSize = document.canvasSize
        isBusy = true
        statusMessage = "Rendering ASCII art…"

        Task { [weak self] in
            let baked = await Task.detached(priority: .userInitiated) {
                ASCIIGenerator().bakeToBitmapLayer(from: source, params: params, canvasSize: canvasSize)
            }.value
            guard let self else { return }
            baked.name = "ASCII Art"
            self.document.addLayer(baked)
            self.isBusy = false
            self.statusMessage = "Added a new layer “ASCII Art”."
            self.redrawCanvas()
        }
    }

    func copyASCIIText() {
        guard let layer = activeBitmapLayer else {
            statusMessage = "Select a bitmap (pixel) layer first."
            return
        }
        updateAutoASCIIRows()
        let text = ASCIIGenerator().generateText(from: layer.tileGrid, params: currentASCIIParams())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = "ASCII text copied to the clipboard."
    }

    // MARK: - Compositing / Export

    /// Flattens all visible layers into one grid (what the user sees on the canvas).
    /// `background` (e.g. white for JPEG) is painted underneath when given.
    func compositeGrid(background: SIMD4<Float>? = nil) -> SparseTileGrid {
        let merged = BitmapLayer(name: "Composite", bounds: document.bounds)
        if let background {
            merged.fillSolid(color: background, canvasSize: document.canvasSize)
        }
        for layer in document.layers where layer.isVisible {
            merged.composite(layer: layer, canvasSize: document.canvasSize)
        }
        return merged.tileGrid
    }
}
