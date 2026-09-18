import QtQuick
import Quickshell
import Quickshell.Io
import "platform.js" as Platform
import "activities.js" as Activities

// The notch as a platform: how another plugin's UI gets inside it.
//
// Omarchy gives a plugin no way to see the others, so this reads the plugins
// folder itself (bin/notch-integrations, read-only), finds the ones whose
// manifest declares `entryPoints.surface` and a `surface.contract`, decides which
// of them the notch accepts (platform.js), and loads each accepted
// integration's QML **once** -- not once per monitor, so an integration never
// duplicates its files, processes or IPC targets. Its panel Component is then
// created per screen by the notch's own panel host.
//
// Each plugin gets one NotchHost: the only notch object it ever sees.
//
// Nothing about this is on for a test notch unless it asks
// (NOTCH_FORCE_PLATFORM=1 plus NOTCH_PLUGINS_DIR), so the existing suites see
// no change and no harness ever reads the real plugins folder.
Item {
  id: platform
  visible: false

  required property var bar

  readonly property int contract: Platform.CONTRACT
  readonly property int oldest: Platform.OLDEST
  readonly property var features: Platform.FEATURES

  readonly property bool harnessed: !!bar && bar.harnessed
  readonly property string pluginsDir: {
    var forced = Quickshell.env("NOTCH_PLUGINS_DIR")
    if (forced) return forced
    if (harnessed) return ""
    var home = Quickshell.env("HOME") || ""
    var config = Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    return config + "/omarchy/plugins"
  }
  readonly property bool enabled: (((!!bar && !!bar.shell && !harnessed) || Quickshell.env("NOTCH_FORCE_PLATFORM") === "1")
    && pluginsDir !== "")

  // False while the notch is being taken apart, so a plugin watching its host
  // knows to draw its own UI again.
  property bool present: true

  readonly property string script: String(Qt.resolvedUrl("bin/notch-integrations")).replace(/^file:\/\//, "")

  // id -> { scan, enabled, enabledBy, userOff, loadStatus, loadError, available,
  //         accepted, reason, detail, pendingUnload }
  // Replaced whole, never mutated in place, so bindings that read it re-evaluate.
  property var candidates: ({})
  property var loaders: ({})
  property var hosts: ({})
  property var loads: ({})
  property var unloadAt: ({})
  property bool scanning: false
  property real scannedAt: 0

  readonly property var list: {
    var ids = Object.keys(candidates).sort()
    var out = []
    for (var i = 0; i < ids.length; i++) {
      var candidate = candidates[ids[i]]
      var scan = candidate.scan || {}
      var item = loaders[ids[i]] && loaders[ids[i]].item ? loaders[ids[i]].item : null
      out.push({
        id: ids[i], name: scan.name || ids[i], version: scan.version || "", dir: scan.dir || "",
        contract: Number(scan.contract || 0), entry: scan.entry || "", problems: scan.problems || [],
        enabled: candidate.enabled === true, enabledBy: candidate.enabledBy || "",
        userOff: candidate.userOff === true, loadStatus: candidate.loadStatus || "none",
        loads: Number(loads[ids[i]] || 0), pendingUnload: candidate.pendingUnload === true,
        accepted: candidate.accepted === true, reason: candidate.reason || "",
        reasonDetail: candidate.detail || "",
        reasonText: Platform.reasonText(candidate.reason || "", candidate.detail || ""),
        hasPanel: !!(item && item.panel),
        activityViews: item && item.activityViews ? Object.keys(item.activityViews) : []
      })
    }
    return out
  }

  readonly property int acceptedCount: {
    var n = 0
    for (var id in candidates) if (candidates[id].accepted) n++
    return n
  }

  // --- what a panel may use --------------------------------------------------

  readonly property real maxPanelWidth: {
    var window = bar ? bar.focusedNotchWindow() : null
    return window ? window.maxBarWidth - 2 * bar.notchSidePadding : 0
  }
  readonly property real maxPanelHeight: {
    var window = bar ? bar.focusedNotchWindow() : null
    return window ? window.panelMaxHeight : 0
  }

  // --- scanning ---------------------------------------------------------------

  function rescan() {
    if (!enabled || scanProcess.running) return false
    scanProcess.command = [script, "scan", pluginsDir]
    scanProcess.running = true
    scanning = true
    return true
  }

  Process {
    id: scanProcess
    stdout: StdioCollector {
      onStreamFinished: {
        var scanned = []
        try { scanned = JSON.parse(text) } catch (e) { scanned = [] }
        platform.applyScan(scanned)
        platform.scanning = false
        platform.scannedAt = Date.now()
      }
    }
    onRunningChanged: if (!running) platform.scanning = false
  }

  // The host's widget catalogue is the cheap answer to "is this plugin
  // enabled": Omarchy registers a plugin's bar widget under its manifest id,
  // and only while it is enabled.
  function enabledFromCatalogue(id) {
    var registry = bar ? bar.barWidgetRegistry : null
    if (!registry || typeof registry.metadataFor !== "function") return null
    var meta = registry.metadataFor(id)
    if (!meta) return null
    if (meta.pluginId !== undefined && String(meta.pluginId) !== id) return null
    return true
  }

  // A plugin with no bar widget can't be found that way. In a harness the
  // answer comes from the environment and no process is ever started; live, the
  // shell is asked.
  function enabledFromEnv(id) {
    var listed = Quickshell.env("NOTCH_PLATFORM_ENABLED") || ""
    if (listed === "*") return true
    return listed.split(/\s+/).indexOf(id) !== -1
  }

  property var listPluginsAnswer: ({})
  property int listPluginsTries: 0

  Process {
    id: listPluginsProcess
    // `omarchy-shell` refuses without OMARCHY_PATH, and a transient shell
    // environment may not carry it, so it is passed explicitly.
    command: ["env", "OMARCHY_PATH=" + (platform.bar ? platform.bar.omarchyPath : ""), "omarchy-shell", "shell", "listPlugins"]
    stdout: StdioCollector {
      onStreamFinished: {
        var answer = {}
        try {
          var parsed = JSON.parse(text)
          var rows = parsed.length !== undefined ? parsed : (parsed.plugins || [])
          for (var i = 0; i < rows.length; i++) answer[String(rows[i].id)] = rows[i].enabled === true
        } catch (e) { answer = {} }
        platform.listPluginsAnswer = answer
        platform.refresh()
      }
    }
    // "Not ready to accept queries yet" exits 1 and is worth another go.
    onRunningChanged: {
      if (running || platform.listPluginsTries >= 3) return
      if (Object.keys(platform.listPluginsAnswer).length > 0) return
      platform.listPluginsTries++
      listPluginsRetry.restart()
    }
  }
  Timer { id: listPluginsRetry; interval: 500; onTriggered: listPluginsProcess.running = true }

  property var scanResult: []

  function applyScan(scanned) {
    scanResult = scanned
    var needsShell = false
    for (var i = 0; i < scanned.length; i++) {
      var id = String(scanned[i].id)
      if (enabledFromCatalogue(id) === null && !harnessed && listPluginsAnswer[id] === undefined) needsShell = true
    }
    if (needsShell && !harnessed && bar && bar.omarchyPath && !listPluginsProcess.running) {
      listPluginsTries = 0
      listPluginsProcess.running = true
    }
    refresh()
  }

  // Rebuild `candidates` from the last scan plus everything that can change
  // under it (enablement, the user's switch, load status). Idempotent: an
  // unchanged candidate comes out identical, so its Loader is never touched.
  function refresh() {
    var next = ({})
    var userOffList = bar ? bar.notchDisabledIntegrations : []
    for (var i = 0; i < scanResult.length; i++) {
      var scan = scanResult[i]
      var id = String(scan.id)
      var previous = candidates[id] || {}
      var enabledBy = ""
      var isEnabled = enabledFromCatalogue(id)
      if (isEnabled === true) enabledBy = "catalogue"
      else if (harnessed) { isEnabled = enabledFromEnv(id); if (isEnabled) enabledBy = "harness-env" }
      else if (listPluginsAnswer[id] !== undefined) { isEnabled = listPluginsAnswer[id]; if (isEnabled) enabledBy = "listPlugins" }
      else isEnabled = false

      var loader = loaders[id]
      var loadStatus = "none"
      var loadError = ""
      if (scan.entry) {
        if (!loader) loadStatus = "loading"
        else if (loader.status === Loader.Ready) loadStatus = "ready"
        else if (loader.status === Loader.Error) { loadStatus = "error"; loadError = previous.loadError || "" }
        else loadStatus = "loading"
      }
      var item = loader && loader.item ? loader.item : null
      var available = item && item.available !== undefined ? item.available === true : true

      var userOff = userOffList.indexOf(id) !== -1
      var verdict = Platform.acceptance(scan, isEnabled, userOff, loadStatus, available, loadError)
      next[id] = {
        scan: scan, enabled: isEnabled === true, enabledBy: enabledBy, userOff: userOff,
        loadStatus: loadStatus, loadError: loadError, available: available,
        accepted: verdict.accepted, reason: verdict.reason, detail: verdict.detail,
        pendingUnload: previous.pendingUnload === true
      }

      // It was shown and isn't accepted any more: close its panel and let its
      // claims go, but keep the file loaded while the panel fades out, so the
      // notch shrinks with content in it rather than emptying first.
      if (previous.accepted === true && !verdict.accepted) {
        if (verdict.reason === "user-off" || verdict.reason === "not-enabled") {
          next[id].pendingUnload = true
          var deadlines = JSON.parse(JSON.stringify(unloadAt))
          deadlines[id] = Date.now() + 300
          unloadAt = deadlines
          unloadTimer.restart()
        }
        releaseOwner(id)
        closePanelFor(id)
      }

      // Switched off and on again inside the 300 ms fade: the file never left,
      // so the mark to unload it has to go too. Left set it stuck true for the
      // life of the notch -- the timer only ever clears it for something that
      // is still not accepted -- and the next switch-off then had a deadline
      // already in the past.
      if (verdict.accepted && next[id].pendingUnload) {
        next[id].pendingUnload = false
        if (unloadAt[id] !== undefined) {
          var cleared = JSON.parse(JSON.stringify(unloadAt))
          delete cleared[id]
          unloadAt = cleared
        }
      }
    }

    // A candidate that vanished takes its host, claims and panel with it.
    for (var old in candidates) {
      if (next[old] === undefined) {
        releaseOwner(old)
        closePanelFor(old)
      }
    }

    candidates = next
    syncLoaderModel()
    writeBeat()
  }

  Timer {
    id: unloadTimer
    interval: 320
    onTriggered: {
      var now = Date.now()
      var next = JSON.parse(JSON.stringify(unloadAt))
      var changed = false
      var updated = ({})
      for (var id in candidates) {
        var candidate = candidates[id]
        var copy = {}
        for (var key in candidate) copy[key] = candidate[key]
        if (copy.pendingUnload && next[id] !== undefined && now >= next[id] && !copy.accepted) {
          copy.pendingUnload = false
          delete next[id]
          changed = true
        }
        updated[id] = copy
      }
      if (changed) { candidates = updated; unloadAt = next; syncLoaderModel() }
      for (var pending in next) { unloadTimer.restart(); break }
    }
  }

  // --- loading each integration once ------------------------------------------

  ListModel { id: loaderModel }

  // Updated in place: a Repeater over a model that is replaced wholesale
  // rebuilds every delegate, which would reload integrations that didn't change.
  function syncLoaderModel() {
    var wanted = ({})
    for (var id in candidates) {
      var scan = candidates[id].scan
      if (!scan || !scan.entry) continue
      if (!Platform.gate(candidates[id])) continue
      wanted[id] = "file://" + scan.dir.replace(/\/+$/, "") + "/" + scan.entry
    }
    for (var i = loaderModel.count - 1; i >= 0; i--) {
      var row = loaderModel.get(i)
      if (wanted[row.pluginId] === undefined) loaderModel.remove(i)
      else if (row.entryUrl !== wanted[row.pluginId]) loaderModel.setProperty(i, "entryUrl", wanted[row.pluginId])
    }
    for (var id2 in wanted) {
      var found = false
      for (var j = 0; j < loaderModel.count; j++) if (loaderModel.get(j).pluginId === id2) found = true
      if (!found) loaderModel.append({ pluginId: id2, entryUrl: wanted[id2] })
    }
  }

  Item {
    width: 0
    height: 0
    visible: false

    Repeater {
      model: loaderModel

      Loader {
        id: entryLoader
        required property string pluginId
        required property string entryUrl
        asynchronous: true
        source: entryUrl

        Component.onCompleted: platform.registerLoader(pluginId, entryLoader)
        Component.onDestruction: platform.unregisterLoader(pluginId)

        onStatusChanged: {
          if (status === Loader.Error) {
            platform.noteLoadError(pluginId, sourceComponent ? String(sourceComponent.errorString()).split("\n")[0] : "couldn't load")
          }
          platform.refresh()
        }

        onLoaded: {
          if (item && "surfaceHost" in item) item.surfaceHost = platform.hostFor(pluginId)
          var counted = JSON.parse(JSON.stringify(platform.loads))
          counted[pluginId] = Number(counted[pluginId] || 0) + 1
          platform.loads = counted
          platform.refresh()
        }
      }
    }
  }

  function registerLoader(id, loader) {
    var next = ({})
    for (var key in loaders) next[key] = loaders[key]
    next[id] = loader
    loaders = next
    refresh()
  }

  function unregisterLoader(id) {
    var next = ({})
    for (var key in loaders) if (key !== id) next[key] = loaders[key]
    loaders = next
  }

  property var loadErrors: ({})
  function noteLoadError(id, message) {
    var next = JSON.parse(JSON.stringify(loadErrors))
    next[id] = message
    loadErrors = next
    if (candidates[id]) candidates[id].loadError = message
  }

  // --- what other parts of the notch ask --------------------------------------

  function accepted(id) { return candidates[id] ? candidates[id].accepted === true : false }
  function reasonFor(id) { return candidates[id] ? (candidates[id].reason || "") : "unknown" }
  function reasonDetailFor(id) { return candidates[id] ? (candidates[id].detail || "") : "" }

  // The panel Component, read from the Loader's item only -- never from
  // acceptance, so it keeps answering while a closing panel fades out.
  function panelFor(id) {
    var loader = loaders[id]
    if (!loader || !loader.item) return null
    return loader.item.panel || null
  }

  function itemFor(id) {
    var loader = loaders[id]
    return loader && loader.item ? loader.item : null
  }

  function hostFor(id) {
    if (hosts[id]) return hosts[id]
    var host = hostComponent.createObject(platform, { pluginId: id, bar: platform.bar, platform: platform })
    var next = ({})
    for (var key in hosts) next[key] = hosts[key]
    next[id] = host
    hosts = next
    return host
  }

  Component { id: hostComponent; NotchHost {} }

  function focusedScreen() {
    if (harnessed) {
      var forced = Quickshell.env("NOTCH_HARNESS_FOCUSED_SCREEN")
      if (forced) return forced
    }
    return bar ? bar.focusedScreenName() : ""
  }

  // --- panels ------------------------------------------------------------------

  function windowForScreen(name) {
    if (!bar) return null
    var windows = bar.notchWindows
    if (!name) return bar.focusedNotchWindow()
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].screen && windows[i].screen.name === name) return windows[i]
    }
    return null
  }

  function openPanelFor(id, route, screenName) {
    if (!accepted(id)) return "declined:not-accepted"
    if (bar && bar.barHidden) return "declined:hidden"
    if (!panelFor(id)) return "declined:no-panel"
    var window = windowForScreen(screenName || focusedScreen())
    if (!window) return "declined:no-screen"
    // One panel per plugin: the same panel open elsewhere is closed first.
    var windows = bar.notchWindows
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] !== window) windows[i].closeIntegration(id)
    }
    return window.openIntegration(id, String(route || ""))
  }

  function closePanelFor(id) {
    if (!bar) return "unknown"
    var closed = false
    var windows = bar.notchWindows
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].integrationOpen && windows[i].integrationId === id) {
        windows[i].closeIntegration(id)
        closed = true
      }
    }
    return closed ? "closed" : "unknown"
  }

  function panelOpenFor(id) {
    if (!bar) return false
    var windows = bar.notchWindows
    for (var i = 0; i < windows.length; i++) if (windows[i].integrationOpen && windows[i].integrationId === id) return true
    return false
  }

  function panelRouteFor(id) {
    if (!bar) return ""
    var windows = bar.notchWindows
    for (var i = 0; i < windows.length; i++) if (windows[i].integrationOpen && windows[i].integrationId === id) return windows[i].integrationRoute
    return ""
  }

  function panelScreenFor(id) {
    if (!bar) return ""
    var windows = bar.notchWindows
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].integrationOpen && windows[i].integrationId === id)
        return windows[i].screen ? windows[i].screen.name : ""
    }
    return ""
  }

  function panelsReport() {
    if (!bar) return []
    var out = []
    var windows = bar.notchWindows
    for (var i = 0; i < windows.length; i++) {
      out.push({ screen: windows[i].screen ? windows[i].screen.name : "", open: windows[i].integrationOpen,
                 id: windows[i].integrationId, route: windows[i].integrationRoute })
    }
    return out
  }

  // --- activities ----------------------------------------------------------------

  property var activityState: Activities.create()
  // Nothing draws activities yet (that is the activities plan), so a claim the
  // queue would show answers "queued" rather than promising a line on screen.
  readonly property bool rendered: !!bar && bar.activitiesRendered

  function claimFor(id, activity, fromIpc) {
    if (!accepted(id)) return "declined:not-accepted"
    if (bar && bar.barHidden) return "declined:hidden"
    var checked = Platform.validClaim(id, activity, fromIpc === true)
    if (!checked.ok) return "declined:" + checked.reason
    var outcome = Activities.claim(activityState, checked.claim, Date.now())
    activityState = outcome.state
    activityTick.restart()
    if (outcome.result === "shown" && !rendered) return "queued"
    return outcome.result
  }

  // The notch's own owners -- notifications, and its peeks later -- do not go
  // through the integration checks: there is no manifest to accept and the
  // owner is the notch itself. Everything after that is the same queue, so a
  // notification competes for the same two slots on the same rules.
  function claimInternal(owner, activity) {
    if (bar && bar.barHidden) return "declined:hidden"
    var checked = Platform.validClaim(String(owner), activity, false)
    if (!checked.ok) return "declined:" + checked.reason
    var outcome = Activities.claim(activityState, checked.claim, Date.now())
    activityState = outcome.state
    activityTick.restart()
    if (outcome.result === "shown" && !rendered) return "queued"
    return outcome.result
  }

  function releaseInternal(owner, key) { return releaseFor(String(owner), key) }

  function releaseFor(id, key) {
    var outcome = Activities.release(activityState, id, String(key || id))
    activityState = outcome.state
    return outcome.result
  }

  function releaseOwner(id) { activityState = Activities.releaseOwner(activityState, id) }

  Timer {
    id: activityTick
    interval: 250
    repeat: true
    running: platform.activityState.visible.length > 0 || platform.activityState.queued.length > 0
    onTriggered: platform.activityState = Activities.tick(platform.activityState, Date.now())
  }

  function activitiesReport() {
    var report = Activities.report(activityState)
    report.rendered = rendered
    return report
  }

  // --- the heartbeat -------------------------------------------------------------
  //
  // A plugin's service or CLI runs outside the shell and can't hold a
  // NotchHost, so it reads this file instead: is a notch there, does it accept
  // me, and which generation is it (so a reload can be noticed). It lives
  // outside the plugins folder, because a write inside one reloads every plugin.

  readonly property string stateDir: Quickshell.env("NOTCH_PLATFORM_STATE_DIR")
    || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/graveklar.notch")
  readonly property bool writesBeat: enabled
    && ((!!bar && !!bar.shell && !harnessed) || Quickshell.env("NOTCH_PLATFORM_STATE_DIR") !== "")
  readonly property string generation: String(startedAt) + "-" + String(Math.floor(Math.random() * 10000))
  readonly property real startedAt: Date.now()
  readonly property int beatMs: 2000
  readonly property int staleAfterMs: 6000

  function beatReport(alive) {
    var acceptedMap = ({})
    var declined = ({})
    for (var id in candidates) {
      if (candidates[id].accepted) acceptedMap[id] = { contract: Number(candidates[id].scan.contract || 0) }
      else declined[id] = candidates[id].reason || "unknown"
    }
    var screens = []
    if (bar) {
      var windows = bar.notchWindows
      for (var i = 0; i < windows.length; i++) if (windows[i].screen) screens.push(windows[i].screen.name)
    }
    return JSON.stringify({
      contract: contract, oldest: oldest, features: features,
      generation: generation, startedAt: startedAt, beatAt: Date.now(),
      beatMs: beatMs, staleAfterMs: staleAfterMs,
      present: alive === true, hidden: !!bar && bar.barHidden,
      screens: screens, accepted: acceptedMap, declined: declined
    })
  }

  function writeBeat() {
    if (!writesBeat) return
    beatFile.setText(beatReport(true))
  }

  FileView {
    id: beatFile
    path: platform.writesBeat ? (platform.stateDir + "/platform.json") : ""
    atomicWrites: true
  }

  // The last word, written synchronously: without it every plugin reload would
  // leave services waiting out the full staleness before drawing their own UI.
  FileView {
    id: finalFile
    path: platform.writesBeat ? (platform.stateDir + "/platform.json") : ""
    atomicWrites: true
    blockWrites: true
  }

  Timer {
    interval: platform.beatMs
    repeat: true
    running: platform.writesBeat
    onTriggered: platform.writeBeat()
  }

  // --- lifecycle -------------------------------------------------------------------

  Timer {
    id: firstScan
    interval: 300
    running: platform.enabled
    onTriggered: platform.rescan()
  }

  Timer {
    id: rescanDebounce
    interval: 500
    onTriggered: platform.rescan()
  }

  Connections {
    target: platform.bar
    enabled: platform.enabled
    // The layout changed: a plugin may have come or gone.
    function onBarConfigSerialChanged() { platform.refresh(); rescanDebounce.restart() }
    // The user switched an integration off or on: that takes effect at once,
    // with no rescan and no reload of anything still accepted.
    function onNotchDisabledIntegrationsChanged() { platform.refresh() }
  }

  Component.onDestruction: {
    platform.present = false
    if (platform.writesBeat) finalFile.setText(platform.beatReport(false))
  }

  function report() {
    return {
      enabled: enabled, contract: contract, oldest: oldest, features: features,
      pluginsDir: pluginsDir, scannedAt: scannedAt, scanning: scanning,
      screens: (function () {
        var names = []
        if (bar) { var windows = bar.notchWindows; for (var i = 0; i < windows.length; i++) if (windows[i].screen) names.push(windows[i].screen.name) }
        return names
      })(),
      focusedScreen: focusedScreen(), panels: panelsReport(), statePath: writesBeat ? (stateDir + "/platform.json") : "",
      generation: generation, list: list
    }
  }
}
