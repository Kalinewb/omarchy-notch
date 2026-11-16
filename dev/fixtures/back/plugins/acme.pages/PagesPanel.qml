import QtQuick

// Pages: ["home", "p1", "p2", ...]. The route sets how deep it opens:
//   main        the home alone
//   deep:N      the home and N pages on top of it
//   mute:N      the same, but goBackInside() answers nothing when it went back
//   raises:N    the same, but goBackInside() throws
// The page is written to the log on every change (dev/back.sh reads it).
Item {
  id: panel

  property var surfaceHost: null
  property string surfaceScreen: ""
  property string route: "main"
  property real maxWidth: 400
  property real maxHeight: 400
  signal closeRequested()

  property var pages: ["home"]
  readonly property bool canGoBack: pages.length > 1
  onPagesChanged: console.log("PAGES " + pages.join("/"))

  property int escapes: 0

  function open(next) {
    var at = String(next || "main").split(":")
    var made = ["home"]
    for (var i = 1; i <= (Number(at[1]) || 0); i++) made.push("p" + i)
    pages = made
  }

  function goBackInside() {
    if (pages.length < 2) return false
    pages = pages.slice(0, -1)
    var how = String(route).split(":")[0]
    if (how === "raises") throw new Error("a panel that fails")
    if (how === "mute") return
    return true
  }

  implicitWidth: 320
  implicitHeight: 180

  focus: true
  Keys.onEscapePressed: { escapes += 1; if (pages.length > 1) pages = pages.slice(0, -1); else closeRequested() }
}
