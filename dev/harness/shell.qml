import QtQuick
import Quickshell
import "notch" as Notch

// The real Bar.qml in a throwaway Quickshell instance, with no widgets and a
// notch config read from $NOTCH_HARNESS_CONFIG (JSON for `bar.notch`). It draws
// on the real screen, on top of the live bar, for as long as the instance runs.
// dev/geometry.sh drives it over IPC (`notch` target).
ShellRoot {
  Notch.Bar {
    barConfig: ({
      position: "top",
      transparent: false,
      layout: { left: [], center: [], right: [] },
      notch: JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}")
    })
  }
}
