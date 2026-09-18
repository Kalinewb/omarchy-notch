.pragma library

// The activity queue: what the resting notch is showing, and what is waiting.
//
// An activity is a short or ongoing line a plugin asks the notch to show
// ("Switching to test…", "Look at the camera"). At most two are visible; the
// rest queue. Pure state in, pure state out -- no QML, no timers, no clock of
// its own: every function takes `now`, so dev/platform.sh can drive time.
//
// Shared with plan-activities-notifications.md, which draws them.

var MAX_VISIBLE = 2
var QUEUE_WAIT_MS = 10000
var OWNER_LIMIT = 4
var RANK = { "transient": 0, "persistent": 1, "persistent-low": 2 }

function create() {
  return { visible: [], queued: [], seq: 0 }
}

function copy(state) {
  return { visible: state.visible.slice(), queued: state.queued.slice(), seq: state.seq }
}

function rankOf(entry) { return RANK[entry.priority] === undefined ? 1 : RANK[entry.priority] }

function entryFor(claim, seq, now) {
  return {
    owner: claim.owner, key: claim.key, priority: claim.priority, title: claim.title,
    detail: claim.detail, glyph: claim.glyph, progress: claim.progress, view: claim.view,
    screens: claim.screens, ttlMs: claim.ttlMs, panelRoute: claim.panelRoute, at: claim.at,
    seq: seq, claimedAt: now, shownAt: 0,
    expiresAt: 0
  }
}

function sameEntry(entry, owner, key) { return entry.owner === owner && entry.key === key }

function countFor(state, owner) {
  var n = 0, i
  for (i = 0; i < state.visible.length; i++) if (state.visible[i].owner === owner) n++
  for (i = 0; i < state.queued.length; i++) if (state.queued[i].owner === owner) n++
  return n
}

function show(entry, now) {
  entry.shownAt = now
  entry.expiresAt = entry.ttlMs > 0 ? now + entry.ttlMs : 0
  return entry
}

// Where a queued entry belongs: ordered by rank, FIFO by seq inside a rank.
function insertQueued(queue, entry) {
  var rank = rankOf(entry)
  for (var i = 0; i < queue.length; i++) {
    var other = queue[i]
    var otherRank = rankOf(other)
    if (otherRank > rank || (otherRank === rank && other.seq > entry.seq)) {
      queue.splice(i, 0, entry)
      return queue
    }
  }
  queue.push(entry)
  return queue
}

// The head of its own rank: where a preempted entry goes back to, so it is the
// next of its kind to be shown again rather than the last.
function insertAtRankHead(queue, entry) {
  var rank = rankOf(entry)
  for (var i = 0; i < queue.length; i++) {
    if (rankOf(queue[i]) >= rank) { queue.splice(i, 0, entry); return queue }
  }
  queue.push(entry)
  return queue
}

// claim(state, claim, now) -> {state, result}
// result: "shown", "queued" or "declined:<reason>"
function claim(state, incoming, now) {
  var next = copy(state)
  var i

  // Same owner and key: replace in place, keep the slot and the seq.
  for (i = 0; i < next.visible.length; i++) {
    if (sameEntry(next.visible[i], incoming.owner, incoming.key)) {
      var kept = entryFor(incoming, next.visible[i].seq, next.visible[i].claimedAt)
      next.visible[i] = show(kept, now)
      return { state: next, result: "shown" }
    }
  }
  for (i = 0; i < next.queued.length; i++) {
    if (sameEntry(next.queued[i], incoming.owner, incoming.key)) {
      var keptQueued = entryFor(incoming, next.queued[i].seq, next.queued[i].claimedAt)
      next.queued[i] = keptQueued
      return { state: next, result: "queued" }
    }
  }

  if (countFor(next, incoming.owner) >= OWNER_LIMIT) return { state: state, result: "declined:owner-limit" }

  next.seq = next.seq + 1
  var entry = entryFor(incoming, next.seq, now)

  if (next.visible.length < MAX_VISIBLE) {
    next.visible.push(show(entry, now))
    return { state: next, result: "shown" }
  }

  if (entry.priority === "transient") {
    // A transient may take a slot from something slower, which goes back to
    // the head of its own rank rather than being dropped.
    var worst = -1
    for (i = 0; i < next.visible.length; i++) {
      if (rankOf(next.visible[i]) === 0) continue
      // The lowest-ranked one, and among equals the one shown most recently --
      // ties go to the later slot, so the choice never depends on ordering luck.
      if (worst === -1 || rankOf(next.visible[i]) > rankOf(next.visible[worst])
          || (rankOf(next.visible[i]) === rankOf(next.visible[worst]) && next.visible[i].shownAt >= next.visible[worst].shownAt))
        worst = i
    }
    if (worst !== -1) {
      var preempted = next.visible[worst]
      preempted.shownAt = 0
      preempted.expiresAt = 0
      insertAtRankHead(next.queued, preempted)
      next.visible[worst] = show(entry, now)
      return { state: next, result: "shown" }
    }
  }

  insertQueued(next.queued, entry)
  return { state: next, result: "queued" }
}

function release(state, owner, key) {
  var next = copy(state)
  var i
  for (i = 0; i < next.visible.length; i++) {
    if (sameEntry(next.visible[i], owner, key)) {
      next.visible.splice(i, 1)
      promote(next, 0)
      return { state: next, result: "released" }
    }
  }
  for (i = 0; i < next.queued.length; i++) {
    if (sameEntry(next.queued[i], owner, key)) {
      next.queued.splice(i, 1)
      return { state: next, result: "released" }
    }
  }
  return { state: state, result: "unknown" }
}

function releaseOwner(state, owner) {
  var next = copy(state)
  next.visible = next.visible.filter(function (entry) { return entry.owner !== owner })
  next.queued = next.queued.filter(function (entry) { return entry.owner !== owner })
  promote(next, 0)
  return next
}

// Fill free slots from the head of the queue. `now` is 0 when the caller has
// no clock to hand (a release), and the entry is shown at its promotion time.
function promote(state, now) {
  while (state.visible.length < MAX_VISIBLE && state.queued.length > 0) {
    var entry = state.queued.shift()
    state.visible.push(show(entry, now))
  }
  return state
}

// tick(state, now): expire what has run out, drop transients that waited too
// long, and promote into whatever that freed.
function tick(state, now) {
  var next = copy(state)
  next.visible = next.visible.filter(function (entry) {
    return !(entry.expiresAt > 0 && now >= entry.expiresAt)
  })
  next.queued = next.queued.filter(function (entry) {
    return !(entry.priority === "transient" && now - entry.claimedAt > QUEUE_WAIT_MS)
  })
  promote(next, now)
  return next
}

function report(state) {
  function line(entry) {
    return {
      owner: entry.owner, key: entry.key, priority: entry.priority, title: entry.title,
      detail: entry.detail, glyph: entry.glyph, progress: entry.progress, view: entry.view,
      screens: entry.screens, seq: entry.seq, at: entry.at,
      shownAt: entry.shownAt, expiresAt: entry.expiresAt, panelRoute: entry.panelRoute
    }
  }
  return { maxVisible: MAX_VISIBLE, visible: state.visible.map(line), queued: state.queued.map(line) }
}
