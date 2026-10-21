#if canImport(XCTest)
import XCTest
#endif
import simd
@testable import PixelCraftEngine

final class BlendModeTests: XCTestCase, @unchecked Sendable {

    // MARK: - Core 7 Blend Modes on Mid-Gray (0.5, 0.5, 0.5)
    
    func testMidGrayCoreBlendModes() {
        let cb = SIMD3<Float>(0.5, 0.5, 0.5)
        let cs = SIMD3<Float>(0.5, 0.5, 0.5)

        let normal = BlendMode.normal.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(normal.x, 0.5000, accuracy: 0.005)

        let multiply = BlendMode.multiply.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(multiply.x, 0.2500, accuracy: 0.005)

        let screen = BlendMode.screen.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(screen.x, 0.7500, accuracy: 0.005)

        let overlay = BlendMode.overlay.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(overlay.x, 0.5000, accuracy: 0.005)

        let softLight = BlendMode.softLight.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(softLight.x, 0.5000, accuracy: 0.005)

        let hardLight = BlendMode.hardLight.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(hardLight.x, 0.5000, accuracy: 0.005)

        let difference = BlendMode.difference.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(difference.x, 0.0000, accuracy: 0.005)
    }

    // MARK: - Asymmetric Blend Vectors (0.2 backdrop, 0.8 source)
    
    func testAsymmetricBlendVectors() {
        let cb = SIMD3<Float>(0.2, 0.2, 0.2)
        let cs = SIMD3<Float>(0.8, 0.8, 0.8)

        let overlay = BlendMode.overlay.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(overlay.x, 0.3200, accuracy: 0.005)

        let hardLight = BlendMode.hardLight.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(hardLight.x, 0.6800, accuracy: 0.005)

        let softLight = BlendMode.softLight.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(softLight.x, 0.3488, accuracy: 0.005)

        let difference = BlendMode.difference.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(difference.x, 0.6000, accuracy: 0.005)
    }

    // MARK: - Overlay vs Hard Light Mathematical Duality
    
    func testOverlayHardLightDuality() {
        let c1 = SIMD3<Float>(0.35, 0.65, 0.15)
        let c2 = SIMD3<Float>(0.75, 0.25, 0.85)

        let overlay1 = BlendMode.overlay.evaluate(backdrop: c1, source: c2)
        let hardLight2 = BlendMode.hardLight.evaluate(backdrop: c2, source: c1)

        XCTAssertEqual(overlay1.x, hardLight2.x, accuracy: 0.001)
        XCTAssertEqual(overlay1.y, hardLight2.y, accuracy: 0.001)
        XCTAssertEqual(overlay1.z, hardLight2.z, accuracy: 0.001)
    }

    // MARK: - Extended Blend Modes
    
    func testExtendedBlendModes() {
        let cb = SIMD3<Float>(0.3, 0.7, 0.4)
        let cs = SIMD3<Float>(0.6, 0.2, 0.8)

        let darken = BlendMode.darken.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(darken.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(darken.y, 0.2, accuracy: 0.001)
        XCTAssertEqual(darken.z, 0.4, accuracy: 0.001)

        let lighten = BlendMode.lighten.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(lighten.x, 0.6, accuracy: 0.001)
        XCTAssertEqual(lighten.y, 0.7, accuracy: 0.001)
        XCTAssertEqual(lighten.z, 0.8, accuracy: 0.001)

        let linearDodge = BlendMode.linearDodge.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(linearDodge.x, 0.9, accuracy: 0.001)
        XCTAssertEqual(linearDodge.y, 0.9, accuracy: 0.001)
        XCTAssertEqual(linearDodge.z, 1.0, accuracy: 0.001) // Clamped to 1.0

        let linearBurn = BlendMode.linearBurn.evaluate(backdrop: cb, source: cs)
        XCTAssertEqual(linearBurn.x, 0.0, accuracy: 0.001) // 0.3 + 0.6 - 1.0 = -0.1 -> 0
        XCTAssertEqual(linearBurn.y, 0.0, accuracy: 0.001)
        XCTAssertEqual(linearBurn.z, 0.2, accuracy: 0.001) // 0.4 + 0.8 - 1.0 = 0.2
    }

    // MARK: - Semi-Transparent Alpha Compositing
    
    func testSemiTransparentCompositingVectors() {
        // Backdrop: Blue (0, 0, 1), alpha 0.5
        let backdrop = SIMD4<Float>(0.0, 0.0, 1.0, 0.5)
        // Source: Yellow (1, 1, 0), alpha 0.5, layer opacity 0.8 -> eff alpha 0.4
        let source = SIMD4<Float>(1.0, 1.0, 0.0, 0.5)
        let opacity: Float = 0.8

        // Expected alpha: 0.4 + 0.5 * (1 - 0.4) = 0.7000
        let normalResult = BlendMode.normal.composite(backdrop: backdrop, source: source, opacity: opacity)
        XCTAssertEqual(normalResult.w, 0.7000, accuracy: 0.005)
        XCTAssertEqual(normalResult.x, 0.5714, accuracy: 0.005)
        XCTAssertEqual(normalResult.y, 0.5714, accuracy: 0.005)
        XCTAssertEqual(normalResult.z, 0.4286, accuracy: 0.005)

        let multiplyResult = BlendMode.multiply.composite(backdrop: backdrop, source: source, opacity: opacity)
        XCTAssertEqual(multiplyResult.w, 0.7000, accuracy: 0.005)
        XCTAssertEqual(multiplyResult.x, 0.2857, accuracy: 0.005)
        XCTAssertEqual(multiplyResult.y, 0.2857, accuracy: 0.005)
        XCTAssertEqual(multiplyResult.z, 0.4286, accuracy: 0.005)

        let screenResult = BlendMode.screen.composite(backdrop: backdrop, source: source, opacity: opacity)
        XCTAssertEqual(screenResult.w, 0.7000, accuracy: 0.005)
        XCTAssertEqual(screenResult.x, 0.5714, accuracy: 0.005)
        XCTAssertEqual(screenResult.y, 0.5714, accuracy: 0.005)
        XCTAssertEqual(screenResult.z, 0.7143, accuracy: 0.005)

        let diffResult = BlendMode.difference.composite(backdrop: backdrop, source: source, opacity: opacity)
        XCTAssertEqual(diffResult.w, 0.7000, accuracy: 0.005)
        XCTAssertEqual(diffResult.x, 0.5714, accuracy: 0.005)
        XCTAssertEqual(diffResult.y, 0.5714, accuracy: 0.005)
        XCTAssertEqual(diffResult.z, 0.7143, accuracy: 0.005)
    }

    // MARK: - Lock Alpha Preservation
    
    func testLockAlphaPreservesBackdropAlpha() {
        let backdrop = SIMD4<Float>(0.0, 0.0, 1.0, 0.4)
        let source = SIMD4<Float>(1.0, 0.0, 0.0, 1.0)

        let lockedResult = BlendMode.normal.composite(backdrop: backdrop, source: source, opacity: 1.0, lockAlpha: true)
        XCTAssertEqual(lockedResult.w, 0.4, accuracy: 0.001, "Destination alpha must be strictly preserved")
        XCTAssertEqual(lockedResult.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(lockedResult.y, 0.0, accuracy: 0.001)
        XCTAssertEqual(lockedResult.z, 0.0, accuracy: 0.001)

        // Zero backdrop alpha remains completely transparent
        let transparentBackdrop = SIMD4<Float>(0.0, 0.0, 0.0, 0.0)
        let lockedTransparent = BlendMode.normal.composite(backdrop: transparentBackdrop, source: source, opacity: 1.0, lockAlpha: true)
        XCTAssertEqual(lockedTransparent.w, 0.0, accuracy: 0.001)
    }
}
