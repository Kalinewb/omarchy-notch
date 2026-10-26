import QtQuick
import Quickshell
import "notch" as Notch

// dev/detached.sh: prints what Detached.qml would run for one job, and quits.
ShellRoot {
  Notch.Detached { id: detached }
  Component.onCompleted: {
    console.log("ARGV " + JSON.stringify(detached.argv("unit-prefix", ["job", "run"], ["NOTCH_TEST_ONE", "NOTCH_TEST_UNSET"], "NOTCH_TEST_DETACH")))
    Qt.callLater(Qt.quit)
  }
}
