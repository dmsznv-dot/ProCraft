import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PixelCraftEngine

public struct InspectorView: View {
    @ObservedObject public var document: Document
    @Binding public var activeTool: ActiveToolType
    @Binding public var activeColor: Color
    @Binding public var brushSize: CGFloat
    @Binding public var brushOpacity: Float
    @Binding public var brushFlow: Float
    @Binding public var brushHardness: Float

    // Transform state
    @State private var transformScaleX: CGFloat = 1.0
    @State private var transformScaleY: CGFloat = 1.0
    @State private var transformRotation: Double = 0.0 // degrees
    @State private var transformInterpolation: InterpolationMode = .bilinear

    // Liquify state
    @State private var liquifyMode: LiquifyToolMode = .push
    @State private var liquifyRadius: CGFloat = 64.0
    @State private var liquifyPressure: Float = 0.5
    @State private var liquifyEngine: LiquifyEngine?

    // Chroma Key state
    @State private var chromaTolerance: Float = 25.0
    @State private var chromaFeather: Float = 10.0
    @State private var chromaSpill: Float = 0.75

    // AI Background state
    @State private var isProcessingAI = false
    @State private var aiRefineEdges = true
    @State private var aiStatusMessage: String?

    // ASCII Art state
    @State private var asciiColumns: Int = 100
    @State private var asciiRows: Int = 50
    @State private var asciiCharSetChoice = 0 // 0: Standard, 1: Unicode, 2: Custom
    @State private var asciiCustomChars: String = " .:-=+*#%@"
    @State private var asciiDithering = true

    // Export state
    @State private var exportFormat: ExportFormat = .png8
    @State private var exportQuality: Float = 0.9
    @State private var isExporting = false

    public init(
        document: Document,
        activeTool: Binding<ActiveToolType>,
        activeColor: Binding<Color>,
        brushSize: Binding<CGFloat>,
        brushOpacity: Binding<Float>,
        brushFlow: Binding<Float>,
        brushHardness: Binding<Float>
    ) {
        self.document = document
        self._activeTool = activeTool
        self._activeColor = activeColor
        self._brushSize = brushSize
        self._brushOpacity = brushOpacity
        self._brushFlow = brushFlow
        self._brushHardness = brushHardness
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: activeTool.iconName)
                        .foregroundColor(.accentColor)
                    Text(activeTool.title)
                        .font(.headline)
                }
                .padding(.bottom, 4)

                Divider()

                // Contextual Tool Settings
                switch activeTool {
                case .brush, .eraser:
                    brushSettingsView

                case .transform:
                    transformSettingsView

                case .liquify:
                    liquifySettingsView

                case .chromaKey:
                    chromaKeySettingsView

                case .backgroundRemoval:
                    aiBackgroundSettingsView

                case .asciiArt:
                    asciiSettingsView

                default:
                    generalToolSettingsView
                }

                Divider()

                // Export Quick Section
                exportSectionView
            }
            .padding()
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
    }

    // MARK: - Tool Subviews

    private var brushSettingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Brush Dynamics").font(.subheadline).bold()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text("\(Int(brushSize)) px").foregroundColor(.secondary)
                }
                Slider(value: $brushSize, in: 1...256, step: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity")
                    Spacer()
                    Text("\(Int(brushOpacity * 100))%").foregroundColor(.secondary)
                }
                Slider(value: $brushOpacity, in: 0.01...1.0)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Hardness")
                    Spacer()
                    Text("\(Int(brushHardness * 100))%").foregroundColor(.secondary)
                }
                Slider(value: $brushHardness, in: 0.0...1.0)
            }
        }
    }

    private var transformSettingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Free Transform").font(.subheadline).bold()

            VStack(alignment: .leading, spacing: 4) {
                Text("Scale: \(String(format: "%.2f", transformScaleX))x")
                Slider(value: $transformScaleX, in: 0.1...3.0)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Rotation: \(Int(transformRotation))°")
                Slider(value: $transformRotation, in: -180...180)
            }

            Picker("Interpolation", selection: $transformInterpolation) {
                Text("Bilinear").tag(InterpolationMode.bilinear)
                Text("Bicubic").tag(InterpolationMode.bicubic)
                Text("Nearest").tag(InterpolationMode.nearestNeighbor)
            }

            Button("Apply Transform") {
                applyTransformToActiveLayer()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    private var liquifySettingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GPU Liquify").font(.subheadline).bold()

            Picker("Mode", selection: $liquifyMode) {
                Text("Push / Warp").tag(LiquifyToolMode.push)
                Text("Twirl CW").tag(LiquifyToolMode.twirlCW)
                Text("Twirl CCW").tag(LiquifyToolMode.twirlCCW)
                Text("Pinch").tag(LiquifyToolMode.pinch)
                Text("Bloat").tag(LiquifyToolMode.bloat)
                Text("Reconstruct").tag(LiquifyToolMode.reconstruct)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Radius: \(Int(liquifyRadius)) px")
                Slider(value: $liquifyRadius, in: 16...256)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Pressure: \(Int(liquifyPressure * 100))%")
                Slider(value: $liquifyPressure, in: 0.05...1.0)
            }

            Button("Reset Liquify Mesh") {
                liquifyEngine?.reset()
            }
            .buttonStyle(.bordered)
        }
    }

    private var chromaKeySettingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CIELAB Chroma Key").font(.subheadline).bold()

            VStack(alignment: .leading, spacing: 4) {
                Text("Tolerance (Delta E): \(Int(chromaTolerance))")
                Slider(value: $chromaTolerance, in: 5...80)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Feather Edge: \(Int(chromaFeather)) px")
                Slider(value: $chromaFeather, in: 0...30)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Spill Suppression: \(Int(chromaSpill * 100))%")
                Slider(value: $chromaSpill, in: 0.0...1.0)
            }

            Button("Key Out Background") {
                applyChromaKey()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var aiBackgroundSettingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Smart Subject Isolation").font(.subheadline).bold()
            Text("Uses Apple Neural Engine Vision instance mask segmentation.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Refine Fine Edges (Hair / Fur)", isOn: $aiRefineEdges)

            if let msg = aiStatusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }

            Button(action: {
                runAIBackgroundRemoval()
            }) {
                HStack {
                    if isProcessingAI {
                        ProgressView().controlSize(.small)
                    }
                    Text(isProcessingAI ? "Segmenting..." : "Remove Background")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessingAI)
        }
    }

    private var asciiSettingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ASCII Art Generator").font(.subheadline).bold()

            VStack(alignment: .leading, spacing: 4) {
                Text("Grid Columns: \(asciiColumns)")
                Slider(value: Binding(get: { Double(asciiColumns) }, set: { asciiColumns = Int($0) }), in: 40...200, step: 5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Grid Rows: \(asciiRows)")
                Slider(value: Binding(get: { Double(asciiRows) }, set: { asciiRows = Int($0) }), in: 20...100, step: 5)
            }

            Picker("Character Set", selection: $asciiCharSetChoice) {
                Text("Standard").tag(0)
                Text("Extended Unicode").tag(1)
                Text("Custom").tag(2)
            }

            if asciiCharSetChoice == 2 {
                TextField("Custom Glyphs", text: $asciiCustomChars)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Floyd-Steinberg Dithering", isOn: $asciiDithering)

            HStack {
                Button("Bake Text") {
                    bakeASCIIText()
                }
                .buttonStyle(.bordered)

                Button("Bake Raster") {
                    bakeASCIIRaster()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var generalToolSettingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Options").font(.subheadline).bold()
            Text("Selected: \(activeTool.title)")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private var exportSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export & Output").font(.subheadline).bold()

            Picker("Format", selection: $exportFormat) {
                Text("PNG (8-bit)").tag(ExportFormat.png8)
                Text("PNG (16-bit)").tag(ExportFormat.png16)
                Text("JPEG").tag(ExportFormat.jpeg)
                Text("TIFF").tag(ExportFormat.tiff)
                Text("HEIC").tag(ExportFormat.heic)
            }

            if exportFormat == .jpeg || exportFormat == .heic {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quality: \(Int(exportQuality * 100))%")
                    Slider(value: $exportQuality, in: 0.1...1.0)
                }
            }

            Button(action: {
                exportCanvas()
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Image...")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

    private func applyTransformToActiveLayer() {
        guard let bitmap = document.activeLayer as? BitmapLayer else { return }
        document.beginUndoGroup("Free Transform")
        let engine = TransformEngine()
        var state = TransformState()
        state.scale = CGSize(width: transformScaleX, height: transformScaleX)
        state.rotation = CGFloat(transformRotation * .pi / 180.0)
        state.pivot = CGPoint(x: document.width / 2, y: document.height / 2)

        let transformed = engine.transform(
            source: bitmap.tileGrid,
            state: state,
            canvasSize: document.canvasSize,
            interpolation: transformInterpolation
        )
        bitmap.tileGrid.copyFrom(transformed)
        document.endUndoGroup()
        document.markDirty()
    }

    private func applyChromaKey() {
        guard let bitmap = document.activeLayer as? BitmapLayer else { return }
        document.beginUndoGroup("Chroma Key")
        let filter = ChromaKeyFilter()
        let nsColor = NSColor(activeColor).usingColorSpace(.deviceRGB) ?? .green
        let rgb = (
            UInt8(nsColor.redComponent * 255),
            UInt8(nsColor.greenComponent * 255),
            UInt8(nsColor.blueComponent * 255)
        )
        let params = ChromaKeyParams(
            keyColor: rgb,
            tolerance: chromaTolerance,
            feather: chromaFeather,
            spillSuppression: chromaSpill
        )
        let result = filter.apply(grid: bitmap.tileGrid, params: params)
        bitmap.tileGrid.copyFrom(result)
        document.endUndoGroup()
        document.markDirty()
    }

    private func runAIBackgroundRemoval() {
        guard let bitmap = document.activeLayer as? BitmapLayer else { return }
        isProcessingAI = true
        aiStatusMessage = "Detecting foreground subjects..."

        Task {
            do {
                let vision = VisionBackgroundRemoval()
                let mask = try await vision.generateForegroundMask(from: bitmap.tileGrid, refineEdges: aiRefineEdges)
                await MainActor.run {
                    document.beginUndoGroup("AI Background Removal")
                    vision.applyMaskToGrid(grid: bitmap.tileGrid, mask: mask)
                    document.endUndoGroup()
                    document.markDirty()
                    isProcessingAI = false
                    aiStatusMessage = "Subject isolated successfully!"
                }
            } catch {
                await MainActor.run {
                    isProcessingAI = false
                    aiStatusMessage = "Segmentation error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func bakeASCIIText() {
        guard let bitmap = document.activeLayer as? BitmapLayer else { return }
        document.beginUndoGroup("Bake ASCII Text Layer")
        let generator = ASCIIGenerator()
        let charSet: ASCIICharacterSet
        switch asciiCharSetChoice {
        case 1: charSet = .extendedUnicode
        case 2: charSet = .custom(asciiCustomChars)
        default: charSet = .standard
        }

        let params = ASCIIParams(
            gridColumns: asciiColumns,
            gridRows: asciiRows,
            charSet: charSet,
            dithering: asciiDithering
        )
        let textLayer = generator.bakeToTextLayer(from: bitmap.tileGrid, params: params)
        _ = document.addLayer(textLayer)
        document.endUndoGroup()
    }

    private func bakeASCIIRaster() {
        guard let bitmap = document.activeLayer as? BitmapLayer else { return }
        document.beginUndoGroup("Bake ASCII Raster Layer")
        let generator = ASCIIGenerator()
        let charSet: ASCIICharacterSet
        switch asciiCharSetChoice {
        case 1: charSet = .extendedUnicode
        case 2: charSet = .custom(asciiCustomChars)
        default: charSet = .standard
        }

        let params = ASCIIParams(
            gridColumns: asciiColumns,
            gridRows: asciiRows,
            charSet: charSet,
            dithering: asciiDithering
        )
        let baked = generator.bakeToBitmapLayer(from: bitmap.tileGrid, params: params, canvasSize: document.canvasSize)
        _ = document.addLayer(baked)
        document.endUndoGroup()
    }

    private func exportCanvas() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: exportFormat.fileExtension) ?? .png]
        panel.nameFieldStringValue = "ExportedImage.\(exportFormat.fileExtension)"

        if panel.runModal() == .OK, let url = panel.url {
            let exporter = ImageExporter()
            if let bitmap = document.activeLayer as? BitmapLayer,
               let data = exporter.export(grid: bitmap.tileGrid, options: ExportOptions(format: exportFormat, quality: exportQuality, preserveAlpha: true)) {
                try? data.write(to: url)
            }
        }
    }
}
