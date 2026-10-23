// Stands in for Quickshell in dev/notifications-companion.sh: env() from a map
// the test sets, and a screens list, which is all the companion reads.
pragma Singleton
import QtQuick
QtObject {
  property var envMap: ({})
  property var screens: []
  function env(name) { return envMap[name] || "" }
}
