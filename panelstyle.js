.pragma library

// The contrast rule of plan-surface-v2.md, as pure functions: what a panel's
// pixels have to clear, and how a colour is moved until it does.
//
// Plain JavaScript with a QML pragma on top, like platform.js, so node tests
// the exact code the shell runs (dev/panelstyle.sh) and PanelGuard.qml only
// has to get pixels out of the scene graph.
//
// A colour here is {r, g, b, a}, each 0..1 (a Qt `color` already is one), a
// "#rrggbb" string or Qt's "#aarrggbb". Pixels are bytes: a {w, h, data}
// region with data laid out R G B A per pixel, as Canvas.getImageData
// returns them. Every region handed to the measurer is OPAQUE: PanelGuard
// composites the grab over the notch's colour first, so a translucent panel
// is measured as it lands.
//
// ONE contrast. `parse` .. `lift` below are the body of
// omarchy-ui/ui/tokens.js (the kit), which is itself `Bar.qml`'s
// `luminance`/`contrast` unchanged. The only edit is that the sRGB channel
// curve is hoisted out of `luminance` so the byte lookup table below
// is built by the same function instead of a second one; dev/panelstyle.sh
// checks the three agree on 200 pairs to 1e-9 and `lift` on 1000 colours.

// ---------------------------------------------------------------- colour

function parse(c) {
  if (c && typeof c === "object") {
    return { r: Number(c.r), g: Number(c.g), b: Number(c.b), a: c.a === undefined ? 1 : Number(c.a) }
  }
  var s = String(c).replace(/^\s+|\s+$/g, "")
  var short = /^#([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])$/.exec(s)
  if (short) s = "#" + short[1] + short[1] + short[2] + short[2] + short[3] + short[3]
  var m = /^#([0-9a-fA-F]{6})$/.exec(s)
  if (m) return { r: parseInt(m[1].substr(0, 2), 16) / 255, g: parseInt(m[1].substr(2, 2), 16) / 255, b: parseInt(m[1].substr(4, 2), 16) / 255, a: 1 }
  m = /^#([0-9a-fA-F]{8})$/.exec(s)
  if (m) return { a: parseInt(m[1].substr(0, 2), 16) / 255, r: parseInt(m[1].substr(2, 2), 16) / 255, g: parseInt(m[1].substr(4, 2), 16) / 255, b: parseInt(m[1].substr(6, 2), 16) / 255 }
  throw new Error("not a colour: " + c)
}

function byte(v) { return Math.max(0, Math.min(255, Math.round(v * 255))) }
function two(n) { return (n < 16 ? "0" : "") + n.toString(16) }

function hex(c) {
  c = parse(c)
  var rgb = two(byte(c.r)) + two(byte(c.g)) + two(byte(c.b))
  return c.a >= 1 ? "#" + rgb : "#" + two(byte(c.a)) + rgb
}

function rgba(r, g, b, a) { return { r: r, g: g, b: b, a: a === undefined ? 1 : a } }

// `top` composited over `bottom`. Opaque when `bottom` is.
function over(top, bottom) {
  top = parse(top); bottom = parse(bottom)
  var a = top.a + bottom.a * (1 - top.a)
  if (a <= 0) return rgba(0, 0, 0, 0)
  function ch(t, b) { return (t * top.a + b * bottom.a * (1 - top.a)) / a }
  return rgba(ch(top.r, bottom.r), ch(top.g, bottom.g), ch(top.b, bottom.b), a)
}

// WCAG 2.x, the body of omarchy-notch Bar.qml's luminance/contrast.
function channel(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }

function luminance(value) {
  var c = parse(value)
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
}

function contrast(a, b) {
  var la = luminance(a), lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

var WHITE = rgba(1, 1, 1, 1)
var BLACK = rgba(0, 0, 0, 1)

function extreme(against) { return contrast(WHITE, against) >= contrast(BLACK, against) ? WHITE : BLACK }

var TEXT = 4.5   // text, no large-text relaxation
var MARK = 3     // a control's fill or border, an icon, a ring, a progress fill

// The colour moved toward whichever of white and black contrasts more with
// `against` (white if tied), one 8-bit step at a time, each channel rounded
// away from where it started, stopping at the first step that reaches
// `floor`; a colour that already passes comes back unchanged. The better
// extreme always reaches 4.58:1 on any backdrop, so this ends.
//
// The kit's body, named `liftTo` here; `lift` below is the host's signature.
function liftTo(color, against, floor) {
  var bg = parse(against)
  var c = over(color, bg)   // a translucent colour is judged as it lands on the backdrop
  if (contrast(c, bg) >= floor) return rgba(c.r, c.g, c.b, 1)
  var t = extreme(bg)
  var from = [byte(c.r), byte(c.g), byte(c.b)], to = [byte(t.r), byte(t.g), byte(t.b)]
  for (var k = 1; k <= 255; k++) {
    var out = []
    for (var i = 0; i < 3; i++) {
      var v = from[i] + (to[i] - from[i]) * k / 255
      out.push((to[i] >= from[i] ? Math.ceil(v - 1e-9) : Math.floor(v + 1e-9)) / 255)
    }
    var next = rgba(out[0], out[1], out[2], 1)
    if (contrast(next, bg) >= floor) return next
  }
  return t
}

function floorOf(role) { return role === "text" ? TEXT : MARK }

// `surfaceHost.lift(color, role, against)` of plan-surface-v2.md section 2.
// `against` defaults to the notch's colour, black.
function lift(color, role, against) {
  return liftTo(color, against === undefined ? BLACK : against, floorOf(role))
}

// ---------------------------------------------------------------- bytes

// The same curve as `channel`, once per byte value: a pixel's luminance is
// three lookups, which is what lets a few hundred thousand pixels be
// compared inside the budget.
var CURVE = (function () {
  var t = []
  for (var i = 0; i < 256; i++) t.push(channel(i / 255))
  return t
})()

function lum255(r, g, b) { return 0.2126 * CURVE[r] + 0.7152 * CURVE[g] + 0.0722 * CURVE[b] }

function ratio255(la, lb) {
  return la >= lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05)
}

// Rec. 601-ish distance between two pixels, 0..765: cheap, only used to ask
// "do these two differ" and "which differs most", never as a contrast.
function dist(data, i, other, j) {
  var d = data[i] - other[j]; if (d < 0) d = -d
  var e = data[i + 1] - other[j + 1]; if (e < 0) e = -e
  var f = data[i + 2] - other[j + 2]; if (f < 0) f = -f
  return d + e + f
}

// ---------------------------------------------------------------- measuring

// Below this distance (of 765) two pixels are the same paint: renderer noise
// and 8-bit rounding of a composited translucent colour.
var SAME = 6

// A glyph's core: the pixels within this share of the strongest difference.
// Anti-aliased edge pixels are a blend of ink and backdrop and always lie
// below it; a stem thinner than a pixel never reaches full ink at all, which
// is why `CORE` is a share of the strongest pixel and not a fixed colour.
var CORE = 0.9

// Text. `a` is the rect as drawn, `b` the same rect with every found item
// hidden (both over the notch colour). The ink is the core of what differs
// most; the backdrop is every pixel of `b`, and the ratio is the ink against
// the backdrop pixel it reads worst on. `painted` false means nothing was
// drawn in the rect (A equals B): clipped, transparent or hidden text is not
// a contrast failure and does not count.
//
// stride > 1 reads every stride-th pixel along both axes.
function textRatio(a, b, stride) {
  stride = stride || 1
  var da = a.data, db = b.data, w = a.w, h = a.h
  var maxD = 0
  for (var y = 0; y < h; y += stride) {
    for (var x = 0; x < w; x += stride) {
      var i = (y * w + x) * 4
      var d = dist(da, i, db, i)
      if (d > maxD) maxD = d
    }
  }
  if (maxD <= SAME) return { painted: false, ratio: 21, maxDiff: maxD, ink: null, back: null }
  // the core: median luminance of the pixels within CORE of the strongest
  var core = [], coreAt = []
  for (y = 0; y < h; y += stride) {
    for (x = 0; x < w; x += stride) {
      i = (y * w + x) * 4
      if (dist(da, i, db, i) >= maxD * CORE) { core.push(lum255(da[i], da[i + 1], da[i + 2])); coreAt.push(i) }
    }
  }
  var order = core.map(function (v, k) { return k }).sort(function (p, q) { return core[p] - core[q] })
  var mid = coreAt[order[order.length >> 1]]
  var ink = [da[mid], da[mid + 1], da[mid + 2]]
  var li = lum255(ink[0], ink[1], ink[2])
  var worst = 99, wi = 0
  for (y = 0; y < h; y += stride) {
    for (x = 0; x < w; x += stride) {
      i = (y * w + x) * 4
      var r = ratio255(li, lum255(db[i], db[i + 1], db[i + 2]))
      if (r < worst) { worst = r; wi = i }
    }
  }
  return { painted: true, ratio: worst, maxDiff: maxD, ink: ink, back: [db[wi], db[wi + 1], db[wi + 2]], core: core.length }
}

// A mark. `a` is the rect as drawn; `ring` is the backdrop around it, as a
// {w, h, data} strip list flattened to one pixel region (the ring 3 px
// outside the rect, from the grab with the text hidden). The backdrop's
// colour is the ring's median; the ink is the median of the rect's pixels
// that differ from it, so a filled button, an outline, a ring and a thin
// icon are all "the pixels that are not the backdrop". Nothing differing
// is a mark that cannot be seen: ratio 1.
function markRatio(a, ring, stride) {
  stride = stride || 1
  var da = a.data
  var rl = []
  for (var k = 0; k < ring.data.length; k += 4 * stride) rl.push(lum255(ring.data[k], ring.data[k + 1], ring.data[k + 2]))
  if (!rl.length) return { painted: false, ratio: 21, ink: null, back: null }
  var sorted = rl.slice().sort(function (p, q) { return p - q })
  var back = sorted[sorted.length >> 1]
  // the backdrop pixel nearest the ring's median luminance stands for "what
  // is around it" when asking which of the rect's pixels differ
  var bi = 0, bd = 9
  for (k = 0; k < rl.length; k++) { var dd = Math.abs(rl[k] - back); if (dd < bd) { bd = dd; bi = k * stride * 4 } }
  var bg = [ring.data[bi], ring.data[bi + 1], ring.data[bi + 2]]
  var diff = []
  for (var y = 0; y < a.h; y += stride) {
    for (var x = 0; x < a.w; x += stride) {
      var i = (y * a.w + x) * 4
      var d = Math.abs(da[i] - bg[0]) + Math.abs(da[i + 1] - bg[1]) + Math.abs(da[i + 2] - bg[2])
      if (d > SAME) diff.push({ i: i, l: lum255(da[i], da[i + 1], da[i + 2]), d: d })
    }
  }
  if (!diff.length) return { painted: true, ratio: 1, ink: null, back: bg, nInk: 0 }
  // a mark's ink is its body, not its anti-aliased rim: the median of the
  // pixels in the strongest half of the difference
  diff.sort(function (p, q) { return q.d - p.d })
  var top = diff.slice(0, Math.max(1, Math.ceil(diff.length / 2)))
  top.sort(function (p, q) { return p.l - q.l })
  var m = top[top.length >> 1]
  var worst = 99
  for (k = 0; k < rl.length; k++) { var r = ratio255(m.l, rl[k]); if (r < worst) worst = r }
  return { painted: true, ratio: worst, ink: [da[m.i], da[m.i + 1], da[m.i + 2]], back: bg, nInk: diff.length }
}

// ---------------------------------------------------------------- the walk

// Alignment enums of Text, so this runs on plain objects under node.
var ALIGN = { left: 1, right: 2, hcenter: 4, top: 32, bottom: 64, vcenter: 128 }

function isText(item) {
  return typeof item.text === "string" && typeof item.contentWidth === "number" &&
         typeof item.contentHeight === "number" && item.font !== undefined
}

function textRectOf(item) {
  // The painted block inside the item, so a Text that fills its parent is
  // measured where its glyphs are, not over everything it overlaps.
  var w = item.width, h = item.height
  var cw = Math.min(w, item.contentWidth), ch = Math.min(h, item.contentHeight)
  if (!(cw > 0) || !(ch > 0)) return { x: 0, y: 0, w: w, h: h }
  var ha = item.horizontalAlignment, va = item.verticalAlignment
  var x = ha === ALIGN.right ? w - cw : ha === ALIGN.hcenter ? (w - cw) / 2 : 0
  var y = va === ALIGN.bottom ? h - ch : va === ALIGN.vcenter ? (h - ch) / 2 : 0
  return { x: x, y: y, w: cw, h: ch }
}

// Every visible text and every declared mark under `root`, with the rect it
// covers in `root`'s coordinates. It finds rectangles and nothing else:
// what they look like is the grab's business.
//
//   opts.map(item, x, y)  item point -> root point (mapToItem; default adds offsets)
//   opts.cap              most rects kept (400)
//   opts.trustVisible     false when `root` itself is not visible (the host
//                         fades the panel in, so before the reveal every
//                         descendant reads visible=false): then `visible`
//                         says nothing and the pixels decide what was drawn
//
// Skipped: disabled items (WCAG 1.4.3, and their subtree), empty text, zero
// size, and anything with an effective opacity of 0. A mark is only what
// declares itself (`uiMark: true`); a focusable item is not one, because an
// outline button's interior is the backdrop and would read 1:1 against it.
function findRects(root, opts) {
  opts = opts || {}
  var cap = opts.cap || 400
  var trust = opts.trustVisible !== false
  var map = opts.map || function (item, x, y) {
    for (var p = item; p && p !== root; p = p.parent) { x += p.x || 0; y += p.y || 0 }
    return { x: x, y: y }
  }
  var out = [], seen = 0
  var W = root.width, H = root.height

  function visit(item, depth, opacity, isRoot) {
    if (!item || depth > 64) return
    var op = opacity * (item.opacity === undefined ? 1 : item.opacity)
    if (op <= 0.01) return
    if (!isRoot && trust && item.visible === false) return
    if (item.enabled === false) return
    var kids = item.children || []
    var own = null
    if (!isRoot) {
      if (isText(item)) own = { role: "text", rect: textRectOf(item), empty: item.text === "" }
      else if (item.uiMark === true) own = { role: "ui", rect: { x: 0, y: 0, w: item.width, h: item.height }, empty: false }
    }
    if (own && !own.empty && own.rect.w > 0 && own.rect.h > 0) {
      seen++
      var p = map(item, own.rect.x, own.rect.y), q = map(item, own.rect.x + own.rect.w, own.rect.y + own.rect.h)
      var x0 = Math.max(0, Math.min(p.x, q.x)), y0 = Math.max(0, Math.min(p.y, q.y))
      var x1 = Math.min(W, Math.max(p.x, q.x)), y1 = Math.min(H, Math.max(p.y, q.y))
      if (x1 > x0 && y1 > y0 && out.length < cap) {
        out.push({ item: item, role: own.role, x: x0, y: y0, w: x1 - x0, h: y1 - y0,
                   name: String(item.objectName || (own.role === "text" ? item.text : "mark")).slice(0, 32) })
      }
    }
    for (var k = 0; k < kids.length; k++) visit(kids[k], depth + 1, op, false)
  }
  visit(root, 0, 1, true)
  return { rects: out, seen: seen, capped: seen > out.length }
}

// "Laid out": a snapshot of what the walk found, so two of them can be
// compared. A sticky verdict must never come from a panel that has not
// filled in yet.
function snapshot(root, found) {
  var sig = Math.round(root.width) + "x" + Math.round(root.height) + ":" + found.rects.length
  for (var i = 0; i < found.rects.length; i++) {
    var r = found.rects[i]
    sig += "|" + Math.round(r.x) + "," + Math.round(r.y) + "," + Math.round(r.w) + "," + Math.round(r.h)
  }
  return { w: root.width, h: root.height, count: found.rects.length, sig: sig }
}

// `history` is the snapshots taken one frame apart, newest last. Laid out
// means: something to measure, a size, and the same snapshot for `frames` in
// a row.
function laidOut(history, frames) {
  frames = frames || 3
  if (history.length < frames) return false
  var last = history[history.length - 1]
  if (!(last.w > 0 && last.h > 0 && last.count > 0)) return false
  for (var i = history.length - frames; i < history.length; i++) if (history[i].sig !== last.sig) return false
  return true
}

// ---------------------------------------------------------------- verdict

// How far below the floor a measured ratio may read and still pass: the
// anti-aliased edge of thin text never reaches full ink, so a colour that is
// 4.56:1 on paper reads a little under it in pixels. Settled by
// docs/panelstyle-phase1.md.
var TOLERANCE = { text: 0.0, ui: 0.0 }

function verdict(results) {
  var worst = null, failing = null, measured = 0
  for (var i = 0; i < results.length; i++) {
    var r = results[i]
    if (!r.painted) continue
    measured++
    var need = floorOf(r.role)
    if (!worst || r.ratio / need < worst.ratio / worst.need) worst = { name: r.name, role: r.role, ratio: r.ratio, need: need }
    if (r.ratio + TOLERANCE[r.role] < need && !failing) failing = { name: r.name, role: r.role, ratio: r.ratio, need: need }
  }
  return { pass: failing === null && measured > 0, measured: measured, worst: worst, failing: failing }
}

function detail(failing) {
  return failing ? failing.name + " " + failing.ratio.toFixed(1) + ":1 < " + failing.need : ""
}

// ---------------------------------------------------------------- limits

// Every second pixel along each axis above this many.
var STRIDE_ABOVE = 200000
function strideFor(w, h) { return w * h > STRIDE_ABOVE ? 2 : 1 }

// The inset a contract-2 panel's clip wrapper takes at the left, right and
// bottom so a full-bleed fill stays inside the notch's bottom corner arcs: the
// smallest whole d for which the clip rectangle's corner lies on or inside
// the arc, 2 (r - d)^2 <= r^2.
//
// `r` is the radius SETTING (`bottomRadius`), not the clamped `bottomR` the
// Island draws with: the clamp reads the bar's width, which grows by 2d, so
// d from the clamped value is a binding loop. d is monotonic in r, so the
// setting's inset is never too small for the clamped radius.
function clipInset(r) {
  r = Math.max(0, Number(r) || 0)
  return Math.ceil(r * (1 - Math.SQRT1_2) - 1e-9)
}

// Whether the clip rectangle's bottom corner is inside a radius-r arc.
function insideArc(r, d) { return r <= 0 || 2 * (r - d) * (r - d) <= r * r + 1e-9 }
