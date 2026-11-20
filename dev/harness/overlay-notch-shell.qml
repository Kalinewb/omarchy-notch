import QtQuick
import Quickshell
import Quickshell.Io
import "kalinewb.notch" as Notch
import "kalinewb.notch-clipboard" as Companion

// The real notch, with an overlay companion's go-between in front of a real
// picker, for dev/overlays.sh part B.
//
// The go-between is companion/kalinewb.notch-clipboard/Facade.qml -- the file
// every overlay companion ships -- laid out like the plugins folder, so it finds
// the notch's bridge at the path it uses live (\"../kalinewb.notch/bridge/Connector.qml\")
// with no override, and given a manifest that says which picker it stands in for.
// The answer under test is the
// whole route a keybind takes: facade.open() -> arm -> the picker opens -> the
// notch takes its card; and the way back: the picker closes itself or the back
// strip is pressed.
ShellRoot {
  id: shellRoot

  readonly property string clonedFrom: Quickshell.env("OVERLAY_CLONED_FROM") || "omarchy.emojis"
  property var notchOverride: ({})

  QtObject {
    id: fakeRegistry
    property int revision: 1
    property var widgets: ({})
    function metadataFor(id) { return null }
    function availableIds() { return [] }
    function has(id) { return false }
  }

  // As Omarchy creates a panel plugin's entry point: created first, injected after.
  Loader {
    id: facadeLoader
    asynchronous: false
    sourceComponent: Component {
      Companion.Facade {
        Component.onCompleted: {
          omarchyPath = Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
          // `shell` is left null: a picker that hides itself through it checks first.
          manifest = { id: "kalinewb.notch-test", version: "1.0.0", omarchy: { clonedFrom: shellRoot.clonedFrom } }
        }
      }
    }
  }

  // A window in the picker's data: the real ones are an OverlayWindow, the
  // fixture's a plain PanelWindow, whose type name is a layer-shell interface.
  function windowOf(item) {
    if (!item || !item.data) return null
    for (var i = 0; i < item.data.length; i++) {
      var entry = item.data[i]
      if (entry && entry.contentItem !== undefined && entry.visible !== undefined && entry.children === undefined) return entry
    }
    return null
  }

  IpcHandler {
    target: "harness"

    function setNotch(json: string): string {
      try { shellRoot.notchOverride = JSON.parse(json) } catch (e) { return "bad-json" }
      return "ok"
    }

    function open(): string {
      if (!facadeLoader.item) return "no facade"
      facadeLoader.item.open("{}")
      return "ok"
    }

    function close(): string {
      if (!facadeLoader.item) return "no facade"
      facadeLoader.item.close()
      return "ok"
    }

    // The picker's own Escape: the picker closing itself.
    function dismiss(): string {
      var inner = facadeLoader.item ? facadeLoader.item.inner : null
      if (!inner) return "no picker"
      if (typeof inner.dismiss === "function") inner.dismiss()
      else inner.close()
      return "ok"
    }

    // What the facade, the picker and the picker's own window say right now.
    function state(): string {
      var facade = facadeLoader.item
      var inner = facade ? facade.inner : null
      var win = shellRoot.windowOf(inner)
      return JSON.stringify({
        loaded: !!facade,
        notch: !!facade && !!facade.notch,
        bridge: !!facade && !!facade.bridge,
        target: !!facade && !!facade.bridge && !!facade.bridge.target,
        sourceId: facade ? String(facade.sourceId) : "",
        stock: !!inner,
        route: facade ? String(facade.route) : "",
        opened: facade ? facade.opened === true : false,
        windowVisible: win ? win.visible === true : null,
        opens: inner && inner.opens !== undefined ? inner.opens : null,
        closes: inner && inner.closes !== undefined ? inner.closes : null
      })
    }
  }

  Notch.Bar {
    id: notch
    barWidgetRegistry: fakeRegistry
    barConfig: ({
      position: "top",
      transparent: false,
      layout: { left: [], center: [], right: [] },
      notch: Object.assign({}, JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}"), shellRoot.notchOverride)
    })
  }
}
