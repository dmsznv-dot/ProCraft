import Foundation
import CoreGraphics

public struct LabColor: Sendable {
    public var L: Float // 0 to 100
    public var a: Float // -128 to 127
    public var b: Float // -128 to 127

    public init(L: Float, a: Float, b: Float) {
        self.L = L
        self.a = a
        self.b = b
    }

    /// Computes CIE76 Delta E color difference.
    public func deltaE(to other: LabColor) -> Float {
        let dL = L - other.L
        let da = a - other.a
        let db = b - other.b
        return sqrt(dL * dL + da * da + db * db)
    }

    /// Converts standard sRGB (0-255) to CIELAB under D65 standard illuminant.
    public static func fromRGB(r: UInt8, g: UInt8, b: UInt8) -> LabColor {
        // Linearize sRGB
        func sRGBtoLinear(_ val: UInt8) -> Float {
            let v = Float(val) / 255.0
            return (v > 0.04045) ? pow((v + 0.055) / 1.055, 2.4) : (v / 12.92)
        }

        let linR = sRGBtoLinear(r)
        let linG = sRGBtoLinear(g)
        let linB = sRGBtoLinear(b)

        // Convert RGB to XYZ (D65)
        let X = linR * 0.4124564 + linG * 0.3575761 + linB * 0.1804375
        let Y = linR * 0.2126729 + linG * 0.7151522 + linB * 0.0721750
        let Z = linR * 0.0193339 + linG * 0.1191920 + linB * 0.9503041

        // D65 reference white
        let Xn: Float = 0.95047
        let Yn: Float = 1.00000
        let Zn: Float = 1.08883

        func f(_ t: Float) -> Float {
            let delta: Float = 6.0 / 29.0
            return (t > delta * delta * delta) ? cbrt(t) : (t / (3.0 * delta * delta) + 4.0 / 29.0)
        }

        let fx = f(X / Xn)
        let fy = f(Y / Yn)
        let fz = f(Z / Zn)

        let L = 116.0 * fy - 16.0
        let a = 500.0 * (fx - fy)
        let bVal = 200.0 * (fy - fz)

        return LabColor(L: L, a: a, b: bVal)
    }
}

public struct ChromaKeyParams: Sendable {
    public var keyColor: (r: UInt8, g: UInt8, b: UInt8)
    public var tolerance: Float     // CIELAB Delta E threshold (e.g. 15.0 to 50.0)
    public var feather: Float       // Transition softness (e.g. 5.0 to 20.0)
    public var spillSuppression: Float // 0.0 (none) to 1.0 (full neutralization)

    public init(
        keyColor: (r: UInt8, g: UInt8, b: UInt8) = (0, 255, 0), // Classic green screen
        tolerance: Float = 25.0,
        feather: Float = 10.0,
        spillSuppression: Float = 0.75
    ) {
        self.keyColor = keyColor
        self.tolerance = tolerance
        self.feather = feather
        self.spillSuppression = spillSuppression
    }
}

public final class ChromaKeyFilter: @unchecked Sendable {
    public init() {}

    /// Removes the sampled key color from the grid using CIELAB Delta E with feathering and spill suppression.
    public func apply(grid: SparseTileGrid, params: ChromaKeyParams) -> SparseTileGrid {
        let output = grid.clone()
        let keyLab = LabColor.fromRGB(r: params.keyColor.r, g: params.keyColor.g, b: params.keyColor.b)

        let width = Int(grid.canvasSize.width)
        let height = Int(grid.canvasSize.height)

        let tol = params.tolerance
        let fth = max(0.1, params.feather)
        let spill = params.spillSuppression

        for y in 0..<height {
            for x in 0..<width {
                let pixel = grid.getPixel(x: x, y: y)
                guard pixel.a > 0 else { continue }

                let pixLab = LabColor.fromRGB(r: pixel.r, g: pixel.g, b: pixel.b)
                let dist = pixLab.deltaE(to: keyLab)

                var newAlpha = Float(pixel.a)

                if dist < tol {
                    // Fully within tolerance: remove completely
                    newAlpha = 0.0
                } else if dist < (tol + fth) {
                    // Feather transition zone
                    let t = (dist - tol) / fth
                    newAlpha = Float(pixel.a) * t
                }

                var r = pixel.r
                var g = pixel.g
                var b = pixel.b

                // Spill suppression: if green screen, suppress green excess; if blue, suppress blue
                if spill > 0 && newAlpha > 0 {
                    let isGreenKey = (params.keyColor.g > params.keyColor.r && params.keyColor.g > params.keyColor.b)
                    let isBlueKey = (params.keyColor.b > params.keyColor.r && params.keyColor.b > params.keyColor.g)

                    if isGreenKey {
                        let maxOther = max(r, b)
                        if g > maxOther {
                            let excess = Float(g - maxOther) * spill
                            g = UInt8(clamping: Int(round(Float(g) - excess)))
                        }
                    } else if isBlueKey {
                        let maxOther = max(r, g)
                        if b > maxOther {
                            let excess = Float(b - maxOther) * spill
                            b = UInt8(clamping: Int(round(Float(b) - excess)))
                        }
                    }
                }

                let finalA = UInt8(clamping: Int(round(newAlpha)))
                output.setPixel(x: x, y: y, color: (r, g, b, finalA))
            }
        }

        return output
    }
}
