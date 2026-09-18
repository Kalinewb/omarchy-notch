import QtQuick
import Quickshell
import Quickshell.Io

// The plugin's bar widget. Under the notch it is handed `surfaceHost` and the
// screen it is on; under any other bar it gets neither, and nothing changes.
Item {
  id: widget

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property var surfaceHost: null
  property string surfaceScreen: ""

  // The plugin's own popup, for when the notch isn't there or declines.
  property bool ownPopupShown: false

  implicitWidth: 24
  implicitHeight: 24

  function press(route) {
    var result = surfaceHost ? surfaceHost.openPanel(route, surfaceScreen) : "no-host"
    // Per-event: the popup is skipped only for the event the notch took.
    widget.ownPopupShown = result !== "opened"
    return result
  }

  Text {
    anchors.centerIn: parent
    text: "A"
    color: widget.surfaceHost ? widget.surfaceHost.foreground : "#ffffff"
  }

  MouseArea {
    anchors.fill: parent
    onClicked: widget.press("main")
  }

  // test-only begin
  readonly property int screenIndex: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (screens[i].name === widget.surfaceScreen) return i
    return -1
  }
  IpcHandler {
    target: "acme.demo.s" + widget.screenIndex
    enabled: Quickshell.env("NOTCH_FIXTURE_MARKER_DIR") !== "" && widget.screenIndex >= 0
    function state(): string {
      return JSON.stringify({
        accepted: widget.surfaceHost ? widget.surfaceHost.accepted : false,
        present: widget.surfaceHost ? widget.surfaceHost.present : false,
        radius: widget.surfaceHost ? widget.surfaceHost.radius : -1,
        contract: widget.surfaceHost ? widget.surfaceHost.contract : 0,
        surfaceScreen: widget.surfaceScreen,
        panelOpen: widget.surfaceHost ? widget.surfaceHost.panelOpen : false,
        panelScreen: widget.surfaceHost ? widget.surfaceHost.panelScreen : "",
        ownPopupShown: widget.ownPopupShown
      })
    }
    function open(route: string): string { return widget.press(route) }
    function claim(payload: string): string {
      if (!widget.surfaceHost) return "no-host"
      var activity = {}
      try { activity = JSON.parse(payload) } catch (e) { return "declined:bad-payload" }
      return widget.surfaceHost.claim(activity)
    }
    function release(key: string): string { return widget.surfaceHost ? widget.surfaceHost.release(key) : "no-host" }
  }
  // test-only end
}
