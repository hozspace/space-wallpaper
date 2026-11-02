#include "../Planets/PlanetCommon.h"

struct ShootingStar {
    float2 centre;
    float2 size;
    float2 screen;
    float angle;
    float2 head;
    float2 direction;
    float length;
    float pixel;
    float fade;
};

// A streak on the pixel grid, so it steps like hand-drawn pixel art: a white head, a tail fading behind.
fragment float4 shooting_star_fragment(PlanetVertexOut in [[stage_in]], constant ShootingStar &s [[buffer(0)]]) {
    float2 cell = (floor(in.position.xy / s.pixel) + 0.5) * s.pixel;
    float2 back = s.head - cell;
    float along = dot(back, s.direction);
    float across = abs(back.x * s.direction.y - back.y * s.direction.x);
    if (along < -s.pixel * 0.5 || along > s.length || across > s.pixel * 0.5) { return float4(0.0); }
    float share = along / s.length;
    float alpha = share < 0.15 ? 1.0 : share < 0.45 ? 0.6 : share < 0.75 ? 0.32 : 0.14;
    float3 colour = share < 0.15 ? float3(1.0) : float3(0.75, 0.86, 1.0);
    return float4(colour, alpha * s.fade);
}
