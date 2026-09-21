import QtQuick
import Quickshell

// The panel entry point, which is a shim.
//
// Omarchy builds this when something summons `omarchy.osd` from inside the
// shell -- the audio panel, the media service -- and drops it afterwards. All
// the deciding lives in Service.qml, which is loaded from the shell's start
// and owns the `osd` IPC target the CLI calls, so both ways in end up in the
// same place.
Item {
  id: root
  visible: false

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  Loader {
    id: link
    asynchronous: false
    source: Quickshell.env("NOTCH_OSD_CONNECTOR_URL") || Qt.resolvedUrl("../kalinewb.notch/bridge/Connector.qml")
  }
  readonly property var bridge: link.item ? link.item.osdBridge : null
  readonly property var service: bridge ? bridge.service : null

  readonly property bool opened: !!service && service.opened === true

  function open(payloadJson) {
    if (service) service.open(payloadJson)
    else console.warn("kalinewb.notch-osd: no service to show an OSD with")
  }

  function close() { if (service) service.close() }
}
