import QtQuick
import qs.Commons

// One activity, drawn as a line in the resting notch: a glyph, the title, and
// the detail in secondary text.
//
// Placement is the binding contract of 18 Sep: the notch widens symmetrically
// around this row and does nothing else. There is no second surface, no panel
// below the notch and no asymmetric growth -- so the content is compact by
// construction, and the full body belongs to the open notch.
//
// Urgency is not a colour. The notch is one palette, white on black, and a
// critical line painted red would be the only hue on the surface
// (DESIGN-PHILOSOPHY.md, 2). Omarchy's own toast still carries its colour.
Item {
  id: row

  property var bar: null
  property var activity: null

  readonly property string glyph: activity ? String(activity.glyph || "") : ""
  readonly property string title: activity ? String(activity.title || "") : ""
  readonly property string detail: activity ? String(activity.detail || "") : ""
  readonly property color foreground: bar ? bar.notchForeground : "#ffffff"
  readonly property color secondary: bar ? bar.notchSecondaryText : Qt.rgba(1, 1, 1, 0.6)

  implicitWidth: line.implicitWidth
  implicitHeight: bar ? bar.notchCompactHeight : Style.space(32)

  Row {
    id: line
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: row.glyph !== ""
      text: row.glyph
      color: row.foreground
      font.family: row.bar ? row.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: row.title !== ""
      text: row.title
      color: row.foreground
      font.family: row.bar ? row.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: row.detail !== ""
      text: row.detail
      color: row.secondary
      font.family: row.bar ? row.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      maximumLineCount: 1
    }
  }
}
