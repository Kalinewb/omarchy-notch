import QtQuick
import Quickshell
import "notch" as Notch

// The real notch, drawing one real Omarchy bar widget, for dev/hosting.sh part B.
//
// The widget is registered from its own file with the metadata Omarchy gives a
// third-party widget, so it reaches the notch through the same path a user's
// plugin does -- and its panel is the thing the notch is asked to host.
ShellRoot {
  id: shellRoot

  readonly property string widgetPath: Quickshell.env("HOSTING_WIDGET")
    || (Quickshell.env("OMARCHY_SHELL_PATH") + "/plugins/panels/audio/Panel.qml")
  readonly property string widgetId: "audio"

  QtObject {
    id: fakeRegistry
    property int revision: 1
    property var widgets: {
      var out = {}
      var component = Qt.createComponent("file://" + shellRoot.widgetPath, Component.PreferSynchronous)
      if (component.status === Component.Error) {
        console.warn("hosting-notch-shell: " + component.errorString())
        return out
      }
      out[shellRoot.widgetId] = {
        component: component,
        metadata: { displayName: "Audio", firstParty: false, pluginId: shellRoot.widgetId }
      }
      return out
    }
    function metadataFor(id) { var e = widgets[String(id)]; return e ? e.metadata : null }
    function availableIds() { return Object.keys(widgets) }
    function has(id) { return widgets[String(id)] !== undefined }
  }

  Notch.Bar {
    barWidgetRegistry: fakeRegistry
    barConfig: ({
      position: "top",
      transparent: false,
      layout: { left: [], center: [], right: [{ id: shellRoot.widgetId }] },
      notch: JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}")
    })
  }
}
