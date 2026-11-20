import QtQuick
import qs.Commons

// What an import would change, in the Settings row's fold (plan-export.md 4):
// flat lines in the panel's own words, `Label  from → to`, never a count of
// characters or a key name. The ones that change a keybind or a plugin list come
// first and are never folded; the rest are cut at five. Then what was left out
// (a value past its ceiling shows as `Width  5000 → 2400`) and how many widgets
// were reordered. The text is the imported file's, so it is plain text, never markup.
Column {
  id: root

  property var page: null
  // `import --stage`'s output; null when there is nothing to show.
  property var plan: null

  readonly property int limit: 5
  readonly property var changes: plan && plan.changes ? plan.changes : []
  readonly property var skipped: plan && plan.skipped ? plan.skipped : []
  readonly property var moves: plan && plan.moves ? plan.moves : []
  readonly property var danger: changes.filter(function(c) { return c.danger })
  readonly property var rest: changes.filter(function(c) { return !c.danger })
  // The lines, in order: [label, value].
  readonly property var lines: {
    var out = danger.concat(rest.slice(0, limit)).map(function(c) { return [c.label, c.from + " → " + c.to] })
    if (rest.length > limit) out.push(["", "+ " + (rest.length - limit) + " more"])
    if (moves.length > 0) out.push(["Widget order", moves.length + " moved"])
    if (skipped.length > 0) out.push(["Skipped", String(skipped.length)])
    skipped.slice(0, 4).forEach(function(s) {
      out.push(["    " + s.label, (s.from !== undefined ? s.from + " → " + s.to + "  " : "") + s.reason])
    })
    if (skipped.length > 4) out.push(["", "    + " + (skipped.length - 4) + " more"])
    return out
  }

  width: parent ? parent.width : 0
  spacing: Style.space(1)

  Repeater {
    model: root.lines
    Item {
      required property var modelData
      width: root.width
      height: Style.space(20)

      Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: modelData[0]
        color: root.page ? root.page.dim : "#999999"
        font.family: root.page ? root.page.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        anchors.left: label.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        text: modelData[1]
        color: root.page ? root.page.foreground : "#ffffff"
        font.family: root.page ? root.page.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
