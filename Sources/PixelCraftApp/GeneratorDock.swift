import SwiftUI
import PixelCraftEngine

/// Photoshop-style collapsed panel dock on the right edge of the canvas.
/// Each generator is an icon + caption; clicking it slides out its settings panel.
struct GeneratorDock: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let generator = state.openGenerator {
                GeneratorPanel(state: state, generator: generator)
                    .frame(width: 290)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            VStack(spacing: 2) {
                Text("EFFECTS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                ForEach(Generator.allCases) { generator in
                    DockButton(generator: generator, isOpen: state.openGenerator == generator) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            state.toggleGenerator(generator)
                        }
                    }
                }
            }
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
            )
        }
    }
}

private struct DockButton: View {
    let generator: Generator
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: generator.iconName)
                    .font(.system(size: 16))
                    .frame(height: 20)
                Text(generator.shortTitle)
                    .font(.system(size: 9, weight: isOpen ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(isOpen ? .accentColor : .primary)
            .frame(width: 62, height: 46)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOpen ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(generator.title) — \(generator.summary)")
    }
}

// MARK: - Panel

private struct GeneratorPanel: View {
    @ObservedObject var state: EditorState
    let generator: Generator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: generator.iconName)
                    .foregroundColor(.accentColor)
                Text(generator.title)
                    .font(.headline)
                Spacer()
                if state.isBusy {
                    ProgressView().controlSize(.small)
                }
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { state.closeGenerator() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (keeps the previewed result)")
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(generator.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    content

                    if let message = state.statusMessage {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 460)

            if generator.usesLivePreview || generator == .liquify {
                Divider()
                HStack {
                    Button("Cancel") { state.cancelPending() }
                        .disabled(!state.hasPendingChanges)
                        .help("Revert the preview (Esc)")
                    Spacer()
                    Button("Apply") { state.commitPending() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!state.hasPendingChanges)
                        .help("Apply as an undoable step (Return)")
                }
                .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 6)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch generator {
        case .transform: transformControls
        case .liquify: liquifyControls
        case .pixelate: pixelateControls
        case .chromaKey: chromaKeyControls
        case .removeBackground: removeBackgroundControls
        case .ascii: asciiControls
        }
    }

    // MARK: Transform

    private var transformControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(title: state.transformLockAspect ? "Scale" : "Width",
                          value: $state.transformScaleX, range: 5...400, suffix: "%")
            if !state.transformLockAspect {
                LabeledSlider(title: "Height", value: $state.transformScaleY, range: 5...400, suffix: "%")
            }
            Toggle("Keep proportions", isOn: $state.transformLockAspect)
                .toggleStyle(.checkbox)
            LabeledSlider(title: "Rotate", value: $state.transformRotation, range: -180...180, suffix: "°")
            LabeledSlider(title: "Move X", value: $state.transformOffsetX, range: -2000...2000, suffix: " px")
            LabeledSlider(title: "Move Y", value: $state.transformOffsetY, range: -2000...2000, suffix: " px")
            HStack {
                Toggle("Flip ↔", isOn: $state.transformFlipH).toggleStyle(.button)
                Toggle("Flip ↕", isOn: $state.transformFlipV).toggleStyle(.button)
                Spacer()
                Button("Reset") { state.cancelPending() }
            }
            Picker("Quality", selection: $state.transformInterpolation) {
                Text("Nearest (pixel art)").tag(InterpolationMode.nearestNeighbor)
                Text("Bilinear").tag(InterpolationMode.bilinear)
                Text("Bicubic").tag(InterpolationMode.bicubic)
            }
        }
    }

    // MARK: Liquify

    private var liquifyControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $state.liquifyMode) {
                Text("Push / Warp").tag(LiquifyToolMode.push)
                Text("Twirl ↻").tag(LiquifyToolMode.twirlCW)
                Text("Twirl ↺").tag(LiquifyToolMode.twirlCCW)
                Text("Pinch").tag(LiquifyToolMode.pinch)
                Text("Bloat").tag(LiquifyToolMode.bloat)
                Text("Reconstruct").tag(LiquifyToolMode.reconstruct)
            }
            LabeledSlider(title: "Brush size", value: $state.liquifySize, range: 10...600, suffix: " px")
            LabeledSlider(title: "Pressure", value: $state.liquifyPressure, range: 0.05...1, percent: true)
            Text("Drag on the canvas. [ and ] change the brush size.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: Pixelate

    private var pixelateControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(title: "Cell size", value: $state.pixelBlockSize, range: 2...256, suffix: " px")
            Picker("Shape", selection: $state.pixelShape) {
                Text("Square").tag(PixelateGridShape.square)
                Text("Hexagon").tag(PixelateGridShape.hexagonal)
                Text("Circle").tag(PixelateGridShape.circular)
            }
            Picker("Color", selection: $state.pixelSampling) {
                Text("Average of cell").tag(PixelateSamplingMode.average)
                Text("Center pixel").tag(PixelateSamplingMode.center)
            }
            Text("With an active selection only the selected area is pixelated.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: Chroma Key

    private var chromaKeyControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Key color")
                Spacer()
                ColorPicker("", selection: $state.chromaKeyColor, supportsOpacity: false)
                    .labelsHidden()
            }
            Text("Tip: click on the backdrop in the canvas to sample it.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            LabeledSlider(title: "Tolerance", value: $state.chromaTolerance, range: 1...100)
            LabeledSlider(title: "Edge softness", value: $state.chromaFeather, range: 0...40)
            LabeledSlider(title: "Spill removal", value: $state.chromaSpill, range: 0...1, percent: true)
        }
    }

    // MARK: Background Removal

    private var removeBackgroundControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Refine fine edges (hair, fur)", isOn: $state.aiRefineEdges)
                .toggleStyle(.checkbox)
            Button {
                state.runRemoveBackground()
            } label: {
                Label(state.isBusy ? "Working…" : "Remove Background", systemImage: "person.and.background.dotted")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isBusy)
            Text("Runs on-device with Apple Vision. Works best on photos with a clear subject.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: ASCII

    private var asciiControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(title: "Columns", value: $state.asciiColumns, range: 20...400, step: 1)
            Toggle("Rows from image aspect", isOn: $state.asciiAutoRows)
                .toggleStyle(.checkbox)
            if !state.asciiAutoRows {
                LabeledSlider(title: "Rows", value: $state.asciiRows, range: 5...300, step: 1)
            }
            Picker("Characters", selection: $state.asciiCharSet) {
                Text("Classic  .:-=+*#%@").tag(0)
                Text("Blocks  ░▒▓█").tag(1)
                Text("Custom").tag(2)
            }
            if state.asciiCharSet == 2 {
                TextField("Light → dense characters", text: $state.asciiCustomChars)
                    .textFieldStyle(.roundedBorder)
            }
            Picker("Style", selection: $state.asciiStyle) {
                ForEach(ASCIIStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            LabeledSlider(title: "Edge depth", value: $state.asciiVolume, range: 0...2, percent: true)
            Toggle("Dithering", isOn: $state.asciiDithering).toggleStyle(.checkbox)
            Toggle("Invert brightness", isOn: $state.asciiInvert).toggleStyle(.checkbox)

            HStack {
                Button("Copy as Text") { state.copyASCIIText() }
                Spacer()
                Button("Create Layer") { state.runASCIIRaster() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isBusy)
            }
        }
    }
}

// MARK: - Reusable slider row

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var suffix: String = ""
    var percent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            if let step {
                Slider(value: $value, in: range, step: step).controlSize(.small)
            } else {
                Slider(value: $value, in: range).controlSize(.small)
            }
        }
    }

    private var valueText: String {
        if percent { return "\(Int((value * 100).rounded()))%" }
        return "\(Int(value.rounded()))\(suffix)"
    }
}
