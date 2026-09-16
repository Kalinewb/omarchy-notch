#version 440

// The subtle charging glow: light only under the notch's bottom edge,
// strongest in the middle and fading to nothing toward the sides.
//
// For every pixel below the notch: the exact distance d to the bar's outline
// (square top corners, convex bottom corners; the fillets are outside the
// bar's width, where this glow is zero anyway), and its horizontal position u
// across the bar, -1 at the left side, 0 in the middle, +1 at the right side.
//
//     alpha = strength / 0.35 × curve(d) × cos²(π u / 2) × presence
//
// curve(d) is the same monotone Hermite falloff as the outline glow (glow.js),
// so this is that glow's shape along the bottom, dimmed to `strength` at its
// brightest and weighted toward the middle. Nothing is drawn under the notch.

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
    float presence;     // 0..1, the fade
    float strength;     // the brightest alpha, in the middle at the edge
    vec4 glowColor;     // unpremultiplied RGBA
    vec4 knotD;         // knot distances
    vec4 knotA;         // knot opacities
    vec4 knotM;         // knot slopes
};

float sdBar(vec2 p) {
    float R = bottomRadius;
    vec2 q = vec2(abs(p.x - barWidth * 0.5) - (barWidth * 0.5 - R), p.y - (barHeight - R));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - R;
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

void main() {
    vec2 p = qt_TexCoord0 * itemSize - vec2(margin, 0.0);
    float u = barWidth > 0.0 ? (p.x - barWidth * 0.5) / (barWidth * 0.5) : 2.0;
    float across = abs(u) >= 1.0 ? 0.0 : pow(cos(1.5707963 * u), 2.0);
    float d = sdBar(p);
    float under = smoothstep(-1.5, -0.5, d);
    float a = (strength / 0.35) * hermite(max(d, 0.0)) * across * under * presence;
    fragColor = vec4(glowColor.rgb * a, a) * qt_Opacity;
}
