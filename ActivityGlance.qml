import QtQuick
import qs.Commons

// One activity in the notch: a glyph and a title on the resting row, and the
// body underneath it, wrapped, so it can be read.
//
// Placement: the notch widens symmetrically around this, and grows **down** for
// the body the way it grows down for a panel — top edge still on the screen
// edge, square top corners, its own bottom radius. There is still no second
// surface, nothing off-centre and nothing hanging below the notch detached from
// it (DESIGN-PHILOSOPHY.md, 1a).
//
// It used to be one elided line, on the grounds that the full text belongs to
// the open notch. In use that was a notification you could see arriving and
// could not read: a title cut mid-word, a body reduced to three words and an
// ellipsis, gone in four seconds, with no way to open what had already passed.
// A notification nobody can read is not a display of a notification. So the
// body gets up to `bodyLines` rows and elides after those — still compact by
// construction, still one surface, but readable.
//
// Urgency is not a colour. The notch is one palette, white on black, and a
// critical line painted red would be the only hue on the surface
// (DESIGN-PHILOSOPHY.md, 2). Omarchy's own toast still carries its colour.
Item {
  id: row

  property var bar: null
  property var activity: null

  // What the notch can give this. The body wraps to it; the notch takes the
  // width back from `implicitWidth`, so a short notification stays narrow.
  property real maxWidth: Style.space(420)
  // Rows of body, after the title's row. Two keeps the notch a notch.
  property int bodyLines: 2

  readonly property string glyph: activity ? String(activity.glyph || "") : ""
  readonly property string title: activity ? String(activity.title || "") : ""
  readonly property string detail: activity ? String(activity.detail || "") : ""
  readonly property color foreground: bar ? bar.notchForeground : "#ffffff"
  readonly property color secondary: bar ? bar.notchSecondaryText : Qt.rgba(1, 1, 1, 0.6)
  readonly property real restHeight: bar ? bar.notchCompactHeight : Style.space(32)
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  // The natural width of the widest part, capped. `body.implicitWidth` is its
  // unwrapped width, which does not depend on the width it is given, so this
  // settles instead of chasing itself.
  readonly property real naturalWidth: Math.max(line.implicitWidth, body.implicitWidth)
  readonly property bool hasBody: detail !== ""

  implicitWidth: Math.min(maxWidth, naturalWidth)
  // The title keeps the resting row exactly as it was; the body is what grows
  // the notch, and only as far as it actually uses.
  implicitHeight: restHeight + (hasBody && body.lineCount > 0
    ? body.contentHeight + Style.space(10) : 0)

  Row {
    id: line
    y: 0
    height: row.restHeight
    spacing: Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: row.glyph !== ""
      text: row.glyph
      color: row.foreground
      font.family: row.family
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: row.title !== ""
      text: row.title
      color: row.foreground
      font.family: row.family
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
      elide: Text.ElideRight
      maximumLineCount: 1
      width: Math.min(implicitWidth, row.implicitWidth - (row.glyph !== "" ? parent.spacing + Style.space(16) : 0))
    }
  }

  Text {
    id: body
    y: row.restHeight - Style.space(4)
    width: row.implicitWidth
    textFormat: Text.PlainText
    visible: row.hasBody
    text: row.detail
    color: row.secondary
    font.family: row.family
    font.pixelSize: Style.font.body
    wrapMode: Text.Wrap
    elide: Text.ElideRight
    maximumLineCount: row.bodyLines
  }
}
