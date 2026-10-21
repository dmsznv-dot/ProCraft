import CoreGraphics
import Foundation

// MARK: - UndoCommand Protocol

public protocol UndoCommand: AnyObject, Sendable {
    var actionName: String { get }
    var estimatedMemoryBytes: Int { get }
    func undo(in document: Document)
    func redo(in document: Document)
}

// MARK: - TileDeltaUndoCommand

/// Stores before/after snapshots of modified 512x512 tiles for a specific layer.
/// Yields over 98% memory reduction compared to copying full layer buffers on 8K canvases.
public final class TileDeltaUndoCommand: UndoCommand, @unchecked Sendable {
    public let actionName: String
    public let layerId: UUID
    public let beforeTiles: [TileCoord: Data?]
    public let afterTiles: [TileCoord: Data?]

    public init(
        actionName: String,
        layerId: UUID,
        beforeTiles: [TileCoord: Data?],
        afterTiles: [TileCoord: Data?]
    ) {
        self.actionName = actionName
        self.layerId = layerId
        self.beforeTiles = beforeTiles
        self.afterTiles = afterTiles
    }

    public var estimatedMemoryBytes: Int {
        var bytes = 0
        for d in beforeTiles.values {
            bytes += d?.count ?? 0
        }
        for d in afterTiles.values {
            bytes += d?.count ?? 0
        }
        return bytes
    }

    public func undo(in document: Document) {
        guard let layer = document.layers.first(where: { $0.id == layerId }) as? BitmapLayer else { return }
        for (coord, maybeData) in beforeTiles {
            if let data = maybeData {
                layer.tileGrid.loadTileData(coord: coord, data: data)
            } else {
                layer.tileGrid.removeTile(at: coord)
            }
        }
    }

    public func redo(in document: Document) {
        guard let layer = document.layers.first(where: { $0.id == layerId }) as? BitmapLayer else { return }
        for (coord, maybeData) in afterTiles {
            if let data = maybeData {
                layer.tileGrid.loadTileData(coord: coord, data: data)
            } else {
                layer.tileGrid.removeTile(at: coord)
            }
        }
    }
}

// MARK: - CompoundUndoCommand

/// Groups multiple commands into a single user-perceived undo step.
public final class CompoundUndoCommand: UndoCommand, @unchecked Sendable {
    public let actionName: String
    public private(set) var commands: [any UndoCommand] = []

    public init(actionName: String) {
        self.actionName = actionName
    }

    public func add(command: any UndoCommand) {
        commands.append(command)
    }

    public var estimatedMemoryBytes: Int {
        commands.reduce(0) { $0 + $1.estimatedMemoryBytes }
    }

    public func undo(in document: Document) {
        for cmd in commands.reversed() {
            cmd.undo(in: document)
        }
    }

    public func redo(in document: Document) {
        for cmd in commands {
            cmd.redo(in: document)
        }
    }
}

// MARK: - TileUndoManager

/// Thread-safe Tile-Delta Undo/Redo Engine with grouping, capacity limits, memory eviction, and document dirty tracking.
public final class TileUndoManager: @unchecked Sendable {
    public static let defaultMaxSteps: Int = 50
    public static let defaultMaxMemoryBytes: Int = 512 * 1024 * 1024 // 512 MB

    public let maxSteps: Int
    public let maxMemoryBytes: Int

    private let lock = NSLock()
    private var undoStack: [any UndoCommand] = []
    private var redoStack: [any UndoCommand] = []

    private var groupingDepth: Int = 0
    private var activeCompoundCommand: CompoundUndoCommand?

    private var savedStepIndex: Int? = 0

    public init(maxSteps: Int = defaultMaxSteps, maxMemoryBytes: Int = defaultMaxMemoryBytes) {
        self.maxSteps = maxSteps
        self.maxMemoryBytes = maxMemoryBytes
    }

    public var canUndo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !undoStack.isEmpty
    }

    public var canRedo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !redoStack.isEmpty
    }

    public var undoActionName: String? {
        lock.lock()
        defer { lock.unlock() }
        return undoStack.last?.actionName
    }

    public var redoActionName: String? {
        lock.lock()
        defer { lock.unlock() }
        return redoStack.last?.actionName
    }

    public var undoCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return undoStack.count
    }

    public var redoCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return redoStack.count
    }

    public var isDirty: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let saved = savedStepIndex else { return true }
        return undoStack.count != saved
    }

    public func markSaved() {
        lock.lock()
        defer { lock.unlock() }
        savedStepIndex = undoStack.count
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        undoStack.removeAll()
        redoStack.removeAll()
        groupingDepth = 0
        activeCompoundCommand = nil
        savedStepIndex = 0
    }

    // MARK: - Undo Grouping

    public func beginUndoGrouping(name: String = "Action") {
        lock.lock()
        defer { lock.unlock() }
        groupingDepth += 1
        if groupingDepth == 1 {
            activeCompoundCommand = CompoundUndoCommand(actionName: name)
        }
    }

    public func endUndoGrouping() {
        lock.lock()
        defer { lock.unlock() }
        guard groupingDepth > 0 else { return }
        groupingDepth -= 1
        if groupingDepth == 0, let compound = activeCompoundCommand {
            activeCompoundCommand = nil
            if !compound.commands.isEmpty {
                pushCommandInternal(compound)
            }
        }
    }

    public func cancelUndoGrouping() {
        lock.lock()
        defer { lock.unlock() }
        groupingDepth = 0
        activeCompoundCommand = nil
    }

    // MARK: - Recording Actions

    public func registerCommand(_ command: any UndoCommand) {
        lock.lock()
        defer { lock.unlock() }
        if groupingDepth > 0, let activeGroup = activeCompoundCommand {
            activeGroup.add(command: command)
        } else {
            pushCommandInternal(command)
        }
    }

    private func pushCommandInternal(_ command: any UndoCommand) {
        redoStack.removeAll()
        undoStack.append(command)
        enforceLimits()
    }

    private func enforceLimits() {
        while undoStack.count > maxSteps {
            undoStack.removeFirst()
            if let saved = savedStepIndex {
                savedStepIndex = saved > 0 ? saved - 1 : nil
            }
        }

        var totalBytes = undoStack.reduce(0) { $0 + $1.estimatedMemoryBytes }
        while totalBytes > maxMemoryBytes && undoStack.count > 1 {
            let removed = undoStack.removeFirst()
            totalBytes -= removed.estimatedMemoryBytes
            if let saved = savedStepIndex {
                savedStepIndex = saved > 0 ? saved - 1 : nil
            }
        }
    }

    // MARK: - Undo & Redo Execution

    public func undo(in document: Document) {
        lock.lock()
        guard let command = undoStack.popLast() else {
            lock.unlock()
            return
        }
        redoStack.append(command)
        lock.unlock()

        command.undo(in: document)
    }

    public func redo(in document: Document) {
        lock.lock()
        guard let command = redoStack.popLast() else {
            lock.unlock()
            return
        }
        undoStack.append(command)
        lock.unlock()

        command.redo(in: document)
    }
}
