import QtQuick
import QtQuick.Window

// shaders/mono.frag.qsb over known colours, rendered offscreen to a PNG so the
// hue that comes out of a hosted panel can be measured rather than described.
// Run by dev/colours.sh under QT_QPA_PLATFORM=offscreen with `qml6`:
//
//   qml6 mono-pixels.qml -- out=/path/mono.png
//
// Each swatch is 40×40 on the notch's black, laid out left to right in the
// order of `swatches`, and its centre is printed as `MONO <hex> <x> <y>` so
// the script samples exactly the right pixel. The top row is drawn through the
// layer, the bottom row is the same colours untouched -- so a run also shows
// the shader did something, not just that black came out black.
Window {
  id: win
  visible: true
  color: "#000000"

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
  readonly property string out: args.out || "mono.png"

  // The real offenders, then the cases that must not move: the accent this
  // machine's Power Manager paints with, System Monitor's, the two near-black
  // navies they fill their BUTTONS with (an accent at 12-15 % over black --
  // the ones that still read as dark after a faithful desaturation, which is
  // what the lift is for), Catppuccin Latte's pinned token, the notch's own
  // white and grey, and a 20 % white fill to prove premultiplied alpha
  // survives.
  readonly property var swatches: [
    "#1E68F9", "#1C60E7", "#0B1F46", "#1F3257", "#4C4F69", "#FF453A", "#30D158",
    "#FFFFFF", "#000000", "#808080", "#33FFFFFF"
  ]
  readonly property int cell: 40

  width: cell * swatches.length
  height: cell * 2

  Item {
    id: scene
    anchors.fill: parent

    // Through the layer, exactly as the notch draws a hosted panel.
    Item {
      id: hosted
      width: parent.width
      height: win.cell
      layer.enabled: true
      layer.effect: ShaderEffect { fragmentShader: "notch/shaders/mono.frag.qsb" }

      Row {
        Repeater {
          model: win.swatches
          Rectangle { width: win.cell; height: win.cell; color: modelData }
        }
      }
    }

    // The same colours, untouched.
    Row {
      y: win.cell
      Repeater {
        model: win.swatches
        Rectangle { width: win.cell; height: win.cell; color: modelData }
      }
    }
  }

  Component.onCompleted: {
    for (var i = 0; i < swatches.length; i++)
      console.log("MONO " + swatches[i] + " " + (i * cell + cell / 2) + " " + (cell / 2))
    console.log("MONO_ROW2_Y " + (cell + cell / 2))
  }

  // One frame after the first, so the layer has been rendered.
  Timer {
    interval: 250
    running: true
    onTriggered: scene.grabToImage(function (result) {
      result.saveToFile(win.out)
      console.log("MONO saved " + win.out)
      Qt.quit()
    })
  }
}
