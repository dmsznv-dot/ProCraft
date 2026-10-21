# PixelCraft Pro (ProCraft)

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138.svg?logo=swift&logoColor=white)](https://swift.org)
[![Platform macOS](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue.svg?logo=apple&logoColor=white)](https://apple.com/macos)
[![Architecture Apple Silicon](https://img.shields.io/badge/arch-ARM64%20Native-success.svg)](https://apple.com)
[![Graphics Metal 3](https://img.shields.io/badge/graphics-Metal%203-orange.svg)](https://developer.apple.com/metal)
[![Tests](https://img.shields.io/badge/tests-117%20passed%20%2F%200%20failed-brightgreen.svg)]()

**PixelCraft Pro** is a high-performance, professional raster graphic editor engineered from the ground up natively for macOS (Apple Silicon ARM64). Built on Swift 6, SwiftUI, AppKit, Metal 3, Accelerate, and Vision frameworks, it delivers real-time 120Hz ProMotion drawing and editing performance on canvases up to 8K ($8192 \times 4320$).

---

## Key Highlights & Capabilities

### 1. Metal 3 Sparse Tile Engine (Up to 8K)
* **Sparse 512×512 Tile Grid:** Unallocated canvas tiles consume 0 MB of memory. An 8K canvas ($8192 \times 4320$, 135 tiles) requires less than 20 MB of active memory for typical drawings.
* **14 Porter-Duff Blend Modes:** Single-pass Metal programmable blending (`[[color(0)]]`) supporting Normal, Multiply, Screen, Overlay, Darken, Lighten, Color Dodge, Color Burn, Hard Light, Soft Light, Difference, Exclusion, Hue, and Saturation with lock alpha and opacity control.
* **Liquid Retina XDR & 120Hz ProMotion:** Smooth sub-pixel trackpad pan and zoom from 10% to 3200% with stationary focal-point invariants.

### 2. Universal Image Import & Drag-and-Drop
* **Drop to Adapt Aspect Ratio:** Drag any image (`.png`, `.jpg`, `.jpeg`, `.tiff`, `.heic`, `.webp`, `.bmp`, `.gif`, `.psd`, `.pcpro`) directly into the canvas. The canvas automatically resizes to match the image dimensions, calculates the exact aspect ratio, and centers the viewport.
* **Option-Drop Layer Insertion:** Holding `⌥ Option` while dragging an image (or dropping onto the Layers list) imports the image as a new centered layer on top of the current composition.
* **Accelerate SIMD Unpremultiplication:** Straight and premultiplied alpha channels are processed at memory-bus speeds via `vImageUnpremultiplyData_RGBA8888`.

### 3. Professional Tool Suite
* **Spline Brush & Eraser:** Catmull-Rom cubic spline interpolation eliminating corner artifacts, configurable radius, flow, hardness, opacity, and alpha lock.
* **Contiguous & Global Flood Fill:** Non-recursive scanline flood fill with Euclidean CIELAB color tolerance and selection clipping.
* **Bayer-Dithered Gradients:** Linear and radial gradients with Pad, Repeat, and Reflect spread modes, anti-banded with Bayer 4×4 dither matrices.
* **Selections & Marching Ants:** Rectangular and elliptical marquees, freehand and polygonal lasso with real-time Marching Squares contour generation.
* **Infinite Tile-Delta Undo/Redo:** Compact tile-level delta snapshots storing only modified 512×512 tiles for zero-overhead undo history.

### 4. GPU Liquify & Free Transform
* **GPU Liquify Engine:** Non-destructive 32-bit floating-point displacement map driven by Metal compute shaders with Push, Twirl (CW/CCW), Pinch, Bloat, and Reconstruct modes.
* **Perspective & Bézier Warp:** 4-point Direct Linear Transformation (DLT) homography perspective pinning and 3×3 bicubic Bézier grid warping.
* **Pixelate Filter:** Square, hexagonal, and circular cell tessellation with center-point and area-average color sampling.

### 5. Smart AI & Vision Features
* **Foreground Instance Segmentation:** Apple Vision `VNGenerateForegroundInstanceMaskRequest` neural segmentation with guided edge refinement.
* **Chroma Key with Despill:** CIELAB Delta E color-difference background keying with controllable tolerance, feathering, and spill suppression.
* **ASCII Art Generator:** Edge-aware volume rendering using Sobel/Laplace gradient analysis, Unicode block character sets, and Floyd-Steinberg dithering baked directly to text or raster layers.

### 6. File I/O & Export
* **Adobe Photoshop (.psd):** Native 8BPS reader and writer with multi-layer preservation.
* **PixelCraft Project (.pcpro):** Native macOS FileWrapper bundle package with JSON manifest and lossless tile streams.
* **Export Formats:** PNG (8-bit and 16-bit HDR with alpha), JPEG (custom quality), TIFF, and HEIC.

---

## Requirements

* **Operating System:** macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)
* **Hardware:** Apple Silicon Mac (M1, M2, M3, M4 or later)
* **Build Tools:** Swift 5.10 / Swift 6.0 toolchain

---

## Quick Start & Building

### Clone the Repository
```bash
git clone https://github.com/dmsznv-dot/ProCraft.git
cd ProCraft
```

### Build & Run via CLI
```bash
# Build the release binary
swift build -c release

# Run the application
.build/release/PixelCraftApp
```

### Run Unit Tests
The project features 117 automated unit tests covering all Metal shaders, blend modes, tools, filters, and codecs:
```bash
swift test
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|:---|:---|
| `⌘ N` | New Document |
| `⌘ O` | Open Image or Project (PNG, JPG, TIFF, HEIC, PSD, PCPRO) |
| `⌘ I` | Import Image as New Layer |
| `⌘ S` | Save Project (`.pcpro`) |
| `⇧ ⌘ S` | Export as Photoshop PSD (`.psd`) |
| `⌘ Z` | Undo |
| `⇧ ⌘ Z` | Redo |
| `⇧ ⌘ N` | New Layer |
| `⌘ J` | Duplicate Layer |
| `⌘ E` | Merge Down |
| `⌘ +` / `⌘ -` | Zoom In / Zoom Out |
| `⌘ 0` | Actual Size (100%) |
| `⌘ 9` | Fit to Screen |
| `Space + Drag` | Pan / Hand Tool |

---

## Architecture

```
PixelCraftPro/
├── Sources/
│   ├── PixelCraftEngine/          # Core graphic engine library
│   │   ├── Metal/                 # SparseTileGrid, MetalContext, CanvasRenderer, LiquifyEngine, Shaders
│   │   ├── Model/                 # Document, Layer, BitmapLayer, TextLayer, BlendMode, ViewportTransform
│   │   ├── Tools/                 # Spline Brush, Eraser, FloodFill, Gradient, Eyedropper, Crop
│   │   ├── Selection/             # SelectionMask, Marquee, Lasso, Marching Squares
│   │   ├── Undo/                  # TileUndoManager, TileDelta, UndoCommands
│   │   ├── Transform/             # PerspectiveHomography, WarpGrid, Bicubic Resampling
│   │   ├── Filters/               # PixelateFilter, ChromaKeyFilter
│   │   ├── Vision/                # VisionBackgroundRemoval
│   │   ├── ASCII/                 # ASCIIGenerator
│   │   └── IO/                    # ImageImporter, ImageExporter, PSDCodec, PCProDocument
│   └── PixelCraftApp/             # macOS Native AppKit + SwiftUI application
│       ├── PixelCraftApp.swift    # App lifecycle, system commands, menus
│       ├── CanvasViewRepresentable.swift # Interactive MTKView canvas & Drag-and-Drop
│       ├── FloatingToolbarView.swift     # Glassmorphic floating tool selector
│       ├── SidebarView.swift      # Layer stack & History panel
│       └── InspectorView.swift    # Contextual tool settings & Quick Export
├── Tests/                         # 11 test suites (117 tests)
└── PixelCraftPro.app              # Standalone macOS Application Bundle
```

---

## License

Licensed under the MIT License.
