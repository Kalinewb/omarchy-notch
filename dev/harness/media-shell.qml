import QtQuick
import Quickshell
import Quickshell.Io
import "notch" as Notch

// The real Bar.qml with a fake host facade whose omarchy.media proxy is
// scripted over IPC, and the real stock media bar widget in the row
// (/usr/share/omarchy/shell/plugins/services/media/BarWidget.qml, via
// $NOTCH_MEDIA_WIDGET). Used by dev/media.sh.
//
//   quickshell ipc -p <dir> call notchtest player <key> <title> <true|false>   (adds or updates)
//   quickshell ipc -p <dir> call notchtest clear
//   quickshell ipc -p <dir> call notchtest active <key|"">
//   quickshell ipc -p <dir> call notchtest retitle <key> <title>
//
// $NOTCH_FAKE_FACADE=0 starts it with no omarchy.media proxy at all.
ShellRoot {
  id: shellRoot

  property var fakePlayers: []

  Component {
    id: fakePlayerComponent
    QtObject {
      property string dbusName: ""
      property string identity: ""
      property string trackTitle: ""
      property string trackArtist: ""
      property string trackArtUrl: ""
      property bool isPlaying: false
      property bool canTogglePlaying: true
      property bool canPlay: true
      property bool canPause: true
      property bool canGoNext: true
      property bool canGoPrevious: true
    }
  }

  QtObject {
    id: fakeMedia
    property var activePlayer: null
    property var sourcePlayers: []
    function playerKey(player) { return player ? String(player.dbusName || player.identity || "") : "" }
    function runAction(action, showFeedback, playerId) {}
    function selectPlayer(playerId) {}
  }

  QtObject {
    id: fakeShell
    function firstPartyServiceFor(id) {
      return id === "omarchy.media" && Quickshell.env("NOTCH_FAKE_FACADE") !== "0" ? fakeMedia : null
    }
    function pluginShellForBarEntry(ownerId, moduleName) { return null }
  }

  function playerFor(key) {
    for (var i = 0; i < fakePlayers.length; i++) if (fakePlayers[i].dbusName === key) return fakePlayers[i]
    return null
  }

  IpcHandler {
    target: "notchtest"
    // One call per player: Quickshell IPC splits arguments on commas, so a
    // JSON list can't be passed in one argument.
    function clear(): string {
      shellRoot.fakePlayers = []
      fakeMedia.sourcePlayers = []
      fakeMedia.activePlayer = null
      return "0"
    }
    function player(key: string, title: string, playing: string): string {
      var p = shellRoot.playerFor(key)
      var fresh = !p
      if (fresh) p = fakePlayerComponent.createObject(shellRoot)
      p.dbusName = key
      p.identity = key
      p.trackTitle = title
      p.isPlaying = playing === "true"
      if (fresh) {
        shellRoot.fakePlayers = shellRoot.fakePlayers.concat([p])
        fakeMedia.sourcePlayers = shellRoot.fakePlayers
      }
      return String(shellRoot.fakePlayers.length)
    }
    function active(key: string): string {
      fakeMedia.activePlayer = key ? shellRoot.playerFor(key) : null
      return fakeMedia.activePlayer ? fakeMedia.playerKey(fakeMedia.activePlayer) : ""
    }
    function retitle(key: string, title: string): string {
      var p = shellRoot.playerFor(key)
      if (p) p.trackTitle = title
      return p ? p.trackTitle : ""
    }
  }

  Component {
    id: mediaWidget
    Loader { }
  }

  QtObject {
    id: registry
    property int revision: 1
    property var mediaComponent: Qt.createComponent(Quickshell.env("NOTCH_MEDIA_WIDGET"))
    property var widgets: ({ "omarchy.media": { component: mediaComponent, metadata: { displayName: "Media", firstParty: true } } })
    function metadataFor(id) { var e = widgets[String(id)]; return e ? e.metadata : null }
    function availableIds() { return Object.keys(widgets) }
    function has(id) { return widgets[String(id)] !== undefined }
  }

  Notch.Bar {
    shell: fakeShell
    barWidgetRegistry: registry
    barConfig: ({
      position: "top",
      transparent: false,
      layout: { left: [], center: [{ id: "omarchy.media" }], right: [] },
      notch: JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}")
    })
  }
}
