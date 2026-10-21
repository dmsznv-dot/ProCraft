#if canImport(XCTest)
import XCTest
#endif
@testable import PixelCraftEngine

final class DocumentTests: XCTestCase, @unchecked Sendable {
    
    // MARK: - Resolution & Initialization Tests
    
    func testDefaultDocumentCreation() throws {
        let doc = try Document()
        
        XCTAssertEqual(doc.width, 1920)
        XCTAssertEqual(doc.height, 1080)
        XCTAssertEqual(doc.canvasSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(doc.layers.count, 1)
        XCTAssertEqual(doc.activeLayerIndex, 0)
        XCTAssertEqual(doc.activeLayer.name, "Background")
        XCTAssertTrue(doc.activeLayer.isVisible)
        XCTAssertEqual(doc.activeLayer.opacity, 1.0)
        XCTAssertEqual(doc.activeLayer.blendMode, .normal)
    }
    
    func test8KCanvasResolutionSupport() throws {
        let size8K = CGSize(width: 8192, height: 4320)
        let doc = try Document(title: "8K Project", canvasSize: size8K)
        
        XCTAssertEqual(doc.width, 8192)
        XCTAssertEqual(doc.height, 4320)
        XCTAssertEqual(doc.bounds, CGRect(origin: .zero, size: size8K))
        XCTAssertEqual(doc.aspectRatio, 8192.0 / 4320.0, accuracy: 0.0001)
    }
    
    func testBoundaryValidationRejectsInvalidDimensions() {
        // Zero dimensions
        XCTAssertThrowsError(try Document(canvasSize: CGSize(width: 0, height: 1080))) { error in
            guard case DocumentError.invalidDimensions = error else {
                XCTFail("Expected invalidDimensions error, got \(error)")
                return
            }
        }
        
        // Negative dimensions
        XCTAssertThrowsError(try Document(canvasSize: CGSize(width: 1920, height: -500))) { error in
            guard case DocumentError.invalidDimensions = error else {
                XCTFail("Expected invalidDimensions error, got \(error)")
                return
            }
        }
        
        // Exceeding 8K max dimensions
        XCTAssertThrowsError(try Document(canvasSize: CGSize(width: 8193, height: 4320))) { error in
            guard case DocumentError.canvasExceedsMaximumSize = error else {
                XCTFail("Expected canvasExceedsMaximumSize error, got \(error)")
                return
            }
        }
        
        XCTAssertThrowsError(try Document(canvasSize: CGSize(width: 8192, height: 4321))) { error in
            guard case DocumentError.canvasExceedsMaximumSize = error else {
                XCTFail("Expected canvasExceedsMaximumSize error, got \(error)")
                return
            }
        }
    }

    // MARK: - Layer Stack CRUD Tests
    
    func testAddLayerIncrementsCountAndUpdatesActiveIndex() throws {
        let doc = try Document()
        XCTAssertEqual(doc.layers.count, 1)
        XCTAssertEqual(doc.activeLayerIndex, 0)
        
        let layer2 = doc.addLayer()
        XCTAssertEqual(doc.layers.count, 2)
        XCTAssertEqual(doc.activeLayerIndex, 1)
        XCTAssertEqual(doc.activeLayer.id, layer2.id)
        
        let layer3 = doc.addLayer(at: 0)
        XCTAssertEqual(doc.layers.count, 3)
        XCTAssertEqual(doc.activeLayerIndex, 0)
        XCTAssertEqual(doc.layers[0].id, layer3.id)
    }
    
    func testDuplicateLayerClonesPropertiesAndInsertsAbove() throws {
        let doc = try Document()
        doc.activeLayer.name = "Art"
        doc.activeLayer.opacity = 0.75
        doc.activeLayer.blendMode = .multiply
        
        let clone = try doc.duplicateLayer()
        XCTAssertEqual(doc.layers.count, 2)
        XCTAssertEqual(doc.activeLayerIndex, 1)
        XCTAssertEqual(clone.name, "Art Copy")
        XCTAssertEqual(clone.opacity, 0.75)
        XCTAssertEqual(clone.blendMode, .multiply)
        XCTAssertNotEqual(clone.id, doc.layers[0].id)
    }
    
    func testDeleteLayerSafetyInvariantNeverAllowsZeroLayers() throws {
        let doc = try Document()
        XCTAssertEqual(doc.layers.count, 1)
        let initialId = doc.activeLayer.id
        
        // Deleting the only remaining layer must not empty the stack
        try doc.deleteLayer(at: 0)
        XCTAssertEqual(doc.layers.count, 1)
        XCTAssertEqual(doc.activeLayerIndex, 0)
        XCTAssertNotEqual(doc.activeLayer.id, initialId, "Should replace with a fresh empty layer")
    }
    
    func testDeleteLayerWithMultipleLayers() throws {
        let doc = try Document()
        doc.addLayer() // Count 2, active 1
        doc.addLayer() // Count 3, active 2
        XCTAssertEqual(doc.layers.count, 3)
        
        try doc.deleteLayer(at: 2)
        XCTAssertEqual(doc.layers.count, 2)
        XCTAssertEqual(doc.activeLayerIndex, 1)
        
        try doc.deleteLayer(at: 0)
        XCTAssertEqual(doc.layers.count, 1)
        XCTAssertEqual(doc.activeLayerIndex, 0)
    }
    
    func testMoveLayerReordering() throws {
        let doc = try Document()
        let l1 = doc.layers[0]; l1.name = "L1"
        let l2 = doc.addLayer(); l2.name = "L2"
        let l3 = doc.addLayer(); l3.name = "L3"
        // Order: [L1, L2, L3], active = 2 (L3)
        
        // Move L3 (index 2) to bottom (index 0)
        try doc.moveLayer(from: 2, to: 0)
        XCTAssertEqual(doc.layers[0].name, "L3")
        XCTAssertEqual(doc.layers[1].name, "L1")
        XCTAssertEqual(doc.layers[2].name, "L2")
        XCTAssertEqual(doc.activeLayerIndex, 0, "Active selection should track with the moved layer")
    }
    
    func testLayerStackCapacity10PlusLayers() throws {
        let doc = try Document()
        
        // Add 15 layers
        for i in 1...15 {
            let l = doc.addLayer()
            l.name = "Layer \(i)"
            l.opacity = Float(i) / 15.0
        }
        
        XCTAssertEqual(doc.layers.count, 16)
        
        // Toggle visibility on alternate layers
        for (idx, l) in doc.layers.enumerated() {
            l.isVisible = (idx % 2 == 0)
        }
        
        XCTAssertEqual(doc.visibleLayers.count, 8)
        
        // Delete 5 layers
        for _ in 0..<5 {
            try doc.deleteLayer(at: doc.layers.count - 1)
        }
        XCTAssertEqual(doc.layers.count, 11)
    }

    // MARK: - Layer Stack Compositing Mutator Tests

    func testMergeDownOperation() throws {
        let doc = try Document(canvasSize: CGSize(width: 512, height: 512))
        let bottom = doc.layers[0]
        bottom.tileGrid.writePixel(x: 10, y: 10, color: SIMD4<UInt8>(255, 0, 0, 255)) // Red

        let top = doc.addLayer()
        top.blendMode = .normal
        top.tileGrid.writePixel(x: 10, y: 10, color: SIMD4<UInt8>(0, 255, 0, 255)) // Green

        XCTAssertEqual(doc.layers.count, 2)
        try doc.mergeDown(at: 1)

        XCTAssertEqual(doc.layers.count, 1)
        let mergedPixel = doc.layers[0].tileGrid.readPixel(x: 10, y: 10)
        XCTAssertEqual(mergedPixel.x, 0)
        XCTAssertEqual(mergedPixel.y, 255)
        XCTAssertEqual(mergedPixel.z, 0)
        XCTAssertEqual(mergedPixel.w, 255)
    }

    func testMergeVisibleOperation() throws {
        let doc = try Document(canvasSize: CGSize(width: 512, height: 512))
        doc.layers[0].name = "Base"
        
        let l2 = doc.addLayer()
        l2.name = "L2"
        l2.tileGrid.writePixel(x: 5, y: 5, color: SIMD4<UInt8>(0, 0, 255, 255))

        let l3 = doc.addLayer()
        l3.name = "L3"
        l3.isVisible = false // Hidden

        XCTAssertEqual(doc.layers.count, 3)
        try doc.mergeVisible()

        // Base and L2 merged into 1, L3 remains hidden
        XCTAssertEqual(doc.layers.count, 2)
        XCTAssertFalse(doc.layers.contains(where: { $0.name == "L2" }))
    }

    func testFlattenOperation() throws {
        let doc = try Document(canvasSize: CGSize(width: 512, height: 512))
        _ = doc.addLayer()
        _ = doc.addLayer()
        XCTAssertEqual(doc.layers.count, 3)

        try doc.flatten()
        XCTAssertEqual(doc.layers.count, 1)
        XCTAssertEqual(doc.activeLayerIndex, 0)
        XCTAssertEqual(doc.layers[0].name, "Background")
        XCTAssertTrue(doc.layers[0].isVisible)
    }
}
