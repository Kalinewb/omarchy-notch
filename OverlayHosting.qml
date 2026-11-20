import QtQuick
import Quickshell

// Draw another plugin's window-based UI inside the notch, and give it back.
//
// PanelHosting.qml takes the card out of a `KeyboardPanel` -- the pop-out of a
// bar widget, which has a PanelController. Omarchy's pickers (clipboard, emojis,
// image picker, reminders) are not that: each is a plugin whose root holds an
// `OverlayWindow`, a full-screen scrim with a card in the middle, opened by
// `open()`/`close()` and an `opened` flag. No controller, no panel. This is the
// same move for that shape: take the card out of the window, parent it into the
// notch's slot, keep the window itself from ever mapping, and put everything
// back. Same interface as PanelHosting, so Bar.qml asks one question
// (GuestHosting.qml routes it).
//
// What it relies on, all of which the four pickers do and none of which is
// documented as a contract -- which is why only a named list of them is ever
// offered to this (Bar.qml `overlayHostable`), and why anything else is declined:
//
//   - the plugin's root has a window in its `data` (an OverlayWindow, a
//     FloatingWindow or a PanelWindow),
//   - that window's content is a card, plus passive full-bleed items (the scrim,
//     the click-outside catcher) that are left behind,
//   - the card centres or fills itself in its parent, and sizes itself from the
//     window's size.
//
// Nothing about the plugin is modified. The window is held down by a `Binding`
// on its `visible`, which Qt restores to whatever the plugin had when the hold
// ends, so no knowledge of how the plugin maps its window is needed or kept.
// Its size is given by a second pair, because the card reads it (`cardWidth:
// min(875, panel.width - ...)`), and a window that never maps reports nothing.
Scope {
  id: hosting

  // The widget the notch's other code is told is hosted: the plugin's root item.
  property var widget: null
  property var panel: null
  property var controller: null
  // The plugin's window, once it is known (arm), and the items taken from it.
  property var window: null
  property var taken: []
  property bool armed: false
  property bool hosting_: false
  // The Omarchy id the plugin is known by, for reports.
  property string sourceId: ""

  readonly property bool active: hosting_ && taken.length > 0
  readonly property var content: taken.length > 0 ? taken[0].item : null

  // The area the plugin lays itself out in while it is held: what the window
  // would measure if it were mapped. A constant, not the notch's current size --
  // the card sizes itself from this and the notch sizes itself from the card, so
  // anything that followed the notch would shrink the card every time it grew.
  property real areaWidth: 880
  property real areaHeight: 680

  // --- finding the parts -------------------------------------------------------

  // A window in the plugin's own `data`: by type name first, because that is
  // exact, then by shape -- a `contentItem` is what no plain Item has.
  function windowOf(item) {
    if (!item || !item.data) return null
    var bag = item.data
    for (var i = 0; i < bag.length; i++) {
      var entry = bag[i]
      if (!entry) continue
      var name = String(entry)
      if (name.indexOf("OverlayWindow") === 0 || name.indexOf("FloatingWindow") === 0
          || name.indexOf("PanelWindow") === 0) return entry
      if (entry.contentItem !== undefined && entry.contentItem !== null && entry.visible !== undefined
          && entry.children === undefined) return entry
    }
    return null
  }

  // A passive filler is what a scrim and a click-outside catcher are: it fills
  // the whole window and holds nothing. There is no outside in the notch, so
  // both stay behind. A filler that holds something is a card (wifiqr's content
  // is inside its full-bleed catcher), and travels.
  function isFiller(entry) {
    var fills = !!(entry.anchors && entry.anchors.fill)
    return fills && (!entry.children || entry.children.length === 0)
  }

  function bodiesOf(win) {
    var out = []
    if (!win || !win.contentItem) return out
    var kids = win.contentItem.children
    for (var i = 0; i < kids.length; i++) if (!isFiller(kids[i])) out.push(kids[i])
    return out
  }

  // --- the question the notch asks -----------------------------------------------

  // Answers "" when the plugin can be drawn here, or why not, in the words
  // PanelHosting uses where the reason is the same.
  function reasonNotHostable(item) {
    if (!item) return "no widget"
    // Already drawn: its card is where it was put, so the window holds nothing.
    if (hosting_ && item === widget) return ""
    var win = (item === widget && window) ? window : windowOf(item)
    if (!win) return "no window"
    if (bodiesOf(win).length === 0) return "window has nothing in it"
    return ""
  }

  function hostable(item) { return reasonNotHostable(item) === "" }

  // Is `item` one this is holding down or hosting? The router asks, so a widget
  // and a picker can share the notch's one hosted slot without sharing a path.
  function owns(item) { return !!item && item === widget }

  // --- holding the window down ---------------------------------------------------

  // Before the plugin opens: its window must not map for even the frame between
  // `open()` setting its state and the notch taking the card. Answers "" or why
  // not. Safe to repeat for the same plugin.
  function arm(item, id) {
    // Asked for again by the plugin that is already drawn: nothing to do.
    if (hosting_) return widget === item ? "" : "already hosting"
    if (armed && widget === item) return ""
    if (armed) disarm()
    var win = windowOf(item)
    if (!win) return "no window"
    widget = item
    window = win
    sourceId = String(id || "")
    armed = true
    return ""
  }

  // Let the plugin have its own window again. Used when the notch declined, and
  // after giving back: what the plugin believes about itself was never touched,
  // so this is only the end of the hold.
  function disarm() {
    if (hosting_) return
    armed = false
    window = null
    widget = null
    sourceId = ""
  }

  Binding { target: hosting.window; property: "visible"; value: false; when: hosting.armed }
  Binding { target: hosting.window; property: "implicitWidth"; value: hosting.areaWidth; when: hosting.armed }
  Binding { target: hosting.window; property: "implicitHeight"; value: hosting.areaHeight; when: hosting.armed }

  // --- the card's own surface -------------------------------------------------------

  // A picker's card paints a surface of its own -- the menu's background and a
  // border -- because in its own window that is the only surface there is. In the
  // notch it would be a second, lighter card inside the notch's black, so for as
  // long as it is held the card paints neither. Width is the border's paint, not
  // its space: the card's contents keep the insets it laid them out with.
  //
  // A body that is not a rectangle (the image picker's is a plain Item) has
  // neither and is left alone, which is why these are conditional on the body.
  readonly property bool flatten: true
  // Decided by the card's `radius`, which nothing here writes: asking `color` would
  // be a loop with the binding that clears it.
  readonly property bool paintsSurface: hosting_ && flatten && !!content && content.radius !== undefined
    && content.border !== undefined
  Binding { target: hosting.paintsSurface ? hosting.content : null; property: "color"; value: "transparent" }
  Binding { target: hosting.paintsSurface ? hosting.content.border : null; property: "width"; value: 0 }

  // --- taking and giving back ------------------------------------------------------

  // Draw `item`'s card in `slot`. Answers "" on success, or why not.
  function take(item, slot) {
    if (hosting_) return "already hosting"
    if (!slot) return "no slot"
    if (!armed || widget !== item) {
      var armedWhy = arm(item, sourceId)
      if (armedWhy !== "") return armedWhy
    }
    var why = reasonNotHostable(item)
    if (why !== "") return why

    var bodies = bodiesOf(window)
    var records = []
    // Where each came from. Nothing is resized: the card sizes itself from the
    // area given above and centres or fills itself in whatever it is parented to,
    // which is the slot after this. What is given back is the parent.
    for (var i = 0; i < bodies.length; i++)
      records.push({ item: bodies[i], origin: bodies[i].parent })

    taken = records
    for (var j = 0; j < records.length; j++) records[j].item.parent = slot
    hosting_ = true
    return ""
  }

  // The plugin names its own focus target by owning the one item that asks for
  // focus; the notch makes the call the plugin's own `forceActiveFocus` made on
  // a window that never mapped.
  function focusItemIn(node, depth) {
    if (!node || depth > 10) return null
    if (node.focus === true && node !== content && typeof node.forceActiveFocus === "function") return node
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) {
      var found = focusItemIn(kids[i], depth + 1)
      if (found) return found
    }
    return null
  }

  readonly property var focusTarget: {
    var inside = taken.length > 0 ? focusItemIn(taken[0].item, 0) : null
    return inside || content
  }

  function focusContent() {
    var target = focusTarget
    if (!target || typeof target.forceActiveFocus !== "function") return false
    target.forceActiveFocus()
    return true
  }

  // Put it back, tell the plugin it was closed, end the hold. Safe to call when
  // nothing is hosted.
  function giveBack() {
    if (taken.length === 0) { reset(); return "" }
    var held = widget
    for (var i = 0; i < taken.length; i++) {
      var record = taken[i]
      if (record.item) record.item.parent = record.origin
    }
    taken = []
    hosting_ = false
    // Closed while the window is still held down, so the plugin packs up with
    // nothing on screen -- its own `close()`, whatever that is -- and only then
    // does the hold end, on a window that already believes it is shut. A plugin
    // that closed itself (its Escape) is not asked again.
    if (held && held.opened === true && typeof held.close === "function") held.close()
    reset()
    return ""
  }

  function reset() {
    hosting_ = false
    taken = []
    armed = false
    window = null
    widget = null
    sourceId = ""
  }

  // How big the plugin's card is. The card sizes itself, so the notch grows to
  // what the author chose, and follows it when it changes.
  readonly property real wantedWidth: content ? Number(content.width || 0) : 0
  readonly property real wantedHeight: content ? Number(content.height || 0) : 0

  // The plugin's colours are the plugin's: a picker is its content (an emoji, a
  // wallpaper thumbnail), and taking the hue out of those is taking the picker.
  readonly property bool monochrome: false

  property var opted: []

  function report() {
    return {
      active: active,
      kind: "overlay",
      opted: opted,
      widget: sourceId,
      items: taken.length,
      told: !!widget && widget.opened === true,
      ownWindow: !!window && window.visible === true,
      armed: armed,
      flat: paintsSurface,
      focused: !!focusTarget && focusTarget.activeFocus === true,
      wanted: { width: Math.round(wantedWidth), height: Math.round(wantedHeight) },
      contentSize: content ? { width: Math.round(content.width), height: Math.round(content.height) } : null
    }
  }
}
