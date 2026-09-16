import QtQuick

// The notch's shape: a bar hanging from the top edge of the screen and fused
// to it, the way a Dynamic Island grows out of the notch above it. Adapted
// from graveklar.face's Island.qml, which settled the geometry.
//
// Three items, and the split between them is the whole point:
//
//   · the bar -- a plain Rectangle. Top edge flush with the screen edge, top
//     corners square (radius 0), bottom corners rounded with an ordinary
//     convex radius. Nothing is carved out of it and nothing is added to it.
//
//   · two fillets, one beside each top corner, drawn OUTSIDE the bar. Each is
//     an r×r square in the open angle between the bar's side and the screen
//     edge with a quarter-disc taken out of it. The disc's centre is r out
//     from the bar's side and r down from the screen edge, so its arc is
//     tangent to both lines: the background curves into the bar's side with
//     no kink. They are painted the bar's colour but are separate items, so
//     the bar's own rectangle stays exactly a rectangle.
//
// Why the arc centre is outside the bar: a circle tangent to both the bar's
// side (x = 0) and the screen edge (y = 0) has its centre at (±r, r). With the
// centre at (+r, r), inside the bar, the arc lies inside the bar too, so
// drawing it cuts a notch out of the bar. Only (-r, r) puts the arc in the
// background, curving from the screen edge down into the bar's side.
//
// What this deliberately is not:
//
//   · a positive radius on the bar's TOP corners -- a pill floating just
//     below the edge;
//   · arcs cut out of the bar's own body at the top corners -- a notch bitten
//     into the bar.
//
// Centres and radii are readonly properties so the geometry can be checked as
// numbers (dev/geometry.sh does) rather than judged from a screenshot.
Item {
  id: root

  // The bar's own rectangle.
  property real barWidth: 0
  property real barHeight: 0
  // Requested radii; `bottomR` and `fillet` below are what actually fits.
  property real bottomRadius: 0
  property real filletRadius: 0
  property color color: "#000000"

  // Children declared inside an Island land inside the bar, clipped to it.
  default property alias contents: bar.data
  readonly property Item body: bar

  // The convex radius of the bottom two corners: no more than half the width
  // (or the two corners would overlap) and no more than half the height (or
  // they would run into the top edge).
  readonly property real bottomR: Math.max(0, Math.min(bottomRadius, barWidth / 2, barHeight / 2))

  // The fillet radius: no more than the straight part of the bar's side (its
  // height minus the bottom radius), or the arc would land on the convex
  // corner below it instead of on a straight edge.
  readonly property real fillet: Math.max(0, Math.min(filletRadius, barHeight - bottomR))

  // The fillets widen the footprint by one radius on each side, and the bar
  // sits in the middle, so centring the Island centres the bar.
  implicitWidth: barWidth + 2 * fillet
  implicitHeight: barHeight
  width: implicitWidth
  height: implicitHeight

  // Where the bar's rectangle starts, in this item's coordinates.
  readonly property real barX: fillet

  // Arc centres in the BAR's coordinates: origin at the bar's top-left corner,
  // x to the right, y down. The fillet centres are outside the bar, in the open
  // angle between its side and the screen edge. The bottom centres are the
  // usual convex ones, one radius in from each edge.
  readonly property point leftFilletCentre: Qt.point(-fillet, fillet)
  readonly property point rightFilletCentre: Qt.point(barWidth + fillet, fillet)
  readonly property point bottomLeftCentre: Qt.point(bottomR, barHeight - bottomR)
  readonly property point bottomRightCentre: Qt.point(barWidth - bottomR, barHeight - bottomR)

  // Each fillet canvas is one pixel wider than its radius, with the extra
  // column tucked under the bar (the bar is declared after the fillets, so it
  // paints on top). The visible fillet is exactly the square minus the
  // quarter-disc. The hidden column stops a hairline seam where two
  // antialiased edges would otherwise meet on a half pixel.
  readonly property real seamOverlap: 1

  function paintFillet(ctx, side) {
    var r = root.fillet
    ctx.reset()
    ctx.clearRect(0, 0, r + root.seamOverlap, Math.max(1, r))
    if (r <= 0) return
    ctx.beginPath()
    if (side === "left") {
      // Local frame: the bar's side is x = r, the screen edge is y = 0, and
      // the arc's centre is the square's bottom-left corner (0, r). Path: the
      // bar's top corner, down its side to the tangent point, then along the
      // arc back up to the screen edge.
      ctx.moveTo(r + root.seamOverlap, 0)
      ctx.lineTo(r + root.seamOverlap, r)
      ctx.lineTo(r, r)
      ctx.arc(0, r, r, 0, -Math.PI / 2, true)
    } else {
      // Mirror image: the bar's side is x = seamOverlap, and the arc's centre
      // is the square's bottom-right corner (seamOverlap + r, r).
      var o = root.seamOverlap
      ctx.moveTo(0, 0)
      ctx.lineTo(0, r)
      ctx.lineTo(o, r)
      ctx.arc(o + r, r, r, Math.PI, 3 * Math.PI / 2, false)
    }
    ctx.closePath()
    ctx.fillStyle = root.color
    ctx.fill()
  }

  // Immediate (GUI-thread) painting, in the same frame as the bindings above,
  // so a fillet never lags one frame behind the side it flows into while the
  // bar's size is animating.
  Canvas {
    id: leftFillet
    x: 0
    y: 0
    width: root.fillet + root.seamOverlap
    height: Math.max(1, root.fillet)
    visible: root.fillet > 0
    renderStrategy: Canvas.Immediate
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: root.paintFillet(getContext("2d"), "left")
  }

  Canvas {
    id: rightFillet
    x: root.barX + root.barWidth - root.seamOverlap
    y: 0
    width: root.fillet + root.seamOverlap
    height: Math.max(1, root.fillet)
    visible: root.fillet > 0
    renderStrategy: Canvas.Immediate
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: root.paintFillet(getContext("2d"), "right")
  }

  onColorChanged: { leftFillet.requestPaint(); rightFillet.requestPaint() }

  // The bar. Declared last so it paints over the fillets' hidden columns.
  Rectangle {
    id: bar
    x: root.barX
    y: 0
    width: root.barWidth
    height: root.barHeight
    color: root.color
    border.width: 0
    topLeftRadius: 0
    topRightRadius: 0
    bottomLeftRadius: root.bottomR
    bottomRightRadius: root.bottomR
    clip: true
  }
}
