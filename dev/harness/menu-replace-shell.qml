import QtQuick
import Quickshell
import Quickshell.Io
import "kalinewb.notch" as Notch
import "kalinewb.notch-menu" as Companion

// The notch and the menu companion in one throwaway Quickshell instance, laid
// out the way ~/.config/omarchy/plugins is, so the go-between finds the notch's
// bridge at the path it uses live ("../kalinewb.notch/bridge/Connector.qml")
// with no override -- the one line that decides whether a live Set up routes
// to the notch at all.
//
// dev/menu-replace.sh drives it through the `menu-replace` IPC target; the
// notch's own `notch` target works as usual. Payloads travel base64-encoded,
// because Quickshell's IPC splits arguments on commas.
ShellRoot {
  id: harness

  // The notch, unless the test wants the companion with no notch behind it.
  Loader {
    id: notch
    active: Quickshell.env("MENU_REPLACE_NO_NOTCH") !== "1"
    sourceComponent: Component {
      Notch.Bar {
        barConfig: ({
          position: "top",
          transparent: false,
          layout: { left: [], center: [], right: [] },
          notch: JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}")
        })
      }
    }
  }

  // The companion's go-between, as Omarchy's menu-kind loader creates it:
  // created first, injected afterwards. In a Loader so a check can take it
  // away the way a plugin reload does.
  Loader {
    id: facadeLoader
    sourceComponent: Component {
      Companion.Facade {
        Component.onCompleted: {
          omarchyPath = Quickshell.env("OMARCHY_PATH")
          manifest = JSON.parse(Quickshell.env("MENU_REPLACE_MANIFEST") || "{}")
          shell = null
        }
      }
    }
  }
  readonly property var facadeItem: facadeLoader.item
  IpcHandler {
    target: "menu-replace"

    // Hand the go-between a menu request, base64-encoded.
    function open(payloadB64: string): string {
      if (!harness.facadeItem) return "no-facade"
      harness.facadeItem.open(Qt.atob(payloadB64))
      return harness.facadeItem.route
    }
    function close(): string { if (harness.facadeItem) harness.facadeItem.close(); return "ok" }
    // Take the notch or the go-between away, as a plugin reload does.
    function unload(what: string): string {
      if (what === "notch") notch.active = false
      else if (what === "facade") facadeLoader.active = false
      else return "unknown"
      return "ok"
    }
    function refresh(): string { return harness.facadeItem ? harness.facadeItem.refresh() : "no-facade" }
    function ping(): string { return harness.facadeItem ? harness.facadeItem.ping() : "no-facade" }

    // Everything the checks read: the go-between, and the stand-in stock menu.
    function state(): string {
      var f = harness.facadeItem
      return JSON.stringify({
        facade: !!f,
        route: f ? f.route : "",
        opened: f ? f.opened : false,
        notchSeen: !!(f && f.notch),
        bridge: !!(f && f.bridge),
        apiVersion: f ? f.apiVersion : 0,
        version: f ? f.version : "",
        appsSource: f ? f.appsSource : "",
        stockError: f ? f.stockError : "",
        stockSource: f ? f.stockFirstSource : "",
        stock: harness.stockState()
      })
    }
  }

  function stockState() {
    var stock = harness.facadeItem ? harness.facadeItem.stockItem : null
    if (!stock) return null
    return { opened: stock.opened, opens: stock.opens, closes: stock.closes, refreshes: stock.refreshes,
             requestActive: stock.requestActive, doneFile: stock.doneFile, lastPayload: stock.lastPayload,
             appEntries: stock.appEntries }
  }
}
