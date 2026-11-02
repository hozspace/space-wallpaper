#include "../Planets/PlanetCommon.h"

struct DustBake {
    float2 cells;
    float seed;
    float cover;
};

struct Cloud {
    float2 centre;
    float radius;
    float fade;
    float4 tintA;
    float4 tintB;
};

struct DustScroll {
    float2 viewOverTexture;
    float2 offset;
    float2 view;
    float opacity;
    int cloudCount;
    float2 churn;
    float2 secondOffset;
    float2 gridShift;
    Cloud clouds[3];
};

constant int dustOctaves = 4;
constant float softness = 0.28;
constant float churnScale = 0.5;
// Art pixels per cloud pixel, matching the planets, and how many shades a cloud steps through.
constant float cloudPixel = 3.0;
constant float cloudShades = 3.0;
constant float bayer[16] = {
    0, 8, 2, 10,
    12, 4, 14, 6,
    3, 11, 1, 9,
    15, 7, 13, 5,
};

static float dust_rand(float2 cell, float2 period, float seed) {
    cell = glsl_mod(cell, period);
    return fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453 * (seed * 0.01 + 1.0));
}

static float dust_noise(float2 p, float2 period, float seed) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 cubic = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(dust_rand(i, period, seed), dust_rand(i + float2(1, 0), period, seed), cubic.x),
        mix(dust_rand(i + float2(0, 1), period, seed), dust_rand(i + float2(1, 1), period, seed), cubic.x),
        cubic.y
    );
}

// Each octave doubles its period too, so the result tiles in both directions.
static float dust_fbm(float2 p, float2 period, float seed) {
    float value = 0.0;
    float scale = 0.5;
    for (int i = 0; i < dustOctaves; i++) {
        value += dust_noise(p, period, seed + float(i)) * scale;
        p *= 2.0;
        period *= 2.0;
        scale *= 0.5;
    }
    return value;
}

// Baked once: red is how thick the cloud is, green blends between its two tints.
fragment float4 dust_bake_fragment(PlanetVertexOut in [[stage_in]], constant DustBake &p [[buffer(0)]]) {
    float2 point = in.uv * p.cells;
    float2 warp = float2(dust_fbm(point, p.cells, p.seed + 20.0), dust_fbm(point + 5.2, p.cells, p.seed + 40.0));
    float value = dust_fbm(point + warp * 1.5, p.cells, p.seed);
    float thickness = smoothstep(p.cover, p.cover + softness, value);
    float blend = dust_fbm(point + 11.0, p.cells, p.seed + 60.0);
    return float4(thickness, smoothstep(0.3, 0.7, blend), 0.0, 1.0);
}

// Thick only inside a cloud's reach, thinning towards its edge, in coarse pixels and a few dithered shades.
fragment float4 dust_scroll_fragment(PlanetVertexOut in [[stage_in]], constant DustScroll &p [[buffer(0)]], texture2d<float> texture [[texture(0)]]) {
    constexpr sampler soft(filter::linear, address::repeat);
    // The pixel grid travels with the cloud, so its edges don't crawl as it passes.
    float2 cell = floor((in.uv * p.view + p.gridShift) / cloudPixel);
    float2 art = (cell + 0.5) * cloudPixel - p.gridShift;
    float reach = 0.0;
    float3 tintA = float3(0.0);
    float3 tintB = float3(0.0);
    float totalWeight = 0.0;
    for (int i = 0; i < p.cloudCount; i++) {
        float here = saturate((p.clouds[i].radius - distance(art, p.clouds[i].centre)) / p.clouds[i].fade);
        // Weighted rather than winner-takes-all, so overlapping clouds blend instead of meeting at a hard line.
        float influence = smoothstep(0.0, 1.0, here);
        float weight = influence * influence;
        reach = max(reach, influence);
        tintA += p.clouds[i].tintA.rgb * weight;
        tintB += p.clouds[i].tintB.rgb * weight;
        totalWeight += weight;
    }
    if (totalWeight <= 0.0) {
        return float4(0.0);
    }
    tintA /= totalWeight;
    tintB /= totalWeight;
    float2 onTexture = art / p.view * p.viewOverTexture;
    float4 baked = texture.sample(soft, onTexture + p.offset + p.churn);
    // A second, larger copy sliding the other way, so the cloud's shape slowly changes as well as its place.
    float4 second = texture.sample(soft, onTexture * churnScale + p.secondOffset);
    baked.r *= 0.35 + second.r * 1.3;
    int2 at = int2(glsl_mod(cell, float2(4.0)));
    float dither = bayer[at.y * 4 + at.x] / 16.0;
    // Each pixel steps up at its own point, so a cloud thickens pixel by pixel rather than in sudden bands.
    float shade = min(floor(baked.r * reach * cloudShades + dither), cloudShades) / cloudShades;
    float blend = step(0.5, baked.g + (dither - 0.5) * 0.3);
    return float4(mix(tintA, tintB, blend), shade * p.opacity);
}
