import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

// Omarchy's Ui/NumberField.qml (4.0.3) for the notch: its box, outline and
// text selection are the notch's text colour at the theme's alpha, never a
// colour the theme pinned in its style tokens (see NotchButton.qml). The
// verbatim upstream file is dev/upstream/ui/NumberField.qml.
Column {
  id: root

  property string label: ""
  property int value: 0
  property int from: 0
  property int to: 100
  property int stepSize: 1
  property color foreground: "#ffffff"
  property color accent: foreground
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real fieldWidth: Style.spacing.numberFieldWidth
  property bool hasCursor: false
  property bool _hovered: false
  property alias field: spin

  signal modified(int value)
  signal hovered(bool on)

  spacing: Style.spacing.md

  Text {
    textFormat: Text.PlainText
    visible: root.label !== ""
    text: root.label
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  QQC.SpinBox {
    id: spin
    width: root.fieldWidth
    implicitHeight: Math.max(Style.spacing.controlHeight, root.fontSize + Style.spacing.controlPaddingY * 2)
    from: root.from
    to: root.to
    stepSize: root.stepSize
    value: root.value
    editable: true
    font.family: root.fontFamily
    font.pixelSize: root.fontSize

    readonly property bool _focused: spin.activeFocus
    readonly property bool _hot: root._hovered || root.hasCursor
    readonly property string _state: _focused ? "focus" : (_hot ? "hover-cursor" : "normal")
    readonly property var _borderSpec: ({
      color: Util.alpha(root.foreground, _focused ? Style.focusBorderAlpha : (_hot ? Style.hoverBorderAlpha : Style.normalBorderAlpha)),
      widths: Border.controlSpec(_state, root.foreground, root.foreground).widths,
      gradient: { colors: [], angle: 0, enabled: false } })

    leftPadding: Border.left(_borderSpec) + Style.spacing.controlPaddingX
    rightPadding: Border.right(_borderSpec) + Style.spacing.controlPaddingX
    topPadding: Border.top(_borderSpec)
    bottomPadding: Border.bottom(_borderSpec)

    onValueModified: root.modified(value)

    background: BorderSurface {
      color: Util.alpha(root.foreground, spin._focused ? Style.focusFillAlpha : (spin._hot ? Style.hoverFillAlpha : Style.normalFillAlpha))
      borderSpec: spin._borderSpec
      radius: Style.cornerRadius

      HoverHandler {
        onHoveredChanged: {
          root._hovered = hovered
          root.hovered(hovered)
        }
      }
    }

    contentItem: TextInput {
      text: spin.displayText
      font: spin.font
      color: root.foreground
      selectionColor: Util.alpha(root.foreground, Style.selectionFillAlpha)
      selectedTextColor: root.foreground
      horizontalAlignment: Qt.AlignHCenter
      verticalAlignment: Qt.AlignVCenter
      readOnly: !spin.editable
      validator: spin.validator
      inputMethodHints: Qt.ImhFormattedNumbersOnly
    }
  }
}
