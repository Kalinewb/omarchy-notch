import QtQuick
import Quickshell
import Quickshell.Io
import "notch" as Notch

// The real Bar.qml in a throwaway Quickshell instance, with no widgets and a
// notch config read from $NOTCH_HARNESS_CONFIG (JSON for `bar.notch`). It draws
// on the real screen, on top of the live bar, for as long as the instance runs.
// dev/geometry.sh drives it over IPC (`notch` target).
ShellRoot {
  id: harness

  // A setting changed while the notch runs, for the checks that are about what
  // happens when the user reaches for a switch rather than what a notch looks
  // like when it starts. The notch reads `bar.notch` as one object, so this
  // replaces it whole, the way writing shell.json does.
  property var notchConfig: JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}")

  IpcHandler {
    target: "harness"
    function setNotch(json: string): string {
      try { harness.notchConfig = JSON.parse(json) } catch (e) { return "bad-json" }
      return "ok"
    }
  }

  Notch.Bar {
    barConfig: ({
      position: "top",
      transparent: false,
      layout: { left: [], center: [], right: [] },
      notch: harness.notchConfig
    })
  }
}
