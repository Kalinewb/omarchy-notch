import QtQuick
import "notch/keys.js" as KeyCombo

// Runs keys.js over a table of key presses and prints each result as
// `KEYS <json>`. Driven by dev/keys.sh with qml6 (no window needed).
QtObject {
  Component.onCompleted: {
    var M = Qt.MetaModifier, C = Qt.ControlModifier, A = Qt.AltModifier, S = Qt.ShiftModifier
    var cases = [
      ["SUPER + N", Qt.Key_N, M],
      ["SUPER + ALT + N", Qt.Key_N, M | A],
      ["order is SUPER CTRL ALT SHIFT", Qt.Key_K, S | A | C | M],
      ["F12 alone", Qt.Key_F12, 0],
      ["CTRL + RETURN", Qt.Key_Return, C],
      ["SUPER + SPACE", Qt.Key_Space, M],
      ["ALT + 5", Qt.Key_5, A],
      ["SUPER + LEFT", Qt.Key_Left, M],
      ["plain letter", Qt.Key_N, 0],
      ["SHIFT + letter", Qt.Key_N, S],
      ["modifier held alone", Qt.Key_Meta, M],
      ["unbindable key", Qt.Key_VolumeUp, M]
    ]
    for (var i = 0; i < cases.length; i++) {
      var r = KeyCombo.combo(cases[i][1], cases[i][2])
      console.log("KEYS " + JSON.stringify({ name: cases[i][0], combo: r.combo, waiting: r.waiting, reason: r.reason }))
    }
    console.log("KEYS " + JSON.stringify({ name: "escape code", escape: KeyCombo.ESCAPE === Qt.Key_Escape }))
    Qt.exit(0)
  }
}
