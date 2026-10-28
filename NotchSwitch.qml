import QtQuick
import qs.Commons
import qs.Ui

// Omarchy's ToggleSwitch, with the notch's colours and radius. `toggled`
// fires before `checked` changes, as ToggleSwitch's does. The knob settles
// on the controls' spring; a press dips to 0.97.
Item {
  id: toggle
  // The settings panel: its colours, radius and the controls' spring.
  property var panel: null
  property bool checked: false
  signal toggled()
  readonly property int trackHeight: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))
  readonly property int trackWidth: Math.round(trackHeight * 1.9)
  readonly property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
  readonly property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))
  implicitWidth: trackWidth
  implicitHeight: trackHeight
  scale: switchMouse.pressed ? 0.97 : 1
  Behavior on scale {
    NumberAnimation {
      duration: panel.still ? 0 : switchMouse.pressed ? 60 : panel.settleMs
      easing.type: switchMouse.pressed ? Easing.OutCubic : Easing.BezierSpline
      easing.bezierCurve: panel.settleCurve
    }
  }

  // Fills are the text colour at the theme's alpha (NotchButton.qml).
  readonly property string borderState: toggle.checked ? "selected" : (switchMouse.containsMouse ? "hover-cursor" : "normal")
  readonly property color trackColor: track.color
  readonly property color knobColor: knob.color

  BorderSurface {
    id: track
    anchors.fill: parent
    radius: panel.radiusFor(Math.min(width, height))
    color: Util.alpha(panel.foreground, toggle.checked ? Style.selectedFillAlpha : Style.normalFillAlpha)
    borderSpec: ({ color: Util.alpha(panel.foreground, toggle.checked ? Style.selectedBorderAlpha : (switchMouse.containsMouse ? Style.hoverBorderAlpha : Style.normalBorderAlpha)),
                   widths: Border.controlSpec(toggle.borderState, panel.foreground, panel.foreground).widths,
                   gradient: { colors: [], angle: 0, enabled: false } })
    Behavior on color { ColorAnimation { duration: panel.still ? 0 : 90 } }

    Rectangle {
      id: knob
      width: toggle.knobSize
      height: toggle.knobSize
      radius: panel.radiusFor(Math.min(width, height))
      x: toggle.checked ? track.width - width - toggle.knobInset : toggle.knobInset
      anchors.verticalCenter: parent.verticalCenter
      color: toggle.checked ? panel.foreground : Qt.darker(panel.foreground, 1.25)
      Behavior on x { NumberAnimation { duration: panel.settleMs; easing.type: Easing.BezierSpline; easing.bezierCurve: panel.settleCurve } }
      Behavior on color { ColorAnimation { duration: panel.still ? 0 : 90 } }
    }
  }

  MouseArea {
    id: switchMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: toggle.toggled()
  }
}
