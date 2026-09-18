import QtQuick
import Quickshell
import Quickshell.Io
import "notch" as Notch

// The real Bar.qml with fixture plugins in a sandbox plugins folder, for
// dev/platform.sh.
//
// The fixtures' bar widgets are registered from their real files, with the
// registry metadata Omarchy gives a third-party widget (`firstParty: false`
// plus `pluginId`), because that is what decides whether a widget is handed the
// notch's API facade and a `surfaceHost` at all. A first-party stand-in would
// test the wrong path.
ShellRoot {
  id: shellRoot

  // {"<plugin id>": "<folder>"} — which fixtures appear in the bar layout.
  readonly property var widgetsJson: JSON.parse(Quickshell.env("NOTCH_PLATFORM_WIDGETS") || "{}")
  readonly property string pluginsDir: Quickshell.env("NOTCH_PLUGINS_DIR") || ""

  readonly property var widgetIds: Object.keys(widgetsJson)

  QtObject {
    id: fakeRegistry
    property int revision: 1
    property var widgets: {
      var out = {}
      for (var i = 0; i < shellRoot.widgetIds.length; i++) {
        var id = shellRoot.widgetIds[i]
        var url = "file://" + shellRoot.pluginsDir + "/" + shellRoot.widgetsJson[id]
        var component = Qt.createComponent(url, Component.PreferSynchronous)
        if (component.status === Component.Error) { console.warn("platform-shell: " + component.errorString()); continue }
        out[id] = { component: component, metadata: { displayName: id, firstParty: false, pluginId: id } }
      }
      return out
    }
    function metadataFor(id) { var e = widgets[String(id)]; return e ? e.metadata : null }
    function availableIds() { return Object.keys(widgets) }
    function has(id) { return widgets[String(id)] !== undefined }
  }

  readonly property var barNotch: JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}")
  property var notchOverride: ({})

  Notch.Bar {
    id: notch
    barWidgetRegistry: fakeRegistry
    barConfig: ({
      position: "top",
      transparent: false,
      layout: { left: shellRoot.widgetIds.map(function (id) { return { id: id } }), center: [], right: [] },
      notch: Object.assign({}, shellRoot.barNotch, shellRoot.notchOverride)
    })
  }

  // The notch writes its own settings through the host in a real session; here
  // the harness stands in for that, so a check can switch an integration off.
  IpcHandler {
    target: "harness"

    function setNotch(json: string): string {
      try { shellRoot.notchOverride = JSON.parse(json) } catch (e) { return "bad-json" }
      return "ok"
    }
    // What a click outside does.
    function grabCleared(): string {
      var window = notch.focusedNotchWindow()
      if (window) window.closePanels()
      return "ok"
    }
    function quit(): string { Qt.quit(); return "ok" }
  }
}
