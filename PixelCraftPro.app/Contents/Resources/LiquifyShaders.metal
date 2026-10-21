#include <metal_stdlib>
using namespace metal;

struct LiquifyParams {
    float2 brushCenter;
    float2 brushDelta;
    float brushRadius;
    float brushPressure;
    float brushDensity;
    float brushRate;
    uint toolMode; // 0: Push, 1: Reconstruct, 2: TwirlCW, 3: TwirlCCW, 4: Pinch, 5: Bloat
    uint width;
    uint height;
};

kernel void liquifyDeformKernel(
    device float2* displacementMap [[buffer(0)]],
    constant LiquifyParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) return;

    uint index = gid.y * params.width + gid.x;
    float2 pixelPos = float2(gid.x, gid.y);
    float2 d = pixelPos - params.brushCenter;
    float dist = length(d);

    if (dist >= params.brushRadius) return;

    // Smooth Gaussian/Hermite brush falloff
    float normDist = dist / params.brushRadius;
    float falloff = (1.0 - normDist * normDist);
    falloff = falloff * falloff * params.brushPressure;

    float2 currentDisp = displacementMap[index];

    switch (params.toolMode) {
        case 0: { // Push / Warp
            currentDisp += params.brushDelta * falloff;
            break;
        }
        case 1: { // Reconstruct
            currentDisp *= max(0.0, 1.0 - falloff * 0.5);
            break;
        }
        case 2: { // Twirl CW
            float angle = falloff * 0.5;
            float cosA = cos(angle);
            float sinA = sin(angle);
            float2 rotated = float2(d.x * cosA - d.y * sinA, d.x * sinA + d.y * cosA);
            currentDisp += (rotated - d);
            break;
        }
        case 3: { // Twirl CCW
            float angle = -falloff * 0.5;
            float cosA = cos(angle);
            float sinA = sin(angle);
            float2 rotated = float2(d.x * cosA - d.y * sinA, d.x * sinA + d.y * cosA);
            currentDisp += (rotated - d);
            break;
        }
        case 4: { // Pinch
            float2 pinchVec = -normalize(d + 1e-4) * (params.brushRadius - dist) * falloff * 0.5;
            currentDisp += pinchVec;
            break;
        }
        case 5: { // Bloat
            float2 bloatVec = normalize(d + 1e-4) * (params.brushRadius - dist) * falloff * 0.5;
            currentDisp += bloatVec;
            break;
        }
    }

    displacementMap[index] = currentDisp;
}
