#include "../Planets/PlanetCommon.h"

struct Star {
    float2 at;
    float4 colour;
    float size;
};

struct StarLayer {
    float2 view;
    float2 offset;
    float scale;
};

struct StarOut {
    float4 position [[position]];
    float size [[point_size]];
    float4 colour;
};

// Stars wrap around the view. Sizes are in screen pixels, so distant ones can be finer than the art.
vertex StarOut star_vertex(uint id [[vertex_id]], constant Star *stars [[buffer(0)]], constant StarLayer &layer [[buffer(1)]]) {
    Star star = stars[id];
    float2 at = glsl_mod(star.at * layer.view - layer.offset, layer.view);
    float2 centre = (floor(at * layer.scale) + star.size * 0.5) / (layer.view * layer.scale);
    return { float4(centre.x * 2.0 - 1.0, 1.0 - centre.y * 2.0, 0.0, 1.0), star.size, star.colour };
}

fragment float4 star_fragment(StarOut in [[stage_in]]) {
    return in.colour;
}
