#version 440

// The notch glow. See glow.js for the curve and Glow.qml for the geometry.
//
// For every pixel: the exact distance to the notch's silhouette (the bar, with
// square top corners and convex bottom corners, plus the two concave fillets
// where it meets the screen edge), then opacity from a monotone cubic Hermite
// spline over that distance. No blur, no filled shape.

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
};

// Signed distance to the bar: x in [0, W], extending upward without end (its
// top is the screen edge), bottom corners rounded by R.
float sdBar(vec2 p) {
    float R = bottomRadius;
    vec2 q = vec2(abs(p.x - barWidth * 0.5) - (barWidth * 0.5 - R), p.y - (barHeight - R));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - R;
}

// Distance to a quarter-circle arc: centre c, radius F, spanning the quadrant
// where sign(p - c) equals `quadrant`, ending at points a and b.
float arcDistance(vec2 p, vec2 c, vec2 quadrant, vec2 a, vec2 b) {
    vec2 v = (p - c) * quadrant;
    if (v.x >= 0.0 && v.y >= 0.0) return abs(length(p - c) - filletRadius);
    return min(length(p - a), length(p - b));
}

// Signed distance to the whole silhouette. The outline a pixel can be near is
// the left fillet's arc, the bar's sides and rounded bottom, and the right
// fillet's arc; the bar's sides beside the fillets and the screen edge are not
// part of it. Outside the silhouette this is the exact Euclidean distance.
// Inside it only the sign matters.
float silhouette(vec2 p) {
    float F = filletRadius;
    float bar = sdBar(p);
    if (F <= 0.0) return bar;

    vec2 cl = vec2(-F, F);
    vec2 cr = vec2(barWidth + F, F);
    float arcL = arcDistance(p, cl, vec2(1.0, -1.0), vec2(-F, 0.0), vec2(0.0, F));
    float arcR = arcDistance(p, cr, vec2(-1.0, -1.0), vec2(barWidth + F, 0.0), vec2(barWidth, F));

    bool inFilletL = p.x >= -F && p.x <= 0.0 && p.y >= 0.0 && p.y <= F && length(p - cl) >= F;
    bool inFilletR = p.x >= barWidth && p.x <= barWidth + F && p.y >= 0.0 && p.y <= F && length(p - cr) >= F;
    if (bar <= 0.0 || inFilletL || inFilletR) return -min(abs(bar), min(arcL, arcR));
    return min(bar, min(arcL, arcR));
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
    float d = silhouette(p);
    // Under the notch nothing is drawn, except a one-pixel sliver so the
    // notch's antialiased edge blends into glow rather than into background.
    float under = smoothstep(-1.5, -0.5, d);
    float a = hermite(max(d, 0.0)) * under * presence;
    fragColor = vec4(glowColor.rgb * a, a) * qt_Opacity;
}
