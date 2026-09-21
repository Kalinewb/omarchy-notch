import QtQuick
import qs.Commons

// Omarchy's on-screen display, drawn in the notch.
//
// The OSD is what answers a volume key, a brightness key, a media button: an
// icon, sometimes a bar and a readout, sometimes a word, for about a second.
// Omarchy draws it as a card at the bottom of the screen. Here it is one row
// in the notch, which widens around it and shrinks back — the same shape a
// peek uses, because it is the same kind of event: something happened, look
// once, it goes.
//
// The payload is Omarchy's, unchanged (`osd-model.js`, vendored from
// `omarchy.osd` so the glyph for "volume-muted" is the glyph Omarchy picks and
// not a second opinion). What is not Omarchy's is the drawing: no card, no
// background, no theme colour, no accent on the bar — the notch is one surface
// and one palette, so the fill is the notch's foreground at an alpha
// (DESIGN-PHILOSOPHY.md, 1 and 2).
Item {
  id: row

  property var bar: null
  // The OSD's state, as `osd-model.js` resolved it: icon, message,
  // hasProgress, value, maxValue.
  property var osd: null

  readonly property string icon: osd ? String(osd.icon || "") : ""
  readonly property string message: osd ? String(osd.message || "") : ""
  readonly property bool hasProgress: !!osd && osd.hasProgress === true
  readonly property real fraction: {
    if (!hasProgress) return 0
    var max = Math.max(1, Number(osd.maxValue) || 1)
    return Math.max(0, Math.min(1, (Number(osd.value) || 0) / max))
  }

  readonly property color foreground: bar ? bar.notchForeground : "#ffffff"
  readonly property color secondary: bar ? bar.notchSecondaryText : Qt.rgba(1, 1, 1, 0.6)
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property real restHeight: bar ? bar.notchCompactHeight : Style.space(32)
  // The bar's width is fixed, not measured: a progress bar that resized itself
  // as the number changed would make the notch breathe on every volume step.
  readonly property real trackWidth: Style.space(120)
  readonly property real maxMessageWidth: Style.space(260)

  // The message is measured, not asked: giving a Text a width derived from its
  // own implicitWidth is a binding loop, and a loop here took the notch's
  // whole target width out with it (`osdWidth` came back NaN, so the notch
  // grew to nothing). Omarchy's own OSD measures with TextMetrics for exactly
  // this reason.
  TextMetrics {
    id: messageMetrics
    font.family: row.family
    font.pixelSize: Style.font.body
    font.weight: row.hasProgress ? Font.Normal : Font.DemiBold
    text: row.message
  }

  implicitWidth: line.implicitWidth
  implicitHeight: restHeight

  Row {
    id: line
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: row.icon !== ""
      text: row.icon
      color: row.foreground
      font.family: row.family
      font.pixelSize: Style.font.body
    }

    // The bar. Its own alphas, not the theme's: the track is the foreground at
    // the notch's normal fill, the fill is the foreground itself.
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      visible: row.hasProgress
      width: row.trackWidth
      height: Math.max(2, Math.round(row.restHeight / 10))
      radius: height / 2
      color: Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, 0.22)

      Rectangle {
        width: Math.round(parent.width * row.fraction)
        height: parent.height
        radius: parent.radius
        color: row.foreground
        // The value moves on the notch's own easing, so a held volume key
        // reads as one movement rather than a series of steps.
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      }
    }

    // The readout, or the word: "40%", "Muted", a track title on a media OSD.
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: row.message !== ""
      text: row.message
      color: row.hasProgress ? row.secondary : row.foreground
      font.family: row.family
      font.pixelSize: Style.font.body
      font.weight: row.hasProgress ? Font.Normal : Font.DemiBold
      elide: Text.ElideRight
      maximumLineCount: 1
      width: Math.min(messageMetrics.advanceWidth, row.maxMessageWidth)
    }
  }
}
