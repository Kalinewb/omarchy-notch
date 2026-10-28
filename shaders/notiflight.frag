#version 440

// The notification light. See notiflight.js for the curve, palettes and timing.
//
// One pass, no offscreen buffers, no texture reads. For every pixel:
//   1. the emitter: a distance `d` to the light's source and an along-edge
//      coordinate `s` (style 0 the notch's silhouette, 1 the screen's top edge,
//      2 all four edges);
//   2. a warp: d is pushed about by 2-octave noise, so the front laps against
//      black like Apple's Intelligent Light rather than sitting in a clean band;
//   3. opacity from a Hermite curve of the warped distance, times a flicker
//      and the burst;
//   4. colour from a cyclic palette along `s`, rotating slowly;
//   5. (particles == 1) a cloud of soft grains from a procedural density
//      field, added on top. Output is premultiplied; alpha 0 is exact black.

#extension GL_GOOGLE_include_directive : enable

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // this item, logical px
    float margin;       // style 0: the bar's left edge is `margin` px in from this item's left
    float barWidth;
    float barHeight;
    float bottomRadius;
    float filletRadius;
    float edgeTail;     // >= 1: how much further the light runs along the top edge than down
    vec2 screenSize;    // styles 1, 2: the screen, logical px
    vec2 origin;        // styles 1, 2: this item's top-left in the screen
    float style;        // 0 notch, 1 top, 2 full
    float time;         // seconds since the light was armed
    float presence;     // 0..1, the fade in and out
    float peak;         // the brightest opacity at the source
    float reach;        // where the curve reaches zero, px (also scales the warp)
    float particles;    // 0 or 1
    float seed;
    float steady;       // 1: no burst, no rotation (critical, reduced motion)
    float view;         // 0 normal, 1 the cloud alone, 2 the light alone
    float cloudRadius;  // grains exist only where d < this, px
    float cloudGain;
    float whiteHot;
    vec4 knotD;         // the curve's knots at full burst width: px
    vec4 knotA;
    vec4 knotM;
    vec4 stop0;         // palette: rgb and the position in the cycle (stop0.w = 0)
    vec4 stop1;
    vec4 stop2;
    vec4 stop3;
    vec4 stop4;
    vec4 cloud0;        // grain colours, rgb
    vec4 cloud1;
    vec4 cloud2;
    vec4 flow;          // period T s, drift v px/s, swirl W px/s, curl A px
    vec4 grainR;        // grain radii, px; w: the curl noise's scale, px
    vec4 grainP;        // grain densities
};

#include "silhouette.glsl"
#include "hash.glsl"

const float TAU = 6.2831853;
const float HALF_PI = 1.5707963;

// ---------------------------------------------------------------------------
// Noise. Value noise on a lattice whose every point sweeps up and down in time
// (a triangle wave, so its values are uniform in [0,1]) with its own phase and
// rate: one hash per corner, it moves without ever jumping, and `noised`
// returns its gradient for free.
// ---------------------------------------------------------------------------

float lattice(ivec2 c, float t, uint salt) {
    uint h = cellHash(c, salt);
    float ph = fract((0.5 + byteOf(h, 1u)) * t + byteOf(h, 0u));
    return 1.0 - abs(2.0 * ph - 1.0);
}

// value in [0,1], d/dx, d/dy
vec3 noised(vec2 p, float t, uint salt) {
    vec2 i = floor(p);
    vec2 f = p - i;
    vec2 w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 dw = 30.0 * f * f * (f - 1.0) * (f - 1.0);
    ivec2 c = ivec2(i);
    float a = lattice(c, t, salt);
    float b = lattice(c + ivec2(1, 0), t, salt);
    float e = lattice(c + ivec2(0, 1), t, salt);
    float g = lattice(c + ivec2(1, 1), t, salt);
    float k1 = b - a, k2 = e - a, k4 = a - b - e + g;
    return vec3(a + k1 * w.x + k2 * w.y + k4 * w.x * w.y,
                dw.x * (k1 + k4 * w.y), dw.y * (k2 + k4 * w.x));
}

// 1D, static, in [0,1]
float vnoise1(float x, uint salt) {
    float i = floor(x);
    float f = x - i;
    float w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    int c = int(i);
    return mix(byteOf(cellHash(ivec2(c, 0), salt), 0u), byteOf(cellHash(ivec2(c + 1, 0), salt), 0u), w);
}

// static 2D, in [0,1]
float vnoise2(vec2 p, uint salt) {
    return noised(p, 0.0, salt).x;
}

float hermite(float d) {
    if (d <= knotD.x) return knotA.x;
    if (d >= knotD.w) return 0.0;
    int i = d <= knotD.y ? 0 : (d <= knotD.z ? 1 : 2);
    float d0 = knotD[i], d1 = knotD[i + 1];
    float h = d1 - d0;
    float t = (d - d0) / h;
    float t2 = t * t, t3 = t2 * t;
    return (2.0 * t3 - 3.0 * t2 + 1.0) * knotA[i] + (t3 - 2.0 * t2 + t) * h * knotM[i]
         + (-2.0 * t3 + 3.0 * t2) * knotA[i + 1] + (t3 - t2) * h * knotM[i + 1];
}

// The cyclic palette: stop i to i+1, the last back to the first at 1.0.
vec3 palette(float x) {
    vec3 c = mix(stop4.rgb, stop0.rgb, smoothstep(stop4.w, 1.0, x));
    if (x < stop4.w) c = mix(stop3.rgb, stop4.rgb, smoothstep(stop3.w, stop4.w, x));
    if (x < stop3.w) c = mix(stop2.rgb, stop3.rgb, smoothstep(stop2.w, stop3.w, x));
    if (x < stop2.w) c = mix(stop1.rgb, stop2.rgb, smoothstep(stop1.w, stop2.w, x));
    if (x < stop1.w) c = mix(stop0.rgb, stop1.rgb, smoothstep(stop0.w, stop1.w, x));
    return c;
}

// ---------------------------------------------------------------------------
// Style 0: the along-outline coordinate. Signed arclength of the silhouette's
// outline from the bottom centre (negative on the left): the bottom, the
// rounded corner, the side up to the fillet, the fillet's arc, then out along
// the screen edge. The tip's fan (pixels beside the notch nearer the tip than
// the side) is polar about the tip, which keeps (s, d) area preserving there.
// ---------------------------------------------------------------------------

float outlineS(vec2 p) {
    float F = filletRadius, R = bottomRadius, H = barHeight;
    float h = barWidth * 0.5;
    float u = abs(p.x - h);
    float S1 = max(h - R, 0.0);
    float S2 = S1 + HALF_PI * R;
    float S3 = S2 + max(H - R - F, 0.0);
    float S4 = S3 + HALF_PI * F;
    float s;
    float dx = u - h - F;
    bool fan = dx > 0.0 && (p.y < F || dx * dx + p.y * p.y < (u - h) * (u - h));
    if (fan) {
        float r = length(vec2(dx, p.y));
        s = S4 + r * atan(p.y, dx);
    } else if (p.y >= H - R) {
        s = u <= S1 ? u : S1 + R * (HALF_PI - atan(p.y - (H - R), u - S1));
    } else if (p.y >= F) {
        s = S2 + (H - R - p.y);
    } else {
        s = S3 + F * clamp(atan(F - p.y, h + F - u), 0.0, HALF_PI);
    }
    return p.x < h ? -s : s;
}

// ---------------------------------------------------------------------------
// The cloud. Each pixel asks which grains are on it, now. A grain is born on a
// cycle `k`, drifts `v` px/s toward the source while swirling along it, and is
// visible only between fade-in and fade-out (E below), so the cycle can reset
// where nothing is drawn. The pixel's pre-image q = (s0, d0) is where its
// grain was at birth; the grains themselves are the 2 x 2 nearest cells of
// three jittered grids around q.
// ---------------------------------------------------------------------------

float flowEnvelope(float a, float h4, float h5) {
    return smoothstep(0.03 + 0.10 * h4, 0.30 + 0.10 * h4, a)
         * (1.0 - smoothstep(0.55 + 0.10 * h5, 0.95 + 0.05 * h5, a));
}

// One layer of the cloud, `shift` of a cycle behind the first.
vec3 cloudLayer(float d, float s, float t, float phi, float shift, uint sd) {
    float T = flow.x, v = flow.y, W = flow.z, A = flow.w;
    float u = t / T + phi + shift;
    float k = floor(u);
    float a = u - k;
    uint ks = uint(int(k));
    float tau = a * T;

    float d0 = d + v * tau;
    float swirl = 2.0 * vnoise1(d0 / 60.0, sd + 11u + ks * 31u) - 1.0;
    vec2 P = vec2(s - W * tau * swirl, d0);
    vec3 g = noised(P / grainR.w, 0.15 * t, sd + 17u);
    vec2 q = P + A * vec2(g.z, -g.y);

    float rho = 1.0 - smoothstep(0.15 * cloudRadius, cloudRadius, d0);
    if (rho <= 0.0) return vec3(0.0);
    // veins and filaments: ridged 3-octave noise
    float f = 0.0, amp = 0.5;
    vec2 fq = q / 28.0;
    for (int o = 0; o < 3; o++) {
        f += amp * vnoise2(fq, sd + 23u + ks * 7u + uint(o));
        fq *= 2.0; amp *= 0.5;
    }
    float ridge = pow(1.0 - abs(2.0 * f / 0.875 - 1.0), 2.5);
    rho *= mix(0.35, 1.0, ridge);

    vec3 sum = vec3(0.0);
    for (int j = 0; j < 3; j++) {
        float r = grainR[j];
        float c = r / 0.3;
        float p = grainP[j] * rho;
        ivec2 i0 = ivec2(floor(q / c - 0.5));
        uint salt = sd + uint(j) * 7919u + ks * 104729u;
        for (int n = 0; n < 4; n++) {
            ivec2 cell = i0 + ivec2(n & 1, n >> 1);
            uint h = cellHash(cell, salt);
            if (byteOf(h, 0u) >= p) continue;
            vec2 centre = (vec2(cell) + vec2(byteOf(h, 1u), byteOf(h, 2u))) * c;
            vec2 dv = (q - centre) / r;
            float dd = dot(dv, dv);
            if (dd > 4.0) continue;
            uint h2 = wang(h);
            float e = flowEnvelope(a, byteOf(h2, 0u), byteOf(h2, 1u));
            float x = byteOf(h, 3u);
            vec3 col = x < 0.5 ? mix(cloud0.rgb, cloud1.rgb, x * 2.0) : mix(cloud1.rgb, cloud2.rgb, x * 2.0 - 1.0);
            col = mix(col, vec3(1.0), whiteHot * (1.0 - smoothstep(0.0, 0.4, a)));
            sum += col * exp(-2.0 * dd) * e;
        }
    }
    return sum * 0.9 * cloudGain;
}

// Each stretch of the outline has its own phase, so the cycles do not all
// reset together; `LAYERS` copies of the cloud, evenly staggered, keep the
// total light level steady however those phases fall.
const int LAYERS = 2;

vec3 cloudLight(float d, float s, float t) {
    uint sd = uint(seed);
    float phi = vnoise1(s / 140.0, sd + 5u) - 0.5;
    vec3 sum = vec3(0.0);
    for (int m = 0; m < LAYERS; m++)
        sum += cloudLayer(d, s, t, phi, float(m) / float(LAYERS), sd + uint(m) * 1000003u);
    return sum;
}

void main() {
    float t = time;
    float d, dReach, under, s, L, weight = 1.0;
    if (style < 0.5) {
        vec2 p = qt_TexCoord0 * itemSize - vec2(margin, 0.0);
        d = silhouette(p);
        under = smoothstep(-1.5, -0.5, d);
        dReach = max(d, 0.0);
        if (edgeTail > 1.0 && d > 0.0) dReach = max(smin(d, tailDistance(p), 0.2 * knotD.w), 0.0);
        d = max(d, 0.0);
        s = outlineS(p);
        L = 2.0 * (max(barWidth * 0.5 - bottomRadius, 0.0) + HALF_PI * bottomRadius
                   + max(barHeight - bottomRadius - filletRadius, 0.0) + HALF_PI * filletRadius);
    } else {
        vec2 sp = origin + qt_TexCoord0 * itemSize;
        under = smoothstep(-1.5, -0.5, silhouette(sp - vec2(0.5 * (screenSize.x - barWidth), 0.0)));
        if (style < 1.5) {
            d = sp.y;
            s = sp.x;
            L = screenSize.x;
            weight = smoothstep(1.0, 0.3, abs(2.0 * sp.x / screenSize.x - 1.0));
        } else {
            vec4 e = vec4(sp.y, screenSize.x - sp.x, screenSize.y - sp.y, sp.x);   // top, right, bottom, left
            d = min(min(e.x, e.y), min(e.z, e.w));
            if (d == e.x) s = sp.x;
            else if (d == e.y) s = screenSize.x + sp.y;
            else if (d == e.z) s = screenSize.x + screenSize.y + (screenSize.x - sp.x);
            else s = 2.0 * screenSize.x + screenSize.y + (screenSize.y - sp.y);
            L = 2.0 * (screenSize.x + screenSize.y);
        }
        dReach = d;
    }

    uint sd = uint(seed);
    float burstW = 1.0, burstB = 1.0, flame = 0.30, rot = 0.0;
    if (steady < 0.5) {
        float tt = max(t, 0.0);
        float cut = 1.0 - smoothstep(1.4, 1.8, tt);
        burstW = 1.0 + 0.30 * exp(-2.2 * tt) * cos(TAU * 1.3 * tt) * cut;
        burstB = 1.0 + 0.25 * exp(-3.6 * tt) * cut;
        flame = 0.30 + 0.6 * exp(-2.2 * tt);
        rot = (tt / 9.0) * (1.0 + 2.5 * exp(-2.2 * tt));
    }

    // 2-octave noise of (s/90, d/60, t*0.3): the warp and a little hue drift
    vec2 np = vec2(s / 90.0, dReach / 60.0);
    float n1 = (noised(np, t * 0.3, sd + 1u).x + 0.5 * noised(np * 2.0, t * 0.45, sd + 2u).x) / 1.5;
    float dw = dReach + (n1 - 0.5) * reach * burstW * flame;
    float dEff = min(dReach, abs(dw));
    float n2 = noised(vec2(s, dReach) / 12.0, t * 1.5, sd + 3u).x;
    float a = hermite(dEff / burstW) * peak * (0.90 + 0.14 * n2) * burstB * weight * presence * under;
    a = clamp(a, 0.0, 1.0);

    vec3 col = palette(fract(1.5 * s / L + rot + 0.15 * (n1 - 0.5)));
    col = clamp(mix(vec3(dot(col, vec3(0.299, 0.587, 0.114))), col, 1.2), 0.0, 1.0);

    vec3 light = col * a;
    vec3 grains = vec3(0.0);
    if (particles > 0.5 && dReach < cloudRadius)
        grains = cloudLight(dReach, s, t) * presence * under * weight;
    if (view > 1.5) grains = vec3(0.0);
    if (view > 0.5 && view < 1.5) { light = vec3(0.0); a = 0.0; }
    fragColor = vec4(min(light + grains, vec3(1.0)), a) * qt_Opacity;
}
