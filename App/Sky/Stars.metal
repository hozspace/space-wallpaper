#include "../Planets/PlanetCommon.h"

struct Star {
    float2 at;
    float4 colour;
    float phase;
};

struct StarLayer {
    float2 view;
    float2 offset;
    float scale;
    float span;
    float pixel;
    float time;
};

struct StarOut {
    float4 position [[position]];
    float size [[point_size]];
    float4 colour;
    float phase;
};

constant float twinkleStepSeconds = 0.3;
// How far a sparkle's arms reach on each step of a twinkle; mostly resting short.
constant int twinkle[12] = { 1, 1, 1, 1, 1, 1, 1, 2, 3, 3, 2, 1 };

// Stars wrap around the view and sit on whole star pixels.
vertex StarOut star_vertex(uint id [[vertex_id]], constant Star *stars [[buffer(0)]], constant StarLayer &layer [[buffer(1)]]) {
    Star star = stars[id];
    float2 at = floor(glsl_mod(star.at * layer.view - layer.offset, layer.view) / layer.pixel) * layer.pixel;
    float2 centre = (at + layer.pixel * 0.5) / layer.view;
    return { float4(centre.x * 2.0 - 1.0, 1.0 - centre.y * 2.0, 0.0, 1.0), layer.span * layer.pixel * layer.scale, star.colour, star.phase };
}

// A dot, a cross, or a sparkle whose arms grow and shrink in steps. The middle is near white and
// the arms take the star's own colour, dropping off fast.
fragment float4 star_fragment(StarOut in [[stage_in]], float2 spot [[point_coord]], constant StarLayer &layer [[buffer(0)]]) {
    int2 cell = int2(floor(spot * layer.span)) - int(layer.span - 1.0) / 2;
    int away = abs(cell.x) + abs(cell.y);
    float strength = max(in.colour.r, max(in.colour.g, in.colour.b));
    if (away == 0) { return layer.span > 1.0 ? float4(mix(in.colour.rgb, float3(strength), 0.6), 1.0) : in.colour; }
    if (cell.x != 0 && cell.y != 0) { return float4(0.0); }
    int reach = layer.span > 3.0 ? twinkle[int(layer.time / twinkleStepSeconds + in.phase) % 12] : 1;
    if (away > reach) { return float4(0.0); }
    return float4(in.colour.rgb * (away == 1 ? 1.0 : away == 2 ? 0.7 : 0.45), away == 1 ? 0.75 : away == 2 ? 0.45 : 0.25);
}
