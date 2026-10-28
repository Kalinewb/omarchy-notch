# Pixel guard, Phase 1 results (plan-surface-v2.md, 2026-10-28)

Branch `surface-p1` from `fe1956d`. Nothing in `Bar.qml` or `platform.js` is touched. New: `panelstyle.js`,
`PanelGuard.qml`, `dev/panelstyle.sh`, `dev/panelstyle_test.js`, `dev/fixtures/panelstyle/`. `./dev/panelstyle.sh`
reproduces everything below (56 pure checks and the live ones, 123 in all, about 55 s; the notch draws briefly over the live screen).

**Verdict: GO to Phase 2, with the Phase 3 requirements at the end.** Readback works inside the real `Bar.qml`
`PanelWindow`, before the reveal, in device pixels.

## Gate 1: the pixel read

Two known colours (orange `255,136,0` / blue `51,102,153`) in a fixture panel the real notch draws, with the host
closed (`ExpandedHost` invisible, disabled, opacity 0, i.e. the state before the reveal) and open, in six arrangements
(the item itself, its parent at opacity 0, its parent `visible: false`, the item itself `visible: false; opacity: 0`,
three levels deep, under a `Loader`): all 12 read back exactly. A 120 x 60 item is a 192 x 96 picture here (window
ratio 1.6). Traps, all new to the plan's 4.1:

- **`Screen.devicePixelRatio` is 2 on this session, the window's `devicePixelRatio` and the grab are 1.6.** Take the
  ratio from the picture (`image.sourceSize.width / item.width`) or the window, never the screen.
- A `Canvas`'s bitmap is its item size times the *window* ratio (600 wide gave 960). Size the canvas item as the
  panel's logical size and it holds the picture.
- `canvasSize: ...` with `renderTarget: Canvas.Image` read back **zeros** (alpha 0) synchronously; a plain `Canvas`
  with `width`/`height` works. The plan's "paint once, return until `Image.Ready`" is not needed: inside the grab
  callback the `Image` is `Ready` the moment `source` is set, and a canvas that is already `available` draws and reads
  with no frame spent. The whole read is two callbacks (A, B).
- A grab ignores the grabbed item's own `visible`/`opacity` and the host's, but **renders nothing for a descendant that
  is `visible: false`** (see "host must be visible").

## What was settled (the round-2 notes)

| note | result |
|---|---|
| Grab B by `visible: false` re-flows | Confirmed: on the `good` Column it moves **9703 pixels outside the found rects** and turns a pass into a false fail ("Looking for your face 3.1:1"). `opacity: 0` moves **0**. B hides the *texts* only (marks stay), through a `Binding` with `when:`: `when: false` restores a binding the plugin had on `opacity` **at once**; destroying the `Binding` (an `Instantiator` model change) restores a frame late. |
| Median over the rect is 1:1 for outlines | A mark's ink is read from **B** (the label is gone) as the median of the strongest half, by count, of the rect's pixels that differ from the ring's median. A transparent `Rectangle` with a border is an **outline**: only its border width (+1 px) from the edge counts, so a card with an outline reads as the outline (6.08:1), not its fill. Marks are only what declares `uiMark: true`; the focusable decoy in `outline` is not found. Marks read exact: 3.727 vs 3.73, 6.083 vs 6.083. |
| Anti-aliasing tolerance | Regular `#757575` (4.558 on paper) reads 4.18 (8 px), 4.24, 4.24, 4.31, 4.37 (12 px), 4.47 (14), 4.50 (16), bold 10 px 4.56; **light** 10 px 3.86, 12 px 3.98; `#747474` (4.493) 12 px 4.32. `TOLERANCE.text = 0.4`: a colour `lift`ed to 4.5 passes at regular weight from 8 px; light-weight thin text at 10-12 px does not (it really reads about 3.9). The leak is the price of not knowing the font: bold or large text at 4.1 passes. Marks 0. |
| "Laid out" | `laidOut(history, 3)`: something to measure, a size, and the same layout signature for 3 ticks of 16 ms (`settle` 33 ms). Then, **after each grab, the walk runs again**; if the signature moved the picture is thrown away and it settles again, because the rects are chosen a frame before the picture is taken (a `Column` polishes in between). It did not fire on the fixtures; it fires without end when B hides by `visible: false` (the reflow), which is how it was seen working. Nothing painted from found rects is not a verdict either: it settles again, ending `unsettled` at 1 s. Animated rect geometry (a growing progress bar) never settles: it ends `unsettled` and the notch treats that as "cannot prove". |
| Clip inset | `clipInset(r) = ceil(r (1 - sqrt(1/2)))` from the **setting** `bottomRadius`, not the clamped `bottomR`: the clamp reads `barWidth`, which would grow by `2d` (a binding loop), and `d` is monotonic in `r`, so the setting's inset is never too small for the clamped radius. 0, 3, 12, 59 at r = 0, 10, 40, 200; smallest whole `d` for every r in 0..300. At r = 200 the panel loses 118 px of width, so Phase 3 needs a cap (the `maxBarWidth` overflow of the note). |
| `lift` vs "#9e3340 fits a lerp" | It is exactly a lerp: each channel moves `k/255` of its distance to the extreme, `k` = 1, 2, ... (`#860111` to 3:1 is k = 50). "One 8-bit step at a time" in section 2 should read "in 1/255 steps of the distance". Vectors in the node tests: `#2a2a2a`, `#6e6e6e`, `#747474` to 4.5 all `#757575` 4.558; `#860111` to 3 `#9e3340` 3.001, to 4.5 `#b15a65` 4.52. |
| One contrast | `panelstyle.js` `parse`...`liftTo` is the kit's `tokens.js` body (itself `Bar.qml`'s), with one edit: `channel()` hoisted so the byte lookup table is built by the same function. Tests: 200 pairs, `Bar.qml` (extracted from the file and run) vs `panelstyle.js` vs the kit, 1e-9; 1000 `lift`s kit vs `liftTo`, identical colours. The kit's `lift(color, against, floor)` is `panelstyle.liftTo`; the host's `lift(color, role, against)` is the wrapper `panelstyle.lift`. No third copy. `Bar.qml` keeps its own until Phase 3 replaces it. |
| `declined` cleared on plugin reload | Not reached (Phase 3). |

## Numbers (this machine: 8 cores, one 2880 x 1800 output at 1.6; median / p95 / max, ms; 40 runs each)

Fixtures of `dev/panelstyle.sh`; "px read" is the pixels of A and B actually sampled.

| | rects | px read | wall to verdict | settle | grab A | grab B | read A / B | arithmetic | **longest stall** |
|---|---|---|---|---|---|---|---|---|---|
| good (host open) | 6 | 27 k | 50 / 71 / 71 | 33 | 2 / 14 / 16 | 8 / 19 / 20 | 1 / 1 | 4 / 6 / 7 | **4 / 5 / 5** |
| outline | 5 | 18 k | 50 / 63 / 67 | 33 | 2 / 15 / 18 | 12 / 16 / 18 | 1 / 1 | 2 / 3 / 3 | 2 / 3 / 3 |
| antialias (11 texts) | 11 | 52 k | 50 / 53 / 62 | 33 | 1 / 4 / 4 | 6 / 9 / 16 | 1 / 1 | 6 / 9 / 9 | 4 / 4 / 4 |
| big card (stride 3) | 2 | 142 k | 49 / 56 / 57 | 33 | 2 / 3 / 3 | 9 / 11 / 11 | 1 / 2 | 4 / 5 / 6 | 4 / 4 / 4 |
| list of 120 labels | 120 | 68 k | 65 / 71 / 73 | 33 | 2 / 3 / 3 | 13 / 18 / 19 | 1 / 2 | 9 / 13 / 13 | 4 / 4 / 4 |
| good, host closed + visible | 6 | 27 k | 75 / 78 / 79 | 33 | 11 / 14 / 14 | 23 / 25 / 25 | 1 / 1 | 4 / 6 / 6 | 4 / 5 / 5 |
| good, all 8 cores busy (60 runs) | 6 | 27 k | 53 / - / 103 | 33 | 2 / - / 16 | 6 / 20 / 24 | - | - | 5 / - / 14 |

- **Limits, placeholders recorded.**
  - **8 ms:** read as the longest stretch the main thread is held, not the whole cost. Reads are done inside the two
    callbacks (1-3 ms each) and the arithmetic runs in slices of `sliceMs = 4` that let the event loop go between
    them: longest stall 4 ms median, 5 ms p95, 9 ms max on an idle machine, 14 ms with all cores busy. Keep 8 ms as
    the target and `sliceMs 4`. The *total* work is 6-20 ms for a panel of 5-120 rects (the engine does about 5 000
    pixels per ms), so it cannot be one callback.
  - **150 ms:** the grab callback arrived in at most 31 ms over every run (A at most 19), 24 ms with every core busy.
    A 1 ms timeout trips on all 6 tries (`unavailable`, panel restored, next measurement clean). Keep 150 ms.
  - **2 s:** the recheck timer works (`regress`: pass, then flipped by the timer; 3+ results in 4.5 s) and costs one
    measurement each: 50-75 ms wall, ~7-17 ms of work, but see the blink below. Keep 2 s only with the light mode or
    a cached B (below).
  - Stride: **24 000 samples per rect** (`strideFor = ceil(sqrt(area / 24000))`, at most 8), not "2 above 200 k
    pixels": at 5 000 px/ms 200 k pixels at stride 1 is 40 ms. A mark's outer 3 px (and an outline's band) are
    always read in full, so a sparse read still sees a 1 px outline. The 400-rect cap holds (the walk is 0.1-0.7 ms
    a pass at 120 rects); 400 rects would be about 45 ms of arithmetic over ~11 slices.
- **Wall time to verdict is 50-75 ms** (33 ms of it settle), so a gated reveal is late by about four frames while the
  island is growing, inside the 220 ms fade.

## Findings the plan did not have

1. **The host must be `visible` while the panel is measured** (Phase 3). Before the reveal `ExpandedHost` is
   `visible: opacity > 0` and `enabled: shown`, and both read as the *effective* value, so every descendant reads
   `visible = false` and `enabled = false`. Consequences, tested: (a) the walk cannot skip hidden items, and an item
   hidden under a drawn neighbour is found at the neighbour's place and measured as the neighbour (a false pass,
   `trusted: false` in the result); (b) a block that becomes visible *while the host is invisible* is not rendered by
   a grab at all (`late`: nothing painted for 1 s, ends `unsettled`). With `ExpandedHost { visible: true }` (opacity
   stays 0, nothing shows; tested on a **copy** of `Bar.qml` with that one line changed, instance B of the script)
   everything passes: `late` settles at 288 ms and fails on its hint, `regress` is caught by the recheck (all of instance B's checks).
   `enabled` can stay `shown`: the disabled exemption cannot be honoured before the reveal (a disabled control is
   measured like any other), which is the conservative side.
2. **Grab B shows on screen.** Hiding the texts is rendered in the frame the window presents: `blinkFrames` is 1
   (2 once in 40). A recheck of a panel that is on screen every 2 s therefore blinks its text for a frame. The plan's
   step 4 cannot hide-and-grab a shown panel. Tested alternative, `mode: "light"`: grab A only, texts only, each
   against the ring around its glyph block; nothing is hidden (`blinkFrames` 0). It reads the same ratios on plain,
   translucent and gradient backdrops (8.50 vs 8.51, 2.06 vs 2.09) but is polluted by text lines within 3 px of each
   other (the antialias stack reads 1.0), cannot see the backdrop *under* a glyph (busy images), and cannot measure
   marks (their labels are in A). Phase 3 decision: re-checks of a shown panel use the light mode for the texts and the
   last full result for marks, or accept a blink; not decided here.
3. Exceptions in a grab callback must not leave the guard busy: the callbacks are wrapped, a throw ends `error` and
   puts the texts back; a callback that never arrives ends `unavailable` at `grabTimeoutMs`.
4. The `Instantiator`-created `Binding`s are inert objects and cost nothing at rest; with the fixtures 120 of them
   were created and toggled in under 1 ms.

## Phase 3 requirements this produces

- `ExpandedHost` for a contract-2 integration: `visible: opacity > 0 || measuring` (one line; opacity unchanged).
- `PanelGuard` sizes its canvas from the panel's logical size, takes the ratio from the picture, reads A and B inside
  their callbacks, and re-walks after each grab (the code is in this prototype).
- Document that a plugin which animates a found rect's geometry will not settle (`unsettled` = v1 styling); text
  and marks may move their *pixels* but should not resize every frame.
- Decide the shown-panel recheck (light mode or accept a blink); `TOLERANCE.text = 0.4`.
- `lift` aims at 4.5 exactly: at regular weight and 8 px it measures about 4.2 and passes on the tolerance; a light
  10 px face of a lifted colour fails the guard. Say so in SURFACE-HOSTING.md section 14.
- Cap the clip inset (r = 200 costs 118 px of width).
