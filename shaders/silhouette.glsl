// The notch's silhouette as a distance field, shared by glow.frag and
// notiflight.frag. Include it AFTER the shader's uniform block: it reads
// barWidth, barHeight, bottomRadius, filletRadius and edgeTail from there.
// Coordinates: origin at the bar's top-left corner, x right, y down, logical px.

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

// Distance to the nearest fillet tip (where the silhouette meets the screen
// edge), with the along-edge part divided by edgeTail: a half-ellipse edgeTail
// times longer along the edge than deep. Only for pixels beside the notch;
// 1e9 anywhere else.
float tailDistance(vec2 p) {
    float F = filletRadius;
    float dx = p.x < -F ? (-F - p.x) : (p.x > barWidth + F ? p.x - barWidth - F : 0.0);
    return dx > 0.0 ? length(vec2(dx / edgeTail, p.y)) : 1.0e9;
}

// Smooth minimum (quadratic), blending the two distances over a band k.
float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}
