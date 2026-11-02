#pragma once
#include <metal_stdlib>
using namespace metal;

struct PlanetVertexOut {
    float4 position [[position]];
    float2 uv;
};

// GLSL's mod floors; Metal's fmod truncates, which breaks the noise on negative values.
template <typename T>
inline T glsl_mod(T x, T y) {
    return x - y * floor(x / y);
}

inline float planet_rand(float2 coord, float size, float seed) {
    coord = glsl_mod(coord, float2(round(size)));
    return fract(sin(dot(coord, float2(12.9898, 78.233))) * 15.5453 * seed);
}

inline float2 planet_rotate(float2 coord, float angle) {
    coord -= 0.5;
    coord = coord * float2x2(float2(cos(angle), -sin(angle)), float2(sin(angle), cos(angle)));
    return coord + 0.5;
}
