import QtQuick
import QtQuick.Window
import "notch" as Notch

// BottomGlow.qml behind Island.qml, rendered offscreen to a PNG so the halo can be
// sampled. Run by dev/glow-bottom.sh with the OpenGL RHI backend (the software
// renderer cannot run the blur):
//
//   qml6 bottomglow-pixels.qml -- w=180 h=32 r=10 fillet=10 color=#FFB340 presence=1 out=glow.png
Window {
  id: win
  visible: true
  color: "transparent"

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
  function num(key, fallback) { var n = Number(args[key]); return isFinite(n) && args[key] !== undefined ? n : fallback }

  readonly property real margin: Math.ceil(glow.maxReach) + 30
  width: Math.ceil(island.width + 2 * margin)
  height: Math.ceil(island.height + margin)

  Item {
    id: scene
    anchors.fill: parent

    Notch.BottomGlow {
      id: glow
      x: island.x + island.barX
      y: 0
      barWidth: island.barWidth
      barHeight: island.barHeight
      bottomRadius: island.bottomR
      color: win.args.color || "#FFB340"
      presence: win.num("presence", 1)
      size: win.num("size", 80)
      strength: win.num("strength", 0.24)
    }

    Notch.Island {
      id: island
      // `offset` shifts the bar by a fraction of a pixel, so pixel centres can
      // land at whole-pixel distances from its edges.
      x: win.margin + win.num("offset", 0)
      y: 0
      barWidth: win.num("w", 180)
      barHeight: win.num("h", 32)
      bottomRadius: win.num("r", 10)
      filletRadius: win.num("fillet", 10)
    }
  }

  function log(key, value) { console.log("GLOW " + key, value) }

  Timer {
    interval: 600
    running: true
    onTriggered: {
      win.log("barX", island.x + island.barX)
      win.log("barWidth", island.barWidth)
      win.log("barHeight", island.barHeight)
      win.log("reach", glow.reach)
      scene.grabToImage(function(result) {
        win.log("saved", result.saveToFile(win.args.out || "glow.png"))
        Qt.exit(0)
      })
    }
  }

  Timer { interval: 10000; running: true; onTriggered: { win.log("timeout", true); Qt.exit(1) } }
}
