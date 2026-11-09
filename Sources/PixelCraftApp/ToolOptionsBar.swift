import SwiftUI
import PixelCraftEngine

/// Horizontal options bar above the canvas with the settings of the active tool.
struct ToolOptionsBar: View {
    @ObservedObject var state: EditorState
    @ObservedObject var document: Document

    var body: some View {
        HStack(spacing: 14) {
            Label(state.openGenerator?.title ?? state.tool.title,
                  systemImage: state.openGenerator?.iconName ?? state.tool.iconName)
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 120, alignment: .leading)

            Divider().frame(height: 18)

            if state.openGenerator != nil {
                Text("Generator settings are in the panel on the right")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                options
            }

            Spacer(minLength: 8)

            Text("\(document.width) × \(document.height) px")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Text("\(document.zoomPercent)%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.bar)
    }

    @ViewBuilder
    private var options: some View {
        switch state.tool {
        case .brush:
            slider("Size", value: $state.brushSize, range: 1...500, format: "%.0f px", width: 130)
            slider("Hardness", value: $state.brushHardness, range: 0...1, percent: true)
            slider("Opacity", value: $state.brushOpacity, range: 0.01...1, percent: true)
            slider("Flow", value: $state.brushFlow, range: 0.01...1, percent: true)
        case .eraser:
            slider("Size", value: $state.eraserSize, range: 1...500, format: "%.0f px", width: 130)
            slider("Hardness", value: $state.brushHardness, range: 0...1, percent: true)
            slider("Strength", value: $state.brushOpacity, range: 0.01...1, percent: true)
        case .fill:
            slider("Tolerance", value: $state.fillTolerance, range: 0...1, percent: true)
            Toggle("Contiguous", isOn: $state.fillContiguous)
                .toggleStyle(.checkbox)
                .help("Off: fill every pixel of similar color on the layer")
        case .gradient:
            Picker("", selection: $state.gradientType) {
                Text("Linear").tag(GradientType.linear)
                Text("Radial").tag(GradientType.radial)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
            Toggle("Primary → Transparent", isOn: $state.gradientToTransparent)
                .toggleStyle(.checkbox)
        case .marquee, .ellipseMarquee, .lasso:
            if state.tool == .lasso {
                Picker("", selection: $state.lassoPolygonal) {
                    Text("Freehand").tag(false)
                    Text("Polygonal").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                .help("Polygonal: click to add points, double-click or Return to close")
            }
            slider("Feather", value: $state.selectionFeather, range: 0...100, format: "%.0f px")
            Button("Select All") { state.selectAll() }
            Button("Deselect") { state.deselect() }
            Button("Invert") { state.invertSelection() }
            Text("⇧ add · ⌥ subtract")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        case .crop:
            Text("Drag a rectangle on the canvas to crop. ⌘Z restores the original size.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .move:
            Text("Drag to move the active layer's pixels.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .hand:
            Button("Fit") { state.fitToScreen() }
            Button("100%") { state.actualSize() }
        case .eyedropper:
            Text("Click: primary color · ⌥-click: secondary color")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String = "%.0f",
        percent: Bool = false,
        width: CGFloat = 100
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Slider(value: value, in: range)
                .controlSize(.small)
                .frame(width: width)
            Text(percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : String(format: format, value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 48, alignment: .leading)
        }
    }
}
