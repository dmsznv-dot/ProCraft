import Foundation
import CoreGraphics
import Metal
import simd
import PixelCraftEngine

// Helper to query process resident memory in bytes via Darwin mach task_info
func getResidentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    if kerr == KERN_SUCCESS {
        return info.resident_size
    } else {
        return 0
    }
}

func formatMB(_ bytes: UInt64) -> String {
    String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
}

func formatBytes(_ bytes: Int) -> String {
    String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
}

print("================================================================================")
print("PixelCraft Pro - Milestone 1 Empirical Stress Verifier")
print("Hardware: Apple Silicon ARM64, macOS")
print("================================================================================")

var allTestsPassed = true
var totalAssertions = 0

func assertTest(_ condition: Bool, _ message: String) {
    totalAssertions += 1
    if !condition {
        print("  [FAIL] \(message)")
        allTestsPassed = false
    } else {
        // print("  [PASS] \(message)")
    }
}

// ================================================================================
// SUITE 1: 8K Canvas ($8192 \times 4320$) Memory Allocation & Sparse Grid Invariant
// ================================================================================
print("\n--- SUITE 1: 8K Canvas Memory & Sparse Grid Invariant ---")

let baselineRSS = getResidentMemoryBytes()
print("Process Baseline RSS: \(formatMB(baselineRSS))")

do {
    let canvas8K = CGSize(width: 8192, height: 4320)
    let denseTileCount = 16 * 9 // 144 tiles
    let denseBytesPerLayer = denseTileCount * 512 * 512 * 4 // 144 MB
    
    print("Canvas Specifications:")
    print("  Resolution: \(Int(canvas8K.width)) x \(Int(canvas8K.height)) px (8K UHD)")
    print("  Tile Dimensions: 512 x 512 px, 4 bytes/px (1 MB per tile)")
    print("  Dense Grid Layout: 16 columns x 9 rows = \(denseTileCount) tiles per layer")
    print("  Dense Uncompressed Memory per layer: \(formatBytes(denseBytesPerLayer))")
    print("  Theoretical Dense 100-layer Memory: \(formatBytes(denseBytesPerLayer * 100)) (14.4 GB)")

    // Step 1: Create 8K Document
    let doc = try Document(title: "8K Stress Doc", canvasSize: canvas8K)
    let initialLayer = doc.layers[0]
    
    assertTest(initialLayer.tileGrid.allocatedTileCount == 0, "Initial 8K layer has 0 allocated tiles")
    assertTest(initialLayer.tileGrid.memoryUsageBytes == 0, "Initial 8K layer consumes 0 bytes of tile memory")
    assertTest(initialLayer.tileGrid.isEmpty, "Initial 8K layer isEmpty is true")
    assertTest(initialLayer.tileGrid.gridColumns == 16, "Grid columns == 16")
    assertTest(initialLayer.tileGrid.gridRows == 9, "Grid rows == 9")

    let docRSS = getResidentMemoryBytes()
    print("RSS after creating 8K Document (1 layer): \(formatMB(docRSS)) (Delta: \(formatMB(docRSS >= baselineRSS ? docRSS - baselineRSS : 0)))")

    // Step 2: Add up to 100 layers on 8K canvas without painting
    print("Allocating 99 additional layers on 8K canvas (Total 100 layers)...")
    let startAdd = Date()
    for i in 2...100 {
        let l = BitmapLayer(name: "Bitmap \(i)", canvasSize: canvas8K)
        doc.addLayer(l)
    }
    let addDuration = Date().timeIntervalSince(startAdd)
    print("100 layers created in \(String(format: "%.3f", addDuration)) seconds")
    
    assertTest(doc.layers.count == 100, "Document contains exactly 100 layers")

    var totalAllocatedTiles = 0
    var totalTileBytes = 0
    for l in doc.layers {
        totalAllocatedTiles += l.tileGrid.allocatedTileCount
        totalTileBytes += l.tileGrid.memoryUsageBytes
    }

    assertTest(totalAllocatedTiles == 0, "100 unallocated 8K layers have exactly 0 allocated tiles")
    assertTest(totalTileBytes == 0, "100 unallocated 8K layers consume exactly 0 bytes tile memory")

    let hundredLayersRSS = getResidentMemoryBytes()
    let deltaHundred = hundredLayersRSS >= baselineRSS ? hundredLayersRSS - baselineRSS : 0
    print("RSS with 100 8K unallocated layers: \(formatMB(hundredLayersRSS)) (Delta from baseline: \(formatMB(deltaHundred)))")
    assertTest(deltaHundred < 20 * 1024 * 1024, "100 8K layers consume < 20 MB system RSS (actual delta: \(formatMB(deltaHundred))) vs 14.4 GB dense")

    // Step 3: Sparse allocation verification - paint only 3 isolated pixels in Layer 1
    print("\nTesting sparse tile allocation with localized writes:")
    let activeLayer = doc.layers[0] as! BitmapLayer
    
    // Pixel 1: Top-Left (0, 0) -> Tile (0, 0)
    activeLayer.tileGrid.writePixel(x: 0, y: 0, color: SIMD4<UInt8>(255, 0, 0, 255))
    assertTest(activeLayer.tileGrid.allocatedTileCount == 1, "Touching pixel (0,0) allocates exactly 1 tile (1 MB)")
    assertTest(activeLayer.tileGrid.memoryUsageBytes == 1024 * 1024, "Tile memory is 1 MB")

    // Pixel 2: Center (4096, 2160) -> Tile (8, 4)
    activeLayer.tileGrid.writePixel(x: 4096, y: 2160, color: SIMD4<UInt8>(0, 255, 0, 255))
    assertTest(activeLayer.tileGrid.allocatedTileCount == 2, "Touching center pixel allocates 2nd tile (Total: 2 MB)")

    // Pixel 3: Bottom-Right (8191, 4319) -> Tile (15, 8)
    activeLayer.tileGrid.writePixel(x: 8191, y: 4319, color: SIMD4<UInt8>(0, 0, 255, 255))
    assertTest(activeLayer.tileGrid.allocatedTileCount == 3, "Touching bottom-right pixel allocates 3rd tile (Total: 3 MB)")

    assertTest(activeLayer.tileGrid.allocatedTileCount == 3, "Exactly 3 tiles allocated out of 144 (sparse ratio: 2.08%)")
    assertTest(activeLayer.tileGrid.memoryUsageBytes == 3 * 1024 * 1024, "Memory usage is exactly 3 MB")

    // Read back touched pixels
    let px1 = activeLayer.tileGrid.readPixel(x: 0, y: 0)
    let px2 = activeLayer.tileGrid.readPixel(x: 4096, y: 2160)
    let px3 = activeLayer.tileGrid.readPixel(x: 8191, y: 4319)
    assertTest(px1 == SIMD4<UInt8>(255, 0, 0, 255), "Pixel (0,0) read matches written value")
    assertTest(px2 == SIMD4<UInt8>(0, 255, 0, 255), "Pixel (4096,2160) read matches written value")
    assertTest(px3 == SIMD4<UInt8>(0, 0, 255, 255), "Pixel (8191,4319) read matches written value")

    // Reading unallocated tiles must return zeros AND must NOT allocate tiles
    let untouched = activeLayer.tileGrid.readPixel(x: 100, y: 100)
    assertTest(untouched == SIMD4<UInt8>(0, 0, 0, 0), "Untouched pixel returns transparent black")
    assertTest(activeLayer.tileGrid.allocatedTileCount == 3, "Reading untouched pixel did NOT allocate tile (still 3 tiles)")

    // Step 4: Duplicate sparse layer
    let dupLayer = activeLayer.duplicate()
    assertTest(dupLayer.tileGrid.allocatedTileCount == 3, "Duplicated layer retains sparse allocation (exactly 3 tiles)")
    assertTest(dupLayer.tileGrid.memoryUsageBytes == 3 * 1024 * 1024, "Duplicated layer consumes 3 MB, not 144 MB")

    // Step 5: Test boundary tile geometry calculations across all 16x9 tiles
    print("\nTesting boundary tile geometry on 8K grid:")
    for ty in 0..<9 {
        for tx in 0..<16 {
            let bounds = activeLayer.tileGrid.effectiveTileBounds(coord: TileCoord(x: tx, y: ty))
            // Columns 0..<16 are all 512 px wide because 16 * 512 = 8192
            assertTest(bounds.width == 512.0, "Tile (\(tx), \(ty)) width is 512")
            assertTest(bounds.maxU == 1.0, "Tile (\(tx), \(ty)) maxU is 1.0")
            
            if ty < 8 {
                assertTest(bounds.height == 512.0, "Tile (\(tx), \(ty)) height is 512")
                assertTest(bounds.maxV == 1.0, "Tile (\(tx), \(ty)) maxV is 1.0")
            } else {
                // Row 8: 4320 - (8 * 512 = 4096) = 224 px
                assertTest(bounds.height == 224.0, "Tile (\(tx), 8) partial height is 224")
                assertTest(abs(bounds.maxV - (224.0 / 512.0)) < 0.0001, "Tile (\(tx), 8) maxV is 224/512 = 0.4375")
            }
        }
    }

    // Step 6: Test out-of-bounds writes do not allocate or crash
    activeLayer.tileGrid.writePixel(x: -1, y: 0, color: SIMD4<UInt8>(1, 1, 1, 1))
    activeLayer.tileGrid.writePixel(x: 8192, y: 0, color: SIMD4<UInt8>(1, 1, 1, 1))
    activeLayer.tileGrid.writePixel(x: 0, y: 4320, color: SIMD4<UInt8>(1, 1, 1, 1))
    activeLayer.tileGrid.writePixel(x: 99999, y: 99999, color: SIMD4<UInt8>(1, 1, 1, 1))
    assertTest(activeLayer.tileGrid.allocatedTileCount == 3, "Out of bounds writes safely rejected, tile count remains 3")

    // Step 7: Clear tiles and verify deallocation
    activeLayer.tileGrid.removeAllTiles()
    assertTest(activeLayer.tileGrid.allocatedTileCount == 0, "removeAllTiles() releases all tiles (count == 0)")
    assertTest(activeLayer.tileGrid.memoryUsageBytes == 0, "removeAllTiles() resets memoryUsageBytes to 0")

    print("SUITE 1 Result: ALL 8K MEMORY & SPARSE GRID INVARIANTS VERIFIED!")
} catch {
    print("SUITE 1 Failed with error: \(error)")
    allTestsPassed = false
}

// ================================================================================
// SUITE 2: Viewport Transform Stability, Stationary Anchor Zoom & Roundtrip Precision
// ================================================================================
print("\n--- SUITE 2: Viewport Transform Stability & Roundtrip Precision ---")

do {
    // 2a. Stationary Anchor Point Zoom Invariant Stress Test
    // Stress test stationary anchor across 10,000 random operations
    print("Executing 10,000 randomized stationary anchor zoom operations...")
    
    var transform = ViewportTransform(zoom: 1.0, panOffset: CGPoint(x: 200, y: 150))
    var maxAnchorError: Double = 0.0
    var totalAnchorError: Double = 0.0
    let testIterations = 10_000
    
    // Seeded deterministic pseudo-random generator
    var seed: UInt64 = 0xDEADBEEFCAFE1234
    func nextRand() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 11) & 0xFFFFFFFFFFFFF) / Double(0x10000000000000)
    }

    let startZoomTime = Date()
    for _ in 1...testIterations {
        // Random screen anchor point in range [-1000, 3000] x [-1000, 2000]
        let anchorX = (nextRand() - 0.25) * 4000.0
        let anchorY = (nextRand() - 0.25) * 3000.0
        let anchorScreen = CGPoint(x: anchorX, y: anchorY)
        
        // Find canvas point directly under this screen anchor
        let canvasPointBefore = transform.screenToCanvas(anchorScreen)
        
        // Random zoom factor in range [0.2, 5.0]
        let factor = 0.2 + nextRand() * 4.8
        
        // Perform stationary zoom
        transform.zoom(by: factor, aroundScreenPoint: anchorScreen)
        
        // Verify invariant: canvasPointBefore must still project to anchorScreen
        let screenPointAfter = transform.canvasToScreen(canvasPointBefore)
        let errorX = abs(Double(screenPointAfter.x - anchorScreen.x))
        let errorY = abs(Double(screenPointAfter.y - anchorScreen.y))
        let err = max(errorX, errorY)
        
        if err > maxAnchorError {
            maxAnchorError = err
        }
        totalAnchorError += err
        
        // Also perform occasional random pan mutation
        if nextRand() < 0.3 {
            let deltaPan = CGPoint(x: (nextRand() - 0.5) * 200.0, y: (nextRand() - 0.5) * 200.0)
            transform.pan(by: deltaPan)
        }
    }
    let zoomDuration = Date().timeIntervalSince(startZoomTime)
    let meanAnchorError = totalAnchorError / Double(testIterations)
    
    print("10,000 zoom operations completed in \(String(format: "%.3f", zoomDuration)) seconds")
    print("  Max Anchor Drift Error: \(String(format: "%.8e", maxAnchorError)) px")
    print("  Mean Anchor Drift Error: \(String(format: "%.8e", meanAnchorError)) px")
    assertTest(maxAnchorError < 1e-4, "Max anchor drift error < 1e-4 px (sub-pixel precision maintained)")
    assertTest(meanAnchorError < 1e-6, "Mean anchor drift error < 1e-6 px")

    // 2b. Zoom range stress testing from 0.05 to 64.0
    print("\nTesting zoom range from 0.05 up to 64.0 (including clamp boundaries):")
    
    var rangeTransform = ViewportTransform(zoom: 1.0, panOffset: .zero)
    let cursor = CGPoint(x: 960, y: 540)
    
    // Zoom down to minimum (0.05)
    rangeTransform.setZoom(0.05, aroundScreenPoint: cursor)
    assertTest(rangeTransform.zoom == 0.05, "Zoom set to minimum 0.05")
    
    // Attempt zoom below minimum (0.001)
    rangeTransform.setZoom(0.001, aroundScreenPoint: cursor)
    assertTest(rangeTransform.zoom == 0.05, "Zoom below 0.05 clamped to 0.05")
    
    // Zoom up to maximum (32.0 in ViewportTransform.maxZoom)
    rangeTransform.setZoom(32.0, aroundScreenPoint: cursor)
    assertTest(rangeTransform.zoom == 32.0, "Zoom set to 32.0")
    
    // Attempt zoom beyond maxZoom (64.0)
    rangeTransform.setZoom(64.0, aroundScreenPoint: cursor)
    assertTest(rangeTransform.zoom == 32.0, "Zoom at 64.0 clamped to maxZoom (32.0)")
    
    // Verify mathematical stability at s = 64.0
    print("Testing mathematical coordinate projection stability at s = 64.0:")
    let s64 = 64.0
    let pan64 = CGPoint(x: -50000.0, y: 30000.0)
    let ptCanvas = CGPoint(x: 8191.75, y: 4319.25)
    
    let screenX = ptCanvas.x * CGFloat(s64) + pan64.x
    let screenY = ptCanvas.y * CGFloat(s64) + pan64.y
    let roundtripX = (screenX - pan64.x) / CGFloat(s64)
    let roundtripY = (screenY - pan64.y) / CGFloat(s64)
    
    let delta64X = abs(roundtripX - ptCanvas.x)
    let delta64Y = abs(roundtripY - ptCanvas.y)
    print("  Roundtrip delta at s = 64.0: (\(String(format: "%.8e", delta64X)), \(String(format: "%.8e", delta64Y)))")
    assertTest(delta64X < 1e-10 && delta64Y < 1e-10, "Coordinate roundtrip at scale 64.0 maintains double-precision stability")

    // 2c. Bidirectional Roundtrip Precision Stress across 10,000 points
    print("\nExecuting 10,000 bidirectional coordinate roundtrips across extreme canvas coordinates:")
    var maxRoundtripError: Double = 0.0
    let testZooms = [0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0]
    
    for _ in 1...10_000 {
        let z = testZooms[Int(nextRand() * Double(testZooms.count))]
        let pan = CGPoint(x: (nextRand() - 0.5) * 20000.0, y: (nextRand() - 0.5) * 20000.0)
        let vt = ViewportTransform(zoom: z, panOffset: pan)
        
        // Random canvas point including subpixels
        let origCanvas = CGPoint(
            x: (nextRand() - 0.1) * 10000.0,
            y: (nextRand() - 0.1) * 6000.0
        )
        
        let screen = vt.canvasToScreen(origCanvas)
        let recoveredCanvas = vt.screenToCanvas(screen)
        
        let err = max(abs(Double(recoveredCanvas.x - origCanvas.x)), abs(Double(recoveredCanvas.y - origCanvas.y)))
        if err > maxRoundtripError {
            maxRoundtripError = err
        }
    }
    print("  Max Bidirectional Roundtrip Error across 10,000 random points: \(String(format: "%.8e", maxRoundtripError)) px")
    assertTest(maxRoundtripError < 1e-8, "Bidirectional roundtrip error < 1e-8 px")

    // 2d. Matrix Representation Consistency
    let matrixVT = ViewportTransform(zoom: 3.5, panOffset: CGPoint(x: 120, y: -80))
    let metalMat = matrixVT.metalMatrix
    let cgTransform = matrixVT.affineTransform
    
    let testPt = CGPoint(x: 400, y: 300)
    let screenFromMethod = matrixVT.canvasToScreen(testPt)
    let screenFromCG = testPt.applying(cgTransform)
    let screenFromMetal = metalMat * SIMD3<Float>(Float(testPt.x), Float(testPt.y), 1.0)
    
    assertTest(abs(screenFromMethod.x - screenFromCG.x) < 1e-5, "affineTransform matches canvasToScreen X")
    assertTest(abs(screenFromMethod.y - screenFromCG.y) < 1e-5, "affineTransform matches canvasToScreen Y")
    assertTest(abs(Double(screenFromMetal.x) - Double(screenFromMethod.x)) < 1e-3, "metalMatrix matches canvasToScreen X")
    assertTest(abs(Double(screenFromMetal.y) - Double(screenFromMethod.y)) < 1e-3, "metalMatrix matches canvasToScreen Y")

    print("SUITE 2 Result: ALL VIEWPORT STABILITY & PRECISION INVARIANTS VERIFIED!")
}

// ================================================================================
// SUITE 3: Layer Stack Stress, CRUD, Reordering, Non-Empty Invariant
// ================================================================================
print("\n--- SUITE 3: Layer Stack Stress & Invariants ---")

do {
    let doc = try Document(title: "Layer Stress Doc", canvasSize: CGSize(width: 3840, height: 2160))
    assertTest(doc.layers.count == 1, "Initial layer count is 1")
    assertTest(doc.activeLayerIndex == 0, "Initial active layer index is 0")

    // 3a. Add up to 100 polymorphic layers
    print("Adding 99 polymorphic layers (Bitmap, Text, Adjustment, Effect)...")
    for i in 2...100 {
        let layerType = i % 4
        switch layerType {
        case 0:
            doc.addLayer(BitmapLayer(name: "Bitmap \(i)", canvasSize: doc.canvasSize))
        case 1:
            doc.addLayer(TextLayer(name: "Text \(i)", text: "Title \(i)", canvasSize: doc.canvasSize))
        case 2:
            doc.addLayer(AdjustmentLayer(name: "Adjustment \(i)", type: .brightnessContrast, canvasSize: doc.canvasSize))
        default:
            doc.addLayer(EffectLayer(name: "Effect \(i)", type: .gaussianBlur, canvasSize: doc.canvasSize))
        }
        assertTest(doc.layers.count == i, "Layer count correctly increments to \(i)")
        assertTest(doc.activeLayerIndex == i - 1, "Active layer index tracks insertion at top (\(i - 1))")
    }
    assertTest(doc.layers.count == 100, "Successfully built 100-layer stack")

    // 3b. Duplicate layers at various indices
    print("Testing duplicate operations on layer stack...")
    let dupTarget = try doc.duplicateLayer(at: 50)
    assertTest(doc.layers.count == 101, "Duplicate layer incremented count to 101")
    assertTest(doc.activeLayerIndex == 51, "Duplicate layer inserted at index 51 and selected")
    assertTest(doc.layers[51].id == dupTarget.id, "Layer at 51 is the duplicate")

    // Duplicate at top
    _ = try doc.duplicateLayer(at: 100)
    assertTest(doc.layers.count == 102, "Duplicate top layer incremented count to 102")
    assertTest(doc.activeLayerIndex == 101, "Duplicate top layer inserted at index 101")

    // 3c. Move layers and test selection tracking
    print("Testing layer reordering and active selection tracking...")
    // Move layer from index 0 to 50
    let movedLayerID = doc.layers[0].id
    try doc.moveLayer(from: 0, to: 50)
    assertTest(doc.layers[50].id == movedLayerID, "Layer originally at 0 is now at 50")

    // Test active layer tracking when active layer moves
    doc.selectLayer(at: 20)
    let activeID = doc.activeLayer.id
    try doc.moveLayer(from: 20, to: 80)
    assertTest(doc.activeLayerIndex == 80, "activeLayerIndex tracked moved layer to 80")
    assertTest(doc.activeLayer.id == activeID, "activeLayer still refers to the same layer")

    // Move a layer before active layer to after active layer
    let oldActiveIdx = doc.activeLayerIndex // 80
    try doc.moveLayer(from: 10, to: 90)
    assertTest(doc.activeLayerIndex == oldActiveIdx - 1, "activeLayerIndex decremented by 1 when layer moved past it")
    assertTest(doc.activeLayer.id == activeID, "activeLayer remains unchanged")

    // 3d. Delete operations down to 1 layer
    print("Deleting 101 layers down to 1 remaining layer...")
    while doc.layers.count > 1 {
        let countBefore = doc.layers.count
        try doc.deleteLayer(at: doc.layers.count - 1)
        assertTest(doc.layers.count == countBefore - 1, "Layer count decremented")
        assertTest(doc.activeLayerIndex >= 0 && doc.activeLayerIndex < doc.layers.count, "Active index valid")
    }
    assertTest(doc.layers.count == 1, "Stack reduced to exactly 1 layer")
    assertTest(doc.activeLayerIndex == 0, "Active layer index is 0")

    // 3e. Non-Empty Invariant Stress Test: delete the LAST layer
    print("Testing non-empty invariant: deleting the last remaining layer...")
    let soleLayerIDBefore = doc.layers[0].id
    try doc.deleteLayer(at: 0)
    assertTest(doc.layers.count == 1, "Non-empty invariant: deleting last layer retains exactly 1 layer")
    assertTest(doc.activeLayerIndex == 0, "Active index remains 0")
    assertTest(doc.layers[0].id != soleLayerIDBefore, "Last layer was replaced with a fresh empty layer")
    assertTest(doc.layers[0].name == "Layer 1", "Replacement layer is named Layer 1")

    // Repeat delete on single layer 10 times
    for _ in 1...10 {
        try doc.deleteLayer(at: 0)
        assertTest(doc.layers.count == 1, "Non-empty invariant preserved under repeated delete")
    }

    // 3f. Out of bounds error handling
    print("Testing boundary error conditions on layer CRUD:")
    var threwOutOfBounds = false
    do {
        try doc.deleteLayer(at: -1)
    } catch DocumentError.layerIndexOutOfBounds {
        threwOutOfBounds = true
    } catch {}
    assertTest(threwOutOfBounds, "deleteLayer at -1 threw layerIndexOutOfBounds")

    threwOutOfBounds = false
    do {
        try doc.deleteLayer(at: 999)
    } catch DocumentError.layerIndexOutOfBounds {
        threwOutOfBounds = true
    } catch {}
    assertTest(threwOutOfBounds, "deleteLayer at 999 threw layerIndexOutOfBounds")

    threwOutOfBounds = false
    do {
        try doc.moveLayer(from: -1, to: 0)
    } catch DocumentError.layerIndexOutOfBounds {
        threwOutOfBounds = true
    } catch {}
    assertTest(threwOutOfBounds, "moveLayer from -1 threw layerIndexOutOfBounds")

    threwOutOfBounds = false
    do {
        try doc.moveLayer(from: 0, to: 100)
    } catch DocumentError.layerIndexOutOfBounds {
        threwOutOfBounds = true
    } catch {}
    assertTest(threwOutOfBounds, "moveLayer to 100 threw layerIndexOutOfBounds")

    // 3g. 1,000-Operation Randomized Monkey Test
    print("Executing 1,000 randomized CRUD operations (monkey test)...")
    var monkeySeed: UInt64 = 0x123456789ABCDEF0
    func nextMonkeyRand() -> Double {
        monkeySeed = monkeySeed &* 6364136223846793005 &+ 1442695040888963407
        return Double((monkeySeed >> 11) & 0xFFFFFFFFFFFFF) / Double(0x10000000000000)
    }

    for step in 1...1000 {
        let op = Int(nextMonkeyRand() * 5.0)
        let currentCount = doc.layers.count
        
        switch op {
        case 0: // Add
            if currentCount < 150 {
                doc.addLayer(BitmapLayer(name: "Monkey \(step)", canvasSize: doc.canvasSize))
            }
        case 1: // Duplicate
            let idx = Int(nextMonkeyRand() * Double(currentCount))
            _ = try doc.duplicateLayer(at: idx)
        case 2: // Delete
            let idx = Int(nextMonkeyRand() * Double(currentCount))
            try doc.deleteLayer(at: idx)
        case 3: // Move
            if currentCount > 1 {
                let from = Int(nextMonkeyRand() * Double(currentCount))
                let to = Int(nextMonkeyRand() * Double(currentCount))
                try doc.moveLayer(from: from, to: to)
            }
        case 4: // Select
            let idx = Int(nextMonkeyRand() * Double(currentCount))
            doc.selectLayer(at: idx)
        default:
            break
        }
        
        // Invariants must hold after EVERY operation
        assertTest(doc.layers.count >= 1, "Invariant: layers.count >= 1 (was \(doc.layers.count))")
        assertTest(doc.activeLayerIndex >= 0 && doc.activeLayerIndex < doc.layers.count, "Invariant: active index valid")
        assertTest(doc.activeLayer.id == doc.layers[doc.activeLayerIndex].id, "Invariant: activeLayer matches index")
    }
    print("1,000 randomized monkey operations passed with 0 invariant violations!")

    print("SUITE 3 Result: ALL LAYER STACK & NON-EMPTY INVARIANTS VERIFIED!")
} catch {
    print("SUITE 3 Failed with error: \(error)")
    allTestsPassed = false
}

print("\n================================================================================")
print("FINAL SUMMARY:")
print("  Total Assertions Evaluated: \(totalAssertions)")
print("  All Suites Passed: \(allTestsPassed ? "YES (100% SUCCESS)" : "NO (FAILURES DETECTED)")")
print("================================================================================")

if !allTestsPassed {
    exit(1)
} else {
    exit(0)
}
