import SwiftUI
import AppKit

/// Bottom toolbar: only the basic canvas tools, each with an icon, a caption and a tooltip
/// that includes the keyboard shortcut. Generators live in the right-hand dock.
struct FloatingToolbarView: View {
    @ObservedObject var state: EditorState

    private var groups: [[CanvasTool]] {
        let all = CanvasTool.allCases
        return [0, 1, 2].map { g in all.filter { $0.group == g } }
    }

    var body: some View {
        HStack(spacing: 6) {
            ColorPairView(state: state)
                .padding(.leading, 4)

            ForEach(groups.indices, id: \.self) { index in
                Divider().frame(height: 34)
                HStack(spacing: 2) {
                    ForEach(groups[index]) { tool in
                        ToolButton(
                            tool: tool,
                            isSelected: state.tool == tool && state.openGenerator == nil
                        ) {
                            if state.openGenerator != nil { state.closeGenerator() }
                            state.tool = tool
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ToolButton: View {
    let tool: CanvasTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tool.iconName)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .frame(height: 18)
                Text(tool.shortLabel)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .accentColor : .primary)
            .frame(width: 52, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(tool.title) (\(String(tool.shortcut).uppercased())) — \(tool.hint)")
    }
}

/// Primary / secondary color swatches (Photoshop-style), with a swap button.
struct ColorPairView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 4) {
            VStack(spacing: 2) {
                ColorPicker("", selection: $state.primaryColor, supportsOpacity: true)
                    .labelsHidden()
                    .help("Primary color (brush, fill, gradient start)")
                ColorPicker("", selection: $state.secondaryColor, supportsOpacity: true)
                    .labelsHidden()
                    .scaleEffect(0.85)
                    .help("Secondary color (gradient end)")
            }
            Button {
                state.swapColors()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Swap colors (X)")
        }
    }
}
