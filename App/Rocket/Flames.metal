#include "../Planets/PlanetCommon.h"

struct Flames {
    float2 centre;
    float2 bounds;
    float2 screen;
    float angle;
    float artPixel;
    float2 shipSize;
    float4 lengths;
    float4 nozzleY;
    float nozzleX;
    int nozzles;
    float width;
};

constant int flameColours = 5;
// Hottest first, at the nozzle.
constant float3 flameRamp[flameColours] = {
    float3(1.0, 0.92, 0.72), float3(1.0, 0.76, 0.2), float3(0.98, 0.48, 0.02), float3(0.94, 0.26, 0.04), float3(0.56, 0.15, 0.11),
};
constant float2 flameSamples[4] = {
    float2(-0.125, -0.375), float2(0.375, -0.125), float2(-0.375, 0.125), float2(0.125, 0.375),
};

// Blocky flames in the ship's own art pixels, tapering in steps towards a cooler tip.
static float4 flame_at(float2 art, constant Flames &f) {
    float behind = floor(f.nozzleX - art.x);
    for (int i = 0; i < f.nozzles; i++) {
        if (behind < 0.0 || behind >= f.lengths[i]) {
            continue;
        }
        float along = behind / f.lengths[i];
        float halfWidth = max(f.width * (along < 0.35 ? 1.0 : (along < 0.7 ? 0.67 : 0.34)), 1.0);
        if (abs(floor(art.y) + 0.5 - f.nozzleY[i]) < halfWidth) {
            return float4(flameRamp[int(along * float(flameColours))], 1.0);
        }
    }
    return float4(0.0);
}

fragment float4 flames_fragment(PlanetVertexOut in [[stage_in]], constant Flames &f [[buffer(0)]]) {
    float c = cos(-f.angle);
    float n = sin(-f.angle);
    float3 colour = float3(0.0);
    float alpha = 0.0;
    for (int i = 0; i < 4; i++) {
        float2 from = in.position.xy + flameSamples[i] - f.centre;
        float2 local = float2(from.x * c - from.y * n, from.x * n + from.y * c);
        float4 here = flame_at(local / f.artPixel + f.shipSize / 2.0, f);
        colour += here.rgb * here.a;
        alpha += here.a;
    }
    return alpha > 0.0 ? float4(colour / alpha, alpha / 4.0) : float4(0.0);
}
