pragma Singleton
import QtQuick

// How a menu companion finds the notch, inside one shell process.
//
// Omarchy gives plugins no way to reach each other, so the companion plugin
// (graveklar.notch-menu, which Omarchy routes every omarchy.menu call to)
// loads bridge/Connector.qml from the notch's folder by URL. Both files
// resolve this same qmldir, so both see this one object.
//
// `target` is deliberately not the notch's Bar root: anything that can load
// the Connector could then reach the notch's shell facade and settings. It is
// MenuCompanion.qml's narrow menuApi, which can only open, close and refresh
// the menu and answer whether it is open.
QtObject {
  // Bumped when menuApi's shape changes. The companion refuses a mismatch and
  // uses Omarchy's own menu instead. Singleton code is cached for the life of
  // the shell process, so a change needs a shell restart (install.sh does one).
  readonly property int apiVersion: 1

  // MenuCompanion.qml's menuApi, while a notch is running here.
  property var target: null

  // The companion's go-between, while one is loaded here.
  property var facade: null
}
