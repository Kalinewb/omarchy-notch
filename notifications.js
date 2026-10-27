.pragma library

// Reading Omarchy's toast state files, as pure functions.
//
// The notch is a display surface only: it does not own
// org.freedesktop.Notifications, does not watch the bus and never closes a
// notification. Omarchy writes one JSON file per toast into
// ~/.local/state/omarchy/notifications while it is on screen and moves it to
// history/ when it expires or is dismissed, so the folder *is* the live set.
//
// No QML and no clock: every function takes what it needs, so
// dev/notifications.sh can drive it directly.

var RETRIES = 3        // reads after the first, for a file caught mid-write
var RETRY_MS = 50
var POLL_MS = 2000     // reconcile interval while inotify is watching
var POLL_ONLY_MS = 500 // …and when polling is all there is
var OWNER_LIMIT = 4    // claimed at once; the rest wait their turn

// How long the notch's copy of a toast stays: until the user acts, or this many
// seconds after it appears. Omarchy's own toast keeps its own clock; this is the
// notch's, so the setting is the whole of it.
var SECONDS_DEFAULT = 6
var SECONDS_MIN = 1
var SECONDS_MAX = 60

function seconds(value) {
  var n = Number(value)
  if (!isFinite(n) || value === "" || value === null || value === undefined) return SECONDS_DEFAULT
  return Math.max(SECONDS_MIN, Math.min(SECONDS_MAX, Math.round(n)))
}

// 0 means "until I act".
function lifetimeMs(stay, value) { return stay === true ? 0 : seconds(value) * 1000 }

// "<stamp>-<id>.json". Anything else -- history/, images/, .tmp files,
// dotfiles -- is not a live toast.
function parseName(name) {
  var m = /^(\d+)-(\d+)\.json$/.exec(String(name || ""))
  return m ? { stamp: Number(m[1]), id: Number(m[2]) } : null
}

function stem(name) { return String(name).replace(/\.json$/, "") }

// Omarchy's cards render Qt rich text, so a summary or body may carry markup.
// The notch draws PlainText, so the markup has to come out rather than be
// shown. The tag rule matches NotificationLogic.stripImageTags: an unterminated
// "<" at the end is one run, because that is what the renderer does with it.
function stripMarkup(value) {
  var text = String(value === undefined || value === null ? "" : value)
  var out = ""
  var i = 0
  while (i < text.length) {
    var open = text.indexOf("<", i)
    if (open === -1) { out += text.slice(i); break }
    out += text.slice(i, open)
    var close = text.indexOf(">", open)
    i = close === -1 ? text.length : close + 1
  }
  out = out.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
           .replace(/&apos;/g, "'").replace(/&#39;/g, "'").replace(/&amp;/g, "&")
  return out.replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").replace(/^ | $/g, "")
}

// A file caught between open and write is empty or half-written, which is why
// the caller retries rather than giving up on the first failure.
function entryFromText(text) {
  var raw = String(text === undefined || text === null ? "" : text).replace(/^\s+|\s+$/g, "")
  if (raw === "") return { ok: false }
  var parsed
  try { parsed = JSON.parse(raw) } catch (e) { return { ok: false } }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return { ok: false }
  return {
    ok: true,
    entry: {
      app: String(parsed.app || parsed.appName || ""),
      summary: String(parsed.summary || ""),
      body: String(parsed.body || ""),
      glyph: String(parsed.glyph || parsed.icon || ""),
      execArgv: String(parsed.execArgv || ""),
      urgency: Number(parsed.urgency === undefined ? 1 : parsed.urgency),
      timestamp: Number(parsed.timestamp || 0)
    }
  }
}

// What the activity queue is asked to show.
//
// No ttl: the line is the notch's copy of a toast, and the source times it
// itself (stay until acted on, or a number of seconds -- a setting), so the
// queue never expires it. What ends a copy is the user acting on it, that
// time, the notification source being switched off, or Omarchy's folder going
// away -- not Omarchy's own toast ending, which has its own, shorter clock.
function claimFor(name, entry) {
  var e = entry || {}
  var glyph = String(e.glyph || "")
  return {
    key: "notch.notifications." + stem(name),
    priority: "transient",
    ttlMs: 0,
    title: stripMarkup(e.summary) || stripMarkup(e.app) || "Notification",
    detail: stripMarkup(e.body),
    glyph: glyph.length > 0 && glyph.length <= 4 ? glyph : "",
    screens: []
  }
}

// The argv a toast carries for its click (Omarchy's own toasts do): a JSON array
// of strings whose first is not an option. The same test Omarchy's service
// makes before it runs one (NotificationLogic.parseExecArgv).
function argvFrom(value) {
  var text = String(value || "")
  if (!text) return null
  var parsed
  try { parsed = JSON.parse(text) } catch (e) { return null }
  if (!Array.isArray(parsed) || parsed.length === 0) return null
  for (var i = 0; i < parsed.length; i++) if (typeof parsed[i] !== "string") return null
  if (!parsed[0] || parsed[0].charAt(0) === "-") return null
  return parsed
}
