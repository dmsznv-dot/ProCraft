import SwiftUI
import UniformTypeIdentifiers
import PixelCraftEngine

public struct SidebarView: View {
    @ObservedObject public var document: Document
    @State private var selectedTab: Int = 0 // 0: Layers, 1: History
    @State private var isDropOverLayers: Bool = false

    public init(document: Document) {
        self.document = document
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Segmented picker
            Picker("", selection: $selectedTab) {
                Text("Layers").tag(0)
                Text("History").tag(1)
            }
            .pickerStyle(.segmented)
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
        .frame(minWidth: 220, idealWidth: 260)
    }

    // MARK: - Layers Panel

    private var layersPanel: some View {
        VStack(spacing: 0) {
            // Top action bar
            HStack(spacing: 12) {
                Button(action: {
                    _ = document.addLayer()
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add New Layer")

                Button(action: {
                    importLayerDialog()
                }) {
                    Image(systemName: "photo.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Import Image as New Layer")

                Button(action: {
                    _ = try? document.duplicateLayer()
                }) {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.borderless)
                .help("Duplicate Active Layer")

                Button(action: {
                    try? document.deleteLayer()
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete Active Layer")

                Spacer()

                Menu {
                    Button("Merge Down") {
                        try? document.mergeDown()
                    }
                    Button("Merge Visible") {
                        try? document.mergeVisible()
                    }
                    Button("Flatten Image") {
                        try? document.flatten()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            // Active layer opacity & blend mode quick bar
            VStack(spacing: 6) {
                HStack {
                    Text("Blend:")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                    Text("Opacity:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Slider(value: Binding<Double>(
                        get: { Double(document.activeLayer.opacity) },
                        set: { val in
                            document.activeLayer.opacity = Float(val)
                            document.markDirty()
                        }
                    ), in: 0.0...1.0)
                    .controlSize(.small)

                    Text("\(Int(document.activeLayer.opacity * 100))%")
                        .font(.caption2)
                        .frame(width: 32)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Layer Stack List (Top layer displayed at the top)
            List {
                ForEach(Array(document.layers.enumerated().reversed()), id: \.element.id) { index, layer in
                    HStack(spacing: 8) {
                        Button(action: {
                            layer.isVisible.toggle()
                            document.markDirty()
                        }) {
                            Image(systemName: layer.isVisible ? "eye.fill" : "eye.slash")
                                .foregroundColor(layer.isVisible ? .primary : .secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            layer.lockAlpha.toggle()
                        }) {
                            Image(systemName: layer.lockAlpha ? "lock.fill" : "lock.open")
                                .font(.caption2)
                                .foregroundColor(layer.lockAlpha ? .accentColor : .secondary.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .help("Lock Alpha Channel")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(layer.name)
                                .font(.system(size: 13, weight: index == document.activeLayerIndex ? .semibold : .regular))

                            Text(layer.blendMode.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .listRowBackground(index == document.activeLayerIndex ? Color.accentColor.opacity(0.15) : Color.clear)
                    .onTapGesture {
                        document.selectLayer(at: index)
                    }
                }
            }
            .listStyle(.inset)
            .onDrop(of: [.fileURL], isTargeted: $isDropOverLayers) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        _ = try? document.importImageAsLayer(url: url)
                    }
                }
                return true
            }
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
            _ = try? document.importImageAsLayer(url: url)
        }
    }

    // MARK: - History Panel

    private var historyPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    document.undo()
                }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!document.undoManager.canUndo)

                Spacer()

                Button(action: {
                    document.redo()
                }) {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!document.undoManager.canRedo)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            List {
                Text("Document Created")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(0..<min(document.undoManager.undoCount, 20), id: \.self) { i in
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.secondary)
                        Text("Action #\(i + 1)")
                            .font(.system(size: 12))
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}
