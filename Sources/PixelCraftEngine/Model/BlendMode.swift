import Foundation
import simd

/// The blending modes supported by PixelCraft Pro for compositing layers and brush strokes.
/// Includes 7 core standard modes (Normal, Multiply, Screen, Overlay, Soft Light, Hard Light, Difference)
/// plus 7 extended modes (Darken, Lighten, Color Dodge, Color Burn, Linear Dodge, Linear Burn, Exclusion).
public enum BlendMode: UInt32, CaseIterable, Identifiable, CustomStringConvertible, Sendable, Codable {
    case normal = 0
    case multiply = 1
    case screen = 2
    case overlay = 3
    case softLight = 4
    case hardLight = 5
    case difference = 6
    case darken = 7
    case lighten = 8
    case colorDodge = 9
    case colorBurn = 10
    case linearDodge = 11
    case linearBurn = 12
    case exclusion = 13
    
    public var id: UInt32 {
        rawValue
    }
    
    public var description: String {
        switch self {
        case .normal: return "Normal"
        case .multiply: return "Multiply"
        case .screen: return "Screen"
        case .overlay: return "Overlay"
        case .softLight: return "Soft Light"
        case .hardLight: return "Hard Light"
        case .difference: return "Difference"
        case .darken: return "Darken"
        case .lighten: return "Lighten"
        case .colorDodge: return "Color Dodge"
        case .colorBurn: return "Color Burn"
        case .linearDodge: return "Linear Dodge (Add)"
        case .linearBurn: return "Linear Burn"
        case .exclusion: return "Exclusion"
        }
    }
    
    // MARK: - Analytical CPU Blending Evaluation
    
    /// Evaluates the pure component blend function B(C_b, C_s) on normalized [0, 1] RGB triplets.
    public func evaluate(backdrop cb: SIMD3<Float>, source cs: SIMD3<Float>) -> SIMD3<Float> {
        switch self {
        case .normal:
            return cs
            
        case .multiply:
            return cb * cs
            
        case .screen:
            return 1.0 - (1.0 - cb) * (1.0 - cs)
            
        case .overlay:
            return SIMD3<Float>(
                cb.x <= 0.5 ? 2.0 * cb.x * cs.x : 1.0 - 2.0 * (1.0 - cb.x) * (1.0 - cs.x),
                cb.y <= 0.5 ? 2.0 * cb.y * cs.y : 1.0 - 2.0 * (1.0 - cb.y) * (1.0 - cs.y),
                cb.z <= 0.5 ? 2.0 * cb.z * cs.z : 1.0 - 2.0 * (1.0 - cb.z) * (1.0 - cs.z)
            )
            
        case .softLight:
            func softLightChannel(_ b: Float, _ s: Float) -> Float {
                if s <= 0.5 {
                    return b - (1.0 - 2.0 * s) * b * (1.0 - b)
                } else {
                    let d: Float = (b <= 0.25) ? ((16.0 * b - 12.0) * b + 4.0) * b : sqrt(b)
                    return b + (2.0 * s - 1.0) * (d - b)
                }
            }
            return SIMD3<Float>(
                softLightChannel(cb.x, cs.x),
                softLightChannel(cb.y, cs.y),
                softLightChannel(cb.z, cs.z)
            )
            
        case .hardLight:
            return SIMD3<Float>(
                cs.x <= 0.5 ? 2.0 * cb.x * cs.x : 1.0 - 2.0 * (1.0 - cb.x) * (1.0 - cs.x),
                cs.y <= 0.5 ? 2.0 * cb.y * cs.y : 1.0 - 2.0 * (1.0 - cb.y) * (1.0 - cs.y),
                cs.z <= 0.5 ? 2.0 * cb.z * cs.z : 1.0 - 2.0 * (1.0 - cb.z) * (1.0 - cs.z)
            )
            
        case .difference:
            return abs(cb - cs)
            
        case .darken:
            return min(cb, cs)
            
        case .lighten:
            return max(cb, cs)
            
        case .colorDodge:
            func dodgeChannel(_ b: Float, _ s: Float) -> Float {
                if b <= 0.0 { return 0.0 }
                if s >= 1.0 { return 1.0 }
                return min(1.0, b / (1.0 - s))
            }
            return SIMD3<Float>(
                dodgeChannel(cb.x, cs.x),
                dodgeChannel(cb.y, cs.y),
                dodgeChannel(cb.z, cs.z)
            )
            
        case .colorBurn:
            func burnChannel(_ b: Float, _ s: Float) -> Float {
                if b >= 1.0 { return 1.0 }
                if s <= 0.0 { return 0.0 }
                return 1.0 - min(1.0, (1.0 - b) / s)
            }
            return SIMD3<Float>(
                burnChannel(cb.x, cs.x),
                burnChannel(cb.y, cs.y),
                burnChannel(cb.z, cs.z)
            )
            
        case .linearDodge:
            return min(SIMD3<Float>(repeating: 1.0), cb + cs)
            
        case .linearBurn:
            return max(SIMD3<Float>(repeating: 0.0), cb + cs - 1.0)
            
        case .exclusion:
            return cb + cs - 2.0 * cb * cs
        }
    }
    
    /// Full Porter-Duff compositing with opacity and lock alpha support.
    /// Input: backdrop RGBA and source RGBA with straight colors in [0, 1].
    /// Output: resulting straight RGBA in [0, 1].
    public func composite(
        backdrop: SIMD4<Float>,
        source: SIMD4<Float>,
        opacity: Float = 1.0,
        lockAlpha: Bool = false
    ) -> SIMD4<Float> {
        let alphaB = max(0.0, min(1.0, backdrop.w))
        let alphaS = max(0.0, min(1.0, source.w * max(0.0, min(1.0, opacity))))
        
        let cb = SIMD3<Float>(backdrop.x, backdrop.y, backdrop.z)
        let cs = SIMD3<Float>(source.x, source.y, source.z)
        
        if lockAlpha {
            if alphaB <= 0.00001 {
                return SIMD4<Float>(0, 0, 0, 0)
            }
            let blended = evaluate(backdrop: cb, source: cs)
            let mixed = cb + (blended - cb) * alphaS
            return SIMD4<Float>(mixed.x, mixed.y, mixed.z, alphaB)
        } else {
            let alphaR = alphaS + alphaB * (1.0 - alphaS)
            if alphaR <= 0.00001 {
                return SIMD4<Float>(0, 0, 0, 0)
            }
            let blended = evaluate(backdrop: cb, source: cs)
            let csPrem = cs * alphaS
            let cbPrem = cb * alphaB
            let crPrem = csPrem * (1.0 - alphaB) + cbPrem * (1.0 - alphaS) + alphaS * alphaB * blended
            let cr = crPrem / alphaR
            return SIMD4<Float>(cr.x, cr.y, cr.z, alphaR)
        }
    }
}
