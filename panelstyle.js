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

// ---------------------------------------------------------------- measuring

// Below this distance (of 765) two pixels are the same paint: renderer noise
// and 8-bit rounding of a composited translucent colour.
var SAME = 6

// A glyph's core: the pixels within this share of the strongest difference.
// Anti-aliased edge pixels are a blend of ink and backdrop and always lie
// below it; a stem thinner than a pixel never reaches full ink at all, which
// is why `CORE` is a share of the strongest pixel and not a fixed colour.
var CORE = 0.9

// A luminance histogram that remembers one pixel per bin, so the median of a
// few thousand pixels costs one pass and no array: the shell's engine has no
// typed-array sort, and a comparator sort is most of the budget.
function Histo() {
  this.n = 0
  this.count = new Uint32Array(1024)
  this.at = new Int32Array(1024)
}
Histo.prototype.add = function (l, i) {
  var bin = (l * 1023) | 0
  if (this.count[bin]++ === 0) this.at[bin] = i
  this.n++
}
// {at, bin} of the median: the first pixel seen in its bin.
Histo.prototype.median = function () {
  var half = this.n >> 1, seen = 0, bin
  for (bin = 0; bin < 1024; bin++) { seen += this.count[bin]; if (seen > half) break }
  return this.at[bin < 1024 ? bin : 1023]
}

// Text. `a` is the rect as drawn, `b` the same rect with every found item
// hidden (both over the notch colour). The ink is the core of what differs
// most; the backdrop is every pixel of `b`, and the ratio is the ink against
// the backdrop pixel it reads worst on. `painted` false means nothing was
// drawn in the rect (A equals B): clipped, transparent or hidden text is not
// a contrast failure and does not count.
//
// stride > 1 reads every stride-th pixel along both axes.
//
// Written for the shell's JavaScript engine, which is slow per operation:
// one pass for the differences, the luminances only of the core, and the
// worst backdrop found as the nearest luminance on each side of the ink
// (the ratio is monotonic on either side of it) with a one-pixel cache.
function textRatio(a, b, stride) {
  stride = stride || 1
  var da = a.data, db = b.data, w = a.w, h = a.h
  var diff = new Uint16Array(w * h)
  var maxD = 0, x, y, p, i, d
  for (y = 0; y < h; y += stride) {
    for (x = 0; x < w; x += stride) {
      p = y * w + x; i = p << 2
      d = da[i] - db[i]; if (d < 0) d = -d
      var e = da[i + 1] - db[i + 1]; d += e < 0 ? -e : e
      e = da[i + 2] - db[i + 2]; d += e < 0 ? -e : e
      diff[p] = d
      if (d > maxD) maxD = d
    }
  }
  if (maxD <= SAME) return { painted: false, ratio: 21, maxDiff: maxD, ink: null, back: null }
  // the core: median luminance of the pixels within CORE of the strongest
  var cut = maxD * CORE, core = new Histo(), cr = -1, cg = -1, cb = -1, cl = 0
  for (y = 0; y < h; y += stride) {
    for (x = 0; x < w; x += stride) {
      p = y * w + x
      if (diff[p] >= cut) {
        i = p << 2
        if (da[i] !== cr || da[i + 1] !== cg || da[i + 2] !== cb) { cr = da[i]; cg = da[i + 1]; cb = da[i + 2]; cl = lum255(cr, cg, cb) }
        core.add(cl, i)
      }
    }
  }
  var mid = core.median()
  var ink = [da[mid], da[mid + 1], da[mid + 2]], li = lum255(ink[0], ink[1], ink[2])
  // the backdrop pixels nearest the ink's luminance, below and above it
  var below = -1, above = 99, belowAt = -1, aboveAt = -1
  var pr = -1, pg = -1, pb = -1
  for (y = 0; y < h; y += stride) {
    for (x = 0; x < w; x += stride) {
      i = (y * w + x) << 2
      var r = db[i], g = db[i + 1], bl = db[i + 2]
      if (r === pr && g === pg && bl === pb) continue
      pr = r; pg = g; pb = bl
      var lb = lum255(r, g, bl)
      if (lb <= li) { if (lb > below) { below = lb; belowAt = i } }
      else if (lb < above) { above = lb; aboveAt = i }
    }
  }
  var worst = 99, wi = 0
  if (belowAt >= 0) { worst = ratio255(li, below); wi = belowAt }
  if (aboveAt >= 0) { var ra = ratio255(li, above); if (ra < worst) { worst = ra; wi = aboveAt } }
  return { painted: true, ratio: worst, maxDiff: maxD, ink: ink, back: [db[wi], db[wi + 1], db[wi + 2]], core: core.n }
}

// Pixels from a mark's own edge that are always read, however sparse the rest.
var EDGE = 3

// A mark. `a` is the rect and `ring` the backdrop around it, as one flat
// pixel region (the ring 3 px outside the rect), both from the grab with the
// text hidden, so a label on a button is not part of the button. The
// backdrop's colour is the ring's median; the ink is the median of the strongest
// half (by count) of the rect's pixels that differ from it, so a filled
// button, an outline, a ring and a thin icon are all "the pixels that are not
// the backdrop", and anti-aliased rim pixels are not the ink. Nothing
// differing is a mark that cannot be seen: ratio 1.
//
// `band` (device pixels, 0 for none) is for an OUTLINE -- a mark whose fill is
// transparent and whose border is the mark: only that many pixels in from the
// edge are the ink. Without it the interior of a card with an outline would
// outweigh the outline itself.
//
// `core` (text read without a grab B, "light" mode): the ink is the core of the
// strongest difference, as in `textRatio`, and the backdrop is the ring alone.
function markRatio(a, ring, stride, band, core) {
  stride = stride || 1
  band = band || 0
  var da = a.data, rd = ring.data, n = rd.length >> 2, k, i
  if (!n) return { painted: false, ratio: 21, ink: null, back: null }
  var m = Math.ceil(n / stride), rl = new Float64Array(m), rh = new Histo(), pr = -1, pg = -1, pb = -1, pl = 0
  for (k = 0, i = 0; k < m; k++, i += 4 * stride) {
    if (rd[i] !== pr || rd[i + 1] !== pg || rd[i + 2] !== pb) { pr = rd[i]; pg = rd[i + 1]; pb = rd[i + 2]; pl = lum255(pr, pg, pb) }
    rl[k] = pl
    rh.add(pl, i)
  }
  // a ring pixel of the median luminance stands for "what is around it"
  var bi = rh.median()
  var bg0 = rd[bi], bg1 = rd[bi + 1], bg2 = rd[bi + 2]
  var w = a.w, h = a.h, diff = new Uint16Array(w * h), hist = new Uint32Array(766), total = 0, x, y, p, d
  var edge = EDGE * stride, full
  for (y = 0; y < h; y += (band || y < edge || y >= h - edge) ? 1 : stride) {
    full = y < band || y >= h - band || (!band && (y < edge || y >= h - edge))
    for (x = 0; x < w; x += band ? (full || x < band || x >= w - band ? 1 : w - 2 * band) : ((full || x < edge || x >= w - edge) ? 1 : stride)) {
      p = y * w + x; i = p << 2
      d = da[i] - bg0; if (d < 0) d = -d
      var e = da[i + 1] - bg1; d += e < 0 ? -e : e
      e = da[i + 2] - bg2; d += e < 0 ? -e : e
      diff[p] = d
      if (d > SAME) { hist[d]++; total++ }
    }
  }
  if (!total) return { painted: true, ratio: 1, ink: null, back: [bg0, bg1, bg2], nInk: 0 }
  // the difference at which half of the differing pixels are stronger
  var cut = 765, above = 0
  if (core) {
    cut = 765
    while (cut > SAME && hist[cut] === 0) cut--
    cut = Math.max(SAME + 1, Math.floor(cut * CORE))
  } else {
    while (cut > SAME && above + hist[cut] < total / 2) { above += hist[cut]; cut-- }
  }
  var body = new Histo(), cr = -1, cg = -1, cb = -1, cl = 0
  for (y = 0; y < h; y += (band || y < edge || y >= h - edge) ? 1 : stride) {
    full = y < band || y >= h - band || (!band && (y < edge || y >= h - edge))
    for (x = 0; x < w; x += band ? (full || x < band || x >= w - band ? 1 : w - 2 * band) : ((full || x < edge || x >= w - edge) ? 1 : stride)) {
      p = y * w + x
      if (diff[p] >= cut) {
        i = p << 2
        if (da[i] !== cr || da[i + 1] !== cg || da[i + 2] !== cb) { cr = da[i]; cg = da[i + 1]; cb = da[i + 2]; cl = lum255(cr, cg, cb) }
        body.add(cl, i)
      }
    }
  }
  var mi = body.median(), li = lum255(da[mi], da[mi + 1], da[mi + 2])
  var below = -1, over = 99
  for (k = 0; k < m; k++) { var l = rl[k]; if (l <= li) { if (l > below) below = l } else if (l < over) over = l }
  var worst = 99
  if (below >= 0) worst = ratio255(li, below)
  if (over < 99) { var ra = ratio255(li, over); if (ra < worst) worst = ra }
  return { painted: true, ratio: worst, ink: [da[mi], da[mi + 1], da[mi + 2]], back: [bg0, bg1, bg2], nInk: body.n }
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
//   opts.trustEnabled     the same for `enabled`: the host is disabled until
//                         it is shown, and `enabled` reads the EFFECTIVE value,
//                         so a disabled control cannot be told from one under
//                         a disabled host. Then it is measured like any other
//
// Skipped: disabled items (WCAG 1.4.3, and their subtree), empty text, zero
// size, and anything with an effective opacity of 0. A mark is only what
// declares itself (`uiMark: true`); a focusable item is not one, because an
// outline button's interior is the backdrop and would read 1:1 against it.
function findRects(root, opts) {
  opts = opts || {}
  var cap = opts.cap || 400
  var trust = opts.trustVisible !== false
  var trustEnabled = opts.trustEnabled !== false
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
    if (trustEnabled && item.enabled === false) return
    var kids = item.children || []
    var own = null
    if (!isRoot) {
      if (isText(item)) own = { role: "text", rect: textRectOf(item), empty: item.text === "" }
      else if (item.uiMark === true) {
        // a transparent Rectangle with a border is an outline: the border is the mark
        var bw = item.border && item.border.width > 0 && item.color && item.color.a === 0 ? item.border.width : 0
        own = { role: "ui", rect: { x: 0, y: 0, w: item.width, h: item.height }, empty: false, band: bw }
      }
    }
    if (own && !own.empty && own.rect.w > 0 && own.rect.h > 0) {
      seen++
      var p = map(item, own.rect.x, own.rect.y), q = map(item, own.rect.x + own.rect.w, own.rect.y + own.rect.h)
      var x0 = Math.max(0, Math.min(p.x, q.x)), y0 = Math.max(0, Math.min(p.y, q.y))
      var x1 = Math.min(W, Math.max(p.x, q.x)), y1 = Math.min(H, Math.max(p.y, q.y))
      if (x1 > x0 && y1 > y0 && out.length < cap) {
        out.push({ item: item, role: own.role, band: own.band || 0, x: x0, y: y0, w: x1 - x0, h: y1 - y0,
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

// How far below the floor a measured ratio may read and still pass. Thin
// text never reaches full ink in pixels (an anti-aliased stem of a regular
// 8-12 px face peaks at 85-95 % coverage), so a colour that is 4.56:1 on
// paper reads 4.2-4.4 as pixels, and a light 10 px face 3.9. 0.4 lets a
// colour `lift`ed to 4.5 pass at regular weight from 8 px up, and lets bold or
// large text 4.1 pass: the leak is the price of not knowing the font.
// Marks are flat paint and read exact. The sweep that sets this is
// docs/panelstyle-phase1.md (fixture `antialias`).
var TOLERANCE = { text: 0.4, ui: 0.0 }

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

// How sparsely a rect of w x h pixels is read: every stride-th pixel along
// each axis, so a rect costs about 24 000 samples however large it is (the
// shell's engine does roughly 5 000 pixels a millisecond, dev/panelstyle.sh).
// Text is read evenly; a mark is always read in full at its edge
// (`markRatio`), where outlines live.
var SAMPLES = 24000
function strideFor(w, h) { return Math.max(1, Math.min(8, Math.ceil(Math.sqrt(w * h / SAMPLES) - 1e-9))) }

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
