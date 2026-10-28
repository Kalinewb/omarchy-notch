// panelstyle.js under node, for dev/panelstyle.sh layer 1. Prints one line per
// check: "<description>\t<expected>\t<actual>" -- the shell compares.
//
//   node dev/panelstyle_test.js [repo] [kit tokens.js]
//
// The kit copy is optional: with no omarchy-ui checkout beside this one the
// cross-checks against it print as skipped.

const vm = require("vm"), fs = require("fs"), path = require("path")
const repo = path.resolve(process.argv[2] || path.join(__dirname, ".."))
const kitPath = process.argv[3] || path.join(process.env.HOME, "Work/omarchy-ui/ui/tokens.js")

function load(file, extra) {
  const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library/m, "")
  const context = Object.assign({ console, Math, JSON, Date, Array, Object, String, Number, Error, RegExp }, extra || {})
  vm.createContext(context)
  vm.runInContext(source, context)
  return context
}
const PS = load(path.join(repo, "panelstyle.js"))

let n = 0
function check(desc, expected, actual) { n++; console.log(`${desc}\t${expected}\t${actual}`) }
const fx = (v, d) => Number(v).toFixed(d === undefined ? 3 : d)

// A seeded generator, so "twice" means the same colours twice.
function rng(seed) { let s = seed >>> 0; return () => ((s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296) }
function randomHex(r) { return "#" + [0, 0, 0].map(() => ("0" + Math.floor(r() * 256).toString(16)).slice(-2)).join("") }

// --- contrast: WCAG vectors ---------------------------------------------------------
check("1. black on white is 21:1", "21.000", fx(PS.contrast("#000000", "#ffffff")))
check("2. a colour on itself is 1:1", "1.000", fx(PS.contrast("#586e75", "#586e75")))
check("3. #586e75 on black is 3.90 (Bar.qml's self-test)", "3.9", fx(PS.contrast("#586e75", "#000000"), 1))
check("4. #757575 on black is 4.558", "4.558", fx(PS.contrast("#757575", "#000000")))
check("5. #747474 on black is 4.493 and fails 4.5", "4.493 false", fx(PS.contrast("#747474", "#000000")) + " " + (PS.contrast("#747474", "#000000") >= 4.5))

// --- one body: Bar.qml, panelstyle.js and the kit agree ---------------------------------
const bar = fs.readFileSync(path.join(repo, "Bar.qml"), "utf8")
const lumSrc = /function luminance\(value\) \{[\s\S]*?\n  \}\n  function contrast\(a, b\) \{[\s\S]*?\n  \}/.exec(bar)
let barContrast = null
if (lumSrc) {
  // Bar's luminance reads a colour with Qt.tint; here that is panelstyle's parse
  const ctx = { Qt: { tint: (v) => PS.parse(v) }, Math }
  vm.createContext(ctx)
  vm.runInContext(lumSrc[0].replace(/^ {2}/gm, ""), ctx)
  barContrast = ctx.contrast
}
check("6. Bar.qml's luminance/contrast body is found", "true", String(barContrast !== null))
{
  const r = rng(7)
  let worst = 0
  for (let i = 0; i < 200; i++) {
    const a = randomHex(r), b = randomHex(r)
    worst = Math.max(worst, Math.abs(barContrast(a, b) - PS.contrast(a, b)))
  }
  check("7. 200 pairs through Bar.contrast and panelstyle.contrast agree to 1e-9", "true", String(worst < 1e-9))
}
const haveKit = fs.existsSync(kitPath)
if (haveKit) {
  const kit = load(kitPath)
  const r = rng(11)
  let worst = 0, lifts = 0, liftDiff = 0
  for (let i = 0; i < 200; i++) { const a = randomHex(r), b = randomHex(r); worst = Math.max(worst, Math.abs(kit.contrast(a, b) - PS.contrast(a, b))) }
  check("8. 200 pairs through the kit's contrast and panelstyle.contrast agree to 1e-9", "true", String(worst < 1e-9))
  for (let i = 0; i < 1000; i++) {
    const c = randomHex(r), against = ["#000000", "#ffffff", randomHex(r)][i % 3], floor = i % 2 ? 4.5 : 3
    lifts++
    if (kit.hex(kit.lift(c, against, floor)) !== PS.hex(PS.liftTo(c, against, floor))) liftDiff++
  }
  check("9. 1000 lifts through the kit's lift and panelstyle.liftTo are the same colour", "0 of 1000", `${liftDiff} of ${lifts}`)
} else {
  check("8. the kit's contrast agrees (skipped: no kit checkout)", "skipped", "skipped")
  check("9. the kit's lift agrees (skipped: no kit checkout)", "skipped", "skipped")
}

// --- lift -----------------------------------------------------------------------------------
const H = (c) => PS.hex(c)
check("10. lift(#2a2a2a, text) on black is #757575", "#757575 4.558", H(PS.lift("#2a2a2a", "text")) + " " + fx(PS.contrast(PS.lift("#2a2a2a", "text"), "#000000")))
check("11. lift(#6e6e6e, text) on black is #757575", "#757575", H(PS.lift("#6e6e6e", "text")))
check("12. lift(#747474, text) on black (4.493) goes to #757575", "#757575", H(PS.lift("#747474", "text")))
check("13. lift(#860111, ui) on black is #9e3340 at 3.001", "#9e3340 3.001", H(PS.lift("#860111", "ui")) + " " + fx(PS.contrast(PS.lift("#860111", "ui"), "#000000")))
check("14. lift(#860111, text) on black is #b15a65 at 4.52", "#b15a65 4.52", H(PS.lift("#860111", "text")) + " " + fx(PS.contrast(PS.lift("#860111", "text"), "#000000"), 2))
check("15. a colour that already passes comes back unchanged", "#89b4fa #f38ba8", H(PS.lift("#89b4fa", "text")) + " " + H(PS.lift("#f38ba8", "text")))
check("16. dark text on a light fill lifts toward black", "true #767676", (() => { const c = PS.lift("#999999", "text", "#ffffff"); return (PS.luminance(c) < PS.luminance("#999999")) + " " + H(c) })())
check("17. on white, a passing dark colour is untouched", "#404040", H(PS.lift("#404040", "text", "#ffffff")))
{
  // mid-greys: neither extreme is easy, the better one still reaches the floor
  let allOk = true, worstSeen = 99
  for (let g = 90; g <= 170; g += 4) {
    const bg = PS.rgba(g / 255, g / 255, g / 255, 1)
    for (const role of ["text", "ui"]) {
      for (const start of ["#000000", "#ffffff", "#7f7f7f", "#ff0000", "#00ff00"]) {
        const c = PS.lift(start, role, bg), cr = PS.contrast(c, bg)
        worstSeen = Math.min(worstSeen, role === "text" ? cr / 4.5 : cr / 3)
        if (cr < PS.floorOf(role)) allOk = false
      }
    }
  }
  check("18. on mid-grey backdrops 90..170 every lift reaches its floor", "true", String(allOk))
}
{
  const r = rng(3)
  let notIdem = 0, below = 0
  const first = [], second = []
  for (let pass = 0; pass < 2; pass++) {
    const q = rng(99)
    for (let i = 0; i < 1000; i++) {
      const c = randomHex(q), role = i % 2 ? "text" : "ui", against = i % 5 === 0 ? "#ffffff" : "#000000"
      const l = PS.lift(c, role, against)
      ;(pass ? second : first).push(H(l))
      if (pass === 0) {
        if (H(PS.lift(l, role, against)) !== H(l)) notIdem++
        if (PS.contrast(l, against) < PS.floorOf(role)) below++
      }
    }
  }
  check("19. lift is idempotent over 1000 random colours", "0", String(notIdem))
  check("20. lift always reaches the floor over 1000 random colours", "0", String(below))
  check("21. lift is deterministic: the same 1000 twice", "true", String(JSON.stringify(first) === JSON.stringify(second)))
}
check("22. a translucent colour is judged as it lands on the backdrop", "#757575", H(PS.lift({ r: 1, g: 1, b: 1, a: 0.1 }, "text")))

// --- the clip inset -----------------------------------------------------------------------
check("23. clip inset at bottomRadius 0, 10, 40, 200", "0 3 12 59", [0, 10, 40, 200].map(PS.clipInset).join(" "))
{
  let ok = true
  for (let r = 0; r <= 300; r++) {
    const d = PS.clipInset(r)
    if (!PS.insideArc(r, d)) ok = false
    if (d > 0 && PS.insideArc(r, d - 1)) ok = false   // and no smaller whole inset would do
  }
  check("24. for every radius 0..300 the inset is the smallest whole d with the corner inside the arc", "true", String(ok))
}
check("25. the inset is monotonic in the radius, so the setting's inset covers a clamped radius", "true", (() => {
  for (let r = 1; r <= 300; r++) if (PS.clipInset(r) < PS.clipInset(r - 1)) return "false"
  return "true"
})())
check("26. a nonsense radius gives no inset", "0 0 0", [-5, NaN, undefined].map(PS.clipInset).join(" "))

// --- the pixel measurer ---------------------------------------------------------------------
function region(w, h, fill) {
  const data = new Uint8ClampedArray(w * h * 4)
  for (let i = 0; i < w * h; i++) { data[i * 4] = fill[0]; data[i * 4 + 1] = fill[1]; data[i * 4 + 2] = fill[2]; data[i * 4 + 3] = 255 }
  return { w, h, data }
}
function put(reg, x, y, c) { const i = (y * reg.w + x) * 4; reg.data[i] = c[0]; reg.data[i + 1] = c[1]; reg.data[i + 2] = c[2] }
function blend(c, b, t) { return c.map((v, k) => Math.round(v * t + b[k] * (1 - t))) }

{
  // a 3 px stem of #757575 with anti-aliased edges, on black
  const a = region(20, 10, [0, 0, 0]), b = region(20, 10, [0, 0, 0])
  for (let y = 2; y < 8; y++) { put(a, 9, y, blend([117, 117, 117], [0, 0, 0], 0.4)); put(a, 10, y, [117, 117, 117]); put(a, 11, y, [117, 117, 117]); put(a, 12, y, blend([117, 117, 117], [0, 0, 0], 0.3)) }
  const t = PS.textRatio(a, b)
  check("27. text: the ink is the glyph core, not its anti-aliased edge", "4.558", fx(t.ratio))
  check("28. text: nothing drawn (A equals B) is not painted, not a failure", "false", String(PS.textRatio(b, b).painted))
}
{
  // text on a gradient: the worst backdrop pixel counts
  const w = 40, h = 8, a = region(w, h, [0, 0, 0]), b = region(w, h, [0, 0, 0])
  for (let x = 0; x < w; x++) for (let y = 0; y < h; y++) { const v = Math.round(x * 3); put(b, x, y, [v, v, v]); put(a, x, y, [v, v, v]) }
  for (let y = 2; y < 6; y++) for (let x = 2; x < 6; x++) put(a, x, y, [255, 255, 255])
  const t = PS.textRatio(a, b)
  // white against #75 (x = 39 -> 117) is the least contrast in the rect
  check("29. text: the ratio is against the worst backdrop pixel of the rect", fx(PS.contrast("#ffffff", "#757575")), fx(t.ratio))
}
{
  // an outline mark: 1 px border #808080, interior = backdrop
  const a = region(20, 12, [0, 0, 0]), ringRegion = region(20, 4, [0, 0, 0])
  for (let x = 0; x < 20; x++) { put(a, x, 0, [128, 128, 128]); put(a, x, 11, [128, 128, 128]) }
  for (let y = 0; y < 12; y++) { put(a, 0, y, [128, 128, 128]); put(a, 19, y, [128, 128, 128]) }
  const m = PS.markRatio(a, ringRegion)
  check("30. mark: an outline reads as its border, not as its interior", fx(PS.contrast("#808080", "#000000")), fx(m.ratio))
  const faint = region(20, 12, [0, 0, 0])
  for (let x = 0; x < 20; x++) { put(faint, x, 0, [40, 40, 40]); put(faint, x, 11, [40, 40, 40]) }
  for (let y = 0; y < 12; y++) { put(faint, 0, y, [40, 40, 40]); put(faint, 19, y, [40, 40, 40]) }
  check("31. mark: a faint outline fails 3:1", "true", String(PS.markRatio(faint, ringRegion).ratio < 3))
  check("32. mark: a mark that paints nothing reads 1:1", "1.000", fx(PS.markRatio(region(20, 12, [0, 0, 0]), ringRegion).ratio))
  const solid = region(20, 12, [58, 130, 247])
  check("33. mark: a filled one reads as its fill", fx(PS.contrast("#3a82f7", "#000000")), fx(PS.markRatio(solid, ringRegion).ratio))
}

// --- the walk ----------------------------------------------------------------------------------
function item(props, kids) {
  const it = Object.assign({ x: 0, y: 0, width: 100, height: 20, visible: true, opacity: 1, enabled: true, children: [], parent: null }, props)
  it.children = kids || []
  for (const k of it.children) k.parent = it
  return it
}
function label(text, props) { return item(Object.assign({ text, contentWidth: 40, contentHeight: 10, font: {}, horizontalAlignment: 1, verticalAlignment: 128 }, props)) }
{
  const root = item({ width: 200, height: 100 }, [
    item({ x: 10, y: 10 }, [label("hello", { x: 4, y: 2 })]),
    label("off", { y: 30, enabled: false }),
    label("gone", { y: 40, visible: false }),
    label("clear", { y: 50, opacity: 0 }),
    label("", { y: 60 }),
    item({ y: 70, uiMark: true, width: 30, height: 12 }),
    item({ y: 80, activeFocusOnTab: true, width: 30, height: 12 }),
    item({ y: 90, opacity: 0.5 }, [label("dim", {})]),
  ])
  const f = PS.findRects(root)
  check("34. the walk finds visible text and declared marks only", "hello,mark,dim", f.rects.map((r) => r.name).join(","))
  check("35. a disabled item, a hidden one, an invisible one, empty text and a bare focusable are skipped", "3", String(f.seen))
  const hello = f.rects[0]
  check("36. a text's rect is in the root's coordinates (vertically centred in its item), as wide as its glyphs", "14,17,40,10", [hello.x, hello.y, hello.w, hello.h].join(","))
  const pre = PS.findRects(item({ width: 200, height: 100, visible: false }, [label("x", { visible: false, y: 5 }), label("y", { y: 20 })]), { trustVisible: false })
  check("37. before the reveal visible says nothing: both are found and the pixels decide", "x,y", pre.rects.map((r) => r.name).join(","))
  const centred = PS.findRects(item({ width: 200, height: 100 }, [label("c", { width: 100, height: 40, horizontalAlignment: 4, verticalAlignment: 128 })]))
  check("38. a centred text's rect is where its glyphs are, not the item it fills", "30,15,40,10", [centred.rects[0].x, centred.rects[0].y, centred.rects[0].w, centred.rects[0].h].join(","))
  const many = item({ width: 100, height: 4000 }, Array.from({ length: 500 }, (_, i) => label("t" + i, { y: i * 8 })))
  const capped = PS.findRects(many, { cap: 400 })
  check("39. the walk keeps 400 rects and says it did not see the rest", "400 true 500", `${capped.rects.length} ${capped.capped} ${capped.seen}`)
  const outside = PS.findRects(item({ width: 50, height: 50 }, [label("far", { x: 300, y: 300 })]))
  check("40. text outside the panel is not a rect", "0", String(outside.rects.length))
}

// --- laid out ------------------------------------------------------------------------------------
{
  const s = (w, h, count, sig) => ({ w, h, count, sig: sig || `${w}x${h}:${count}` })
  check("41. an empty panel is never laid out", "false", String(PS.laidOut([s(0, 0, 0), s(0, 0, 0), s(0, 0, 0), s(0, 0, 0)])))
  check("42. a panel with nothing to measure is not laid out", "false", String(PS.laidOut([s(300, 100, 0), s(300, 100, 0), s(300, 100, 0)])))
  check("43. a panel still changing is not laid out", "false", String(PS.laidOut([s(300, 100, 2), s(300, 120, 2), s(300, 120, 3), s(300, 120, 3)])))
  check("44. three identical snapshots in a row are laid out", "true", String(PS.laidOut([s(300, 100, 1), s(300, 120, 3), s(300, 120, 3), s(300, 120, 3)])))
  check("45. fewer snapshots than the settle count are not", "false", String(PS.laidOut([s(300, 120, 3), s(300, 120, 3)])))
}

// --- verdict ----------------------------------------------------------------------------------------
{
  const v = PS.verdict([{ name: "title", role: "text", ratio: 12, painted: true }, { name: "ring", role: "ui", ratio: 3.4, painted: true }, { name: "ghost", role: "text", ratio: 1, painted: false }])
  check("46. all clear: pass, the unpainted one not counted", "true 2", `${v.pass} ${v.measured}`)
  const bad = PS.verdict([{ name: "title", role: "text", ratio: 12, painted: true }, { name: "hint", role: "text", ratio: 2.61, painted: true }])
  check("47. a text under 4.5 fails and is named", "false hint 2.6:1 < 4.5", `${bad.pass} ${PS.detail(bad.failing)}`)
  check("48. a mark is held to 3, not 4.5", "true false", `${PS.verdict([{ name: "m", role: "ui", ratio: 3.2, painted: true }]).pass} ${PS.verdict([{ name: "m", role: "ui", ratio: 2.9, painted: true }]).pass}`)
  check("49. nothing measured is not a pass", "false", String(PS.verdict([]).pass))
}
check("50. stride is 1 up to 200 k pixels and 2 above", "1 1 2", [PS.strideFor(400, 500), PS.strideFor(200, 1000), PS.strideFor(401, 500)].join(" "))
