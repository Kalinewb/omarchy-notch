import QtQuick
import Quickshell
import "notch" as Notch

// The real Bar.qml with a whole bar config from $NOTCH_HARNESS_BAR (the `bar`
// object of a shell.json: layout and notch) and a fake widget catalogue: every
// id in the layout is registered as a plain widget whose width is derived
// from its id, so widths are the same on every run and every machine. Used by
// dev/contract.sh.
ShellRoot {
  id: shellRoot

  readonly property var barJson: JSON.parse(Quickshell.env("NOTCH_HARNESS_BAR") || "{}")
  // Optional per-id `notch` declarations for the fake widgets, as a widget
  // opting into the contract would expose them: {"<id>": {hideable: false, ...}}
  readonly property var declarations: JSON.parse(Quickshell.env("NOTCH_HARNESS_DECLARE") || "{}")

  // A stable width per id: 18 + (sum of char codes mod 47) px.
  function widthFor(id) {
    var s = 0
    for (var i = 0; i < id.length; i++) s += id.charCodeAt(i)
    return 18 + (s % 47)
  }

  function idsIn(layout) {
    var ids = {}
    var regions = ["left", "center", "right"]
    for (var r = 0; r < regions.length; r++) {
      var entries = layout && Array.isArray(layout[regions[r]]) ? layout[regions[r]] : []
      for (var i = 0; i < entries.length; i++) {
        var e = entries[i]
        var id = typeof e === "string" ? e : (e && e.id ? String(e.id) : "")
        if (id) ids[id] = true
      }
    }
    return Object.keys(ids)
  }

  Component {
    id: fakeWidget
    Item {
      property var bar
      property string moduleName: ""
      property var settings
      readonly property var notch: moduleName && shellRoot.declarations[moduleName] ? shellRoot.declarations[moduleName] : null
      implicitWidth: moduleName ? shellRoot.widthFor(moduleName) : 0
      implicitHeight: 26
    }
  }

  QtObject {
    id: fakeRegistry
    property int revision: 1
    property var widgets: {
      var out = {}
      var ids = shellRoot.idsIn(shellRoot.barJson.layout)
      for (var i = 0; i < ids.length; i++)
        out[ids[i]] = { component: fakeWidget, metadata: { displayName: "Fake " + ids[i], firstParty: true } }
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
      layout: shellRoot.barJson.layout || { left: [], center: [], right: [] },
      notch: shellRoot.barJson.notch || {}
    })
  }
}
