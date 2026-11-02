#include "PlanetCommon.h"

// Covers the whole target, with uv's origin at the top left.
vertex PlanetVertexOut fullscreen_vertex(uint id [[vertex_id]]) {
    float2 uv = float2((id << 1) & 2, id & 2);
    return { float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0), uv };
}

// A quad at `rect` (x, y, width, height in clip space).
vertex PlanetVertexOut sprite_vertex(uint id [[vertex_id]], constant float4 &rect [[buffer(0)]]) {
    float2 uv = float2(id & 1, (id >> 1) & 1);
    return { float4(rect.x + uv.x * rect.z, rect.y - uv.y * rect.w, 0.0, 1.0), uv };
}

fragment float4 sprite_fragment(PlanetVertexOut in [[stage_in]], constant float &brightness [[buffer(0)]], texture2d<float> texture [[texture(0)]]) {
    constexpr sampler nearest(filter::nearest, address::clamp_to_edge);
    float4 colour = texture.sample(nearest, in.uv);
    return float4(colour.rgb * brightness, colour.a);
}

// A pixel with no matching neighbour takes the colour around it, so thin detail can't blink as loose specks.
// Diagonal neighbours count, which keeps dithering.
fragment float4 tidy_specks_fragment(PlanetVertexOut in [[stage_in]], texture2d<float, access::read> painted [[texture(0)]]) {
    int2 here = int2(in.position.xy);
    int2 last = int2(painted.get_width(), painted.get_height()) - 1;
    float4 colour = painted.read(uint2(here));
    if (colour.a == 0.0) { return colour; }
    float4 around[8];
    int count = 0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            if (x == 0 && y == 0) { continue; }
            float4 other = painted.read(uint2(clamp(here + int2(x, y), int2(0), last)));
            if (all(other == colour)) { return colour; }
            if (other.a > 0.0) { around[count++] = other; }
        }
    }
    float4 best = colour;
    int bestMatches = 0;
    for (int i = 0; i < count; i++) {
        int matches = 0;
        for (int j = 0; j < count; j++) {
            if (all(around[i] == around[j])) { matches++; }
        }
        if (matches > bestMatches) {
            best = around[i];
            bestMatches = matches;
        }
    }
    return best;
}
