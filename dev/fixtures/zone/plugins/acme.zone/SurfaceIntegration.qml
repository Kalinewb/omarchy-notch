import QtQuick

// A panel whose header controls sit where the route says, for dev/backzone.sh
// (SURFACE-HOSTING.md section 15, the way-back zone).
Item {
  id: integration

  property var surfaceHost: null
  property bool available: true
  property Component panel: Component { ZonePanel {} }
}
