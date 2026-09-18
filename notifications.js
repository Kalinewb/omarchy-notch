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
      urgency: Number(parsed.urgency === undefined ? 1 : parsed.urgency),
      timestamp: Number(parsed.timestamp || 0)
    }
  }
}

// What the activity queue is asked to show.
//
// The TTL is the transient ceiling rather than "forever": what normally ends a
// notification is its file leaving the folder, which is Omarchy's own timeout
// deciding, not the notch's. The TTL is the backstop for a watch event that
// never arrives -- a line that outlives its toast by 15 s is a blemish, one
// that never leaves is a bug. (platform.js clamps a transient to TTL_MAX
// anyway, so 0 would have become 3.5 s and cut every toast short.)
function claimFor(name, entry) {
  var e = entry || {}
  var glyph = String(e.glyph || "")
  return {
    key: "notch.notifications." + stem(name),
    priority: "transient",
    ttlMs: 15000,
    title: stripMarkup(e.summary) || stripMarkup(e.app) || "Notification",
    detail: stripMarkup(e.body),
    glyph: glyph.length > 0 && glyph.length <= 4 ? glyph : "",
    screens: []
  }
}
