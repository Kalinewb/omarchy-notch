pragma Singleton
import QtQuick

// How the notifications companion finds the notch, inside one shell process.
//
// The same arrangement as NotchMenuBridge and NotchOsdBridge, and separate
// from both: three companions, three narrow APIs. The companion plugin
// (kalinewb.notch-notifications, which Omarchy loads in place of
// omarchy.notifications) loads bridge/Connector.qml from the notch's folder by
// URL; both files resolve this same qmldir, so both see this one object.
//
// `target` is NotificationsCompanion.qml's notificationsApi: whether the notch
// is taking Omarchy's toasts right now, and since when. Nothing else.
QtObject {
  // Bumped when notificationsApi's shape changes. The companion treats a
  // mismatch as "no notch" and leaves Omarchy's toast on screen.
  readonly property int apiVersion: 1

  // NotificationsCompanion.qml's notificationsApi, while a notch is running here.
  property var target: null

  // The companion's service, while one is loaded here, for the notch's report.
  property var facade: null
}
