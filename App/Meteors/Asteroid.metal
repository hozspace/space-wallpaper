#include "../Planets/PlanetNoise.h"

// Ported from PixelPlanets' Asteroids shader.
constant float asteroidNoisePeriod = 100000.0;

static float rock_circle(float2 uv, Noise n) {
    float row = floor(uv.y);
    uv.x += row * 0.31;
    float2 f = fract(uv);
    float h = noise_rand(float2(floor(uv.x), row), n);
    float m = length(f - 0.25 - h * 0.5);
    float r = h * 0.25;
    return smoothstep(r - 0.1 * r, r, m);
}

static float rock_crater(float2 uv, float size, Noise n) {
    float c = 1.0;
    for (int i = 0; i < 2; i++) {
        c *= rock_circle(uv * size + (float(i + 1) + 10.0), n);
    }
    return 1.0 - c;
}

fragment float4 asteroid_fragment(PlanetVertexOut in [[stage_in]], constant PlanetLayer &p [[buffer(0)]]) {
    Noise n = { float2(asteroidNoisePeriod), p.seed, gentleNoise, p.octaves };
    float2 uv = pixelled(in.uv, p.pixels);
    bool dith = dither_at(uv, in.uv, p.pixels);
    float d = distance(uv, float2(0.5));
    uv = planet_rotate(uv, p.rotation);

    float shape = noise_fbm(uv * p.size, n);
    float shadowed = noise_fbm(uv * p.size + (planet_rotate(p.light, p.rotation) - 0.5) * 0.5, n);
    float edge = step(0.2, shape - d);
    float shadowEdge = step(0.2, shadowed - d);
    float relative = (shadowEdge + shadowed) - (edge + shape);

    float crater = rock_crater(uv, p.size, n);
    float craterShadow = rock_crater(uv + (p.light - 0.5) * 0.03, p.size, n);

    float4 colour = p.colours[1];
    if (relative < -0.06 || (relative < -0.04 && dith)) { colour = p.colours[0]; }
    if (relative > 0.05 || (relative > 0.03 && dith)) { colour = p.colours[2]; }
    if (crater > 0.4) { colour = p.colours[1]; }
    if (craterShadow < crater) { colour = p.colours[2]; }
    return float4(colour.rgb, edge * colour.a);
}
