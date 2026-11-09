import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PixelCraftEngine

@main
struct PixelCraftApp: App {
    @StateObject private var state = EditorState(document: PixelCraftApp.makeInitialDocument())

    /// Initial 1920×1080 document with a soft gradient backdrop.
    /// Built as one RGBA buffer (the old per-pixel loop issued ~2M GPU texture writes at launch).
    private static func makeInitialDocument() -> Document {
        let w = 1920, h = 1080
        do {
            let doc = try Document(title: "Untitled", canvasSize: CGSize(width: w, height: h))
            if let bg = doc.activeLayer as? BitmapLayer {
                var rgba = [UInt8](repeating: 255, count: w * h * 4)
                for y in 0..<h {
                    let v = Float(y) / Float(h)
                    for x in 0..<w {
                        let u = Float(x) / Float(w)
                        let o = (y * w + x) * 4
                        rgba[o] = UInt8(clamping: Int((u * 80.0 + 30.0).rounded()))
                        rgba[o + 1] = UInt8(clamping: Int((v * 70.0 + 30.0).rounded()))
                        rgba[o + 2] = UInt8(clamping: Int(((1.0 - u) * 90.0 + 40.0).rounded()))
                    }
                }
                bg.tileGrid.writeRGBA(rgba)
            }
            return doc
        } catch {
            fatalError("Failed to initialize default document: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("PixelCraft Pro") {
            MainEditorView(state: state, document: state.document)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Document…") {
                    state.isNewDocumentSheetPresented = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Image or Project…") {
                    FileActions.open(state: state)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Import Image as Layer…") {
                    FileActions.importLayer(document: state.document, state: state)
                }
                .keyboardShortcut("i", modifiers: .command)

                Divider()

                Button("Save Project (.pcpro)…") {
                    FileActions.saveProject(state: state)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save as PSD…") {
                    FileActions.savePSD(state: state)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Export Image…") {
                    state.commitPending()
                    state.isExportSheetPresented = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    state.undo()
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    state.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandMenu("Select") {
                Button("All") {
                    if !FileActions.forwardToTextField(#selector(NSText.selectAll(_:))) {
                        state.selectAll()
                    }
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Deselect") {
                    state.deselect()
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Inverse") {
                    state.invertSelection()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            CommandMenu("Layer") {
                Button("New Layer") {
                    state.commitPending()
                    state.document.addLayer()
                    state.redrawCanvas()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Duplicate Layer") {
                    state.commitPending()
                    _ = try? state.document.duplicateLayer()
                    state.redrawCanvas()
                }
                .keyboardShortcut("j", modifiers: .command)

                Button("Delete Layer") {
                    state.commitPending()
                    try? state.document.deleteLayer()
                    state.redrawCanvas()
                }

                Divider()

                Button("Bring Forward") {
                    let doc = state.document
                    try? doc.moveLayer(from: doc.activeLayerIndex, to: doc.activeLayerIndex + 1)
                    state.redrawCanvas()
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Send Backward") {
                    let doc = state.document
                    try? doc.moveLayer(from: doc.activeLayerIndex, to: doc.activeLayerIndex - 1)
                    state.redrawCanvas()
                }
                .keyboardShortcut("[", modifiers: .command)

                Divider()

                Button("Merge Down") {
                    state.commitPending()
                    try? state.document.mergeDown()
                    state.redrawCanvas()
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Merge Visible") {
                    state.commitPending()
                    try? state.document.mergeVisible()
                    state.redrawCanvas()
                }

                Button("Flatten Image") {
                    state.commitPending()
                    try? state.document.flatten()
                    state.redrawCanvas()
                }
            }

            // Goes into the system "View" menu instead of creating a second one.
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { state.zoom(by: 1.25) }
                    .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") { state.zoom(by: 0.8) }
                    .keyboardShortcut("-", modifiers: .command)

                Button("Fit on Screen") { state.fitToScreen() }
                    .keyboardShortcut("0", modifiers: .command)

                Button("Actual Size (100%)") { state.actualSize() }
                    .keyboardShortcut("1", modifiers: .command)
            }
        }
    }
}

// MARK: - Main Window

struct MainEditorView: View {
    @ObservedObject var state: EditorState
    @ObservedObject var document: Document
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(document: document, state: state)
        } detail: {
            VStack(spacing: 0) {
                ToolOptionsBar(state: state, document: document)
                Divider()

                ZStack {
                    CanvasViewRepresentable(state: state, document: document) { url, asLayer in
                        FileActions.handleOpen(url: url, asNewLayer: asLayer, state: state)
                    }

                    // Right: generator dock (Photoshop-like collapsible panels)
                    VStack {
                        HStack {
                            Spacer()
                            GeneratorDock(state: state)
                        }
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 12)

                    // Bottom: basic tools only
                    VStack {
                        Spacer()
                        FloatingToolbarView(state: state)
                            .padding(.bottom, 16)
                    }
                }
                .clipped()
            }
        }
        .sheet(isPresented: $state.isNewDocumentSheetPresented) {
            NewDocumentSheet(state: state)
        }
        .sheet(isPresented: $state.isExportSheetPresented) {
            ExportSheet(state: state)
        }
    }
}

// MARK: - File Actions

@MainActor
enum FileActions {
    /// If a text field is being edited, forwards a standard edit action to it and returns true.
    static func forwardToTextField(_ action: Selector) -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder, responder is NSText else { return false }
        return NSApp.sendAction(action, to: nil, from: nil)
    }

    static func showError(_ title: String, _ error: Error? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        if let error {
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
    }

    private static let imageTypes: [UTType] = [
        .png, .jpeg, .tiff, .heic, .image,
        UTType(filenameExtension: "webp") ?? .image
    ]

    static func open(state: EditorState) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = imageTypes + [
            UTType(filenameExtension: "pcpro") ?? .package,
            UTType(filenameExtension: "psd") ?? .data
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            handleOpen(url: url, asNewLayer: false, state: state)
        }
    }

    static func importLayer(document: Document, state: EditorState) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = imageTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            handleOpen(url: url, asNewLayer: true, state: state)
        }
    }

    static func handleOpen(url: URL, asNewLayer: Bool, state: EditorState) {
        let document = state.document
        let ext = url.pathExtension.lowercased()
        state.commitPending()
        do {
            if ext == "pcpro" {
                let wrapper = try FileWrapper(url: url, options: .immediate)
                let loaded = try PCProDocument().deserialize(wrapper: wrapper)
                document.replace(with: loaded)
                state.fitToScreen()
            } else if ext == "psd" {
                let data = try Data(contentsOf: url)
                let loaded = try PSDCodec().decode(data: data)
                document.replace(with: loaded)
                state.fitToScreen()
            } else if ImageImporter.isImageFile(url: url) {
                if asNewLayer {
                    _ = try document.importImageAsLayer(url: url)
                } else {
                    try document.openAndFitImage(url: url, viewportSize: state.viewportSize)
                }
            } else {
                showError("Unsupported file type “.\(ext)”.")
                return
            }
        } catch {
            showError("Could not open “\(url.lastPathComponent)”.", error)
            return
        }
        state.refreshSelectionOutline()
        state.redrawCanvas()
    }

    static func saveProject(state: EditorState) {
        state.commitPending()
        let document = state.document
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pcpro") ?? .package]
        panel.nameFieldStringValue = "\(document.title).pcpro"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let wrapper = try PCProDocument().serialize(document: document)
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
            document.undoManager.markSaved()
        } catch {
            showError("Could not save the project.", error)
        }
    }

    static func savePSD(state: EditorState) {
        state.commitPending()
        let document = state.document
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "psd") ?? .data]
        panel.nameFieldStringValue = "\(document.title).psd"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PSDCodec().encode(document: document).write(to: url)
        } catch {
            showError("Could not save the PSD file.", error)
        }
    }
}

// MARK: - New Document

struct NewDocumentSheet: View {
    @ObservedObject var state: EditorState
    @Environment(\.dismiss) private var dismiss

    @State private var width: Int = 1920
    @State private var height: Int = 1080
    @State private var background: Int = 0 // 0 white, 1 transparent, 2 secondary color
    @State private var errorText: String?

    private let presets: [(String, Int, Int)] = [
        ("Full HD 1920×1080", 1920, 1080),
        ("4K UHD 3840×2160", 3840, 2160),
        ("8K 8192×4320", 8192, 4320),
        ("Square 1080×1080", 1080, 1080),
        ("Story 1080×1920", 1080, 1920),
        ("Square 2048×2048", 2048, 2048)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Document").font(.title2.bold())

            Menu("Presets") {
                ForEach(presets.indices, id: \.self) { i in
                    Button(presets[i].0) {
                        width = presets[i].1
                        height = presets[i].2
                    }
                }
            }
            .frame(width: 220)

            Form {
                TextField("Width (px)", value: $width, format: .number)
                TextField("Height (px)", value: $height, format: .number)
                Picker("Background", selection: $background) {
                    Text("White").tag(0)
                    Text("Transparent").tag(1)
                    Text("Secondary color").tag(2)
                }
            }

            Text("Max \(Document.maxDimensionWidth) × \(Document.maxDimensionHeight) px")
                .font(.caption)
                .foregroundColor(.secondary)

            if let errorText {
                Text(errorText).font(.caption).foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func create() {
        let bg: SIMD4<Float>?
        switch background {
        case 1: bg = nil
        case 2: bg = EditorState.simdColor(state.secondaryColor)
        default: bg = SIMD4<Float>(1, 1, 1, 1)
        }
        do {
            state.cancelPending()
            try state.document.resetToNewCanvas(
                title: "Untitled",
                size: CGSize(width: width, height: height),
                background: bg,
                viewportSize: state.viewportSize
            )
            state.refreshSelectionOutline()
            state.redrawCanvas()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Export

struct ExportSheet: View {
    @ObservedObject var state: EditorState
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .png8
    @State private var quality: Double = 0.9
    @State private var activeLayerOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Image").font(.title2.bold())

            Form {
                Picker("Format", selection: $format) {
                    Text("PNG (8-bit)").tag(ExportFormat.png8)
                    Text("PNG (16-bit)").tag(ExportFormat.png16)
                    Text("JPEG").tag(ExportFormat.jpeg)
                    Text("TIFF").tag(ExportFormat.tiff)
                    Text("HEIC").tag(ExportFormat.heic)
                }
                if format == .jpeg || format == .heic {
                    LabeledSlider(title: "Quality", value: $quality, range: 0.1...1, percent: true)
                }
                Toggle("Active layer only", isOn: $activeLayerOnly)
            }

            Text(format == .jpeg
                 ? "JPEG has no transparency: transparent areas are exported as white."
                 : "Transparency is preserved.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { export() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func export() {
        let document = state.document
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .png]
        panel.nameFieldStringValue = "\(document.title).\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let background: SIMD4<Float>? = format == .jpeg ? SIMD4<Float>(1, 1, 1, 1) : nil
        let grid: SparseTileGrid
        if activeLayerOnly {
            if let background {
                let flat = BitmapLayer(name: "Export", bounds: document.bounds)
                flat.fillSolid(color: background, canvasSize: document.canvasSize)
                flat.composite(layer: document.activeLayer, canvasSize: document.canvasSize)
                grid = flat.tileGrid
            } else {
                grid = document.activeLayer.tileGrid
            }
        } else {
            grid = state.compositeGrid(background: background)
        }

        let options = ExportOptions(format: format, quality: Float(quality), preserveAlpha: format != .jpeg)
        guard let data = ImageExporter().export(grid: grid, options: options) else {
            FileActions.showError("Export failed: the image could not be encoded.")
            return
        }
        do {
            try data.write(to: url)
            dismiss()
        } catch {
            FileActions.showError("Could not write the exported file.", error)
        }
    }
}
