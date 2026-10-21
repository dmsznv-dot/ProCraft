import Foundation
import CoreGraphics

/// A 3x3 Projective Homography matrix for 4-corner perspective transformations.
public struct Matrix3x3: Sendable {
    public var m00, m01, m02: CGFloat
    public var m10, m11, m12: CGFloat
    public var m20, m21, m22: CGFloat

    public init(
        m00: CGFloat = 1, m01: CGFloat = 0, m02: CGFloat = 0,
        m10: CGFloat = 0, m11: CGFloat = 1, m12: CGFloat = 0,
        m20: CGFloat = 0, m21: CGFloat = 0, m22: CGFloat = 1
    ) {
        self.m00 = m00; self.m01 = m01; self.m02 = m02
        self.m10 = m10; self.m11 = m11; self.m12 = m12
        self.m20 = m20; self.m21 = m21; self.m22 = m22
    }

    /// Transforms a 2D homogeneous point (x, y, 1) to (x'/w', y'/w').
    public func map(point: CGPoint) -> CGPoint? {
        let x = point.x
        let y = point.y
        let w = m20 * x + m21 * y + m22
        guard abs(w) > 1e-12 else { return nil }
        let nx = (m00 * x + m01 * y + m02) / w
        let ny = (m10 * x + m11 * y + m12) / w
        return CGPoint(x: nx, y: ny)
    }

    /// Computes matrix inverse via cofactor matrix / determinant.
    public func inverse() -> Matrix3x3? {
        let det = m00 * (m11 * m22 - m12 * m21) -
                  m01 * (m10 * m22 - m12 * m20) +
                  m02 * (m10 * m21 - m11 * m20)

        guard abs(det) > 1e-12 else { return nil }
        let invDet = 1.0 / det

        return Matrix3x3(
            m00: (m11 * m22 - m12 * m21) * invDet,
            m01: (m02 * m21 - m01 * m22) * invDet,
            m02: (m01 * m12 - m02 * m11) * invDet,
            m10: (m12 * m20 - m10 * m22) * invDet,
            m11: (m00 * m22 - m02 * m20) * invDet,
            m12: (m02 * m10 - m00 * m12) * invDet,
            m20: (m10 * m21 - m11 * m20) * invDet,
            m21: (m01 * m20 - m00 * m21) * invDet,
            m22: (m00 * m11 - m01 * m10) * invDet
        )
    }
}

public struct PerspectiveQuad: Sendable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public init(rect: CGRect) {
        self.topLeft = CGPoint(x: rect.minX, y: rect.minY)
        self.topRight = CGPoint(x: rect.maxX, y: rect.minY)
        self.bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        self.bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
    }

    public var bounds: CGRect {
        let xs = [topLeft.x, topRight.x, bottomRight.x, bottomLeft.x]
        let ys = [topLeft.y, topRight.y, bottomRight.y, bottomLeft.y]
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public final class PerspectiveHomography: @unchecked Sendable {
    public init() {}

    /// Solves the 3x3 Homography mapping unit square [0,1]^2 to arbitrary quadrilateral.
    public static func squareToQuad(_ q: PerspectiveQuad) -> Matrix3x3? {
        let x0 = q.topLeft.x, y0 = q.topLeft.y
        let x1 = q.topRight.x, y1 = q.topRight.y
        let x2 = q.bottomRight.x, y2 = q.bottomRight.y
        let x3 = q.bottomLeft.x, y3 = q.bottomLeft.y

        let dx1 = x1 - x2
        let dx2 = x3 - x2
        let dy1 = y1 - y2
        let dy2 = y3 - y2

        let sx = x0 - x1 + x2 - x3
        let sy = y0 - y1 + y2 - y3

        if abs(sx) < 1e-10 && abs(sy) < 1e-10 {
            // Affine mapping
            return Matrix3x3(
                m00: x1 - x0, m01: x2 - x1, m02: x0,
                m10: y1 - y0, m11: y2 - y1, m12: y0,
                m20: 0, m21: 0, m22: 1
            )
        }

        let det = dx1 * dy2 - dx2 * dy1
        guard abs(det) > 1e-12 else { return nil }

        let g = (sx * dy2 - sy * dx2) / det
        let h = (dx1 * sy - dy1 * sx) / det

        let a = x1 - x0 + g * x1
        let b = x3 - x0 + h * x3
        let c = x0
        let d = y1 - y0 + g * y1
        let e = y3 - y0 + h * y3
        let f = y0

        return Matrix3x3(
            m00: a, m01: b, m02: c,
            m10: d, m11: e, m12: f,
            m20: g, m21: h, m22: 1
        )
    }

    /// Solves the 3x3 Homography matrix mapping source quad to destination quad.
    public static func findHomography(from src: PerspectiveQuad, to dst: PerspectiveQuad) -> Matrix3x3? {
        guard let m1 = squareToQuad(src)?.inverse(),
              let m2 = squareToQuad(dst) else {
            return nil
        }

        // Multiply m2 * m1
        return Matrix3x3(
            m00: m2.m00 * m1.m00 + m2.m01 * m1.m10 + m2.m02 * m1.m20,
            m01: m2.m00 * m1.m01 + m2.m01 * m1.m11 + m2.m02 * m1.m21,
            m02: m2.m00 * m1.m02 + m2.m01 * m1.m12 + m2.m02 * m1.m22,

            m10: m2.m10 * m1.m00 + m2.m11 * m1.m10 + m2.m12 * m1.m20,
            m11: m2.m10 * m1.m01 + m2.m11 * m1.m11 + m2.m12 * m1.m21,
            m12: m2.m10 * m1.m02 + m2.m11 * m1.m12 + m2.m12 * m1.m22,

            m20: m2.m20 * m1.m00 + m2.m21 * m1.m10 + m2.m22 * m1.m20,
            m21: m2.m20 * m1.m01 + m2.m21 * m1.m11 + m2.m22 * m1.m21,
            m22: m2.m20 * m1.m02 + m2.m21 * m1.m12 + m2.m22 * m1.m22
        )
    }

    /// Distorts a source tile grid according to destination corner pins.
    public func distort(
        source: SparseTileGrid,
        sourceRect: CGRect,
        destinationQuad: PerspectiveQuad,
        canvasSize: CGSize,
        interpolation: InterpolationMode = .bilinear
    ) -> SparseTileGrid {
        let srcQuad = PerspectiveQuad(rect: sourceRect)
        guard let fwd = PerspectiveHomography.findHomography(from: srcQuad, to: destinationQuad),
              let inv = fwd.inverse() else {
            return source.clone()
        }

        let output = SparseTileGrid(canvasSize: canvasSize)
        let dstBounds = destinationQuad.bounds

        let minX = max(0, Int(dstBounds.minX.rounded(.down)))
        let maxX = min(Int(canvasSize.width) - 1, Int(dstBounds.maxX.rounded(.up)))
        let minY = max(0, Int(dstBounds.minY.rounded(.down)))
        let maxY = min(Int(canvasSize.height) - 1, Int(dstBounds.maxY.rounded(.up)))

        if minX > maxX || minY > maxY { return output }

        let transformEngine = TransformEngine()

        for y in minY...maxY {
            for x in minX...maxX {
                let dstPt = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                guard let srcPt = inv.map(point: dstPt) else { continue }

                // Check bounds in sourceRect
                if sourceRect.contains(srcPt) {
                    let color = transformEngine.sample(grid: source, point: srcPt, mode: interpolation)
                    if color.a > 0 {
                        output.setPixel(x: x, y: y, color: color)
                    }
                }
            }
        }

        return output
    }
}
