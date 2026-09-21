import QtQuick
import Quickshell
import Quickshell.Io
import "kalinewb.notch" as Notch
import "kalinewb.notch-osd" as Companion

// The notch and the OSD companion in one throwaway Quickshell instance, laid
// out the way ~/.config/omarchy/plugins is, so the go-between finds the notch's
// bridge at the path it uses live ("../kalinewb.notch/bridge/Connector.qml")
// with no override -- the one line that decides whether a live install routes
// to the notch at all.
//
// dev/osd.sh drives it through the `osd-test` IPC target; the notch's own
// `notch` target works as usual. Payloads travel base64-encoded, because
// Quickshell's IPC splits arguments on commas.
ShellRoot {
  id: harness

  // The notch, unless the test wants the companion with no notch behind it.
  Loader {
    id: notch
    active: Quickshell.env("OSD_NO_NOTCH") !== "1"
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

  // The companion's service, as Omarchy's service loader creates it at
  // startup: created first, injected afterwards. In a Loader so a check can
  // take it away the way a plugin reload does. (The panel entry point is a
  // shim that forwards here, so the deciding is all in this object.)
  Loader {
    id: facadeLoader
    sourceComponent: Component {
      Companion.Service {
        Component.onCompleted: {
          omarchyPath = Quickshell.env("OMARCHY_PATH")
          manifest = JSON.parse(Quickshell.env("OSD_MANIFEST") || "{}")
          shell = null
        }
      }
    }
  }
  readonly property var facadeItem: facadeLoader.item

  IpcHandler {
    target: "osd-test"

    // `send`, not `show`: `quickshell ipc show` is the CLI's own subcommand,
    // and a function by that name is swallowed by it -- the call comes back
    // "The following argument was not expected" and never reaches here.
    //
    // Hand the go-between an OSD request, base64-encoded -- and unpadded,
    // because Quickshell's IPC CLI takes an argument containing "=" for an
    // option and refuses the call. The padding goes back on here.
    function send(payloadB64: string): string {
      if (!harness.facadeItem) return "no-facade"
      var text = String(payloadB64 || "")
      while (text.length % 4 !== 0) text += "="
      harness.facadeItem.open(Qt.atob(text))
      return harness.facadeItem.route
    }
    function close(): string { if (harness.facadeItem) harness.facadeItem.close(); return "ok" }
    function unload(what: string): string {
      if (what === "notch") notch.active = false
      else if (what === "facade") facadeLoader.active = false
      else return "unknown"
      return "ok"
    }

    // Everything the checks read: the go-between, and the stand-in stock OSD.
    function state(): string {
      var f = harness.facadeItem
      var stock = f ? f.stockItem : null
      return JSON.stringify({
        facade: !!f,
        route: f ? f.route : "",
        declined: f ? f.declined : "",
        opened: f ? f.opened : false,
        notchSeen: !!(f && f.notch),
        bridge: !!(f && f.bridge),
        apiVersion: f ? f.apiVersion : 0,
        version: f ? f.version : "",
        stockError: f ? f.stockError : "",
        stock: stock ? { opened: stock.opened, opens: stock.opens, closes: stock.closes,
                         lastPayload: stock.lastPayload } : null
      })
    }
  }
}
