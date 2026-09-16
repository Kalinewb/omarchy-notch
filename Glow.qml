import QtQuick
import "glow.js" as GlowCurve

// The battery glow: opacity falling off with distance from the notch's edge.
//
// A ShaderEffect, not a shape: shaders/glow.frag computes each pixel's exact
// distance to the notch's silhouette (bar plus concave fillets) and takes its
// opacity from the curve in glow.js -- at full size 0.35 up to 6 px, 0.18 at
// 20 px, 0.07 at 50 px, reaching 0 smoothly at 80 px; `size` sets where it
// reaches zero and scales the other distances with it. Nothing is drawn under
// the notch.
//
// This item's origin is the notch bar's top-left corner, like the bar's own
// coordinates; the effect itself spills `reach` px (plus a spare `pad`) past
// the bar on the left, right and bottom, so the curve is always drawn out to
// zero and never cut off. Its window must leave that much room below the bar.
Item {
  id: root

  property real barWidth: 0
  property real barHeight: 0
  property real bottomRadius: 0
  property real filletRadius: 0
  property color color: "#FFB340"
  property real presence: 0
  // Where the glow reaches zero, px from the edge.
  property real size: 30

  readonly property real reach: Math.max(1, size)
  // The window holding the glow is sized once, for the largest glow allowed.
  readonly property real maxReach: GlowCurve.fullReach
  readonly property real pad: 8
  readonly property var knots: GlowCurve.scaled(reach)
  function alphaAt(d) { return GlowCurve.alpha(d, reach) }

  width: barWidth
  height: barHeight
  visible: presence > 0.001 && barHeight > 0.5

  ShaderEffect {
    readonly property var curve: GlowCurve.uniforms(root.reach)

    x: -margin
    y: 0
    width: root.barWidth + 2 * margin
    height: root.barHeight + root.reach + root.pad
    fragmentShader: "shaders/glow.frag.qsb"
    blending: true

    readonly property size itemSize: Qt.size(width, height)
    readonly property real margin: root.filletRadius + root.reach + root.pad
    readonly property real barWidth: root.barWidth
    readonly property real barHeight: root.barHeight
    readonly property real bottomRadius: root.bottomRadius
    readonly property real filletRadius: root.filletRadius
    readonly property real presence: Math.max(0, Math.min(1, root.presence))
    readonly property color glowColor: root.color
    readonly property vector4d knotD: curve.d
    readonly property vector4d knotA: curve.a
    readonly property vector4d knotM: curve.m
  }
}
