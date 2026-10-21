#include <metal_stdlib>
using namespace metal;

enum BlendModeIndex : uint {
    Normal = 0,
    Multiply = 1,
    Screen = 2,
    Overlay = 3,
    SoftLight = 4,
    HardLight = 5,
    Difference = 6,
    Darken = 7,
    Lighten = 8,
    ColorDodge = 9,
    ColorBurn = 10,
    LinearDodge = 11,
    LinearBurn = 12,
    Exclusion = 13
};

struct TileVertexUniforms {
    float2 tileOffset;     // (tx * 512, ty * 512)
    float2 quadSize;       // (effW, effH)
    float2 maxUV;          // (maxU, maxV)
    float2 viewportSize;   // (V_w, V_h)
    float2 pan;            // (pan_x, pan_y)
    float zoom;
};

struct TileFragmentUniforms {
    float opacity;
    uint blendMode;
    uint lockAlpha;
};

struct LayerUniforms {
    uint blendMode;
    float opacity;
    bool lockAlpha;
    bool isLinear;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Core Blend Math Helpers

inline float3 blend_normal(float3 cb, float3 cs) { 
    return cs; 
}

inline float3 blend_multiply(float3 cb, float3 cs) { 
    return cb * cs; 
}

inline float3 blend_screen(float3 cb, float3 cs) { 
    return 1.0f - (1.0f - cb) * (1.0f - cs); 
}

inline float3 blend_overlay(float3 cb, float3 cs) {
    return select(2.0f * cb * cs, 1.0f - 2.0f * (1.0f - cb) * (1.0f - cs), cb > 0.5f);
}

inline float3 blend_hard_light(float3 cb, float3 cs) {
    return select(2.0f * cb * cs, 1.0f - 2.0f * (1.0f - cb) * (1.0f - cs), cs > 0.5f);
}

inline float3 blend_soft_light(float3 cb, float3 cs) {
    float3 d = select(sqrt(cb), ((16.0f * cb - 12.0f) * cb + 4.0f) * cb, cb <= 0.25f);
    return select(cb - (1.0f - 2.0f * cs) * cb * (1.0f - cb),
                  cb + (2.0f * cs - 1.0f) * (d - cb),
                  cs > 0.5f);
}

inline float3 blend_difference(float3 cb, float3 cs) { 
    return abs(cb - cs); 
}

inline float3 blend_darken(float3 cb, float3 cs) { 
    return min(cb, cs); 
}

inline float3 blend_lighten(float3 cb, float3 cs) { 
    return max(cb, cs); 
}

inline float3 blend_color_dodge(float3 cb, float3 cs) {
    float3 res;
    for (int i = 0; i < 3; ++i) {
        if (cb[i] <= 0.0f) res[i] = 0.0f;
        else if (cs[i] >= 1.0f) res[i] = 1.0f;
        else res[i] = min(1.0f, cb[i] / (1.0f - cs[i]));
    }
    return res;
}

inline float3 blend_color_burn(float3 cb, float3 cs) {
    float3 res;
    for (int i = 0; i < 3; ++i) {
        if (cb[i] >= 1.0f) res[i] = 1.0f;
        else if (cs[i] <= 0.0f) res[i] = 0.0f;
        else res[i] = 1.0f - min(1.0f, (1.0f - cb[i]) / cs[i]);
    }
    return res;
}

inline float3 blend_linear_dodge(float3 cb, float3 cs) { 
    return min(1.0f, cb + cs); 
}

inline float3 blend_linear_burn(float3 cb, float3 cs) { 
    return max(0.0f, cb + cs - 1.0f); 
}

inline float3 blend_exclusion(float3 cb, float3 cs) { 
    return cb + cs - 2.0f * cb * cs; 
}

inline float3 evaluate_blend(uint mode, float3 cb, float3 cs) {
    switch (mode) {
        case Normal: return blend_normal(cb, cs);
        case Multiply: return blend_multiply(cb, cs);
        case Screen: return blend_screen(cb, cs);
        case Overlay: return blend_overlay(cb, cs);
        case SoftLight: return blend_soft_light(cb, cs);
        case HardLight: return blend_hard_light(cb, cs);
        case Difference: return blend_difference(cb, cs);
        case Darken: return blend_darken(cb, cs);
        case Lighten: return blend_lighten(cb, cs);
        case ColorDodge: return blend_color_dodge(cb, cs);
        case ColorBurn: return blend_color_burn(cb, cs);
        case LinearDodge: return blend_linear_dodge(cb, cs);
        case LinearBurn: return blend_linear_burn(cb, cs);
        case Exclusion: return blend_exclusion(cb, cs);
        default: return blend_normal(cb, cs);
    }
}

// MARK: - Vertex Shader
vertex VertexOut canvas_tile_vertex(uint vertexID [[vertex_id]],
                                    constant TileVertexUniforms &u [[buffer(0)]]) {
    // Quad vertices: 0: (0,0), 1: (1,0), 2: (0,1), 3: (1,1)
    float2 unitPos = float2(float(vertexID & 1), float(vertexID >> 1));
    float2 canvasPos = u.tileOffset + unitPos * u.quadSize;
    float2 viewportPos = canvasPos * u.zoom + u.pan;

    float2 ndc;
    ndc.x = (2.0f * viewportPos.x / u.viewportSize.x) - 1.0f;
    ndc.y = 1.0f - (2.0f * viewportPos.y / u.viewportSize.y);

    VertexOut out;
    out.position = float4(ndc, 0.0f, 1.0f);
    out.texCoord = unitPos * u.maxUV;
    return out;
}

// MARK: - Checkerboard Fragment Shader
fragment float4 checkerboard_fragment(VertexOut in [[stage_in]]) {
    uint2 screenPos = uint2(in.position.xy);
    bool check = ((screenPos.x / 16) ^ (screenPos.y / 16)) & 1;
    float c = check ? 0.90f : 0.75f;
    return float4(c, c, c, 1.0f);
}

// MARK: - Canvas Tile Fragment Shader (Programmable Blending via [[color(0)]])
fragment float4 canvas_tile_fragment(VertexOut in [[stage_in]],
                                     float4 dstColor [[color(0)]],
                                     texture2d<float> tileTexture [[texture(0)]],
                                     constant TileFragmentUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 srcSample = tileTexture.sample(s, in.texCoord);

    float srcA = srcSample.a * u.opacity;
    if (srcA <= 0.0001f) {
        return dstColor;
    }

    float dstA = dstColor.a;
    float3 blended = evaluate_blend(u.blendMode, dstColor.rgb, srcSample.rgb);

    if (u.lockAlpha != 0) {
        if (dstA <= 0.00001f) {
            return float4(0.0f);
        }
        float3 outRGB = mix(dstColor.rgb, blended, srcA);
        return float4(outRGB, dstA);
    } else {
        float outA = srcA + dstA * (1.0f - srcA);
        if (outA <= 0.0001f) {
            return float4(0.0f);
        }

        float3 outRGB = (srcA * (1.0f - dstA) * srcSample.rgb +
                         srcA * dstA * blended +
                         (1.0f - srcA) * dstA * dstColor.rgb) / outA;

        return float4(outRGB, outA);
    }
}

// MARK: - Offscreen / Tile Compute Compositing Kernel
kernel void composite_layers_kernel(
    texture2d<float, access::read_write> backdrop [[texture(0)]],
    texture2d<float, access::read> source [[texture(1)]],
    constant LayerUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= backdrop.get_width() || gid.y >= backdrop.get_height()) {
        return;
    }

    float4 c_b = backdrop.read(gid);
    float4 c_s = source.read(gid);

    float alpha_b = c_b.a;
    float alpha_s = c_s.a * uniforms.opacity;

    if (uniforms.lockAlpha) {
        if (alpha_b <= 0.00001f) {
            backdrop.write(float4(0.0f, 0.0f, 0.0f, 0.0f), gid);
            return;
        }
        float3 b = evaluate_blend(uniforms.blendMode, c_b.rgb, c_s.rgb);
        float3 cr = mix(c_b.rgb, b, alpha_s);
        backdrop.write(float4(cr, alpha_b), gid);
    } else {
        float alpha_r = alpha_s + alpha_b * (1.0f - alpha_s);
        if (alpha_r <= 0.00001f) {
            backdrop.write(float4(0.0f, 0.0f, 0.0f, 0.0f), gid);
            return;
        }

        float3 cs_prem = c_s.rgb * alpha_s;
        float3 cb_prem = c_b.rgb * alpha_b;
        float3 b = evaluate_blend(uniforms.blendMode, c_b.rgb, c_s.rgb);
        float3 cr_prem = cs_prem * (1.0f - alpha_b) + cb_prem * (1.0f - alpha_s) + alpha_s * alpha_b * b;
        float3 cr = cr_prem / alpha_r;

        backdrop.write(float4(cr, alpha_r), gid);
    }
}
