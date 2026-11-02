// Ported from PixelPlanets' GasLayers and Ring shaders (MIT, see licences/).
#include "PlanetCommon.h"

struct RingedLayer {
    float pixels;
    float rotation;
    float2 light;
    float time;
    float seed;
    float4 colours[3];
    float4 darkColours[3];
};

constant float gasSize = 10.107;
constant int gasOctaves = 3;
constant float gasBands = 0.892;
constant int turbulenceSteps = 10;
constant float ringSize = 15.0;
constant int ringOctaves = 4;
constant float ringWidth = 0.127;
constant float ringPerspective = 6.0;
constant float ringScaleToPlanet = 6.0;

static float ringed_rand(float2 coord, float size, float seed) {
    coord = glsl_mod(coord, float2(2.0, 1.0) * round(size));
    return fract(sin(dot(coord, float2(12.9898, 78.233))) * 15.5453 * seed);
}

static float ringed_noise(float2 coord, float size, float seed) {
    float2 i = floor(coord);
    float2 f = fract(coord);
    float a = ringed_rand(i, size, seed);
    float b = ringed_rand(i + float2(1.0, 0.0), size, seed);
    float c = ringed_rand(i + float2(0.0, 1.0), size, seed);
    float d = ringed_rand(i + float2(1.0, 1.0), size, seed);
    float2 cubic = f * f * (3.0 - 2.0 * f);
    return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

static float ringed_fbm(float2 coord, float size, int octaves, float seed) {
    float value = 0.0;
    float scale = 0.5;
    for (int i = 0; i < octaves; i++) {
        value += ringed_noise(coord, size, seed) * scale;
        coord *= 2.0;
        scale *= 0.5;
    }
    return value;
}

static float gas_circle(float2 uv, float seed) {
    float uvY = floor(uv.y);
    uv.x += uvY * 0.31;
    float2 f = fract(uv);
    float h = ringed_rand(float2(floor(uv.x), uvY), gasSize, seed);
    float m = length(f - 0.25 - (h * 0.5));
    float r = h * 0.25;
    return smoothstep(0.0, r, m * 0.75);
}

static float gas_turbulence(float2 uv, float time, float seed) {
    float total = 0.0;
    for (int i = 0; i < turbulenceSteps; i++) {
        total += gas_circle((uv * gasSize * 0.3) + (float(i + 1) + 10.0) + float2(time, 0.0), seed);
    }
    return total;
}

static float2 gas_spherify(float2 uv) {
    float2 centred = uv * 2.0 - 1.0;
    float z = sqrt(1.0 - dot(centred, centred));
    float2 sphere = centred / (z + 1.0);
    return sphere * 0.5 + 0.5;
}

fragment float4 ringed_gas_fragment(PlanetVertexOut in [[stage_in]], constant RingedLayer &p [[buffer(0)]]) {
    float2 uv = floor(in.uv * p.pixels) / p.pixels;
    float lightD = distance(uv, p.light);
    bool dith = glsl_mod(uv.x + in.uv.y, 2.0 / p.pixels) <= 1.0 / p.pixels;
    float a = step(length(uv - float2(0.5)), 0.49999);

    uv = planet_rotate(uv, p.rotation);
    uv = gas_spherify(uv);

    float band = ringed_fbm(float2(0.0, uv.y * gasSize * gasBands), gasSize, gasOctaves, p.seed);
    float turb = gas_turbulence(uv, p.time, p.seed);
    float fbm1 = ringed_fbm(uv * gasSize, gasSize, gasOctaves, p.seed);
    float fbm2 = ringed_fbm(uv * float2(1.0, 2.0) * gasSize + fbm1 + float2(-p.time, 0.0) + turb, gasSize, gasOctaves, p.seed);

    fbm2 *= pow(band, 2.0) * 7.0;
    float light = fbm2 + lightD * 1.8;
    fbm2 += lightD - 0.3;
    fbm2 = smoothstep(-0.2, 4.0 - fbm2, light);
    if (dith) {
        fbm2 *= 1.1;
    }

    float posterized = floor(fbm2 * 4.0) / 2.0;
    float4 colour = fbm2 < 0.625
        ? p.colours[int(posterized * 2.0)]
        : p.darkColours[int((posterized - 1.0) * 2.0)];
    return float4(colour.rgb, a * colour.a);
}

fragment float4 ringed_ring_fragment(PlanetVertexOut in [[stage_in]], constant RingedLayer &p [[buffer(0)]]) {
    float2 uv = floor(in.uv * p.pixels) / p.pixels;
    float lightD = distance(uv, p.light);
    uv = planet_rotate(uv, p.rotation);

    float2 centre = (uv - float2(0.0, 0.5)) * float2(1.0, ringPerspective);
    float centreD = distance(centre, float2(0.5, 0.0));

    float ring = smoothstep(0.5 - ringWidth * 2.0, 0.5 - ringWidth, centreD);
    ring *= smoothstep(centreD - ringWidth, centreD, 0.4);

    // The ring passes behind the planet in the upper half.
    if (uv.y < 0.5) {
        ring *= step(1.0 / ringScaleToPlanet, distance(uv, float2(0.5)));
    }

    centre = planet_rotate(centre + float2(0.0, 0.5), p.time);
    ring *= ringed_fbm(centre * ringSize, ringSize, ringOctaves, p.seed);

    float posterized = floor((ring + pow(lightD, 2.0) * 2.0) * 4.0) / 4.0;
    posterized = min(posterized, 2.0);
    float4 colour = posterized <= 1.0
        ? p.colours[int(posterized * 2.0)]
        : p.darkColours[int((posterized - 1.0) * 2.0)];
    return float4(colour.rgb, step(0.28, ring) * colour.a);
}
