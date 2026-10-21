# Project: PixelCraft Pro
# Scope: Full Application Lifecycle & Verification

## Architecture
PixelCraft Pro is an Apple Silicon native (arm64, macOS 14.0+) professional graphic editor built with Swift 6.2, Metal, SwiftUI, AppKit, Vision, and CoreImage.

### High-Level Components
1. **PixelCraftEngine (Core Library)**
   - **Metal Canvas**: GPU-accelerated rendering using `MTLDevice`, `MTLCommandQueue`, `MTLRenderPipelineState`, `MTLComputePipelineState`.
   - **Tiled Layer System**: 512×512 sparse tile grid supporting up to 8K (8192×4320 px) with minimal memory footprint; polymorphic layers (`BitmapLayer`, `TextLayer`, `AdjustmentLayer`, `EffectLayer`); 7 core blend modes + extra modes.
   - **Drawing & Selection**: Catmull-Rom spline brush engine, eraser, scanline flood fill, linear/radial gradients, eyedropper, single-channel 8-bit selection masks (marquee, lasso), tile-delta undo/redo manager.
   - **Transforms & GPU Liquify**: Affine transform matrix with Nearest/Bilinear/Bicubic sampling, 4-corner perspective DLT homography, 3×3 Bézier warp, pixelate compute shader, GPU compute liquify with float2 displacement map.
   - **Vision AI & Chroma Key**: `VNGenerateForegroundInstanceMaskRequest` subject segmentation, `CIGuidedFilter` edge refinement, CIELAB Delta E (CIE76/CIE94/CIEDE2000) chroma keying with despill.
   - **ASCII Art Generator**: Luminance conversion, CLAHE contrast amplification, Sobel directional edges, standard/Unicode/custom glyph density mapping, error diffusion, text or raster output.
   - **File I/O**: `.pcpro` FileWrapper bundle document format, best-effort PSD 8BPS parser/serializer, ImageIO export (PNG 8/16-bit, JPEG, TIFF, HEIC).
2. **PixelCraftApp (Native macOS UI & AppKit/SwiftUI Wrapper)**
   - **Main Layout**: `NavigationSplitView` (Sidebar: Layers & history, Detail: Canvas with MTKView, Inspector: Properties).
   - **Floating Tool Palette**: Glass aesthetic (`.ultraThinMaterial`), SF Symbols 5+, tool settings.
   - **Event & Shortcut Routing**: Local key monitors for Pan (Space), Zoom (⌘+/⌘-), Undo/Redo (⌘Z/⇧⌘Z), Save/Export (⌘S/⌘E), Delete.
3. **PixelCraftEngineTests & E2E Testing Suite**
   - XCTest unit test suite covering engine mathematics, compositing, and tools.
   - Requirement-driven E2E test harness exercising Tiers 1–4 opaque-box acceptance criteria.

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Metal Canvas Rendering | GPU-accelerated rendering pipeline via Metal MTKView | M1 | ORIGINAL_REQUEST §R1 |
| 2 | Viewport Zoom & Pan | Smooth zoom (pinch, ⌘+/⌘-) and panning (Space+drag) | M1 | ORIGINAL_REQUEST §R1 |
| 3 | 8K Tiled Rendering | 512×512 sparse tile grid supporting up to 8192×4320 px | M1 | ORIGINAL_REQUEST §R1 |
| 4 | Polymorphic Layer Stack | Bitmap, Text, Adjustment, Effect/Filter layer types | M1 | ORIGINAL_REQUEST §R1 |
| 5 | Layer Management CRUD | Add, duplicate, delete, reorder, show/hide layers | M1 | ORIGINAL_REQUEST §R1 |
| 6 | Layer Merge Operations | Merge down, merge visible, and flatten operations | M1 | ORIGINAL_REQUEST §R1 |
| 7 | Layer Opacity & Alpha Lock | Real-time 0–100% opacity slider and lock alpha toggle | M1 | ORIGINAL_REQUEST §R1 |
| 8 | Blend Modes | Normal, Multiply, Screen, Overlay, Soft Light, Hard Light, Difference | M1 | ORIGINAL_REQUEST §R1 |
| 9 | Brush Tool | Round, square, soft variants with size, opacity, and flow | M2 | ORIGINAL_REQUEST §R2 |
| 10 | Eraser Tool | Erases pixel content on active layer with alpha lock support | M2 | ORIGINAL_REQUEST §R2 |
| 11 | Fill Tool | Scanline flood fill with configurable color tolerance | M2 | ORIGINAL_REQUEST §R2 |
| 12 | Gradient Tool | Linear and radial gradients with multi-stop color ramps | M2 | ORIGINAL_REQUEST §R2 |
| 13 | Eyedropper Tool | Point and box-filtered color sampling from canvas | M2 | ORIGINAL_REQUEST §R2 |
| 14 | Selection Tools | Rectangular marquee, elliptical marquee, lasso | M2 | ORIGINAL_REQUEST §R2 |
| 15 | Selection Constraints | Active selection restricts all paint and fill operations | M2 | ORIGINAL_REQUEST §R2 |
| 16 | Crop Tool | Document canvas resize and layer coordinate translation | M2 | ORIGINAL_REQUEST §R2 |
| 17 | Undo/Redo Engine | Tile-delta command pattern history manager | M2 | ORIGINAL_REQUEST §R2 |
| 18 | Free Transform | Scale, rotate, skew, flip, Shift (aspect), Option (center) | M3 | ORIGINAL_REQUEST §R3 |
| 19 | Transform Interpolation | Nearest Neighbor, Bilinear, Bicubic Catmull-Rom | M3 | ORIGINAL_REQUEST §R3 |
| 20 | Perspective Distort | 4-corner pin DLT homography with pivot stabilization | M3 | ORIGINAL_REQUEST §R3 |
| 21 | Warp Grid | 3×3 Bézier curve grid patch deformation | M3 | ORIGINAL_REQUEST §R3 |
| 22 | Pixelate Effect | Block size 2–512px, square/hex grid, center/average sampling | M3 | ORIGINAL_REQUEST §R3 |
| 23 | GPU Liquify Engine | Push, Reconstruct, Twirl, Pinch, Bloat via compute shaders | M3 | ORIGINAL_REQUEST §R3 |
| 24 | Vision Background Removal | Foreground segmentation via `VNGenerateForegroundInstanceMaskRequest` | M4 | ORIGINAL_REQUEST §R4 |
| 25 | Mask Edge Refinement | Guided filter / edge preservation for hair, fur, thin edges | M4 | ORIGINAL_REQUEST §R4 |
| 26 | Chroma Key Tool | CIELAB Delta E color removal with tolerance, feather, despill | M4 | ORIGINAL_REQUEST §R4 |
| 27 | ASCII Image Pipeline | Luminance conversion, CLAHE contrast, Sobel edge filter | M5 | ORIGINAL_REQUEST §R5 |
| 28 | ASCII Glyph Mapping | Standard, Extended Unicode, and Custom character sets with dithering | M5 | ORIGINAL_REQUEST §R5 |
| 29 | ASCII Layer Generation | Output as editable TextLayer or baked BitmapLayer with color tint | M5 | ORIGINAL_REQUEST §R5 |
| 30 | Native Project Format | `.pcpro` FileWrapper bundle document (manifest, metadata, raw tiles) | M6 | ORIGINAL_REQUEST §R6 |
| 31 | PSD File Support | Best-effort 8BPS reader/writer with layer tree preservation | M6 | ORIGINAL_REQUEST §R6 |
| 32 | Multi-Format Export | PNG (8/16-bit + alpha), JPEG (quality), TIFF (layers), HEIC | M6 | ORIGINAL_REQUEST §R6 |
| 33 | Native 3-Column UI | NavigationSplitView (Sidebar, Canvas Detail, Inspector) | M7 | ORIGINAL_REQUEST §R7 |
| 34 | Floating Toolbar & Styling | Glass floating palette, SF Symbols 5+, Vibrancy, Light/Dark | M7 | ORIGINAL_REQUEST §R7 |
| 35 | Keyboard Shortcuts | ⌘Z, ⇧⌘Z, ⌘S, ⌘E, Delete, Space, ⌘+/⌘-, ⌘0 with focus guard | M7 | ORIGINAL_REQUEST §R7 |
| 36 | Layer & Property Inspectors | Real-time layer list reordering, blend mode picker, sliders | M7 | ORIGINAL_REQUEST §R7 |
| 37 | Automated Unit Tests | XCTest test suite covering engine mathematics, blending, transforms (≥10 tests) | M8 | ORIGINAL_REQUEST §AC |
| 38 | E2E Acceptance Suite | Comprehensive opaque-box test suite passing 100% across Tiers 1–4 + Tier 5 Hardening | M8 | ORIGINAL_REQUEST §AC |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Core Engine & Metal Canvas | Package setup, Document model, 8K Tiled Metal Canvas, polymorphic Layers, MSL Blend modes (F1–F8) | none | PLANNED |
| M2 | Drawing & Selection Tools | Brush engine, Eraser, Scanline Flood Fill, Gradients, Eyedropper, Marquee/Lasso selections, Tile-delta Undo/Redo (F9–F17) | M1 | PLANNED |
| M3 | Transforms & GPU Liquify | Free transform, DLT homography, Bézier warp, Pixelate, GPU Liquify compute shaders (F18–F23) | M1 | PLANNED |
| M4 | Vision AI & Chroma Key | Vision foreground segmentation, Guided filter hair refinement, CIELAB Delta E chroma key with despill (F24–F26) | M1 | PLANNED |
| M5 | ASCII Art Generator | ASCII luminance/Sobel pipeline, Standard/Extended/Custom glyph sets, TextLayer & BitmapLayer outputs (F27–F29) | M1 | PLANNED |
| M6 | File I/O & Export Engine | `.pcpro` FileWrapper document format, PSD 8BPS reader/writer, PNG/JPEG/TIFF/HEIC export (F30–F32) | M1, M2 | PLANNED |
| M7 | Native macOS UI & Integration | NavigationSplitView, MTKView canvas wrapper, Floating toolbar, Layer panel drag & drop, Inspector, Shortcuts (F33–F36) | M1–M6 | PLANNED |
| M8 | Final Milestone & E2E Verification | 100% pass of E2E test suite (Tiers 1–4) & Tier 5 Adversarial Coverage Hardening (F37–F38) | M1–M7, TEST_READY | PLANNED |

*Note: In parallel with M1–M7, the E2E Testing Track Orchestrator creates the opaque-box test runner and test cases (Tiers 1–4), publishing `TEST_READY.md`.*

---

## Interface Contracts

### 1. Document ↔ TileGrid ↔ Layer
- `Document`: Holds `canvasSize: CGSize`, `layers: [Layer]`, `activeLayerIndex: Int`, `undoManager: TileUndoManager`.
- `Layer` (Protocol):
  ```swift
  public protocol Layer: AnyObject {
      var id: UUID { get }
      var name: String { get set }
      var isVisible: Bool { get set }
      var opacity: Float { get set } // 0.0 ... 1.0
      var blendMode: BlendMode { get set }
      var lockAlpha: Bool { get set }
      var tileGrid: SparseTileGrid { get }
      func duplicate() -> Layer
      func render(into context: MetalRenderContext)
  }
  ```
- `SparseTileGrid`: 512×512 tile coordinates `(tx, ty)` mapped to `MTLTexture` (pixel format `.rgba8Unorm`). Unallocated tiles consume 0 bytes.

### 2. Metal Canvas ↔ Renderer
- `MetalCanvasRenderer`:
  - Input: Document layer stack, viewport transform matrix `simd_float3x3` (pan, zoom).
  - Output: Composited frame rendered into `MTKView` drawable texture or offscreen export texture.
  - Shaders: `composite_layer.metal` executing Porter-Duff and component blend equations (Normal, Multiply, Screen, Overlay, Soft Light, Hard Light, Difference).

### 3. Tool Engine ↔ Canvas
- `DrawingTool` (Protocol):
  ```swift
  public protocol DrawingTool {
      func mouseDown(at canvasPoint: CGPoint, document: Document)
      func mouseDragged(to canvasPoint: CGPoint, document: Document)
      func mouseUp(at canvasPoint: CGPoint, document: Document)
  }
  ```
- All drawing operations write to the active `BitmapLayer.tileGrid`, recording modified tile deltas to `TileUndoManager`.

### 4. Transform & Effect Contracts
- `TransformEngine`:
  - `applyAffine(to layer: BitmapLayer, matrix: CGAffineTransform, interpolation: InterpolationMode)`
  - `applyPerspective(to layer: BitmapLayer, quad: QuadCorners)`
- `LiquifyEngine`:
  - Computes `float2` displacement map using Metal compute pipeline `liquify_deform.metal`.
  - Tools: `push`, `reconstruct`, `twirlCW`, `twirlCCW`, `pinch`, `bloat`.

### 5. AI & ASCII Contracts
- `BackgroundRemovalService`:
  - `removeBackground(from texture: MTLTexture) async throws -> MTLTexture` (using Vision + GuidedFilter).
- `ChromaKeyService`:
  - `applyChromaKey(to texture: MTLTexture, targetColor: SIMD3<Float>, tolerance: Float, feather: Float, despill: Float) -> MTLTexture`
- `ASCIIArtGenerator`:
  - `generateASCII(from texture: MTLTexture, options: ASCIIOptions) -> ASCIIGridResult`

### 6. File I/O Contracts
- `ProjectDocument`:
  - `save(to url: URL, document: Document) throws` (creates `.pcpro` directory bundle).
  - `load(from url: URL) throws -> Document`
- `ExportService`:
  - `export(document: Document, to url: URL, format: ExportFormat, options: ExportOptions) throws`

---

## Code Layout
```
PixelCraftPro/
├── Package.swift
├── Sources/
│   ├── PixelCraftEngine/
│   │   ├── Model/
│   │   │   ├── Document.swift
│   │   │   ├── Layer.swift
│   │   │   ├── BitmapLayer.swift
│   │   │   ├── TextLayer.swift
│   │   │   ├── AdjustmentLayer.swift
│   │   │   ├── EffectLayer.swift
│   │   │   └── BlendMode.swift
│   │   ├── Metal/
│   │   │   ├── MetalContext.swift
│   │   │   ├── SparseTileGrid.swift
│   │   │   ├── CanvasRenderer.swift
│   │   │   └── Shaders/
│   │   │       ├── BlendingShaders.metal
│   │   │       ├── LiquifyShaders.metal
│   │   │       └── PixelateShaders.metal
│   │   ├── Tools/
│   │   │   ├── ToolType.swift
│   │   │   ├── BrushTool.swift
│   │   │   ├── EraserTool.swift
│   │   │   ├── FloodFillTool.swift
│   │   │   ├── GradientTool.swift
│   │   │   ├── EyedropperTool.swift
│   │   │   ├── SelectionTool.swift
│   │   │   ├── CropTool.swift
│   │   │   └── UndoManager.swift
│   │   ├── Transform/
│   │   │   ├── TransformEngine.swift
│   │   │   ├── HomographySolver.swift
│   │   │   ├── WarpGrid.swift
│   │   │   ├── PixelateFilter.swift
│   │   │   └── LiquifyEngine.swift
│   │   ├── AI/
│   │   │   ├── BackgroundRemovalService.swift
│   │   │   ├── GuidedFilterRefiner.swift
│   │   │   └── ChromaKeyService.swift
│   │   ├── ASCII/
│   │   │   ├── ASCIIArtGenerator.swift
│   │   │   ├── GlyphDensityTable.swift
│   │   │   └── DitherEngine.swift
│   │   └── FileIO/
│   │       ├── ProjectPackageIO.swift
│   │       ├── PSDReaderWriter.swift
│   │       └── ImageExporter.swift
│   └── PixelCraftApp/
│       ├── PixelCraftApp.swift
│       ├── Views/
│       │   ├── MainEditorView.swift
│       │   ├── CanvasView.swift (MTKView wrapper)
│       │   ├── LayerPanelView.swift
│       │   ├── FloatingToolbarView.swift
│       │   └── InspectorPanelView.swift
│       └── ViewModels/
│           └── EditorViewModel.swift
└── Tests/
    ├── PixelCraftEngineTests/
    │   ├── LayerCompositingTests.swift
    │   ├── BlendModeTests.swift
    │   ├── ColorDistanceTests.swift
    │   ├── ASCIIMappingTests.swift
    │   ├── TransformMatrixTests.swift
    │   ├── FloodFillTests.swift
    │   ├── SparseTileGridTests.swift
    │   ├── ChromaKeyTests.swift
    │   ├── ProjectIOTests.swift
    │   └── ExportTests.swift
    └── E2ETests/
        ├── TestHarness.swift
        ├── Tier1FeatureTests.swift
        ├── Tier2BoundaryTests.swift
        ├── Tier3CombinationTests.swift
        └── Tier4ScenarioTests.swift
```
