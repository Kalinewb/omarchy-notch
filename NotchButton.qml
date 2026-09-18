import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Omarchy's Ui/Button.qml (4.0.3) for the notch. The one change: every fill
// and border is the notch's text colour at the theme's alpha, never a colour
// the theme picked. Upstream routes them through Style's state tokens, and a
// theme may pin those to its own colour (Catppuccin Latte pins all four to
// #4c4f69), which put a grey-blue switch and grey-blue outlines on the black
// notch (DESIGN-PHILOSOPHY.md, 2). The theme still decides widths and alphas.
// The verbatim upstream file is dev/upstream/ui/Button.qml.
//
// States compose independently and are applied in priority order:
//
//   pressed (mouse down)         pressed fill
//   activeFocus (Tab focus)      focus fill + focus border token
//   hasCursor || hover           hover-cursor fill (+ border if `bordered`)
//   selected                     selected fill + optional selected border
//   active                       selected fill
//   idle                         transparent or normal border if `bordered`
//
// Alphas and border widths come from `qs.Commons.Style` tokens; colours
// come from `foreground` alone.
//
// Emits `hovered(bool)` so panels with their own keyboard cursor model
// can update state on mouse enter/leave.
BorderSurface {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""

  // State flags (see comment above for paint priority).
  property bool selected: false
  property bool active: false
  property bool hasCursor: false
  property bool focusable: false
  property bool bordered: false

  // Colours. The defaults are the notch's palette; `accent` is kept for
  // callers and is the foreground on the notch anyway.
  property color foreground: "#ffffff"
  property color background: "transparent"
  property color accent: foreground

  // Sizing.
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real iconSize: Style.font.icon
  property real iconRotation: 0
  property bool iconSpinning: false
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY
  property bool leftAlign: false

  leftPadding: horizontalPadding
  rightPadding: horizontalPadding
  topPadding: verticalPadding
  bottomPadding: verticalPadding

  // Tooltip palette. Auto-rendered if tooltipText is set. Defaults pull
  // from [tooltip] in shell.toml; override per-instance only when a button
  // intentionally wants a tooltip that diverges from the theme.
  property color tooltipBackground: "#000000"
  property color tooltipForeground: foreground
  property color tooltipBorder: Util.alpha(foreground, Style.normalBorderAlpha)

  signal clicked()
  signal rightClicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  // Reserve the largest border any visual state can paint. Otherwise a
  // borderless idle button grows by a pixel per side on hover/focus and
  // relayouts neighboring controls.
  implicitWidth: row.implicitWidth + horizontalPadding * 2 + _reservedBorderLeft + _reservedBorderRight
  implicitHeight: row.implicitHeight + verticalPadding * 2 + _reservedBorderTop + _reservedBorderBottom
  radius: Style.cornerRadius

  readonly property bool hot: mouseArea.containsMouse || hasCursor
  readonly property bool _showFocusRing: focusable && activeFocus
  readonly property color _selectedColor: root.foreground
  // The theme's widths for each state, in the notch's colour at the theme's alpha.
  function notchSpec(state, alpha) {
    var themed = Border.controlSpec(state, root.foreground, root.foreground)
    return { color: Util.alpha(root.foreground, alpha), widths: themed.widths, gradient: { colors: [], angle: 0, enabled: false } }
  }
  readonly property var _tooltipBorderSpec: Border.flat(root.tooltipBorder, Math.max(1, Style.normalBorderWidth))
  readonly property var _focusBorderSpec: notchSpec("focus", Style.focusBorderAlpha)
  readonly property var _hoverBorderSpec: notchSpec("hover-cursor", Style.hoverBorderAlpha)
  readonly property var _selectedBorderSpec: notchSpec("selected", Style.selectedBorderAlpha)
  readonly property var _normalBorderSpec: notchSpec("normal", Style.normalBorderAlpha)
  // What this button paints when selected or hovered (dev/colours.sh: no hue).
  readonly property color selectedFill: Util.alpha(root.foreground, Style.selectedFillAlpha)
  readonly property color hoverFill: Util.alpha(root.foreground, Style.hoverFillAlpha)
  readonly property real _reservedBorderTop: Math.max(
    focusable ? Border.top(_focusBorderSpec) : 0,
    Border.top(_hoverBorderSpec),
    Border.top(_selectedBorderSpec),
    bordered ? Border.top(_normalBorderSpec) : 0)
  readonly property real _reservedBorderRight: Math.max(
    focusable ? Border.right(_focusBorderSpec) : 0,
    Border.right(_hoverBorderSpec),
    Border.right(_selectedBorderSpec),
    bordered ? Border.right(_normalBorderSpec) : 0)
  readonly property real _reservedBorderBottom: Math.max(
    focusable ? Border.bottom(_focusBorderSpec) : 0,
    Border.bottom(_hoverBorderSpec),
    Border.bottom(_selectedBorderSpec),
    bordered ? Border.bottom(_normalBorderSpec) : 0)
  readonly property real _reservedBorderLeft: Math.max(
    focusable ? Border.left(_focusBorderSpec) : 0,
    Border.left(_hoverBorderSpec),
    Border.left(_selectedBorderSpec),
    bordered ? Border.left(_normalBorderSpec) : 0)
  readonly property real _reservedContentLeftInset: _reservedBorderLeft + leftPadding
  readonly property var _borderSpec: _showFocusRing ? _focusBorderSpec
    : hot                      ? _hoverBorderSpec
    : selected                 ? (Border.controlHasWidth("selected") ? _selectedBorderSpec : (bordered ? _normalBorderSpec : Border.none()))
    : bordered                 ? _normalBorderSpec
    : Border.none()

  color: mouseArea.pressed ? Util.alpha(root.foreground, Style.pressedFillAlpha)
    : _showFocusRing       ? Util.alpha(root.foreground, Style.focusFillAlpha)
    : hot                  ? hoverFill
    : selected             ? selectedFill
    : active               ? selectedFill
    : background

  // Border follows the same state precedence as fill. Buttons stay
  // borderless at rest unless `bordered` is set, but hover-cursor/focus
  // always use the shared cursor border so the keyboard target is visible
  // and consistent with the rest of the kit. Selected borders are off by
  // default for plain buttons; explicitly bordered buttons keep their
  // normal border when selected unless selected-border-width opts in to a
  // dedicated selected border.
  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: 120 } }

  ToolTip {
    visible: root.tooltipText !== "" && mouseArea.containsMouse
    text: root.tooltipText
    delay: 400
    padding: 0
    background: BorderSurface {
      color: root.tooltipBackground
      borderSpec: root._tooltipBorderSpec
      radius: 0
    }
    contentItem: Text {
      textFormat: Text.PlainText
      text: root.tooltipText
      color: root.tooltipForeground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      leftPadding: Border.left(root._tooltipBorderSpec) + Style.spacing.controlPaddingX
      rightPadding: Border.right(root._tooltipBorderSpec) + Style.spacing.controlPaddingX
      topPadding: Border.top(root._tooltipBorderSpec) + Style.spacing.controlPaddingY
      bottomPadding: Border.bottom(root._tooltipBorderSpec) + Style.spacing.controlPaddingY
    }
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: root.leftAlign ? parent.left : undefined
    anchors.leftMargin: root.leftAlign ? root._reservedContentLeftInset : 0
    anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
    spacing: Style.spacing.controlGap

    Text {
      textFormat: Text.PlainText
      visible: root.iconText !== ""
      text: root.iconText
      color: root.selected ? root._selectedColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      rotation: root.iconSpinning ? 0 : root.iconRotation
      transformOrigin: Item.Center
      anchors.verticalCenter: parent.verticalCenter

      RotationAnimation on rotation {
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        running: root.iconSpinning
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.text !== ""
      text: root.text
      color: root.selected ? root._selectedColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.selected
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (root.focusable) root.forceActiveFocus()
      if (mouse.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}
