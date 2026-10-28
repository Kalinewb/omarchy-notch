#version 440

// The notch glow. See glow.js for the curve and Glow.qml for the geometry.
//
// For every pixel: the exact distance to the notch's silhouette (the bar, with
// square top corners and convex bottom corners, plus the two concave fillets
// where it meets the screen edge), then opacity from a monotone cubic Hermite
// spline over that distance. No blur, no filled shape.

#extension GL_GOOGLE_include_directive : enable

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // this item, logical px
    float margin;       // bar's left edge is `margin` px in from this item's left
    float barWidth;
    float barHeight;
    float bottomRadius;
    float filletRadius;
    float presence;     // 0..1, the fade
    vec4 glowColor;     // unpremultiplied RGBA
    vec4 knotD;         // knot distances
    vec4 knotA;         // knot opacities
    vec4 knotM;         // knot slopes
    float edgeTail;     // >= 1: how much further the glow runs along the screen's top edge than down
};

#include "silhouette.glsl"

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

void main() {
    vec2 p = qt_TexCoord0 * itemSize - vec2(margin, 0.0);
    float d = silhouette(p);
    // Under the notch nothing is drawn, except a one-pixel sliver so the
    // notch's antialiased edge blends into glow rather than into background.
    float under = smoothstep(-1.5, -0.5, d);
    // The curve reads a distance that is longer along the screen's top edge,
    // so the glow tapers outward there instead of being cut off at its
    // brightest. `under` keeps the true distance, and the clamp stops the
    // blend dipping below zero at the tip.
    float reachD = max(d, 0.0);
    if (edgeTail > 1.0 && d > 0.0) reachD = max(smin(d, tailDistance(p), 0.2 * knotD.w), 0.0);
    float a = hermite(reachD) * under * presence;
    fragColor = vec4(glowColor.rgb * a, a) * qt_Opacity;
}
