.pragma library

// The notch plugin contract.
//
// Everything the notch can show is a plugin described by one descriptor:
//
//   id               unique id. Bar widgets keep the id the bar layout (and
//                    every notch setting) already uses, e.g. "quickshell.spotify".
//                    The notch's own items have reserved "notch." ids.
//   kind             "builtin" (the notch's own) or "widget" (a bar widget)
//   label            what pickers show
//   closedView       what the resting notch shows for it: a Component, or
//                    "widget" (the live bar widget item) / "glance:<item>"
//   expandedView     full content, or null: a Component, or a built-in key
//                    ("settings") that the notch resolves to its own Component.
//                    Every expanded view renders through the same host.
//   preferredHeight  a request in px; the notch decides the final height.
//                    0 means "the resting height".
//   priority         "transient" | "persistent" | "persistent-low"
//   groupable        may be grouped with others
//   hideable         the user may hide it (hiddenPlugins has no effect otherwise)
//
// Bar widgets need do nothing: an adapter describes every one with the
// defaults below. A widget opts in by exposing a `notch` property -- a plain
// object with any of closedView, expandedView, preferredHeight, priority,
// groupable, hideable -- which overrides those defaults field by field.
// Invalid values fall back to the default rather than failing.
//
// Configuration never changes format: settings keep their short names
// ("clock") and widget ids; SHORT_NAMES maps short names to reserved ids at
// read time only.

var PRIORITIES = ["transient", "persistent", "persistent-low"]

var DEFAULTS = {
  closedView: "widget",
  expandedView: null,
  preferredHeight: 0,
  priority: "persistent-low",
  groupable: true,
  hideable: true
}

var BUILTINS = [
  { id: "notch.clock",    short: "clock",    label: "Time",     closedView: "glance:clock",   expandedView: null,       priority: "persistent-low", groupable: true,  hideable: true },
  { id: "notch.date",     short: "date",     label: "Date",     closedView: "glance:date",    expandedView: null,       priority: "persistent-low", groupable: true,  hideable: true },
  { id: "notch.media",    short: "media",    label: "Media",    closedView: "glance:media",   expandedView: null,       priority: "persistent-low", groupable: true,  hideable: true },
  { id: "notch.battery",  short: "battery",  label: "Battery",  closedView: "glance:battery", expandedView: null,       priority: "persistent-low", groupable: true,  hideable: true },
  { id: "notch.settings", short: "settings", label: "Settings", closedView: null,             expandedView: "settings", priority: "persistent",     groupable: false, hideable: false }
]

var SHORT_NAMES = (function() {
  var out = {}
  for (var i = 0; i < BUILTINS.length; i++) out[BUILTINS[i].short] = BUILTINS[i].id
  return out
})()

function shortToId(name) {
  var key = String(name || "")
  return SHORT_NAMES[key] || ""
}

function idToShort(id) {
  for (var i = 0; i < BUILTINS.length; i++) if (BUILTINS[i].id === id) return BUILTINS[i].short
  return ""
}

function isComponent(value) {
  return !!value && typeof value === "object" && typeof value.createObject === "function"
}

// A descriptor for a built-in, with the contract's defaults filled in.
function builtin(def, restHeight) {
  return {
    id: def.id, kind: "builtin", label: def.label, short: def.short,
    closedView: def.closedView, expandedView: def.expandedView,
    preferredHeight: restHeight, priority: def.priority,
    groupable: def.groupable, hideable: def.hideable, declared: false
  }
}

// A descriptor for a bar widget: the defaults, overridden field by field by
// whatever valid values its `notch` property declares.
function widget(id, label, declared, restHeight) {
  var d = {
    id: id, kind: "widget", label: label,
    closedView: DEFAULTS.closedView, expandedView: DEFAULTS.expandedView,
    preferredHeight: restHeight, priority: DEFAULTS.priority,
    groupable: DEFAULTS.groupable, hideable: DEFAULTS.hideable,
    declared: false, invalid: []
  }
  if (!declared || typeof declared !== "object") return d
  d.declared = true
  if ("closedView" in declared) {
    if (declared.closedView === "widget" || isComponent(declared.closedView)) d.closedView = declared.closedView
    else d.invalid.push("closedView")
  }
  if ("expandedView" in declared) {
    if (declared.expandedView === null || isComponent(declared.expandedView)) d.expandedView = declared.expandedView
    else d.invalid.push("expandedView")
  }
  if ("preferredHeight" in declared) {
    var h = Number(declared.preferredHeight)
    if (isFinite(h) && h > 0) d.preferredHeight = h
    else d.invalid.push("preferredHeight")
  }
  if ("priority" in declared) {
    if (PRIORITIES.indexOf(declared.priority) !== -1) d.priority = declared.priority
    else d.invalid.push("priority")
  }
  if ("groupable" in declared) {
    if (typeof declared.groupable === "boolean") d.groupable = declared.groupable
    else d.invalid.push("groupable")
  }
  if ("hideable" in declared) {
    if (typeof declared.hideable === "boolean") d.hideable = declared.hideable
    else d.invalid.push("hideable")
  }
  return d
}

// The ids hiddenPlugins actually hides: those configured, minus any plugin
// that declares hideable: false.
function effectiveHidden(configured, byId) {
  return (configured || []).filter(function(id) {
    var p = byId[id]
    return !(p && p.hideable === false)
  })
}

// A descriptor without its Components, for reports.
function plain(d) {
  function view(v) { return isComponent(v) ? "component" : v }
  return {
    id: d.id, kind: d.kind, label: d.label, closedView: view(d.closedView), expandedView: view(d.expandedView),
    preferredHeight: d.preferredHeight, priority: d.priority, groupable: d.groupable, hideable: d.hideable,
    declared: d.declared, invalid: d.invalid || []
  }
}
