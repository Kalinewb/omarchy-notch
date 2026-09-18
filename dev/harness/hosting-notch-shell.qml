import QtQuick
import Quickshell
import Quickshell.Io
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
  property var notchOverride: ({})

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

  // Reach the widget the notch is drawing, to open its panel the way the
  // plugin's own keybind does -- through its own controller, with nothing the
  // notch could intercept first.
  IpcHandler {
    target: "harness"

    // The notch writes its settings through the host in a real session; here
    // the harness stands in for that, so a check can turn hosting on the way
    // the settings switch does.
    function setNotch(json: string): string {
      try { shellRoot.notchOverride = JSON.parse(json) } catch (e) { return "bad-json" }
      return "ok"
    }

    function summon(): string {
      var item = notch.widgetItemFor(shellRoot.widgetId)
      if (!item) return "no widget"
      var controller = notch.hosting.controllerOf(item)
      if (!controller) return "no controller"
      controller.open = true
      return "ok"
    }

    function dismiss(): string {
      var item = notch.widgetItemFor(shellRoot.widgetId)
      var controller = item ? notch.hosting.controllerOf(item) : null
      if (controller) controller.open = false
      return "ok"
    }

    // Whether the plugin's own window is mapped right now, and whether its own
    // panel thinks it is open.
    function ownWindow(): string {
      var item = notch.widgetItemFor(shellRoot.widgetId)
      var panel = item ? notch.hosting.panelOf(item) : null
      return JSON.stringify({ visible: panel ? panel.visible === true : false,
                              open: panel ? panel.open === true : false })
    }
  }

  Notch.Bar {
    id: notch
    barWidgetRegistry: fakeRegistry
    barConfig: ({
      position: "top",
      transparent: false,
      layout: { left: [], center: [], right: [{ id: shellRoot.widgetId }] },
      notch: Object.assign({}, JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}"), shellRoot.notchOverride)
    })
  }
}
