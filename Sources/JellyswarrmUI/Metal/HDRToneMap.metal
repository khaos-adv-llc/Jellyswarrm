#include <metal_stdlib>
using namespace metal;

// Reinhard MaxRGB tonemapping — Burke et al. 2020
float3 tonemap_maxrgb(float3 x, float maxInput, float maxOutput) {
    if (maxInput <= maxOutput) { return x; }
    float a = maxOutput / (maxInput * maxInput);
    float b = 1.0f / maxOutput;
    float colorMax = max(x.r, max(x.g, x.b));
    return x * (1.0f + a * colorMax) / (1.0f + b * colorMax);
}

// PQ EOTF — maps nonlinear PQ signal to absolute nits
float3 eotf_pq(float3 x) {
    float c1 = 107.0f / 128.0f;
    float c2 = 2413.0f / 128.0f;
    float c3 = 2392.0f / 128.0f;
    float m1 = 1305.0f / 8192.0f;
    float m2 = 2523.0f / 32.0f;
    float3 p = pow(x, 1.0f / m2);
    float3 L = 10000.0f * pow(max(p - c1, 0.0f) / (c2 - c3 * p), 1.0f / m1);
    return L;
}

// HDR10 (PQ) tonemap — output in linear Rec.2020
float3 tonemap_pq(float3 x, float hdrHeadroom) {
    const float referenceWhite = 203.0f;
    const float peakWhite = 10000.0f;
    return tonemap_maxrgb(eotf_pq(x) / referenceWhite, peakWhite / referenceWhite, hdrHeadroom);
}

// HLG inverse OETF
float inv_oetf_hlg_scalar(float v) {
    float a = 0.17883277f;
    float b = 1.0f - 4.0f * a;
    float c = 0.5f - a * log(4.0f * a);
    if (v <= 0.5f) { return pow(v, 2.0f) / 3.0f; }
    else { return (exp((v - c) / a) + b) / 12.0f; }
}

float3 inv_oetf_hlg(float3 v) {
    return float3(inv_oetf_hlg_scalar(v.r), inv_oetf_hlg_scalar(v.g), inv_oetf_hlg_scalar(v.b));
}

// HLG OOTF
float3 ootf_hlg(float3 Y, float Lw) {
    float gamma = 1.2f + 0.42f * log(Lw / 1000.0f) / log(10.0f);
    return pow(Y, gamma - 1.0f) * Y;
}

// HLG tonemap — output in linear Rec.2020
float3 tonemap_hlg(float3 x, float edrHeadroom) {
    const float referenceWhite = 100.0f;
    const float peakWhite = 1000.0f;
    float3 v = ootf_hlg(inv_oetf_hlg(x), peakWhite);
    v *= peakWhite / referenceWhite;
    v = tonemap_maxrgb(v, peakWhite / referenceWhite, edrHeadroom);
    return v;
}

// Uniforms
struct ToneMappingUniforms {
    float edrHeadroom;
    int   hdrMode; // 0=SDR, 1=HDR10/PQ, 2=HLG
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Full-screen quad vertex shader
vertex VertexOut hdr_vertex(uint vid [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1, -1), float2( 1, -1),
        float2(-1,  1), float2( 1,  1)
    };
    const float2 texCoords[4] = {
        float2(0, 1), float2(1, 1),
        float2(0, 0), float2(1, 0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.texCoord = texCoords[vid];
    return out;
}

// Fragment shader — applies tonemapping based on hdrMode
fragment float4 hdr_fragment(VertexOut in [[stage_in]],
                              texture2d<float> videoTexture [[texture(0)]],
                              constant ToneMappingUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear);
    float3 color = videoTexture.sample(s, in.texCoord).rgb;

    switch (uniforms.hdrMode) {
        case 1: color = tonemap_pq(color, uniforms.edrHeadroom); break;
        case 2: color = tonemap_hlg(color, uniforms.edrHeadroom); break;
        default: break; // SDR passthrough
    }
    return float4(color, 1.0);
}
