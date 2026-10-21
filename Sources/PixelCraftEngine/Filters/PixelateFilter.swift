import Foundation
import CoreGraphics

public enum PixelateGridShape: String, CaseIterable, Sendable {
    case square
    case hexagonal
    case circular
}

public enum PixelateSamplingMode: String, CaseIterable, Sendable {
    case center
    case average
}

public final class PixelateFilter: @unchecked Sendable {
    public init() {}

    /// Applies the pixelate effect to the given tile grid.
    public func apply(
        grid: SparseTileGrid,
        blockSize: Int,
        shape: PixelateGridShape = .square,
        sampling: PixelateSamplingMode = .average,
        bounds: CGRect? = nil
    ) -> SparseTileGrid {
        let clampedBlockSize = max(2, min(512, blockSize))
        let output = grid.clone()

        let targetBounds = bounds ?? CGRect(origin: .zero, size: grid.canvasSize)
        let minX = max(0, Int(targetBounds.minX))
        let maxX = min(Int(grid.canvasSize.width) - 1, Int(targetBounds.maxX))
        let minY = max(0, Int(targetBounds.minY))
        let maxY = min(Int(grid.canvasSize.height) - 1, Int(targetBounds.maxY))

        if minX > maxX || minY > maxY { return output }

        switch shape {
        case .square:
            applySquare(grid: grid, output: output, blockSize: clampedBlockSize, minX: minX, maxX: maxX, minY: minY, maxY: maxY, sampling: sampling)
        case .hexagonal:
            applyHexagonal(grid: grid, output: output, blockSize: clampedBlockSize, minX: minX, maxX: maxX, minY: minY, maxY: maxY, sampling: sampling)
        case .circular:
            applyCircular(grid: grid, output: output, blockSize: clampedBlockSize, minX: minX, maxX: maxX, minY: minY, maxY: maxY, sampling: sampling)
        }

        return output
    }

    private func applySquare(
        grid: SparseTileGrid,
        output: SparseTileGrid,
        blockSize: Int,
        minX: Int, maxX: Int,
        minY: Int, maxY: Int,
        sampling: PixelateSamplingMode
    ) {
        for by in stride(from: minY, through: maxY, by: blockSize) {
            for bx in stride(from: minX, through: maxX, by: blockSize) {
                let cellMaxX = min(maxX, bx + blockSize - 1)
                let cellMaxY = min(maxY, by + blockSize - 1)

                let color: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
                if sampling == .center {
                    let cx = (bx + cellMaxX) / 2
                    let cy = (by + cellMaxY) / 2
                    color = grid.getPixel(x: cx, y: cy)
                } else {
                    color = computeAverage(grid: grid, minX: bx, maxX: cellMaxX, minY: by, maxY: cellMaxY)
                }

                if color.a == 0 {
                    for y in by...cellMaxY {
                        for x in bx...cellMaxX {
                            output.setPixel(x: x, y: y, color: (0, 0, 0, 0))
                        }
                    }
                } else {
                    for y in by...cellMaxY {
                        for x in bx...cellMaxX {
                            output.setPixel(x: x, y: y, color: color)
                        }
                    }
                }
            }
        }
    }

    private func applyHexagonal(
        grid: SparseTileGrid,
        output: SparseTileGrid,
        blockSize: Int,
        minX: Int, maxX: Int,
        minY: Int, maxY: Int,
        sampling: PixelateSamplingMode
    ) {
        let r = CGFloat(blockSize) / 2.0
        let h = r * sqrt(3.0)
        let stepX = 1.5 * r
        let stepY = h

        for y in minY...maxY {
            for x in minX...maxX {
                let pt = CGPoint(x: CGFloat(x), y: CGFloat(y))
                // Find nearest hex center
                let hexCenter = findNearestHexCenter(point: pt, radius: r, stepX: stepX, stepY: stepY)

                let color: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
                if sampling == .center {
                    color = grid.getPixel(x: Int(hexCenter.x), y: Int(hexCenter.y))
                } else {
                    let hx = Int(hexCenter.x)
                    let hy = Int(hexCenter.y)
                    let half = blockSize / 2
                    color = computeAverage(grid: grid, minX: max(minX, hx - half), maxX: min(maxX, hx + half), minY: max(minY, hy - half), maxY: min(maxY, hy + half))
                }
                output.setPixel(x: x, y: y, color: color)
            }
        }
    }

    private func findNearestHexCenter(point: CGPoint, radius: CGFloat, stepX: CGFloat, stepY: CGFloat) -> CGPoint {
        let approxCol = Int(round(point.x / stepX))
        let colOffset = (approxCol % 2 != 0) ? (stepY / 2.0) : 0.0
        let approxRow = Int(round((point.y - colOffset) / stepY))

        var bestCenter = CGPoint(x: CGFloat(approxCol) * stepX, y: CGFloat(approxRow) * stepY + colOffset)
        var bestDist = hypot(point.x - bestCenter.x, point.y - bestCenter.y)

        for dc in -1...1 {
            for dr in -1...1 {
                let c = approxCol + dc
                let offset = (abs(c) % 2 != 0) ? (stepY / 2.0) : 0.0
                let r = approxRow + dr
                let cand = CGPoint(x: CGFloat(c) * stepX, y: CGFloat(r) * stepY + offset)
                let d = hypot(point.x - cand.x, point.y - cand.y)
                if d < bestDist {
                    bestDist = d
                    bestCenter = cand
                }
            }
        }
        return bestCenter
    }

    private func applyCircular(
        grid: SparseTileGrid,
        output: SparseTileGrid,
        blockSize: Int,
        minX: Int, maxX: Int,
        minY: Int, maxY: Int,
        sampling: PixelateSamplingMode
    ) {
        let radius = CGFloat(blockSize) / 2.0
        let radiusSq = radius * radius

        for by in stride(from: minY, through: maxY, by: blockSize) {
            for bx in stride(from: minX, through: maxX, by: blockSize) {
                let cellMaxX = min(maxX, bx + blockSize - 1)
                let cellMaxY = min(maxY, by + blockSize - 1)

                let cx = CGFloat(bx + cellMaxX) / 2.0
                let cy = CGFloat(by + cellMaxY) / 2.0

                let color: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
                if sampling == .center {
                    color = grid.getPixel(x: Int(cx), y: Int(cy))
                } else {
                    color = computeAverage(grid: grid, minX: bx, maxX: cellMaxX, minY: by, maxY: cellMaxY)
                }

                for y in by...cellMaxY {
                    for x in bx...cellMaxX {
                        let dx = CGFloat(x) - cx
                        let dy = CGFloat(y) - cy
                        if dx * dx + dy * dy <= radiusSq {
                            output.setPixel(x: x, y: y, color: color)
                        } else {
                            // Border background outside circle dots
                            output.setPixel(x: x, y: y, color: (0, 0, 0, 0))
                        }
                    }
                }
            }
        }
    }

    private func computeAverage(grid: SparseTileGrid, minX: Int, maxX: Int, minY: Int, maxY: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var rSum = 0
        var gSum = 0
        var bSum = 0
        var aSum = 0
        var count = 0

        for y in minY...maxY {
            for x in minX...maxX {
                let p = grid.getPixel(x: x, y: y)
                if p.a > 0 {
                    rSum += Int(p.r)
                    gSum += Int(p.g)
                    bSum += Int(p.b)
                    aSum += Int(p.a)
                    count += 1
                }
            }
        }

        guard count > 0 else { return (0, 0, 0, 0) }
        return (
            UInt8(rSum / count),
            UInt8(gSum / count),
            UInt8(bSum / count),
            UInt8(aSum / count)
        )
    }
}
