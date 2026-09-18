import QtQuick

// The panel, drawn inside the notch. Everything it paints with comes from
// `surfaceHost`: a panel never picks its own colours or radius.
Item {
  id: panel

  // Set by the notch, once.
  property var surfaceHost: null
  property string surfaceScreen: ""
  // Bound by the notch: a later openPanel at another route changes this on the
  // same item.
  property string route: "main"
  property real maxWidth: 400
  property real maxHeight: 400
  signal closeRequested()

  readonly property color background: surfaceHost ? surfaceHost.color : "#000000"
  readonly property color foreground: surfaceHost ? surfaceHost.foreground : "#ffffff"

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
    radius: panel.surfaceHost ? panel.surfaceHost.radiusFor(Math.min(width, height)) : 8
    color: "transparent"
    border.width: 1
    border.color: panel.foreground

    Text {
      anchors.centerIn: parent
      text: "Acme · " + panel.route
      color: panel.foreground
      font.family: panel.surfaceHost ? panel.surfaceHost.fontFamily : ""
    }
  }
}
