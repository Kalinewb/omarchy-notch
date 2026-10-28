import QtQuick
import Quickshell.Io
import "panelstyle.js" as PS

// A contract-2-shaped panel for the guard prototype (dev/panelstyle.sh): it
// owns its colours, and holds one fixture at a time, which the harness picks
// over IPC. The guard measures the fixture; PanelGuard.qml and panelstyle.js
// are copied in beside this file by the script, as the notch will have them.
//
// Every fixture states what it expects (`expect`: pass or fail, the name of
// the item that fails, and where the colours are flat, the exact ratio).
Item {
  id: panel

  property var surfaceHost: null
  property string surfaceScreen: ""
  property string route: "main"
  property real maxWidth: 400
  property real maxHeight: 400
  signal closeRequested()

  implicitWidth: 320
  implicitHeight: 190

  focus: true
  Keys.onEscapePressed: panel.closeRequested()

  // The colour ratio two flat colours should read as: what the pixel check is
  // compared against.
  function expectRatio(ink, back) { return PS.contrast(ink, back) }

  property string fixture: ""
  property var expect: ({})
  property int sequence: 0

  // --- the fixtures -----------------------------------------------------------

  // 1. Own colours, all of them clear: pass.
  Component {
    id: good
    Column {
      spacing: 8
      property var expect: ({ pass: true, ratio: { "Face ID": PS.contrast("#ffffff", "#000000") } })
      Text { text: "Face ID"; color: "#ffffff"; font.pixelSize: 16 }
      Text { text: "Looking for your face"; color: "#c8c8c8"; font.pixelSize: 12 }
      Row {
        spacing: 8
        Rectangle {
          property bool uiMark: true; objectName: "Enrol"
          width: 90; height: 30; radius: 8; color: "#2a5fd8"
          Text { anchors.centerIn: parent; text: "Enrol"; color: "#ffffff"; font.pixelSize: 13 }
        }
        Rectangle {
          property bool uiMark: true; objectName: "Cancel"
          width: 90; height: 30; radius: 8; color: "#6a6a6a"
          Text { anchors.centerIn: parent; text: "Cancel"; color: "#ffffff"; font.pixelSize: 13 }
        }
      }
    }
  }

  // 2. A hint at 2.8:1: fail, and it is the hint that is named.
  Component {
    id: lowText
    Column {
      spacing: 8
      property var expect: ({ pass: false, failing: "Hint text", ratio: { "Hint text": PS.contrast("#555555", "#000000") } })
      Text { text: "Face ID"; color: "#ffffff"; font.pixelSize: 16 }
      Text { text: "Hint text"; color: "#555555"; font.pixelSize: 13 }
    }
  }

  // 3. Outline buttons: transparent inside, the border is the mark. Passes 3:1.
  // The faint box beside them is focusable but declares nothing: it is not
  // measured (a focusable item is not a mark).
  Component {
    id: outline
    Column {
      spacing: 10
      property var expect: ({ pass: true, found: 5, ratio: { "Retry": PS.contrast("#8a8a8a", "#000000") } })
      Text { text: "Outline"; color: "#ffffff"; font.pixelSize: 14 }
      Row {
        spacing: 10
        Rectangle {
          property bool uiMark: true; objectName: "Retry"
          width: 80; height: 30; radius: 8; color: "transparent"; border.width: 1; border.color: "#8a8a8a"
          Text { anchors.centerIn: parent; text: "Retry"; color: "#ffffff"; font.pixelSize: 13 }
        }
        Rectangle {
          property bool uiMark: true; objectName: "Skip"
          width: 80; height: 30; radius: 8; color: "transparent"; border.width: 2; border.color: "#8a8a8a"
          Text { anchors.centerIn: parent; text: "Skip"; color: "#ffffff"; font.pixelSize: 13 }
        }
        Rectangle {
          activeFocusOnTab: true
          width: 60; height: 30; color: "transparent"; border.width: 1; border.color: "#1c1c1c"
        }
      }
    }
  }

  // 4. The same buttons with a border at 1.5:1: the mark fails, the text is fine.
  Component {
    id: outlineBad
    Column {
      spacing: 10
      property var expect: ({ pass: false, failing: "Retry", ratio: { "Retry": PS.contrast("#2a2a2a", "#000000") } })
      Text { text: "Outline"; color: "#ffffff"; font.pixelSize: 14 }
      Rectangle {
        property bool uiMark: true; objectName: "Retry"
        width: 80; height: 30; radius: 8; color: "transparent"; border.width: 1; border.color: "#2a2a2a"
        Text { anchors.centerIn: parent; text: "Retry"; color: "#ffffff"; font.pixelSize: 13 }
      }
    }
  }

  // 5. Translucency: a 12 % white card, text at 70 % alpha on it and a
  // 60 %-opaque label. Judged as it lands on the notch's black.
  Component {
    id: translucent
    Item {
      width: 300; height: 110
      readonly property color card: Qt.rgba(1, 1, 1, 0.12)
      readonly property color cardOnBlack: PS.over(card, "#000000")
      property var expect: ({ pass: true, ratio: {
        "Translucent": PS.contrast(PS.over(Qt.rgba(1, 1, 1, 0.7), PS.over(Qt.rgba(1, 1, 1, 0.12), "#000000")), PS.over(Qt.rgba(1, 1, 1, 0.12), "#000000")),
        "Faded": PS.contrast(PS.over(Qt.rgba(1, 1, 1, 0.6), PS.over(Qt.rgba(1, 1, 1, 0.12), "#000000")), PS.over(Qt.rgba(1, 1, 1, 0.12), "#000000")) } })
      Rectangle {
        x: 0; y: 0; width: 300; height: 80; radius: 12; color: parent.card
        Text { x: 12; y: 10; text: "Translucent"; color: Qt.rgba(1, 1, 1, 0.7); font.pixelSize: 15 }
        Text { x: 12; y: 40; text: "Faded"; color: "#ffffff"; opacity: 0.6; font.pixelSize: 15 }
      }
    }
  }

  // 6. Text across a gradient that ends light: it reads at the left and not at
  // the right, and the worst pixel of the rect decides.
  Component {
    id: gradient
    Item {
      width: 300; height: 70
      property var expect: ({ pass: false, failing: "Across the gradient" })
      Rectangle {
        anchors.fill: parent; radius: 10
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: "#101010" }
          GradientStop { position: 1; color: "#c0c0c0" }
        }
        Text { x: 130; y: 24; text: "Across the gradient"; color: "#ffffff"; font.pixelSize: 16 }
      }
    }
  }

  // 7. #757575 (4.558:1 on black, the lift of a failing grey) and #747474
  // (4.493:1) at the sizes real panels use. What the pixels read is what sets
  // panelstyle.js's TOLERANCE.
  Component {
    id: antialias
    Column {
      spacing: 1
      property var expect: ({ pass: true, sweep: true })
      Repeater {
        model: [{ s: 8, c: "#757575", b: false }, { s: 9, c: "#757575", b: false }, { s: 10, c: "#757575", b: false },
                { s: 11, c: "#757575", b: false }, { s: 12, c: "#757575", b: false }, { s: 14, c: "#757575", b: false },
                { s: 16, c: "#757575", b: false }, { s: 10, c: "#757575", b: true }, { s: 12, c: "#747474", b: false },
                { s: 10, c: "#757575", b: false, w: Font.Light }, { s: 12, c: "#757575", b: false, w: Font.Light }]
        Text {
          required property var modelData
          objectName: "aa " + modelData.s + (modelData.b ? "b " : modelData.w !== undefined ? "l " : " ") + modelData.c
          text: "Hamburgefonstiv " + modelData.s
          color: modelData.c
          font.pixelSize: modelData.s
          font.bold: modelData.b
          font.weight: modelData.w !== undefined ? modelData.w : (modelData.b ? Font.Bold : Font.Normal)
        }
      }
    }
  }

  // 8. A panel that fills in late: empty for 250 ms, then a title and a
  // hint at 2.8:1. Whatever is measured must be measured after it is there.
  Component {
    id: late
    Item {
      id: lateRoot
      width: 300; height: 70
      property var expect: ({ pass: false, failing: "Late hint", settleAtLeast: 250 })
      Timer { interval: 250; running: true; onTriggered: lateBody.visible = true }
      Column {
        id: lateBody
        visible: false
        spacing: 8
        Text { text: "Loaded"; color: "#ffffff"; font.pixelSize: 15 }
        Text { text: "Late hint"; color: "#555555"; font.pixelSize: 13 }
      }
    }
  }

  // 9. Fine when first measured, bad 600 ms later: a sticky pass must be
  // caught by the recheck, not by luck.
  Component {
    id: regress
    Item {
      width: 300; height: 70
      property var expect: ({ pass: true, then: false, failing: "Regressed" })
      Timer { interval: 600; running: true; onTriggered: bad.visible = true }
      Column {
        spacing: 8
        Text { text: "Steady"; color: "#ffffff"; font.pixelSize: 15 }
        Text { id: bad; visible: false; text: "Regressed"; color: "#444444"; font.pixelSize: 13 }
      }
    }
  }

  // 10. One big card: a 290 x 160 filled panel with an outline and a headline,
  // read sparsely. The outline and the headline must still read as themselves.
  Component {
    id: big
    Item {
      width: 290; height: 160
      property var expect: ({ pass: true, ratio: { "Card": PS.contrast("#8a8a8a", "#000000"), "Headline": PS.contrast("#ffffff", "#1a2a44") } })
      Rectangle {
        anchors.fill: parent; radius: 12; color: "#1a2a44"
        Text { x: 14; y: 14; text: "Headline"; color: "#ffffff"; font.pixelSize: 40 }
        // the card's fill carries nothing; its outline is the mark
        Rectangle {
          property bool uiMark: true; objectName: "Card"
          anchors.fill: parent; radius: 12; color: "transparent"; border.width: 1; border.color: "#8a8a8a"
        }
      }
    }
  }

  // 11. A hundred and twenty short labels: what the walk and the arithmetic
  // cost when a panel is a list, and what the cap does to it.
  Component {
    id: many
    Grid {
      columns: 10; columnSpacing: 0; rowSpacing: 1
      property var expect: ({ pass: true, count: 120 })
      Repeater {
        model: 120
        Text { width: 29; height: 13; text: "r" + index; color: "#d0d0d0"; font.pixelSize: 9 }
      }
    }
  }

  readonly property var table: ({ good: good, lowText: lowText, outline: outline, outlineBad: outlineBad,
    translucent: translucent, gradient: gradient, antialias: antialias, late: late, regress: regress, big: big, many: many })

  // The panel's own background-free content, where the guard looks.
  Item {
    id: content
    x: 12; y: 10
    width: panel.width - 24
    height: panel.height - 20
    Loader {
      id: loader
      sourceComponent: panel.fixture !== "" ? panel.table[panel.fixture] : null
      onLoaded: panel.expect = item && item.expect ? item.expect : ({})
    }
  }

  PanelGuard {
    id: guard
    target: content
    backdrop: panel.surfaceHost ? panel.surfaceHost.color : "#000000"
    onMeasured: function (res) { panel.collect(res) }
  }

  // --- the bare readback (gate 1) ---------------------------------------------------

  // Two known colours in five arrangements, to find what a grab needs of the
  // item and of everything above it.
  Item {
    id: swatchBox
    x: 0; y: 0; width: 1; height: 1
    // direct: nothing hidden but what the host does
    Item { id: s1; width: 120; height: 60
      Rectangle { x: 0; y: 0; width: 60; height: 60; color: "#ff8800" }
      Rectangle { x: 60; y: 0; width: 60; height: 60; color: "#336699" } }
    // the parent at opacity 0
    Item { opacity: 0; width: 120; height: 60
      Item { id: s2; width: 120; height: 60
        Rectangle { x: 0; y: 0; width: 60; height: 60; color: "#ff8800" }
        Rectangle { x: 60; y: 0; width: 60; height: 60; color: "#336699" } } }
    // the parent explicitly invisible
    Item { visible: false; width: 120; height: 60
      Item { id: s3; width: 120; height: 60
        Rectangle { x: 0; y: 0; width: 60; height: 60; color: "#ff8800" }
        Rectangle { x: 60; y: 0; width: 60; height: 60; color: "#336699" } } }
    // the item itself invisible and at opacity 0
    Item { id: s4; visible: false; opacity: 0; width: 120; height: 60
      Rectangle { x: 0; y: 0; width: 60; height: 60; color: "#ff8800" }
      Rectangle { x: 60; y: 0; width: 60; height: 60; color: "#336699" } }
    // three levels down
    Item { id: s5; width: 120; height: 60
      Column { Row { Item { width: 120; height: 60
        Rectangle { x: 0; y: 0; width: 60; height: 60; color: "#ff8800" }
        Rectangle { x: 60; y: 0; width: 60; height: 60; color: "#336699" } } } } }
    // a Loader, as the fixtures use
    Loader { id: s6; sourceComponent: Component { Item { width: 120; height: 60
        Rectangle { x: 0; y: 0; width: 60; height: 60; color: "#ff8800" }
        Rectangle { x: 60; y: 0; width: 60; height: 60; color: "#336699" } } } }
  }
  property Item swatch: s1
  Image { id: probeImg; visible: false; cache: false }
  Canvas { id: probeCanvas; visible: false; width: 600; height: 400 }
  property var probeResult: null

  function readback(mode) {
    var t0 = new Date().getTime()
    var chain = []
    var table0 = { s1: s1, s2: s2, s3: s3, s4: s4, s5: s5, s6: s6 }
    for (var p = table0[mode] || s1; p; p = p.parent) chain.push(String(p).replace(/\(0x.*/, "").replace(/_QMLTYPE_\d+/, "") + ":v" + (p.visible ? 1 : 0) + ":o" + Number(p.opacity).toFixed(2))
    var table = { s1: s1, s2: s2, s3: s3, s4: s4, s5: s5, s6: s6 }
    swatch = table[mode] || s1
    swatch.grabToImage(function (g) {
      var t1 = new Date().getTime()
      if (!g) { panel.probeResult = { ok: false, why: "grab returned null" }; return }
      probeImg.source = g.url
      var w = probeImg.sourceSize.width, h = probeImg.sourceSize.height
      var ctx = probeCanvas.getContext("2d")
      ctx.drawImage(probeImg, 0, 0)
      var s = w / 120
      var a = ctx.getImageData(Math.floor(10 * s), Math.floor(10 * s), 1, 1).data
      var b = ctx.getImageData(Math.floor(90 * s), Math.floor(10 * s), 1, 1).data
      var t2 = new Date().getTime()
      ctx.fillStyle = "#ff0000"; ctx.fillRect(0, 0, 3000, 3000)
      var far = ctx.getImageData(599, 399, 1, 1).data, beyond = ctx.getImageData(700, 450, 1, 1).data
      var lo = 0, hi = 3000
      while (hi - lo > 1) { var mid = (lo + hi) >> 1; if (ctx.getImageData(mid, 0, 1, 1).data[3] === 255) lo = mid; else hi = mid }
      panel.probeResult = { ok: true, mode: mode, a: [a[0], a[1], a[2], a[3]], b: [b[0], b[1], b[2], b[3]],
        source: [w, h], item: [120, 60], scale: Number(s.toFixed(3)),
        dpr: panel.Screen.devicePixelRatio, status: probeImg.status, grabMs: t1 - t0, readMs: t2 - t1,
        swatchVisible: swatch.visible, hostOpacity: panel.opacity, chain: chain.slice(0, 6), canvasSize: [probeCanvas.canvasSize.width, probeCanvas.canvasSize.height], bitmapWidth: hi, windowDpr: panel.Window.window ? panel.Window.window.devicePixelRatio : -1, farA: far[3], beyondA: beyond[3] }
    })
  }

  // --- driving it ---------------------------------------------------------------

  property var runs: []
  property var history: []
  property int wanted: 0
  property bool recheckLater: false
  property var last: null

  function collect(res) {
    panel.last = res
    panel.runs.push({ state: res.state, pass: res.pass, ms: res.ms, blink: res.blinkFrames, ticks: res.ticks })
    panel.history.push({ state: res.state, reason: res.reason, at: new Date().getTime() })
    if (panel.runs.length < panel.wanted) Qt.callLater(function () { guard.measure("repeat") })
    else { panel.sequence += 1; if (panel.recheckLater) { guard.rechecking = true; panel.recheckLater = false } }
  }

  Timer { id: kick; interval: 1; onTriggered: guard.measure("start") }

  IpcHandler {
    target: "guard." + panel.surfaceScreen
    enabled: panel.surfaceScreen !== ""

    function fixtures(): string { return Object.keys(panel.table).join(" ") }

    // start("<fixture>", '{"repeat":1,"audit":false,"hideBy":"opacity","at":0}')
    function start(name: string, opts: string): string {
      var o = {}
      try { o = JSON.parse(opts || "{}") } catch (e) { return "bad-json" }
      if (!(name in panel.table) && name !== "none") return "unknown"
      guard.rechecking = false
      guard.maxRects = o.maxRects || 400
      guard.mode = o.mode || "full"
      guard.grabTimeoutMs = o.timeout || 150
      guard.audit = o.audit === true
      guard.hideBy = o.hideBy || "opacity"
      panel.runs = []
      panel.history = []
      panel.last = null
      panel.recheckLater = o.recheck === true
      panel.wanted = o.repeat || 1
      panel.fixture = name === "none" ? "" : name
      kick.interval = Math.max(1, o.at || 1)
      kick.restart()
      return "started"
    }

    // measure the fixture that is already up, again (the recheck)
    function again(): string { panel.wanted = panel.runs.length + 1; guard.measure("again"); return "started" }

    function stop(): string { guard.rechecking = false; return "ok" }

    function result(): string {
      var r = panel.last
      return JSON.stringify({
        sequence: panel.sequence, done: r !== null && !guard.busy, busy: guard.busy,
        fixture: panel.fixture, expect: panel.expect, runs: panel.runs, history: panel.history, result: r
      })
    }

    function readback(mode: string): string { panel.probeResult = null; panel.readback(mode); return "started" }
    function readbackResult(): string { return JSON.stringify(panel.probeResult) }

    // The host around the panel, as the guard sees it right now.
    function host(): string {
      return JSON.stringify({ target: guard.target ? guard.ancestry() : null, panelVisible: panel.visible, panelOpacity: panel.opacity,
                              open: panel.surfaceHost ? panel.surfaceHost.panelOpen : false })
    }
  }
}
