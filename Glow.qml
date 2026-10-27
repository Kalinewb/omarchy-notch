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
  // The brightest opacity, right at the edge. 0.35 is the curve in glow.js as
  // it stands; a lower one scales the whole curve down (same shape).
  property real strength: GlowCurve.knots[0].a
  // >= 1: the glow runs this many times further along the screen's top edge
  // than it reaches down, tapering out instead of being cut off there. 1 is a
  // plain circle about each fillet tip.
  property real edgeTail: 1
  // A diffuse glow instead of the curve: a gaussian-like bell, brightest right
  // at the edge with no flat top or rim, `spread` times as far as `size`
  // (never past maxReach), with `strength` as its peak. False draws the curve.
  property bool diffuse: false
  property real spread: 1.6

  readonly property real reach: Math.max(1, size)
  // How far what is drawn reaches: `reach`, or further when diffuse.
  readonly property real drawReach: diffuse ? Math.min(GlowCurve.fullReach, reach * Math.max(1, spread)) : reach
  // The window holding the glow is sized once, for the largest glow allowed.
  readonly property real maxReach: GlowCurve.fullReach
  readonly property real pad: 8
  readonly property var knots: GlowCurve.scaled(reach)
  function alphaAt(d) { return GlowCurve.alpha(d, reach) }

  width: barWidth
  height: barHeight
  visible: presence > 0.001 && barHeight > 0.5

  ShaderEffect {
    readonly property var curve: root.diffuse ? GlowCurve.softUniforms(root.drawReach, Math.max(0, root.strength)) : GlowCurve.uniforms(root.reach)

    x: -margin
    y: 0
    width: root.barWidth + 2 * margin
    height: root.barHeight + root.drawReach + root.pad
    fragmentShader: "shaders/glow.frag.qsb"
    blending: true

    readonly property size itemSize: Qt.size(width, height)
    readonly property real margin: root.filletRadius + root.drawReach * Math.max(1, root.edgeTail) + root.pad
    readonly property real barWidth: root.barWidth
    readonly property real barHeight: root.barHeight
    readonly property real bottomRadius: root.bottomRadius
    readonly property real filletRadius: root.filletRadius
    readonly property real presence: Math.max(0, Math.min(1, root.presence))
    readonly property color glowColor: root.color
    readonly property vector4d knotD: curve.d
    readonly property real gain: root.diffuse ? 1 : Math.max(0, root.strength) / GlowCurve.knots[0].a
    readonly property vector4d knotA: curve.a.times(gain)
    readonly property vector4d knotM: curve.m.times(gain)
    readonly property real edgeTail: Math.max(1, root.edgeTail)
  }
}
