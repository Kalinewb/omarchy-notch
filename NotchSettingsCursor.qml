import QtQuick

// The settings panel's row cursor (plan-settings.md 4), on the pattern of
// NotchPlugins.handleKey and its ensureVisible. It walks the main rows, the
// Advanced line, then Advanced's rows when open; inside an open fold (or a
// row of buttons) it walks the lines. While a key recorder listens it is
// suspended and Escape only cancels the recording. Header buttons are reached
// by Tab, not here.
QtObject {
  id: nav

  // The panel (NotchSettings) and the Flickable its rows scroll in.
  property var panel: null
  property var flick: null
  // The row under the cursor ("advanced" is the fold's own line), and the
  // line inside its open fold or buttons; -1 for the row itself.
  property string at: ""
  property int sub: -1

  // Every stop, in the order drawn.
  function stops() {
    return panel.groups.reduce(function(all, g) {
      var rows = g.fold && !g.open ? [] : g.rows().filter(function(r) { return r.visible })
      return all.concat(g.fold && g.visible !== false ? [g] : [], g.visible !== false ? rows : [])
    }, [])
  }
  // The stop the cursor is on; a row in a fold that has closed is its fold.
  function current(list) {
    return list.filter(function(s) { return s.rid === at })[0]
      || panel.groups.filter(function(g) { return g.fold && g.rows().some(function(r) { return r.rid === at }) })[0] || null
  }
  function lines(stop) { return stop && stop.targets ? stop.targets() : [] }
  function target() { var stop = current(stops()); return lines(stop)[sub] || (stop ? stop.head : null) }

  // The cursor's own mark on the lines it walks.
  function paint() {
    stops().forEach(function(s) { lines(s).forEach(function(l, i) { l.hasCursor = s.rid === at && i === sub }) })
  }
  function reveal(item) {
    var y = item.mapToItem(flick.contentItem, 0, 0).y
    if (y + item.height > flick.contentY + flick.height)
      flick.contentY = Math.max(0, Math.min(y + item.height - flick.height, flick.contentHeight - flick.height))
    else if (y < flick.contentY) flick.contentY = y
  }
  function ensureVisible() { var t = target(); if (t) reveal(t) }
  function reset() { at = ""; sub = -1; panel.tip.hide() }

  function go(stop, line) {
    at = stop.rid
    sub = line
    paint()
    ensureVisible()
  }
  // The pointer moves the cursor to its row, and the tip follows the pointer.
  function hover(row) { at = row.rid; sub = -1; paint(); panel.tip.want(row.rid, "hover") }
  function unhover(row) { if (!row || row.rid === at) panel.tip.leave() }

  function activate(line) { if (typeof line.activate === "function") line.activate(); else if (line.enabled) line.clicked() }

  // A key by name; whether it was used.
  function press(name) {
    var tip = panel.tip
    if (panel.recorder) { if (name === "escape") panel.recorder.stop(); return true }
    var list = stops(), here = current(list)
    var held = lines(here)
    if (name === "escape") {
      if (tip.pending || tip.shown) { tip.hide(); return true }
      if (typeof panel.cancelPending === "function" && panel.cancelPending()) return true
      var open = panel.rows().filter(function(r) { return r.open && r.visible })
      var one = open.filter(function(r) { return r.rid === at })[0] || open[0]
      if (one) { one.open = false; sub = -1; paint() }
      else panel.closeRequested()
      return true
    }
    if (name === "down" || name === "up") {
      var next = list[Math.max(0, Math.min(list.length - 1, list.indexOf(here) + (name === "down" ? 1 : -1)))]
      if (next) { go(next, -1); tip.want(next.rid, "focus") }
      return true
    }
    if (name === "left" || name === "right") {
      var way = name === "right" ? 1 : -1
      if (held.length > 0) { sub = Math.max(0, Math.min(held.length - 1, sub + way)); paint(); ensureVisible() }
      else if (here && here.kind === "stepper") here.apply(Math.max(here.from, Math.min(here.to, here.value + way * here.stepSize)))
      return true
    }
    if (name === "space" || name === "return" || name === "enter") {
      if (!here) return true
      tip.hide()
      if (here.kind === "fold") here.open = !here.open
      else if (here.kind === "switch") here.apply(!here.checked)
      else if (held.length > 0) { sub = Math.max(0, sub); activate(held[sub]); if (!here.open) sub = -1; paint() }
      else if (here.foldable) { here.open = true; sub = 0; Qt.callLater(paint) }
      return true
    }
    return false
  }

  // A real key press (Keys.onPressed), without Ctrl, Alt or Super.
  function handle(event) {
    var names = {}
    names[Qt.Key_Escape] = "escape"; names[Qt.Key_Up] = "up"; names[Qt.Key_Down] = "down"; names[Qt.Key_Left] = "left"
    names[Qt.Key_Right] = "right"; names[Qt.Key_Space] = "space"; names[Qt.Key_Return] = "return"; names[Qt.Key_Enter] = "return"
    if (names[event.key] === undefined || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return false
    return press(names[event.key])
  }

  // dev/settings.sh reads this through the panel's report.
  function report() {
    var t = target()
    var top = t ? t.mapToItem(flick, 0, 0).y : -1
    return { cursor: at, cursorSub: sub, cursorTop: Number(top.toFixed(1)), cursorBottom: t ? Number((top + t.height).toFixed(1)) : -1,
             recorder: !!panel.recorder, open: panel.enabled, tip: panel.tip.report(),
             footTop: panel.tip.y, viewBottom: flick.y + flick.height }
  }
}
