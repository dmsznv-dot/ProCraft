import Foundation
import CoreGraphics
import simd

public enum DocumentError: LocalizedError, Equatable {
    case invalidDimensions(width: Int, height: Int)
    case canvasExceedsMaximumSize(width: Int, height: Int, maxWidth: Int, maxHeight: Int)
    case layerIndexOutOfBounds(index: Int, count: Int)
    case cannotMergeBottomLayer
    case layerIsLocked(name: String)
    case noVisibleLayersToMerge

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions(let width, let height):
            return "Invalid canvas dimensions (\(width)x\(height)). Width and height must be positive integers."
        case .canvasExceedsMaximumSize(let width, let height, let maxW, let maxH):
            return "Canvas dimensions (\(width)x\(height)) exceed maximum supported resolution (\(maxW)x\(maxH))."
        case .layerIndexOutOfBounds(let index, let count):
            return "Layer index \(index) is out of bounds for layer stack of count \(count)."
        case .cannotMergeBottomLayer:
            return "Cannot merge down from the bottom-most layer (index 0)."
        case .layerIsLocked(let name):
            return "Layer '\(name)' is locked and cannot be modified or merged."
        case .noVisibleLayersToMerge:
            return "No visible layers found to merge."
        }
    }
}

/// The core document model in PixelCraft Pro.
/// Represents a multi-layered 2D graphic composition with canvas resolution up to 8K.
public final class Document: Identifiable, ObservableObject, @unchecked Sendable {
    // MARK: - Constants
    
    public static let minDimension: Int = 1
    public static let maxDimensionWidth: Int = 8192
    public static let maxDimensionHeight: Int = 4320
    public static let defaultCanvasSize: CGSize = CGSize(width: 1920, height: 1080)

    // MARK: - Properties
    
    public let id: UUID
    
    @Published public private(set) var title: String
    @Published public private(set) var canvasSize: CGSize
    @Published public private(set) var layers: [any Layer]
    @Published public var activeLayerIndex: Int {
        didSet {
            clampActiveLayerIndex()
        }
    }
    
    /// Viewport pan/zoom. Intentionally *not* `@Published`: it changes on every scroll/pinch event and
    /// publishing it re-evaluated the whole SwiftUI hierarchy (layers list, panels) each time.
    /// UI that only needs the zoom level observes `zoomPercent` instead.
    public var viewportTransform: ViewportTransform {
        didSet {
            let z = Int((viewportTransform.zoom * 100.0).rounded())
            if z != zoomPercent { zoomPercent = z }
        }
    }

    /// Current zoom level in percent (rounded), published for HUD/status display.
    @Published public private(set) var zoomPercent: Int = 100
    public let undoManager: TileUndoManager
    @Published public var selectionMask: SelectionMask?
    
    // Internal synchronization lock for thread safety
    private let lock = NSLock()

    // MARK: - Computed Properties
    
    public var width: Int {
        Int(canvasSize.width)
    }
    
    public var height: Int {
        Int(canvasSize.height)
    }
    
    public var bounds: CGRect {
        CGRect(origin: .zero, size: canvasSize)
    }
    
    public var aspectRatio: CGFloat {
        guard canvasSize.height > 0 else { return 1.0 }
        return canvasSize.width / canvasSize.height
    }
    
    public var activeLayer: any Layer {
        get {
            lock.lock()
            defer { lock.unlock() }
            let index = min(max(0, activeLayerIndex), layers.count - 1)
            return layers[index]
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            if let idx = layers.firstIndex(where: { $0.id == newValue.id }) {
                activeLayerIndex = idx
            }
        }
    }
    
    public var visibleLayers: [any Layer] {
        lock.lock()
        defer { lock.unlock() }
        return layers.filter { $0.isVisible }
    }

    // MARK: - Initializers
    
    /// Initializes a new Document with validated canvas dimensions and an initial blank bitmap layer.
    public init(
        title: String = "Untitled",
        canvasSize: CGSize = Document.defaultCanvasSize,
        initialLayer: (any Layer)? = nil
    ) throws {
        let w = Int(canvasSize.width)
        let h = Int(canvasSize.height)
        
        guard w >= Document.minDimension && h >= Document.minDimension else {
            throw DocumentError.invalidDimensions(width: w, height: h)
        }
        guard w <= Document.maxDimensionWidth && h <= Document.maxDimensionHeight else {
            throw DocumentError.canvasExceedsMaximumSize(
                width: w,
                height: h,
                maxWidth: Document.maxDimensionWidth,
                maxHeight: Document.maxDimensionHeight
            )
        }
        
        self.id = UUID()
        self.title = title
        self.canvasSize = canvasSize
        self.viewportTransform = ViewportTransform()
        self.undoManager = TileUndoManager()
        self.selectionMask = SelectionMask(canvasSize: canvasSize)
        
        let baseLayer = initialLayer ?? BitmapLayer(name: "Background", bounds: CGRect(origin: .zero, size: canvasSize))
        self.layers = [baseLayer]
        self.activeLayerIndex = 0
    }

    // MARK: - Layer Stack CRUD Operations
    
    /// Adds a new layer at the specified index, or above the active layer by default.
    @discardableResult
    public func addLayer(_ layer: (any Layer)? = nil, at targetIndex: Int? = nil) -> any Layer {
        lock.lock()
        defer { lock.unlock() }
        
        let newLayer = layer ?? BitmapLayer(
            name: "Layer \(layers.count + 1)",
            bounds: bounds
        )
        
        let insertionIndex: Int
        if let idx = targetIndex {
            insertionIndex = min(max(0, idx), layers.count)
        } else {
            insertionIndex = min(activeLayerIndex + 1, layers.count)
        }
        
        layers.insert(newLayer, at: insertionIndex)
        activeLayerIndex = insertionIndex
        return newLayer
    }
    
    /// Duplicates the layer at the given index (or the active layer by default).
    @discardableResult
    public func duplicateLayer(at index: Int? = nil) throws -> any Layer {
        lock.lock()
        defer { lock.unlock() }
        
        let sourceIndex = index ?? activeLayerIndex
        guard sourceIndex >= 0 && sourceIndex < layers.count else {
            throw DocumentError.layerIndexOutOfBounds(index: sourceIndex, count: layers.count)
        }
        
        let source = layers[sourceIndex]
        let duplicate = source.duplicate()
        duplicate.name = "\(source.name) Copy"
        
        let targetIndex = sourceIndex + 1
        layers.insert(duplicate, at: targetIndex)
        activeLayerIndex = targetIndex
        return duplicate
    }
    
    /// Deletes the layer at the given index (or the active layer by default).
    /// Enforces the invariant that a document must never have 0 layers.
    public func deleteLayer(at index: Int? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let targetIndex = index ?? activeLayerIndex
        guard targetIndex >= 0 && targetIndex < layers.count else {
            throw DocumentError.layerIndexOutOfBounds(index: targetIndex, count: layers.count)
        }
        
        if layers.count == 1 {
            // Cannot empty layer stack; replace with fresh empty layer
            let freshLayer = BitmapLayer(name: "Layer 1", bounds: bounds)
            layers = [freshLayer]
            activeLayerIndex = 0
            return
        }
        
        let oldActiveIndex = activeLayerIndex
        layers.remove(at: targetIndex)
        if targetIndex < oldActiveIndex {
            activeLayerIndex = oldActiveIndex - 1
        } else if targetIndex == oldActiveIndex {
            activeLayerIndex = min(targetIndex, layers.count - 1)
        } else {
            activeLayerIndex = min(oldActiveIndex, layers.count - 1)
        }
    }
    
    /// Reorders a layer from sourceIndex to destinationIndex.
    public func moveLayer(from sourceIndex: Int, to destinationIndex: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard sourceIndex >= 0 && sourceIndex < layers.count else {
            throw DocumentError.layerIndexOutOfBounds(index: sourceIndex, count: layers.count)
        }
        guard destinationIndex >= 0 && destinationIndex < layers.count else {
            throw DocumentError.layerIndexOutOfBounds(index: destinationIndex, count: layers.count)
        }
        guard sourceIndex != destinationIndex else { return }
        
        let movingLayer = layers.remove(at: sourceIndex)
        layers.insert(movingLayer, at: destinationIndex)
        
        // Track selection with moved layer
        if activeLayerIndex == sourceIndex {
            activeLayerIndex = destinationIndex
        } else if sourceIndex < activeLayerIndex && destinationIndex >= activeLayerIndex {
            activeLayerIndex -= 1
        } else if sourceIndex > activeLayerIndex && destinationIndex <= activeLayerIndex {
            activeLayerIndex += 1
        }
    }
    
    /// Reorders the whole stack to match `orderedIDs` (bottom → top). IDs that are unknown are ignored and
    /// layers missing from the list keep their relative order at the end. The active layer is preserved.
    public func setLayerOrder(_ orderedIDs: [UUID]) {
        lock.lock()
        defer { lock.unlock() }

        let activeID = layers.indices.contains(activeLayerIndex) ? layers[activeLayerIndex].id : nil
        var remaining = layers
        var reordered: [any Layer] = []
        reordered.reserveCapacity(layers.count)
        for id in orderedIDs {
            if let idx = remaining.firstIndex(where: { $0.id == id }) {
                reordered.append(remaining.remove(at: idx))
            }
        }
        reordered.append(contentsOf: remaining)
        guard reordered.map({ $0.id }) != layers.map({ $0.id }) else { return }

        layers = reordered
        if let activeID, let idx = layers.firstIndex(where: { $0.id == activeID }) {
            activeLayerIndex = idx
        }
    }

    /// Selects the active layer by index with bounds safety.
    public func selectLayer(at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        activeLayerIndex = min(max(0, index), layers.count - 1)
    }
    
    /// Selects the active layer by UUID.
    public func selectLayer(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = layers.firstIndex(where: { $0.id == id }) {
            activeLayerIndex = idx
        }
    }

    // MARK: - Layer Stack Compositing Mutators
    
    /// Merges the layer at topIndex down into the layer at (topIndex - 1).
    public func mergeDown(at topIndex: Int? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let idx = topIndex ?? activeLayerIndex
        guard idx > 0 else {
            throw DocumentError.cannotMergeBottomLayer
        }
        guard idx < layers.count else {
            throw DocumentError.layerIndexOutOfBounds(index: idx, count: layers.count)
        }
        
        let topLayer = layers[idx]
        let bottomLayer = layers[idx - 1]
        
        guard !topLayer.isLocked && !bottomLayer.isLocked else {
            throw DocumentError.layerIsLocked(name: topLayer.isLocked ? topLayer.name : bottomLayer.name)
        }
        
        bottomLayer.merge(layer: topLayer, canvasSize: canvasSize)
        
        layers.remove(at: idx)
        activeLayerIndex = idx - 1
    }
    
    /// Merges all visible layers into a single newly allocated BitmapLayer.
    public func mergeVisible() throws {
        lock.lock()
        defer { lock.unlock() }
        
        let visibleIndices = layers.enumerated().compactMap { $0.element.isVisible ? $0.offset : nil }
        guard !visibleIndices.isEmpty else {
            throw DocumentError.noVisibleLayersToMerge
        }
        guard visibleIndices.count > 1 else { return } // Nothing to merge if only 1 visible
        
        let highestVisibleIndex = visibleIndices.last!
        let mergedLayer = BitmapLayer(name: "Merged Visible", bounds: bounds)
        
        for idx in visibleIndices {
            let layer = layers[idx]
            mergedLayer.composite(layer: layer, canvasSize: canvasSize)
        }
        
        // Remove old visible layers in reverse order
        for idx in visibleIndices.reversed() {
            layers.remove(at: idx)
        }
        
        let insertionIndex = min(highestVisibleIndex - (visibleIndices.count - 1), layers.count)
        layers.insert(mergedLayer, at: insertionIndex)
        activeLayerIndex = insertionIndex
    }
    
    /// Flattens the entire document onto a solid background color.
    public func flatten(backgroundColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let flatLayer = BitmapLayer(name: "Background", bounds: bounds)
        flatLayer.fillSolid(color: backgroundColor, canvasSize: canvasSize)
        
        for layer in layers where layer.isVisible {
            flatLayer.composite(layer: layer, canvasSize: canvasSize)
        }
        
        layers = [flatLayer]
        activeLayerIndex = 0
    }

    // MARK: - Canvas Geometry Operations

    /// Directly sets canvasSize and updates the selection mask (used by CropTool and CropUndoCommand).
    public func resizeCanvasDirect(newSize: CGSize) {
        lock.lock()
        defer { lock.unlock() }
        self.canvasSize = newSize
        self.selectionMask = SelectionMask(canvasSize: newSize)
    }

    // MARK: - Document Replacement & Image Import

    /// Replaces the current document's state in-place with another Document.
    /// This preserves UI bindings and immediately triggers SwiftUI view updates.
    public func replace(with other: Document) {
        lock.lock()
        self.title = other.title
        self.canvasSize = other.canvasSize
        self.layers = other.layers
        self.activeLayerIndex = other.activeLayerIndex
        self.viewportTransform = other.viewportTransform
        self.selectionMask = other.selectionMask ?? SelectionMask(canvasSize: other.canvasSize)
        self.undoManager.clear()
        lock.unlock()

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    /// Resets the document to a fresh canvas of the given size with a single background layer.
    public func resetToNewCanvas(
        title: String = "Untitled",
        size: CGSize,
        background: SIMD4<Float>? = SIMD4<Float>(1, 1, 1, 1),
        viewportSize: CGSize = CGSize(width: 1200, height: 800)
    ) throws {
        let fresh = try Document(title: title, canvasSize: size)
        if let bg = background, let layer = fresh.activeLayer as? BitmapLayer {
            layer.fillSolid(color: bg, canvasSize: size)
        }
        fresh.viewportTransform = ViewportTransform.fitToViewport(canvasSize: size, viewportSize: viewportSize)
        replace(with: fresh)
    }

    /// Sets the document title and notifies observers.
    public func setTitle(_ newTitle: String) {
        lock.lock()
        self.title = newTitle
        lock.unlock()
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    /// Opens an image file and adapts the canvas dimensions and aspect ratio to match it.
    public func openAndFitImage(url: URL, viewportSize: CGSize = CGSize(width: 1200, height: 800)) throws {
        let imported = try ImageImporter.shared.createDocument(from: url)
        imported.viewportTransform = ViewportTransform.fitToViewport(
            canvasSize: imported.canvasSize,
            viewportSize: viewportSize
        )
        replace(with: imported)
    }

    /// Imports an image file as a new layer into the current canvas.
    @discardableResult
    public func importImageAsLayer(url: URL, centerInCanvas: Bool = true) throws -> any Layer {
        let newLayer = try ImageImporter.shared.createLayer(
            from: url,
            targetCanvasSize: canvasSize,
            centerInCanvas: centerInCanvas
        )
        return addLayer(newLayer)
    }

    /// Static convenience method to create a new Document directly from an image URL.
    public static func openImage(at url: URL) throws -> Document {
        return try ImageImporter.shared.createDocument(from: url)
    }

    // MARK: - Private Helpers
    
    private func clampActiveLayerIndex() {
        guard !layers.isEmpty else {
            activeLayerIndex = 0
            return
        }
        if activeLayerIndex < 0 {
            activeLayerIndex = 0
        } else if activeLayerIndex >= layers.count {
            activeLayerIndex = layers.count - 1
        }
    }
}

extension Document {
    public func undo() {
        undoManager.undo(in: self)
        objectWillChange.send()
    }

    public func redo() {
        undoManager.redo(in: self)
        objectWillChange.send()
    }

    public func beginUndoGroup(_ name: String = "Action") {
        undoManager.beginUndoGrouping(name: name)
    }

    public func endUndoGroup() {
        undoManager.endUndoGrouping()
        objectWillChange.send()
    }

    public func markDirty() {
        objectWillChange.send()
    }

    /// Replaces the pixel content of a bitmap layer with `newGrid` and records a single undo step.
    /// Used by all "generators" (transform, pixelate, chroma key, liquify, AI background removal) so they
    /// can be undone with Cmd+Z — previously they opened an undo group but registered nothing in it.
    public func commitGridEdit(layer: BitmapLayer, newGrid: SparseTileGrid, actionName: String) {
        let before = layer.tileGrid.duplicate()
        commitGridEdit(layer: layer, before: before, newGrid: newGrid, actionName: actionName)
    }

    /// Same as above, but with an explicit "before" snapshot (for edits that were previewed live on the layer).
    public func commitGridEdit(layer: BitmapLayer, before: SparseTileGrid, newGrid: SparseTileGrid, actionName: String) {
        layer.tileGrid.copyFrom(newGrid)

        let coords = Set(before.allAllocatedCoordinates()).union(newGrid.allAllocatedCoordinates())
        var beforeTiles: [TileCoord: Data?] = [:]
        var afterTiles: [TileCoord: Data?] = [:]
        for coord in coords {
            let b = before.extractTileData(coord: coord)
            let a = newGrid.extractTileData(coord: coord)
            if b == a { continue }
            beforeTiles.updateValue(b, forKey: coord)
            afterTiles.updateValue(a, forKey: coord)
        }
        if !beforeTiles.isEmpty {
            undoManager.registerCommand(TileDeltaUndoCommand(
                actionName: actionName,
                layerId: layer.id,
                beforeTiles: beforeTiles,
                afterTiles: afterTiles
            ))
        }
        objectWillChange.send()
    }
}

