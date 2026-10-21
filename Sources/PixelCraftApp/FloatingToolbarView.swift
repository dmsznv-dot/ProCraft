import SwiftUI
import AppKit

public struct FloatingToolbarView: View {
    @Binding public var activeTool: ActiveToolType
    @Binding public var activeColor: Color

    public init(activeTool: Binding<ActiveToolType>, activeColor: Binding<Color>) {
        self._activeTool = activeTool
        self._activeColor = activeColor
    }

    public var body: some View {
        HStack(spacing: 4) {
            // Color well
            ColorPicker("", selection: $activeColor, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 28, height: 28)
                .padding(.leading, 4)

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 2)

            ForEach(ActiveToolType.allCases) { tool in
                Button(action: {
                    activeTool = tool
                }) {
                    Image(systemName: tool.iconName)
                        .font(.system(size: 14, weight: activeTool == tool ? .bold : .regular))
                        .foregroundColor(activeTool == tool ? .accentColor : .primary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(activeTool == tool ? Color.accentColor.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(tool.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}
