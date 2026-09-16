.pragma library

// The glow's falloff: opacity as a function of distance from the notch's edge.
//
// The curve below is the full-size one, reaching zero at 80 px. The notch's
// `glowSize` setting is that reach in px; every knot distance scales with it
// (opacities do not), so a 40 px glow is the same curve at half the distance.
//
// Not a shape and not a blur. Every pixel outside the notch takes its opacity
// from its exact distance `d` (logical px) to the notch's silhouette -- the bar
// plus both concave fillets -- through this one curve:
//
//     d ≤ 6    0.35                        the brightest the glow gets
//     d = 20   0.18
//     d = 50   0.07
//     d ≥ 80   0                            and nothing beyond
//
// Between the knots it is a monotone cubic Hermite spline (Fritsch–Butland
// slopes), with zero slope at 6 px and at 80 px. So the curve is continuous
// and smooth (C¹) everywhere, never rises, and meets zero tangentially: there
// is no step and no kink anywhere a viewer could read as the glow's edge.
//
// Glow.qml passes these same knots and slopes to the fragment shader, which
// evaluates the identical spline, so `alpha(d)` here is what gets drawn.

var knots = [
  { d: 6, a: 0.35 },
  { d: 20, a: 0.18 },
  { d: 50, a: 0.07 },
  { d: 80, a: 0 }
]

// Interior slopes by Fritsch–Butland (a weighted harmonic mean of the two
// neighbouring secants): monotone, and zero wherever the curve would turn.
// The end slopes are zero by construction.
function slopes() {
  var m = [0]
  for (var i = 1; i < knots.length - 1; i++) {
    var h0 = knots[i].d - knots[i - 1].d, h1 = knots[i + 1].d - knots[i].d
    var s0 = (knots[i].a - knots[i - 1].a) / h0, s1 = (knots[i + 1].a - knots[i].a) / h1
    m.push(s0 * s1 <= 0 ? 0 : 3 * (h0 + h1) / ((2 * h1 + h0) / s0 + (h1 + 2 * h0) / s1))
  }
  m.push(0)
  return m
}

var m = slopes()

// The knot distances for a glow reaching zero at `size` px.
function scaled(size) {
  var k = (size === undefined ? fullReach : Number(size)) / fullReach
  return knots.map(function(n) { return { d: n.d * k, a: n.a } })
}

function alpha(d, size) {
  var k = (size === undefined ? fullReach : Number(size)) / fullReach
  if (k <= 0) return 0
  d = d / k
  if (d <= knots[0].d) return knots[0].a
  var last = knots.length - 1
  if (d >= knots[last].d) return 0
  var i = 0
  while (d > knots[i + 1].d) i++
  var h = knots[i + 1].d - knots[i].d
  var t = (d - knots[i].d) / h
  var t2 = t * t, t3 = t2 * t
  return (2 * t3 - 3 * t2 + 1) * knots[i].a + (t3 - 2 * t2 + t) * h * m[i]
       + (-2 * t3 + 3 * t2) * knots[i + 1].a + (t3 - t2) * h * m[i + 1]
}

// The distance past which the full-size glow is exactly zero.
var fullReach = knots[knots.length - 1].d

// For ShaderEffect, for a glow reaching zero at `size` px: the knots'
// distances, opacities and slopes as vec4s. Scaling the distances by k scales
// each slope by 1/k, which keeps the Hermite curve the same shape.
function uniforms(size) {
  var k = Number(size) / fullReach
  var n = scaled(size)
  return {
    d: Qt.vector4d(n[0].d, n[1].d, n[2].d, n[3].d),
    a: Qt.vector4d(n[0].a, n[1].a, n[2].a, n[3].a),
    m: Qt.vector4d(m[0] / k, m[1] / k, m[2] / k, m[3] / k)
  }
}
