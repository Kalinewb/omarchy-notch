import QtQuick
import "glow.js" as GlowCurve

// The subtle charging glow: the outline glow's falloff, only below the
// notch's bottom edge, strongest in the middle and fading to nothing at the
// sides (shaders/bottomglow.frag says exactly how).
//
// Same coordinates as Glow.qml: this item's origin is the notch bar's top-left
// corner, and the effect spills `reach` px (plus `pad`) past the bar.
Item {
  id: root

  property real barWidth: 0
  property real barHeight: 0
  property real bottomRadius: 0
  property color color: "#FFB340"
  property real presence: 0
  // Where the falloff reaches zero, px below the edge.
  property real size: 30
  // The brightest alpha: in the middle, right at the bottom edge.
  property real strength: 0.24

  readonly property real reach: Math.max(1, size)
  readonly property real maxReach: GlowCurve.fullReach
  readonly property real pad: 8

  // Alpha at `d` px below the edge and `u` across the bar (-1 left side,
  // 0 middle, +1 right side), for reporting and tests.
  function alphaAt(d, u) {
    var across = Math.abs(u) >= 1 ? 0 : Math.pow(Math.cos(Math.PI / 2 * u), 2)
    return (strength / 0.35) * GlowCurve.alpha(d, reach) * across
  }

  width: barWidth
  height: barHeight
  visible: presence > 0.001 && barHeight > 0.5 && strength > 0

  ShaderEffect {
    readonly property var curve: GlowCurve.uniforms(root.reach)

    x: -margin
    y: 0
    width: root.barWidth + 2 * margin
    height: root.barHeight + root.reach + root.pad
    fragmentShader: "shaders/bottomglow.frag.qsb"
    blending: true

    readonly property size itemSize: Qt.size(width, height)
    readonly property real margin: root.reach + root.pad
    readonly property real barWidth: root.barWidth
    readonly property real barHeight: root.barHeight
    readonly property real bottomRadius: root.bottomRadius
    readonly property real presence: Math.max(0, Math.min(1, root.presence))
    readonly property real strength: root.strength
    readonly property color glowColor: root.color
    readonly property vector4d knotD: curve.d
    readonly property vector4d knotA: curve.a
    readonly property vector4d knotM: curve.m
  }
}
