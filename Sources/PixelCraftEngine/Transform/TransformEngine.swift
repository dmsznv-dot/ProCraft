import Foundation
import CoreGraphics

public enum InterpolationMode: String, CaseIterable, Sendable {
    case nearestNeighbor
    case bilinear
    case bicubic
    case lanczos
}

public struct TransformState: Sendable {
    public var translation: CGPoint
    public var scale: CGSize
    public var rotation: CGFloat // in radians
    public var skew: CGPoint    // in radians (x, y)
    public var flipHorizontal: Bool
    public var flipVertical: Bool
    public var pivot: CGPoint

    public init(
        translation: CGPoint = .zero,
        scale: CGSize = CGSize(width: 1.0, height: 1.0),
        rotation: CGFloat = 0.0,
        skew: CGPoint = .zero,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        pivot: CGPoint = .zero
    ) {
        self.translation = translation
        self.scale = scale
        self.rotation = rotation
        self.skew = skew
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.pivot = pivot
    }

    /// Computes the forward 2D affine transformation matrix.
    public func forwardMatrix() -> CGAffineTransform {
        var t = CGAffineTransform(translationX: pivot.x + translation.x, y: pivot.y + translation.y)
        t = t.rotated(by: rotation)
        let sx = (flipHorizontal ? -1.0 : 1.0) * scale.width
        let sy = (flipVertical ? -1.0 : 1.0) * scale.height
        t = t.scaledBy(x: sx, y: sy)
        if skew.x != 0 || skew.y != 0 {
            // Apply shear
            let shear = CGAffineTransform(a: 1, b: tan(skew.y), c: tan(skew.x), d: 1, tx: 0, ty: 0)
            t = shear.concatenating(t)
        }
        t = t.translatedBy(x: -pivot.x, y: -pivot.y)
        return t
    }

    /// Computes the inverse 2D affine transformation matrix for sampling.
    public func inverseMatrix() -> CGAffineTransform? {
        let fwd = forwardMatrix()
        guard abs(fwd.a * fwd.d - fwd.b * fwd.c) > 1e-12 else { return nil }
        return fwd.inverted()
    }
}

public final class TransformEngine: @unchecked Sendable {
    public init() {}

    /// Transforms a source tile grid and writes the output into a new or target tile grid.
    public func transform(
        source: SparseTileGrid,
        state: TransformState,
        canvasSize: CGSize,
        interpolation: InterpolationMode = .bilinear
    ) -> SparseTileGrid {
        guard let invMatrix = state.inverseMatrix() else {
            return source.clone()
        }

        let output = SparseTileGrid(canvasSize: canvasSize)
        let contentBounds = source.contentBounds
        guard !contentBounds.isNull && !contentBounds.isEmpty else {
            return output
        }

        // Compute transformed bounding box of content
        let fwd = state.forwardMatrix()
        let corners = [
            CGPoint(x: contentBounds.minX, y: contentBounds.minY).applying(fwd),
            CGPoint(x: contentBounds.maxX, y: contentBounds.minY).applying(fwd),
            CGPoint(x: contentBounds.minX, y: contentBounds.maxY).applying(fwd),
            CGPoint(x: contentBounds.maxX, y: contentBounds.maxY).applying(fwd)
        ]

        var minX = corners.map { $0.x }.min() ?? 0
        var maxX = corners.map { $0.x }.max() ?? canvasSize.width
        var minY = corners.map { $0.y }.min() ?? 0
        var maxY = corners.map { $0.y }.max() ?? canvasSize.height

        minX = max(0, floor(minX))
        maxX = min(canvasSize.width - 1, ceil(maxX))
        minY = max(0, floor(minY))
        maxY = min(canvasSize.height - 1, ceil(maxY))

        if minX > maxX || minY > maxY {
            return output
        }

        let startTileX = Int(minX) / SparseTileGrid.tileSize
        let endTileX = Int(maxX) / SparseTileGrid.tileSize
        let startTileY = Int(minY) / SparseTileGrid.tileSize
        let endTileY = Int(maxY) / SparseTileGrid.tileSize

        let tileSize = SparseTileGrid.tileSize

        for ty in startTileY...endTileY {
            for tx in startTileX...endTileX {
                let tileMinX = tx * tileSize
                let tileMinY = ty * tileSize
                var tileHasContent = false

                // Process tile pixels
                for py in 0..<tileSize {
                    let dstY = CGFloat(tileMinY + py)
                    if dstY > maxY || dstY < minY { continue }

                    for px in 0..<tileSize {
                        let dstX = CGFloat(tileMinX + px)
                        if dstX > maxX || dstX < minX { continue }

                        let srcPoint = CGPoint(x: dstX + 0.5, y: dstY + 0.5).applying(invMatrix)
                        let color = sample(grid: source, point: srcPoint, mode: interpolation)

                        if color.a > 0 {
                            output.setPixel(x: Int(dstX), y: Int(dstY), color: color)
                            tileHasContent = true
                        }
                    }
                }
                _ = tileHasContent
            }
        }

        return output
    }

    /// Samples a color from the sparse tile grid with the specified interpolation filter.
    public func sample(
        grid: SparseTileGrid,
        point: CGPoint,
        mode: InterpolationMode
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let x = point.x - 0.5
        let y = point.y - 0.5

        let width = grid.canvasSize.width
        let height = grid.canvasSize.height

        guard x >= -1 && x < width && y >= -1 && y < height else {
            return (0, 0, 0, 0)
        }

        switch mode {
        case .nearestNeighbor:
            let ix = Int(round(x))
            let iy = Int(round(y))
            guard ix >= 0 && ix < Int(width) && iy >= 0 && iy < Int(height) else {
                return (0, 0, 0, 0)
            }
            return grid.getPixel(x: ix, y: iy)

        case .bilinear:
            let x0 = Int(floor(x))
            let y0 = Int(floor(y))
            let x1 = x0 + 1
            let y1 = y0 + 1

            let fx = Float(x - CGFloat(x0))
            let fy = Float(y - CGFloat(y0))

            let p00 = getSafePixel(grid: grid, x: x0, y: y0, width: Int(width), height: Int(height))
            let p10 = getSafePixel(grid: grid, x: x1, y: y0, width: Int(width), height: Int(height))
            let p01 = getSafePixel(grid: grid, x: x0, y: y1, width: Int(width), height: Int(height))
            let p11 = getSafePixel(grid: grid, x: x1, y: y1, width: Int(width), height: Int(height))

            let w00 = (1.0 - fx) * (1.0 - fy)
            let w10 = fx * (1.0 - fy)
            let w01 = (1.0 - fx) * fy
            let w11 = fx * fy

            let r = UInt8(clamping: Int(round(Float(p00.r) * w00 + Float(p10.r) * w10 + Float(p01.r) * w01 + Float(p11.r) * w11)))
            let g = UInt8(clamping: Int(round(Float(p00.g) * w00 + Float(p10.g) * w10 + Float(p01.g) * w01 + Float(p11.g) * w11)))
            let b = UInt8(clamping: Int(round(Float(p00.b) * w00 + Float(p10.b) * w10 + Float(p01.b) * w01 + Float(p11.b) * w11)))
            let a = UInt8(clamping: Int(round(Float(p00.a) * w00 + Float(p10.a) * w10 + Float(p01.a) * w01 + Float(p11.a) * w11)))
            return (r, g, b, a)

        case .bicubic, .lanczos:
            return sampleBicubic(grid: grid, x: x, y: y, width: Int(width), height: Int(height))
        }
    }

    private func getSafePixel(grid: SparseTileGrid, x: Int, y: Int, width: Int, height: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        if x < 0 || x >= width || y < 0 || y >= height {
            return (0, 0, 0, 0)
        }
        return grid.getPixel(x: x, y: y)
    }

    // Catmull-Rom cubic spline weight (a = -0.5)
    private func cubicWeight(_ t: Float) -> Float {
        let a: Float = -0.5
        let at = abs(t)
        if at <= 1.0 {
            return (a + 2.0) * at * at * at - (a + 3.0) * at * at + 1.0
        } else if at < 2.0 {
            return a * at * at * at - 5.0 * a * at * at + 8.0 * a * at - 4.0 * a
        }
        return 0.0
    }

    private func sampleBicubic(
        grid: SparseTileGrid,
        x: CGFloat,
        y: CGFloat,
        width: Int,
        height: Int
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))

        var rAcc: Float = 0
        var gAcc: Float = 0
        var bAcc: Float = 0
        var aAcc: Float = 0
        var totalWeight: Float = 0

        for j in -1...2 {
            let py = y0 + j
            let wy = cubicWeight(Float(CGFloat(py) - y))

            for i in -1...2 {
                let px = x0 + i
                let wx = cubicWeight(Float(CGFloat(px) - x))
                let w = wx * wy

                let p = getSafePixel(grid: grid, x: px, y: py, width: width, height: height)
                rAcc += Float(p.r) * w
                gAcc += Float(p.g) * w
                bAcc += Float(p.b) * w
                aAcc += Float(p.a) * w
                totalWeight += w
            }
        }

        if abs(totalWeight) > 1e-6 {
            rAcc /= totalWeight
            gAcc /= totalWeight
            bAcc /= totalWeight
            aAcc /= totalWeight
        }

        return (
            UInt8(clamping: Int(round(max(0, min(255, rAcc))))),
            UInt8(clamping: Int(round(max(0, min(255, gAcc))))),
            UInt8(clamping: Int(round(max(0, min(255, bAcc))))),
            UInt8(clamping: Int(round(max(0, min(255, aAcc)))))
        )
    }
}
