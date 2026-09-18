import QtQuick
import Quickshell

// Draw another plugin's pop-out panel inside the notch, and give it back.
//
// An Omarchy bar widget puts its panel in a `KeyboardPanel` -- a full-screen
// layer-shell surface with a card inside it, opened when the widget's own
// controller says so. This takes the card's content out of that surface and
// parents it into a slot the notch owns, so the same panel is drawn inside the
// notch instead of in a window of its own.
//
// Nothing about the plugin is modified: no file is touched, no property of its
// own is rewritten, and everything taken is put back. A plugin that does not
// look the way this expects is declined, and keeps its own window.
//
// Proven before it was written: dev/harness/reparent-probe.qml moves Omarchy's
// real audio panel into a foreign window and back, with its bindings, its model
// and its layout intact. dev/hosting.sh keeps it proven.
QtObject {
  id: hosting

  // What is being hosted right now: the widget's item, its panel object, and
  // one record per item taken -- where it came from, what size it was, and
  // whether this had to give it one.
  property var widget: null
  property var panel: null
  property var taken: []
  property bool hosting_: false

  readonly property bool active: hosting_ && taken.length > 0
  // The first item taken, which is the panel's body: what the notch measures.
  readonly property var content: taken.length > 0 ? taken[0].item : null

  // --- finding the parts ------------------------------------------------------

  // A widget's panel is not a visual child -- it is a window -- but everything
  // declared inside the widget's root lands in its `data`.
  function panelOf(item) {
    if (!item) return null
    var bag = item.data
    if (!bag) return null
    for (var i = 0; i < bag.length; i++) {
      var entry = bag[i]
      if (!entry) continue
      if (String(entry).indexOf("KeyboardPanel") === 0) return entry
    }
    return null
  }

  // The object holding the widget's open/closed state, so the notch can keep
  // the plugin's own window shut while it draws the panel itself.
  function controllerOf(item) {
    if (!item) return null
    var bag = item.data
    if (!bag) return null
    for (var i = 0; i < bag.length; i++) {
      var entry = bag[i]
      if (entry && String(entry).indexOf("PanelController") === 0) return entry
    }
    return null
  }

  // Can this widget's panel be drawn inside the notch? Every answer is "no"
  // unless every part is there: a panel with something in it, and a controller
  // to keep the plugin's own window shut with.
  //
  // More than one item is normal and fine -- Profiles keeps four dialogs
  // anchored over its column -- so all of them travel together.
  function reasonNotHostable(item) {
    if (!item) return "no widget"
    var found = panelOf(item)
    if (!found) return "no panel"
    var content = found.contentItem
    if (!content || content.length === 0) return "panel has nothing in it"
    if (!controllerOf(item)) return "no panel controller"
    return ""
  }

  function hostable(item) { return reasonNotHostable(item) === "" }

  // --- taking and giving back --------------------------------------------------

  // Draw `item`'s panel in `slot`. Answers "" on success, or why not.
  function take(item, slot) {
    if (active) return "already hosting"
    if (!slot) return "no slot"
    var why = reasonNotHostable(item)
    if (why !== "") return why

    var found = panelOf(item)
    var bodies = found.contentItem
    var records = []

    // Every item, with its size before anything is touched: the panel is handed
    // back the way it was found, and clearing anchors alone would leave it at
    // the notch's size (measured; see the probe's caveat).
    for (var i = 0; i < bodies.length; i++) {
      var body = bodies[i]
      // An item that already fills its parent follows the reparent by itself,
      // because `anchors.fill: parent` is a binding on `parent`. One that does
      // not is sized by the panel's card, which it is about to leave, so the
      // notch gives it a size and takes it back afterwards.
      var fills = !!(body.anchors && body.anchors.fill)
      records.push({ item: body, origin: body.parent, width: body.width, height: body.height, filled: !fills })
    }

    hosting.widget = item
    hosting.panel = found
    hosting.taken = records

    for (var j = 0; j < records.length; j++) {
      var record = records[j]
      record.item.parent = slot
      if (record.filled) record.item.anchors.fill = slot
    }
    hosting.hosting_ = true
    return ""
  }

  // Put it back exactly as it was found. Safe to call when nothing is hosted.
  function giveBack() {
    if (taken.length === 0) { reset(); return "" }
    for (var i = 0; i < taken.length; i++) {
      var record = taken[i]
      if (!record.item) continue
      if (record.filled) {
        record.item.anchors.fill = undefined
        // Anchors cleared leave the last size behind, so the original is put
        // back rather than assumed.
        if (record.width > 0) record.item.width = record.width
        if (record.height > 0) record.item.height = record.height
      }
      record.item.parent = record.origin
    }
    reset()
    return ""
  }

  function reset() {
    hosting.hosting_ = false
    hosting.taken = []
    hosting.panel = null
    hosting.widget = null
  }

  // How big the plugin says its panel wants to be. The plugin already computes
  // this for its own card, so the notch grows to the size the author chose
  // rather than to a guess -- and it stays a binding, so a panel that changes
  // height (a dialog opening, a list filling) moves the notch with it.
  readonly property real wantedWidth: panel ? Number(panel.contentWidth || 0) : 0
  readonly property real wantedHeight: panel ? Number(panel.contentHeight || 0) : 0

  // Which widgets the user has asked to see inside the notch. Set by the notch.
  property var opted: []


  // What the notch's reports say about it.
  function report() {
    return {
      active: active,
      opted: opted,
      widget: widget ? String(widget.moduleName || "") : "",
      items: taken.length,
      wanted: { width: Math.round(wantedWidth), height: Math.round(wantedHeight) },
      contentSize: content ? { width: Math.round(content.width), height: Math.round(content.height) } : null
    }
  }
}
