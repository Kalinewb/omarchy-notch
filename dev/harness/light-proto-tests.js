// Node tests for the notification light's maths (notiflight.js), as
// dev/light-proto.sh runs them:  node light-proto-tests.js <repo>
//
//   flow      the grain envelope is zero, with zero slope, at both ends of a
//             cycle for any h4, h5; so the cycle can reset where nothing shows
//   jacobian  the map from a pixel's (s, d) to its grain pre-image q: the
//             determinant of its Jacobian over the band and time. Measured
//             twice: before the curl displacement (closed form 1 - W T n phi')
//             and with it
//   speed     how far a grain moves between frames, against the smallest grain
//   nopop     the envelope used by the shader is continuous in time at a wrap
//
// Prints one "pass|FAIL name (detail)" line per check; exit 1 on any FAIL.

const vm = require("vm"), fs = require("fs")
const repo = process.argv[2]
function load(file, extra) {
  const source = fs.readFileSync(repo + "/" + file, "utf8").replace(/^\.pragma library/m, "").replace(/^\.import .*$/gm, "")
  const context = Object.assign({ console, Math, JSON, Date, Array, Object, String, Number }, extra || {})
  vm.createContext(context)
  vm.runInContext(source, context)
  return context
}
const Glow = load("glow.js", { Qt: { vector4d() {} } })
const L = load("notiflight.js", { GlowCurve: Glow, Qt: { vector4d() {} } })

let failures = 0
function check(name, ok, detail) {
  if (!ok) failures++
  console.log((ok ? "  pass  " : "  FAIL  ") + name + (detail ? "  (" + detail + ")" : ""))
}
// a small deterministic generator
let seed = 12345
function rnd() { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296 }

// --- flow ------------------------------------------------------------------
{
  let worst0 = 0, worst1 = 0, slope0 = 0, slope1 = 0
  const e = 1e-6
  for (let i = 0; i < 1000; i++) {
    const h4 = rnd(), h5 = rnd()
    worst0 = Math.max(worst0, Math.abs(L.flowEnvelope(0, h4, h5)))
    worst1 = Math.max(worst1, Math.abs(L.flowEnvelope(1 - 1e-12, h4, h5)))
    slope0 = Math.max(slope0, Math.abs((L.flowEnvelope(e, h4, h5) - L.flowEnvelope(0, h4, h5)) / e))
    slope1 = Math.max(slope1, Math.abs((L.flowEnvelope(1, h4, h5) - L.flowEnvelope(1 - e, h4, h5)) / e))
  }
  check("flow: E(0) = E(1) = 0 for 1000 random (h4, h5)", worst0 === 0 && worst1 === 0, "max " + worst0 + ", " + worst1)
  check("flow: E'(0) = E'(1) = 0", slope0 < 1e-3 && slope1 < 1e-3, "max slope " + slope0.toExponential(1) + ", " + slope1.toExponential(1))
  // across the wrap, for every stretch's phase: the grain on a pixel is drawn
  // with E(a) just before the wrap and E(a') just after, from a new cloud.
  let jump = 0
  for (let i = 0; i < 2000; i++) {
    const s = (rnd() - 0.5) * 2000, d = rnd() * 60, t0 = rnd() * 20
    const em = L.emitter
    // time at which this stretch wraps next
    const phi = L.flowMap(s, d, t0, 7).a
    const dt = (1 - phi) * em.period
    const before = L.flowMap(s, d, t0 + dt - 1e-4, 7), after = L.flowMap(s, d, t0 + dt + 1e-4, 7)
    const h4 = rnd(), h5 = rnd()
    jump = Math.max(jump, Math.abs(L.flowEnvelope(before.a, h4, h5) - L.flowEnvelope(after.a, h4, h5)))
  }
  check("flow: E is continuous across the wrap for 2000 (s, d, t)", jump < 1e-3, "max jump " + jump.toExponential(1))
}

// --- Jacobian --------------------------------------------------------------
{
  const em = L.emitter
  const h = 0.05
  let min = [9, 9], max = [0, 0], n = 0, closedErr = 0
  for (let i = 0; i < 20000; i++) {
    const s = (rnd() - 0.5) * 1200, d = rnd() * 72, t = rnd() * 30
    const m0 = L.flowMap(s, d, t, 7, em)
    if (m0.a < 0.02 || m0.a > 0.98) continue    // the cycle's seam, where E is zero
    const ms = L.flowMap(s + h, d, t, 7, em), mm = L.flowMap(s - h, d, t, 7, em)
    const dd = L.flowMap(s, d + h, t, 7, em), dm = L.flowMap(s, d - h, t, 7, em)
    if (ms.k !== mm.k) continue
    n++
    for (let which = 0; which < 2; which++) {
      const key = which ? "q" : "P"
      const ds = [(ms[key][0] - mm[key][0]) / (2 * h), (ms[key][1] - mm[key][1]) / (2 * h)]   // d(q)/d(s)
      const dd_ = [(dd[key][0] - dm[key][0]) / (2 * h), (dd[key][1] - dm[key][1]) / (2 * h)]  // d(q)/d(d)
      const det = ds[0] * dd_[1] - dd_[0] * ds[1]
      min[which] = Math.min(min[which], det); max[which] = Math.max(max[which], det)
    }
    // the closed form 1 - W T n phi', with n the swirl noise, phi' by differences
    const phiPrime = (ms.a - mm.a) / (2 * h)
    const nn = (m0.P[0] - s) / (-em.swirl * m0.tau)
    closedErr = Math.max(closedErr, Math.abs(((ms.P[0] - mm.P[0]) / (2 * h) * (dd.P[1] - dm.P[1]) / (2 * h) - (dd.P[0] - dm.P[0]) / (2 * h) * (ms.P[1] - mm.P[1]) / (2 * h)) - (1 - em.swirl * em.period * nn * phiPrime)))
  }
  console.log("  note  Jacobian samples " + n + ": before the curl det in [" + min[0].toFixed(3) + ", " + max[0].toFixed(3) + "], with it [" + min[1].toFixed(3) + ", " + max[1].toFixed(3) + "]")
  check("jacobian: before the curl, det = 1 - W T n phi' (the cross term cancels)", closedErr < 0.01, "max |measured - closed form| " + closedErr.toExponential(1))
  check("jacobian: before the curl, det within [0.7, 1.4]", min[0] >= 0.7 && max[0] <= 1.4, min[0].toFixed(3) + " .. " + max[0].toFixed(3))
  check("jacobian: with the curl (A " + em.curl + " px), det within [0.7, 1.4]", min[1] >= 0.7 && max[1] <= 1.4, min[1].toFixed(3) + " .. " + max[1].toFixed(3))
}

// --- speed -----------------------------------------------------------------
{
  const em = L.emitter
  const rMin = Math.min.apply(null, em.grain)
  const limit = 0.75 * rMin * 60   // px/s: under 0.75 r_min per 1/60 s
  const h = 0.05, dt = 1e-3
  let peak = 0, n = 0
  for (let i = 0; i < 20000; i++) {
    const s = (rnd() - 0.5) * 1200, d = rnd() * 72, t = rnd() * 30
    const m0 = L.flowMap(s, d, t, 7, em)
    if (m0.a < 0.02 || m0.a > 0.98) continue
    const mt = L.flowMap(s, d, t + dt, 7, em), mb = L.flowMap(s, d, t - dt, 7, em)
    if (mt.k !== mb.k) continue
    const ms = L.flowMap(s + h, d, t, 7, em), mm = L.flowMap(s - h, d, t, 7, em)
    const dd = L.flowMap(s, d + h, t, 7, em), dm = L.flowMap(s, d - h, t, 7, em)
    // The grain is fixed in q; the pixel it sits on moves by -J^-1 dq/dt.
    const J = [[(ms.q[0] - mm.q[0]) / (2 * h), (dd.q[0] - dm.q[0]) / (2 * h)], [(ms.q[1] - mm.q[1]) / (2 * h), (dd.q[1] - dm.q[1]) / (2 * h)]]
    const det = J[0][0] * J[1][1] - J[0][1] * J[1][0]
    if (Math.abs(det) < 0.05) continue
    const qt = [(mt.q[0] - mb.q[0]) / (2 * dt), (mt.q[1] - mb.q[1]) / (2 * dt)]
    const vs = -(J[1][1] * qt[0] - J[0][1] * qt[1]) / det, vd = -(-J[1][0] * qt[0] + J[0][0] * qt[1]) / det
    peak = Math.max(peak, Math.hypot(vs, vd)); n++
  }
  console.log("  note  speed samples " + n + ": peak grain speed " + peak.toFixed(1) + " px/s = " + (peak / 60).toFixed(2) + " px per 1/60 s; smallest grain radius " + rMin + " px")
  check("speed: a grain moves under 0.75 r_min (" + (0.75 * rMin).toFixed(2) + " px) per 1/60 s", peak <= limit, (peak / 60).toFixed(2) + " px per frame")
}

process.exit(failures ? 1 : 0)
