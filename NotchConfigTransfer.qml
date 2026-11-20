import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// What a Share or Import row holds on its right (plan-export.md 4): a state word,
// then the buttons that fit the moment. Everything it runs is bin/notch-config
// and, to apply or undo, Setup's own jobs (SetupService); it writes nothing.
//
//   export   [Copy code] [Save file]    Copied, Saved, Too long, Failed
//   import   [Import]                   reads the clipboard: a code, or the path of a saved file,
//                                        and shows what it would change (NotchConfigPreview)
//            "3 changes" [Apply] [Cancel]   then Importing, Imported [Undo] [Import], Undone, Failed
//
// `done(result)` says how a run ended -- copied saved imported unchanged undone --
// for a host that wants to follow (the guided setup's last screen). A preview is
// a question waiting: the panel's Escape and the notch's back strip answer it no
// (`cancel`), and so does opening the panel again.
Row {
  id: root

  // The Settings panel: its look and foot line, and the bar (for Setup's jobs).
  property var page: null
  // The row it sits in: its fold holds the preview, and its state is the word shown here.
  property Item row: null
  // "both", "export" or "import": which buttons there are.
  property string mode: "both"
  signal done(string result)

  readonly property var bar: page ? page.bar : null
  readonly property var setup: bar ? bar.setup : null
  readonly property string script: String(Qt.resolvedUrl("bin/notch-config")).replace(/^file:\/\//, "")

  // idle, working (a run is out), preview, applying
  property string phase: "idle"
  // The state word: empty at rest.
  property string note: ""
  // What `import --stage` printed (changes, skipped, moves, staged), while it is shown.
  property var preview: null
  // The snapshot an import made, for Undo.
  property string snapshot: ""
  property real startedAt: 0

  readonly property bool previewing: phase === "preview"
  readonly property var buttons: {
    if (phase === "working" || phase === "applying") return []
    if (phase === "preview") return [{ text: "Apply", name: "apply" }, { text: "Cancel", name: "cancel" }]
    var out = []
    if (mode !== "import") out.push({ text: "Copy code", name: "copy" }, { text: "Save file", name: "save" })
    if (mode !== "export") out = out.concat(snapshot !== "" ? [{ text: "Undo", name: "undo" }] : [], [{ text: "Import", name: "import" }])
    return out
  }

  spacing: Style.space(6)
  onNoteChanged: if (row) row.stateText = note
  onPreviewingChanged: if (row) row.open = previewing

  function say(word, result) {
    note = word
    if (result) done(result)
    clearTimer.restart()
  }
  // Back to rest. A run that is out keeps its word; an import's Undo stays until the panel opens again.
  function reset() { cancel(); if (phase === "idle") { note = ""; snapshot = "" } }

  // What a button, a key or the test hook asks for.
  function press(name) {
    // Only where Setup runs, as the rows themselves: a test notch reads no clipboard and starts nothing.
    if (phase === "working" || phase === "applying" || !setup || !setup.enabled) return
    clearTimer.stop()
    if (name === "copy") run("copy")
    else if (name === "save") run("save")
    else if (name === "import") run("import")
    else if (name === "apply") apply()
    else if (name === "cancel") cancel()
    else if (name === "undo") undo()
  }

  // Answer a preview no; whether there was one.
  function cancel() {
    if (phase !== "preview") return false
    forget(preview ? preview.staged : "")
    preview = null
    phase = "idle"
    note = ""
    return true
  }
  // The staged document is used once; one that is not is deleted, and only ever from its own folder.
  function forget(path) {
    if (/\/staged\/[0-9a-f]{8}\.json$/.test(String(path || ""))) Quickshell.execDetached(["rm", "-f", "--", String(path)])
  }

  function run(what) {
    phase = "working"
    note = what === "import" ? "Reading" : ""
    runner.what = what
    runner.command = what === "import"
      ? ["sh", "-c", 'timeout 2 wl-paste -n 2>/dev/null | head -c 12001 | "$1" import - --stage 2>/dev/null', "notch-config", script]
      : what === "copy" ? ["sh", "-c", 'out=$("$1" export 2>/dev/null); rc=$?; printf "%s\\n%s" "$rc" "$out"', "notch-config", script]
      : [script, "export", "--file", "~/notch-config.json"]
    runner.running = true
  }

  // The words for a refusal, from notch-config's one-word reasons.
  readonly property var reasons: ({ "not-code": "Not a notch code", "damaged": "Damaged", "newer": "Newer notch",
                                    "too-long": "Too long", "empty": "Nothing copied" })

  Process {
    id: runner
    property string what: ""
    // Saving prints nothing, so its word waits for the exit; the others print what they need.
    stdout: StdioCollector { id: collected; onStreamFinished: if (runner.what !== "save") root.finished(runner.what, collected.text, 0) }
    onExited: function(code) { if (runner.what === "save") root.finished("save", "", code) }
  }
  Process {
    id: clipboard
    onExited: function(code) { root.phase = "idle"; root.say(code === 0 ? "Copied" : "Failed", code === 0 ? "copied" : "") }
  }

  function finished(what, text, code) {
    if (phase !== "working") return
    if (what === "save") { phase = "idle"; say(code === 0 ? "Saved" : "Failed", code === 0 ? "saved" : ""); return }
    if (what === "copy") {
      var at = text.indexOf("\n")
      var rc = at < 0 ? "1" : text.slice(0, at)
      var code_ = at < 0 ? "" : text.slice(at + 1).trim()
      if (rc !== "0" || code_ === "") { phase = "idle"; say(rc === "2" ? "Too long" : "Failed"); return }
      clipboard.command = ["sh", "-c", 'printf %s "$1" | wl-copy', "copy", code_]
      clipboard.running = true
      return
    }
    var plan = null
    try { plan = JSON.parse(text) } catch (e) { plan = null }
    phase = "idle"
    if (!plan || typeof plan !== "object") { say("Failed"); return }
    if (plan.reason) { say(reasons[plan.reason] || "Failed"); return }
    if (!plan.staged) { say("Nothing to change", "unchanged"); return }
    preview = plan
    note = plan.changes.length > 0 ? plan.changes.length + (plan.changes.length === 1 ? " change" : " changes") : "Widget order"
    phase = "preview"
  }

  function apply() {
    if (phase !== "preview" || !setup) return
    startedAt = Date.now()
    if (!setup.startFix("config-import", preview.staged)) { say("Failed"); return }
    phase = "applying"
    note = "Importing"
  }
  function undo() {
    if (!setup || snapshot === "") return
    startedAt = Date.now()
    if (!setup.startRestore(snapshot, "")) { say("Failed"); return }
    phase = "applying"
    note = "Undoing"
  }

  // The job's status file says how it went. An older job's status is still in
  // the file for a moment after a start, so only one that began after the press counts.
  Connections {
    target: root.setup
    function onJobChanged() {
      var job = root.setup.job || {}
      if (root.phase !== "applying" || job.point !== "config-import" || Number(job.startedAt || 0) < root.startedAt) return
      var finalPhases = ["done", "failed", "rolled-back", "conflict", "locked-out"]
      if (finalPhases.indexOf(job.phase) === -1) return
      var restoring = job.action === "restore"
      root.phase = "idle"
      root.preview = null
      if (job.phase !== "done") { root.say("Failed"); return }
      root.snapshot = restoring ? "" : String(job.snapshot || "")
      root.say(restoring ? "Undone" : "Imported", restoring ? "undone" : "imported")
      // An import is one more thing Earlier fixes can undo.
      root.setup.refreshSnapshots()
    }
  }
  Connections {
    target: root.page
    function onEnabledChanged() { if (root.page.enabled) root.reset() }
  }
  // The row's own press (the test hook, `set:<row>:<button>`).
  Connections {
    target: root.row
    function onChosen(value) { root.press(String(value)) }
  }
  // Copied, Saved and the refusals go quiet by themselves; an import's result does not.
  Timer { id: clearTimer; interval: 4000; onTriggered: if (root.phase === "idle" && root.snapshot === "") root.note = "" }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    visible: root.note !== ""
    text: root.note
    color: root.page ? root.page.foreground : "#ffffff"
    font.family: root.page ? root.page.fontFamily : Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: root.buttons
    NotchPanelButton {
      required property var modelData
      page: root.page
      text: modelData.text
      onClicked: root.press(modelData.name)
    }
  }
}
