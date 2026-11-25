import QtQuick
import qs.Commons
import "settings-tips.js" as Tips

// The settings panel's foot line (plan-settings.md 4): one reserved line, empty
// when nothing is hovered or focused, so the panel never changes height for it.
// Plain text in the label colour, elided on the right; nothing to place, clamp
// or clip. A tip shows after the pointer rests on a row (hoverMs) or the
// keyboard cursor does (focusMs); while one shows the next row swaps at once;
// it goes hideMs after the pointer leaves every row, and at once on hide().
// The fade is opacity only.
Item {
  id: tip

  property color color: "#ffffff"
  property string fontFamily: Style.font.family
  // A hairline over the foot and a smaller size, so a description reads as a note under the
  // rows and not as one more setting name (it is in the same grey as the values).
  property bool divider: false
  readonly property int hoverMs: 400
  readonly property int focusMs: 250
  readonly property int hideMs: 120
  readonly property int fadeMs: 90

  property bool pending: false
  property bool shown: false
  property string text: ""
  property string source: ""
  property string rowId: ""
  property string wanted: ""
  // A page whose rows have no entry in settings-tips.js says where the text is: id -> text.
  property var lookup: null

  // `from` is "hover" or "focus". The text is the id's tip in settings-tips.js
  // unless the page brings its own (a Setup point's summary).
  function want(id, from, own) {
    hideTimer.stop()
    var next = own !== undefined ? String(own) : lookup ? String(lookup(id) || "") : (Tips.t[id] || "")
    if (next === "") { hide(); return }
    rowId = id
    wanted = next
    source = from
    if (shown) { text = next; return }
    pending = true
    showTimer.interval = from === "hover" ? hoverMs : focusMs
    showTimer.restart()
  }
  // The pointer left a row; a focus tip stays.
  function leave() { if (source === "hover") hideTimer.restart() }
  function hide() {
    showTimer.stop()
    hideTimer.stop()
    pending = false
    shown = false
    source = ""
    rowId = ""
  }
  function report() {
    return { pending: pending, shown: shown, text: text, source: source, id: rowId, truncated: label.truncated,
             color: String(label.color).toUpperCase(), height: height }
  }

  Timer {
    id: showTimer
    onTriggered: { tip.text = tip.wanted; tip.pending = false; tip.shown = true }
  }
  Timer { id: hideTimer; interval: tip.hideMs; onTriggered: tip.hide() }

  Rectangle {
    visible: tip.divider
    width: parent.width
    height: 1
    color: Qt.rgba(tip.color.r, tip.color.g, tip.color.b, 0.25)
  }

  Text {
    id: label
    width: parent.width
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: tip.divider ? 2 : 0
    text: tip.text
    elide: Text.ElideRight
    color: tip.color
    font.family: tip.fontFamily
    font.pixelSize: tip.divider ? Style.font.caption : Style.font.bodySmall
    opacity: tip.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: tip.fadeMs; easing.type: Easing.OutCubic } }
  }
}
