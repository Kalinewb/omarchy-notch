import QtQuick

// Stands in for Omarchy's own OSD (shell/plugins/osd/Osd.qml) in dev/osd.sh.
// The real one maps a full-screen layer-shell window, which a test must not do
// on the user's screen. It answers the same lifecycle the go-between uses --
// open(payloadJson), close(), opened -- and records what it was asked.
Item {
  id: root
  visible: false

  property string omarchyPath: ""
  property var shell: null

  property bool opened: false
  property int opens: 0
  property int closes: 0
  property string lastPayload: ""

  function open(payloadJson) {
    lastPayload = String(payloadJson || "")
    opens += 1
    opened = true
  }

  function close() {
    if (opened) closes += 1
    opened = false
  }
}
