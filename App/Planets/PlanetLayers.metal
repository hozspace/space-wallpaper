// Ported from PixelPlanets (MIT, see licences/). Each planet type stacks some of these layers.
#include "PlanetNoise.h"

// Bare ground (NoAtmosphere): light with a noisy edge.
fragment float4 ground_fragment(PlanetVertexOut in [[stage_in]], constant PlanetLayer &p [[buffer(0)]]) {
    Noise n = squareNoise(p);
    float2 uv = pixelled(in.uv, p.pixels);
    float dLight = distance(uv, p.light);
    float a = step(distance(uv, float2(0.5)), 0.49999);
    bool dith = dither_at(uv, in.uv, p.pixels);
    uv = planet_rotate(uv, p.rotation);

    float fbm1 = noise_fbm(uv, n);
    dLight += noise_fbm(uv * p.size + fbm1 + float2(p.time, 0.0), n) * 0.3;

    float border = (1.0 / p.pixels) * p.ditherSize;
    float4 colour = p.colours[0];
    if (dLight > p.border1) {
        colour = p.colours[1];
        if (dLight < p.border1 + border && dith) { colour = p.colours[0]; }
    }
    if (dLight > p.border2) {
        colour = p.colours[2];
        if (dLight < p.border2 + border && dith) { colour = p.colours[1]; }
    }
    return float4(colour.rgb, a * colour.a);
}

static float crater_circle(float2 uv, Noise n) {
    float uvY = floor(uv.y);
    uv.x += uvY * 0.31;
    float2 f = fract(uv);
    float h = noise_rand(float2(floor(uv.x), uvY), n);
    float m = length(f - 0.25 - (h * 0.5));
    float r = h * 0.25;
    return smoothstep(r - 0.10 * r, r, m);
}

static float crater(float2 uv, constant PlanetLayer &p, Noise n) {
    float c = 1.0;
    for (int i = 0; i < 2; i++) {
        c *= crater_circle((uv * p.size) + (float(i + 1) + 10.0) + float2(p.time, 0.0), n);
    }
    return 1.0 - c;
}

fragment float4 craters_fragment(PlanetVertexOut in [[stage_in]], constant PlanetLayer &p [[buffer(0)]]) {
    Noise n = squareNoise(p);
    float2 uv = pixelled(in.uv, p.pixels);
    float dCircle = distance(uv, float2(0.5));
    float dLight = distance(uv, p.light);
    float a = step(dCircle, 0.49999);
    uv = sphere_map(planet_rotate(uv, p.rotation));

    float c1 = crater(uv, p, n);
    float c2 = crater(uv + (p.light - 0.5) * 0.03, p, n);
    float4 colour = p.colours[0];
    a *= step(0.5, c1);
    if (c2 < c1 - (0.5 - dLight) * 2.0) { colour = p.colours[1]; }
    if (dLight > p.border1) { colour = p.colours[1]; }
    a *= step(dCircle, 0.5);
    return float4(colour.rgb, a * colour.a);
}

// Sea or ice under other layers (PlanetUnder).
fragment float4 under_fragment(PlanetVertexOut in [[stage_in]], constant PlanetLayer &p [[buffer(0)]]) {
    Noise n = wideNoise(p, gentleNoise);
    float2 uv = pixelled(in.uv, p.pixels);
    bool dith = dither_at(uv, in.uv, p.pixels);
    float dLight = distance(uv, p.light);
    float a = step(distance(uv, float2(0.5)), 0.49999);
    uv = planet_rotate(sphere_map(uv), p.rotation);
    dLight += noise_fbm(uv * p.size + float2(p.time, 0.0), n) * 0.3;

    float border = (1.0 / p.pixels) * p.ditherSize;
    float4 colour = p.colours[0];
    if (dLight > p.border1) {
        colour = p.colours[1];
        if (dLight < p.border1 + border && dith) { colour = p.colours[0]; }
    }
    if (dLight > p.border2) {
        colour = p.colours[2];
        if (dLight < p.border2 + border && dith) { colour = p.colours[1]; }
    }
    return float4(colour.rgb, a * colour.a);
}

// Sand in five shades (DryTerran).
fragment float4 dry_fragment(PlanetVertexOut in [[stage_in]], constant PlanetLayer &p [[buffer(0)]]) {
    Noise n = wideNoise(p, sharpNoise);
    float2 uv = pixelled(in.uv, p.pixels);
    bool dith = dither_at(uv, in.uv, p.pixels);
    float a = step(distance(uv, float2(0.5)), 0.49999);
    uv = sphere_map(uv);
    float dLight = distance(uv, p.light);
    uv = planet_rotate(uv, p.rotation);

    float f = noise_fbm(uv * p.size + float2(p.time, 0.0), n);
    dLight = smoothstep(-0.3, 1.2, dLight);
    if (dLight < p.border1) { dLight *= 0.9; }
    if (dLight < p.border2) { dLight *= 0.9; }

    float c = dLight * pow(f, 0.8) * 3.5;
    if (dith) {
        c += 0.02;
        c *= 1.05;
    }
    float posterize = min(floor(c * 4.0) / 4.0, 1.0);
    float4 colour = p.colours[int(posterize * 4.0)];
    return float4(colour.rgb, a * colour.a);
}

// Continents over a sea (PlanetLandmass).
fragment float4 land_fragment(PlanetVertexOut in [[stage_in]], constant PlanetLayer &p [[buffer(0)]]) {
    Noise n = wideNoise(p, gentleNoise);
    float2 uv = pixelled(in.uv, p.pixels);
    float dLight = distance(uv, p.light);
    float a = step(distance(uv, float2(0.5)), 0.49999);
    uv = sphere_map(planet_rotate(uv, p.rotation));

    float2 base = uv * p.size + float2(p.time, 0.0);
    float fbm1 = noise_fbm(base, n);
    float fbm2 = noise_fbm(base - p.light * fbm1, n);
    float fbm3 = noise_fbm(base - p.light * 1.5 * fbm1, n);
    float fbm4 = noise_fbm(base - p.light * 2.0 * fbm1, n);

    if (dLight < p.border1) { fbm4 *= 0.9; }
    if (dLight > p.border1) {
        fbm2 *= 1.05;
        fbm3 *= 1.05;
        fbm4 *= 1.05;
    }
    if (dLight > p.border2) {
        fbm2 *= 1.3;
        fbm3 *= 1.4;
        fbm4 *= 1.8;
    }
    dLight = pow(dLight, 2.0) * 0.1;
    float4 colour = p.colours[3];
    if (fbm4 + dLight < fbm1) { colour = p.colours[2]; }
    if (fbm3 + dLight < fbm1) { colour = p.colours[1]; }
    if (fbm2 + dLight < fbm1) { colour = p.colours[0]; }
    return float4(colour.rgb, step(p.cutoff, fbm1) * a * colour.a);
}

// Land threaded with rivers (LandRivers).
fragment float4 river_land_fragment(PlanetVertexOut in [[stage_in]], constant PlanetLayer &p [[buffer(0)]]) {
    Noise n = wideNoise(p, gentleNoise);
    float2 uv = pixelled(in.uv, p.pixels);
    bool dith = dither_at(uv, in.uv, p.pixels);
    float a = step(length(uv - float2(0.5)), 0.49999);
    uv = sphere_map(uv);
    float dLight = distance(uv, p.light);
    uv = planet_rotate(uv, p.rotation);

    float2 base = uv * p.size + float2(p.time, 0.0);
    float fbm1 = noise_fbm(base, n);
    float fbm2 = noise_fbm(base - p.light * fbm1, n);
    float fbm3 = noise_fbm(base - p.light * 1.5 * fbm1, n);
    float fbm4 = noise_fbm(base - p.light * 2.0 * fbm1, n);
    float river = step(p.cutoff, noise_fbm(base + fbm1 * 6.0, n));

    float border = (1.0 / p.pixels) * p.ditherSize;
    if (dLight < p.border1) { fbm4 *= 0.9; }
    if (dLight > p.border1) {
        fbm2 *= 1.05;
        fbm3 *= 1.05;
        fbm4 *= 1.05;
    }
    if (dLight > p.border2) {
        fbm2 *= 1.3;
        fbm3 *= 1.4;
        fbm4 *= 1.8;
        if (dLight < p.border2 + border && dith) { fbm4 *= 0.5; }
    }
    dLight = pow(dLight, 2.0) * 0.4;
    float4 colour = p.colours[3];
    if (fbm4 + dLight < fbm1 * 1.5) { colour = p.colours[2]; }
    if (fbm3 + dLight < fbm1 * 1.0) { colour = p.colours[1]; }
    if (fbm2 + dLight < fbm1) { colour = p.colours[0]; }
    if (river < fbm1 * 0.5) {
        colour = p.colours[5];
        if (fbm4 + dLight < fbm1 * 1.5) { colour = p.colours[4]; }
    }
    return float4(colour.rgb, a * colour.a);
}

// Lava flowing over a crust (LavaWorld's Rivers).
fragment float4 lava_rivers_fragment(PlanetVertexOut in [[stage_in]], constant PlanetLayer &p [[buffer(0)]]) {
    Noise n = wideNoise(p, gentleNoise);
    float2 uv = pixelled(in.uv, p.pixels);
    float dLight = distance(uv, p.light);
    float a = step(distance(uv, float2(0.5)), 0.49999);
    uv = sphere_map(planet_rotate(uv, p.rotation));

    float fbm1 = noise_fbm(uv * p.size + float2(p.time, 0.0), n);
    float river = noise_fbm(uv + fbm1 * 2.5, n);
    dLight = pow(dLight, 2.0) * 0.4;
    dLight -= dLight * river;
    river = step(p.cutoff, river);

    float4 colour = p.colours[0];
    if (dLight > p.border1) { colour = p.colours[1]; }
    if (dLight > p.border2) { colour = p.colours[2]; }
    a *= step(p.cutoff, river);
    return float4(colour.rgb, a * colour.a);
}

// Pools on an ice world (IceWorld's Lakes).
fragment float4 lakes_fragment(PlanetVertexOut in [[stage_in]], constant PlanetLayer &p [[buffer(0)]]) {
    Noise n = wideNoise(p, sharpNoise);
    float2 uv = pixelled(in.uv, p.pixels);
    float dLight = distance(uv, p.light);
    uv = planet_rotate(uv, p.rotation);
    float dCircle = distance(uv, float2(0.5));
    uv = sphere_map(uv);

    float lake = noise_fbm(uv * p.size + float2(p.time, 0.0), n);
    dLight = pow(dLight, 2.0) * 0.4;
    dLight -= dLight * lake;
    float4 colour = p.colours[0];
    if (dLight > p.border1) { colour = p.colours[1]; }
    if (dLight > p.border2) { colour = p.colours[2]; }
    float a = step(p.cutoff, lake) * step(dCircle, 0.5);
    return float4(colour.rgb, a * colour.a);
}

constant int cloudSteps = 9;
constant float cloudCurve = 1.3;

static float cloud_circle(float2 uv, Noise n) {
    float uvY = floor(uv.y);
    uv.x += uvY * 0.31;
    float2 f = fract(uv);
    float h = noise_rand(float2(floor(uv.x), uvY), n);
    float m = length(f - 0.25 - (h * 0.5));
    float r = h * 0.25;
    return smoothstep(0.0, r, m * 0.75);
}

// Clouds and gas giant bands (Clouds, GasPlanet).
fragment float4 clouds_fragment(PlanetVertexOut in [[stage_in]], constant PlanetLayer &p [[buffer(0)]]) {
    Noise n = squareNoise(p);
    float2 uv = pixelled(in.uv, p.pixels);
    float dLight = distance(uv, p.light);
    float a = step(distance(uv, float2(0.5)), 0.49999);
    uv = sphere_map(planet_rotate(uv, p.rotation));
    uv.y += smoothstep(0.0, cloudCurve, abs(uv.x - 0.4));

    float2 stretched = uv * float2(1.0, p.stretch);
    float turbulence = 0.0;
    for (int i = 0; i < cloudSteps; i++) {
        turbulence += cloud_circle((stretched * p.size * 0.3) + (float(i + 1) + 10.0) + float2(p.time, 0.0), n);
    }
    float c = noise_fbm(stretched * p.size + turbulence + float2(p.time, 0.0), n);

    float4 colour = p.colours[0];
    if (c < p.cutoff + 0.03) { colour = p.colours[1]; }
    if (dLight + c * 0.2 > p.border1) { colour = p.colours[2]; }
    if (dLight + c * 0.2 > p.border2) { colour = p.colours[3]; }
    return float4(colour.rgb, step(p.cutoff, c) * a * colour.a);
}
