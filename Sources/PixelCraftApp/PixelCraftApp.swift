import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PixelCraftEngine

@main
struct PixelCraftApp: App {
    @StateObject private var document: Document = {
        do {
            let doc = try Document(title: "Untitled", canvasSize: CGSize(width: 1920, height: 1080))
            // Pre-seed some default artwork on the initial background layer
            if let bg = doc.activeLayer as? BitmapLayer {
                // Soft gradient/canvas backdrop
                for y in 0..<1080 {
                    let v = Float(y) / 1080.0
                    for x in 0..<1920 {
                        let u = Float(x) / 1920.0
                        let r = UInt8(clamping: Int(round(u * 80.0 + 30.0)))
                        let g = UInt8(clamping: Int(round(v * 70.0 + 30.0)))
                        let b = UInt8(clamping: Int(round((1.0 - u) * 90.0 + 40.0)))
                        bg.tileGrid.setPixel(x: x, y: y, color: (r, g, b, 255))
                    }
                }
            }
            return doc
        } catch {
            fatalError("Failed to initialize default document: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup("PixelCraft Pro") {
            MainEditorView(document: document)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Document...") {
                    // Reset to fresh document
                    try? document.deleteLayer(at: 0)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Image or Project...") {
                    openProjectDialog()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Import Image as Layer...") {
                    importLayerDialog()
                }
                .keyboardShortcut("i", modifiers: .command)

                Divider()

                Button("Save Project (.pcpro)") {
                    saveProjectDialog()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save as PSD...") {
                    savePSDDialog()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    document.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!document.undoManager.canUndo)

                Button("Redo") {
                    document.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!document.undoManager.canRedo)
            }

            CommandMenu("Layer") {
                Button("New Layer") {
                    _ = document.addLayer()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Duplicate Layer") {
                    _ = try? document.duplicateLayer()
                }
                .keyboardShortcut("j", modifiers: .command)

                Button("Delete Layer") {
                    try? document.deleteLayer()
                }

                Divider()

                Button("Merge Down") {
                    try? document.mergeDown()
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Merge Visible") {
                    try? document.mergeVisible()
                }

                Button("Flatten Image") {
                    try? document.flatten()
                }
            }

            CommandMenu("View") {
                Button("Zoom In") {
                    let center = CGPoint(x: document.width / 2, y: document.height / 2)
                    document.viewportTransform.zoom(by: 1.25, aroundScreenPoint: center)
                    document.markDirty()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    let center = CGPoint(x: document.width / 2, y: document.height / 2)
                    document.viewportTransform.zoom(by: 0.8, aroundScreenPoint: center)
                    document.markDirty()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size (100%)") {
                    document.viewportTransform.zoom = 1.0
                    document.viewportTransform.panOffset = .zero
                    document.markDirty()
                }
                .keyboardShortcut("0", modifiers: .command)

                Button("Fit to Screen") {
                    document.viewportTransform = ViewportTransform.fitToViewport(
                        canvasSize: document.canvasSize,
                        viewportSize: CGSize(width: 1200, height: 800)
                    )
                    document.markDirty()
                }
                .keyboardShortcut("9", modifiers: .command)
            }
        }
    }

    private func saveProjectDialog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pcpro") ?? .package]
        panel.nameFieldStringValue = "\(document.title).pcpro"

        if panel.runModal() == .OK, let url = panel.url {
            let codec = PCProDocument()
            if let wrapper = try? codec.serialize(document: document) {
                try? wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
            }
        }
    }

    private func savePSDDialog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "psd") ?? .data]
        panel.nameFieldStringValue = "\(document.title).psd"

        if panel.runModal() == .OK, let url = panel.url {
            let codec = PSDCodec()
            let data = codec.encode(document: document)
            try? data.write(to: url)
        }
    }

    private func openProjectDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType.png,
            UTType.jpeg,
            UTType.tiff,
            UTType.heic,
            UTType.image,
            UTType(filenameExtension: "webp") ?? .data,
            UTType(filenameExtension: "pcpro") ?? .package,
            UTType(filenameExtension: "psd") ?? .data
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            handleFileOpen(url: url, asNewLayer: false)
        }
    }

    private func importLayerDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType.png,
            UTType.jpeg,
            UTType.tiff,
            UTType.heic,
            UTType.image,
            UTType(filenameExtension: "webp") ?? .data
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            handleFileOpen(url: url, asNewLayer: true)
        }
    }

    private func handleFileOpen(url: URL, asNewLayer: Bool) {
        let ext = url.pathExtension.lowercased()
        if ext == "pcpro" {
            if let wrapper = try? FileWrapper(url: url, options: .immediate) {
                let codec = PCProDocument()
                if let loadedDoc = try? codec.deserialize(wrapper: wrapper) {
                    document.replace(with: loadedDoc)
                }
            }
        } else if ext == "psd" {
            if let data = try? Data(contentsOf: url) {
                let codec = PSDCodec()
                if let loadedDoc = try? codec.decode(data: data) {
                    document.replace(with: loadedDoc)
                }
            }
        } else if ImageImporter.isImageFile(url: url) {
            do {
                if asNewLayer {
                    _ = try document.importImageAsLayer(url: url)
                } else {
                    try document.openAndFitImage(url: url)
                }
            } catch {
                print("Failed to open or import image: \(error)")
            }
        }
    }
}

public struct MainEditorView: View {
    @ObservedObject public var document: Document

    // Active tool state
    @State private var activeTool: ActiveToolType = .brush
    @State private var activeColor: Color = .blue
    @State private var brushSize: CGFloat = 24.0
    @State private var brushOpacity: Float = 1.0
    @State private var brushFlow: Float = 1.0
    @State private var brushHardness: Float = 0.8
    @State private var isSidebarVisible: NavigationSplitViewVisibility = .all
    @State private var isDropTargeted: Bool = false

    public init(document: Document) {
        self.document = document
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $isSidebarVisible) {
            SidebarView(document: document)
        } detail: {
            ZStack {
                // Interactive Metal Canvas
                CanvasViewRepresentable(
                    document: document,
                    activeTool: activeTool,
                    brushColor: NSColor(activeColor),
                    brushSize: brushSize,
                    brushOpacity: brushOpacity,
                    brushFlow: brushFlow,
                    brushHardness: brushHardness,
                    onColorSampled: { sampled in
                        activeColor = Color(nsColor: sampled)
                    },
                    onFileDropped: { url, isOption in
                        handleFileDrop(url: url, asNewLayer: isOption)
                    }
                )
                .ignoresSafeArea()

                // Floating Bottom Toolbar
                VStack {
                    Spacer()
                    FloatingToolbarView(activeTool: $activeTool, activeColor: $activeColor)
                        .padding(.bottom, 20)
                }

                // Top-Left HUD Info Bar
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(document.title) — \(document.width) × \(document.height) px (\(String(format: "%.2f:1", document.aspectRatio)))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))

                            Text("Zoom: \(Int(document.viewportTransform.zoom * 100))% | Tool: \(activeTool.title)")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.5))
                        )
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.leading, 12)
                    Spacer()
                }

                // Drag & Drop Feedback HUD
                if isDropTargeted {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.accentColor, lineWidth: 3.5)
                            .background(Color.accentColor.opacity(0.12))

                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundColor(.accentColor)

                            Text("Drop Image to Open & Adapt Canvas")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)

                            Text("Canvas will adapt to exact image dimensions\nHold ⌥ Option to import as a new layer")
                                .font(.system(size: 12))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(28)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.4), radius: 25, x: 0, y: 10)
                    }
                    .padding(24)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        let isOption = NSEvent.modifierFlags.contains(.option)
                        handleFileDrop(url: url, asNewLayer: isOption)
                    }
                }
                return true
            }
        }
        .inspector(isPresented: .constant(true)) {
            InspectorView(
                document: document,
                activeTool: $activeTool,
                activeColor: $activeColor,
                brushSize: $brushSize,
                brushOpacity: $brushOpacity,
                brushFlow: $brushFlow,
                brushHardness: $brushHardness
            )
        }
    }

    private func handleFileDrop(url: URL, asNewLayer: Bool) {
        let ext = url.pathExtension.lowercased()
        if ext == "pcpro" {
            if let wrapper = try? FileWrapper(url: url, options: .immediate) {
                let codec = PCProDocument()
                if let loadedDoc = try? codec.deserialize(wrapper: wrapper) {
                    document.replace(with: loadedDoc)
                }
            }
        } else if ext == "psd" {
            if let data = try? Data(contentsOf: url) {
                let codec = PSDCodec()
                if let loadedDoc = try? codec.decode(data: data) {
                    document.replace(with: loadedDoc)
                }
            }
        } else if ImageImporter.isImageFile(url: url) {
            do {
                if asNewLayer {
                    _ = try document.importImageAsLayer(url: url)
                } else {
                    try document.openAndFitImage(url: url)
                }
            } catch {
                print("Failed to open or import image: \(error)")
            }
        }
    }
}
