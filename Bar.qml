import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "BarModel.js" as BarModel
import "spring.js" as Spring
import "contract.js" as Contract
import "menu"
import "plugins"
import "plugins/PluginsModel.js" as PluginsModel

Item {
  id: root

  // The omarchy-shell host injects omarchyPath from OMARCHY_PATH.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Injected by the host shell so bar slots can resolve enabled widgets.
  property var barWidgetRegistry: fallbackBarWidgetRegistry
  // Read-only registry view for third-party full bars; the built-in bar does
  // not otherwise need it, but declaring it keeps clone construction atomic.
  property var pluginRegistry: null
  // Injected by the host shell every time shell.json is reloaded. Holds the
  // `bar:` subtree: position, centerAnchor, layout. The host owns file IO;
  // the bar just renders whatever it's handed. The bar font follows the
  // OS-level fontconfig monospace binding — it is not stored in shell.json.
  property var barConfig: ({})
  // Injected by the host shell. Used for shell-wide actions such as opening
  // settings and persisting inline widget state.
  property var shell: null
  // Manifest for the active bar option. Present for custom bars and useful for
  // diagnostics; the built-in bar does not otherwise need it.
  property var manifest: null
  QtObject {
    id: fallbackBarWidgetRegistry
    property var widgets: ({})
    property int revision: 0
    function metadataFor(id) { return null }
  }
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Hidden panels stay mapped but park off-screen
  // without an exclusion zone; updated by the FileView watcher further down.
  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  property string stateHome: home + "/.local/state"
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    transparent: false,
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false
  property bool centerSectionHovered: false
  // One bar surface exists per monitor and each reports into this count, so a
  // pointer crossing from one monitor's bar to another's stays counted however
  // the enter and leave interleave. A single shared bool would be left false by
  // whichever event landed last.
  property int barHoverCount: 0
  // True while the pointer is over any bar, widgets included.
  readonly property bool barHovered: barHoverCount > 0
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property int barConfigSerial: 0
  property string position: "top"
  // Resolves through fontconfig at paint time (Style.font.family defaults
  // to "monospace"), so changing the system font (via `omarchy-font-set`)
  // updates the bar without a reload.
  property string fontFamily: Style.font.family
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  property color themeForeground: Color.bar.text
  property color themeContrastForeground: Color.background
  property color transparentForeground: Color.bar.text
  // `barForeground` is what widgets paint with in the bar itself, so in the
  // notch it is the notch's readable colour (see "colours on the notch").
  // `foreground`, `background` and `urgent` are what widgets use in their own
  // pop-out panels. A panel in its own window sits on the theme's background,
  // so there they stay the theme's -- white text on a light panel reads no
  // better than dark text on a black notch. While the notch is drawing that
  // panel inside itself (PanelHosting) they are the notch's, for the same
  // reason the other way round. The flip is instant, not animated: the panel
  // is already fading in on the notch's timing, and a 420 ms crossfade from
  // the theme's text would show the wrong colour for the first frames.
  property color themeBackground: Color.bar.background
  property color themeUrgent: Color.bar.active
  property color foreground: hosting.active ? notchForeground : themeForeground
  property color barForeground: useTransparentForeground ? transparentForeground : notchForeground
  property bool foregroundAnimationEnabled: true
  property color background: hosting.active ? notchColor : themeBackground
  property color urgent: hosting.active ? notchForeground : themeUrgent

  Behavior on barForeground { enabled: root.foregroundAnimationEnabled; ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on themeBackground { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on themeUrgent { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null
  property var barDragSource: null
  property var barDragTarget: null
  property var barDragTargetGeometry: null
  property bool barDragAfter: false
  property var barDragWindow: null
  property var barDragScreen: null
  property url barDragImageUrl: ""
  property real barDragSceneX: 0
  property real barDragSceneY: 0
  property real barDragScreenX: 0
  property real barDragScreenY: 0
  property real barDragOffsetX: 0
  property real barDragOffsetY: 0
  property bool barMoveActive: false
  property string barMoveCandidate: ""
  property var barMoveWindow: null
  property var barMoveScreen: null
  property var clickTargets: []
  property var moduleSlots: []
  property var pluginBarApis: ({})
  property var pluginObjectOwners: []

  Component {
    id: pluginBarApiComponent
    PluginBarApi { }
  }

  function publicLayoutConfig() {
    return JSON.parse(JSON.stringify(root.layoutConfig || {}))
  }

  function bindPluginBarApi(api) {
    if (!api) return
    api.foreground = Qt.binding(function() { return root.foreground })
    api.barForeground = Qt.binding(function() { return root.barForeground })
    api.background = Qt.binding(function() { return root.background })
    api.urgent = Qt.binding(function() { return root.urgent })
    api.fontFamily = Qt.binding(function() { return root.fontFamily })
    api.position = Qt.binding(function() { return root.position })
    api.vertical = Qt.binding(function() { return root.vertical })
    api.barSize = Qt.binding(function() { return root.barSize })
    api.transparent = Qt.binding(function() { return root.transparent })
    api.foregroundAnimationEnabled = Qt.binding(function() { return root.foregroundAnimationEnabled })
    api.centerSectionRevealHeld = Qt.binding(function() { return root.centerSectionRevealHeld })
    api._centerHoverRevealSuppressed = Qt.binding(function() { return root.centerHoverRevealSuppressed })
    root.syncPluginBarApiObjects(api)
  }

  function syncPluginBarApiObjects(api) {
    if (!api) return
    api.activePopout = root.pluginOwnsBarObject(api.pluginId, root.activePopout)
      ? root.activePopout : (root.activePopout ? api.foreignPopoutMarker : null)
    api.clickTargets = root.pluginClickTargets(api.pluginId)
    api.layoutConfig = root.publicLayoutConfig()
  }

  function pluginObjectRecord(target) {
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var record = pluginObjectOwners[i]
      if (record && record.target === target) return record
    }
    return null
  }

  function markPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    if (!key || !target) return false
    var record = root.pluginObjectRecord(target)
    if (record && record.pluginId !== key) return false
    var next = []
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var existing = pluginObjectOwners[i]
      if (!existing || existing.target !== target) next.push(existing)
    }
    var updated = record || { target: target, pluginId: key, clickTarget: false, popout: false }
    updated[role] = true
    next.push(updated)
    pluginObjectOwners = next
    return true
  }

  function unmarkPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    var next = []
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var record = pluginObjectOwners[i]
      if (!record || record.target !== target || record.pluginId !== key) {
        next.push(record)
        continue
      }
      record[role] = false
      if (record.clickTarget || record.popout) next.push(record)
    }
    pluginObjectOwners = next
  }

  function pluginOwnsBarObject(pluginId, target) {
    var record = target ? root.pluginObjectRecord(target) : null
    return !!record && record.pluginId === String(pluginId || "")
  }

  function pluginClickTargets(pluginId) {
    var out = []
    for (var i = 0; i < root.clickTargets.length; i++) {
      var target = root.clickTargets[i]
      if (root.pluginOwnsBarObject(pluginId, target)) out.push(target)
    }
    return out
  }

  function syncAllPluginBarApiObjects() {
    for (var id in pluginBarApis) root.syncPluginBarApiObjects(pluginBarApis[id])
  }

  function registerPluginClickTarget(pluginId, target) {
    if (!root.markPluginObject(pluginId, target, "clickTarget")) return
    root.registerClickTarget(target)
  }

  function unregisterPluginClickTarget(pluginId, target) {
    if (!root.pluginOwnsBarObject(pluginId, target)) return
    root.unregisterClickTarget(target)
    root.unmarkPluginObject(pluginId, target, "clickTarget")
  }

  function requestPluginPopout(pluginId, owner) {
    if (!root.markPluginObject(pluginId, owner, "popout")) return
    root.requestPopout(owner)
  }

  function releasePluginPopout(pluginId, owner) {
    if (!root.pluginOwnsBarObject(pluginId, owner)) return
    root.releasePopout(owner)
    root.unmarkPluginObject(pluginId, owner, "popout")
  }

  function pluginBarApiFor(pluginId, moduleName, registered) {
    var key = String(pluginId || "")
    if (!key) return null

    var pluginShell = null
    if (registered && root.shell && typeof root.shell.pluginShellForId === "function") {
      // Only the trusted built-in bar receives ShellRoot and can request a
      // service-capable facade for the widget it is instantiating.
      pluginShell = root.shell.pluginShellForId(moduleName)
    } else if (root.shell && typeof root.shell.pluginShellForBarEntry === "function") {
      // Replacement bars receive a service-less entry facade. Giving an
      // untrusted bar a generic facade factory would let it retrieve another
      // third-party plugin's live service object.
      pluginShell = root.shell.pluginShellForBarEntry(key, moduleName)
    }

    if (pluginBarApis[key]) {
      pluginBarApis[key].shell = pluginShell
      return pluginBarApis[key]
    }

    var api = pluginBarApiComponent.createObject(null, {
      pluginId: key,
      moduleName: String(moduleName || ""),
      shell: pluginShell,
      _showTooltip: function(target, text) { root.showTooltip(target, text) },
      _hideTooltip: function(target) { root.hideTooltip(target) },
      _registerClickTarget: function(target) { root.registerPluginClickTarget(key, target) },
      _unregisterClickTarget: function(target) { root.unregisterPluginClickTarget(key, target) },
      _requestPopout: function(owner) { root.requestPluginPopout(key, owner) },
      _releasePopout: function(owner) { root.releasePluginPopout(key, owner) },
      _switchPanelFrom: function(owner, direction) { return root.switchPanelFrom(owner, direction) },
      _targetBelongsToWindow: function(target, window) { return root.targetBelongsToWindow(target, window) },
      _moduleWidgets: function(requestedId) {
        return String(requestedId || "") === String(moduleName || "")
          ? root.moduleWidgets(moduleName) : []
      },
      _run: function(command) { root.run(command) },
      _setCenterHoverRevealSuppressed: function(value) {
        root.centerHoverRevealSuppressed = !!value
      }
    })
    if (!api) return null
    root.bindPluginBarApi(api)

    var next = ({})
    for (var id in pluginBarApis) next[id] = pluginBarApis[id]
    next[key] = api
    pluginBarApis = next
    return api
  }

  function pluginBarApiUsed(pluginId) {
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.pluginApiId === pluginId) return true
    }
    return false
  }

  function releasePluginObjects(pluginId) {
    var owned = pluginObjectOwners.slice()
    for (var i = 0; i < owned.length; i++) {
      var record = owned[i]
      if (!record || record.pluginId !== pluginId) continue
      if (record.clickTarget) root.unregisterClickTarget(record.target)
      if (record.popout && root.activePopout === record.target) root.releasePopout(record.target)
    }
    pluginObjectOwners = pluginObjectOwners.filter(function(record) {
      return record && record.pluginId !== pluginId
    })
  }

  function prunePluginBarApis() {
    var next = ({})
    for (var id in pluginBarApis) {
      var api = pluginBarApis[id]
      if (root.pluginBarApiUsed(id)) {
        next[id] = api
        continue
      }
      root.releasePluginObjects(id)
      if (api && typeof api.destroy === "function") api.destroy()
    }
    pluginBarApis = next
  }

  onActivePopoutChanged: syncAllPluginBarApiObjects()
  onClickTargetsChanged: syncAllPluginBarApiObjects()
  onLayoutConfigChanged: syncAllPluginBarApiObjects()
  onModuleSlotsChanged: Qt.callLater(prunePluginBarApis)

  Component.onDestruction: {
    for (var id in pluginBarApis) {
      root.releasePluginObjects(id)
      if (pluginBarApis[id] && typeof pluginBarApis[id].destroy === "function")
        pluginBarApis[id].destroy()
    }
    pluginBarApis = ({})
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    var next = moduleSlots.filter(function(item) { return item !== slot })
    moduleSlots = next
  }

  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: slot.x, y: slot.y }
      try {
        point = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }
      out.push({
        id: slot.moduleName,
        section: slot.region,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function slotWindow(slot) {
    if (!slot) return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function clearBarDrag() {
    barDragSource = null
    barDragWindow = null
    barDragScreen = null
    barDragImageUrl = ""
    barDragTarget = null
    barDragTargetGeometry = null
    barDragAfter = false
    barDragSceneX = 0
    barDragSceneY = 0
    barDragScreenX = 0
    barDragScreenY = 0
    barDragOffsetX = 0
    barDragOffsetY = 0
  }

  function windowScreenPoint(scenePoint, window) {
    var x = scenePoint ? scenePoint.x : 0
    var y = scenePoint ? scenePoint.y : 0
    if (!window || !window.screen) return { x: x, y: y }

    if (root.position === "bottom")
      y += Math.max(0, window.screen.height - window.height)
    else if (root.position === "right")
      x += Math.max(0, window.screen.width - window.width)

    return { x: x, y: y }
  }

  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  function dropMarkerRect(slot, after) {
    if (!slot) return null

    try {
      var slotPoint = slot.mapToItem(null, 0, 0)
      var screenPoint = barDragScreenPoint(slotPoint)
      var thickness = Style.spacing.xs
      if (vertical) {
        return {
          x: screenPoint.x,
          y: screenPoint.y + (after ? slot.height : 0) - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }

      return {
        x: screenPoint.x + (after ? slot.width : 0) - thickness / 2,
        y: screenPoint.y,
        width: thickness,
        height: slot.height
      }
    } catch (e) {
      return null
    }
  }

  // Split the screen along its diagonals (in normalized space, so widescreens
  // don't bias toward left/right): whichever triangle holds the cursor names
  // the candidate edge.
  function nearestScreenEdge(point, screen) {
    var nx = screen.width > 0 ? Util.clamp(point.x / screen.width, 0, 1) : 0.5
    var ny = screen.height > 0 ? Util.clamp(point.y / screen.height, 0, 1) : 0.5

    var edge = "top"
    var best = ny
    if (1 - ny < best) { edge = "bottom"; best = 1 - ny }
    if (nx < best) { edge = "left"; best = nx }
    if (1 - nx < best) { edge = "right"; best = 1 - nx }
    return edge
  }

  // The notch cannot move to another edge.
  function beginBarMove(window) {
  }

  function updateBarMove(screenPoint) {
    if (!barMoveActive || !barMoveScreen) return
    barMoveCandidate = nearestScreenEdge(screenPoint, barMoveScreen)
  }

  function clearBarMove() {
    barMoveActive = false
    barMoveCandidate = ""
    barMoveWindow = null
    barMoveScreen = null
  }

  function finishBarMove() {
    var edge = barMoveCandidate
    if (!barMoveActive || !edge || edge === position) {
      clearBarMove()
      return
    }

    clearBarMove()
    setBarPosition(edge)
  }

  function setBarPosition(value) {
    var next = normalizePosition(value)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.position = next
      })
    } else {
      root.position = next
    }
  }

  function captureBarDragGhost(slot) {
    var item = slot && slot.activeItem ? slot.activeItem : null
    barDragImageUrl = ""
    if (!item || typeof item.grabToImage !== "function") return

    var grabWidth = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
    var grabHeight = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
    item.grabToImage(function(result) {
      if (root.barDragSource !== slot || !result || !result.url) return
      root.barDragImageUrl = result.url
    }, Qt.size(grabWidth, grabHeight))
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  function normalizePosition(value) {
    return BarModel.normalizePosition(value)
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and scriptable config helpers can't drift on entry shape.
  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right")
    }
  }

  // The tray drawer reveals inward (away from the bar edge). Place it at the
  // section's inner edge: start of the right section, end of the left/center
  // sections. The drawer's reserved space then sits next to the bar center,
  // not stranded mid-section.
  function pinTrayToInner(entries, section) {
    return BarModel.pinTrayToInner(entries, section)
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    // The notch only exists at the top edge, and it is never see-through.
    position = "top"
    setRequestedTransparency(false)
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")

    // layoutEntries feeds plain JS arrays to the module Repeaters, and QML
    // cannot diff those: reassigning layoutConfig rebuilds every widget on
    // every monitor. When a shell.json write only changed inline widget
    // settings, patch the live layout and running widgets in place instead.
    var next = normalizeLayout(config.layout)
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta) {
      applySettingsDelta(delta)
      return
    }
    layoutConfig = next
    barConfigSerial++
  }

  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      layoutConfig[change.region][change.index] = change.entry
      var settings = entrySettings(change.entry)
      for (var s = 0; s < moduleSlots.length; s++) {
        var slot = moduleSlots[s]
        if (!slot || slot.region !== change.region || slot.moduleName !== entryId(change.entry)) continue
        var item = slot.activeItem
        if (item && "settings" in item) item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  // Tab order for the panels in one bar region. Scoped to a single bar surface
  // so tabbing walks the bar the open panel belongs to instead of hopping the
  // panel to another monitor's copy of the same widget.
  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id) continue
        if (window && !sameWindow(slotWindow(slot), window)) continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  // The Nth panel in a bar region, counted the way the bar reads: layout order,
  // and only the panels actually on screen. A widget with no panel (the tray)
  // and one that is hiding itself are passed over, so the number lands on the
  // Nth panel icon the user can see rather than the Nth layout entry.
  // One-based, because it exists for hotkeys; anything else lands on no slot.
  //
  // Counting any bar surface is enough: every monitor lays its bar out from the
  // one layout, and summoning the id routes through pickPanelSlot, which opens
  // the focused monitor's copy whichever surface was counted.
  function panelWidgetIdAt(region, index) {
    var slots = panelNavigationSlots(String(region || ""), null)
    var slot = slots[Math.round(Number(index)) - 1]
    return slot ? String(slot.moduleName || "") : ""
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false

    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) {
        currentSlot = slot
        break
      }
    }
    if (!currentSlot) return false

    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2) return false

    var currentIndex = -1
    for (var j = 0; j < slots.length; j++) {
      if (slots[j] === currentSlot) {
        currentIndex = j
        break
      }
    }
    if (currentIndex < 0) return false

    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner) return false

    nextSlot.activeItem.open()
    return true
  }

  // Every live instance of a widget id. A bar surface is built per monitor, so
  // a widget that appears once in the layout is still live once per screen.
  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      items.push(slot.activeItem)
    }
    return items
  }

  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  // The output Hyprland has focused, which is where a keyboard-summoned panel
  // belongs. Empty until Hyprland reports one, which leaves panel routing on
  // its per-monitor fallback rather than guessing at an output.
  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  // Resolve the live bar-widget instance for a plugin id (e.g. "omarchy.bluetooth").
  // Only widgets that expose popup open/close methods count; plain indicators
  // (clock, workspaces, tray) return null. Used by shell.summon/toggle so
  // panel hotkeys route through the bar instead of a per-target IPC handler
  // that only reaches whichever per-monitor instance claimed the target.
  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    // One copy per monitor, plus a zero-size placeholder for anchored center
    // modules. See BarModel.pickPanelSlot for which one a hotkey acts on.
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.open !== "function") return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.close !== "function") return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function entrySettings(entry) {
    return BarModel.entrySettings(entry)
  }

  function entryId(entry) {
    return BarModel.entryId(entry)
  }

  function moduleString(entry, key, fallback) {
    return BarModel.moduleString(entry, key, fallback)
  }

  function entryIndex(entries, name) {
    return BarModel.entryIndex(entries, name)
  }

  function entriesBefore(entries, name) {
    return BarModel.entriesBefore(entries, name)
  }

  function entriesAfter(entries, name) {
    return BarModel.entriesAfter(entries, name)
  }

  function canonicalWidgetId(name) {
    return Util.canonicalWidgetId(name)
  }

  // Enabling the menu companion swaps omarchy.menu's button in the layout for
  // the companion's identical one, so settings that name one id keep working
  // when only the other is registered. Nothing is written to the config.
  function menuAliasId(id) {
    var widgets = (barWidgetRegistry && barWidgetRegistry.widgets) || {}
    if (id === "omarchy.menu" && !widgets["omarchy.menu"] && widgets["graveklar.notch-menu"]) return "graveklar.notch-menu"
    if (id === "graveklar.notch-menu" && !widgets["graveklar.notch-menu"] && widgets["omarchy.menu"]) return "omarchy.menu"
    return id
  }

  function expandPath(path) {
    return BarModel.expandPath(path, home)
  }

  function customModuleSafeName(name) {
    return BarModel.customModuleSafeName(name)
  }

  function customModuleType(entry) {
    return BarModel.customModuleType(entry)
  }

  function customModuleSource(entry) {
    var source = BarModel.customModulePath(entry, home, omarchyConfigDir)
    return source ? Util.fileUrl(source) : ""
  }

  Component.onCompleted: {
    applyBarConfig()
    Qt.callLater(applyKeybinds)
    previousBatteryMode = batteryMode
  }

  // Revealing the indicators widens their section, which can slide a neighbour
  // under a stationary pointer. Collapsing on that un-hover would move it back
  // out and re-open the peek, so hold until the pointer leaves the bar.
  function setCenterSectionHovered(hovered) {
    centerSectionHovered = hovered
    if (hovered) {
      centerSectionRevealTimer.stop()
      centerSectionRevealHeld = true
    } else {
      centerSectionRevealTimer.restart()
    }
  }

  function setBarHovered(hovered) {
    barHoverCount = Math.max(0, barHoverCount + (hovered ? 1 : -1))
    if (barHoverCount === 0) centerSectionRevealTimer.restart()
  }

  function setCenterHoverRevealSuppressed(value) {
    centerHoverRevealSuppressed = !!value
  }

  Timer {
    id: centerSectionRevealTimer
    interval: 120
    // Collapse only. Opening the peek is the center section's own gesture, done
    // in setCenterSectionHovered, so a timer left pending by a pointer that dipped
    // off the bar and came back cannot reveal indicators it never pointed at.
    onTriggered: if (!root.centerSectionHovered && !root.barHovered) root.centerSectionRevealHeld = false
  }

  function run(command) {
    if (!command) return

    Util.execDetached(command)
  }

  function toggleTransparency() {
    var nextTransparent = !(root.requestedTransparent === true)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.transparent = nextTransparent
      })
    } else {
      root.setRequestedTransparency(nextTransparent)
    }
  }

  function rawLayoutSection(config, region) {
    if (!Util.isPlainObject(config.bar)) config.bar = {}
    if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
    if (!Array.isArray(config.bar.layout[region])) config.bar.layout[region] = []

    return config.bar.layout[region]
  }

  function rawEntryIndex(entries, name) {
    for (var i = 0; i < entries.length; i++) {
      if (root.entryId(entries[i]) === name) return i
    }

    return -1
  }

  function moveModuleInConfig(config, fromRegion, fromName, toRegion, beforeName) {
    var fromEntries = rawLayoutSection(config, fromRegion)
    var toEntries = rawLayoutSection(config, toRegion)
    var fromIndex = rawEntryIndex(fromEntries, fromName)
    if (fromIndex < 0) return false

    var toIndex = beforeName ? rawEntryIndex(toEntries, beforeName) : toEntries.length
    if (toIndex < 0) toIndex = toEntries.length

    if (fromRegion === toRegion && fromIndex === toIndex) return false

    var movedEntry = fromEntries[fromIndex]
    fromEntries.splice(fromIndex, 1)

    if (fromRegion === toRegion && fromIndex < toIndex) toIndex -= 1
    if (toIndex < 0) toIndex = 0
    if (toIndex > toEntries.length) toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }

    toEntries.splice(toIndex, 0, movedEntry)
    return true
  }

  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion) return false
    if (source.region === toRegion && source.moduleName === beforeName) return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      changed = moveModuleInConfig(config, source.region, source.moduleName, toRegion, beforeName)
    })
    return changed
  }

  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    if (sourceWindow && sourceWindow.contentItem) {
      var barPoint = sourceWindow.contentItem.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (barPoint.x < 0 || barPoint.x > sourceWindow.contentItem.width ||
          barPoint.y < 0 || barPoint.y > sourceWindow.contentItem.height)
        return null
    }

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue

      var slotPoint = { x: slot.x, y: slot.y }
      try {
        slotPoint = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }

      candidates.push({
        slot: slot,
        x: slotPoint.x,
        y: slotPoint.y,
        width: slot.width,
        height: slot.height
      })
    }

    return BarModel.nearestDropTarget(candidates, scenePoint, root.vertical)
  }

  function visibleModuleSlot(region, name, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name ||
          !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue
      return slot
    }

    return null
  }

  function nextVisibleModuleName(region, afterName, sourceSlot) {
    var entries = layoutEntries(region)
    var found = false
    for (var i = 0; i < entries.length; i++) {
      var name = entryId(entries[i])
      if (!found) {
        found = name === afterName
        continue
      }

      if (visibleModuleSlot(region, name, sourceSlot)) return name
    }

    return ""
  }

  function dropBarModuleAtTarget(sourceSlot, targetSlot, afterTarget) {
    if (!sourceSlot || !targetSlot) return false

    var beforeName = afterTarget ? nextVisibleModuleName(targetSlot.region, targetSlot.moduleName, sourceSlot) : targetSlot.moduleName
    return dropBarModule(sourceSlot, targetSlot.region, beforeName)
  }

  function moduleTargetClickable(target) {
    return target
      && target.visible !== false
      && target.opacity !== 0
      && target.interactive !== false
      && target.pressable !== false
      && target.concealed !== true
      && typeof target.triggerPress === "function"
  }

  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue

      var targetPoint = { x: localX, y: localY }
      try {
        targetPoint = slot.mapToItem(target, localX, localY)
      } catch (e) {
        continue
      }

      if (targetPoint.x >= 0 && targetPoint.x <= target.width &&
          targetPoint.y >= 0 && targetPoint.y <= target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem)) return slot.activeItem
    return null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false

    target.triggerPress(button)
    return true
  }

  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string") c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  function setRequestedTransparency(value) {
    var nextTransparent = value === true
    requestedTransparent = nextTransparent
    if (!nextTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      restoreForegroundAnimation()
      return
    }
    scheduleTransparentForegroundRefresh()
  }

  function restoreForegroundAnimation() {
    Qt.callLater(function() {
      Qt.callLater(function() { root.foregroundAnimationEnabled = true })
    })
  }

  function scheduleTransparentForegroundRefresh() {
    if (!requestedTransparent) {
      transparentForeground = themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!requestedTransparent || transparentForegroundProc.running) return

    transparentForegroundProc.command = [
      "omarchy-bar-text-color",
      root.position,
      String(root.barSize),
      colorHex(root.themeForeground),
      colorHex(root.themeContrastForeground)
    ]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: scheduleTransparentForegroundRefresh()
  onPositionChanged: scheduleTransparentForegroundRefresh()
  onThemeForegroundChanged: scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value)) return

        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: root.stateHome + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return

    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  // Presence of the `bar-off` flag = bar hidden. Watching the parent toggles
  // directory because FileView can't observe a file that doesn't exist yet,
  // and the flag is created/removed by `omarchy-toggle-bar`.
  //
  // The flag belongs to the bar Omarchy's shell is hosting. A notch running
  // anywhere else (a test harness) ignores it, as it ignores keybinds, unless
  // NOTCH_HONOR_BAR_OFF=1. The host sets `shell` after creating the bar, so the
  // probe runs again when it arrives.
  readonly property bool hostedBar: (!!root.shell && !root.harnessed) || Quickshell.env("NOTCH_HONOR_BAR_OFF") === "1"
  onShellChanged: barHiddenProbe.running = true
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = root.hostedBar && String(line).trim() === "yes" } }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  // The directory watch can permanently stop delivering events after flag
  // changes land in quick succession, stranding the bar off screen until the
  // shell restarts. `omarchy-toggle-bar` nudges this after flipping the flag
  // so the probe re-reads it even when the watch has gone quiet.
  IpcHandler {
    target: "omarchy.bar"

    // Start rather than restart: a probe already in flight was launched by the
    // directory watch after the flag flipped, so its answer is current, and
    // killing it here can swallow the result entirely.
    function syncHidden(): void {
      barHiddenProbe.running = true
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData

        screen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      DragGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  // ---------------------------------------------------------------------------
  // The notch
  // ---------------------------------------------------------------------------
  //
  // Settings live under `bar.notch` in shell.json; every key is optional.
  //
  //   compact        glance items shown in the resting notch: "clock", "date",
  //                  "media". Empty by default, which keeps the notch pitch black.
  //   expanded       glance items shown in the open notch's row (default
  //                  ["clock", "date", "media"], or ["media"] when the layout
  //                  already has an omarchy.clock widget)
  //   openWith       what opens the notch's widgets: any of "hover", "click",
  //                  "doubleClick", "longPress", "rightClick", "middleClick",
  //                  "scroll" (default ["hover", "click"])
  //   openKey        a Hyprland key combination that toggles the widgets, e.g.
  //                  "SUPER + N" (default none)
  //   settingsWith   what opens the settings panel, from the same list plus
  //                  "longRightClick" (default ["longRightClick"])
  //   settingsKey    a key combination that toggles the settings (default none)
  //   menuWith       what opens the Omarchy menu inside the notch: any of "click",
  //                  "doubleClick", "longPress", "rightClick", "longRightClick",
  //                  "middleClick" (default none). Settings win a trigger both
  //                  claim, then the menu, then openWith.
  //   menuKey        a key combination that toggles the menu (default none)
  //   autoHideKey    a key combination that toggles autoHide (default none)
  //   stayOpen       true: the notch stays open on its open view (openAction, or
  //                  the widgets when that is a panel), whatever the pointer
  //                  does; the settings and the menu still open over it (default false)
  //   stayOpenKey    a key combination that toggles stayOpen (default none)
  //   color          notch colour (default "#000000")
  //   foreground     text colour (default: the theme's bar text)
  //   compactWidth   resting width in logical px (default 180)
  //   compactHeight  resting height, and the space reserved for windows (default 32)
  //   bottomRadius   convex bottom-corner radius (default 10)
  //   filletRadius   concave fillet radius where the notch meets the screen edge (default 10)
  //   hoverDelay / collapseDelay   ms (default 60 / 350)
  //   peekOnTrackChange  briefly widen to show a new track (default true)
  //   peekDuration   ms (default 3500)
  //   batteryGlow    the charging glow (default true)
  //   glowScale      how far the glow reaches, relative to the resting notch's
  //                  size: scale × √(width × height) × 32/√(180×32), so 32 px
  //                  for the default notch at 1.0 (0–2.5, never past 80 px;
  //                  0 draws no glow at all)
  //   glowStyle      "outline" (default) or "bottom": a subtler glow only
  //                  under the bottom edge, strongest in the middle
  //   hoverItems     what hovering shows when "hover" is not in openWith: any of
  //                  "clock", "date", "media", "battery" (default none) ...
  //   hoverPlugins   ... together with any bar widgets, by id (default none).
  //                  With both empty, hovering does nothing; with "hover" in
  //                  openWith, hovering opens the notch (openAction) instead.
  //   openAction     what every other trigger (click, keybind, …) opens:
  //                  "widgets", "clock", "battery", "plugin", "settings" or
  //                  "menu" (default "widgets")
  //   openPlugin     the bar widget id shown when openAction is "plugin"
  //   hiddenPlugins  bar widget ids left out of the open notch's widget row
  //                  (they stay loaded, and can still be a hover/open plugin)
  //   chargingColor / fullColor / lowColor   (default #FFB340 / #30D158 / #FF453A)
  //   lowBattery / criticalBattery   percent thresholds (default 20 / 10)
  //   greenAbove     charging at or above this percent shows the full colour
  //                  (default 100: only when full)
  //   batteryPeek    widen to show the charge when plugged in or running low (default true)
  //   autoHide       true: the resting notch hides in the screen edge until the
  //                  pointer reaches the top edge above it (default false).
  //   windowsToTop   false: windows stay below the resting notch. true: windows
  //                  go all the way to the top edge, under the notch. Defaults
  //                  to autoHide's value, so an auto-hiding notch lets windows
  //                  use the full height unless this is set to false. Either
  //                  way the space kept clear never changes while the notch
  //                  opens, peeks, hides or reveals.
  //                  Toggle with `quickshell ipc -p $OMARCHY_PATH/shell call notch windowsToTop toggle`.

  readonly property var notchConfig: Util.isPlainObject(barConfig) && Util.isPlainObject(barConfig.notch) ? barConfig.notch : ({})

  function notchSetting(key, fallback) {
    var value = notchConfig[key]
    return value === undefined || value === null || value === "" ? fallback : value
  }

  function notchNumber(key, fallback) {
    var n = Number(notchSetting(key, fallback))
    return isFinite(n) ? n : fallback
  }

  function notchItems(key, fallback) {
    var value = notchConfig[key]
    return Array.isArray(value) ? value.map(function(v) { return String(v) }) : fallback
  }

  readonly property var notchCompactItems: notchItems("compact", [])
  // Older configs said `hoverAction` ("clock", "battery", "plugin" with
  // `hoverPlugin`); read them as the equivalent items and plugins.
  readonly property string legacyHoverAction: String(notchSetting("hoverAction", ""))
  readonly property var notchHoverItems: notchItems("hoverItems",
      legacyHoverAction === "clock" ? ["clock", "date"] : legacyHoverAction === "battery" ? ["battery"] : [])
    .filter(function(i) { return ["clock", "date", "media", "battery"].indexOf(i) !== -1 })
  readonly property var notchHoverPlugins: notchItems("hoverPlugins",
      legacyHoverAction === "plugin" && notchSetting("hoverPlugin", "") ? [String(notchSetting("hoverPlugin", ""))] : [])
    .map(function(id) { return menuAliasId(canonicalWidgetId(id)) })
  readonly property bool notchHoverShowsSomething: notchHoverItems.length > 0 || notchHoverPlugins.length > 0
  readonly property string notchOpenAction: {
    var v = String(notchSetting("openAction", "widgets"))
    return ["widgets", "clock", "battery", "plugin", "settings", "menu"].indexOf(v) === -1 ? "widgets" : v
  }
  readonly property string notchOpenPlugin: menuAliasId(canonicalWidgetId(String(notchSetting("openPlugin", ""))))
  // The hide list as configured (widget ids, unchanged format)...
  readonly property var notchHiddenPlugins: notchItems("hiddenPlugins", []).map(function(id) { return menuAliasId(canonicalWidgetId(id)) })
  // ...and what it actually hides: plugins declaring hideable: false stay.
  // Integrations the user has switched off in Settings → Integrations.
  readonly property var notchDisabledIntegrations: notchItems("disabledIntegrations", [])
  // Widgets whose own pop-out panel opens inside the notch instead of in a
  // window of its own. Empty by default: nothing changes until it is asked for.
  readonly property var notchHostedPanels: notchItems("hostedPanels", []).map(function (id) { return canonicalWidgetId(id) })
  function hostsPanelOf(name) { return notchHostedPanels.indexOf(canonicalWidgetId(name)) !== -1 }
  readonly property var notchEffectiveHidden: Contract.effectiveHidden(notchHiddenPlugins, notchPlugins.byId)

  // --- the plugin contract (contract.js) --------------------------------------
  //
  // One registry of everything the notch can show: its built-ins under
  // reserved "notch." ids, then every widget in the bar layout, in layout
  // order, described by the adapter -- defaults, overridden by the widget's
  // own `notch` property when it has one. Pickers, the hide list and the
  // expanded-view host all read this; nothing reaches a widget another way.
  readonly property var notchPlugins: {
    var serial = barConfigSerial
    var registry = barWidgetRegistry.widgets
    var declared = {}
    var slots = root.moduleSlots
    for (var s = 0; s < slots.length; s++) {
      var slot = slots[s]
      var item = slot ? slot.activeItem : null
      var notch = item && ("notch" in item) ? item.notch : null
      var sid = slot ? canonicalWidgetId(slot.moduleName) : ""
      if (sid && notch && typeof notch === "object" && !declared[sid]) declared[sid] = notch
    }
    var list = [], byId = {}
    for (var b = 0; b < Contract.BUILTINS.length; b++) {
      var bd = Contract.builtin(Contract.BUILTINS[b], notchCompactHeight)
      list.push(bd); byId[bd.id] = bd
    }
    var regions = ["left", "center", "right"]
    for (var r = 0; r < regions.length; r++) {
      var entries = layoutEntries(regions[r])
      for (var i = 0; i < entries.length; i++) {
        var id = canonicalWidgetId(entryId(entries[i]))
        if (!id || byId[id]) continue
        var meta = barWidgetRegistry.metadataFor(id)
        var wd = Contract.widget(id, meta && meta.displayName ? String(meta.displayName) : id, declared[id] || null, notchCompactHeight)
        list.push(wd); byId[id] = wd
      }
    }
    return { list: list, byId: byId }
  }

  // Every widget in the bar layout, for the settings' plugin pickers: the
  // registry's widget plugins, in layout order.
  function layoutPluginChoices() {
    return notchPlugins.list
      .filter(function(p) { return p.kind === "widget" })
      .map(function(p) { return { value: p.id, label: p.label } })
  }
  // By default the open notch's top row shows time, date and media -- minus
  // time and date when the layout already has a clock widget in the row below.
  readonly property bool layoutHasClock: {
    var serial = barConfigSerial
    var regions = ["left", "center", "right"]
    for (var i = 0; i < regions.length; i++) {
      var entries = layoutEntries(regions[i])
      for (var j = 0; j < entries.length; j++)
        if (canonicalWidgetId(entryId(entries[j])) === "omarchy.clock") return true
    }
    return false
  }
  readonly property var notchExpandedItems: notchItems("expanded", layoutHasClock ? ["media"] : ["clock", "date", "media"])
  readonly property var notchTriggerNames: ["hover", "click", "doubleClick", "longPress", "rightClick", "longRightClick", "middleClick", "scroll"]
  function notchTriggers(key, fallback) {
    var list = notchItems(key, fallback).filter(function(t) { return notchTriggerNames.indexOf(t) !== -1 })
    return list
  }
  // Settings win a trigger more than one list claims, then the menu, then
  // opening the notch; the settings panel does not let that happen.
  readonly property var notchSettingsWith: notchTriggers("settingsWith", ["longRightClick"])
  // Hover and scroll never open the menu: it takes the keyboard.
  readonly property var notchMenuWith: notchTriggers("menuWith", [])
    .filter(function(t) { return t !== "hover" && t !== "scroll" && notchSettingsWith.indexOf(t) === -1 })
  readonly property var notchOpenWith: notchTriggers("openWith",
      notchSetting("expandOn", "") === "click" ? ["click"] : ["hover", "click"])
    .filter(function(t) { return notchSettingsWith.indexOf(t) === -1 && notchMenuWith.indexOf(t) === -1 })
  function opensWith(trigger) { return notchOpenWith.indexOf(trigger) !== -1 }
  function settingsWith(trigger) { return notchSettingsWith.indexOf(trigger) !== -1 }
  function menuWith(trigger) { return notchMenuWith.indexOf(trigger) !== -1 }
  readonly property string notchOpenKey: cleanKey(notchSetting("openKey", ""))
  readonly property string notchSettingsKey: cleanKey(notchSetting("settingsKey", ""))
  readonly property string notchMenuKey: cleanKey(notchSetting("menuKey", ""))
  readonly property string notchAutoHideKey: cleanKey(notchSetting("autoHideKey", ""))
  readonly property string notchStayOpenKey: cleanKey(notchSetting("stayOpenKey", ""))

  // A Hyprland key combination: modifiers and a key joined by "+", letters,
  // digits and underscores only, so it can be quoted into a Lua call safely.
  function cleanKey(value) {
    var parts = String(value || "").split("+").map(function(p) { return p.trim().toUpperCase() }).filter(function(p) { return p !== "" })
    for (var i = 0; i < parts.length; i++) if (!/^[A-Z0-9_]+$/.test(parts[i])) return ""
    return parts.join(" + ")
  }

  // Keybinds are added to the running Hyprland with `hyprctl eval`; nothing is
  // written to its config. Hyprland keeps runtime binds across a shell
  // restart and a new shell can't know what an earlier one bound, so every
  // apply hands bin/notch-keybinds the wanted binds and it reconciles them
  // against Hyprland's own list: present once is left alone, missing is
  // added, duplicates and stale notch binds are removed -- only on keys where
  // every bind is a notch bind. Config reloads clear runtime binds; the apply
  // after `configreloaded` adds them back. NOTCH_NO_KEYBINDS=1 turns it off
  // (test harnesses).
  property var appliedKeys: ({ open: "", settings: "", autoHide: "", menu: "", stayOpen: "" })
  readonly property string keyState: notchOpenKey + "|" + notchSettingsKey + "|" + notchAutoHideKey + "|" + notchMenuKey + "|" + notchStayOpenKey
  // Only the notch Omarchy's shell is hosting touches Hyprland's binds. A notch
  // running anywhere else (a test harness) would otherwise reconcile the live
  // notch's binds away; NOTCH_FORCE_KEYBINDS=1 lets a keybind test opt in.
  readonly property bool keybindsDisabled: Quickshell.env("NOTCH_NO_KEYBINDS") === "1"
    || ((!root.shell || root.harnessed) && Quickshell.env("NOTCH_FORCE_KEYBINDS") !== "1")
  // NOTCH_HARNESS=1: a test harness, even one that hands the bar a fake shell
  // facade. Treated as unhosted for keybinds and the bar-off flag.
  readonly property bool harnessed: Quickshell.env("NOTCH_HARNESS") === "1"
  // Appended to every keybind description. Test harnesses set it, so a test
  // notch's binds are distinct and its reconcile can never touch the live
  // notch's binds (which it would otherwise see as stale notch binds).
  readonly property string keybindTag: Quickshell.env("NOTCH_KEYBIND_TAG") || ""
  readonly property var keybindActions: ({
    open: { method: "toggle", description: "Open the notch" + keybindTag },
    settings: { method: "settings", description: "Notch settings" + keybindTag },
    autoHide: { method: "autoHide toggle", description: "Toggle notch auto-hide" + keybindTag },
    menu: { method: "menu root", description: "Notch menu" + keybindTag },
    stayOpen: { method: "stayOpen toggle", description: "Keep the notch open" + keybindTag }
  })
  onKeyStateChanged: Qt.callLater(applyKeybinds)
  // Keybinds are skipped until the host has set `shell` (see keybindsDisabled);
  // apply as soon as that changes.
  onKeybindsDisabledChanged: if (!keybindsDisabled) Qt.callLater(applyKeybinds)
  function keybindLua(key, method, description) {
    return 'hl.bind("' + key + '", hl.dsp.exec_cmd("omarchy-shell -q notch ' + method + '"), { description = "' + description + '" })'
  }
  property bool keybindRerun: false
  function applyKeybinds() {
    if (keybindsDisabled) return
    var wanted = { open: notchOpenKey, settings: notchSettingsKey, autoHide: notchAutoHideKey, menu: notchMenuKey, stayOpen: notchStayOpenKey }
    var names = ["open", "settings", "autoHide", "menu", "stayOpen"]
    var list = []
    for (var i = 0; i < names.length; i++) {
      var n = names[i]
      if (!wanted[n]) continue
      list.push({ description: keybindActions[n].description, combo: wanted[n],
                  lua: keybindLua(wanted[n], keybindActions[n].method, keybindActions[n].description) })
    }
    appliedKeys = wanted
    var script = String(Qt.resolvedUrl("bin/notch-keybinds")).replace(/^file:\/\//, "")
    keybindProcess.command = [script, JSON.stringify(list), JSON.stringify(names.map(function(n) { return keybindActions[n].description }))]
    if (keybindProcess.running) keybindRerun = true
    else keybindProcess.running = true
  }
  // The last Lua sent to Hyprland for keybinds, for the IPC report: Hyprland
  // itself only reports a bind's action as a function reference.
  property string lastKeybindLua: ""
  Process {
    id: keybindProcess
    stdout: StdioCollector { onStreamFinished: root.lastKeybindLua = text.trim() }
    onRunningChanged: if (!running && root.keybindRerun) { root.keybindRerun = false; running = true }
  }
  readonly property color notchColor: notchSetting("color", "#000000")
  readonly property color notchForeground: notchSetting("foreground", notchText)

  // --- colours on the notch ----------------------------------------------------
  //
  // The notch is black whatever the theme, so text on it doesn't take the
  // theme's colours: it is Apple white (#FFFFFF, secondary text #EBEBF5 at
  // 60 %) on a dark notch, and Apple black (#000000, secondary #3C3C43 at
  // 60 %) on a light one -- whichever reads better on the notch colour. A
  // `foreground` setting still wins. The accent is the theme's when it reaches
  // 3:1 on the notch (it marks, it isn't read), otherwise the text colour.
  function luminance(value) {
    var c = Qt.tint(value, "transparent")   // a color from a color or a "#rrggbb" string
    function channel(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
  }
  function contrast(a, b) {
    var la = luminance(a), lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }
  function readableOn(background, candidates, minimum) {
    for (var i = 0; i < candidates.length; i++) {
      if (candidates[i] === undefined || candidates[i] === null) continue
      var c = Qt.tint(candidates[i], "transparent")
      if (contrast(c, background) >= minimum) return Qt.rgba(c.r, c.g, c.b, 1)
    }
    // None reads well enough: white or black, whichever reads better (on a
    // mid-tone notch neither may reach the minimum).
    return contrast("#ffffff", background) >= contrast("#000000", background) ? "#ffffff" : "#000000"
  }
  // A translucent tint (a selection fill) that disappears on this background
  // is replaced by `fallback` at 14 %.
  function visibleTint(tintValue, backgroundValue, fallbackValue) {
    var tint = Qt.tint(tintValue, "transparent"), background = Qt.tint(backgroundValue, "transparent"), fallback = Qt.tint(fallbackValue, "transparent")
    var a = tint.a
    var mixed = Qt.rgba(background.r * (1 - a) + tint.r * a, background.g * (1 - a) + tint.g * a, background.b * (1 - a) + tint.b * a, 1)
    return contrast(mixed, background) >= 1.1 ? tint : Qt.rgba(fallback.r, fallback.g, fallback.b, 0.14)
  }
  readonly property bool notchIsDark: contrast("#ffffff", notchColor) >= contrast("#000000", notchColor)
  readonly property color notchText: notchIsDark ? "#ffffff" : "#000000"
  readonly property color notchSecondaryText: notchSetting("foreground", "") !== ""
    ? Qt.rgba(notchForeground.r, notchForeground.g, notchForeground.b, 0.6)
    : notchIsDark ? Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.6) : Qt.rgba(60 / 255, 60 / 255, 67 / 255, 0.6)

  // One radius (DESIGN-PHILOSOPHY.md, 5): every button, chip, field, switch,
  // highlight, outline and tooltip in or hanging from the notch uses the
  // notch's bottom radius -- not the theme's Hyprland rounding -- capped at
  // half the item's height so a short control becomes a pill.
  readonly property real notchRadius: notchBottomRadius
  // `size` is the item's smaller side (its height, for anything wider than tall).
  function radiusFor(size) { return Math.max(0, Math.min(notchRadius, Number(size) / 2)) }
  // Every item with a radius under `item`, for dev/design.sh.
  function radiusAudit(item) {
    var out = []
    function typeOf(o) { return String(o).replace(/_QMLTYPE_\d+/, "").replace(/\(0x[0-9a-f]+.*$/, "").replace(/^QQuick/, "") }
    function walk(o, path) {
      if (!o) return
      if (o.radius !== undefined && typeof o.radius === "number") {
        var drawn = (o.color !== undefined && o.color.a > 0) || (o.border !== undefined && o.border.width > 0)
          || (o.usesOverlayBorder === true)
        out.push({ type: typeOf(o), path: path, radius: Number(o.radius.toFixed(3)), width: Number(o.width.toFixed(2)),
                   height: Number(o.height.toFixed(2)), drawn: drawn, gradient: !!o.gradient })
      }
      var kids = o.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i], path + "/" + typeOf(kids[i]))
    }
    walk(item, typeOf(item))
    return out
  }
  // The notch does not take a colour from the theme. Its text is white on the
  // black surface (`notchText`), and so is everything that marks a control as
  // selected, focused or needing attention -- the theme's accent used to come
  // through here, which put a blue switch and a blue highlight on a surface
  // whose whole point is that it is one colour and its text reads on it.
  // Selected still reads as selected: those states differ from normal by alpha,
  // not by hue (Style.selectedFillFor). A custom `foreground` setting carries
  // the accent with it, so the notch stays one palette either way.
  readonly property color notchAccent: notchForeground
  readonly property real notchCompactWidth: Math.max(0, notchNumber("compactWidth", 180))
  readonly property real notchCompactHeight: Math.max(barSize, notchNumber("compactHeight", 32))
  readonly property real notchBottomRadius: Math.max(0, notchNumber("bottomRadius", 10))
  readonly property real notchFilletRadius: Math.max(0, notchNumber("filletRadius", 10))
  readonly property int notchHoverDelay: Math.max(0, notchNumber("hoverDelay", 60))
  readonly property int notchCollapseDelay: Math.max(0, notchNumber("collapseDelay", 350))
  readonly property bool notchPeekOnTrackChange: notchSetting("peekOnTrackChange", true) !== false
  readonly property int notchPeekDuration: Math.max(500, notchNumber("peekDuration", 3500))
  readonly property bool notchAutoHide: notchSetting("autoHide", false) === true
  readonly property bool notchStayOpen: notchSetting("stayOpen", false) === true
  readonly property bool notchWindowsToTop: notchSetting("windowsToTop", notchAutoHide) === true
  // Whether windowsToTop is set, or follows autoHide (for the settings' note).
  readonly property bool notchWindowsToTopSet: notchConfig.windowsToTop === true || notchConfig.windowsToTop === false

  // --- battery ---------------------------------------------------------------

  readonly property bool notchBatteryGlow: notchSetting("batteryGlow", true) !== false
  readonly property real notchGlowScale: Math.max(0, Math.min(2.5, notchNumber("glowScale", 1)))
  // "outline" (default): the glow around the whole resting notch.
  // "bottom": a subtler glow only under its bottom edge, strongest in the middle.
  readonly property string notchGlowStyle: notchSetting("glowStyle", "outline") === "bottom" ? "bottom" : "outline"
  readonly property color notchChargingColor: notchSetting("chargingColor", "#FFB340")
  readonly property color notchFullColor: notchSetting("fullColor", "#30D158")
  readonly property color notchLowColor: notchSetting("lowColor", "#FF453A")
  readonly property int notchLowBattery: notchNumber("lowBattery", 20)
  // Charging at or above this percentage already shows the full (green)
  // colour; 100 (default) means only a full battery does.
  readonly property int notchGreenAbove: Math.max(0, Math.min(100, notchNumber("greenAbove", 100)))
  readonly property bool batteryLooksFull: batteryMode === "full"
    || (batteryMode === "charging" && batteryPercent >= notchGreenAbove)
  readonly property int notchCriticalBattery: notchNumber("criticalBattery", 10)
  readonly property bool notchBatteryPeek: notchSetting("batteryPeek", true) !== false

  // `notch simulateBattery <charging|discharging|full> <percent>` overrides the
  // real battery, to preview the glow; `auto` hands back to UPower.
  property string batterySimulatedState: ""
  property int batterySimulatedPercent: -1
  readonly property bool batterySimulated: batterySimulatedState !== ""

  readonly property var batteryDevice: UPower.displayDevice
  readonly property bool batteryPresent: batterySimulated || (!!batteryDevice && batteryDevice.isPresent)
  readonly property int batteryPercent: batterySimulated ? batterySimulatedPercent
    : batteryPresent ? Math.round(Number(batteryDevice.percentage || 0) * 100) : -1
  readonly property bool batteryCharging: batterySimulated ? batterySimulatedState === "charging"
    : batteryPresent && !UPower.onBattery
      && (batteryDevice.state === UPowerDeviceState.Charging || batteryDevice.state === UPowerDeviceState.PendingCharge)
  readonly property bool batteryFull: batterySimulated ? batterySimulatedState === "full"
    : batteryPresent && !UPower.onBattery
      && (batteryDevice.state === UPowerDeviceState.FullyCharged || batteryPercent >= 100)
  readonly property bool batteryDischarging: batterySimulated ? batterySimulatedState === "discharging"
    : batteryPresent && UPower.onBattery
  // "none" | "charging" | "full" | "low" | "critical"
  readonly property string batteryMode: !batteryPresent || batteryPercent < 0 ? "none"
    : batteryCharging ? "charging"
    : batteryDischarging && batteryPercent <= notchCriticalBattery ? "critical"
    : batteryDischarging && batteryPercent <= notchLowBattery ? "low"
    : batteryFull ? "full" : "none"

  // Which glow is on: amber while charging, green once full on the charger,
  // red when the battery is low. None on battery above the low threshold.
  readonly property string glowMode: !notchBatteryGlow ? "none"
    : batteryMode === "critical" ? "low" : batteryMode
  readonly property color glowColor: glowMode === "full" || (glowMode === "charging" && batteryLooksFull) ? notchFullColor
    : glowMode === "low" ? notchLowColor : notchChargingColor

  // The glow does not move on its own. It fades in once, 800 ms ease-out
  // (OutCubic), when it turns on, and out the same way when it turns off; a
  // colour change while it is on (charging → full) crossfades over 600 ms.
  // The three layers' blur radii and opacities live in Glow.qml.
  readonly property int glowFadeIn: 800
  readonly property int glowFadeOut: 800
  readonly property int glowCrossfade: 600

  // Hyprland animates a layer surface as it maps; the glow's window should just
  // be there. `hyprctl eval` is how this Lua-configured Hyprland takes a rule
  // at runtime, re-applied after every config reload. Nothing depends on it.
  readonly property string glowLayerRule:
    'hl.layer_rule({ match = { namespace = "omarchy-notch-glow" }, no_anim = true, animation = "none" })'

  Process {
    id: glowLayerRuleProcess
    command: ["hyprctl", "eval", root.glowLayerRule]
    running: true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") {
        glowLayerRuleProcess.running = true
        root.applyKeybinds()
        // Omarchy's Style reads Hyprland's rounding and gaps only at startup,
        // on a theme change and on the gaps toggle, so a rounding changed and
        // reset through the Hyprland config left the shell's boxes behind.
        Style.scheduleRefresh()
      }
    }
  }

  // Omarchy hands a third-party bar a snapshot of the widget catalogue. When
  // the bar is reloaded because shell.json or a plugin changed on disk, that
  // snapshot can still hold components from the previous load, which build
  // empty widgets -- catalogue entries with no component, or items with no
  // `bar` property and no width -- and those
  // stay empty until the shell restarts. A plugin rescan refreshes the
  // snapshot, so if any widget is in that state a moment after loading, ask
  // for one: at most once every 30 s, remembered across reloads, so it can
  // never loop.
  PersistentProperties {
    id: healState
    reloadableId: "graveklar-notch-widget-heal"
    property real lastRescan: 0
  }
  Timer {
    interval: 2500
    running: true
    onTriggered: root.healEmptyWidgets()
  }
  Process { id: healProcess; command: ["omarchy-shell", "-q", "shell", "rescanPlugins"] }
  // Widgets in the bar whose own pop-out panel the notch could draw inside
  // itself, and whether the user has asked it to. Read by Settings →
  // Integrations; empty until some widget in the layout has a panel.
  function hostableWidgets() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      var id = canonicalWidgetId(slot.moduleName)
      if (!hosting.hostable(slot.activeItem)) continue
      var meta = barWidgetRegistry.metadataFor(id)
      out.push({
        id: id,
        name: meta && meta.displayName ? String(meta.displayName) : id,
        hosted: hostsPanelOf(id)
      })
    }
    return out
  }


  // The live item of a widget the notch is drawing, by the name the layout
  // knows it as. Used to host that widget's own panel inside the notch.
  function widgetItemFor(name) {
    var wanted = String(name || "")
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (String(slot.moduleName) === wanted || canonicalWidgetId(slot.moduleName) === wanted) return slot.activeItem
    }
    return null
  }

  // Which widgets loaded but drew nothing. The same test healEmptyWidgets
  // uses; Setup shows what is still empty after the one heal rescan.
  function emptyWidgetIds() {
    var entries = layoutEntries("left").length + layoutEntries("center").length + layoutEntries("right").length
    if (entries === 0) return []
    // Before the heal has had its chance there is nothing to report.
    if (Date.now() - startedAt < 35000) return []
    var stale = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      var item = slot ? slot.activeItem : null
      if (!slot || slot.customType) continue
      var id = canonicalWidgetId(slot.moduleName)
      var known = !!(barWidgetRegistry.widgets && barWidgetRegistry.widgets[id])
      if ((!slot.registered && known) || (slot.registered && item && !("bar" in item) && item.implicitWidth <= 0))
        stale.push(slot.moduleName)
    }
    return stale
  }

  function healEmptyWidgets() {
    var serial = barConfigSerial
    var entries = layoutEntries("left").length + layoutEntries("center").length + layoutEntries("right").length
    if (entries === 0) return
    var stale = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      var item = slot ? slot.activeItem : null
      if (!slot || slot.customType) continue
      var id = canonicalWidgetId(slot.moduleName)
      var known = !!(barWidgetRegistry.widgets && barWidgetRegistry.widgets[id])
      // Listed in the catalogue but with no component to build it from, or
      // built from a dead component into an item that is not a widget.
      if ((!slot.registered && known) || (slot.registered && item && !("bar" in item) && item.implicitWidth <= 0))
        stale.push(slot.moduleName)
    }
    if (stale.length === 0) return
    if (Date.now() - healState.lastRescan < 30000) return
    healState.lastRescan = Date.now()
    console.warn("graveklar.notch: widgets loaded empty (" + stale.join(", ") + "); rescanning plugins to refresh the widget catalogue")
    healProcess.running = true
  }

  // The notch's one media source: omarchy.media's activePlayer, through the
  // facade the host gives this bar -- the same player the stock media widget
  // in the row shows (it asks bar.shell for the same proxy). omarchy.media
  // picks it by cross-checking MPRIS players against live PipeWire streams.
  // No facade or no active player means no media anywhere in the notch; there
  // is deliberately no direct-MPRIS fallback, since two sources picking
  // different players is exactly the bug this replaces.
  readonly property var mediaService: root.shell && typeof root.shell.firstPartyServiceFor === "function"
    ? root.shell.firstPartyServiceFor("omarchy.media") : null
  readonly property var mediaPlayer: mediaService && mediaService.activePlayer ? mediaService.activePlayer : null
  function mediaPlayerKey(player) {
    return mediaService && player && typeof mediaService.playerKey === "function" ? String(mediaService.playerKey(player)) : ""
  }

  signal batteryEvent(string kind)
  property string previousBatteryMode: ""
  onBatteryModeChanged: {
    var previous = previousBatteryMode
    previousBatteryMode = batteryMode
    if (previous === "") return
    var wasPlugged = previous === "charging" || previous === "full"
    var isPlugged = batteryMode === "charging" || batteryMode === "full"
    if (batteryMode === "charging" && !wasPlugged) batteryEvent("plugged")
    else if (wasPlugged && !isPlugged) batteryEvent("unplugged")
    else if (batteryMode === "critical" && previous !== "critical") batteryEvent("critical")
    else if (batteryMode === "low" && previous !== "low" && previous !== "critical") batteryEvent("low")
  }

  // Persist a notch setting into bar.notch in shell.json; the change comes
  // back in through barConfig like any other edit.
  // --- updates -------------------------------------------------------------------
  //
  // The live notch is a git checkout (`omarchy plugin add`). When GitHub has a
  // newer notch, a small notice pops down from the resting notch with Later and
  // Update (NotchUpdate.qml). Update runs bin/notch-update detached, in its own
  // `systemd-run --user` unit: the update reloads every plugin and restarts the
  // shell, which destroys this notch, so the rebuilt notch reads the job's
  // status file and says how it went. Later snoozes that version.
  //
  //   updateCheck    check at start (after 20 s) and every 6 h (default true)
  //
  // Test notches never check or update unless NOTCH_FORCE_UPDATES=1; dev/update.sh
  // also points NOTCH_UPDATE_DIR / _STATE_DIR / _APPLY / _RESTART at a sandbox.
  readonly property bool notchUpdateCheck: notchSetting("updateCheck", true) !== false
  // Replace the Omarchy menu: every way into Omarchy's menu opens the notch's
  // menu instead, through the companion plugin (MenuCompanion.qml). Off means
  // Omarchy's own menu window, exactly as before.
  readonly property bool notchReplaceMenu: notchSetting("replaceMenu", false) === true
  readonly property bool updatesEnabled: (!!root.shell && !root.harnessed) || Quickshell.env("NOTCH_FORCE_UPDATES") === "1"
  readonly property string updateScript: String(Qt.resolvedUrl("bin/notch-update")).replace(/^file:\/\//, "")
  readonly property string updateStateDir: Quickshell.env("NOTCH_UPDATE_STATE_DIR") || ""
  readonly property string updateStatusPath: (updateStateDir || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/graveklar.notch")) + "/update.json"
  readonly property string updateSnoozePath: (updateStateDir || ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/graveklar.notch")) + "/update-snoozed"
  property var updateCheckResult: ({ state: "unchecked" })
  property var updateJob: ({})
  property string updateSnoozed: ""
  // Ticks while the notice depends on time (a running or just-finished job).
  property real updateClock: Date.now()

  // What the notice shows, or "" for nothing:
  //   updating   a job started in the last 5 minutes is still running
  //   done       a job finished in the last 10 minutes and hasn't been seen
  //   failed     likewise, failed
  //   available  an update is out and that version isn't snoozed
  readonly property string updateNotice: {
    if (!updatesEnabled) return ""
    var now = updateClock
    var job = updateJob || {}
    if (job.phase === "updating" && now - Number(job.startedAt || 0) < 5 * 60000) return "updating"
    if ((job.phase === "done" || job.phase === "failed") && job.seen !== true && now - Number(job.finishedAt || 0) < 10 * 60000) return job.phase
    var c = updateCheckResult || {}
    // Not a version the last job just installed (the check result can be
    // older than the job).
    if (c.state === "available" && c.remote && c.remote !== updateSnoozed && !(job.phase === "done" && job.to === c.remote)) return "available"
    return ""
  }

  readonly property bool updateCheckRunning: updateCheckProcess.running

  function checkForUpdates() {
    if (!updatesEnabled || updateCheckProcess.running) return false
    updateCheckProcess.running = true
    return true
  }

  // Start the update. Returns false when it can't start (disabled, or one is running).
  function startUpdate() {
    // Not while a plugin job runs: both reload every plugin.
    if (!updatesEnabled || updateNotice === "updating" || pluginJobRunning) return false
    var run = [updateScript, "run", updateStatusPath]
    var argv
    if ((Quickshell.env("NOTCH_UPDATE_DETACH") || "systemd-run") === "systemd-run") {
      argv = ["systemd-run", "--user", "--collect", "--quiet", "--unit", "graveklar-notch-update-" + Date.now()];
      // A transient unit starts from the user manager's environment: hand it
      // what omarchy's commands and the test hooks need.
      var passed = ["PATH", "HOME", "OMARCHY_PATH", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR",
                    "XDG_STATE_HOME", "NOTCH_UPDATE_DIR", "NOTCH_UPDATE_APPLY", "NOTCH_UPDATE_RESTART"]
      for (var i = 0; i < passed.length; i++) {
        var value = Quickshell.env(passed[i])
        if (value) argv.push("--setenv=" + passed[i] + "=" + value)
      }
      argv = argv.concat(run)
    } else {
      argv = ["setsid", "-f"].concat(run)
    }
    updateJob = { phase: "updating", startedAt: Date.now(), from: String((updateCheckResult || {}).local || ""), finishedAt: 0, seen: false, launched: true }
    updateClock = Date.now()
    Quickshell.execDetached(argv)
    updateStatusPoll.restart()
    return true
  }

  // Later: don't offer this version again.
  function snoozeUpdate() {
    var sha = String((updateCheckResult || {}).remote || "")
    if (!/^[0-9a-f]{7,64}$/.test(sha)) return false
    updateSnoozed = sha
    Quickshell.execDetached([updateScript, "snooze", updateSnoozePath, sha])
    return true
  }

  // A finished update's notice has been seen. Dismissing a failed update also
  // snoozes that version, so the notice doesn't come straight back (Settings →
  // Updates still offers it).
  function ackUpdate() {
    if (!updateJob || !updateJob.phase) return false
    var job = JSON.parse(JSON.stringify(updateJob))
    job.seen = true
    updateJob = job
    Quickshell.execDetached([updateScript, "ack", updateStatusPath])
    if (job.phase === "failed") snoozeUpdate()
    return true
  }

  // --- setup ---------------------------------------------------------------
  //
  // What is stopping the notch from working the way you want, and the buttons
  // that put it right. SetupService.qml reads; bin/notch-setup changes.
  SetupService { id: setupService; bar: root }

  // --- the platform -----------------------------------------------------------
  //
  // Other plugins' panels, drawn inside the notch (NotchPlatform.qml, SURFACE-HOSTING.md).
  NotchPlatform { id: platformService; bar: root }

  // Another plugin's pop-out panel, drawn inside the notch instead of in a
  // window of its own (PanelHosting.qml). One at a time, on one screen.
  PanelHosting { id: panelHosting; opted: root.notchHostedPanels }
  readonly property var notificationsSource: notifications
  readonly property var hosting: panelHosting

  // Open `item`'s panel inside the notch, on the screen it was clicked on.
  // Answers "opened", or why not -- the caller draws its own panel on anything
  // but "opened", so a decline is never a plugin with no UI.
  function hostPanel(item, screenName) {
    var window = null
    var windows = notchWindows
    for (var i = 0; i < windows.length; i++)
      if (screenName && windows[i].screen && windows[i].screen.name === screenName) window = windows[i]
    if (!window) window = focusedNotchWindow()
    if (!window) return "declined:no-screen"
    if (barHidden) return "declined:hidden"
    return window.openHosted(item)
  }

  function releaseHostedPanel() {
    var windows = notchWindows
    for (var i = 0; i < windows.length; i++) if (windows[i].hostedOpen) windows[i].hostedOpen = false
  }
  readonly property var platform: platformService
  // Activities are claimed and queued, but nothing draws them at rest yet, so a
  // claim that would be shown answers "queued" (plan-activities-notifications).
  // Activities draw as a line in the resting notch (the transient slot widens
  // it sideways), so a claim the queue shows is a claim the user sees.
  readonly property bool activitiesRendered: true
  readonly property bool notchNotifications: notchSetting("notifications", true) !== false

  NotchNotifications { id: notifications; bar: root }

  // The activity the notch is showing, if any.
  //
  // The queue holds two visible at once (activities.js MAX_VISIBLE, the
  // platform's rule), but the notch draws **one**: placement is sideways only,
  // so a second line would either stack -- which the placement contract rules
  // out -- or widen the notch until it stopped being a notch. The newest wins,
  // because a notification arriving is the thing you are meant to see; the
  // other keeps its slot and draws when that one goes.
  readonly property var activityLine: {
    var visible = platform.activityState.visible
    var best = null
    for (var i = 0; i < visible.length; i++) {
      if (best === null || Number(visible[i].shownAt) >= Number(best.shownAt)) best = visible[i]
    }
    return best
  }
  readonly property var setup: setupService
  readonly property real startedAt: Date.now()

  function setupReport() {
    var status = setupService.status()
    status.script = setupService.script
    return status
  }

  function updateReport() {
    return {
      enabled: updatesEnabled, checkSetting: notchUpdateCheck, checking: updateCheckProcess.running,
      check: updateCheckResult, job: updateJob, snoozed: updateSnoozed, notice: updateNotice,
      statusPath: updateStatusPath, snoozePath: updateSnoozePath
    }
  }

  Process {
    id: updateCheckProcess
    command: [root.updateScript, "check"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.updateCheckResult = JSON.parse(text) }
        catch (e) { root.updateCheckResult = { state: "error", checkedAt: Date.now() } }
      }
    }
  }

  Timer {
    interval: Number(Quickshell.env("NOTCH_UPDATE_FIRST_CHECK_MS") || 20000)
    running: root.updatesEnabled && root.notchUpdateCheck
    onTriggered: root.checkForUpdates()
  }
  Timer {
    interval: 6 * 3600 * 1000
    repeat: true
    running: root.updatesEnabled && root.notchUpdateCheck
    onTriggered: root.checkForUpdates()
  }

  FileView {
    id: updateStatusFile
    // A notch that doesn't update itself never reads the live notch's files.
    path: root.updatesEnabled ? root.updateStatusPath : ""
    printErrors: false
    onLoaded: {
      try {
        var job = JSON.parse(text())
        // A job this notch launched that hasn't written its first status yet
        // keeps the local "updating" until the file catches up.
        if (job && job.phase && !(root.updateJob.launched && Number(job.startedAt || 0) < Number(root.updateJob.startedAt || 0) - 2000)) {
          var finished = root.updateJob.phase === "updating" && (job.phase === "done" || job.phase === "failed")
          root.updateJob = job
          // A job that just finished changes what there is to update to.
          if (finished) root.checkForUpdates()
        }
      } catch (e) { }
      root.updateClock = Date.now()
    }
  }
  FileView {
    id: updateSnoozeFile
    path: root.updatesEnabled ? root.updateSnoozePath : ""
    printErrors: false
    onLoaded: root.updateSnoozed = String(text()).trim()
  }
  // While a job runs, follow its status file; after, keep the clock moving so
  // stale notices expire.
  Timer {
    id: updateStatusPoll
    interval: 1000
    repeat: true
    running: root.updatesEnabled && (root.updateNotice === "updating" || root.updateNotice === "done" || root.updateNotice === "failed")
    onTriggered: { updateStatusFile.reload(); root.updateClock = Date.now() }
  }
  // "Notch updated" shows for a few seconds, then counts as seen.
  Timer {
    interval: Number(Quickshell.env("NOTCH_UPDATE_DONE_MS") || 5000)
    running: root.updateNotice === "done"
    onTriggered: root.ackUpdate()
  }

  // --- plugins -------------------------------------------------------------------
  //
  // The user's own plugins (plugins/catalogue.json: Face ID and Profiles) are
  // installed, turned on and updated from the Plugins page inside the notch
  // (plugins/NotchPlugins.qml). bin/notch-plugins does the work: `state` probes
  // every entry, `preview` fills the confirmation card, and `run` is launched
  // detached like the notch's own update, because installing or updating a
  // plugin reloads every plugin and destroys this notch. The rebuilt notch
  // reads the job's status file, re-reads the disk and pops down a notice
  // (plugins/NotchPluginsNotice.qml). Setup and removal are handed to each
  // plugin's own panel.
  //
  // Nothing is checked at startup: the page checks when it opens (if the last
  // full check is a minute old), on Refresh, and after a job -- first locally
  // (no network: the notice never waits for GitHub), then in full. Test
  // notches never probe, read the status file or act unless
  // NOTCH_FORCE_PLUGINS=1 and the NOTCH_PLUGINS_DIR and NOTCH_PLUGINS_OMARCHY
  // sandbox hooks are set (dev/plugins.sh).
  readonly property bool pluginsEnabled: (!!root.shell && !root.harnessed) || Quickshell.env("NOTCH_FORCE_PLUGINS") === "1"
  readonly property bool pluginsSandboxed: !!Quickshell.env("NOTCH_PLUGINS_DIR") && !!Quickshell.env("NOTCH_PLUGINS_OMARCHY")
  readonly property bool pluginsCanAct: pluginsEnabled && (!root.harnessed || pluginsSandboxed)
  readonly property string pluginsScript: String(Qt.resolvedUrl("bin/notch-plugins")).replace(/^file:\/\//, "")
  // The status dir hook is honoured only in a sandbox.
  readonly property string pluginsStatusPath: ((pluginsSandboxed && Quickshell.env("NOTCH_PLUGINS_STATE_DIR"))
    || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/graveklar.notch")) + "/plugins-job.json"
  // The validated catalogue, the last probe (a local one merged over the last
  // full one), the last full probe, the job's status file, the card
  // ({ action, id, token }) and its preview, and the last handoff's answer.
  property var pluginsCatalogue: ({ self: {}, plugins: [] })
  property var pluginsState: ({ checkedAt: 0, startedAt: 0, entries: [] })
  property var pluginsFull: ({ checkedAt: 0, startedAt: 0, entries: [] })
  property var pluginsJob: ({})
  property var pluginsPreview: ({})
  property var pluginsConfirm: ({})
  property var pluginsHandoff: ({})
  property real pluginsClock: Date.now()
  property int pluginsTokens: 0

  // A plugin job this notch (or an earlier one) started is still running. The
  // notch's own update waits for it, and it for the update.
  readonly property bool pluginJobRunning: PluginsModel.jobRunning(pluginsJob, pluginsClock)
  readonly property bool pluginsStateProcessRunning: pluginsStateProcess.running
  // One view per catalogue entry, for the page, its keys and the report.
  readonly property var pluginsViews: {
    var now = pluginsClock
    var byId = {}
    var probed = (pluginsState && pluginsState.entries) || []
    for (var i = 0; i < probed.length; i++) byId[probed[i].id] = probed[i]
    var listed = (pluginsCatalogue && pluginsCatalogue.plugins && pluginsCatalogue.plugins.length) ? pluginsCatalogue.plugins : probed
    return listed.map(function(p) {
      var e = byId[p.id] ? Object.assign({ checked: true }, byId[p.id]) : { id: p.id, name: p.name, checked: false }
      return PluginsModel.entryView(e, root.pluginsJob, now, { canAct: root.pluginsCanAct, handoff: root.pluginsHandoff,
                                                             checking: pluginsStateProcess.running })
    })
  }
  readonly property var pluginsSelfView: PluginsModel.selfView(Object.assign({}, (pluginsCatalogue || {}).self || {}, (pluginsState || {}).self || {}))
  readonly property var pluginsJobEntry: {
    var probed = (pluginsState && pluginsState.entries) || []
    for (var i = 0; i < probed.length; i++) if (probed[i].id === (pluginsJob || {}).id) return probed[i]
    return null
  }
  // A finished job's notice stays (until a click) when it has something to offer.
  readonly property bool pluginsDoneNeedsClick: {
    var e = pluginsJobEntry
    if ((pluginsJob || {}).restartSuggested === true) return true
    if (!e) return false
    return (e.installed && !e.enabled) || (e.enabled && (e.setup === "needed" || e.setup === "attention"))
  }
  // The disk has been probed since the job finished: a probe that started
  // after it (a slow probe begun earlier doesn't count).
  readonly property bool pluginsProbedAfterJob: Number((pluginsState || {}).startedAt || 0) >= Number((pluginsJob || {}).finishedAt || 0)

  // What the post-job notice shows, or "":
  //   running   a job started in the last 5 minutes is running, or finished and
  //             the disk is being re-read (success is never shown from the
  //             status file alone)
  //   done      it finished in the last 10 minutes, unseen
  //   failed    likewise, failed; or a "running" job older than 5 minutes
  readonly property string pluginsNotice: {
    if (!pluginsCanAct) return ""
    var job = pluginsJob || {}
    var now = pluginsClock
    if (!job.phase || job.seen === true) return ""
    if (job.phase === "running") return now - Number(job.startedAt || 0) < 5 * 60000 ? "running" : now - Number(job.startedAt || 0) < 15 * 60000 ? "failed" : ""
    if ((job.phase === "done" || job.phase === "failed") && now - Number(job.finishedAt || 0) < 10 * 60000) {
      if (job.phase === "done" && !pluginsProbedAfterJob) return "running"
      return job.phase
    }
    return ""
  }
  // The card's confirm button: a fresh preview returned the exact commit, and
  // the repository there is still this plugin (its manifest id and kinds).
  readonly property bool pluginsConfirmReady: !!(pluginsConfirm || {}).id && pluginsPreview.id === pluginsConfirm.id
    && pluginsPreview.token === pluginsConfirm.token && pluginsPreview.ok === true && pluginsPreview.refused === ""
    && /^[0-9a-f]{40}$/.test(String(pluginsPreview.remote || "")) && !pluginJobRunning && updateNotice !== "updating"
    && !pluginsStateProcess.running

  function loadPluginsCatalogue() {
    if (!pluginsCanAct || pluginsCatalogueProcess.running || ((pluginsCatalogue || {}).plugins || []).length > 0) return
    pluginsCatalogueProcess.running = true
  }

  // Probe the plugins: `local` true for HEAD, enabled and setup only (no
  // network). While a job runs every probe is local, so nothing fetches into
  // a checkout the job is changing.
  function refreshPlugins(local) {
    loadPluginsCatalogue()
    if (!pluginsCanAct) return false
    var p = local === true || pluginJobRunning ? pluginsLocalProcess : pluginsStateProcess
    if (p.running) p.again = true
    else p.running = true
    return true
  }

  function refreshPluginsIfStale() {
    loadPluginsCatalogue()
    if (Date.now() - Number((pluginsFull || {}).checkedAt || 0) > 60000 && !pluginsStateProcess.running) refreshPlugins()
  }

  // Install… and Update… open the card; nothing runs until it is confirmed.
  function askPluginAction(action, id) {
    if (!pluginsCanAct || (action !== "install" && action !== "update") || pluginJobRunning) return false
    pluginsTokens += 1
    pluginsConfirm = { action: action, id: String(id), token: pluginsTokens }
    pluginsPreview = {}
    pluginsPreviewProcess.nextToken = pluginsTokens
    pluginsPreviewProcess.nextId = String(id)
    if (!pluginsPreviewProcess.running) pluginsPreviewProcess.begin()
    return true
  }

  function cancelPluginAction() {
    if (!(pluginsConfirm || {}).id && !(pluginsPreview || {}).id) return
    pluginsConfirm = ({})
    pluginsPreview = ({})
  }

  // Launch `run` detached, exactly like startUpdate(). Returns false when it
  // can't start (a test notch, or a plugin job or notch update is running).
  function launchPluginsRun(args) {
    if (!pluginsCanAct || pluginJobRunning || updateNotice === "updating") return false
    var run = [pluginsScript, "run"].concat(args)
    var argv
    if ((Quickshell.env("NOTCH_PLUGINS_DETACH") || "systemd-run") === "systemd-run") {
      argv = ["systemd-run", "--user", "--collect", "--quiet", "--unit", "graveklar-notch-plugins-" + Date.now()]
      var passed = ["PATH", "HOME", "OMARCHY_PATH", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR",
                    "XDG_CONFIG_HOME", "XDG_STATE_HOME", "NOTCH_PLUGINS_DIR", "NOTCH_PLUGINS_OMARCHY", "NOTCH_PLUGINS_CATALOGUE",
                    "NOTCH_PLUGINS_SHELL", "NOTCH_PLUGINS_TERMINAL", "NOTCH_PLUGINS_SESSION_LOCKED", "NOTCH_PLUGINS_SCRATCH",
                    "NOTCH_PLUGINS_DISCOVER_MS"]
      for (var i = 0; i < passed.length; i++) {
        var value = Quickshell.env(passed[i])
        if (value) argv.push("--setenv=" + passed[i] + "=" + value)
      }
      argv = argv.concat(run)
    } else {
      argv = ["setsid", "-f"].concat(run)
    }
    // Local until the runner writes its first status; a runner that refuses
    // before that (another job holds the lock) is caught by
    // expirePluginsLaunch().
    pluginsJob = { phase: "running", action: String(args[0]), id: String(args[1]), startedAt: Date.now(), finishedAt: 0, seen: false, launched: true }
    pluginsClock = Date.now()
    Quickshell.execDetached(argv)
    pluginsStatusPoll.restart()
    return true
  }

  // A launched job whose runner never wrote its status within 5 s didn't start.
  function expirePluginsLaunch() {
    var j = pluginsJob || {}
    if (j.launched && j.phase === "running" && Date.now() - Number(j.startedAt || 0) > 5000)
      pluginsJob = { phase: "failed", reason: "not-started", action: j.action, id: j.id, startedAt: j.startedAt,
                     finishedAt: Date.now(), seen: false, launched: true }
  }

  // The card's confirm: only for the card on show, with the commit it showed.
  function startPluginJob(token) {
    var c = pluginsConfirm || {}
    if (!c.id || token !== c.token || !pluginsConfirmReady) return false
    if (!launchPluginsRun([c.action, c.id, pluginsStatusPath, String(pluginsPreview.remote)])) return false
    cancelPluginAction()
    return true
  }

  // Enable needs no card: nothing is downloaded and no --yes is involved.
  function enablePlugin(id) {
    return launchPluginsRun(["enable", String(id), pluginsStatusPath])
  }

  function openPluginSetup(id) { return pluginsHandOff("setup", id) }
  function openPluginRemoval(id) { return pluginsHandOff("remove", id) }
  function pluginsHandOff(kind, id) {
    if (!pluginsCanAct || pluginsHandoffProcess.running) return false
    pluginsHandoff = { id: String(id), kind: kind, pending: true }
    pluginsHandoffProcess.command = [pluginsScript, kind, String(id)]
    pluginsHandoffProcess.running = true
    return true
  }

  function reviewPluginInTerminal(id) {
    if (!pluginsCanAct) return false
    Quickshell.execDetached([pluginsScript, "review", String(id)])
    return true
  }

  // Only on an explicit click: a rescan leaves non-entry QML stale.
  function restartShellForPlugins() {
    var hook = Quickshell.env("NOTCH_PLUGINS_RESTART")
    if (!pluginsCanAct || (root.harnessed && !hook)) return false
    ackPluginJob()
    Quickshell.execDetached(hook ? ["bash", "-c", hook] : ["omarchy", "restart", "shell"])
    return true
  }

  // Seen here at once; in the status file only for that job, once finished
  // (the runner checks both under the job lock).
  function ackPluginJob() {
    if (!pluginsJob || !pluginsJob.phase) return false
    var job = JSON.parse(JSON.stringify(pluginsJob))
    job.seen = true
    pluginsJob = job
    if (pluginsCanAct && job.job && job.phase !== "running")
      Quickshell.execDetached([pluginsScript, "ack", pluginsStatusPath, String(job.job)])
    return true
  }

  function clearPluginHandoff() { pluginsHandoff = ({}) }

  function closePluginsPages() {
    for (var i = 0; i < notchWindows.length; i++) if (notchWindows[i].pluginsOpen) notchWindows[i].pluginsOpen = false
  }

  // A finished job re-reads the disk before its notice says anything: a local
  // probe first (a few hundred ms, no network), then a full one.
  function pluginsJobSettled() {
    var job = pluginsJob || {}
    if ((job.phase === "done" || job.phase === "failed") && job.seen !== true && !pluginsLocalProcess.running
        && Date.now() - Number(job.finishedAt || 0) < 10 * 60000 && !pluginsProbedAfterJob) {
      pluginsLocalProcess.thenFull = true
      refreshPlugins(true)
    }
  }

  function pluginsReport() {
    var w = focusedNotchWindow()
    var c = pluginsConfirm || {}
    var entry = null
    var listed = (pluginsCatalogue || {}).plugins || []
    for (var i = 0; i < listed.length; i++) if (listed[i].id === c.id) entry = listed[i]
    var s = pluginsState || {}
    return {
      enabled: pluginsEnabled, canAct: pluginsCanAct, sandboxed: pluginsSandboxed, open: w ? w.pluginsOpen : false,
      checking: pluginsStateProcess.running, checkingLocal: pluginsLocalProcess.running,
      checkedAt: Number(s.checkedAt || 0), startedAt: Number(s.startedAt || 0), local: s.local === true,
      fullCheckedAt: Number((pluginsFull || {}).checkedAt || 0), pluginsDir: s.pluginsDir || "", shell: s.shell,
      entries: pluginsViews, self: pluginsSelfView, probe: s.entries || [],
      job: pluginsJob, jobRunning: pluginJobRunning, notice: pluginsNotice, doneNeedsClick: pluginsDoneNeedsClick,
      confirm: c.id ? { action: c.action, id: c.id, url: entry ? entry.url : "", token: c.token, ready: pluginsConfirmReady,
                        refused: String(pluginsPreview.refused || ""),
                        sha: pluginsConfirmReady ? String(pluginsPreview.remote) : "" } : null,
      preview: pluginsPreview, handoff: pluginsHandoff, statusPath: pluginsStatusPath,
      updateBlocked: pluginJobRunning
    }
  }

  Process {
    id: pluginsCatalogueProcess
    command: [root.pluginsScript, "catalogue"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { var c = JSON.parse(text); if (c && c.plugins) root.pluginsCatalogue = c } catch (e) { }
      }
    }
  }
  Process {
    id: pluginsStateProcess
    // Asked again while a probe ran: probe once more after it.
    property bool again: false
    command: [root.pluginsScript, "state"]
    stdout: StdioCollector {
      onStreamFinished: {
        var s = null
        try { s = JSON.parse(text) } catch (e) { }
        if (!s || !s.entries) s = { checkedAt: Date.now(), startedAt: 0, entries: [], reason: s && s.reason ? s.reason : "command" }
        else root.pluginsFull = s
        // A local probe newer than this one stays; its network fields come from this.
        if (Number((root.pluginsState || {}).startedAt || 0) > Number(s.startedAt || 0) && root.pluginsState.local === true && s.entries.length)
          root.pluginsState = PluginsModel.mergeLocal(s, root.pluginsState)
        else
          root.pluginsState = s
        root.pluginsClock = Date.now()
      }
    }
    onRunningChanged: if (!running && again) { again = false; root.refreshPlugins() }
  }
  Process {
    id: pluginsLocalProcess
    property bool again: false
    // A job just finished: the full probe follows this one.
    property bool thenFull: false
    command: [root.pluginsScript, "state", "--local"]
    stdout: StdioCollector {
      onStreamFinished: {
        var s = null
        try { s = JSON.parse(text) } catch (e) { }
        if (s && s.entries) root.pluginsState = PluginsModel.mergeLocal(root.pluginsFull, s)
        root.pluginsClock = Date.now()
      }
    }
    onRunningChanged: {
      if (running) return
      if (again) { again = false; running = true; return }
      if (thenFull) { thenFull = false; root.refreshPlugins() }
      root.pluginsJobSettled()
    }
  }
  Process {
    id: pluginsPreviewProcess
    // The card each run is for; a newer card starts its own run after this one.
    property int runToken: 0
    property int nextToken: 0
    property string nextId: ""
    function begin() {
      runToken = nextToken
      command = [root.pluginsScript, "preview", nextId]
      running = true
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (pluginsPreviewProcess.runToken !== (root.pluginsConfirm || {}).token) return
        var p = null
        try { p = JSON.parse(text) } catch (e) { }
        if (!p || !p.id) p = { id: root.pluginsConfirm.id, ok: false, refused: "", reason: p && p.reason ? p.reason : "command" }
        p.token = pluginsPreviewProcess.runToken
        root.pluginsPreview = p
      }
    }
    onRunningChanged: if (!running && nextToken !== runToken && root.pluginsCanAct) begin()
  }
  Process {
    id: pluginsHandoffProcess
    stdout: StdioCollector {
      onStreamFinished: {
        var r = null
        try { r = JSON.parse(text) } catch (e) { }
        if (!r || !r.id) r = { id: root.pluginsHandoff.id, kind: root.pluginsHandoff.kind, ok: false, reason: r && r.reason === "sandbox" ? "sandbox" : "not-running" }
        root.pluginsHandoff = r
        // The plugin's own panel is opening: get out of its way.
        if (r.ok) root.closePluginsPages()
      }
    }
  }
  FileView {
    id: pluginsStatusFile
    // A notch that can't act never reads the live notch's files.
    path: root.pluginsCanAct ? root.pluginsStatusPath : ""
    printErrors: false
    onLoaded: {
      try {
        var job = JSON.parse(text())
        var local = root.pluginsJob || {}
        // A job this notch launched keeps its local state until the runner
        // writes a status of its own (an older file is the previous job).
        if (job && job.phase && !(local.launched && Number(job.startedAt || 0) < Number(local.startedAt || 0) - 2000))
          root.pluginsJob = job
      } catch (e) { }
      root.expirePluginsLaunch()
      root.pluginsClock = Date.now()
      root.pluginsJobSettled()
    }
    onLoadFailed: root.expirePluginsLaunch()
  }
  // While a job runs or its notice shows, follow the status file and keep the
  // clock moving so stale notices expire.
  Timer {
    id: pluginsStatusPoll
    interval: 1000
    repeat: true
    running: root.pluginsCanAct && (root.pluginsNotice !== "" || root.pluginJobRunning)
    onTriggered: { pluginsStatusFile.reload(); root.expirePluginsLaunch(); root.pluginsClock = Date.now() }
  }
  // "Face ID installed" shows for a few seconds, then counts as seen, unless it
  // offers Open setup, Enable or Restart shell.
  Timer {
    interval: Number(Quickshell.env("NOTCH_PLUGINS_DONE_MS") || 5000)
    running: root.pluginsNotice === "done" && !root.pluginsDoneNeedsClick
    onTriggered: root.ackPluginJob()
  }

  // The menu companion: the bridge registration, its folder's state, and the
  // jobs that install or update it.
  MenuCompanion { id: menuCompanionHelper; bar: root }
  readonly property var menuCompanion: menuCompanionHelper

  function setNotchSetting(key, value) {
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false
    return root.shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      if (!Util.isPlainObject(config.bar.notch)) config.bar.notch = {}
      config.bar.notch[key] = value
    }) !== false
  }

  // The open notch is one row on the same axis as the resting one: it keeps
  // the resting height and only widens, with the widgets vertically centred
  // where the resting notch's content sits.
  readonly property real notchSidePadding: Style.space(14)
  readonly property real notchSectionGap: Style.space(18)
  readonly property real notchExpandedHeight: notchCompactHeight

  // Motion, as numbers. Growing runs on a damped spring (one overshoot of
  // about 4 %, then settled): height over 350 ms, width 50 ms later over
  // 300 ms, so both land together. Shrinking eases out over 240 ms with no
  // overshoot. The entrance grows from a seed 35 % as wide as the notch and
  // zero high, top edge on the screen edge from the first frame.
  readonly property real springDamping: 0.72
  readonly property real springPeakAt: 0.6
  readonly property real springOvershoot: Spring.overshoot(springDamping)
  readonly property var springCurve: Spring.curve(springDamping, springPeakAt, 8)
  readonly property int growHeightDuration: 350
  readonly property int growWidthDelay: 50
  readonly property int growWidthDuration: 300
  readonly property int shrinkDuration: 240
  readonly property real seedWidthFraction: 0.35

  property bool notchForcedExpanded: false
  property var notchWindows: []

  function registerNotchWindow(window) {
    if (notchWindows.indexOf(window) === -1) notchWindows = notchWindows.concat([window])
  }

  function unregisterNotchWindow(window) {
    notchWindows = notchWindows.filter(function(w) { return w !== window })
  }

  // --- the Omarchy menu, when the notch is it -----------------------------------
  //
  // MenuCompanion.qml hands these to the companion plugin (and nothing else).
  readonly property bool anyMenuOpen: {
    for (var i = 0; i < notchWindows.length; i++) if (notchWindows[i].menuOpen) return true
    return false
  }

  // Take an Omarchy menu request (a route, or a select/input picker) into the
  // notch. False means "not now": the setting is off, the bar is hidden, no
  // notch window has focus, or its menu hasn't loaded -- the companion then
  // opens Omarchy's own menu, so the request is never dropped.
  function openMenuPayload(payloadJson) {
    if (!notchReplaceMenu || barHidden) return false
    var w = focusedNotchWindow()
    if (!w || !w.menuHostItem) return false
    for (var i = 0; i < notchWindows.length; i++)
      if (notchWindows[i] !== w) notchWindows[i].menuOpen = false
    return w.openMenuRequest(payloadJson)
  }

  function closeMenus() {
    for (var i = 0; i < notchWindows.length; i++) notchWindows[i].menuOpen = false
  }

  function refreshMenus() {
    for (var i = 0; i < notchWindows.length; i++) {
      var item = notchWindows[i].menuHostItem
      if (item && typeof item.refresh === "function") item.refresh()
    }
  }

  function focusedNotchWindow() {
    var name = focusedScreenName()
    for (var i = 0; i < notchWindows.length; i++)
      if (notchWindows[i].screen && notchWindows[i].screen.name === name) return notchWindows[i]
    return notchWindows.length > 0 ? notchWindows[0] : null
  }

  IpcHandler {
    target: "notch"

    function expand(): void { var w = root.focusedNotchWindow(); if (w) w.openView(root.notchOpenAction, "key") }
    function collapse(): void { for (var i = 0; i < root.notchWindows.length; i++) root.notchWindows[i].collapseNow() }
    // The open keybind. From the settings or the menu it goes to the open view
    // (or just closes the panel, when the open action is that panel).
    function toggle(): void {
      var w = root.focusedNotchWindow()
      if (!w) return
      var action = root.notchOpenAction
      if (w.panelOpen) {
        if (action === "none" || w.setupOpen || (action === "settings" && w.settingsOpen) || (action === "menu" && w.menuOpen)) w.closePanels()
        else w.openView(action, "key")
        return
      }
      if (w.expanded) w.collapseNow()
      else w.openView(action, "key")
    }
    function peek(): void { var w = root.focusedNotchWindow(); if (w) w.startPeek("media") }
    // Open one of the notch's views as if hovered: widgets, clock, battery,
    // plugin (the hoverPlugin widget), settings or setup.
    function view(name: string): void { var w = root.focusedNotchWindow(); if (w) w.openView(name, "hover") }
    // Preview the battery glow: state is charging, discharging, full or auto
    // (back to the real battery). Returns the resulting battery mode.
    function simulateBattery(state: string, percent: int): string {
      if (state === "auto" || ["charging", "discharging", "full"].indexOf(state) === -1) {
        root.batterySimulatedState = ""
        root.batterySimulatedPercent = -1
      } else {
        root.batterySimulatedPercent = Math.max(0, Math.min(100, percent))
        root.batterySimulatedState = state
      }
      return root.batteryMode
    }
    // "true", "false" or "toggle"; saved to shell.json. Returns the new value.
    function stayOpen(value: string): string {
      var next = value === "toggle" ? !root.notchStayOpen : value === "true"
      if (value !== "toggle" && value !== "true" && value !== "false") return String(root.notchStayOpen)
      return root.setNotchSetting("stayOpen", next) ? String(next) : "unsaved"
    }
    // "true", "false" or "toggle"; saved to shell.json. Returns the new value.
    function autoHide(value: string): string {
      var next = value === "toggle" ? !root.notchAutoHide : value === "true"
      if (value !== "toggle" && value !== "true" && value !== "false") return String(root.notchAutoHide)
      return root.setNotchSetting("autoHide", next) ? String(next) : "unsaved"
    }
    // "true", "false" or "toggle"; saved to shell.json. Returns the new value.
    function windowsToTop(value: string): string {
      var next = value === "toggle" ? !root.notchWindowsToTop : value === "true"
      if (value !== "toggle" && value !== "true" && value !== "false") return String(root.notchWindowsToTop)
      return root.setNotchSetting("windowsToTop", next) ? String(next) : "unsaved"
    }
    // Every radius, centre and easing constant of the focused screen's notch,
    // as JSON, so the geometry can be checked numerically.
    // Open or close the settings dropdown on the focused screen.
    function settings(): void {
      var w = root.focusedNotchWindow()
      if (!w) return
      if (w.settingsOpen) w.settingsOpen = false
      else w.openSettings()
    }
    // Open the Omarchy menu inside the focused screen's notch at a route --
    // "root", a menu id such as "system", or an alias such as "power" -- or
    // close it if it is open there.
    function menu(route: string): void {
      var w = root.focusedNotchWindow()
      if (!w) return
      if (w.menuOpen) w.menuOpen = false
      else w.openMenu(route)
    }
    // Save one notch setting the way the settings panel does (no bar reload):
    // `set compactWidth 220`, `set hoverPlugin omarchy.clock`. List settings
    // take space-separated values -- `set hiddenPlugins "a b"` -- because the
    // IPC command line splits arguments on commas. Anything else is JSON if it
    // parses, a string if not.
    function set(key: string, value: string): string {
      var lists = ["compact", "expanded", "openWith", "settingsWith", "menuWith", "hiddenPlugins", "hoverItems", "hoverPlugins"]
      var parsed
      if (lists.indexOf(key) !== -1 && String(value).trim().charAt(0) !== "[")
        parsed = String(value).split(/\s+/).filter(function(v) { return v !== "" })
      else {
        try { parsed = JSON.parse(value) } catch (e) { parsed = value }
      }
      return root.setNotchSetting(key, parsed) ? "ok" : "unsaved"
    }
    // Read-only: what the focused notch shows and how its settings resolve,
    // for dev/contract.sh to compare before and after the plugin contract.
    // The plugin registry as the notch sees it: every descriptor (without its
    // Components), the effective hide list, and short names resolved to ids.
    function contract(): string {
      return JSON.stringify({
        plugins: root.notchPlugins.list.map(function(p) { return Contract.plain(p) }),
        hiddenConfigured: root.notchHiddenPlugins,
        hiddenEffective: root.notchEffectiveHidden,
        shortNames: {
          compact: root.notchCompactItems.map(Contract.shortToId),
          expanded: root.notchExpandedItems.map(Contract.shortToId),
          hover: root.notchHoverItems.map(Contract.shortToId)
        }
      })
    }
    // Updates: "check" checks now, "now" starts the update, "later" snoozes the
    // version on offer, "dismiss" clears a finished update's notice; any of
    // them, and "status", answer with the update state as JSON.
    // --- the platform ---------------------------------------------------
    //
    // What other plugins integrate, and their panels. Nothing here installs,
    // enables or runs anything: a panel opens, a claim is queued, that's all.

    // Draw an installed widget's own panel inside the notch. `id` is the
    // widget's module name as the layout knows it. Answers "opened", "closed"
    // or "declined:<reason>" -- the same words a plugin acts on.
    function hostPanel(id: string): string {
      var item = root.widgetItemFor(id)
      if (!item) return "declined:no such widget"
      return root.hostPanel(item, "")
    }

    function releasePanel(): string { root.releaseHostedPanel(); return "ok" }

    function hosting(): string { return JSON.stringify(root.hosting.report()) }

    // What Settings → Integrations is showing, so a check can read the same
    // list the user does. `hostable` is the walk done now; `panelHostable` is
    // what the open panel is actually listing, which is a cached copy -- the
    // walk cannot be a binding. They agree only if the panel refreshes when it
    // opens, so a check can hold them against each other.
    function settingsReport(): string {
      // The panel's item outlives its being shown, so this reads the same
      // cache whether it is open or not.
      var panel = null
      for (var i = 0; i < root.notchWindows.length; i++) {
        var item = root.notchWindows[i].settingsItem
        if (item) { panel = item; break }
      }
      return JSON.stringify({ hostable: root.hostableWidgets(), opted: root.notchHostedPanels,
                              integrations: root.platform.list.length,
                              panelHostable: panel ? panel.hostable.length : -1 })
    }

    function integrations(): string { return JSON.stringify(root.platform.report()) }

    // What the notifications source is tracking, and what it has claimed.
    function notifications(): string { return JSON.stringify(root.notificationsSource.report()) }

    // Clear one notification from the notch. Nothing is written and nothing is
    // sent to Omarchy: its own toast runs its own course.
    function dismissNotification(key: string): string {
      return root.notificationsSource.dismiss(String(key)) ? "dismissed" : "no-such-notification"
    }

    // One plugin's view of the notch, for its own service or CLI to read.
    function integration(id: string): string {
      var known = root.platform.reasonFor(id) !== "unknown" || root.platform.accepted(id)
      return JSON.stringify({ id: id, present: true, contract: root.platform.contract,
                              accepted: root.platform.accepted(id),
                              reason: known ? root.platform.reasonFor(id) : "unknown" })
    }

    // Open a plugin's panel on the focused screen: "opened", "closed" or
    // "declined:<reason>".
    function panel(id: string, route: string): string {
      return root.platform.openPanelFor(id, route, "")
    }

    // Ask for a line in the resting notch. An IPC claim can be sent by any
    // process running as this user, so SURFACE-HOSTING.md tells a plugin that warns the
    // user never to hide its own UI on this answer.
    function claim(owner: string, payload: string): string {
      var activity = null
      try { activity = JSON.parse(payload) } catch (e) { return "declined:bad-payload" }
      return root.platform.claimFor(owner, activity, true)
    }

    function release(owner: string, key: string): string { return root.platform.releaseFor(owner, key) }

    function activities(): string { return JSON.stringify(root.platform.activitiesReport()) }

    function rescanIntegrations(): string { return root.platform.rescan() ? "scanning" : "off" }

    // Setup on the focused screen. "status" and "check" only read; "fix",
    // "restore" and "forget" change the machine, so they are refused unless
    // this is a test notch that asked for them (NOTCH_SETUP_IPC_ACTIONS=1) --
    // the live notch changes nothing without a click in the page.
    function setup(action: string, arg: string): string {
      if (action === "check") root.setup.check(false)
      else if (action === "fix" || action === "restore" || action === "forget") {
        if (!(root.harnessed && Quickshell.env("NOTCH_SETUP_IPC_ACTIONS") === "1")) return JSON.stringify({ refused: "ipc" })
        if (action === "fix") root.setup.startFix(arg, "")
        else if (action === "restore") root.setup.startRestore(arg, "")
        else root.setup.forget(arg)
      }
      return JSON.stringify(root.setupReport())
    }

    function update(action: string): string {
      if (action === "check") root.checkForUpdates()
      else if (action === "now") root.startUpdate()
      else if (action === "later") root.snoozeUpdate()
      else if (action === "dismiss") root.ackUpdate()
      return JSON.stringify(root.updateReport())
    }
    // The Plugins page on the focused screen: "open" (or "open:<id>", scrolled
    // to that entry), "close", "refresh" (probe again), or "status"; each
    // answers with the plugins state as JSON. Nothing here installs, updates,
    // enables, sets up or removes anything: that takes a click in the page, and
    // install and update a confirmed card.
    function plugins(action: string): string {
      var w = root.focusedNotchWindow()
      if (action === "open" || action.indexOf("open:") === 0) { if (w) w.openPlugins(action.slice(5)) }
      else if (action === "close") root.closePluginsPages()
      else if (action === "refresh") root.refreshPlugins()
      else if (action !== "status") return JSON.stringify({ error: "unknown action" })
      return JSON.stringify(root.pluginsReport())
    }
    // Test hook (dev/plugins.sh): press a visible button on the focused
    // screen's Plugins page or its notice -- "install:<id>", "confirm",
    // "cancel", "escape", "close", "refresh", "restart", "notice:<button>",
    // or a key, "key:up|down|tab|return|escape" -- through the handler a click
    // or a key press uses. Only a sandboxed test notch accepts it:
    // everything else answers "refused".
    function pluginsPress(button: string): string {
      if (!(root.harnessed && root.pluginsSandboxed)) return "refused"
      var w = root.focusedNotchWindow()
      return w ? w.pressPluginsButton(button) : "no-such-button"
    }
    // Every rounded item in the settings panel and the menu, with the notch's
    // radius, for dev/design.sh (DESIGN-PHILOSOPHY.md, 5).
    function design(): string { var w = root.focusedNotchWindow(); return w ? JSON.stringify(w.designReport()) : "{}" }
    function snapshot(): string { var w = root.focusedNotchWindow(); return w ? JSON.stringify(w.contractSnapshot()) : "{}" }
    function geometry(): string { var w = root.focusedNotchWindow(); return w ? JSON.stringify(w.geometryReport()) : "{}" }
  }

  // Renders one plugin's expandedView: its Component, or the built-in one its
  // key names. Faded in while shown; only then does it take input and focus.
  component ExpandedHost: Loader {
    id: host
    property var plugin: null
    property var builtins: ({})
    property bool shown: false
    readonly property var view: plugin ? plugin.expandedView : null
    y: 0
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0
    sourceComponent: typeof view === "string" ? (builtins[view] || null) : view
    opacity: shown ? 1 : 0
    visible: opacity > 0
    enabled: shown
    Behavior on opacity { NumberAnimation { duration: host.shown ? 220 : 90; easing.type: Easing.OutCubic } }
    onEnabledChanged: if (enabled && item) item.forceActiveFocus()
  }

  component BarPanel: PanelWindow {
    id: barWindow

    visible: !remapGuard.remapping

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    // A full-width transparent strip as tall as the expanded notch (plus room
    // for the spring's overshoot). Only the notch itself takes input; the rest
    // of the strip lets clicks through to the windows underneath.
    anchors {
      top: true
      left: true
      right: true
    }
    // One height, always: the resting notch plus the spring's overshoot, which
    // is what panels that hang from the bar read. The notch's tall shapes --
    // the settings, the menu, the update notice -- are drawn in panelWindow,
    // sized once. Resizing a layer surface makes Hyprland draw its old buffer
    // stretched to the new size for a few frames (measured: 1-5 frames, the
    // blink that looked like a reload), so no surface showing the notch ever
    // changes size.
    readonly property real panelMaxHeight: Math.max(root.notchCompactHeight,
      Math.min(Style.space(620), (barWindow.screen ? barWindow.screen.height : 900) - Style.space(60)))
    implicitHeight: Math.ceil(root.notchExpandedHeight * (1 + root.springOvershoot) + 2)
    color: "transparent"
    surfaceFormat.opaque: false
    // The stock bar's namespace, so Omarchy's own layer rule (no map
    // animation) and any user blur rule written for the bar still apply.
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top
    // The space windows keep clear at the top: the resting height, or nothing
    // when windows reach the top edge (windowsToTop) or the bar is hidden. It
    // depends on settings only, never on whether the notch is open, peeking,
    // hiding or revealed, so using the notch never resizes a window.
    readonly property int reservedZone: root.barHidden || root.notchWindowsToTop ? 0 : Math.ceil(root.notchCompactHeight)
    // A test notch (no host shell, or NOTCH_HARNESS=1) never reserves space on
    // the real screen -- that would move the user's windows while tests run --
    // it only reports the zone it would reserve.
    readonly property bool reservesOnScreen: !!root.shell && !root.harnessed
    // Applied imperatively, zone first and then mode, because of two Quickshell
    // behaviours measured on this system: setting exclusiveZone switches
    // exclusionMode back to Normal, and with the two bound together a change
    // made just after the window is created (when the host hands over
    // shell.json) is reported but never reaches Hyprland, which kept the old
    // 32 px reserved. In this order the change always lands.
    function applyExclusion() {
      var zone = reservesOnScreen ? reservedZone : 0
      exclusiveZone = zone
      exclusionMode = zone > 0 ? ExclusionMode.Normal : ExclusionMode.Ignore
    }
    onReservedZoneChanged: applyExclusion()
    onReservesOnScreenChanged: applyExclusion()

    // Input: the notch itself (unless panelWindow is drawing it), plus the
    // reveal strip while it auto-hides.
    mask: Region {
      item: barWindow.barShapeHidden ? noInput : island
      Region { item: revealZone; intersection: Intersection.Combine }
    }
    Item { id: noInput; width: 0; height: 0 }

    // --- state --------------------------------------------------------------

    property bool hoverExpanded: false
    property bool clickExpanded: false
    // Opened by a keybind (or IPC): it doesn't arm the click-outside focus
    // grab, which Hyprland clears on unrelated focus changes when the pointer
    // is elsewhere. It closes on the keybind again, or once the pointer has
    // been over the notch and left.
    property bool keyExpanded: false
    property bool keyVisited: false
    property bool peeking: false
    property bool mediaReady: false
    property string peekKind: "media"
    // What the open notch shows: "widgets", "clock", "battery", "plugin",
    // "settings" or "menu". Set when it opens and kept while it closes, so the
    // content does not change under a shrinking notch.
    property string view: "widgets"
    // The widget shown by the "plugin" view (the open action's plugin).
    property string viewPlugin: ""
    // The notch grown into its settings panel (long right-click, the
    // "settings" hover action, or IPC). Stays until closed: a click outside,
    // Escape, or the ✕.
    property bool settingsOpen: false
    // The notch grown into the Omarchy menu (menuWith, the menu keybind, the
    // "menu" open action, or IPC). Like the settings, it stays until closed:
    // a picked row, Escape, or a click outside. At most one of the two is open.
    property bool menuOpen: false
    // The notch grown into the Plugins page (Settings → Updates → Manage…, or
    // IPC). Like the menu, it stays until closed. At most one panel is open.
    property bool pluginsOpen: false
    property bool setupOpen: false
    // A plugin's own panel, drawn inside the notch.
    property bool integrationOpen: false
    // Another plugin's own panel, hosted in this notch.
    property bool hostedOpen: false
    property string integrationId: ""
    property string integrationRoute: ""
    // The catalogue entry the page opened on ("" for the top).
    property string pluginsFocusId: ""
    readonly property bool panelOpen: settingsOpen || menuOpen || pluginsOpen || setupOpen || integrationOpen || hostedOpen
    readonly property bool popoutHere: root.activePopout !== null && root.targetBelongsToWindow(root.activePopout, barWindow)
    readonly property bool dragHere: root.barDragSource !== null && root.barDragWindow === barWindow
    // stayOpen: the notch stays open on its open view.
    readonly property bool pinned: root.notchStayOpen && !root.barHidden
    readonly property bool expanded: !root.barHidden
      && (panelOpen || hoverExpanded || clickExpanded || keyExpanded || pinned || popoutHere || dragHere
          || (root.notchForcedExpanded && root.focusedNotchWindow() === barWindow))
    // Auto-hide: tucked into the edge at rest until the pointer reaches the
    // strip above it. Anything that is not rest -- open, peeking, settings --
    // still shows.
    property bool revealed: false
    // An update notice pops down from the resting notch (see "updates"). It
    // shows over auto-hide and peeks; opening the notch covers it.
    // A finished plugin job's notice pops down the same way; the update's wins.
    readonly property bool noticeShown: (root.updateNotice !== "" || root.pluginsNotice !== "") && !root.barHidden
    // The notice kept while the notch shrinks away, so its text doesn't change
    // under it, and which of the two it is.
    property string shownNotice: ""
    property string shownPluginsNotice: ""
    property string noticeKind: "update"
    Connections {
      target: root
      function onUpdateNoticeChanged() {
        if (root.updateNotice !== "") { barWindow.shownNotice = root.updateNotice; barWindow.noticeKind = "update" }
        else if (root.pluginsNotice !== "") barWindow.noticeKind = "plugins"
      }
      function onPluginsNoticeChanged() {
        if (root.pluginsNotice === "") return
        barWindow.shownPluginsNotice = root.pluginsNotice
        if (root.updateNotice === "") barWindow.noticeKind = "plugins"
      }
    }
    // An activity is a line the notch is showing at rest: a notification, or a
    // plugin's own claim. Placement is the binding contract of 18 Sep --
    // symmetric sideways expansion and nothing else -- so this is the peek's
    // geometry with the activity's content, on the same spring and silhouette.
    readonly property var activityLine: root.activityLine
    readonly property bool activityPresent: !root.barHidden && activityLine !== null
    // A notification must never be silently missed: one arriving while the
    // notch is tucked into the edge brings it back out on the existing reveal.
    readonly property bool autoHidden: root.notchAutoHide && !revealed && !expanded && !peeking && !noticeShown && !activityPresent
    readonly property string notchState: root.barHidden || autoHidden ? "hidden" : expanded ? "expanded" : noticeShown ? "notice" : activityPresent ? "activity" : peeking ? "peek" : "compact"

    function collapseNow() {
      expandTimer.stop()
      hoverExpanded = false
      clickExpanded = false
      keyExpanded = false
      keyVisited = false
      if (pinned) showPinnedView()
    }

    function closePanels() {
      settingsOpen = false
      menuOpen = false
      pluginsOpen = false
      setupOpen = false
      integrationOpen = false
      hostedOpen = false
    }

    // The view stayOpen keeps: the open action, or the widgets when that is a panel.
    function showPinnedView() {
      // The flags themselves, not panelOpen: this runs from their change
      // handlers, before panelOpen's binding has caught up.
      if (settingsOpen || menuOpen || pluginsOpen || setupOpen || integrationOpen || hostedOpen) return
      var action = root.notchOpenAction
      if (["widgets", "clock", "battery", "plugin"].indexOf(action) === -1) action = "widgets"
      if (action === "plugin" && !root.notchOpenPlugin) action = "widgets"
      viewPlugin = action === "plugin" ? root.notchOpenPlugin : ""
      view = action
    }
    onPinnedChanged: if (pinned) showPinnedView()

    function openSettings() {
      expandTimer.stop()
      peeking = false
      view = "settings"
      settingsOpen = true
      menuOpen = false
      pluginsOpen = false
      setupOpen = false
      integrationOpen = false
      hostedOpen = false
    }

    // Open the menu at `route` (a menu id or alias; "" is the root menu). A
    // route that names an action runs it without the menu staying open.
    function openMenu(route) {
      openMenuRequest(JSON.stringify({ menu: route || "root" }))
    }

    // Open the menu for a whole Omarchy menu request: a route, or a select or
    // input picker with the files its caller waits on.
    function openMenuRequest(payloadJson) {
      expandTimer.stop()
      peeking = false
      settingsOpen = false
      pluginsOpen = false
      setupOpen = false
      integrationOpen = false
      hostedOpen = false
      view = "menu"
      menuOpen = true
      var menu = menuHost.item
      if (!menu) return false
      menu.open(payloadJson)
      // A route that names an action runs it and never opens.
      if (!menu.opened) menuOpen = false
      return true
    }

    // The menu inside this notch, once its host has loaded it.
    readonly property var menuHostItem: menuHost.item

    // Open the Plugins page, at the entry `focusId` ("" for the top).
    function openPlugins(focusId) {
      expandTimer.stop()
      peeking = false
      settingsOpen = false
      menuOpen = false
      pluginsFocusId = focusId || ""
      view = "plugins"
      pluginsOpen = true
      setupOpen = false
      integrationOpen = false
      hostedOpen = false
    }

    // Setup: what's stopping the notch from working the way you want.
    // `setupOpen` is set before the other flags are cleared, so `panelOpen`
    // never goes false in between -- the notch resizes on its spring instead
    // of collapsing through rest first.
    function openSetup() {
      expandTimer.stop()
      peeking = false
      view = "setup"
      setupOpen = true
      settingsOpen = false
      menuOpen = false
      pluginsOpen = false
      integrationOpen = false
      hostedOpen = false
      if (root.setup) root.setup.check(true)
    }

    // Open another plugin's panel inside this notch, at `route`. Answers the
    // word the plugin acts on: only "opened" means the notch is showing it, so
    // anything else is the plugin's cue to open its own UI.
    function openIntegration(id, route) {
      if (root.barHidden) return "declined:hidden"
      if (!root.platform.accepted(id)) return "declined:not-accepted"
      if (!root.platform.panelFor(id)) return "declined:no-panel"
      if (integrationOpen && integrationId === id && integrationRoute === route) {
        integrationOpen = false
        return "closed"
      }
      expandTimer.stop()
      peeking = false
      settingsOpen = false
      menuOpen = false
      pluginsOpen = false
      setupOpen = false
      integrationId = id
      integrationRoute = String(route || "")
      view = "integration"
      integrationOpen = true
      hostedOpen = false
      if (integrationHost.item && typeof integrationHost.item.open === "function")
        integrationHost.item.open(integrationRoute)
      return "opened"
    }

    // Draw another plugin's own panel in this notch. The content is taken from
    // the plugin's panel and parented into the notch's surface, so the notch
    // grows to it on its own spring and it fades in on the notch's timings --
    // the plugin's window never maps.
    function openHosted(item) {
      var why = root.hosting.reasonNotHostable(item)
      if (why !== "") return "declined:" + why
      if (hostedOpen && root.hosting.widget === item) { hostedOpen = false; return "closed" }
      if (root.hosting.active) root.hosting.giveBack()
      var taken = root.hosting.take(item, hostedSlot)
      if (taken !== "") return "declined:" + taken
      expandTimer.stop()
      peeking = false
      settingsOpen = false
      menuOpen = false
      pluginsOpen = false
      setupOpen = false
      integrationOpen = false
      view = "hosted"
      hostedOpen = true
      return "opened"
    }

    onHostedOpenChanged: {
      if (hostedOpen) return
      hoverExpanded = false
      clickExpanded = false
      keyExpanded = false
      if (pinned) showPinnedView()
      // Given back only once the notch has shrunk past it, so the panel fades
      // with the surface instead of vanishing out of a closing box.
      hostedReturn.restart()
    }

    // The fade out is 90 ms and the shrink 240 (Bar.qml's own timings), so the
    // content stays where it is until both are done.
    Timer {
      id: hostedReturn
      interval: 260
      onTriggered: if (!barWindow.hostedOpen && root.hosting.active) root.hosting.giveBack()
    }

    // Closing keeps `integrationId` and `integrationRoute`: the host is bound to
    // them, and clearing them would destroy the panel mid-shrink, leaving an
    // empty notch closing on an empty box.
    function closeIntegration(id) {
      if (integrationOpen && integrationId === id) integrationOpen = false
    }

    // The open settings panel itself, for settingsReport.
    readonly property var settingsItem: expandedHost.item

    // The settings, opened at one section ("updates").
    function openSettingsSection(name) {
      openSettings()
      if (expandedHost.item && typeof expandedHost.item.revealSection === "function") expandedHost.item.revealSection(name)
    }

    // pluginsPress: a button on this window's Plugins page or its notice.
    function pressPluginsButton(name) {
      var n = String(name)
      if (n === "restart" || n.indexOf("notice:") === 0) {
        var notice = noticeHost.item
        if (noticeKind !== "plugins" || notchState !== "notice" || !notice || typeof notice.press !== "function") return "no-such-button"
        return notice.press(n === "restart" ? "restart" : n.slice(7))
      }
      if (!pluginsOpen || !pluginsHost.item) return "no-such-button"
      return pluginsHost.item.press(n)
    }

    // A press on the notch: open or close the settings, the menu or the
    // widgets, according to which trigger list claims it.
    function trigger(name) {
      if (root.settingsWith(name)) {
        if (settingsOpen) settingsOpen = false
        else openSettings()
        return
      }
      if (root.menuWith(name)) {
        if (menuOpen) menuOpen = false
        else openMenu("root")
        return
      }
      if (panelOpen || !root.opensWith(name)) return
      if (expanded && (clickExpanded || keyExpanded)) collapseNow()
      else openView(root.notchOpenAction, "click")
    }

    // Open `requested` because of a hover or a click (any non-hover trigger).
    // "hover" is the hover view: the hover items next to the hover plugins.
    function openView(requested, how) {
      if (requested === "none") return
      if (requested === "hover" && !root.notchHoverShowsSomething) return
      if (requested === "settings") { openSettings(); return }
      if (requested === "menu") { openMenu("root"); return }
      if (requested === "setup") { openSetup(); return }
      if (requested === "plugins") { openPlugins(""); return }
      // A panel stays put for hovers; a click or a keybind leaves it for this view.
      if (panelOpen) {
        if (how !== "click" && how !== "key") return
        closePanels()
      }
      var plugin = root.notchOpenPlugin
      if (requested === "plugin" && !plugin) requested = "widgets"
      peeking = false
      viewPlugin = requested === "plugin" ? plugin : ""
      view = requested
      if (how === "click") clickExpanded = true
      else if (how === "key") { keyExpanded = true; keyVisited = islandHover.hovered }
      else hoverExpanded = true
    }

    onSettingsOpenChanged: {
      if (settingsOpen) return
      hoverExpanded = false
      clickExpanded = false
      keyExpanded = false
      if (pinned) showPinnedView()
      // Leaving the settings stops any battery preview started there.
      if (root.batterySimulated) { root.batterySimulatedState = ""; root.batterySimulatedPercent = -1 }
    }

    onMenuOpenChanged: {
      if (menuOpen) return
      hoverExpanded = false
      clickExpanded = false
      keyExpanded = false
      if (pinned) showPinnedView()
      // Closed from outside the menu (a click outside, a trigger, IPC).
      if (menuHost.item && menuHost.item.opened) menuHost.item.close()
    }

    onIntegrationOpenChanged: {
      if (integrationOpen) return
      hoverExpanded = false
      clickExpanded = false
      keyExpanded = false
      if (pinned) showPinnedView()
      if (integrationHost.item && typeof integrationHost.item.close === "function") integrationHost.item.close()
    }

    onSetupOpenChanged: {
      if (setupOpen) return
      hoverExpanded = false
      clickExpanded = false
      keyExpanded = false
      if (pinned) showPinnedView()
    }

    onPluginsOpenChanged: {
      if (pluginsOpen) return
      hoverExpanded = false
      clickExpanded = false
      keyExpanded = false
      if (pinned) showPinnedView()
      // A card left open is cancelled by the page once it has faded out, so it
      // never changes under the shrinking notch (NotchPlugins.qml).
    }

    function startPeek(kind) {
      if (expanded) return
      peekKind = kind === "battery" ? "battery" : "media"
      peeking = true
      peekTimer.restart()
    }

    Component.onCompleted: {
      applyExclusion()
      if (pinned) showPinnedView()
      root.registerNotchWindow(barWindow)
      shownWidth = targetWidth * root.seedWidthFraction
      shownHeight = 0
      retarget()
      if (glowOn) { glowFadeAnim.to = 1; glowFadeAnim.duration = root.glowFadeIn; glowFadeAnim.restart() }
    }
    Component.onDestruction: root.unregisterNotchWindow(barWindow)

    Timer {
      id: expandTimer
      interval: root.notchHoverDelay
      // Hover either opens the notch (when it is one of the ways to open it)
      // or shows its own hover view; both close again when the pointer leaves.
      onTriggered: {
        // Not while the update notice is up: the pointer is on its way to a button.
        if (!islandHover.hovered || barWindow.expanded || barWindow.noticeShown) return
        if (root.opensWith("hover")) barWindow.openView(root.notchOpenAction, "hoverOpen")
        else barWindow.openView("hover", "hover")
      }
    }

    Timer {
      id: autoHideTimer
      interval: root.notchCollapseDelay
      onTriggered: if (!islandHover.hovered && !revealHover.hovered) barWindow.revealed = false
    }

    // The top strip above the auto-hidden notch, a little wider than it:
    // reaching for it brings the notch back.
    Item {
      id: revealZone
      readonly property real span: barWindow.compactWidth + 2 * root.notchFilletRadius + Style.space(40)
      x: (barWindow.width - width) / 2
      y: 0
      width: root.notchAutoHide ? span : 0
      height: root.notchAutoHide ? Style.space(3) : 0
      HoverHandler {
        id: revealHover
        enabled: root.notchAutoHide
        onHoveredChanged: {
          if (hovered) { autoHideTimer.stop(); barWindow.revealed = true }
          else autoHideTimer.restart()
        }
      }
    }

    Timer {
      id: collapseTimer
      interval: root.notchCollapseDelay
      onTriggered: {
        if (islandHover.hovered || barWindow.popoutHere || barWindow.dragHere) return
        barWindow.hoverExpanded = false
        if (barWindow.keyVisited) { barWindow.keyExpanded = false; barWindow.keyVisited = false }
        if (barWindow.pinned && !barWindow.panelOpen) barWindow.showPinnedView()
      }
    }

    Timer {
      id: peekTimer
      interval: root.notchPeekDuration
      onTriggered: barWindow.peeking = false
    }

    // A track already playing when the shell starts is not news.
    Timer {
      interval: 2000
      running: true
      onTriggered: barWindow.mediaReady = true
    }

    // --- battery glow -----------------------------------------------------------

    readonly property bool glowOn: root.glowMode !== "none" && !root.barHidden
    // 0 at rest, 1 once the notch is 24 px wider or taller than rest: how far
    // the glow has moved from the resting shape to the open notch's bottom.
    readonly property real glowWiden: Math.max(0, Math.min(1, Math.max(
      (shownWidth - Math.min(maxBarWidth, compactWidth)) / 24,
      (shownHeight - root.notchCompactHeight) / 24)))
    property real glowPresence: 0
    // When the current fade began (ms since epoch), for the report: the fade's
    // progress measured inside the notch, free of IPC latency.
    property real glowFadeStartedAt: 0
    // Follows the glow's colour while it is on, crossfading on a change; held
    // while it fades out, so it does not flash to another colour on the way.
    property color glowColorShown: root.glowColor

    onGlowOnChanged: {
      glowCrossfade.enabled = false
      if (glowOn) glowColorShown = Qt.binding(function() { return root.glowColor })
      else glowColorShown = glowColorShown
      glowCrossfade.enabled = true
      glowFadeAnim.stop()
      glowFadeStartedAt = Date.now()
      glowFadeAnim.to = glowOn ? 1 : 0
      glowFadeAnim.duration = glowOn ? root.glowFadeIn : root.glowFadeOut
      glowFadeAnim.start()
    }
    Behavior on glowColorShown {
      id: glowCrossfade
      ColorAnimation { duration: root.glowCrossfade; easing.type: Easing.InOutQuad }
    }

    NumberAnimation {
      id: glowFadeAnim
      target: barWindow; property: "glowPresence"
      easing.type: Easing.OutCubic
    }

    Connections {
      target: root
      function onBatteryEvent(kind) {
        if (root.notchBatteryPeek) barWindow.startPeek("battery")
      }
    }

    Connections {
      target: root
      function onActivePopoutChanged() {
        if (!barWindow.popoutHere && !islandHover.hovered) collapseTimer.restart()
      }
    }

    // Clicking anywhere outside the settings panel or the menu closes it. While
    // either is open the notch takes keyboard focus -- for Escape, typed
    // numbers, and the menu's search -- which the grab hands it straight away.
    // (Not WlrKeyboardFocus.Exclusive, as Omarchy's menu window uses: Hyprland
    // clears a focus grab that starts in the same frame as an exclusive claim.)
    HyprlandFocusGrab {
      active: barWindow.panelOpen
      windows: [barWindow, barWindow.panelWindow]
      onCleared: barWindow.closePanels()
    }
    // The keyboard goes to panelWindow, where the panels are.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // In click mode, clicking anywhere outside the expanded notch closes it.
    HyprlandFocusGrab {
      active: barWindow.clickExpanded && !barWindow.popoutHere && !barWindow.panelOpen
      windows: [barWindow]
      onCleared: barWindow.clickExpanded = false
    }

    // --- size ---------------------------------------------------------------

    readonly property real maxBarWidth: Math.max(root.notchCompactWidth, width - 2 * (root.notchFilletRadius + Style.space(8)))

    readonly property real compactWidth: Math.max(root.notchCompactWidth,
      compactGlance.empty ? 0 : compactGlance.implicitWidth + 2 * root.notchSidePadding)
    readonly property real peekWidth: Math.max(compactWidth, peekGlance.implicitWidth + 2 * root.notchSidePadding)
    readonly property real activityWidth: Math.max(compactWidth,
      Math.min(560, activityGlance.implicitWidth + 2 * root.notchSidePadding))
    readonly property real rowWidth: Math.max(compactWidth, widgetRow.implicitWidth + 2 * root.notchSidePadding)
    readonly property real clockWidth: Math.max(compactWidth, clockGlance.implicitWidth + 2 * root.notchSidePadding)
    readonly property real batteryWidth: Math.max(compactWidth, batteryGlance.implicitWidth + 2 * root.notchSidePadding)
    readonly property real settingsWidth: Math.max(compactWidth, expandedHost.item ? expandedHost.item.implicitWidth : 0)
    readonly property real settingsHeight: Math.max(root.notchCompactHeight, expandedHost.item ? expandedHost.item.implicitHeight : 0)
    readonly property real menuWidth: Math.max(compactWidth, menuHost.item ? menuHost.item.implicitWidth : 0)
    readonly property real menuHeight: Math.max(root.notchCompactHeight, menuHost.item ? menuHost.item.implicitHeight : 0)
    readonly property real pluginsWidth: Math.max(compactWidth, pluginsHost.item ? pluginsHost.item.implicitWidth : 0)
    readonly property real pluginsHeight: Math.max(root.notchCompactHeight, pluginsHost.item ? pluginsHost.item.implicitHeight : 0)
    readonly property real setupWidth: Math.max(compactWidth, setupHost.item ? setupHost.item.implicitWidth : 0)
    readonly property real setupHeight: Math.max(root.notchCompactHeight, setupHost.item ? setupHost.item.implicitHeight : 0)
    // What the plugin asked its own card for, clamped to what the notch can
    // give it. Side padding matches the notch's other panels.
    readonly property real hostedWidth: Math.max(compactWidth,
      Math.min(maxBarWidth, root.hosting.wantedWidth + 2 * root.notchSidePadding))
    readonly property real hostedHeight: Math.max(root.notchCompactHeight,
      Math.min(panelMaxHeight, root.hosting.wantedHeight + 2 * root.notchSidePadding))
    readonly property real integrationWidth: Math.max(compactWidth, integrationHost.item ? integrationHost.item.implicitWidth : 0)
    readonly property real integrationHeight: Math.max(root.notchCompactHeight,
      Math.min(integrationHost.item ? integrationHost.item.implicitHeight : 0, panelMaxHeight))
    readonly property real noticeWidth: Math.max(compactWidth, noticeHost.item ? noticeHost.item.implicitWidth : 0)
    readonly property real noticeHeight: Math.max(root.notchCompactHeight, noticeHost.item ? noticeHost.item.implicitHeight : 0)
    // The open notch's width for the current view. Widgets and a single plugin
    // are the same row (filtered), so both measure the row.
    readonly property real expandedWidth: view === "settings" ? settingsWidth : view === "menu" ? menuWidth : view === "plugins" ? pluginsWidth
      : view === "setup" ? setupWidth : view === "integration" ? integrationWidth
      : view === "hosted" ? hostedWidth
      : view === "clock" ? clockWidth : view === "battery" ? batteryWidth : rowWidth

    readonly property real targetWidth: Math.min(maxBarWidth,
      notchState === "expanded" ? expandedWidth : notchState === "notice" ? noticeWidth
        : notchState === "activity" ? activityWidth : notchState === "peek" ? peekWidth : compactWidth)
    // Every view but the settings and the menu is one row at the resting
    // height; those grow the notch down, top edge still on the screen edge.
    readonly property real targetHeight: notchState === "hidden" ? 0
      : notchState === "expanded" && view === "settings" ? settingsHeight
      : notchState === "expanded" && view === "menu" ? menuHeight
      : notchState === "expanded" && view === "plugins" ? pluginsHeight
      : notchState === "expanded" && view === "setup" ? setupHeight
      : notchState === "expanded" && view === "integration" ? integrationHeight
      : notchState === "expanded" && view === "hosted" ? hostedHeight
      : notchState === "notice" ? noticeHeight : root.notchCompactHeight

    property real shownWidth: 0
    property real shownHeight: 0

    onTargetWidthChanged: Qt.callLater(retarget)
    onTargetHeightChanged: Qt.callLater(retarget)

    // Start (or restart, from wherever the notch is now) the animation to the
    // current target. Each axis springs when it grows and eases when it
    // shrinks; the width waits 50 ms only when the height is also growing.
    function retarget() {
      var growH = targetHeight > shownHeight + 0.01
      var growW = targetWidth > shownWidth + 0.01
      heightGrow.stop(); heightShrink.stop(); widthGrow.stop(); widthShrink.stop()
      if (Math.abs(targetHeight - shownHeight) > 0.01) {
        var h = growH ? heightGrow : heightShrink
        h.to = targetHeight
        h.start()
      }
      if (Math.abs(targetWidth - shownWidth) > 0.01) {
        if (growW) {
          widthGrowDelay.duration = growH ? root.growWidthDelay : 0
          widthGrowNumber.to = targetWidth
          widthGrow.start()
        } else {
          widthShrink.to = targetWidth
          widthShrink.start()
        }
      }
    }

    NumberAnimation {
      id: heightGrow
      target: barWindow; property: "shownHeight"
      duration: root.growHeightDuration
      easing.type: Easing.BezierSpline
      easing.bezierCurve: root.springCurve
    }
    NumberAnimation {
      id: heightShrink
      target: barWindow; property: "shownHeight"
      duration: root.shrinkDuration
      easing.type: Easing.OutCubic
    }
    SequentialAnimation {
      id: widthGrow
      PauseAnimation { id: widthGrowDelay; duration: 0 }
      NumberAnimation {
        id: widthGrowNumber
        target: barWindow; property: "shownWidth"
        duration: root.growWidthDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.springCurve
      }
    }
    NumberAnimation {
      id: widthShrink
      target: barWindow; property: "shownWidth"
      duration: root.shrinkDuration
      easing.type: Easing.OutCubic
    }

    // Requested radii: the settings, in every state -- growing, hiding and the
    // panels included. They used to scale down with the height while the notch
    // emerged or tucked away, which ended a hide as a sharp-cornered sliver.
    // The Island caps them to what fits instead (bottom corners at most half
    // the height, fillets at most the straight side), so the notch stays
    // rounded all the way into the edge; the top corners stay square and the
    // fillets keep it fused, so it is never a pill.
    readonly property real requestedBottomRadius: root.notchBottomRadius
    readonly property real requestedFilletRadius: root.notchFilletRadius

    // The width the notch is DRAWN at. It is `shownWidth` for all but the last
    // stretch of a hide, and the difference is why a tuck used to end looking
    // sharp.
    //
    // The Island already gives every height the roundest bottom corners that
    // height can hold: `bottomR` is capped to half the height, so a 2 px sliver
    // gets a 1 px radius. Measured against an ideal circle it is exactly right
    // at every height (dev/motion.sh checks the numbers, dev/geometry.sh the
    // pixels). It still reads as a sharp-cornered rule, because the height
    // falls to zero while the width stays at `compactWidth`: the last frames
    // are a 300 px line whose 1 px of curvature is invisible beside it. No
    // radius setting can fix that -- there is no radius left to give.
    //
    // So the width converges too, and by exactly the amount that holds the
    // corner's share of the silhouette constant. Down to `tuckThreshold` --
    // two bottom radii, the height below which the corners stop being a full
    // quarter-circle -- the notch draws at its full width and nothing changes.
    // Below it the Island's cap makes the radius h/2, so scaling the width by
    // the same h/(2R) keeps `bottomR / drawnWidth` at the value it has at
    // rest, at every height. The ends of the tuck are the resting silhouette's
    // ends, scaled: a lozenge withdrawing into the edge rather than a bar
    // flattened against it. At the default size the corner's share stays 6.7%
    // all the way in; before this it fell to 0.7%.
    //
    // Keyed on the height alone, not on the state, so a reveal is the same
    // curve run backwards -- the island grows out of the edge as a lozenge too
    // -- with no width pop at the moment the state flips.
    //
    // Only the drawn shape is tapered. `shownWidth` is untouched, so the
    // animations, the target widths and anything that reads them are as they
    // were; and the widget row is sized from `rowWidth` rather than from the
    // Island, so a narrowed notch clips its content without ever re-measuring
    // it at the tapered width.
    readonly property real tuckThreshold: Math.max(1, 2 * requestedBottomRadius)
    readonly property real tuckWidth: shownWidth * Math.max(0, Math.min(1, shownHeight / tuckThreshold))

    function point(p) { return { x: Number(p.x.toFixed(3)), y: Number(p.y.toFixed(3)) } }

    // The structure of what the notch shows, without anything that changes
    // on its own (clock text, media, battery level): which widgets the row
    // shows, in order, with their widths; which glance items each place
    // resolves to; the pickers' choices; the resolved settings.
    function contractSnapshot() {
      var slots = root.moduleSlots.filter(function(sl) { return root.slotWindow(sl) === barWindow })
      var row = []
      for (var i = 0; i < slots.length; i++) {
        var sl = slots[i]
        if (sl.filteredOut || sl.width <= 0) continue
        var p = sl.mapToItem(widgetRow, 0, 0)
        row.push({ id: root.canonicalWidgetId(sl.moduleName), region: sl.region, x: Math.round(p.x * 100) / 100, w: Math.round(sl.width * 100) / 100 })
      }
      row.sort(function(a, b) { return a.x - b.x })
      var widgetsWidth = 0
      for (var j = 0; j < row.length; j++) widgetsWidth += row[j].w
      return {
        state: notchState, view: view, viewPlugin: viewPlugin, settingsOpen: settingsOpen,
        rowShown: widgetRow.opacity > 0,
        row: row.map(function(r) { return r.id + ":" + r.w }),
        widgetsWidth: Math.round(widgetsWidth * 100) / 100,
        rowFilter: widgetRow.filter,
        glance: {
          compact: root.notchCompactItems, expanded: expandedGlance.visible ? root.notchExpandedItems : [],
          hover: barWindow.view === "hover" ? root.notchHoverItems : [],
          peek: peekGlance.items
        },
        heightIsRest: Math.abs(targetHeight - root.notchCompactHeight) < 0.01,
        settingsPanel: { width: Math.round(settingsWidth * 100) / 100, height: Math.round(settingsHeight * 100) / 100 },
        pickers: root.layoutPluginChoices(),
        resolved: {
          compact: root.notchCompactItems, expanded: root.notchExpandedItems,
          hoverItems: root.notchHoverItems, hoverPlugins: root.notchHoverPlugins,
          hiddenPlugins: root.notchHiddenPlugins, openAction: root.notchOpenAction, openPlugin: root.notchOpenPlugin,
          openWith: root.notchOpenWith, settingsWith: root.notchSettingsWith,
          keys: { open: root.notchOpenKey, settings: root.notchSettingsKey, autoHide: root.notchAutoHideKey },
          autoHide: root.notchAutoHide, windowsToTop: root.notchWindowsToTop,
          glowStyle: root.notchGlowStyle, glowScale: root.notchGlowScale
        }
      }
    }

    // The menu inside the notch, as numbers: whether it is open, where it is,
    // how its card is measured, and what the notch does around it.
    function menuReport() {
      var m = menuHost.item
      return {
        open: menuOpen, loaded: !!m, opened: m ? m.opened : false,
        plugin: menuHost.plugin ? Contract.plain(menuHost.plugin) : null,
        rowsLoaded: m ? m.rowsLoaded : false, activeMenu: m ? m.activeMenu : "",
        rows: m ? m.rowCount : 0, filter: m ? m.filterText : "", lastAction: m ? m.lastAction : "", dryRun: m ? m.dryRun : false,
        selectedIndex: m ? m.selectedIndex : -1,
        rowLabels: m ? m.rowLabels() : [],
        card: m ? {
          width: m.cardWidth, height: m.cardHeight, rowsHeight: m.visibleRowsHeight, rowsCeiling: m.rowsCeiling,
          contentMargin: m.contentMargin, headerHeight: m.headerHeight, contentSpacing: m.contentSpacing,
          baseRowHeight: m.baseRowHeight, rowSpacing: m.rowSpacing, maxWidth: m.maxWidth, maxHeight: m.maxHeight
        } : null,
        host: { opacity: Number(menuHost.opacity.toFixed(3)), enabled: menuHost.enabled, width: menuHost.width, height: menuHost.height },
        // keyboard: what the layer asks for; windowActive: the compositor
        // actually gave the notch keyboard focus; keys: the menu's key
        // handler has Qt's focus inside the notch.
        focus: { keyboard: barWindow.panelWindow.WlrLayershell.keyboardFocus === WlrKeyboardFocus.Exclusive ? "exclusive"
                   : barWindow.panelWindow.WlrLayershell.keyboardFocus === WlrKeyboardFocus.OnDemand ? "onDemand" : "none",
                 windowActive: menuHost.Window.active, keys: m ? m.keysFocused : false },
        background: m ? String(m.background).toUpperCase() : "", notchColor: String(root.notchColor).toUpperCase(),
        colours: m ? {
          text: String(m.foreground), selectedText: String(m.selectedText), selectedBackground: String(m.selectedBackground),
          selectedBorder: String(m.selectedBorder),
          textContrast: Number(root.contrast(m.foreground, m.background).toFixed(2)),
          selectedTextContrast: Number(root.contrast(m.selectedText, m.background).toFixed(2)),
          selectionContrast: Number(root.contrast(Qt.rgba(
            m.background.r * (1 - m.selectedBackground.a) + m.selectedBackground.r * m.selectedBackground.a,
            m.background.g * (1 - m.selectedBackground.a) + m.selectedBackground.g * m.selectedBackground.a,
            m.background.b * (1 - m.selectedBackground.a) + m.selectedBackground.b * m.selectedBackground.a, 1), m.background).toFixed(3))
        } : null,
        appLibrary: m ? { present: !!m.appLibrary, own: m.appLibrary === m.ownLibrary } : null,
        menuWith: root.notchMenuWith, menuKey: root.notchMenuKey,
        // Replacing Omarchy's menu: the setting, whether a companion is talking
        // to this notch, and what it last did.
        replace: { setting: root.notchReplaceMenu, bridged: root.menuCompanion.bridged,
                   companion: root.menuCompanion.companionState, facadeRoute: root.menuCompanion.facadeRoute,
                   anyOpen: root.anyMenuOpen, status: root.menuCompanion.statusKey,
                   actionsEnabled: root.menuCompanion.actionsEnabled, job: root.menuCompanion.job }
      }
    }

    function designReport() {
      return {
        radius: root.notchRadius, bottomRadius: root.notchBottomRadius,
        tooltip: { radius: tooltipBubble.radius, height: tooltipBubble.height },
        settings: expandedHost.item ? root.radiusAudit(expandedHost.item) : [],
        notice: noticeHost.item ? root.radiusAudit(noticeHost.item) : [],
        menu: menuHost.item ? root.radiusAudit(menuHost.item) : [],
        plugins: pluginsHost.item ? root.radiusAudit(pluginsHost.item) : [],
        setup: setupHost.item ? root.radiusAudit(setupHost.item) : [],
        hosted: hostedSlot.children.length > 0 ? root.radiusAudit(hostedSlot) : [],
        integration: integrationHost.item ? root.radiusAudit(integrationHost.item) : []
      }
    }

    // The notch's colours and their contrast, as numbers.
    function coloursReport() {
      function hex(value) { var c = Qt.tint(value, "transparent"); return String(Qt.rgba(c.r, c.g, c.b, 1)).toUpperCase() }
      var settings = expandedHost.item
      return {
        notch: hex(root.notchColor),
        dark: root.notchIsDark, secondary: String(root.notchSecondaryText).toUpperCase(),
        foregroundSetting: String(root.notchSetting("foreground", "")),
        text: hex(root.notchText), foreground: hex(root.notchForeground), accent: hex(root.notchAccent),
        textContrast: Number(root.contrast(root.notchForeground, root.notchColor).toFixed(3)),
        accentContrast: Number(root.contrast(root.notchAccent, root.notchColor).toFixed(3)),
        widgets: { foreground: hex(root.foreground), barForeground: hex(root.barForeground), background: hex(root.background) },
        urgent: hex(root.urgent), hosting: root.hosting.active,
        themeText: hex(Color.bar.text), themeBarBackground: hex(Color.bar.background),
        tooltip: { background: hex(tooltipBubble.color), text: hex(tooltipLabel.color), border: String(tooltipBubble.borderSpec.color).toUpperCase() },
        // Every colour the notch may paint with, apart from its surface and the
        // battery glow. dev/colours.sh asserts none of them has a hue.
        palette: [root.notchForeground, root.notchAccent, root.notchSecondaryText, root.barForeground,
                  tooltipLabel.color, tooltipBubble.borderSpec.color]
          .concat(menuHost.item ? [menuHost.item.selectedBackground, menuHost.item.selectedText, menuHost.item.selectedBorder] : [])
          .concat(settings ? [settings.foreground, settings.accent].concat(settings.painted || []) : [])
          .map(function (c) { return String(c).toUpperCase() }),
        glance: hex(compactGlance.foreground),
        settings: settings ? { foreground: hex(settings.foreground), accent: hex(settings.accent), surface: hex(settings.surface), glowReach: Number(settings.glowReach.toFixed(3)) } : null,
        // What another plugin's panel is actually painting with: it may only use
        // the colours the notch handed it.
        integration: (integrationHost.item && ("background" in integrationHost.item) && ("foreground" in integrationHost.item))
          ? { background: hex(integrationHost.item.background), foreground: hex(integrationHost.item.foreground) } : null,
        selfTest: {
          blackWhite: Number(root.contrast("#000000", "#ffffff").toFixed(3)),
          same: Number(root.contrast("#586e75", "#586e75").toFixed(3)),
          bestOnNotch: Number(Math.max(root.contrast("#ffffff", root.notchColor), root.contrast("#000000", root.notchColor)).toFixed(3)),
          slateOnBlack: Number(root.contrast("#586e75", "#000000").toFixed(3)),
          readableFallbackOnBlack: hex(root.readableOn("#000000", ["#111111"], 7)),
          readableFallbackOnWhite: hex(root.readableOn("#ffffff", ["#eeeeee"], 7))
        }
      }
    }

    function geometryReport() {
      var bx = island.x + island.barX
      function onScreen(p) { return { x: Number((bx + p.x).toFixed(3)), y: Number((island.y + p.y).toFixed(3)) } }
      return {
        screen: { name: barWindow.screen ? barWindow.screen.name : "", width: barWindow.width, height: barWindow.screen ? barWindow.screen.height : 0 },
        state: barWindow.notchState,
        // exclusiveZone: the space kept clear for windows (a test notch only
        // reports it); applied: what the window actually asks Hyprland for.
        panel: { height: barWindow.panelWindow.height, shape: barWindow.panelShape, barShapeHidden: barWindow.barShapeHidden, tall: barWindow.tallShape,
                 keyboard: barWindow.panelWindow.WlrLayershell.keyboardFocus === WlrKeyboardFocus.OnDemand ? "onDemand" : "none" },
        hosted: { open: barWindow.hostedOpen, items: hostedSlot.children.length,
                  width: Number(barWindow.hostedWidth.toFixed(3)), height: Number(barWindow.hostedHeight.toFixed(3)),
                  opacity: Number(hostedHost.opacity.toFixed(3)),
                  report: root.hosting.report() },
        integration: { open: barWindow.integrationOpen, id: barWindow.integrationId, route: barWindow.integrationRoute,
                       loaded: integrationHost.item !== null,
                       itemRoute: integrationHost.item && ("route" in integrationHost.item) ? String(integrationHost.item.route) : "",
                       host: { opacity: Number(integrationHost.opacity.toFixed(3)), enabled: integrationHost.enabled },
                       width: Number(barWindow.integrationWidth.toFixed(3)), height: Number(barWindow.integrationHeight.toFixed(3)),
                       contentWidth: Number(panelContent.width.toFixed(3)), contentHeight: Number(panelContent.height.toFixed(3)) },
        setup: { open: barWindow.setupOpen, width: Number(barWindow.setupWidth.toFixed(3)), height: Number(barWindow.setupHeight.toFixed(3)) },
        open: { key: barWindow.keyExpanded, click: barWindow.clickExpanded, hover: barWindow.hoverExpanded, pinned: barWindow.pinned, stayOpen: root.notchStayOpen },
        window: { height: barWindow.height, exclusiveZone: barWindow.reservedZone, windowsToTop: root.notchWindowsToTop,
                  applied: { zone: barWindow.exclusiveZone, mode: barWindow.exclusionMode === ExclusionMode.Ignore ? "ignore" : "normal", onScreen: barWindow.reservesOnScreen } },
        bar: { x: Number(bx.toFixed(3)), y: island.y, width: Number(island.barWidth.toFixed(3)), height: Number(island.barHeight.toFixed(3)) },
        // The panel window's copy of the shape. The two overlap during the
        // handoff, so they have to agree on every number: one of them drawn
        // from a different width is two notches on screen, and nothing that
        // reads only `bar` can see it.
        panelBar: { width: Number(panelIsland.barWidth.toFixed(3)), height: Number(panelIsland.barHeight.toFixed(3)),
                    bottom: Number(panelIsland.bottomR.toFixed(3)), fillet: Number(panelIsland.fillet.toFixed(3)),
                    painted: barWindow.panelShape },
        target: { width: Number(targetWidth.toFixed(3)), height: Number(targetHeight.toFixed(3)) },
        widgets: {
          rowWidth: widgetRow.implicitWidth, slots: root.moduleSlots.length,
          entries: root.layoutEntries("left").length + root.layoutEntries("center").length + root.layoutEntries("right").length,
          registered: Object.keys(root.barWidgetRegistry.widgets || {}).length,
          emptyWidgets: root.moduleSlots.filter(function(sl) { return root.slotWindow(sl) === barWindow && sl.implicitWidth <= 0 && !sl.filteredOut })
            .map(function(sl) { return sl.moduleName })
        },
        radii: {
          topLeft: islandBody.topLeftRadius, topRight: islandBody.topRightRadius,
          bottomLeft: islandBody.bottomLeftRadius, bottomRight: islandBody.bottomRightRadius,
          bottomRequested: Number(requestedBottomRadius.toFixed(3)),
          fillet: Number(island.fillet.toFixed(3)), filletRequested: Number(requestedFilletRadius.toFixed(3))
        },
        centresBar: {
          leftFillet: point(island.leftFilletCentre), rightFillet: point(island.rightFilletCentre),
          bottomLeft: point(island.bottomLeftCentre), bottomRight: point(island.bottomRightCentre)
        },
        centresScreen: {
          leftFillet: onScreen(island.leftFilletCentre), rightFillet: onScreen(island.rightFilletCentre),
          bottomLeft: onScreen(island.bottomLeftCentre), bottomRight: onScreen(island.bottomRightCentre)
        },
        settingsOpen: barWindow.settingsOpen,
        menu: menuReport(),
        colours: coloursReport(),
        update: {
          notice: root.updateNotice, shownNotice: barWindow.shownNotice, noticeShown: barWindow.noticeShown,
          host: { opacity: Number(noticeHost.opacity.toFixed(3)), enabled: noticeHost.enabled, width: noticeHost.width, height: noticeHost.height },
          size: { width: Number(noticeWidth.toFixed(3)), height: Number(noticeHeight.toFixed(3)) }
        },
        plugins: {
          open: barWindow.pluginsOpen, focusId: barWindow.pluginsFocusId,
          host: { opacity: Number(pluginsHost.opacity.toFixed(3)), enabled: pluginsHost.enabled, width: pluginsHost.width, height: pluginsHost.height },
          size: { width: Number(pluginsWidth.toFixed(3)), height: Number(pluginsHeight.toFixed(3)) },
          // panelContent, which hosts the page: never smaller than it.
          content: { width: Number(panelContent.width.toFixed(3)), height: Number(panelContent.height.toFixed(3)) },
          listHeight: pluginsHost.item ? pluginsHost.item.listHeight : 0,
          heldHeight: pluginsHost.item ? pluginsHost.item.implicitHeight : 0,
          layers: pluginsHost.item ? { list: Number(pluginsHost.item.listOpacity.toFixed(3)), card: Number(pluginsHost.item.cardOpacity.toFixed(3)) } : null,
          motion: pluginsHost.item ? pluginsHost.item.motionSamples : [],
          focus: pluginsHost.item ? pluginsHost.item.focusName : "",
          refreshEnabled: pluginsHost.item ? pluginsHost.item.refreshEnabled : false,
          settingsUpdatesOpen: expandedHost.item ? expandedHost.item.updatesSectionOpen : false,
          scroll: pluginsHost.item ? pluginsHost.item.scrollReport() : null,
          notice: root.pluginsNotice, shownNotice: barWindow.shownPluginsNotice, noticeKind: barWindow.noticeKind,
          card: pluginsHost.item ? pluginsHost.item.carding : false, selected: pluginsHost.item ? pluginsHost.item.selectedIndex : -1,
          foreground: pluginsHost.item ? String(pluginsHost.item.foreground).toUpperCase() : "",
          surface: pluginsHost.item ? String(pluginsHost.item.surface).toUpperCase() : "",
          updateButtons: {
            settings: expandedHost.item ? expandedHost.item.updateButtonEnabled : null,
            notice: noticeHost.item && barWindow.noticeKind === "update" ? noticeHost.item.updateButtonEnabled : null
          }
        },
        media: {
          facade: !!root.mediaService,
          activeKey: root.mediaPlayerKey(root.mediaPlayer),
          glance: { key: root.mediaPlayerKey(compactGlance.player), title: compactGlance.trackTitle, hasMedia: compactGlance.hasMedia, playing: compactGlance.playing, width: compactGlance.implicitWidth },
          peekKey: root.mediaPlayerKey(peekGlance.player),
          mediaPeek: barWindow.peeking && barWindow.peekKind === "media",
          widgets: root.moduleSlots.filter(function(sl) { return root.slotWindow(sl) === barWindow && root.canonicalWidgetId(sl.moduleName) === "omarchy.media" })
            .map(function(sl) { var it = sl.activeItem; return { key: it && it.activePlayer !== undefined ? root.mediaPlayerKey(it.activePlayer) : null, title: it && it.title !== undefined ? it.title : null } })
        },
        autoHide: { on: root.notchAutoHide, revealed: barWindow.revealed, hidden: barWindow.autoHidden, revealZone: { width: revealZone.width, height: revealZone.height } },
        pointer: { overNotch: islandHover.hovered, tooltip: root.tooltipShown ? root.tooltipText : "", hoveredWidgets: root.moduleSlots.filter(function(sl) { return root.slotWindow(sl) === barWindow && sl.hovered }).map(function(sl) { return sl.moduleName }) },
        view: barWindow.view,
        hoverItems: root.notchHoverItems,
        openWith: root.notchOpenWith, settingsWith: root.notchSettingsWith,
        keys: { open: root.notchOpenKey, settings: root.notchSettingsKey, autoHide: root.notchAutoHideKey, stayOpen: root.notchStayOpenKey, applied: root.appliedKeys, lastLua: root.lastKeybindLua },
        hiddenPlugins: root.notchHiddenPlugins, hoverPlugins: root.notchHoverPlugins, openAction: root.notchOpenAction, openPlugin: root.notchOpenPlugin, viewPlugin: barWindow.viewPlugin,
        battery: {
          percent: root.batteryPercent, mode: root.batteryMode, simulated: root.batterySimulated,
          greenAbove: root.notchGreenAbove, looksFull: root.batteryLooksFull,
          lowThreshold: root.notchLowBattery, criticalThreshold: root.notchCriticalBattery
        },
        glow: {
          mode: root.glowMode, color: String(barWindow.glowColorShown).toUpperCase(),
          fadeElapsedMs: glowFadeStartedAt > 0 ? Date.now() - glowFadeStartedAt : -1,
          presence: Number(glowPresence.toFixed(4)),
          curve: {
            style: root.notchGlowStyle,
          outlineDrawn: glow.visible, bottomDrawn: bottomGlow.visible, openDrawn: openGlow.visible,
          widen: Number(glowWiden.toFixed(3)),
          open: { width: Number(openGlow.barWidth.toFixed(3)), height: Number(openGlow.barHeight.toFixed(3)), bottomRadius: Number(openGlow.bottomRadius.toFixed(3)), presence: Number(openGlow.presence.toFixed(3)) },
          bottom: {
            strength: bottomGlow.strength, reach: Number(bottomGlow.reach.toFixed(3)),
            alphaAt: [[0, 0], [0, 0.5], [0, 0.9], [glow.knots[1].d, 0], [glow.knots[2].d, 0], [bottomGlow.reach, 0]].map(function(p) {
              return { d: Number(p[0].toFixed(3)), u: p[1], alpha: Number(bottomGlow.alphaAt(p[0], p[1]).toFixed(4)) }
            })
          },
          scale: root.notchGlowScale, sizeBase: Number(glow.sizeBase.toFixed(3)), size: Number(glow.reach.toFixed(3)), knots: glow.knots.map(function(n) { return { d: Number(n.d.toFixed(3)), a: n.a } }),
            alphaAt: glow.knots.map(function(n) { return n.d }).concat([glow.reach + 10]).map(function(d) { return { d: Number(d.toFixed(3)), alpha: Number(glow.alphaAt(d).toFixed(4)), shown: Number((glow.alphaAt(d) * glowPresence).toFixed(4)) } })
          },
          window: { namespace: "omarchy-notch-glow", height: glowWindow.height, input: "none" },
          roomBelowBar: Number((glowWindow.height - glow.barHeight).toFixed(3)),
          shape: { width: Number(glow.barWidth.toFixed(3)), height: Number(glow.barHeight.toFixed(3)), bottomRadius: Number(glow.bottomRadius.toFixed(3)), fillet: Number(glow.filletRadius.toFixed(3)) },
          colours: { charging: String(root.notchChargingColor).toUpperCase(), full: String(root.notchFullColor).toUpperCase(), low: String(root.notchLowColor).toUpperCase() },
          fadeInMs: root.glowFadeIn, fadeOutMs: root.glowFadeOut, fadeEasing: "OutCubic",
          crossfadeMs: root.glowCrossfade, crossfadeEasing: "InOutQuad"
        },
        motion: {
          springDamping: root.springDamping, springPeakAt: root.springPeakAt,
          springOvershoot: Number(root.springOvershoot.toFixed(5)),
          growHeightMs: root.growHeightDuration, growWidthDelayMs: root.growWidthDelay,
          growWidthMs: root.growWidthDuration, shrinkMs: root.shrinkDuration,
          seedWidthFraction: root.seedWidthFraction, springCurve: root.springCurve
        }
      }
    }

    // --- the shape and what is in it ------------------------------------------

    // The glow lives in a window of its own, under this one. This window's
    // height is read by panels that hang from the bar (the clock, the weather)
    // and must stay the notch's own, while the glow needs 80 px of room below
    // the open notch to fall all the way to zero. That window is sized once
    // for the open notch plus the glow's full reach and never resizes, so the
    // glow is never cut off and nothing reflows when it turns on or off. It
    // takes no input, and it has its own layer namespace so a blur rule
    // written for the bar cannot draw a blurred edge inside the falloff.
    property PanelWindow glowWindow: PanelWindow {
      screen: barWindow.screen
      visible: barWindow.visible
      anchors { top: true; left: true; right: true }
      // Sized once for the tallest the notch can grow (its settings panel)
      // plus the largest glow the setting allows, so nothing ever resizes it.
      implicitHeight: Math.ceil(Math.max(root.notchCompactHeight, barWindow.panelMaxHeight) * (1 + root.springOvershoot) + glow.maxReach + glow.pad + 16)
      color: "transparent"
      surfaceFormat.opaque: false
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "omarchy-notch-glow"
      WlrLayershell.layer: WlrLayer.Top
      mask: Region {}

      // The glow follows the resting notch, not the open one: its width eases
      // to the resting width, and its height is the notch's height only while
      // that is at or below rest (so it still grows out of the edge with the
      // notch, and slides away with it when hidden).
      Glow {
        id: glow
        readonly property real restWidth: Math.min(barWindow.maxBarWidth, barWindow.compactWidth)
        Behavior on barWidth { NumberAnimation { duration: root.shrinkDuration; easing.type: Easing.OutCubic } }
        x: (barWindow.width - barWidth) / 2
        y: 0
        barWidth: restWidth
        barHeight: Math.max(0, Math.min(barWindow.shownHeight, root.notchCompactHeight))
        bottomRadius: Math.max(0, Math.min(root.notchBottomRadius, barWidth / 2, barHeight / 2))
        filletRadius: Math.max(0, Math.min(root.notchFilletRadius, barHeight - bottomRadius))
        color: barWindow.glowColorShown
        // Drawn only in the outline style, not at all at glow size 0, and
        // handed over to the open-notch glow as the notch widens.
        presence: root.notchGlowStyle === "outline" && root.notchGlowScale > 0 ? barWindow.glowPresence * (1 - barWindow.glowWiden) : 0
        // Relative to the resting notch's size: glowScale × √(width × height),
        // calibrated so the default 180 × 32 notch reaches 32 px at 1.0 --
        // a wider or taller notch glows further. Never past the 80 px the
        // window leaves room for.
        readonly property real sizeBase: Math.sqrt(Math.max(0, barWidth) * Math.max(0, barHeight)) * 32 / Math.sqrt(180 * 32)
        size: Math.max(1, Math.min(glow.maxReach, root.notchGlowScale * sizeBase))
      }

      // The subtle style: same resting shape, size and fade, only under the
      // bottom edge. Its own component and shader, so the outline glow is
      // untouched.
      BottomGlow {
        id: bottomGlow
        x: glow.x
        y: 0
        barWidth: glow.barWidth
        barHeight: glow.barHeight
        bottomRadius: glow.bottomRadius
        color: barWindow.glowColorShown
        presence: root.notchGlowStyle === "bottom" && root.notchGlowScale > 0 ? barWindow.glowPresence * (1 - barWindow.glowWiden) : 0
        size: glow.size
      }

      // When the notch widens or grows past rest, the glow moves to the
      // bottom of the notch as it is now, whichever style is set at rest:
      // the bottom glow, following the live width, height and corner radius.
      // It takes over from the resting glow over the first 24 px of growth.
      BottomGlow {
        id: openGlow
        x: island.x + island.barX
        y: 0
        barWidth: island.barWidth
        barHeight: island.barHeight
        bottomRadius: island.bottomR
        color: barWindow.glowColorShown
        presence: root.notchGlowScale > 0 ? barWindow.glowPresence * barWindow.glowWiden : 0
        size: glow.size
      }
    }

    Island {
      id: island

      x: (barWindow.width - width) / 2
      y: 0
      // Never hidden, even at zero height (where it draws nothing): widgets
      // created inside a hidden item -- as they are when the bar is reloaded
      // with the widget registry already filled -- measure zero wide and stay
      // that way, which leaves the open notch with an empty row.
      barWidth: Math.max(0, barWindow.tuckWidth)
      barHeight: Math.max(0, barWindow.shownHeight)
      bottomRadius: barWindow.requestedBottomRadius
      filletRadius: barWindow.requestedFilletRadius
      // Transparent while panelWindow draws the shape (see the handoff).
      color: barWindow.barShapeHidden ? "transparent" : root.notchColor

      HoverHandler {
        id: islandHover
        onHoveredChanged: {
          root.setBarHovered(hovered)
          if (hovered && barWindow.keyExpanded) barWindow.keyVisited = true
          if (hovered) {
            collapseTimer.stop()
            autoHideTimer.stop()
            if (root.opensWith("hover") || root.notchHoverShowsSomething) expandTimer.restart()
          } else {
            expandTimer.stop()
            collapseTimer.restart()
            if (root.notchAutoHide) autoHideTimer.restart()
          }
        }
        Component.onDestruction: if (hovered) root.setBarHovered(false)
      }

      // Presses on the notch itself (widgets take their own first). Each one
      // goes to whichever of `openWith` / `settingsWith` claims it.
      TapHandler {
        acceptedButtons: Qt.LeftButton
        longPressThreshold: 0.45
        onSingleTapped: barWindow.trigger("click")
        onDoubleTapped: barWindow.trigger("doubleClick")
        onLongPressed: barWindow.trigger("longPress")
      }

      // Declared before the content, so a widget's own right- or middle-click
      // still wins over these.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.MiddleButton
        pressAndHoldInterval: 450
        onClicked: function(mouse) { barWindow.trigger(mouse.button === Qt.MiddleButton ? "middleClick" : "rightClick") }
        onPressAndHold: function(mouse) { if (mouse.button === Qt.RightButton) barWindow.trigger("longRightClick") }
      }

      // Scrolling down opens, scrolling up closes.
      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          if (!root.opensWith("scroll") || barWindow.panelOpen) return
          if (event.angleDelta.y < 0 && !barWindow.expanded) barWindow.openView(root.notchOpenAction, "click")
          else if (event.angleDelta.y > 0 && barWindow.expanded) barWindow.collapseNow()
        }
      }

      // The bar's content is laid out at full expanded size, centred on the
      // bar, and clipped by it -- so widgets never move while the notch
      // resizes around them, and popups anchor to the same place every time.
      Item {
        id: content
        width: Math.max(barWindow.rowWidth, barWindow.peekWidth, barWindow.clockWidth,
                        barWindow.batteryWidth, barWindow.activityWidth)
        height: root.notchCompactHeight
        x: (island.barWidth - width) / 2
        y: 0

        // The activity line. One row at the resting height, centred: the notch
        // widens around it and nothing else moves (DESIGN-PHILOSOPHY.md, 1).
        ActivityGlance {
          id: activityGlance
          bar: root
          activity: barWindow.activityLine
          x: (content.width - width) / 2
          width: implicitWidth
          height: root.notchCompactHeight
          opacity: barWindow.notchState === "activity" ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }

        Glance {
          player: root.mediaPlayer
          id: compactGlance
          x: (content.width - width) / 2
          width: implicitWidth
          height: root.notchCompactHeight
          items: root.notchCompactItems
          foreground: root.notchForeground
          batteryPercent: root.batteryPercent
          batteryCharging: root.batteryCharging
          batteryColor: root.batteryLooksFull ? root.notchFullColor
            : root.batteryMode === "charging" ? root.notchChargingColor
            : root.batteryMode === "critical" || root.batteryMode === "low" ? root.notchLowColor : root.notchForeground
          fontFamily: root.fontFamily
          fontSize: Style.font.body
          opacity: barWindow.notchState === "compact" ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }

        Glance {
          player: root.mediaPlayer
          id: peekGlance
          x: (content.width - width) / 2
          width: implicitWidth
          height: root.notchCompactHeight
          items: root.notchCompactItems.indexOf(barWindow.peekKind) === -1 ? root.notchCompactItems.concat([barWindow.peekKind]) : root.notchCompactItems
          foreground: root.notchForeground
          batteryPercent: root.batteryPercent
          batteryCharging: root.batteryCharging
          batteryColor: root.batteryLooksFull ? root.notchFullColor
            : root.batteryMode === "charging" ? root.notchChargingColor
            : root.batteryMode === "critical" || root.batteryMode === "low" ? root.notchLowColor : root.notchForeground
          fontFamily: root.fontFamily
          fontSize: Style.font.body
          opacity: barWindow.notchState === "peek" ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

          // Read the player itself, not hasMedia/playing: those are bindings on
          // the same change and can still hold the previous player's values
          // when this runs -- which made a player going away (null) peek.
          onTrackTitleChanged: {
            var p = player
            if (root.notchPeekOnTrackChange && barWindow.mediaReady && p && p.trackTitle && p.isPlaying)
              barWindow.startPeek("media")
          }
        }

        Glance {
          player: root.mediaPlayer
          id: hoverGlanceProbe
          opacity: 0
          enabled: false
          items: root.notchHoverItems
          batteryPercent: root.batteryPercent
          fontFamily: root.fontFamily
          fontSize: Style.font.body
        }

        Glance {
          player: root.mediaPlayer
          id: expandedGlanceProbe
          opacity: 0
          enabled: false
          items: root.notchExpandedItems
          batteryPercent: root.batteryPercent
          fontFamily: root.fontFamily
          fontSize: Style.font.body
        }

        // Every widget from the bar layout, left | center | glance | right, in
        // the same row as the resting notch's content. Always loaded, so
        // widgets keep their services and their width is known before the
        // notch opens; hidden and inert while it is closed.
        //
        // The "plugin" and "hover" views are this same row with the widgets
        // they do not show collapsed, so a widget is never loaded twice. The
        // filter is a space-separated list of the widget ids to keep, padded
        // with spaces; " " keeps none, "" keeps all but the hidden ones.
        Row {
          id: widgetRow
          readonly property bool rowView: barWindow.view === "widgets" || barWindow.view === "plugin" || barWindow.view === "hover"
          readonly property string filter: barWindow.view === "plugin" ? " " + barWindow.viewPlugin + " "
            : barWindow.view === "hover" ? " " + root.notchHoverPlugins.join(" ") + " "
            : ""
          x: (content.width - width) / 2
          y: 0
          height: root.notchCompactHeight
          spacing: filter ? 0 : root.notchSectionGap
          opacity: barWindow.notchState === "expanded" && rowView ? 1 : 0
          enabled: barWindow.expanded && rowView

          // The hover view's time, date, media and battery, ahead of its
          // plugins, with a gap between them when there are both.
          Item {
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool shown: barWindow.view === "hover" && hoverGlanceProbe.implicitWidth > 0
            visible: shown
            width: shown ? hoverGlance.implicitWidth + (root.notchHoverPlugins.length > 0 ? root.notchSectionGap : 0) : 0
            height: root.notchCompactHeight
            Glance {
              player: root.mediaPlayer
              id: hoverGlance
              width: implicitWidth
              height: parent.height
              items: root.notchHoverItems
              foreground: root.notchForeground
              batteryPercent: root.batteryPercent
              batteryCharging: root.batteryCharging
              batteryColor: root.batteryLooksFull ? root.notchFullColor
                : root.batteryMode === "charging" ? root.notchChargingColor
                : root.batteryMode === "critical" || root.batteryMode === "low" ? root.notchLowColor : root.notchForeground
              fontFamily: root.fontFamily
              fontSize: Style.font.body
            }
          }

          Behavior on opacity { NumberAnimation { duration: barWindow.expanded ? 220 : 90; easing.type: Easing.OutCubic } }

          LeftModules { anchors.verticalCenter: parent.verticalCenter; filter: widgetRow.filter }
          ModuleList {
            anchors.verticalCenter: parent.verticalCenter
            entries: root.layoutEntries("center")
            region: "center"
            filter: widgetRow.filter
          }
          Glance {
            player: root.mediaPlayer
            id: expandedGlance
            anchors.verticalCenter: parent.verticalCenter
            // Hidden while it has nothing to show, so the row has no empty gap.
            // Whether it has anything is read from a copy outside the row: a
            // hidden item's own content measures as empty, and would stay hidden.
            visible: expandedGlanceProbe.implicitWidth > 0 && !widgetRow.filter
            width: implicitWidth
            height: root.notchCompactHeight
            items: root.notchExpandedItems
            foreground: root.notchForeground
            batteryPercent: root.batteryPercent
            batteryCharging: root.batteryCharging
            batteryColor: root.batteryLooksFull ? root.notchFullColor
              : root.batteryMode === "charging" ? root.notchChargingColor
              : root.batteryMode === "critical" || root.batteryMode === "low" ? root.notchLowColor : root.notchForeground
            fontFamily: root.fontFamily
            fontSize: Style.font.body
          }
          RightModules { anchors.verticalCenter: parent.verticalCenter; filter: widgetRow.filter }
        }

        // While the row is not interactive (at rest, peeking, another view) this
        // hover-only cover keeps the pointer away from its hidden widgets:
        // being disabled does not stop their hover handlers, so they would
        // light up and show tooltips under a closed notch. It takes no buttons,
        // so presses still reach the notch's own handlers.
        MouseArea {
          x: widgetRow.x
          y: widgetRow.y
          width: widgetRow.width
          height: widgetRow.height
          visible: !widgetRow.enabled
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
        }

        Glance {
          player: root.mediaPlayer
          id: clockGlance
          x: (content.width - width) / 2
          width: implicitWidth
          height: root.notchCompactHeight
          items: ["clock", "date"]
          foreground: root.notchForeground
          fontFamily: root.fontFamily
          fontSize: Style.font.body
          opacity: barWindow.notchState === "expanded" && barWindow.view === "clock" ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }

        Glance {
          player: root.mediaPlayer
          id: batteryGlance
          x: (content.width - width) / 2
          width: implicitWidth
          height: root.notchCompactHeight
          items: ["battery"]
          foreground: root.notchForeground
          batteryPercent: root.batteryPercent
          batteryCharging: root.batteryCharging
          batteryColor: root.batteryLooksFull ? root.notchFullColor
            : root.batteryMode === "charging" ? root.notchChargingColor
            : root.batteryMode === "critical" || root.batteryMode === "low" ? root.notchLowColor : root.notchForeground
          fontFamily: root.fontFamily
          fontSize: Style.font.body
          opacity: barWindow.notchState === "expanded" && barWindow.view === "battery" ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }

      }
    }

    // --- the panel window ----------------------------------------------------------
    //
    // The notch's tall shapes: the settings, the menu and the update notice. A
    // surface sized once for the tallest the notch can grow, drawing the same
    // Island from the same tuckWidth/shownHeight as the bar window, so the bar
    // window never changes height. The width must be the DRAWN one, not
    // shownWidth: the two windows overlap during the handoff, and a panelIsland
    // at full width behind a tapered bar island is two notches on screen. It takes input only where the shape is and
    // only while it draws it, and the keyboard while a panel is open.
    //
    // Handoff: while the notch is tall (a panel or the notice is up, or it is
    // still shrinking from one) panelWindow draws the shape and the bar
    // window's shape is transparent. Both are identical at the resting size,
    // where they swap, and they overlap for a moment instead of leaving a gap.
    readonly property bool tallShape: panelOpen || notchState === "notice"
      || shownHeight > root.notchCompactHeight * (1 + root.springOvershoot) + 1
    property bool panelShape: false
    property bool barShapeHidden: false
    onTallShapeChanged: {
      if (tallShape) panelShape = true
      else barShapeHidden = false
      shapeHandoff.restart()
    }
    Timer {
      id: shapeHandoff
      interval: 50
      onTriggered: {
        if (barWindow.tallShape) barWindow.barShapeHidden = true
        else barWindow.panelShape = false
      }
    }

    property PanelWindow panelWindow: PanelWindow {
      screen: barWindow.screen
      visible: barWindow.visible
      anchors { top: true; left: true; right: true }
      implicitHeight: Math.ceil(barWindow.panelMaxHeight * (1 + root.springOvershoot) + 2)
      color: "transparent"
      surfaceFormat.opaque: false
      exclusionMode: ExclusionMode.Ignore
      // The bar's namespace, for Omarchy's no-animation layer rule.
      WlrLayershell.namespace: "omarchy-bar"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: barWindow.panelOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
      mask: Region { item: barWindow.panelShape ? panelIsland : panelNoInput }
      Item { id: panelNoInput; width: 0; height: 0 }

      Island {
        id: panelIsland
        x: (barWindow.width - width) / 2
        y: 0
        barWidth: Math.max(0, barWindow.tuckWidth)
        barHeight: Math.max(0, barWindow.shownHeight)
        bottomRadius: barWindow.requestedBottomRadius
        filletRadius: barWindow.requestedFilletRadius
        color: barWindow.panelShape ? root.notchColor : "transparent"

        // The same presses as on the bar window's notch, for the notice's
        // background and a long right-click on a panel.
        TapHandler {
          acceptedButtons: Qt.LeftButton
          longPressThreshold: 0.45
          onSingleTapped: barWindow.trigger("click")
          onDoubleTapped: barWindow.trigger("doubleClick")
          onLongPressed: barWindow.trigger("longPress")
        }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.RightButton | Qt.MiddleButton
          pressAndHoldInterval: 450
          onClicked: function(mouse) { barWindow.trigger(mouse.button === Qt.MiddleButton ? "middleClick" : "rightClick") }
          onPressAndHold: function(mouse) { if (mouse.button === Qt.RightButton) barWindow.trigger("longRightClick") }
        }

        // Laid out at full size, centred on the notch and clipped by it, and
        // revealed as the notch grows.
        Item {
          id: panelContent
          width: Math.max(barWindow.settingsWidth, barWindow.menuWidth, barWindow.pluginsWidth, barWindow.setupWidth,
                          barWindow.integrationWidth, barWindow.hostedWidth, barWindow.noticeWidth)
          height: Math.max(root.notchCompactHeight, barWindow.settingsHeight, barWindow.menuHeight, barWindow.pluginsHeight,
                           barWindow.setupHeight, barWindow.integrationHeight, barWindow.hostedHeight, barWindow.noticeHeight)
          x: (panelIsland.barWidth - width) / 2
          y: 0

          // The expanded-view hosts: each renders one plugin's expandedView
          // inside the notch, which grows around it -- a Component a plugin
          // declares, or a built-in key the notch resolves
          // (builtinExpandedViews). notch.settings and notch.menu have one.
          // Laid out at full size and revealed as the notch grows.
          ExpandedHost {
            id: expandedHost
            plugin: root.notchPlugins.byId["notch.settings"] || null
            builtins: barWindow.builtinExpandedViews
            shown: barWindow.settingsOpen
            x: (panelContent.width - width) / 2
          }
          // The update notice, revealed as the notch pops down around it.
          Loader {
            id: noticeHost
            x: (panelContent.width - width) / 2
            y: 0
            width: item ? item.implicitWidth : 0
            height: item ? item.implicitHeight : 0
            sourceComponent: barWindow.noticeKind === "plugins" ? pluginsNoticeView : updateNoticeView
            opacity: barWindow.notchState === "notice" ? 1 : 0
            visible: opacity > 0
            enabled: barWindow.notchState === "notice"
            Behavior on opacity { NumberAnimation { duration: barWindow.notchState === "notice" ? 220 : 90; easing.type: Easing.OutCubic } }
          }
          ExpandedHost {
            id: menuHost
            plugin: root.notchPlugins.byId["notch.menu"] || null
            builtins: barWindow.builtinExpandedViews
            shown: barWindow.menuOpen
            x: (panelContent.width - width) / 2
          }
          // The Plugins page. Not a contract built-in: a plain descriptor.
          ExpandedHost {
            id: pluginsHost
            plugin: ({ id: "notch.plugins", expandedView: "plugins" })
            builtins: barWindow.builtinExpandedViews
            shown: barWindow.pluginsOpen
            x: (panelContent.width - width) / 2
          }
          // The Setup page, the same way.
          ExpandedHost {
            id: setupHost
            plugin: ({ id: "notch.setup", expandedView: "setup" })
            builtins: barWindow.builtinExpandedViews
            shown: barWindow.setupOpen
            x: (panelContent.width - width) / 2
          }
          // Another plugin's OWN panel, taken out of its window and drawn here.
          // It fades on the notch's timings like every other view, and is given
          // back untouched when it closes (PanelHosting.qml).
          Item {
            id: hostedHost
            width: barWindow.hostedWidth
            height: barWindow.hostedHeight
            x: (panelContent.width - width) / 2
            opacity: barWindow.hostedOpen ? 1 : 0
            visible: opacity > 0
            enabled: barWindow.hostedOpen
            Behavior on opacity { NumberAnimation { duration: barWindow.hostedOpen ? 220 : 90; easing.type: Easing.OutCubic } }

            // The notch's own side padding, so a hosted panel sits in the
            // surface the way the notch's own panels do.
            Item {
              id: hostedSlot
              anchors.fill: parent
              anchors.margins: root.notchSidePadding
            }
          }

          // Another plugin's panel. Its Component comes from that plugin's own
          // integration file; the notch hands it everything it may use.
          ExpandedHost {
            id: integrationHost
            plugin: ({ id: "notch.integration", expandedView: root.platform.panelFor(barWindow.integrationId) })
            builtins: barWindow.builtinExpandedViews
            shown: barWindow.integrationOpen
            x: (panelContent.width - width) / 2
            onLoaded: {
              var panel = integrationHost.item
              if (!panel) return
              if ("surfaceHost" in panel) panel.surfaceHost = root.platform.hostFor(barWindow.integrationId)
              if ("surfaceScreen" in panel) panel.surfaceScreen = barWindow.screen ? barWindow.screen.name : ""
              if ("route" in panel) panel.route = Qt.binding(function () { return barWindow.integrationRoute })
              if ("maxWidth" in panel) panel.maxWidth = Qt.binding(function () { return barWindow.maxBarWidth - 2 * root.notchSidePadding })
              if ("maxHeight" in panel) panel.maxHeight = Qt.binding(function () { return barWindow.panelMaxHeight })
              if (panel.closeRequested) panel.closeRequested.connect(function () { barWindow.integrationOpen = false })
              if (typeof panel.open === "function" && barWindow.integrationOpen) panel.open(barWindow.integrationRoute)
            }
          }
        }
      }
    }

    // Built-in expandedView keys, resolved by the expanded-view hosts.
    readonly property var builtinExpandedViews: ({ settings: settingsExpandedView, menu: menuExpandedView,
      plugins: pluginsExpandedView, setup: setupExpandedView })
    Component {
      id: settingsExpandedView
      NotchSettings {
        bar: root
        headerHeight: root.notchCompactHeight
        maxHeight: barWindow.panelMaxHeight
        glowReach: glow.reach
        onCloseRequested: barWindow.settingsOpen = false
        onSetupRequested: barWindow.openSetup()
      }
    }
    Component {
      id: updateNoticeView
      NotchUpdate {
        bar: root
        notice: barWindow.shownNotice
      }
    }
    Component {
      id: pluginsExpandedView
      NotchPlugins {
        bar: root
        window: barWindow
        headerHeight: root.notchCompactHeight
        maxHeight: barWindow.panelMaxHeight
        focusId: barWindow.pluginsFocusId
        onCloseRequested: barWindow.pluginsOpen = false
        onBackRequested: barWindow.openSetup()
      }
    }
    Component {
      id: setupExpandedView
      NotchSetup {
        bar: root
        headerHeight: root.notchCompactHeight
        maxHeight: barWindow.panelMaxHeight
        onCloseRequested: barWindow.setupOpen = false
        onBackRequested: barWindow.openSettings()
        onPluginsRequested: barWindow.openPlugins("")
      }
    }
    Component {
      id: pluginsNoticeView
      NotchPluginsNotice {
        bar: root
        window: barWindow
        notice: barWindow.shownPluginsNotice
      }
    }
    Component {
      id: menuExpandedView
      NotchMenu {
        bar: root
        maxWidth: barWindow.maxBarWidth - 2 * root.notchSidePadding
        maxHeight: barWindow.panelMaxHeight
        onCloseRequested: barWindow.menuOpen = false
      }
    }

    // The Island's own bar Rectangle, for reading its corner radii back.
    readonly property Item islandBody: island.body

    PopupWindow {
      id: tooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      anchor {
        id: tooltipAnchor
        window: barWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, barWindow)) return

          var popupWidth = tooltipWindow.implicitWidth
          var localX = target.width / 2 - popupWidth / 2
          var localY = target.height + 6
          var point = barWindow.contentItem.mapFromItem(target, localX, localY)
          tooltipAnchor.rect.x = Math.round(point.x)
          tooltipAnchor.rect.y = Math.round(point.y)
        }
      }

      // A tooltip hangs off the notch, so it is the notch's: its surface, its
      // text, its radius. The theme's tooltip colours never reach it.
      BorderSurface {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 20
        implicitHeight: tooltipLabel.implicitHeight + 14
        color: root.notchColor
        borderSpec: Border.flat(Util.alpha(root.notchForeground, Style.normalBorderAlpha), 1)
        radius: root.radiusFor(height)

        Text {
          id: tooltipLabel
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.tooltipText
          color: root.notchForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  component DragGhostPanel: PanelWindow {
    id: ghostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barDragScreen === ghostScreen ||
      (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
    readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
    readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
    readonly property int ghostPadding: Style.space(1)
    readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
    readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

    visible: active && sourceItem !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-drag-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only drag feedback. Keep the input region empty so the ghost can
    // sit under the cursor without stealing the MouseArea's active pointer grab.
    mask: Region {}

    Item {
      visible: ghostWindow.visible
      x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
      y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
      width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
      height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

      BorderSurface {
        anchors.fill: parent
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        radius: root.radiusFor(height)
        opacity: root.transparent ? 0.45 : 0.94
      }

      Image {
        anchors.fill: parent
        anchors.margins: ghostWindow.ghostPadding
        source: root.barDragImageUrl
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.84
      }
    }

    Rectangle {
      readonly property var targetRect: root.barDragTargetGeometry

      visible: ghostWindow.active && targetRect !== null
      x: targetRect ? Math.round(targetRect.x) : 0
      y: targetRect ? Math.round(targetRect.y) : 0
      width: targetRect ? targetRect.width : 0
      height: targetRect ? targetRect.height : 0
      color: root.barForeground
      radius: Math.min(width, height) / 2
    }
  }

  component BarMoveGhostPanel: PanelWindow {
    id: moveGhostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barMoveScreen === ghostScreen ||
      (root.barMoveScreen && ghostScreen && root.barMoveScreen.name && ghostScreen.name && root.barMoveScreen.name === ghostScreen.name)
    visible: root.barMoveActive && screenMatches
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-move-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only preview of the candidate edge. Keep the input region empty
    // so the overlay never steals the gesture area's active pointer grab.
    mask: Region {}

    // One fixed-geometry slab per edge, crossfaded on candidate changes.
    // Resizing a single slab between edges repaints mid-transition and
    // flickers; fading between static ones does not.
    Repeater {
      model: ["top", "bottom", "left", "right"]

      BorderSurface {
        id: edgeSlab

        required property string modelData
        readonly property bool edgeVertical: modelData === "left" || modelData === "right"
        readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

        x: modelData === "right" ? parent.width - edgeSize : 0
        y: modelData === "bottom" ? parent.height - edgeSize : 0
        width: edgeVertical ? edgeSize : parent.width
        height: edgeVertical ? parent.height : edgeSize
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        visible: opacity > 0
        opacity: root.barMoveCandidate === modelData ? (root.transparent ? 0.45 : 0.7) : 0

        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component LeftModules: ModuleList {
    entries: root.layoutEntries("left")
    region: "left"
  }

  component RightModules: ModuleList {
    entries: root.layoutEntries("right")
    region: "right"
  }

  component CenterModules: Item {
    id: centerRoot

    property var entries: root.layoutEntries("center")
    readonly property bool hasAnchor: root.entryIndex(entries, root.centerAnchor) !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry()

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.bottom: centerAnchorModule.top
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.top: centerAnchorModule.bottom
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }
      }
    }
  }

  component CenterGestureArea: MouseArea {
    id: gestureArea

    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property real dragThreshold: Style.space(4)

    acceptedButtons: Qt.LeftButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
    pressAndHoldInterval: 200

    function startDrag(x, y) {
      if (dragging) return
      dragging = true
      root.beginBarMove(root.targetWindow(gestureArea))
      var scenePoint = gestureArea.mapToItem(null, x, y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
    }

    onPressAndHold: function(mouse) {
      // A widget above us propagates its composed press-and-hold down here without
      // ever handing over the grab, so we'd get no release or cancel to end the move.
      if (!gestureArea.pressed) return
      startDrag(mouse.x, mouse.y)
    }

    onPositionChanged: function(mouse) {
      if (!(mouse.buttons & Qt.LeftButton)) return

      if (!dragging) {
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance < dragThreshold) return
        startDrag(mouse.x, mouse.y)
        return
      }

      var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onReleased: function(mouse) {
      if (!dragging) return
      dragging = false
      suppressClick = true
      root.finishBarMove()
      mouse.accepted = true
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      root.clearBarMove()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
      }
    }

    onDoubleClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (mouse.button === Qt.LeftButton) {
        root.toggleTransparency()
        mouse.accepted = true
      }
    }
  }

  component ModuleList: Loader {
    id: moduleListRoot

    property var entries: []
    property string region: ""
    // A widget id: only that widget is shown. Empty: every widget.
    property string filter: ""

    visible: entries.length > 0
    // A hidden list must not build its modules. The center section declares
    // both an anchored and an unanchored arrangement and shows whichever
    // fits, so leaving the other one loaded mounts every center module
    // twice — two IPC handlers registered for the same target, two clocks
    // ticking, two of every timer and fetch behind them.
    active: visible && entries.length > 0
    sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0

    Component {
      id: horizontalModuleList

      Row {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
            filter: moduleListRoot.filter
          }
        }
      }
    }

    Component {
      id: verticalModuleList

      Column {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
            filter: moduleListRoot.filter
          }
        }
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    property string filter: ""
    readonly property string moduleName: root.entryId(entry)
    // Left out of the row -- everything but the chosen widget in a
    // single-plugin view, or a widget in `hiddenPlugins` in the full row. Kept
    // loaded and visible (a hidden widget can stop measuring or drop its
    // state), but zero width, clipped and inert.
    readonly property bool filteredOut: filter !== ""
      ? filter.indexOf(" " + root.canonicalWidgetId(moduleName) + " ") === -1
      : root.notchEffectiveHidden.indexOf(root.canonicalWidgetId(moduleName)) !== -1
    clip: filteredOut
    enabled: !filteredOut
    opacity: filteredOut ? 0 : 1
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property string customType: root.customModuleType(entry)
    readonly property var registryMetadata: root.barWidgetRegistry.metadataFor(root.canonicalWidgetId(moduleName))
    readonly property bool firstParty: registryMetadata && registryMetadata.firstParty === true
    readonly property string pluginApiId: registered ? root.canonicalWidgetId(moduleName) : "bar-entry:" + moduleName
    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      if (customType) return null
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }
    readonly property bool hovered: moduleHover.hovered
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool panelOpen: root.activePopout === slot.activeItem
    // Modules bigger than the mark they want (a text label in a padded slot,
    // a multi-line stack on a vertical bar) can say how long the open-panel
    // dot should be along the bar, so it tracks what the module paints
    // instead of a fraction of whatever slot it happens to fill.
    readonly property real panelIndicatorExtent: {
      var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
      return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55))
    }
    implicitWidth: filteredOut ? 0 : activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    z: modulePointer.dragging ? 100 : 0

    Component.onCompleted: root.registerModuleSlot(slot)
    Component.onDestruction: {
      if (root.barDragSource === slot) root.clearBarDrag()
      root.unregisterModuleSlot(slot)
    }

    HoverHandler { id: moduleHover }

    // A widget the user has asked to see inside the notch: its click is taken
    // here, before it reaches the widget's own button, so the plugin's
    // controller never opens and its window never maps. Everything else about
    // the widget -- hover, tooltip, scroll, its other buttons -- is untouched,
    // and a click the notch cannot serve is passed straight on.
    TapHandler {
      enabled: root.hostsPanelOf(slot.moduleName) && !slot.filteredOut && !!slot.activeItem
      acceptedButtons: Qt.LeftButton
      gesturePolicy: TapHandler.ReleaseWithinBounds
      onSingleTapped: function (point, button) {
        var answer = root.hostPanel(slot.activeItem, root.slotScreenName(slot))
        // Not something the notch could draw: let the widget do what it always
        // does, rather than swallowing the click.
        if (answer.indexOf("declined") === 0 && slot.activeItem && typeof slot.activeItem.toggle === "function")
          slot.activeItem.toggle()
      }
    }

    // A plugin can open its own panel without going through its bar icon: its
    // own keybind, or `omarchy-shell <plugin> open`. Nothing the notch can
    // intercept comes first, so it watches the plugin's own open state instead
    // and takes the panel the moment it goes up -- in the same turn, because
    // `open` is what maps the plugin's window, and a Timer would show it for a
    // frame. This also catches a click the notch's own handler did not win.
    Connections {
      target: root.hostsPanelOf(slot.moduleName) ? slot.panelController : null
      enabled: !!target
      ignoreUnknownSignals: true
      function onOpenChanged() {
        if (!target || target.open !== true) return
        if (root.hosting.widget === slot.activeItem && root.hosting.active) { target.open = false; return }
        if (root.hostPanel(slot.activeItem, root.slotScreenName(slot)) === "opened") target.open = false
      }
    }

    BorderSurface {
      visible: slot.dragSource
      anchors.fill: parent
      anchors.margins: Style.space(1)
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: root.radiusFor(height)
      opacity: root.transparent ? 0.22 : 0.32
    }

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Rectangle {
      id: openPanelIndicator

      readonly property int inset: Style.space(2)

      visible: opacity > 0
      opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
      // The notch's white, like every other mark on it (DESIGN-PHILOSOPHY.md, 2).
      color: root.barForeground
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
      height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
      // The mark sits on the module's inner edge — the one facing the
      // desktop — so it underlines a top bar, overlines a bottom one, and
      // points inward from a left or right one. It reads as pointing at the
      // panel that opens on that side.
      x: root.vertical
        ? (root.position === "left" ? parent.width - width - inset : inset)
        : Math.round((parent.width - width) / 2)
      y: root.vertical
        ? Math.round((parent.height - height) / 2)
        : (root.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      enabled: slot.visible && slot.width > 0 && slot.height > 0
      propagateComposedEvents: true
      cursorShape: root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Do not assign drag.target here: ModuleSlot is owned by Row/Column
      // positioners, and mutating slot.x/slot.y can leave stale offsets that
      // make neighboring modules overlap after a small aborted drag.

      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
      }

      onPositionChanged: function(mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
            root.barDragOffsetX = pressedX
            root.barDragOffsetY = pressedY
            root.captureBarDragGhost(slot)
            root.barDragSource = slot
          }
          dragging = true
          root.hideTooltip(slot.activeItem)
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var screenPoint = root.barDragScreenPoint(scenePoint)
          root.barDragSceneX = scenePoint.x
          root.barDragSceneY = scenePoint.y
          root.barDragScreenX = screenPoint.x
          root.barDragScreenY = screenPoint.y

          var drop = root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
          root.barDragTargetGeometry = drop ? root.dropMarkerRect(drop.slot, drop.after) : null
        }
      }

      onReleased: function(mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter

        if (wasDragging) suppressClick = true

        dragging = false
        root.clearBarDrag()

        if (wasDragging && targetSlot) {
          root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
      }
    }

    onModuleSettingsChanged: injectProps()

    // The widget's own panel controller, resolved once when the widget loads.
    // As a binding it walked every widget's children on every pass -- QML warns
    // that `data` is not bindable, 70 times per start -- and the answer only
    // ever changes when the widget itself does. The second pass catches a panel
    // whose own Loader finishes after the widget's root does.
    property var panelController: null
    function resolvePanelController() { slot.panelController = root.hosting.controllerOf(slot.activeItem) }

    onActiveItemChanged: {
      Qt.callLater(injectProps)
      resolvePanelController()
      Qt.callLater(resolvePanelController)
    }

    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = firstParty
        ? root : root.pluginBarApiFor(pluginApiId, moduleName, registered)
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
      // A widget of a plugin that integrates gets its own notch host, and the
      // screen this copy of it is on, so a click opens the panel on the right
      // monitor. Under another bar neither property is ever set.
      if ("surfaceHost" in target && pluginApiId) target.surfaceHost = root.platform.hostFor(pluginApiId)
      if ("surfaceScreen" in target) target.surfaceScreen = root.slotScreenName(slot)
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { entry: slot.entry }
    }
  }

  component CustomCommandModule: WidgetButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var settings: root.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = Util.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    bar: root
    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function(button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command) root.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: root.runProcess(customProc)
    }
  }
}
