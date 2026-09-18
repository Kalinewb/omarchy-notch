import QtQuick
import Quickshell
import Quickshell.Io

// The plugin's bar widget. Under the notch it is handed `notchHost` and the
// screen it is on; under any other bar it gets neither, and nothing changes.
Item {
  id: widget

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property var notchHost: null
  property string notchScreen: ""

  // The plugin's own popup, for when the notch isn't there or declines.
  property bool ownPopupShown: false

  implicitWidth: 24
  implicitHeight: 24

  function press(route) {
    var result = notchHost ? notchHost.openPanel(route, notchScreen) : "no-host"
    // Per-event: the popup is skipped only for the event the notch took.
    widget.ownPopupShown = result !== "opened"
    return result
  }

  Text {
    anchors.centerIn: parent
    text: "A"
    color: widget.notchHost ? widget.notchHost.foreground : "#ffffff"
  }

  MouseArea {
    anchors.fill: parent
    onClicked: widget.press("main")
  }

  // test-only begin
  readonly property int screenIndex: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (screens[i].name === widget.notchScreen) return i
    return -1
  }
  IpcHandler {
    target: "acme.demo.s" + widget.screenIndex
    enabled: Quickshell.env("NOTCH_FIXTURE_MARKER_DIR") !== "" && widget.screenIndex >= 0
    function state(): string {
      return JSON.stringify({
        accepted: widget.notchHost ? widget.notchHost.accepted : false,
        present: widget.notchHost ? widget.notchHost.present : false,
        radius: widget.notchHost ? widget.notchHost.radius : -1,
        contract: widget.notchHost ? widget.notchHost.contract : 0,
        notchScreen: widget.notchScreen,
        panelOpen: widget.notchHost ? widget.notchHost.panelOpen : false,
        panelScreen: widget.notchHost ? widget.notchHost.panelScreen : "",
        ownPopupShown: widget.ownPopupShown
      })
    }
    function open(route: string): string { return widget.press(route) }
    function claim(payload: string): string {
      if (!widget.notchHost) return "no-host"
      var activity = {}
      try { activity = JSON.parse(payload) } catch (e) { return "declined:bad-payload" }
      return widget.notchHost.claim(activity)
    }
    function release(key: string): string { return widget.notchHost ? widget.notchHost.release(key) : "no-host" }
  }
  // test-only end
}
