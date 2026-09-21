pragma Singleton
import QtQuick

// How the OSD companion finds the notch, inside one shell process.
//
// The same arrangement as NotchMenuBridge, and separate from it on purpose:
// two companions, two narrow APIs, and neither can reach the other's. The
// companion plugin (kalinewb.notch-osd, which Omarchy routes every
// `omarchy.osd` call to) loads bridge/Connector.qml from the notch's folder by
// URL; both files resolve this same qmldir, so both see this one object.
//
// `target` is deliberately not the notch's Bar root: anything that can load
// the Connector could then reach the notch's shell facade and settings. It is
// OsdCompanion.qml's narrow osdApi, which can only show an OSD, hide it, and
// answer whether the notch wants them.
QtObject {
  // Bumped when osdApi's shape changes. The companion refuses a mismatch and
  // uses Omarchy's own OSD instead. Singleton code is cached for the life of
  // the shell process, so a change needs a shell restart (install.sh does one).
  readonly property int apiVersion: 1

  // OsdCompanion.qml's osdApi, while a notch is running here.
  property var target: null

  // The companion's go-between, while one is loaded here.
  property var facade: null
  // The same object, for the companion's own panel entry point to forward to:
  // Omarchy builds that entry point on a summon and drops it afterwards, while
  // the service is there from the shell's start.
  property var service: null
}
