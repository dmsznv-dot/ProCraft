# Original User Request

## 2026-10-20T13:33:37Z

Build PixelCraft Pro — a professional macOS native graphic editor application. The app targets macOS 14.0+ (Apple Silicon native, ARM64) and must be built strictly with Swift, SwiftUI/AppKit, and the Metal API. The goal is a fully functional, impressive demo application with a polished native macOS UI following Apple Human Interface Guidelines. This is a large multi-component project requiring a full team.

Working directory: /Users/dmitrysazonov/Projects/PixelCraftPro
Integrity mode: development

## Requirements

### R1. Metal-Accelerated Canvas with Layer System
The application must provide a GPU-accelerated canvas using Metal for rendering. The canvas must support smooth zoom (pinch and Cmd+/Cmd-), panning (Space+drag), and handle resolutions up to 8K (8192×4320 px) via tiled rendering. The layer system must support: bitmap layers, text layers, adjustment layers, and effect/filter layers. Layers must be reorderable via drag-and-drop in a side panel, support blending modes (Normal, Multiply, Screen, Overlay, Soft Light, Hard Light, Difference at minimum), per-layer opacity (0–100%), lock alpha, and operations: add, duplicate, delete, merge down, merge visible, and flatten.

### R2. Drawing and Selection Tools
The editor must include a functional drawing toolkit: brush (round, square, soft variants with size/opacity/flow), eraser, fill (flood fill), gradient tool, eyedropper/color picker, selection tools (rectangular marquee, elliptical marquee, lasso), and crop tool. All drawing tools must render to the active bitmap layer with undo/redo support.

### R3. Transform, Distort, Pixelate, and Liquify Tools
**Transform:** Free transform with scale, rotate, skew, flip. Support Shift (constrain proportions), Option (from center), custom pivot point. Interpolation modes: Nearest Neighbor, Bilinear, Bicubic.
**Distort:** 4-corner pin perspective transform and warp grid (at least 3×3). Bézier-curve handles for free-form distortion.
**Pixelate:** Block size 2–512px, square and hexagonal grid modes, center-pixel and average-color sampling.
**Liquify:** GPU-accelerated Metal compute shader with Push/Warp, Reconstruct, Twirl CW/CCW, Pinch, Bloat tools. Brush parameters: size, pressure, density, rate. Must use a displacement map buffer for non-destructive editing.

### R4. AI-Powered Background Removal and Chroma Key
**Smart Background Removal:** Use Vision.framework (`VNGenerateForegroundInstanceMaskRequest`) to detect and segment the primary subject (people, objects, animals) and generate a refined mask with edge detail (hair, fur, thin edges).
**Chroma Key:** Click-to-sample color removal using CIELAB Delta E color distance. Parameters: Tolerance (sensitivity), Feather (edge softness), Spill Suppression (remove color reflections on edges).

### R5. ASCII Art Generator
Convert a raster layer or selection to ASCII/Unicode pseudo-graphics with depth and shading awareness. Pipeline: luminance conversion → adaptive histogram contrast → edge detection (Sobel/Laplacian) → character mapping. Character sets: standard (`.:-=+*#%@`), extended Unicode (block characters), and user-defined custom set. Parameters: grid resolution (horizontal/vertical character count), font selection (monospaced: SF Mono, Menlo), density/weight, dithering toggle, volume intensity (contrast amplification). Output as a text layer or baked to a raster layer.

### R6. File I/O and Export
**Save/Open:** PSD file format support for opening and saving with layer structure preserved. If full PSD read/write is not feasible, implement a native project format (.pcpro or similar) that preserves all layer data, and provide PSD import/export on a best-effort basis.
**Export:** PNG (8-bit and 16-bit per channel, with alpha), JPEG (quality slider), TIFF (with layers optionally), HEIC. All exports must correctly preserve the alpha channel when applicable.

### R7. Native macOS UI/UX
The interface must follow Apple Human Interface Guidelines: use `NavigationSplitView` for the main layout (sidebar for layers, detail for canvas, inspector for properties). Apply system vibrancy/blur effects, SF Symbols 5+ for all icons, automatic Light/Dark mode support. Include a floating/sticky toolbar for tool selection. Keyboard shortcuts: Cmd+Z/Cmd+Shift+Z (undo/redo), Cmd+S (save), Cmd+E (export), Delete (delete layer), Space (pan), Cmd+/Cmd- (zoom in/out).

## Acceptance Criteria

### Build and Launch
- [ ] The Xcode project compiles without errors on macOS 14.0+ targeting Apple Silicon (arm64)
- [ ] The application launches and displays the main editor window with canvas, layer panel, tool bar, and inspector
- [ ] The application does not crash during normal operation (creating documents, drawing, applying effects, saving, exporting)

### Canvas and Layers
- [ ] A new document can be created with a user-specified resolution (at minimum 1920×1080 up to 8192×4320)
- [ ] The canvas supports smooth zoom in/out and panning via keyboard shortcuts and gestures
- [ ] At least 10 layers can be created, reordered, shown/hidden, and deleted without performance degradation
- [ ] At least 5 blending modes work correctly when compositing layers (visually verifiable by applying a blending mode to a colored layer over another)
- [ ] Layer opacity slider changes are reflected on the canvas in real time

### Drawing Tools
- [ ] Brush tool paints strokes on the active bitmap layer with configurable size and color
- [ ] Eraser tool removes pixel content from the active layer
- [ ] Fill tool fills a contiguous area with the selected color
- [ ] Eyedropper tool samples and selects a color from the canvas
- [ ] Rectangular selection tool creates a selection that constrains drawing/fill operations

### Transform and Effects
- [ ] Free Transform (scale, rotate) works on the active layer with visual handles
- [ ] Pixelate effect is visible on a test layer with adjustable block size
- [ ] Liquify tool visually deforms pixel content in real time on the canvas

### AI Background Removal
- [ ] When a photo with a clear subject is loaded, the background removal tool produces a mask that isolates the subject
- [ ] Chroma key tool removes a sampled color from the image within the specified tolerance

### ASCII Art
- [ ] An image or layer can be converted to ASCII art output with visible character-based representation
- [ ] At least two character sets are available (standard and extended)
- [ ] Grid resolution parameter changes the density of the output

### File Operations
- [ ] A project can be saved to disk and re-opened with layers preserved
- [ ] Export to PNG produces a valid PNG file with correct dimensions and alpha channel
- [ ] Export to JPEG produces a valid JPEG file

### Automated Tests
- [ ] XCTest unit tests exist for core engine logic: layer compositing, color sampling (Delta E), ASCII character mapping, transform matrix calculations
- [ ] All unit tests pass when run via `xcodebuild test`
- [ ] At minimum 10 unit tests covering distinct functionality areas
