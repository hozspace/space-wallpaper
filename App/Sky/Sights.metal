#include "../Planets/PlanetCommon.h"

struct Sight {
    float pixels;
    float radius;
    float seed;
    float tilt;
    float flatness;
    float time;
    float4 colours[4];
};

constant float galaxyTurnSeconds = 240.0;
constant float sightBayer[16] = {
    0, 8, 2, 10,
    12, 4, 14, 6,
    3, 11, 1, 9,
    15, 7, 13, 5,
};

// Nudges a value by an ordered dither, so steps between shades break into a pixel pattern.
static float dithered(float value, float2 cell, float strength) {
    int2 at = int2(glsl_mod(cell, float2(4.0)));
    return value + (sightBayer[at.y * 4 + at.x] / 16.0 - 0.5) * strength;
}

static float sight_hash(float2 cell, float seed) {
    return fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453 * (seed * 0.1 + 1.0));
}

// A bright body with a dithered edge and a soft ring of glow.
fragment float4 sun_fragment(PlanetVertexOut in [[stage_in]], constant Sight &p [[buffer(0)]]) {
    float2 cell = floor(in.uv * p.pixels);
    float d = length(cell + 0.5 - p.pixels * 0.5);
    float body = p.radius * 0.8;
    if (d < body * 0.55) { return p.colours[0]; }
    if (d < body * 0.85) { return dithered((d - body * 0.55) / (body * 0.3), cell, 0.5) < 0.5 ? p.colours[0] : p.colours[1]; }
    if (d < body) { return p.colours[1]; }
    float glow = dithered((d - body) / (body * 0.7), cell, 0.3);
    if (glow < 0.5) { return float4(p.colours[2].rgb, 0.45); }
    if (glow < 1.0) { return float4(p.colours[3].rgb, 0.18); }
    return float4(0.0);
}

// A spiral seen at an angle, slowly turning: a pale bulge, two arms winding out, and scattered bright knots.
fragment float4 galaxy_fragment(PlanetVertexOut in [[stage_in]], constant Sight &p [[buffer(0)]]) {
    float2 cell = floor(in.uv * p.pixels);
    float2 c = (cell + 0.5 - p.pixels * 0.5) / p.radius;
    c = float2(c.x * cos(p.tilt) + c.y * sin(p.tilt), -c.x * sin(p.tilt) + c.y * cos(p.tilt));
    c.y /= p.flatness;
    float r = length(c);
    if (r > 1.1) { return float4(0.0); }

    float direction = fmod(floor(p.seed * 10.0), 2.0) < 1.0 ? 1.0 : -1.0;
    float turned = direction * p.time * 2.0 * M_PI_F / galaxyTurnSeconds;
    // Nudged off zero: the very middle has no angle.
    float angle = atan2(c.y, c.x + 1e-4) - turned;
    // Knots and grain live on the disc, so they turn with it.
    float2 disc = float2(cos(angle), sin(angle)) * r * p.radius * 0.5;
    float arms = pow(0.5 + 0.5 * cos(2.0 * (angle - 3.0 * log(r + 0.08)) + p.seed), 2.0);
    float knots = step(0.93, sight_hash(floor(disc), p.seed)) * arms;
    float bulge = exp(-r * r * 50.0);
    float glow = exp(-r * 2.4) * (0.15 + 0.85 * arms + knots);
    float value = dithered(bulge * 1.1 + glow * 0.9 * (0.8 + 0.4 * sight_hash(floor(disc / 2.0), p.seed + 3.0)), cell, 0.12);

    if (value > 0.8) { return float4(p.colours[0].rgb, 0.7); }
    if (value > 0.45) { return float4(p.colours[1].rgb, 0.5); }
    if (value > 0.22) { return float4(p.colours[2].rgb, 0.4); }
    if (value > 0.1) { return float4(p.colours[3].rgb, 0.35); }
    return float4(0.0);
}
