import QtQuick
import Quickshell

// The information the notch can show without any widget: time, date and what
// is playing. Used for the compact notch (empty by default, so the notch stays
// pitch black) and for the top row of the expanded notch.
//
// `items` is an ordered list of "clock", "date", "media" and "battery". An
// item with nothing to show (media with no player, battery on a desktop)
// takes no space.
Item {
  id: root

  property var items: []
  property color foreground: "#ffffff"
  property color dimForeground: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  property string fontFamily: "monospace"
  property int fontSize: 12
  property string clockFormat: "HH:mm"
  property string dateFormat: "ddd d MMM"
  property int mediaMaxWidth: 240
  property int spacing: 14
  // Whether the equaliser may dance here. The bar says no for the resting
  // glance, which is on screen the whole time nobody is touching the notch;
  // see the bars below.
  property bool animate: true
  // Fed by the bar, so a simulated battery shows here too. -1: no battery.
  property int batteryPercent: -1
  property bool batteryCharging: false
  property color batteryColor: foreground

  // What is playing: the notch's one media source, omarchy.media's
  // activePlayer, handed in by the bar (the same player the stock media widget
  // shows). Null -- no facade, or nothing playing -- means no media item.
  property var player: null
  readonly property string trackTitle: player ? (player.trackTitle || "") : ""
  readonly property string trackArtist: player ? (player.trackArtist || "") : ""
  readonly property bool hasMedia: trackTitle !== ""
  readonly property bool playing: !!player && player.isPlaying

  readonly property bool empty: row.implicitWidth <= 0

  implicitWidth: row.implicitWidth
  implicitHeight: Math.max(fontSize + 8, 18)

  function has(name) {
    return Array.isArray(items) && items.indexOf(name) !== -1
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: root.spacing

    Repeater {
      model: Array.isArray(root.items) ? root.items : []

      Loader {
        required property var modelData
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        sourceComponent: modelData === "clock" ? clockItem
          : modelData === "date" ? dateItem
          : modelData === "media" ? mediaItem
          : modelData === "battery" ? batteryItem
          : null
        visible: item !== null && item.implicitWidth > 0
        width: visible ? item.implicitWidth : 0
        height: visible ? item.implicitHeight : 0
      }
    }
  }

  Component {
    id: clockItem
    Text {
      text: Qt.formatDateTime(clock.date, root.clockFormat)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.weight: Font.DemiBold
    }
  }

  Component {
    id: dateItem
    Text {
      text: Qt.formatDateTime(clock.date, root.dateFormat)
      color: root.dimForeground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }
  }

  Component {
    id: batteryItem
    Item {
      implicitWidth: root.batteryPercent >= 0 ? batteryRow.implicitWidth : 0
      implicitHeight: batteryRow.implicitHeight
      visible: root.batteryPercent >= 0

      Row {
        id: batteryRow
        spacing: 6

        // A drawn battery: outline, nub, fill to the charge, bolt while charging.
        Item {
          width: 22
          height: 11
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            id: batteryCase
            width: 20
            height: parent.height
            radius: 3
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
          }
          Rectangle {
            x: 20.5
            width: 1.5
            height: 4
            radius: 0.75
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
          }
          Rectangle {
            x: 2
            y: 2
            height: parent.height - 4
            width: Math.max(1.5, (batteryCase.width - 4) * Math.max(0, Math.min(100, root.batteryPercent)) / 100)
            radius: 1.5
            color: root.batteryColor
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
          }
          Canvas {
            anchors.centerIn: batteryCase
            width: 8
            height: 11
            // The bolt fades rather than vanishing when charging stops.
            opacity: root.batteryCharging ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            onVisibleChanged: requestPaint()
            Component.onCompleted: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.beginPath()
              ctx.moveTo(5, 0); ctx.lineTo(1, 6); ctx.lineTo(4, 6)
              ctx.lineTo(3, 11); ctx.lineTo(7, 5); ctx.lineTo(4, 5)
              ctx.closePath()
              ctx.fillStyle = "#ffffff"
              ctx.strokeStyle = "#000000"
              ctx.lineWidth = 1
              ctx.stroke()
              ctx.fill()
            }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.batteryPercent + "%"
          color: root.batteryCharging || root.batteryColor !== root.foreground ? root.batteryColor : root.dimForeground
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          font.weight: Font.DemiBold
        }
      }
    }
  }

  Component {
    id: mediaItem
    Item {
      implicitWidth: root.hasMedia ? mediaRow.implicitWidth : 0
      implicitHeight: mediaRow.implicitHeight
      visible: root.hasMedia

      Row {
        id: mediaRow
        spacing: 7

        Rectangle {
          width: root.fontSize + 4
          height: width
          radius: 4
          color: Qt.rgba(1, 1, 1, 0.12)
          anchors.verticalCenter: parent.verticalCenter
          clip: true

          Image {
            anchors.fill: parent
            source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 64
            sourceSize.height: 64
          }
        }

        Text {
          width: Math.min(implicitWidth, root.mediaMaxWidth)
          anchors.verticalCenter: parent.verticalCenter
          text: root.trackArtist ? root.trackTitle + "  ·  " + root.trackArtist : root.trackTitle
          elide: Text.ElideRight
          color: root.playing ? root.foreground : root.dimForeground
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
        }

        // Three bars that stand still when paused -- and when nobody is
        // looking.
        //
        // Measured on a resting notch with the media in its glance: 10.85 % of
        // a core with something playing, 2.00 % with it paused, same state,
        // same screen. Three 2 px bars are not expensive to draw; what costs
        // is that anything moving at all repaints the notch's surface at 60 Hz
        // for as long as it moves, and the compositor composites every one of
        // those frames. A notch nobody is touching has to cost nothing, so at
        // rest the bars hold a still equaliser shape -- which still reads as
        // playing -- and they dance when the notch is hovered, peeked or open.
        //
        // Nine Glances exist at once: the resting one, the peek, the hover
        // row, the expanded row, the clock and battery views, the activity
        // line, and two invisible probes the notch measures widths with. On
        // `playing` alone, all nine ran an infinite animation whenever
        // anything was playing -- including the ones behind a hidden notch and
        // the probes that are never drawn. Twenty-seven bars kept Qt's
        // animation driver, and with it the shell's render loop, awake at
        // 60 Hz to move nothing: about 10 % of a core in the shell, and as
        // much again in the compositor compositing the frames. A notch nobody
        // is touching should cost what an idle Quickshell costs.
        //
        // `visible` is effective -- false when any ancestor is hidden, which
        // is how the notch turns each of these off -- and `opacity > 0`
        // catches the two probes, which stay visible on purpose because a Row
        // measures no width through an invisible child.
        Row {
          spacing: 2
          anchors.verticalCenter: parent.verticalCenter
          Repeater {
            model: 3
            Rectangle {
              id: bar
              required property int index
              // The shape they hold when they are not dancing: uneven, so it
              // reads as an equaliser standing still rather than as three
              // bars nobody finished.
              readonly property var restLevels: [0.45, 0.9, 0.6]
              readonly property bool dancing: root.playing && root.animate
                && root.visible && root.opacity > 0
              width: 2
              radius: 1
              color: root.foreground
              anchors.verticalCenter: parent.verticalCenter
              // Off the animated `level` only while it is animating: a binding
              // that reads it at rest would be re-evaluated for a value that
              // never changes, and the height would jump when it stopped.
              height: root.playing ? 4 + (root.fontSize - 4) * (dancing ? level : restLevels[index]) : 3
              property real level: 0.5
              SequentialAnimation on level {
                running: bar.dancing
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 260 + index * 90; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.2; duration: 300 + index * 70; easing.type: Easing.InOutSine }
              }
            }
          }
        }
      }
    }
  }
}
