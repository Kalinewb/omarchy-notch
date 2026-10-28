.pragma library

// What the Plugins page shows for each catalogue entry, from bin/notch-plugins
// `state`, the last job and the last handoff. Pure, so the states can be
// checked without a notch.
//
//   entryView(entry, job, now, options) -> { id, name, version, state, words, actions: [{ name, label, primary, enabled }] }
//   deriveState(entry)                   -> the runner's state for a probed entry
//
// `entry` is a catalogue entry merged with its probe (`checked: true` once
// probed). options: { canAct, handoff, checking }. Actions are in display
// order, the primary one last; a name is "<action>:<id>".

var STALE_MS = 5 * 60000

function jobRunning(job, now) {
  return !!job && job.phase === "running" && now - Number(job.startedAt || 0) < STALE_MS
}

// The same order as bin/notch-plugins `probe`.
function deriveState(e) {
  if (!e.installed) return "not-installed"
  if (!e.git || !e.originMatches) return "other-source"
  if (e.dirty || e.relation === "diverged") return "local-changes"
  if (!e.enabled) return "disabled"
  if (e.relation === "behind") return "update-available"
  if (e.relation === "newer") return "newer"
  return "current"
}

function reasonWords(reason, name) {
  var n = name || "The plugin"
  switch (reason) {
    case "catalogue": return "The notch's plugin list is invalid."
    case "denied": return "Can't install that plugin here."
    case "unknown-id": return "That plugin isn't in the notch's list."
    case "sandbox": return "A test notch can't change plugins."
    case "locked": return "The session is locked."
    case "busy": return "A plugin job or update is running."
    case "not-installed": return n + " isn't installed."
    case "already-installed": return n + " is already installed."
    case "not-git": return "Not from git: reinstall to update."
    case "wrong-origin": return n + " was installed from somewhere else."
    case "local-changes": return n + " has local changes."
    case "plugin-busy": return n + " is busy: try again soon."
    case "changed": return "Notch updated: reopen this card."
    case "wrong-id": return "Verified commit isn't " + n + ": nothing changed."
    case "bar-kind": return "Verified commit is a bar, not " + n + "."
    case "renamed": return n + " has its old name: update it."
    case "rename": return "Rename unfinished: open Setup."
    case "invalid": return "Verified " + n + " didn't validate: left alone."
    case "newer": return "Newer than verified: left alone."
    case "not-started": return "Didn't start: another job may be running."
    case "command": return "The command failed."
    case "stopped": return "Stopped without finishing."
    case "offline": return "Couldn't reach GitHub."
    case "not-hosted": return "Turn " + n + " on first."
    case "not-running": return "Couldn't ask the shell."
    default: return "Something went wrong."
  }
}

function busyWords(action) {
  return action === "update" ? "Updating…" : action === "enable" ? "Turning on…" : action === "remove" ? "Removing…" : "Installing…"
}

// "Update to 1.4.0…", or "Update…" when the catalogue names no version.
function updateLabel(e) {
  return e.pinVersion ? "Update to " + e.pinVersion + "…" : "Update…"
}

// The non-empty parts of a state line, a middle dot between them.
function joinWords(parts) {
  return parts.filter(function(p) { return p !== "" }).join(" · ")
}

function entryView(entry, job, now, options) {
  options = options || {}
  var e = entry || {}
  var id = String(e.id || "")
  var name = String(e.name || id)
  var canAct = options.canAct === true
  var actions = []
  function act(action, label, primary, enabled) {
    actions.push({ name: action + ":" + id, label: label, primary: !!primary, enabled: canAct && enabled !== false })
  }
  var view = { id: id, name: name, version: String(e.version || ""), state: "", words: "", actions: actions }

  if (jobRunning(job, now) && job.id === id) {
    view.state = "busy"
    view.words = busyWords(job.action)
    return view
  }
  if (!e.checked) {
    view.state = "unchecked"
    view.words = canAct ? "Checking…" : "Not checked"
    return view
  }

  var words = ""
  var setupDue = e.setup === "needed" || e.setup === "attention"
  view.state = String(e.state || "")
  switch (view.state) {
    case "not-installed":
      words = "Not installed"
      act("install", "Install…", true)
      break
    case "other-source":
      words = "Installed from somewhere else"
      act("remove", "Remove…", false)
      break
    case "local-changes":
      words = e.dirty ? "Local edits" : "Differs from the verified version"
      act("review", "Review in terminal", false)
      act("remove", "Remove…", false)
      break
    case "disabled":
      words = joinWords(["Installed, turned off", e.relation === "behind" ? "Verified update ready" : "", setupDue ? "Turn on to set up" : ""])
      if (e.relation === "behind") act("update", updateLabel(e), false, !e.pluginBusy)
      act("enable", "Enable", true)
      break
    case "update-available":
      words = joinWords(["Verified update ready", e.renames ? "Renames to " + id : "", e.pluginBusy ? "Busy" : ""])
      act("remove", "Remove…", false)
      act("update", updateLabel(e), true, !e.pluginBusy)
      break
    case "newer":
      words = "Newer than the verified version"
      act("remove", "Remove…", false)
      break
    case "current":
      words = "Pinned to the verified version"
      act("remove", "Remove…", false)
      break
    default:
      words = "Unknown"
  }

  // An enabled plugin that says it needs setting up: its own panel, primary.
  if (e.enabled && setupDue && view.state !== "disabled") {
    words = joinWords([words, e.setup === "attention" ? "Needs attention" : "Needs setup"])
    for (var i = 0; i < actions.length; i++) actions[i].primary = false
    act("setup", "Open setup", true)
  }

  // An unseen failed job for this entry says why, until dismissed.
  if (job && job.id === id && job.seen !== true && (job.phase === "failed" || (job.phase === "running" && !jobRunning(job, now)))) {
    words = reasonWords(job.phase === "running" ? "stopped" : job.reason, name)
    act("dismiss", "Dismiss", false)
  }
  // A handoff that didn't reach the plugin's panel.
  var h = options.handoff
  if (h && h.id === id && h.ok === false) {
    words = reasonWords(h.reason, name)
    if (h.reason === "not-hosted" && !e.enabled && view.state !== "disabled" && e.installed) act("enable", "Enable", true)
    act("dismiss", "Dismiss", false)
  }
  view.words = words
  return view
}

// The notch's own row: never acted on here.
// The notch is listed with the plugins because it is updated the way they are.
// It used to carry a button that sent you to Settings -> Updates instead, which
// made "what is managed where" two answers to one question: everything you
// install or update lives here, everything you choose lives in Settings.
function selfView(self, update) {
  var s = self || {}
  var u = update || {}
  var id = String(s.id || "kalinewb.notch")
  var available = u.state === "available"
  var actions = []
  if (available && u.canUpdate !== false) {
    actions.push({ name: "updateSelf:" + id, label: "Update", primary: true, enabled: u.busy !== true })
  }
  actions.push({ name: "checkSelf:" + id, label: u.checking === true ? "Checking…" : "Check now",
                 primary: false, enabled: u.canCheck !== false && u.checking !== true })
  return {
    id: id, name: String(s.name || "Notch"), version: String(s.version || ""),
    state: "self", words: String(u.words || "This notch."),
    actions: actions
  }
}

// Where the notch's own updates stand, in words: its row's line. `check` is
// bin/notch-update's answer, `notice` the update notice's state.
function updateWords(check, enabled, notice) {
  if (!enabled) return "This notch doesn't update itself."
  if (notice === "updating") return "Updating…"
  var c = check || {}
  var version = c.localVersion ? " (" + c.localVersion + ")" : ""
  switch (c.state) {
    case "unchecked": return "Not checked yet" + version + "."
    case "current": return "Up to date" + version + "."
    case "available": return (c.remoteVersion && c.remoteVersion !== c.localVersion
      ? c.remoteVersion : (c.behind === 1 ? "1 change" : c.behind + " changes")) + " available."
    case "ahead": return "Ahead of GitHub (a development install)."
    case "diverged": return "Differs from GitHub: update by hand."
    case "dirty": return "Local edits: update by hand."
    case "not-git": return "Not a git install."
    case "offline": return "Couldn't reach GitHub."
    default: return "Couldn't check for updates."
  }
}
