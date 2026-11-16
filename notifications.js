.pragma library

// Reading Omarchy's live notification list, as pure functions.
//
// The notch is a display surface only: it does not own
// org.freedesktop.Notifications, does not watch the bus and never closes a
// notification. Omarchy keeps the cards on its screen in one file,
// ~/.local/state/omarchy/notifications/live.json: a JSON list of rows, oldest
// first, rewritten whole a moment after a card arrives, changes or leaves. So
// the file *is* the live set, and a row's `key` names it for as long as it is
// there. (Omarchy 4.5 and newer; before that it wrote one file per card.)
//
// What the file does not hold: a card that asked not to be kept (the
// "transient" hint), one Do Not Disturb kept off the screen, a card replayed
// from history, and any picture. A card with a verification code in it is
// kept only as a placeholder, which the notch leaves to Omarchy's own toast.
//
// No QML and no clock: every function takes what it needs, so
// dev/notifications.sh can drive it directly.

var RETRIES = 3        // reads after the first, for a file that would not parse
var RETRY_MS = 50
var POLL_MS = 2000     // reconcile interval while the watch is on
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

// A row's key, the way Omarchy's Store.js allows one.
var KEY = /^[A-Za-z0-9_-]{1,120}$/
var ROWS_LIMIT = 100
var ROW_CHARS = 16384

// What a placeholder says (Store.js REDACTED_SUMMARY and REDACTED_BODY): the
// card had a code in it, so only the fact of it was kept.
function redacted(row) {
  return !!row && row.summary === "Verification notification" && row.body === "[redacted]"
}

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

// live.json, read defensively: whatever is not a list of keyed objects is no
// list at all (`ok: false`, so the caller keeps what it had and tries again),
// an empty file is an empty list, and each row is cut down to what the notch
// draws. Oldest first, as Omarchy wrote it.
function parseLive(text) {
  var raw = String(text === undefined || text === null ? "" : text).replace(/^\s+|\s+$/g, "")
  if (raw === "") return { ok: true, rows: [] }
  if (raw.length > ROWS_LIMIT * ROW_CHARS * 2) return { ok: false, rows: [] }
  var parsed
  try { parsed = JSON.parse(raw) } catch (e) { return { ok: false, rows: [] } }
  if (!Array.isArray(parsed)) return { ok: false, rows: [] }
  var rows = [], seen = ({})
  for (var i = 0; i < parsed.length && rows.length < ROWS_LIMIT; i++) {
    var p = parsed[i]
    if (!p || typeof p !== "object" || Array.isArray(p)) continue
    if (typeof p.key !== "string" || !KEY.test(p.key) || seen[p.key] === true) continue
    var ts = Number(p.ts)
    if (!isFinite(ts) || ts <= 0) continue
    seen[p.key] = true
    var row = {
      key: p.key,
      app: String(p.app || ""),
      summary: String(p.summary || ""),
      body: String(p.body || ""),
      glyph: String(p.glyph || ""),
      execArgv: String(p.execArgv || ""),
      urgency: Number(p.urgency === undefined ? 1 : p.urgency),
      ts: ts
    }
    row.redacted = redacted(row)
    rows.push(row)
  }
  return { ok: true, rows: rows }
}

// What the activity queue is asked to show.
//
// No ttl: the line is the notch's copy of a toast, and the source times it
// itself (stay until acted on, or a number of seconds -- a setting), so the
// queue never expires it. What ends a copy is the user acting on it, that
// time, the notification source being switched off, or Omarchy's folder going
// away -- not Omarchy's own toast ending, which has its own, shorter clock.
function claimFor(key, entry) {
  var e = entry || {}
  var glyph = String(e.glyph || "")
  return {
    key: "notch.notifications." + key,
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
