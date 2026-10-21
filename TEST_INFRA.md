# E2E Test Infra: PixelCraft Pro

## Test Philosophy
- Opaque-box, requirement-driven testing derived strictly from `ORIGINAL_REQUEST.md`.
- Systematic 4-tier methodology: Category-Partition (Tier 1), Boundary Value Analysis (Tier 2), Pairwise Combinatorial Testing (Tier 3), Real-World Application Scenarios (Tier 4).
- Progressive testability: Earliest tests verify basic primitives before depending on composite features.

## Feature Inventory & Test Matrix
| # | Feature | Requirement | Tier 1 (Count) | Tier 2 (Count) | Tier 3 (Pairwise) |
|---|---------|-------------|:--------------:|:--------------:|:-----------------:|
| F1 | Metal Canvas GPU Rendering | R1 | 5 | 5 | ✓ |
| F2 | Viewport Zoom & Pan Matrix | R1 | 5 | 5 | ✓ |
| F3 | 8K Tiled Rendering (512x512) | R1 | 5 | 5 | ✓ |
| F4 | Polymorphic Layer Stack | R1 | 5 | 5 | ✓ |
| F5 | Layer CRUD & Reordering | R1 | 5 | 5 | ✓ |
| F6 | Layer Merge (Down, Visible, Flatten) | R1 | 5 | 5 | ✓ |
| F7 | Layer Opacity & Lock Alpha | R1 | 5 | 5 | ✓ |
| F8 | Blend Modes (7 core + extras) | R1 | 5 | 5 | ✓ |
| F9 | Brush Tool (Round, Square, Soft) | R2 | 5 | 5 | ✓ |
| F10 | Eraser Tool & Alpha Lock | R2 | 5 | 5 | ✓ |
| F11 | Flood Fill (Scanline) | R2 | 5 | 5 | ✓ |
| F12 | Gradients (Linear & Radial) | R2 | 5 | 5 | ✓ |
| F13 | Eyedropper Color Sampling | R2 | 5 | 5 | ✓ |
| F14 | Selection Tools (Marquee, Lasso) | R2 | 5 | 5 | ✓ |
| F15 | Selection Painting Constraints | R2 | 5 | 5 | ✓ |
| F16 | Crop Tool Canvas Resize | R2 | 5 | 5 | ✓ |
| F17 | Undo/Redo Tile Delta History | R2 | 5 | 5 | ✓ |
| F18 | Free Transform (Scale, Rotate, Skew) | R3 | 5 | 5 | ✓ |
| F19 | Transform Interpolations | R3 | 5 | 5 | ✓ |
| F20 | Perspective DLT Homography | R3 | 5 | 5 | ✓ |
| F21 | 3x3 Warp Grid Deformation | R3 | 5 | 5 | ✓ |
| F22 | Pixelate Filter (Square & Hex) | R3 | 5 | 5 | ✓ |
| F23 | GPU Liquify Compute Engine | R3 | 5 | 5 | ✓ |
| F24 | Vision AI Background Removal | R4 | 5 | 5 | ✓ |
| F25 | Mask Guided Filter Refinement | R4 | 5 | 5 | ✓ |
| F26 | Chroma Key Delta E & Despill | R4 | 5 | 5 | ✓ |
| F27 | ASCII Image Pipeline | R5 | 5 | 5 | ✓ |
| F28 | ASCII Glyph Mapping & Dither | R5 | 5 | 5 | ✓ |
| F29 | ASCII Layer Outputs | R5 | 5 | 5 | ✓ |
| F30 | Project File Save/Open (.pcpro) | R6 | 5 | 5 | ✓ |
| F31 | PSD Format Import/Export | R6 | 5 | 5 | ✓ |
| F32 | Multi-Format Export (PNG/JPEG/TIFF/HEIC) | R6 | 5 | 5 | ✓ |
| F33 | 3-Column NavigationSplitView UI | R7 | 5 | 5 | ✓ |
| F34 | Floating Toolbar & Styling | R7 | 5 | 5 | ✓ |
| F35 | Keyboard Shortcuts & Focus Guard | R7 | 5 | 5 | ✓ |
| F36 | Layer & Property Inspectors | R7 | 5 | 5 | ✓ |

## Test Architecture
- **Location**: `Tests/PixelCraftEngineTests/` and `Tests/E2ETests/`
- **Execution Command**:
  ```bash
  swift test
  ```
- **Pass/Fail Semantics**: 100% test assertions pass with exit code 0. Zero crashes, zero memory leaks, zero unhandled errors.

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Studio Portrait Retouching & Export | F1, F4, F9, F10, F24, F25, F32 | High |
| 2 | High-Resolution 8K Matte Painting | F3, F7, F8, F9, F11, F12, F17, F30 | Very High |
| 3 | Chroma Key Green Screen Composite | F4, F6, F7, F8, F26, F30, F32 | High |
| 4 | Character Art Poster with ASCII Stylization | F4, F8, F14, F18, F22, F27, F28, F29 | High |
| 5 | Full Graphic Asset Pipeline (Import -> Transform/Liquify -> Multi-Format Export) | F14, F18, F20, F23, F30, F31, F32 | Very High |

## Coverage Thresholds
- **Tier 1 (Feature Coverage)**: ≥5 test cases per feature (36 features × 5 = 180 tests)
- **Tier 2 (Boundary & Corner)**: ≥5 test cases per feature (36 features × 5 = 180 tests)
- **Tier 3 (Cross-Feature Combinations)**: ≥36 interaction tests covering state & compositing pairs
- **Tier 4 (Real-World Scenarios)**: ≥5 complete end-to-end workload pipelines
- **Total Suite Target**: ≥400 test cases
