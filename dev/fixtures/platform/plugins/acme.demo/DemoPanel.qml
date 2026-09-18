import QtQuick

// The panel, drawn inside the notch. Everything it paints with comes from
// `notchHost`: a panel never picks its own colours or radius.
Item {
  id: panel

  // Set by the notch, once.
  property var notchHost: null
  property string notchScreen: ""
  // Bound by the notch: a later openPanel at another route changes this on the
  // same item.
  property string route: "main"
  property real maxWidth: 400
  property real maxHeight: 400
  signal closeRequested()

  readonly property color background: notchHost ? notchHost.color : "#000000"
  readonly property color foreground: notchHost ? notchHost.foreground : "#ffffff"

  property int opens: 0
  property int closes: 0
  function open(next) { panel.opens += 1 }
  function close() { panel.closes += 1 }

  implicitWidth: route === "tall" ? maxWidth : 320
  implicitHeight: route === "tall" ? maxHeight : 180

  focus: true
  Keys.onEscapePressed: panel.closeRequested()

  Rectangle {
    anchors.centerIn: parent
    width: 120
    height: 28
    radius: panel.notchHost ? panel.notchHost.radiusFor(Math.min(width, height)) : 8
    color: "transparent"
    border.width: 1
    border.color: panel.foreground

    Text {
      anchors.centerIn: parent
      text: "Acme · " + panel.route
      color: panel.foreground
      font.family: panel.notchHost ? panel.notchHost.fontFamily : ""
    }
  }
}
