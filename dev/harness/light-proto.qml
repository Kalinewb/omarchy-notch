import QtQuick
import QtQuick.Window
import "../.." as Notch
import "../../notiflight.js" as Light

// The notification light prototype: shaders/notiflight.frag over a black
// scene with the real Island.qml notch, one tile per time, rendered offscreen
// to a PNG. Run by dev/light-proto.sh with the OpenGL RHI backend:
//
//   qml6 light-proto.qml -- style=notch palette=aurora w=360 h=110 ts=0.4,1,2.5,4 cols=4 out=sheet.png
//
// Arguments (all optional):
//   style    notch | top | full           palette  aurora | blue | white | critical
//   w h r fillet   the notch bar, px      reach    where the curve reaches zero, px
//   peak     0 = the style's default      particles 0 | 1 (default: the palette's)
//   ts       tile times, seconds          t0 t1 dt  alternative: a range
//   tw       tile width (default: just fits)    cols     tiles per row                view     0 normal | 1 cloud only | 2 light only
//   sw sh    top and full: the screen     seed     grain seed
//   presence override the fade (default: the envelope for a 5 s light)
//   T v W A  cloud period, drift, swirl, curl (px)         gain, radius, hot  cloud brightness, spawn radius, whiteHot
//   mode=gpu frames=N hidden=0|1   time N grabs of the scene (the effect hidden = the baseline: scene and readback only)
//   mode=bench seconds=N   live: animate N s (QSG_RENDER_TIMING logs the frames, CPU side only)
Window {
  id: win
  visible: true
  color: "black"

  readonly property var args: {
    var all = Qt.application.arguments
    var parsed = {}
    var start = all.indexOf("--")
    for (var i = start < 0 ? 0 : start + 1; i < all.length; i++) {
      var eq = String(all[i]).indexOf("=")
      if (eq > 0) parsed[String(all[i]).slice(0, eq)] = String(all[i]).slice(eq + 1)
    }
    return parsed
  }
  function num(key, fallback) { var n = Number(args[key]); return isFinite(n) && args[key] !== undefined && args[key] !== "" ? n : fallback }
  function str(key, fallback) { return args[key] !== undefined ? args[key] : fallback }

  readonly property string style: str("style", "notch")
  readonly property int styleIndex: style === "top" ? 1 : (style === "full" ? 2 : 0)
  readonly property string paletteName: str("palette", "aurora")
  readonly property var pal: Light.palettes[paletteName]
  readonly property bool bench: str("mode", "") === "bench" || gpu
  readonly property bool gpu: str("mode", "") === "gpu"
  readonly property real barW: num("w", 180)
  readonly property real barH: num("h", 32)
  readonly property real screenW: num("sw", 1000)
  readonly property real screenH: num("sh", 600)
  readonly property real reach: num("reach", 48)
  readonly property real peakDefault: styleIndex === 0 ? 0.55 : (styleIndex === 1 ? 0.50 : 0.35)
  readonly property real peak: (num("peak", 0) > 0 ? num("peak", 0) : peakDefault) * pal.peak
  readonly property bool particles: num("particles", pal.particles) > 0.5
  readonly property real cloudRadius: num("radius", Math.min(80, reach * 1.5))
  readonly property real drawReach: Math.max(reach * 1.25, cloudRadius)
  readonly property real tail: styleIndex === 0 ? 2 : 1
  readonly property real pad: 12

  readonly property var times: {
    if (args.ts) return args.ts.split(",").map(Number)
    if (args.t0 !== undefined) {
      var out = [], t0 = num("t0", 0), t1 = num("t1", 3), dt = num("dt", 1 / 30)
      for (var t = t0; t <= t1 + 1e-9; t += dt) out.push(t)
      return out
    }
    return [num("t", 1)]
  }
  readonly property int cols: Math.min(times.length, Math.max(1, num("cols", times.length)))
  readonly property int rows: Math.ceil(times.length / cols)

  readonly property real tileW: num("tw", styleIndex === 0 ? barW + 2 * 10 + 2 * (drawReach * tail + pad) : screenW)
  readonly property real tileH: styleIndex === 0 ? barH + drawReach + pad : (styleIndex === 1 ? drawReach + pad : screenH)

  width: Math.ceil(tileW * cols)
  height: Math.ceil(tileH * (win.bench ? 1 : rows))

  component Fx: ShaderEffect {
    id: fx
    property real tTime: 0
    property real tPresence: 1
    property point strip: Qt.point(0, 0)

    fragmentShader: Qt.resolvedUrl("../../shaders/notiflight.frag.qsb")
    blending: true
    opacity: win.num("hidden", 0) > 0.5 ? 0 : 1

    readonly property var curve: Light.uniforms(win.reach)
    readonly property size itemSize: Qt.size(width, height)
    readonly property real margin: win.styleIndex === 0 ? 10 + win.drawReach * win.tail + win.pad : 0
    readonly property real barWidth: win.barW
    readonly property real barHeight: win.barH
    readonly property real bottomRadius: win.num("r", 10)
    readonly property real filletRadius: win.num("fillet", 10)
    readonly property real edgeTail: win.tail
    readonly property size screenSize: Qt.size(win.screenW, win.screenH)
    readonly property point origin: strip
    readonly property real style: win.styleIndex
    readonly property real time: tTime
    readonly property real presence: tPresence
    readonly property real peak: win.peak
    readonly property real reach: win.reach
    readonly property real particles: win.particles ? 1 : 0
    readonly property real seed: win.num("seed", 7)
    readonly property real steady: win.paletteName === "critical" || win.str("steady", "0") === "1" ? 1 : 0
    readonly property real view: win.num("view", 0)
    readonly property real cloudRadius: win.cloudRadius
    readonly property real cloudGain: win.num("gain", Light.emitter.gain)
    readonly property real whiteHot: win.num("hot", Light.emitter.whiteHot)
    readonly property vector4d knotD: curve.d
    readonly property vector4d knotA: curve.a
    readonly property vector4d knotM: curve.m
    readonly property vector4d stop0: stop(0)
    readonly property vector4d stop1: stop(1)
    readonly property vector4d stop2: stop(2)
    readonly property vector4d stop3: stop(3)
    readonly property vector4d stop4: stop(4)
    readonly property vector4d cloud0: cloudColour(0)
    readonly property vector4d cloud1: cloudColour(1)
    readonly property vector4d cloud2: cloudColour(2)
    readonly property vector4d flow: Qt.vector4d(win.num("T", Light.emitter.period), win.num("v", Light.emitter.drift),
                                                  win.num("W", Light.emitter.swirl), win.num("A", Light.emitter.curl))
    readonly property vector4d grainR: Qt.vector4d(win.num("r1", Light.emitter.grain[0]), win.num("r2", Light.emitter.grain[1]), win.num("r3", Light.emitter.grain[2]), win.num("cs", Light.emitter.curlScale))
    readonly property vector4d grainP: Qt.vector4d(win.num("p1", Light.emitter.density[0]), win.num("p2", Light.emitter.density[1]), win.num("p3", Light.emitter.density[2]), 0)

    function stop(i) {
      var s = win.pal.stops[i], c = Light.hex(s[0])
      return Qt.vector4d(c[0], c[1], c[2], s[1])
    }
    function cloudColour(i) {
      var c = Light.hex(win.pal.cloud[i])
      return Qt.vector4d(c[0], c[1], c[2], 1)
    }
  }

  // One tile: the notch (or the screen) and the light at time `t`.
  component Tile: Item {
    id: tile
    property real t: 0
    property real presence: win.num("presence", Light.envelope(t * 1000, 5000))
    width: win.tileW
    height: win.tileH
    clip: true

    Fx {
      visible: win.styleIndex === 0
      x: (tile.width - win.barW) / 2 - margin
      y: 0
      width: win.barW + 2 * margin
      height: win.barH + win.drawReach + win.pad
      tTime: tile.t
      tPresence: tile.presence
    }
    Fx {
      visible: win.styleIndex === 1
      width: win.screenW
      height: win.drawReach + win.pad
      tTime: tile.t
      tPresence: tile.presence
    }
    // full: four strips, one per edge, the corners belonging to top and bottom
    Repeater {
      model: win.styleIndex === 2 ? 4 : 0
      Fx {
        readonly property real e: win.drawReach
        x: index === 3 ? win.screenW - e : 0
        y: index === 0 ? 0 : (index === 1 ? win.screenH - e : e)
        width: index < 2 ? win.screenW : e
        height: index < 2 ? e : win.screenH - 2 * e
        strip: Qt.point(x, y)
        tTime: tile.t
        tPresence: tile.presence
      }
    }

    Notch.Island {
      x: (tile.width - width) / 2
      y: 0
      barWidth: win.barW
      barHeight: win.barH
      bottomRadius: win.num("r", 10)
      filletRadius: win.num("fillet", 10)
    }
  }

  Item {
    id: scene
    width: win.width
    height: win.height

    Rectangle { anchors.fill: parent; color: "#000000" }
    Repeater {
      model: win.bench ? 1 : win.times.length
      Tile {
        x: (index % win.cols) * win.tileW
        y: Math.floor(index / win.cols) * win.tileH
        t: win.bench ? benchClock.time : win.times[index]
      }
    }
  }

  // Bench: animate like the shell would, one FrameAnimation writing `time`.
  QtObject {
    id: benchClock
    property real time: 0
  }
  FrameAnimation {
    running: win.bench && !win.gpu
    onTriggered: benchClock.time += frameTime
  }

  function log(key, value) { console.log("LIGHT " + key, value) }

  // gpu: every grab renders the scene and reads it back, so the loop's time
  // per frame is the GPU's work plus the readback; the baseline run (hidden=1)
  // has everything but the effect's pixels.
  property var gpuTimes: []
  property real gpuLast: 0
  function gpuStep() {
    scene.grabToImage(function(result) {
      var now = Date.now()
      if (win.gpuLast > 0) win.gpuTimes.push(now - win.gpuLast)
      win.gpuLast = now
      benchClock.time += 1 / 60
      if (win.gpuTimes.length >= win.num("frames", 120)) {
        var a = win.gpuTimes.slice(10).sort(function(x, y) { return x - y })
        var sum = 0
        for (var i = 0; i < a.length; i++) sum += a[i]
        win.log("gpuMs", "mean " + (sum / a.length).toFixed(3) + " median " + a[Math.floor(a.length / 2)] + " p90 " + a[Math.floor(a.length * 0.9)] + " n " + a.length)
        Qt.exit(0)
      } else win.gpuStep()
    })
  }
  Timer { interval: 800; running: win.gpu; onTriggered: win.gpuStep() }

  Timer {
    interval: 800
    running: !win.bench
    onTriggered: {
      win.log("size", win.width + "x" + win.height + " tile " + win.tileW + "x" + win.tileH + " dpr " + win.devicePixelRatio)
      scene.grabToImage(function(result) {
        win.log("saved", result.saveToFile(win.str("out", "light.png")))
        Qt.exit(0)
      })
    }
  }
  Timer {
    interval: win.num("seconds", 4) * 1000 + 1500
    running: win.bench && !win.gpu
    onTriggered: { win.log("bench", "done"); Qt.exit(0) }
  }
  Timer { interval: 600000; running: true; onTriggered: { win.log("timeout", true); Qt.exit(1) } }
}
