import QtQuick
import QtQuick.Effects

// A soft coloured mist around the notch, used for the battery glow.
//
// It is the notch's own silhouette -- the bar plus both background fillets --
// grown by `spread` px, painted in `color`, and blurred. It sits BEHIND the
// notch, so the bar stays pitch black and only the halo outside it shows:
// down its sides, along its rounded bottom, and out along the screen edge
// past the fillets.
//
// This item's origin is the notch bar's top-left corner. Put it at the bar's
// position and give it the bar's size and radii; the halo spills outside it
// by up to `reach` px.
Item {
  id: root

  property real barWidth: 0
  property real barHeight: 0
  property real bottomRadius: 0
  property real filletRadius: 0
  property color color: "#30d158"
  // 0..1: how strong the mist is. 0 draws nothing at all.
  property real intensity: 0
  // How far the silhouette is grown before blurring, and the blur's size.
  property real spread: 6
  property int blurMax: 48

  readonly property real reach: spread + blurMax

  width: barWidth
  height: barHeight
  visible: intensity > 0.001 && barHeight > 0.5

  Island {
    id: silhouette
    // Grown by `spread` on the sides and bottom; the top stays on the screen
    // edge. The fillets grow with it, so the halo keeps the fused outline.
    x: -silhouette.barX - root.spread
    y: 0
    barWidth: root.barWidth + 2 * root.spread
    barHeight: root.barHeight + root.spread
    bottomRadius: root.bottomRadius + root.spread
    filletRadius: root.filletRadius + root.spread
    color: root.color
    visible: false
    layer.enabled: root.visible
  }

  MultiEffect {
    source: silhouette
    x: silhouette.x
    y: silhouette.y
    width: silhouette.width
    height: silhouette.height
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 1.0
    blurMax: root.blurMax
    blurMultiplier: 0.6
    opacity: Math.max(0, Math.min(1, root.intensity))
  }
}
