import SwiftUI
import UniformTypeIdentifiers
import PixelCraftEngine

/// One row of the layer list. Wrapping the existential `any Layer` in a value type gives SwiftUI a
/// stable `Identifiable` element (needed for List selection and drag-to-reorder).
private struct LayerRowItem: Identifiable {
    let id: UUID
    let index: Int
    let layer: any Layer
}

struct SidebarView: View {
    @ObservedObject var document: Document
    @ObservedObject var state: EditorState
    @State private var selectedTab: Int = 0 // 0: Layers, 1: History
    @State private var isDropOverLayers: Bool = false
    @State private var renamingLayerID: UUID?
    @State private var renameText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Layers").tag(0)
                Text("History").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()

            if selectedTab == 0 {
                layersPanel
            } else {
                historyPanel
            }
        }
        .frame(minWidth: 230, idealWidth: 260)
        .alert("Rename Layer", isPresented: Binding(
            get: { renamingLayerID != nil },
            set: { if !$0 { renamingLayerID = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renamingLayerID = nil }
        }
    }

    // MARK: - Layers

    /// Top-most layer first, like in every editor.
    private var rows: [LayerRowItem] {
        document.layers.enumerated().reversed().map { LayerRowItem(id: $0.element.id, index: $0.offset, layer: $0.element) }
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { document.layers.indices.contains(document.activeLayerIndex) ? document.layers[document.activeLayerIndex].id : nil },
            set: { newID in
                guard let newID else { return }
                if state.hasPendingChanges { state.commitPending() }
                document.selectLayer(id: newID)
            }
        )
    }

    private var layersPanel: some View {
        VStack(spacing: 0) {
            // Blend mode & opacity of the active layer
            VStack(spacing: 6) {
                HStack {
                    Text("Blend")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                    Picker("", selection: Binding<PixelCraftEngine.BlendMode>(
                        get: { document.activeLayer.blendMode },
                        set: { val in
                            document.activeLayer.blendMode = val
                            document.markDirty()
                        }
                    )) {
                        ForEach(PixelCraftEngine.BlendMode.allCases) { mode in
                            Text(mode.description).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }

                HStack {
                    Text("Opacity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                    Slider(value: Binding<Double>(
                        get: { Double(document.activeLayer.opacity) },
                        set: { val in
                            document.activeLayer.opacity = Float(val)
                            document.markDirty()
                        }
                    ), in: 0.0...1.0)
                    .controlSize(.small)
                    Text("\(Int((document.activeLayer.opacity * 100).rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            List(selection: selection) {
                ForEach(rows) { row in
                    layerRow(row)
                        .contextMenu { contextMenu(for: row) }
                }
                .onMove(perform: moveRows)
            }
            .listStyle(.inset)
            .onDrop(of: [.fileURL], isTargeted: $isDropOverLayers) { providers in
                guard let provider = providers.first else { return false }
                // Capture Sendable references only (not the View struct) for the background callback.
                let doc = document
                let editor = state
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        _ = try? doc.importImageAsLayer(url: url)
                        editor.redrawCanvas()
                    }
                }
                return true
            }

            Divider()

            // Bottom action bar (Photoshop-like)
            HStack(spacing: 14) {
                iconButton("plus", help: "New Layer (⇧⌘N)") {
                    document.addLayer()
                    state.redrawCanvas()
                }
                iconButton("photo.badge.plus", help: "Import Image as Layer (⌘I)") {
                    FileActions.importLayer(document: document, state: state)
                }
                iconButton("plus.square.on.square", help: "Duplicate Layer (⌘J)") {
                    _ = try? document.duplicateLayer()
                    state.redrawCanvas()
                }
                iconButton("arrow.down.to.line", help: "Merge Down (⌘E)") {
                    state.commitPending()
                    try? document.mergeDown()
                    state.redrawCanvas()
                }
                Spacer()
                iconButton("trash", help: "Delete Layer") {
                    state.commitPending()
                    try? document.deleteLayer()
                    state.redrawCanvas()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func layerRow(_ row: LayerRowItem) -> some View {
        let layer = row.layer
        return HStack(spacing: 8) {
            Button {
                layer.isVisible.toggle()
                document.markDirty()
                state.redrawCanvas()
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundColor(layer.isVisible ? .primary : .secondary.opacity(0.5))
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help(layer.isVisible ? "Hide layer" : "Show layer")

            Image(systemName: icon(for: layer))
                .foregroundColor(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name)
                    .font(.system(size: 13, weight: row.index == document.activeLayerIndex ? .semibold : .regular))
                    .lineLimit(1)
                Text("\(layer.blendMode.description) · \(Int((layer.opacity * 100).rounded()))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                layer.lockAlpha.toggle()
                document.markDirty()
            } label: {
                Image(systemName: layer.lockAlpha ? "lock.fill" : "lock.open")
                    .font(.caption)
                    .foregroundColor(layer.lockAlpha ? .accentColor : .secondary.opacity(0.4))
            }
            .buttonStyle(.borderless)
            .help("Lock transparent pixels")
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func contextMenu(for row: LayerRowItem) -> some View {
        Button("Rename…") {
            renameText = row.layer.name
            renamingLayerID = row.id
        }
        Button("Duplicate") {
            _ = try? document.duplicateLayer(at: row.index)
            state.redrawCanvas()
        }
        Button("Merge Down") {
            state.commitPending()
            try? document.mergeDown(at: row.index)
            state.redrawCanvas()
        }
        .disabled(row.index == 0)
        Divider()
        Button("Move Up") {
            try? document.moveLayer(from: row.index, to: row.index + 1)
            state.redrawCanvas()
        }
        .disabled(row.index >= document.layers.count - 1)
        Button("Move Down") {
            try? document.moveLayer(from: row.index, to: row.index - 1)
            state.redrawCanvas()
        }
        .disabled(row.index == 0)
        Divider()
        Button("Delete", role: .destructive) {
            state.commitPending()
            try? document.deleteLayer(at: row.index)
            state.redrawCanvas()
        }
    }

    private func icon(for layer: any Layer) -> String {
        switch layer {
        case is TextLayer: return "textformat"
        case is AdjustmentLayer: return "slider.horizontal.3"
        case is EffectLayer: return "sparkles"
        default: return "photo"
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    /// Drag-to-reorder. The list shows layers top-first, the model stores them bottom-first.
    private func moveRows(from source: IndexSet, to destination: Int) {
        var displayed = rows.map { $0.id }
        displayed.move(fromOffsets: source, toOffset: destination)
        document.setLayerOrder(Array(displayed.reversed()))
        state.redrawCanvas()
    }

    private func commitRename() {
        defer { renamingLayerID = nil }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = renamingLayerID, !name.isEmpty,
              let layer = document.layers.first(where: { $0.id == id }) else { return }
        layer.name = name
        document.markDirty()
    }

    // MARK: - History

    private var historyPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    state.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!document.undoManager.canUndo && !state.hasPendingChanges)

                Spacer()

                Button {
                    state.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!document.undoManager.canRedo)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            List {
                Text("Document opened")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let name = document.undoManager.undoActionName {
                    Label("Last: \(name)", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                }
                Text("\(document.undoManager.undoCount) step(s) can be undone, \(document.undoManager.redoCount) redone")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .listStyle(.inset)
        }
    }
}
