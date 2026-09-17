import QtQuick
import Quickshell

// Stands in for Omarchy's own menu (shell/plugins/menu/Menu.qml) in
// dev/menu-replace.sh. The real one opens a full-screen window that takes the
// keyboard outright, which a test must never do on the user's screen. It
// answers the same lifecycle the go-between uses, and records what it was
// asked to do.
Item {
  id: root
  visible: false

  property string omarchyPath: ""
  property var shell: null

  property bool opened: false
  property bool requestActive: false
  property string selectionFile: ""
  property string doneFile: ""
  property string lastPayload: ""
  property int opens: 0
  property int closes: 0
  property int refreshes: 0
  // How many desktop entries the app library it was handed can see.
  readonly property int appEntries: {
    var library = shell ? shell.appLibrary : null
    if (!library) return -1
    try { return library.sortedEntries("").length } catch (e) { return -2 }
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    root.lastPayload = String(payloadJson || "")
    root.opens += 1
    root.selectionFile = String(payload.selectionFile || "")
    root.doneFile = String(payload.doneFile || "")
    root.requestActive = !!root.doneFile
    root.opened = true
    return "ok"
  }

  function close() {
    root.closes += 1
    root.opened = false
    root.requestActive = false
    return "ok"
  }

  function refresh() { root.refreshes += 1; return "ok" }
  function ping() { return "ok" }
}
