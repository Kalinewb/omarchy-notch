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
    case "denied": return "That plugin can't be installed from the notch."
    case "unknown-id": return "That plugin isn't in the notch's list."
    case "sandbox": return "A test notch can't change plugins."
    case "locked": return "The session is locked."
    case "busy": return "Another plugin job or a notch update is running."
    case "not-installed": return n + " isn't installed."
    case "already-installed": return n + " is already installed."
    case "not-git": return n + " wasn't installed from git, so it can't update here."
    case "wrong-origin": return n + " was installed from somewhere else."
    case "local-changes": return n + " has local changes."
    case "plugin-busy": return n + " is busy. Try again when it has finished."
    case "changed": return "The notch was updated while this card was open. Open it again."
    case "wrong-id": return "The verified commit isn't " + n + ", so nothing changed."
    case "bar-kind": return "The verified commit is a bar, not " + n + ", so nothing changed."
    case "renamed": return n + " is installed under its old name. Update it instead."
    case "rename": return n + " was updated, but its rename didn't finish. Setup can finish it."
    case "invalid": return "The verified " + n + " didn't validate here, so it stays as it was."
    case "newer": return n + " is newer than the verified version, so it stays as it is."
    case "not-started": return "It didn't start. Another plugin job or a notch update may be running."
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
      words = "Installed, turned off" + (e.relation === "behind" ? " · verified update ready" : "")
      if (setupDue) words += ". Turn it on to set it up."
      if (e.relation === "behind") act("update", updateLabel(e), false, !e.pluginBusy)
      act("enable", "Enable", true)
      break
    case "update-available":
      words = "Verified update ready" + (e.renames ? " · renames it " + id : "")
      if (e.pluginBusy) words += " · busy"
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
    words += e.setup === "attention" ? " · needs attention" : " · needs setup"
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
