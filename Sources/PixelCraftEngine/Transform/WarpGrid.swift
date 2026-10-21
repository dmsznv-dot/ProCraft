import Foundation
import CoreGraphics

/// A 2D control point mesh for non-linear Bézier surface warping.
public struct WarpMesh: Sendable {
    public let rows: Int
    public let cols: Int
    public var points: [[CGPoint]]

    public init(rows: Int = 3, cols: Int = 3, rect: CGRect) {
        precondition(rows >= 2 && cols >= 2, "Grid must be at least 2x2")
        self.rows = rows
        self.cols = cols
        var grid = [[CGPoint]]()

        for r in 0..<rows {
            var rowPoints = [CGPoint]()
            let v = CGFloat(r) / CGFloat(rows - 1)
            let y = rect.minY + v * rect.height
            for c in 0..<cols {
                let u = CGFloat(c) / CGFloat(cols - 1)
                let x = rect.minX + u * rect.width
                rowPoints.append(CGPoint(x: x, y: y))
            }
            grid.append(rowPoints)
        }
        self.points = grid
    }

    /// Evaluates Bézier surface point using Bernstein polynomial blending.
    public func evaluate(u: CGFloat, v: CGFloat) -> CGPoint {
        let clampedU = max(0, min(1, u))
        let clampedV = max(0, min(1, v))

        let n = cols - 1
        let m = rows - 1

        var resultX: CGFloat = 0
        var resultY: CGFloat = 0

        for j in 0...m {
            let bV = bernstein(n: m, i: j, t: clampedV)
            for i in 0...n {
                let bU = bernstein(n: n, i: i, t: clampedU)
                let weight = bU * bV
                let pt = points[j][i]
                resultX += weight * pt.x
                resultY += weight * pt.y
            }
        }

        return CGPoint(x: resultX, y: resultY)
    }

    private func binomial(_ n: Int, _ k: Int) -> CGFloat {
        if k < 0 || k > n { return 0 }
        if k == 0 || k == n { return 1 }
        var c: CGFloat = 1
        for i in 1...k {
            c = c * CGFloat(n - (k - i)) / CGFloat(i)
        }
        return c
    }

    private func bernstein(n: Int, i: Int, t: CGFloat) -> CGFloat {
        let b = binomial(n, i)
        return b * pow(t, CGFloat(i)) * pow(1.0 - t, CGFloat(n - i))
    }

    public var bounds: CGRect {
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude

        for row in points {
            for pt in row {
                minX = min(minX, pt.x)
                maxX = max(maxX, pt.x)
                minY = min(minY, pt.y)
                maxY = max(maxY, pt.y)
            }
        }
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}

public final class WarpEngine: @unchecked Sendable {
    public init() {}

    /// Warps source tile grid using forward mesh mapping with inverse lookup table or bilinear grid inversion.
    public func warp(
        source: SparseTileGrid,
        sourceRect: CGRect,
        mesh: WarpMesh,
        canvasSize: CGSize,
        interpolation: InterpolationMode = .bilinear
    ) -> SparseTileGrid {
        let output = SparseTileGrid(canvasSize: canvasSize)
        let transformEngine = TransformEngine()

        // Generate discrete lookup grid from UV to mesh coordinate
        let lutResolution = 64
        var fwdLUT = [[CGPoint]](repeating: [CGPoint](repeating: .zero, count: lutResolution + 1), count: lutResolution + 1)

        for j in 0...lutResolution {
            let v = CGFloat(j) / CGFloat(lutResolution)
            for i in 0...lutResolution {
                let u = CGFloat(i) / CGFloat(lutResolution)
                fwdLUT[j][i] = mesh.evaluate(u: u, v: v)
            }
        }

        // Render each cell of the mesh as a small bilinearly mapped patch
        for j in 0..<lutResolution {
            for i in 0..<lutResolution {
                let p00 = fwdLUT[j][i]
                let p10 = fwdLUT[j][i + 1]
                let p11 = fwdLUT[j + 1][i + 1]
                let p01 = fwdLUT[j + 1][i]

                let u0 = CGFloat(i) / CGFloat(lutResolution)
                let u1 = CGFloat(i + 1) / CGFloat(lutResolution)
                let v0 = CGFloat(j) / CGFloat(lutResolution)
                let v1 = CGFloat(j + 1) / CGFloat(lutResolution)

                let cellQuad = PerspectiveQuad(topLeft: p00, topRight: p10, bottomRight: p11, bottomLeft: p01)
                guard let invHomography = PerspectiveHomography.findHomography(
                    from: PerspectiveQuad(rect: CGRect(x: 0, y: 0, width: 1, height: 1)),
                    to: cellQuad
                )?.inverse() else { continue }

                let cellBounds = cellQuad.bounds
                let minX = max(0, Int(cellBounds.minX.rounded(.down)))
                let maxX = min(Int(canvasSize.width) - 1, Int(cellBounds.maxX.rounded(.up)))
                let minY = max(0, Int(cellBounds.minY.rounded(.down)))
                let maxY = min(Int(canvasSize.height) - 1, Int(cellBounds.maxY.rounded(.up)))

                if minX > maxX || minY > maxY { continue }

                for y in minY...maxY {
                    for x in minX...maxX {
                        let dstPt = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                        guard let uv = invHomography.map(point: dstPt) else { continue }
                        if uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1 {
                            // Compute source coordinate
                            let srcU = u0 + uv.x * (u1 - u0)
                            let srcV = v0 + uv.y * (v1 - v0)
                            let srcX = sourceRect.minX + srcU * sourceRect.width
                            let srcY = sourceRect.minY + srcV * sourceRect.height

                            let color = transformEngine.sample(grid: source, point: CGPoint(x: srcX, y: srcY), mode: interpolation)
                            if color.a > 0 {
                                output.setPixel(x: x, y: y, color: color)
                            }
                        }
                    }
                }
            }
        }

        return output
    }
}
