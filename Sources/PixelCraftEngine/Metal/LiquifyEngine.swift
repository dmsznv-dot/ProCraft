import Foundation
import CoreGraphics
import Metal

public enum LiquifyToolMode: UInt32, CaseIterable, Sendable {
    case push = 0
    case reconstruct = 1
    case twirlCW = 2
    case twirlCCW = 3
    case pinch = 4
    case bloat = 5
}

public struct LiquifyBrushParams: Sendable {
    public var size: CGFloat       // radius * 2
    public var pressure: CGFloat   // 0.0 to 1.0
    public var density: CGFloat    // 0.0 to 1.0
    public var rate: CGFloat       // 0.0 to 1.0

    public init(size: CGFloat = 64.0, pressure: CGFloat = 0.5, density: CGFloat = 0.5, rate: CGFloat = 0.5) {
        self.size = size
        self.pressure = pressure
        self.density = density
        self.rate = rate
    }
}

public final class LiquifyEngine: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public private(set) var displacementMap: [SIMD2<Float>]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.displacementMap = [SIMD2<Float>](repeating: .zero, count: width * height)
    }

    /// Resets the displacement map to zero displacement.
    public func reset() {
        displacementMap = [SIMD2<Float>](repeating: .zero, count: width * height)
    }

    /// Applies a stroke to the displacement map.
    public func applyBrush(
        mode: LiquifyToolMode,
        center: CGPoint,
        delta: CGPoint = .zero,
        params: LiquifyBrushParams
    ) {
        let radius = params.size / 2.0
        let radiusSq = radius * radius
        let pressure = Float(params.pressure)

        let minX = max(0, Int(center.x - radius))
        let maxX = min(width - 1, Int(center.x + radius))
        let minY = max(0, Int(center.y - radius))
        let maxY = min(height - 1, Int(center.y + radius))

        if minX > maxX || minY > maxY { return }

        let cx = Float(center.x)
        let cy = Float(center.y)
        let dxDelta = Float(delta.x)
        let dyDelta = Float(delta.y)

        for y in minY...maxY {
            let dy = Float(y) - cy
            for x in minX...maxX {
                let dx = Float(x) - cx
                let distSq = dx * dx + dy * dy
                if distSq >= Float(radiusSq) { continue }

                let dist = sqrt(distSq)
                let normDist = dist / Float(radius)
                var falloff = 1.0 - normDist * normDist
                falloff = falloff * falloff * pressure

                let idx = y * width + x
                var disp = displacementMap[idx]

                switch mode {
                case .push:
                    disp.x += dxDelta * falloff
                    disp.y += dyDelta * falloff

                case .reconstruct:
                    disp *= max(0.0, 1.0 - falloff * 0.5)

                case .twirlCW:
                    let angle = falloff * 0.5
                    let cosA = cos(angle)
                    let sinA = sin(angle)
                    let rx = dx * cosA - dy * sinA
                    let ry = dx * sinA + dy * cosA
                    disp.x += (rx - dx)
                    disp.y += (ry - dy)

                case .twirlCCW:
                    let angle = -falloff * 0.5
                    let cosA = cos(angle)
                    let sinA = sin(angle)
                    let rx = dx * cosA - dy * sinA
                    let ry = dx * sinA + dy * cosA
                    disp.x += (rx - dx)
                    disp.y += (ry - dy)

                case .pinch:
                    let len = dist + 1e-4
                    let pinch = (Float(radius) - dist) * falloff * 0.5
                    disp.x -= (dx / len) * pinch
                    disp.y -= (dy / len) * pinch

                case .bloat:
                    let len = dist + 1e-4
                    let bloat = (Float(radius) - dist) * falloff * 0.5
                    disp.x += (dx / len) * bloat
                    disp.y += (dy / len) * bloat
                }

                displacementMap[idx] = disp
            }
        }
    }

    /// Renders only `rect` (canvas pixels) of the deformed image from `source` into `target`.
    /// Used for interactive brushing: only the area under the brush is recomputed per mouse event.
    public func renderRegion(source: SparseTileGrid, into target: SparseTileGrid, rect: CGRect) {
        let minX = max(0, Int(floor(rect.minX)))
        let maxX = min(width - 1, Int(ceil(rect.maxX)))
        let minY = max(0, Int(floor(rect.minY)))
        let maxY = min(height - 1, Int(ceil(rect.maxY)))
        guard minX <= maxX, minY <= maxY else { return }

        let transformEngine = TransformEngine()
        for y in minY...maxY {
            for x in minX...maxX {
                let disp = displacementMap[y * width + x]
                if abs(disp.x) < 0.001 && abs(disp.y) < 0.001 {
                    target.writePixel(x: x, y: y, color: source.readPixel(x: x, y: y))
                    continue
                }
                let srcPt = CGPoint(x: CGFloat(Float(x) - disp.x) + 0.5, y: CGFloat(Float(y) - disp.y) + 0.5)
                let c = transformEngine.sample(grid: source, point: srcPt, mode: .bilinear)
                target.writePixel(x: x, y: y, color: SIMD4<UInt8>(c.r, c.g, c.b, c.a))
            }
        }
    }

    /// Renders the deformed result into a new SparseTileGrid.
    public func render(source: SparseTileGrid) -> SparseTileGrid {
        let output = SparseTileGrid(canvasSize: CGSize(width: width, height: height))
        let transformEngine = TransformEngine()

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let disp = displacementMap[idx]

                // Inverse displacement mapping: sample pixel from (x - disp.x, y - disp.y)
                let srcPt = CGPoint(x: CGFloat(Float(x) - disp.x) + 0.5, y: CGFloat(Float(y) - disp.y) + 0.5)
                let color = transformEngine.sample(grid: source, point: srcPt, mode: .bilinear)
                if color.a > 0 {
                    output.setPixel(x: x, y: y, color: color)
                }
            }
        }

        return output
    }
}
