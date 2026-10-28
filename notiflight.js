.pragma library
.import "glow.js" as GlowCurve

// The notification light: its falloff, palettes, timing and the maths of its
// particle cloud, in plain JS so they can be tested (dev/light-proto.sh) and
// handed to shaders/notiflight.frag as uniforms.
//
// The falloff has its own knots, as a Hermite spline built with glow.js's
// slopesOf(): 0.55 up to 3 px, 0.32 at 10, 0.12 at 24 and 0 at 40, at full
// size. `reach` is where it reaches zero; the distances scale with it.

var fullReach = 40

var knots = [
  { d: 3, a: 0.55 },
  { d: 10, a: 0.32 },
  { d: 24, a: 0.12 },
  { d: 40, a: 0 }
]
var m = GlowCurve.slopesOf(knots)

// Opacity at `d` px of a light reaching zero at `reach`, before peak scaling
// (so 0.55 at the source).
function alpha(d, reach) {
  var k = (reach === undefined ? fullReach : Number(reach)) / fullReach
  if (k <= 0) return 0
  d = d / k
  if (d <= knots[0].d) return knots[0].a
  if (d >= knots[3].d) return 0
  var i = 0
  while (d > knots[i + 1].d) i++
  var h = knots[i + 1].d - knots[i].d
  var t = (d - knots[i].d) / h
  var t2 = t * t, t3 = t2 * t
  return (2 * t3 - 3 * t2 + 1) * knots[i].a + (t3 - 2 * t2 + t) * h * m[i]
       + (-2 * t3 + 3 * t2) * knots[i + 1].a + (t3 - t2) * h * m[i + 1]
}

// The knots for the shader, in px for a light reaching zero at `reach`.
function uniforms(reach) {
  var k = Number(reach) / fullReach
  return {
    d: Qt.vector4d(knots[0].d * k, knots[1].d * k, knots[2].d * k, knots[3].d * k),
    a: Qt.vector4d(knots[0].a, knots[1].a, knots[2].a, knots[3].a),
    m: Qt.vector4d(m[0] / k, m[1] / k, m[2] / k, m[3] / k)
  }
}

// ---------------------------------------------------------------------------
// Palettes: five stops (rgb, position in the cycle), cyclic: the last runs
// back to the first at 1.0. A palette of fewer colours repeats its last stop.
// ---------------------------------------------------------------------------

function hex(c) {
  return [parseInt(c.slice(1, 3), 16) / 255, parseInt(c.slice(3, 5), 16) / 255, parseInt(c.slice(5, 7), 16) / 255]
}

var palettes = {
  aurora: {
    stops: [["#2F7BFF", 0.00], ["#EEF1FF", 0.24], ["#9B5CFF", 0.46], ["#FF5FC8", 0.70], ["#FF9A3C", 0.82]],
    cloud: ["#EEF1FF", "#5AA8FF", "#9B5CFF"], particles: 1, peak: 1.0
  },
  blue: {
    stops: [["#0A84FF", 0.00], ["#64D2FF", 0.34], ["#5E9BFF", 0.67], ["#5E9BFF", 0.67], ["#5E9BFF", 0.67]],
    cloud: ["#FFFFFF", "#9AE2FF", "#9AE2FF"], particles: 1, peak: 1.0
  },
  white: {
    stops: [["#FFFFFF", 0.00], ["#CFD8FF", 0.50], ["#CFD8FF", 0.50], ["#CFD8FF", 0.50], ["#CFD8FF", 0.50]],
    cloud: ["#FFFFFF", "#FFFFFF", "#FFFFFF"], particles: 0, peak: 0.8
  },
  critical: {
    stops: [["#FFB340", 0.00], ["#FF453A", 0.40], ["#FFE2B0", 0.75], ["#FFE2B0", 0.75], ["#FFE2B0", 0.75]],
    cloud: ["#FFB340", "#FFB340", "#FFB340"], particles: 0, peak: 1.15
  }
}

// The palette's colour at position x in [0,1), as the shader mixes it.
function paletteAt(name, x) {
  var st = palettes[name].stops.map(function(s) { return { c: hex(s[0]), p: s[1] } })
  x = x - Math.floor(x)
  function ss(a, b, v) { if (b <= a) return v >= b ? 1 : 0; var t = Math.min(1, Math.max(0, (v - a) / (b - a))); return t * t * (3 - 2 * t) }
  function mix(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t] }
  var c = mix(st[4].c, st[0].c, ss(st[4].p, 1, x))
  for (var i = 3; i >= 0; i--) if (x < st[i + 1].p) c = mix(st[i].c, st[i + 1].c, ss(st[i].p, st[i + 1].p, x))
  return c
}

// ---------------------------------------------------------------------------
// Timing. Times in ms.
// ---------------------------------------------------------------------------

// How long the light stays, fade-out included.
function lightMs(stay, lifetimeMs, critical) {
  if (critical) return 8000
  if (stay) return 5000
  return Math.max(1200, Math.min(5000, lifetimeMs))
}

// The fade: 280 ms OutCubic in, 600 ms InOutQuad out ending at lightMs.
function envelope(tMs, lightMs) {
  if (tMs <= 0 || tMs >= lightMs) return 0
  var fin = tMs >= 280 ? 1 : 1 - Math.pow(1 - tMs / 280, 3)
  var left = lightMs - tMs
  var fout = 1
  if (left < 600) {
    var u = 1 - left / 600
    fout = 1 - (u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2)
  }
  return fin * fout
}

// The burst, as the shader computes it (t in s): width and brightness factors.
function burstWidth(t) { return 1 + 0.30 * Math.exp(-2.2 * t) * Math.cos(2 * Math.PI * 1.3 * t) * (1 - smoothstep(1.4, 1.8, t)) }
function burstBrightness(t) { return 1 + 0.25 * Math.exp(-3.6 * t) * (1 - smoothstep(1.4, 1.8, t)) }

function smoothstep(a, b, x) {
  var t = Math.min(1, Math.max(0, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}

// ---------------------------------------------------------------------------
// The cloud. Everything below mirrors shaders/notiflight.frag in float64.
// ---------------------------------------------------------------------------

// Tuned in the prototype; not settings.
var emitter = {
  period: 2.2, drift: 18, swirl: 10, curl: 6, curlScale: 80, gain: 0.85,
  grain: [1.0, 1.6, 2.6], density: [1.0, 0.9, 0.7], whiteHot: 0.4
}

// The integer hash (hash.glsl): all arithmetic as unsigned 32-bit.
function wang(x) {
  x = ((x ^ 61) ^ (x >>> 16)) >>> 0
  x = Math.imul(x, 9) >>> 0
  x = (x ^ (x >>> 4)) >>> 0
  x = Math.imul(x, 668265261) >>> 0
  return (x ^ (x >>> 15)) >>> 0
}
function cellHash(cx, cy, salt) { return wang(((cx >>> 0) ^ wang(((cy >>> 0) ^ wang(salt >>> 0)) >>> 0)) >>> 0) }
function byteOf(h, i) { return ((h >>> (8 * i)) & 255) / 255 }

function lattice(cx, cy, t, salt) {
  var h = cellHash(cx, cy, salt)
  var ph = (0.5 + byteOf(h, 1)) * t + byteOf(h, 0)
  ph -= Math.floor(ph)
  return 1 - Math.abs(2 * ph - 1)
}

// value in [0,1] and its gradient: [v, dv/dx, dv/dy]
function noised(x, y, t, salt) {
  var ix = Math.floor(x), iy = Math.floor(y)
  var fx = x - ix, fy = y - iy
  var wx = fx * fx * fx * (fx * (fx * 6 - 15) + 10), wy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
  var dwx = 30 * fx * fx * (fx - 1) * (fx - 1), dwy = 30 * fy * fy * (fy - 1) * (fy - 1)
  var a = lattice(ix, iy, t, salt), b = lattice(ix + 1, iy, t, salt)
  var e = lattice(ix, iy + 1, t, salt), g = lattice(ix + 1, iy + 1, t, salt)
  var k1 = b - a, k2 = e - a, k4 = a - b - e + g
  return [a + k1 * wx + k2 * wy + k4 * wx * wy, dwx * (k1 + k4 * wy), dwy * (k2 + k4 * wx)]
}

function vnoise1(x, salt) {
  var i = Math.floor(x), f = x - i
  var w = f * f * f * (f * (f * 6 - 15) + 10)
  var a = byteOf(cellHash(i, 0, salt), 0), b = byteOf(cellHash(i + 1, 0, salt), 0)
  return a + (b - a) * w
}

// The flow envelope of a grain over its cycle, a in [0,1); zero (with zero
// slope) at both ends for any h4, h5 in [0,1).
function flowEnvelope(a, h4, h5) {
  return smoothstep(0.03 + 0.10 * h4, 0.30 + 0.10 * h4, a) * (1 - smoothstep(0.55 + 0.10 * h5, 0.95 + 0.05 * h5, a))
}

// Where the grain on pixel (s, d) at time t (s) was at birth: the pre-image
// before and after the curl displacement, plus the cycle and its age.
function flowMap(s, d, t, seed, em) {
  em = em || emitter
  var sd = seed >>> 0
  var phi = vnoise1(s / 140, (sd + 5) >>> 0) - 0.5
  var u = t / em.period + phi
  var k = Math.floor(u), a = u - k
  var ks = k >>> 0
  var tau = a * em.period
  var d0 = d + em.drift * tau
  var swirl = 2 * vnoise1(d0 / 60, (sd + 11 + Math.imul(ks, 31)) >>> 0) - 1
  var Ps = s - em.swirl * tau * swirl
  var g = noised(Ps / em.curlScale, d0 / em.curlScale, 0.15 * t, (sd + 17) >>> 0)
  return { k: k, a: a, tau: tau, P: [Ps, d0], q: [Ps + em.curl * g[2], d0 - em.curl * g[1]] }
}
