import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Takes a Hyprland focus grab of its own for 400 ms: Hyprland ends any other
// client's grab (sending it `cleared`), as a click outside that grab would.
// dev/surface.sh runs it as its own quickshell instance to test click-outside closing.
ShellRoot {
  PanelWindow {
    id: w
    anchors { top: true; left: true }
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "notch-test-grabber"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}
    HyprlandFocusGrab {
      id: g
      windows: [w]
      active: false
      onActiveChanged: console.log("GRABBER active=" + active + " " + Date.now())
      onCleared: console.log("GRABBER cleared " + Date.now())
    }
    Timer { interval: 500; running: true; onTriggered: { console.log("GRABBER activate " + Date.now()); g.active = true } }
    Timer { interval: 900; running: true; onTriggered: { console.log("GRABBER release " + Date.now()); g.active = false } }
    Timer { interval: 1100; running: true; onTriggered: Qt.quit() }
  }
}
