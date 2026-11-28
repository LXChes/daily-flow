#include <metal_stdlib>
using namespace metal;

// The 3D skeleton watch: a Cook-Torrance GGX material with a procedural studio the metal reflects, a PCF shadow
// map from the key light, a clearcoat for the ceramic bezel, a sapphire crystal, ruby jewels, lume that glows,
// then a cheap bloom and ACES tone mapping. The structs below mirror the Swift ones in WatchRenderer.swift and
// WatchScene.swift field for field: change one side, change the other.

struct Material {
    float4 baseColor;   // rgb linear
    float4 emissive;    // rgb HDR; for bridges the rgb is the bevel colour instead
    float4 params;      // x metallic, y roughness, z clearcoat, w kind
    float4 extra;       // x pattern, y pattern strength, z bevel polish, w glow
};

struct Draw {
    float4x4 model;
    Material material;
};

struct Frame {
    float4x4 viewProj;
    float4x4 root;
    float4x4 lightViewProj;
    float4 cameraPos;   // xyz world
    float4 lightDir;    // xyz world, towards the light; w key gain
    float4 lightColor;  // rgb
    float4 envTint;     // rgb tint, a gain
    float4 timing;      // x time, y pulse, z exposure, w bloom strength
    float4 flags;       // x isDark, y shadow texel, z unused, w curtain
    float4 background;  // rgb linear
    float4 motion;      // x tilt x, y tilt y, z aspect, w unused
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 worldNormal;
    float3 modelPos;
    float3 modelNormal;
    float2 uv;
    float4 shadowCoord;
};

// MARK: Vertex

vertex VertexOut vs_main(VertexIn in [[stage_in]],
                         constant Frame &frame [[buffer(1)]],
                         constant Draw &draw [[buffer(2)]])
{
    VertexOut out;
    float4 modelPos = draw.model * float4(in.position, 1.0);
    float4 worldPos = frame.root * modelPos;
    float3 modelNormal = normalize((draw.model * float4(in.normal, 0.0)).xyz);
    out.position = frame.viewProj * worldPos;
    out.worldPos = worldPos.xyz;
    out.worldNormal = normalize((frame.root * float4(modelNormal, 0.0)).xyz);
    out.modelPos = modelPos.xyz;
    out.modelNormal = modelNormal;
    out.uv = in.uv;
    out.shadowCoord = frame.lightViewProj * modelPos;
    return out;
}

vertex float4 vs_shadow(VertexIn in [[stage_in]],
                        constant Frame &frame [[buffer(1)]],
                        constant Draw &draw [[buffer(2)]])
{
    return frame.lightViewProj * (draw.model * float4(in.position, 1.0));
}

// MARK: Helpers

float hash21(float2 p)
{
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float hash11(float x)
{
    return fract(sin(x * 127.1) * 43758.5453);
}

/// A soft rectangular light seen from the origin: `center` is its direction, `halfSize` its half extent in
/// gnomonic units, `soft` how far the edge is blurred (grows with roughness).
float softBox(float3 d, float3 center, float3 upRef, float2 halfSize, float soft)
{
    float dz = dot(d, center);
    if (dz < 0.08) {
        return 0.0;
    }
    float3 right = normalize(cross(upRef, center));
    float3 up = cross(center, right);
    float2 p = float2(dot(d, right), dot(d, up)) / dz;
    float2 q = abs(p) - halfSize;
    float sd = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0);
    return 1.0 - smoothstep(-soft, soft, sd);
}

/// The studio the watch sits in, fixed in the room: a graded floor and ceiling, a dark curtain behind the
/// viewer, a big key softbox up and to the left, a strip light overhead, two tall rim strips and a small kicker
/// below. Tilting the watch slides these across the metal.
float3 studio(float3 d, float rough, constant Frame &fr)
{
    if (fr.flags.z > 0.5) {
        return float3(0.3) * fr.envTint.rgb;
    }
    float soft = 0.02 + rough * rough * 0.8;
    float h = d.y;
    float3 col = mix(float3(0.012, 0.013, 0.018), float3(0.10, 0.105, 0.12), smoothstep(-0.8, 0.0, h));
    col = mix(col, float3(0.34, 0.36, 0.40), smoothstep(0.0, 1.0, h));
    float front = smoothstep(0.45, 0.95, d.z);
    col *= 1.0 - fr.flags.w * front * (1.0 - rough);
    // The key: a big softbox up and to the left.
    col += float3(1.0, 0.97, 0.92) * 12.0
        * softBox(d, normalize(float3(-0.55, 0.62, 0.62)), float3(0.0, 1.0, 0.0), float2(0.55, 0.36), soft);
    // A broad, soft fill behind the viewer, so flat polished faces read as grey metal rather than black.
    col += float3(1.0, 1.0, 1.0) * 0.55
        * softBox(d, normalize(float3(0.05, 0.30, 0.95)), float3(0.0, 1.0, 0.0), float2(0.85, 0.50), soft + 0.25);
    // Two tall strips in front of the viewer: they glide across flat metal as the watch tilts.
    col += float3(1.0, 1.0, 1.0) * 4.0
        * softBox(d, normalize(float3(-0.42, 0.10, 0.90)), float3(0.0, 1.0, 0.0), float2(0.07, 0.95), soft);
    col += float3(1.0, 0.98, 0.95) * 3.0
        * softBox(d, normalize(float3(0.30, 0.05, 0.95)), float3(0.0, 1.0, 0.0), float2(0.05, 0.95), soft);
    // A strip light overhead, two rim strips at the sides and a kicker below.
    col += float3(0.92, 0.96, 1.0) * 7.0
        * softBox(d, normalize(float3(0.06, 1.0, 0.14)), float3(0.0, 0.0, -1.0), float2(0.95, 0.18), soft);
    col += float3(1.0, 1.0, 1.0) * 9.0
        * softBox(d, normalize(float3(0.95, 0.06, 0.30)), float3(0.0, 1.0, 0.0), float2(0.10, 0.95), soft);
    col += float3(0.9, 0.95, 1.0) * 6.0
        * softBox(d, normalize(float3(-0.95, -0.04, -0.22)), float3(0.0, 1.0, 0.0), float2(0.10, 0.95), soft);
    col += float3(1.0, 0.9, 0.8) * 3.5
        * softBox(d, normalize(float3(0.50, -0.42, 0.74)), float3(0.0, 1.0, 0.0), float2(0.38, 0.14), soft);
    return col * fr.envTint.rgb * fr.envTint.a;
}

float distributionGGX(float noh, float a)
{
    float a2 = a * a;
    float d = noh * noh * (a2 - 1.0) + 1.0;
    return a2 / (M_PI_F * d * d + 1e-5);
}

float visibilitySmith(float nov, float nol, float a)
{
    float a2 = a * a;
    float gv = nol * sqrt(nov * nov * (1.0 - a2) + a2);
    float gl = nov * sqrt(nol * nol * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-4);
}

/// Analytic split-sum environment BRDF (Karis, mobile).
float2 envBRDF(float rough, float nov)
{
    float4 c0 = float4(-1.0, -0.0275, -0.572, 0.022);
    float4 c1 = float4(1.0, 0.0425, 1.04, -0.04);
    float4 r = rough * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * nov)) * r.x + r.y;
    return float2(-1.04, 1.04) * a004 + r.zw;
}

float shadowFactor(float4 shadowCoord, depth2d<float> shadowMap, constant Frame &fr)
{
    constexpr sampler shadowSampler(coord::normalized, filter::linear, address::clamp_to_edge,
                                    compare_func::less_equal);
    float3 p = shadowCoord.xyz / shadowCoord.w;
    float2 uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || p.z > 1.0) {
        return 1.0;
    }
    float texel = fr.flags.y;
    float sum = 0.0;
    for (int ix = 0; ix < 4; ix++) {
        for (int iy = 0; iy < 4; iy++) {
            float2 offset = (float2(float(ix), float(iy)) - 1.5) * texel * 2.0;
            sum += shadowMap.sample_compare(shadowSampler, uv + offset, p.z - 0.0012);
        }
    }
    return sum / 16.0;
}

/// Metal or dielectric under the key light and the studio, with an optional clearcoat.
float3 shadePBR(float3 base, float metallic, float rough, float coat,
                float3 n, float3 v, float shadow, float ao, constant Frame &fr)
{
    rough = clamp(rough, 0.04, 1.0);
    float a = rough * rough;
    float nov = max(dot(n, v), 1e-3);
    float3 f0 = mix(float3(0.04), base, metallic);
    // Satin metal scatters a little: a share of its colour is lit like a diffuse surface. Mirror polish has none.
    float satin = 0.4 * smoothstep(0.1, 0.4, rough);
    float3 diffuseColor = base * (1.0 - metallic * (1.0 - satin));
    float2 ab = envBRDF(rough, nov);
    float3 r = reflect(-v, n);

    float3 specEnv = studio(r, rough, fr) * (f0 * ab.x + ab.y) * ao;
    float3 irradiance = studio(n, 1.0, fr) + float3(0.05);
    float3 diffEnv = diffuseColor * irradiance * ao;

    float3 l = normalize(fr.lightDir.xyz);
    float3 h = normalize(l + v);
    float nol = saturate(dot(n, l));
    float noh = saturate(dot(n, h));
    float voh = saturate(dot(v, h));
    float3 fresnel = f0 + (1.0 - f0) * pow(1.0 - voh, 5.0);
    float3 radiance = fr.lightColor.rgb * fr.lightDir.w * shadow;
    float3 specDirect = min(distributionGGX(noh, a) * visibilitySmith(nov, nol, a) * fresnel, float3(24.0));
    float3 direct = (diffuseColor * (1.0 / M_PI_F) + specDirect) * nol * radiance;

    float coatF = 0.04 + 0.96 * pow(1.0 - nov, 5.0);
    float3 coatTerm = float3(0.0);
    float coatAtten = 1.0;
    if (coat > 0.0) {
        coatAtten = 1.0 - coatF * coat;
        float coatSpec = min(distributionGGX(noh, 0.0036) * visibilitySmith(nov, nol, 0.0036) * 0.04, 24.0);
        coatTerm = (studio(r, 0.05, fr) * coatF + coatSpec * nol * radiance) * coat;
    }
    return (diffEnv + specEnv + direct) * coatAtten + coatTerm;
}

// MARK: Material fragment

fragment float4 fs_main(VertexOut in [[stage_in]],
                        constant Frame &fr [[buffer(1)]],
                        constant Draw &draw [[buffer(2)]],
                        texture2d<float> printTex [[texture(0)]],
                        texture2d<float> auxTex [[texture(1)]],
                        depth2d<float> shadowMap [[texture(3)]])
{
    constexpr sampler texSampler(filter::linear, mip_filter::linear, address::clamp_to_edge, max_anisotropy(8));

    float kind = draw.material.params.w;
    float3 base = draw.material.baseColor.rgb;
    float metallic = draw.material.params.x;
    float rough = draw.material.params.y;
    float coat = draw.material.params.z;
    float patternType = draw.material.extra.x;
    float patternStrength = draw.material.extra.y;
    float bevelPolish = draw.material.extra.z;
    float glow = draw.material.extra.w;

    float shadow = shadowFactor(in.shadowCoord, shadowMap, fr);
    // Leather and the satin bracelet are far from the movement: no shadow-map streaks on them.
    if (kind == 8.0 || (patternType > 0.5 && patternType < 1.5)) {
        shadow = 1.0;
    }
    float3 nm = normalize(in.modelNormal);
    float3 v = normalize(fr.cameraPos.xyz - in.worldPos);

    // Sapphire crystal: reflections only, a faint thin-film tint, clear at the centre.
    if (kind == 4.0) {
        float3 nw = normalize(in.worldNormal);
        float ndv = saturate(dot(nw, v));
        float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
        float3 refl = studio(reflect(-v, nw), 0.03, fr);
        float3 film = 0.5 + 0.5 * cos(6.2831853 * (ndv * 0.9 + float3(0.0, 0.33, 0.67)));
        float3 tint = mix(float3(1.0), film, 0.35) * mix(float3(1.0), base, 0.5);
        // Added light only (the pipeline blends One, One): the glass can never darken or hide the dial.
        return float4(refl * fres * tint * draw.material.extra.y * 0.5, 0.0);
    }

    // Printed overlay (progress arc and label), lit softly and shadowed by the hands.
    if (kind == 7.0) {
        float4 t = auxTex.sample(texSampler, in.uv);
        float3 c = t.a > 0.002 ? t.rgb / t.a : float3(0.0);
        float lit = mix(0.45, 1.0, shadow);
        return float4(c * lit * 1.35 * t.a, t.a);
    }

    // Lume and glowing marks.
    if (kind == 5.0) {
        float3 nw = normalize(in.worldNormal);
        float ndv = saturate(dot(nw, v));
        float3 color = base * 0.12 + draw.material.emissive.rgb * glow * (0.85 + 0.15 * ndv);
        return float4(color, 1.0);
    }

    // Ruby jewel: a dark red that glows through its dome, with a hard reflection on top.
    if (kind == 3.0) {
        float3 nw = normalize(in.worldNormal);
        float ndv = saturate(dot(nw, v));
        float inner = pow(ndv, 1.5);
        float3 spec = studio(reflect(-v, nw), 0.05, fr) * (0.06 + 0.94 * pow(1.0 - ndv, 5.0));
        float3 body = mix(base * 0.22, base * 1.15, inner) * mix(0.55, 1.0, shadow);
        float3 color = body + draw.material.emissive.rgb * glow * (0.35 + 0.65 * inner) + spec;
        return float4(color, 1.0);
    }

    // Ambient occlusion for the low parts of the movement: the deeper, the darker, and more so under the ring.
    float rr = length(in.modelPos.xy);
    float insideDial = 1.0 - smoothstep(0.93, 0.97, rr);
    float depthAO = mix(0.42, 1.0, smoothstep(-0.01, 0.17, in.modelPos.z));
    float edgeAO = 1.0 - 0.55 * smoothstep(0.62, 0.89, rr) * (1.0 - smoothstep(0.05, 0.2, in.modelPos.z));
    float ao = mix(1.0, depthAO * edgeAO, insideDial);

    float edge = bevelPolish * (1.0 - smoothstep(0.88, 0.995, abs(nm.z)));

    if (kind == 1.0) {
        // Perlage: overlapping circular dishes on a hex lattice, each catching the light on its own.
        float2 p = in.modelPos.xy / 0.0525;
        float2 cell = float2(1.0, 1.7320508);
        float2 a = p - cell * floor(p / cell) - cell * 0.5;
        float2 pb = p + cell * 0.5;
        float2 b = pb - cell * floor(pb / cell) - cell * 0.5;
        float2 g = dot(a, a) < dot(b, b) ? a : b;
        float radius = length(g);
        nm = normalize(nm + float3(-g * 0.6 * (1.0 - smoothstep(0.2, 0.7, radius)), 0.0));
        base *= 0.78 + 0.22 * (1.0 - smoothstep(0.3, 0.64, radius));
        rough *= 0.8 + 0.4 * smoothstep(0.15, 0.62, radius);
    } else if (kind == 2.0) {
        // Cotes de Geneve: fine parallel stripes that flash as the light slides.
        float s = dot(in.modelPos.xy, float2(0.766, 0.643)) * 125.0;
        float top = smoothstep(0.9, 0.99, nm.z);
        nm = normalize(nm + float3(0.766, 0.643, 0.0) * cos(s) * patternStrength * top);
        base *= 1.0 - 0.07 * (0.5 - 0.5 * sin(s)) * top;
        base = mix(base, draw.material.emissive.rgb, edge);
    } else if (kind == 6.0) {
        // Printed ring (bezel, hour ring): the painted texture over a lacquered or ceramic body.
        float4 t = printTex.sample(texSampler, in.uv);
        base = t.rgb + (1.0 - t.a) * base;
    } else if (kind == 8.0) {
        // Leather: the stitched texture with a fine grain.
        float4 t = auxTex.sample(texSampler, in.uv);
        float2 gp = floor(in.uv * float2(260.0, 700.0));
        float n1 = hash21(gp);
        float n2 = hash21(gp + 17.0);
        nm = normalize(nm + float3(n1 - 0.5, n2 - 0.5, 0.0) * patternStrength);
        base = t.rgb * (0.9 + 0.2 * n1);
    }

    if (kind != 2.0) {
        base = mix(base, min(base * 1.35, float3(1.0)), edge);
    }
    rough = mix(rough, rough * 0.3, edge);

    if (patternType > 0.5 && patternType < 1.5) {
        // Brushed along y: fine streaks.
        float h = hash11(floor(in.modelPos.x * 340.0));
        nm = normalize(nm + float3((h - 0.5) * patternStrength, 0.0, 0.0));
    } else if (patternType > 1.5 && patternType < 2.5) {
        // Knurling round an axis along x.
        float ang = atan2(in.modelPos.z + 0.02, in.modelPos.y);
        float3 tang = float3(0.0, -sin(ang), cos(ang));
        nm = normalize(nm + tang * cos(ang * 44.0) * patternStrength);
    }

    float3 nw = normalize((fr.root * float4(nm, 0.0)).xyz);
    float3 color = shadePBR(base, metallic, rough, coat, nw, v, shadow, ao, fr);
    if (kind == 0.0) {
        color += draw.material.emissive.rgb * glow;
    }
    return float4(color, 1.0);
}

// MARK: Full screen passes

struct ScreenOut {
    float4 position [[position]];
    float2 uv;
};

vertex ScreenOut vs_fullscreen(uint vid [[vertex_id]])
{
    float2 p = float2(float((vid << 1) & 2u), float(vid & 2u));
    ScreenOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

/// Keeps what is brighter than 1 (lume, jewels, glints) and shrinks it to a quarter size.
fragment float4 fs_bright(ScreenOut in [[stage_in]], texture2d<float> source [[texture(0)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 texel = 1.0 / float2(float(source.get_width()), float(source.get_height()));
    float3 sum = float3(0.0);
    for (int ix = 0; ix < 2; ix++) {
        for (int iy = 0; iy < 2; iy++) {
            float2 offset = (float2(float(ix), float(iy)) * 2.0 - 1.0) * texel;
            sum += source.sample(s, in.uv + offset).rgb;
        }
    }
    float3 c = sum * 0.25;
    float peak = max(max(c.r, c.g), c.b);
    float knee = max(peak - 1.0, 0.0) / max(peak, 1e-4);
    return float4(c * knee, 1.0);
}

fragment float4 fs_blur(ScreenOut in [[stage_in]],
                        texture2d<float> source [[texture(0)]],
                        constant float2 &direction [[buffer(0)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 texel = 1.0 / float2(float(source.get_width()), float(source.get_height()));
    float weights[5] = {0.2270270, 0.1945946, 0.1216216, 0.0540541, 0.0162162};
    float3 sum = source.sample(s, in.uv).rgb * weights[0];
    for (int i = 1; i < 5; i++) {
        float2 offset = direction * texel * (float(i) * 1.7);
        sum += source.sample(s, in.uv + offset).rgb * weights[i];
        sum += source.sample(s, in.uv - offset).rgb * weights[i];
    }
    return float4(sum, 1.0);
}

float3 acesFilm(float3 x)
{
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

/// Scene plus bloom, tone mapped, over the app's background with a soft shadow that follows the tilt.
fragment float4 fs_composite(ScreenOut in [[stage_in]],
                             constant Frame &fr [[buffer(1)]],
                             texture2d<float> sceneTex [[texture(0)]],
                             texture2d<float> bloomTex [[texture(1)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 scene = sceneTex.sample(s, in.uv);
    float3 bloom = bloomTex.sample(s, in.uv).rgb;

    float3 lit = acesFilm((scene.rgb + bloom * fr.timing.w) * fr.timing.z);

    // The 360 x 440 composition the 2D watch uses: the shadow falls a little down and right, and slides with tilt.
    float2 design = float2(in.uv.x * 360.0, in.uv.y * 440.0);
    float2 center = float2(183.0 + fr.motion.y * 12.0, 225.0 - fr.motion.x * 12.0);
    float dist = length(design - center);
    float shade = 1.0 - smoothstep(120.0, 160.0, dist);
    float3 backdrop = fr.background.rgb * (1.0 - 0.3 * shade * (fr.flags.x > 0.5 ? 1.0 : 0.5));

    float3 color = lit + (1.0 - scene.a) * backdrop;
    // A touch of noise so the dark gradients do not band.
    float noise = hash21(in.position.xy) - 0.5;
    color += noise * (1.0 / 400.0);
    return float4(max(color, float3(0.0)), 1.0);
}
