#pragma once
#include "PlanetCommon.h"

struct PlanetLayer {
    float pixels;
    float rotation;
    float2 light;
    float time;
    float seed;
    float size;
    float border1;
    float border2;
    float cutoff;
    float stretch;
    float ditherSize;
    int octaves;
    float4 colours[6];
};

constant float gentleNoise = 15.5453;
constant float sharpNoise = 43758.5453;

struct Noise {
    float2 period;
    float seed;
    float factor;
    int octaves;
};

// Surfaces wrap round a planet twice as wide as it is tall; clouds and craters just tile.
inline Noise wideNoise(constant PlanetLayer &p, float factor) {
    return { float2(2.0, 1.0) * round(p.size), p.seed, factor, p.octaves };
}

inline Noise squareNoise(constant PlanetLayer &p) {
    return { float2(round(p.size)), p.seed, gentleNoise, p.octaves };
}

inline float noise_rand(float2 coord, Noise n) {
    coord = glsl_mod(coord, n.period);
    return fract(sin(dot(coord, float2(12.9898, 78.233))) * n.factor * n.seed);
}

inline float noise_value(float2 coord, Noise n) {
    float2 i = floor(coord);
    float2 f = fract(coord);
    float a = noise_rand(i, n);
    float b = noise_rand(i + float2(1.0, 0.0), n);
    float c = noise_rand(i + float2(0.0, 1.0), n);
    float d = noise_rand(i + float2(1.0, 1.0), n);
    float2 cubic = f * f * (3.0 - 2.0 * f);
    return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

inline float noise_fbm(float2 coord, Noise n) {
    float value = 0.0;
    float scale = 0.5;
    for (int i = 0; i < n.octaves; i++) {
        value += noise_value(coord, n) * scale;
        coord *= 2.0;
        scale *= 0.5;
    }
    return value;
}

inline float2 sphere_map(float2 uv) {
    float2 centred = uv * 2.0 - 1.0;
    float z = sqrt(1.0 - dot(centred, centred));
    float2 sphere = centred / (z + 1.0);
    return sphere * 0.5 + 0.5;
}

inline bool dither_at(float2 pixelled, float2 real, float pixels) {
    return glsl_mod(pixelled.x + real.y, 2.0 / pixels) <= 1.0 / pixels;
}

inline float2 pixelled(float2 uv, float pixels) {
    return floor(uv * pixels) / pixels;
}
