.pragma library

// The rules that decide whether a plugin's notch integration is accepted, and
// what a claim may contain. Pure functions, no QML: NotchPlatform.qml owns the
// state and the side effects, dev/platform.sh checks these by number.
//
// SURFACE-HOSTING.md is the author-facing version of everything here.

// The contract version this notch implements, and the oldest it still accepts.
// Additive changes (a new host member, a new claim field, a new verb) do not
// bump these; they go in FEATURES and authors feature-detect. A rename, a
// removed member, a changed result word or a changed queue rule bumps CONTRACT.
var CONTRACT = 1
var OLDEST = 1
var FEATURES = ["panel", "activityViews", "heartbeat"]

// Why an integration isn't shown, in the order the checks run.
var REASON_TEXT = {
  "": "Shown inside the notch",
  "invalid-manifest": "Its notch declaration has a problem",
  "contract-newer": "Needs a newer notch",
  "contract-older": "Written for an older notch",
  "not-enabled": "Plugin isn't enabled",
  "user-off": "Off",
  "loading": "Loading…",
  "load-error": "Couldn't load its notch view",
  "unavailable": "Not available right now"
}

function reasonText(reason, detail) {
  var text = REASON_TEXT[reason]
  if (text === undefined) text = "Not shown"
  if (reason === "invalid-manifest" && detail) return text + ": " + detail
  return text
}

// acceptance(scan, enabled, userOff, loadStatus, available) -> {accepted, reason, detail}
//
// `scan` is one entry from bin/notch-integrations. `loadStatus` is "none" (no
// entry file: the plugin claims activities only), "loading", "ready" or
// "error". `available` is what the integration itself says.
function acceptance(scan, enabled, userOff, loadStatus, available, loadError) {
  function no(reason, detail) { return { accepted: false, reason: reason, detail: detail || "" } }
  if (!scan) return no("invalid-manifest", "no manifest")
  if (scan.problems && scan.problems.length > 0) return no("invalid-manifest", String(scan.problems[0]))
  var contract = Number(scan.contract)
  if (!(contract > 0)) return no("invalid-manifest", "bad-contract")
  if (contract > CONTRACT) return no("contract-newer")
  // Unreachable while OLDEST is 1, because a contract below 1 isn't a contract
  // at all and was already refused above. It becomes reachable when OLDEST moves.
  if (contract < OLDEST) return no("contract-older")
  if (enabled !== true) return no("not-enabled")
  if (userOff === true) return no("user-off")
  if (scan.entry) {
    if (loadStatus === "loading" || loadStatus === "none") return no("loading")
    if (loadStatus === "error") return no("load-error", loadError || "")
  }
  if (available === false) return no("unavailable")
  return { accepted: true, reason: "", detail: "" }
}

// Should this candidate's integration file be loaded at all? Everything up to
// the load itself has to pass -- plus `pendingUnload`, which keeps a Loader
// alive while its panel fades out (NotchPlatform.qml).
function gate(candidate) {
  if (!candidate) return false
  if (candidate.pendingUnload === true) return true
  var scan = candidate.scan
  if (!scan || !scan.entry) return false
  if (scan.problems && scan.problems.length > 0) return false
  var contract = Number(scan.contract)
  if (!(contract > 0) || contract > CONTRACT || contract < OLDEST) return false
  if (candidate.enabled !== true) return false
  if (candidate.userOff === true) return false
  return true
}

// --- claims -----------------------------------------------------------------

var PRIORITIES = ["transient", "persistent", "persistent-low"]
var TITLE_MAX = 60
// The body gets two wrapped rows in the notch now, so 80 characters is no
// longer a bound on what can be shown -- it was a bound on what could be read,
// and `clip` cuts mid-word with nothing to say it did. This is a safety bound
// (a claim cannot be a novel); the display elides, visibly, at whatever it can
// actually fit.
var DETAIL_MAX = 240
var GLYPH_MAX = 4
var TTL_MIN = 500
var TTL_MAX = 15000
var TTL_DEFAULT = 3500
var IPC_TTL_MIN = 1000
var IPC_TTL_MAX = 60000

function clip(text, max) {
  var value = String(text === undefined || text === null ? "" : text)
  return value.length > max ? value.slice(0, max) : value
}

// validClaim(owner, obj, fromIpc) -> {ok, claim, reason}
//
// A claim may only carry a key of its own owner's: `owner`, or `owner.`
// something. Nothing here trusts the caller's own idea of who it is; the caller
// is decided before this runs.
function validClaim(owner, obj, fromIpc) {
  function bad(reason) { return { ok: false, claim: null, reason: reason } }
  if (!owner) return bad("unknown-owner")
  if (!obj || typeof obj !== "object") return bad("bad-payload")
  var title = clip(obj.title, TITLE_MAX)
  if (!title) return bad("bad-payload")

  var key = obj.key === undefined || obj.key === null || obj.key === "" ? owner : String(obj.key)
  if (key !== owner && key.indexOf(owner + ".") !== 0) return bad("bad-key")

  var priority = obj.priority === undefined ? "transient" : String(obj.priority)
  if (PRIORITIES.indexOf(priority) === -1) return bad("bad-payload")

  var ttl = Number(obj.ttlMs)
  if (priority === "transient") {
    if (!(ttl > 0)) ttl = TTL_DEFAULT
    ttl = Math.max(TTL_MIN, Math.min(TTL_MAX, ttl))
  } else if (fromIpc) {
    // An out-of-process owner can go away without saying so, so a persistent
    // claim of theirs has to be renewed rather than trusted forever.
    if (!(ttl > 0)) return bad("bad-payload")
    ttl = Math.max(IPC_TTL_MIN, Math.min(IPC_TTL_MAX, ttl))
  } else {
    ttl = ttl > 0 ? Math.max(TTL_MIN, Math.min(IPC_TTL_MAX, ttl)) : 0
  }

  var progress = Number(obj.progress)
  if (!(progress >= 0 && progress <= 1)) progress = -1

  var screens = []
  if (obj.screens && obj.screens.length !== undefined) {
    for (var i = 0; i < obj.screens.length; i++) screens.push(String(obj.screens[i]))
  }

  return {
    ok: true,
    reason: "",
    claim: {
      owner: String(owner), key: key, priority: priority, title: title,
      detail: clip(obj.detail, DETAIL_MAX), glyph: clip(obj.glyph, GLYPH_MAX),
      progress: progress, view: obj.view === undefined ? "" : String(obj.view),
      screens: screens, ttlMs: ttl,
      panelRoute: obj.panelRoute === undefined ? "" : String(obj.panelRoute),
      at: Number(obj.at) > 0 ? Number(obj.at) : 0
    }
  }
}
