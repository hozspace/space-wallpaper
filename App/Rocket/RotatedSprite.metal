#include "../Planets/PlanetCommon.h"

struct RotatedSprite {
    float2 centre;
    float2 size;
    float2 screen;
    float angle;
};

constant float2 sampleOffsets[4] = {
    float2(-0.125, -0.375), float2(0.375, -0.125), float2(-0.375, 0.125), float2(0.125, 0.375),
};

// A square big enough to hold the sprite at any angle. All in screen pixels.
vertex PlanetVertexOut rotated_sprite_vertex(uint id [[vertex_id]], constant RotatedSprite &s [[buffer(0)]]) {
    float2 corner = float2(id & 1, (id >> 1) & 1) * 2.0 - 1.0;
    float2 at = s.centre + corner * length(s.size) * 0.5;
    return { float4(at.x / s.screen.x * 2.0 - 1.0, 1.0 - at.y / s.screen.y * 2.0, 0.0, 1.0), float2(0.0) };
}

// Blends four samples per screen pixel, so turning and drifting stay smooth and detail doesn't shimmer.
fragment float4 rotated_sprite_fragment(PlanetVertexOut in [[stage_in]], constant RotatedSprite &s [[buffer(0)]], texture2d<float> texture [[texture(0)]]) {
    constexpr sampler nearest(filter::nearest, address::clamp_to_zero);
    float c = cos(-s.angle);
    float n = sin(-s.angle);
    float3 colour = float3(0.0);
    float alpha = 0.0;
    for (int i = 0; i < 4; i++) {
        float2 from = in.position.xy + sampleOffsets[i] - s.centre;
        float2 local = float2(from.x * c - from.y * n, from.x * n + from.y * c);
        float4 texel = texture.sample(nearest, local / s.size + 0.5);
        colour += texel.rgb * texel.a;
        alpha += texel.a;
    }
    return alpha > 0.0 ? float4(colour / alpha, alpha / 4.0) : float4(0.0);
}
