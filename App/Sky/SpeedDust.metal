#include "../Planets/PlanetCommon.h"

struct Speck {
    float2 at;
    float brightness;
};

struct SpeedLayer {
    float2 view;
    float2 offset;
    float2 direction;
    float length;
    float thickness;
    float opacity;
};

struct SpeckOut {
    float4 position [[position]];
    float alpha;
};

// Thin lines along the direction of travel, wrapping around the view.
vertex SpeckOut speed_dust_vertex(uint id [[vertex_id]], uint instance [[instance_id]], constant Speck *specks [[buffer(0)]], constant SpeedLayer &layer [[buffer(1)]]) {
    Speck speck = specks[instance];
    float2 at = glsl_mod(speck.at * layer.view - layer.offset, layer.view);
    float2 corner = float2(id & 1, (id >> 1) & 1);
    float2 across = float2(-layer.direction.y, layer.direction.x);
    float2 point = at - layer.direction * corner.x * layer.length + across * (corner.y - 0.5) * layer.thickness;
    float2 clip = point / layer.view;
    return { float4(clip.x * 2.0 - 1.0, 1.0 - clip.y * 2.0, 0.0, 1.0), speck.brightness * layer.opacity * (1.0 - corner.x) };
}

fragment float4 speed_dust_fragment(SpeckOut in [[stage_in]]) {
    return float4(0.82, 0.86, 1.0, in.alpha);
}
