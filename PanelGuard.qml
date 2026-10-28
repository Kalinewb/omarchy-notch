pragma ComponentBehavior: Bound
import QtQuick
import "panelstyle.js" as PS

// PROTOTYPE (plan-surface-v2.md section 4, Phase 1): reads a panel's pixels and
// says whether every text and every declared mark clears the contrast floor.
//
// Nothing here is wired into Bar.qml yet. The fixtures of dev/panelstyle.sh
// put a guard inside a plugin's panel, which the real notch draws in its real
// PanelWindow, so everything below runs in the scene graph that decides.
//
// Three things the plan left open are settled by what this does:
//
// - **Hiding for grab B is opacity 0 through a `Binding`, never `visible:
//   false`.** `visible: false` re-flows a Column, Row or Layout, so B would be
//   a different picture; opacity keeps every item where it is. A `Binding`
//   (restoreMode RestoreBindingOrValue) puts back a binding the plugin had on
//   `opacity`, which assigning the old value would not.
// - **The grab callback is the only thing waited for.** The `Image` of a
//   grab result is ready the moment its source is set, and a `Canvas` that is
//   already `available` draws and reads back at once, so A and B are read
//   inside their own callbacks with no frame spent on a Canvas paint.
// - **"Laid out" is a rule, not a delay.** The measurement starts when the
//   walk has found something to measure and the panel's size and every
//   found rect have been the same for `settleFrames` ticks; a panel that
//   never gets there ends `unsettled`, never a pass.
//
// What it measures: every visible Text/TextInput and every item that
// declares `uiMark: true` (panelstyle.js, `findRects`). Grab A is the panel
// as drawn, grab B the same with every found TEXT hidden (marks stay, so a
// label's backdrop is the button it sits on), both composited over `backdrop`
// so a translucent panel is measured as it lands. Rects are read in device
// pixels: a grab is `devicePixelRatio` times the item.
Item {
  id: guard

  visible: false

  // The panel root to measure. Not the guard's parent: the guard sits beside
  // what it measures, so its own helpers are never in the grab.
  property Item target: null
  // What a translucent panel lands on (surfaceHost.color).
  property color backdrop: "#000000"

  // Limits. Placeholders until dev/panelstyle.sh records them.
  property int maxRects: 400
  property int grabTimeoutMs: 150
  property int settleFrames: 3
  property int settleTimeoutMs: 1000
  property int recheckMs: 2000
  // The longest the arithmetic runs before it lets the event loop go.
  property int sliceMs: 4
  // How far outside a mark its backdrop is read, in logical pixels.
  property real ringPx: 3
  // How far past a text's glyph block its rect is widened, for anti-aliasing.
  property real padPx: 1
  // dev/panelstyle.sh only: also count the pixels outside the found rects
  // that differ between A and B (a hide that moved something shows here).
  property bool audit: false
  // How B hides the texts. "visible" is here only so dev/panelstyle.sh can
  // show what it does to a Column.
  property string hideBy: "opacity"
  // "full": grab A and grab B (texts hidden), every found rect measured.
  // "light": grab A only, texts only, each against the ring around its
  // glyph block. Nothing is hidden, so nothing blinks; it is what a re-check
  // of a panel on screen could use. It cannot see the backdrop under the glyphs.
  property string mode: "full"
  // Re-measure every recheckMs while true (the plan's timer, post-reveal).
  property bool rechecking: false

  readonly property bool busy: guard.run !== null
  property var result: null
  signal measured(var result)

  property var run: null
  property var hiding: []
  property bool hideNow: false
  property bool rerun: false
  property int seq: 0

  function now() { return new Date().getTime() }

  // Start a measurement. One at a time: a call while busy measures again when
  // the running one finishes, so the answer is for the panel as it is after.
  function measure(reason) {
    if (!guard.target) return
    if (guard.run) { guard.rerun = true; return }
    guard.seq += 1
    guard.run = { id: guard.seq, reason: String(reason || ""), t0: now(), history: [], found: null, ticks: 0,
                  walkMs: 0, walks: 0 }
    settleTimer.restart()
    tick()
  }

  // What the host is doing to the panel while it is measured: before the
  // reveal it is invisible and at opacity 0.
  function ancestry() {
    var opacity = 1
    for (var p = guard.target; p; p = p.parent) if (p.opacity !== undefined) opacity *= p.opacity
    return { visible: guard.target.visible, enabled: guard.target.enabled, opacity: Number(opacity.toFixed(3)) }
  }

  function walk() {
    var t = now()
    var found = PS.findRects(guard.target, {
      cap: guard.maxRects,
      trustVisible: guard.target.visible,
      trustEnabled: guard.target.enabled,
      map: function (item, x, y) { return item.mapToItem(guard.target, x, y) }
    })
    guard.run.walkMs += now() - t
    guard.run.walks += 1
    return found
  }

  // The panel's layout signature as it is right now, filtered as the walk is.
  function currentSig() {
    var found = walk()
    if (guard.mode === "light") found.rects = found.rects.filter(function (q) { return q.role === "text" })
    return PS.snapshot(guard.target, found).sig
  }

  // Something moved between the settle tick that chose the rects and the
  // frame the grab was taken in: the rects no longer sit on their pixels.
  // Throw the picture away and settle again.
  function moved(r) {
    var last = r.history.length ? r.history[r.history.length - 1].sig : ""
    if (currentSig() === last) return false
    guard.unhide()
    r.retries = (r.retries || 0) + 1
    r.moves = (r.moves || 0) + 1
    r.history = []
    settleTimer.restart()
    return true
  }

  // One settle tick: look at the panel, and go when it has stopped changing.
  function tick() {
    var r = guard.run
    if (!r) return
    if (!guard.target) { finish({ state: "unavailable", pass: false, why: "no target" }); return }
    r.ticks += 1
    r.found = walk()
    if (guard.mode === "light") r.found.rects = r.found.rects.filter(function (q) { return q.role === "text" })
    r.history.push(PS.snapshot(guard.target, r.found))
    if (r.history.length > 8) r.history.shift()
    // The canvas bitmap is its size times the WINDOW's pixel ratio (1.6 on a
    // fractional-scale Wayland output; Screen.devicePixelRatio says 2), the
    // same ratio a grab is taken at, so an item-sized canvas holds the picture.
    var w = Math.ceil(guard.target.width) + 2, h = Math.ceil(guard.target.height) + 2
    if (surface.width !== w || surface.height !== h) { surface.width = w; surface.height = h }
    if (PS.laidOut(r.history, guard.settleFrames) && surface.available) {
      settleTimer.stop()
      r.tSettled = now()
      grabA()
    } else if (now() - r.t0 > guard.settleTimeoutMs) {
      settleTimer.stop()
      finish({ state: "unsettled", pass: false, why: (r.retries ? "nothing painted: " : "") + (r.history.length ? r.history[r.history.length - 1].sig : "") })
    }
  }

  Timer { id: settleTimer; interval: 16; repeat: true; onTriggered: guard.tick() }

  // --- the two grabs ---------------------------------------------------------

  Timer {
    id: grabTimer
    interval: guard.grabTimeoutMs
    onTriggered: {
      // A grab that never answered: put the panel back and say so. The notch
      // reveals in v1 styling; it cannot prove, so it does not claim.
      guard.unhide()
      guard.finish({ state: "unavailable", pass: false, why: "no grab in " + guard.grabTimeoutMs + " ms" })
    }
  }

  function grabA() {
    var r = guard.run
    r.tGrabA = now()
    grabTimer.restart()
    var id = r.id
    guard.target.grabToImage(function (g) { onA(g, id) })
  }

  // The panel as drawn -> canvas -> the bytes under every rect.
  function paint(w, h) {
    var ctx = surface.getContext("2d")
    ctx.fillStyle = Qt.rgba(guard.backdrop.r, guard.backdrop.g, guard.backdrop.b, 1)
    ctx.fillRect(0, 0, w, h)
    ctx.drawImage(img, 0, 0)
    return ctx
  }

  function device(rect, sx, sy, pad, W, H) {
    var x0 = Math.max(0, Math.floor((rect.x - pad) * sx)), y0 = Math.max(0, Math.floor((rect.y - pad) * sy))
    var x1 = Math.min(W, Math.ceil((rect.x + rect.w + pad) * sx)), y1 = Math.min(H, Math.ceil((rect.y + rect.h + pad) * sy))
    return { x: x0, y: y0, w: Math.max(0, x1 - x0), h: Math.max(0, y1 - y0) }
  }

  function read(ctx, d) {
    if (d.w <= 0 || d.h <= 0) return { w: 0, h: 0, data: [] }
    return { w: d.w, h: d.h, data: ctx.getImageData(d.x, d.y, d.w, d.h).data }
  }

  // The ring around a mark, as one strip of pixels: four bands `ringPx`
  // outside the rect, clipped to the picture.
  function ringOf(ctx, d, rw, W, H) {
    var bands = [
      { x: d.x - rw, y: d.y - rw, w: d.w + 2 * rw, h: rw },
      { x: d.x - rw, y: d.y + d.h, w: d.w + 2 * rw, h: rw },
      { x: d.x - rw, y: d.y, w: rw, h: d.h },
      { x: d.x + d.w, y: d.y, w: rw, h: d.h }
    ]
    var parts = [], total = 0
    for (var i = 0; i < bands.length; i++) {
      var b = bands[i]
      var x0 = Math.max(0, b.x), y0 = Math.max(0, b.y), x1 = Math.min(W, b.x + b.w), y1 = Math.min(H, b.y + b.h)
      if (x1 <= x0 || y1 <= y0) continue
      var piece = read(ctx, { x: x0, y: y0, w: x1 - x0, h: y1 - y0 })
      parts.push(piece); total += piece.w * piece.h * 4
    }
    var data = new Uint8ClampedArray(total), at = 0
    for (i = 0; i < parts.length; i++) {
      var src = parts[i].data
      for (var k = 0; k < src.length; k++) data[at++] = src[k]
    }
    return { w: total / 4, h: 1, data: data }
  }

  // Put every hidden text back, now: `when: false` restores a Binding at once,
  // where destroying it is deferred to the event loop and would leave the text
  // hidden for another frame.
  function unhide() { guard.hideNow = false; guard.hiding = [] }

  // A callback that throws would leave the guard busy for good: a measurer
  // that cannot measure says so, and the notch treats that as "cannot prove".
  function onA(g, id) {
    try { stepA(g, id) } catch (e) { guard.unhide(); finish({ state: "error", pass: false, why: "A: " + e }) }
  }

  function onB(g, id) {
    guard.unhide()
    try { stepB(g, id) } catch (e) { finish({ state: "error", pass: false, why: "B: " + e }) }
  }

  function stepA(g, id) {
    var r = guard.run
    if (!r || r.id !== id) return
    grabTimer.stop()
    r.tA = now()
    if (!g) { finish({ state: "unavailable", pass: false, why: "grab returned nothing" }); return }
    img.source = g.url
    var W = img.sourceSize.width, H = img.sourceSize.height
    var ratio = guard.Window.window ? guard.Window.window.devicePixelRatio : 1
    if (W <= 0 || H <= 0 || W > Math.floor(surface.width * ratio) || H > Math.floor(surface.height * ratio)) {
      finish({ state: "unavailable", pass: false, why: "picture " + W + "x" + H + " in canvas " + surface.width + "x" + surface.height + " at " + ratio })
      return
    }
    if (moved(r)) return
    r.W = W; r.H = H
    r.sx = W / guard.target.width; r.sy = H / guard.target.height
    var ctx = paint(W, H)
    r.a = []
    var rects = r.found.rects
    for (var i = 0; i < rects.length; i++) {
      var d = device(rects[i], r.sx, r.sy, rects[i].role === "text" ? guard.padPx : 0, W, H)
      // a mark is judged on B, where its label is gone: only texts are read here
      r.a.push({ d: d, px: rects[i].role === "text" ? read(ctx, d) : null })
    }
    if (guard.audit) r.aFull = ctx.getImageData(0, 0, W, H).data
    if (guard.mode === "light") {
      var rwl = Math.max(1, Math.ceil(guard.ringPx * r.sx))
      r.b = []
      for (i = 0; i < rects.length; i++) r.b.push({ px: r.a[i].px, ring: ringOf(ctx, r.a[i].d, rwl, W, H) })
      r.tAread = now(); r.tBread = r.tAread; r.restoredAt = r.tAread; r.hiddenAt = r.tAread
      r.blinkFrames = 0
      r.next = 0; r.out = []
      r.parts = { text: 0, mark: 0, nText: 0, nMark: 0, pixels: 0, slices: 0, maxSlice: 0 }
      compute()
      return
    }
    r.tAread = now()
    // hide every found text, then ask for B: it is rendered at the next sync
    var texts = []
    for (i = 0; i < rects.length; i++) if (rects[i].role === "text") texts.push(rects[i])
    guard.hiding = texts
    guard.hideNow = true
    r.hiddenAt = now()
    r.frames0 = guard.frames
    grabTimer.restart()
    guard.target.grabToImage(function (gb) { onB(gb, id) })
  }

  // (onB has already put the panel back: the hide must not outlive its grab.)
  function stepB(g, id) {
    var r = guard.run
    if (!r || r.id !== id) return
    grabTimer.stop()
    r.restoredAt = now()
    r.blinkFrames = guard.frames - r.frames0
    if (!g) { finish({ state: "unavailable", pass: false, why: "grab B returned nothing" }); return }
    img.source = g.url
    if (img.sourceSize.width !== r.W || img.sourceSize.height !== r.H) {
      finish({ state: "unavailable", pass: false, why: "B is " + img.sourceSize.width + "x" + img.sourceSize.height + ", A was " + r.W + "x" + r.H })
      return
    }
    // (hiding by `visible` re-flows by design, so it is never "settled" again)
    if (guard.hideBy === "opacity" && moved(r)) return
    var ctx = paint(r.W, r.H)
    var rects = r.found.rects
    var rw = Math.max(1, Math.ceil(guard.ringPx * r.sx))
    r.b = []
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].role === "text") r.b.push({ px: read(ctx, r.a[i].d) })
      else r.b.push({ px: read(ctx, r.a[i].d), ring: ringOf(ctx, r.a[i].d, rw, r.W, r.H) })
    }
    var bFull = guard.audit ? ctx.getImageData(0, 0, r.W, r.H).data : null
    r.tBread = now()
    r.bFull = bFull
    r.out = []
    r.next = 0
    r.parts = { text: 0, mark: 0, nText: 0, nMark: 0, pixels: 0, slices: 0, maxSlice: 0 }
    compute()
  }

  // --- the numbers, in slices ------------------------------------------------------
  //
  // The pixels are in memory by now; the arithmetic is the long part (about
  // 5 000 pixels a millisecond in this engine), and one callback doing all of
  // it would hold the notch's growth for a frame or more. It runs for
  // `sliceMs` and lets the event loop go.
  function compute() {
    var r = guard.run
    if (!r) return
    try {
      var rects = r.found.rects, t0 = now()
      while (r.next < rects.length) {
        var i = r.next++, tm = now()
        var pa = r.a[i].px || r.b[i].px
        var stride = PS.strideFor(pa.w, pa.h)
        var m = rects[i].role === "text" ? (guard.mode === "light" ? PS.markRatio(pa, r.b[i].ring, stride, 0, true) : PS.textRatio(pa, r.b[i].px, stride))
                                         : PS.markRatio(r.b[i].px, r.b[i].ring, stride,
                                                        rects[i].band > 0 ? Math.min(Math.ceil(rects[i].band * r.sx) + 1, Math.floor(Math.min(pa.w, pa.h) / 2)) : 0)
        var spent = now() - tm
        if (rects[i].role === "text") { r.parts.text += spent; r.parts.nText++ } else { r.parts.mark += spent; r.parts.nMark++ }
        r.parts.pixels += pa.w * pa.h
        r.out.push({ name: rects[i].name, role: rects[i].role, ratio: m.ratio, painted: m.painted,
                     ink: m.ink, back: m.back, stride: stride, x: rects[i].x, y: rects[i].y, w: rects[i].w, h: rects[i].h })
        if (now() - t0 >= guard.sliceMs && r.next < rects.length) {
          r.parts.slices++
          r.parts.maxSlice = Math.max(r.parts.maxSlice, now() - t0)
          sliceTimer.restart()
          return
        }
      }
      r.parts.maxSlice = Math.max(r.parts.maxSlice, now() - t0)
      conclude()
    } catch (e) {
      finish({ state: "error", pass: false, why: "compute: " + e })
    }
  }

  Timer { id: sliceTimer; interval: 1; onTriggered: guard.compute() }

  function conclude() {
    var r = guard.run, rects = r.found.rects
    var v = PS.verdict(r.out)
    r.tDone = now()
    // Found something, drew none of it: the panel has not filled in (or its
    // content sits behind a `visible: false` the walk could not see before the
    // reveal). Not a verdict: settle again.
    if (v.measured === 0 && rects.length > 0 && r.tDone - r.t0 < guard.settleTimeoutMs) {
      r.retries = (r.retries || 0) + 1
      r.history = []
      settleTimer.restart()
      return
    }
    // Out of time and still nothing drawn: the same "cannot prove" as never settling.
    var res = { state: v.pass ? "pass" : (v.measured === 0 ? "unsettled" : "fail"), pass: v.pass, why: v.measured === 0 ? "nothing painted" : undefined,
                detail: PS.detail(v.failing), worst: v.worst, failing: v.failing,
                rects: r.out, found: rects.length, seen: r.found.seen, capped: r.found.capped, painted: v.measured,
                image: { w: r.W, h: r.H }, scale: r.sx }
    if (guard.audit) res.outsideDiff = outside(r.aFull, r.bFull, r)
    finish(res)
  }

  // Pixels that differ between A and B outside every found rect: zero when the
  // hide moved nothing.
  function outside(a, b, r) {
    var W = r.W, H = r.H, covered = new Uint8Array(W * H)
    for (var i = 0; i < r.a.length; i++) {
      var d = r.a[i].d
      for (var y = d.y; y < d.y + d.h; y++) for (var x = d.x; x < d.x + d.w; x++) covered[y * W + x] = 1
    }
    var n = 0
    for (var p = 0; p < W * H; p++) {
      if (covered[p]) continue
      var k = p * 4
      if (Math.abs(a[k] - b[k]) + Math.abs(a[k + 1] - b[k + 1]) + Math.abs(a[k + 2] - b[k + 2]) > PS.SAME) n++
    }
    return n
  }

  function finish(res) {
    var r = guard.run
    if (!r) return
    settleTimer.stop(); grabTimer.stop(); sliceTimer.stop()
    guard.unhide()
    var t = now()
    res.reason = r.reason
    res.ms = {
      total: t - r.t0,
      settle: (r.tSettled || t) - r.t0,
      grabA: r.tA ? r.tA - r.tGrabA : -1,
      grabB: r.restoredAt ? r.restoredAt - r.hiddenAt : -1,
      // the guard's own work between the callbacks: draw, read, hide, compute
      readA: r.tAread ? r.tAread - r.tA : -1,
      readB: r.tBread ? r.tBread - r.restoredAt : -1,
      compute: r.tDone ? r.tDone - r.tBread : -1,
      // the arithmetic alone, summed over its slices
      work: r.parts ? r.parts.text + r.parts.mark : -1,
      // the longest the main thread was held at a stretch: a read or a slice
      stall: r.tDone ? Math.max(r.tAread - r.tA, r.tBread - r.restoredAt, r.parts.maxSlice) : -1,
      walk: r.walks ? r.walkMs / r.walks : 0
    }
    res.ticks = r.ticks
    res.parts = r.parts
    res.retries = r.retries || 0
    res.moves = r.moves || 0
    res.blinkFrames = r.blinkFrames === undefined ? -1 : r.blinkFrames
    res.host = guard.target ? guard.ancestry() : null
    // false when the panel's own `visible` was false: the walk could not tell
    // a hidden item from a drawn one, and one hidden under a drawn neighbour
    // is measured as the neighbour. The host must be visible (at opacity 0).
    res.trusted = res.host ? res.host.visible : false
    guard.run = null
    guard.result = res
    guard.measured(res)
    if (guard.rerun) { guard.rerun = false; Qt.callLater(function () { guard.measure("rerun") }) }
  }

  Timer { interval: guard.recheckMs; repeat: true; running: guard.rechecking; onTriggered: guard.measure("recheck") }

  // --- plumbing --------------------------------------------------------------

  // Frames the window has swapped, for counting how long a hide was on screen.
  property int frames: 0
  Connections {
    target: guard.Window.window
    ignoreUnknownSignals: true
    function onFrameSwapped() { guard.frames += 1 }
  }

  Instantiator {
    model: guard.hiding
    delegate: Binding {
      required property var modelData
      target: modelData.item
      when: guard.hideNow
      property: guard.hideBy
      value: guard.hideBy === "opacity" ? 0 : false
      restoreMode: Binding.RestoreBindingOrValue
    }
  }

  Image { id: img; visible: false; cache: false }
  Canvas { id: surface; visible: false }
}
