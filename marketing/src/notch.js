// Notch marketing helpers: the notch's exact shape, its battery glow, and the
// annotation arrows. The geometry follows the plugin itself:
//
//   Island.qml      bar with square top corners and convex bottom corners
//                   (radius R), plus two concave fillets (radius r) centred
//                   OUTSIDE the bar at (-r, r) and (w + r, r)
//   glow.js         outline falloff: 0.35 up to 6/80 of the reach, 0.18 at
//                   20/80, 0.07 at 50/80, 0 at the reach; monotone cubic
//                   Hermite (Fritsch-Butland) between the knots
//   bottomglow.frag the open/settings glow: same curve, strength 0.24, only
//                   below the bar, weighted cos^2(pi u / 2) across it
//
// Everything is drawn from numbers; nothing is traced by eye.
(function () {
  "use strict";

  // ---- the shape -----------------------------------------------------------

  // Outline in a frame whose origin is the left fillet's tip on the screen
  // edge, so the bar's left side is x = r. viewBox: 0 0 (w + 2r) h.
  function pathD(w, h, R, r) {
    const x0 = r, x1 = r + w;
    const p = ["M 0 0", `H ${x1 + r}`];
    if (r > 0) p.push(`A ${r} ${r} 0 0 0 ${x1} ${r}`);
    p.push(`V ${h - R}`);
    if (R > 0) p.push(`A ${R} ${R} 0 0 1 ${x1 - R} ${h}`);
    p.push(`H ${x0 + R}`);
    if (R > 0) p.push(`A ${R} ${R} 0 0 1 ${x0} ${h - R}`);
    p.push(`V ${r}`);
    if (r > 0) p.push(`A ${r} ${r} 0 0 0 0 0`);
    p.push("Z");
    return p.join(" ");
  }

  function svgShape(w, h, R, r, s, fill) {
    const W = w + 2 * r;
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${W * s}" height="${h * s}" viewBox="0 0 ${W} ${h}" shape-rendering="geometricPrecision"><path d="${pathD(w, h, R, r)}" fill="${fill}"/></svg>`;
  }

  // ---- the glow curve (glow.js) --------------------------------------------

  const knots = [{ d: 6, a: 0.35 }, { d: 20, a: 0.18 }, { d: 50, a: 0.07 }, { d: 80, a: 0 }];
  const fullReach = 80;
  const slopes = (function () {
    const m = [0];
    for (let i = 1; i < knots.length - 1; i++) {
      const h0 = knots[i].d - knots[i - 1].d, h1 = knots[i + 1].d - knots[i].d;
      const s0 = (knots[i].a - knots[i - 1].a) / h0, s1 = (knots[i + 1].a - knots[i].a) / h1;
      m.push(s0 * s1 <= 0 ? 0 : 3 * (h0 + h1) / ((2 * h1 + h0) / s0 + (h1 + 2 * h0) / s1));
    }
    m.push(0);
    return m;
  })();

  function alpha(d, reach) {
    const k = reach / fullReach;
    if (k <= 0) return 0;
    d = d / k;
    if (d <= knots[0].d) return knots[0].a;
    const last = knots.length - 1;
    if (d >= knots[last].d) return 0;
    let i = 0;
    while (d > knots[i + 1].d) i++;
    const h = knots[i + 1].d - knots[i].d;
    const t = (d - knots[i].d) / h, t2 = t * t, t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * knots[i].a + (t3 - 2 * t2 + t) * h * slopes[i]
         + (-2 * t3 + 3 * t2) * knots[i + 1].a + (t3 - t2) * h * slopes[i + 1];
  }

  // ---- distances, in bar coordinates (origin: the bar's top-left corner) ---

  // Unsigned distance to the bar (0 inside): square top corners, bottom
  // corners of radius R.
  function dBar(x, y, w, h, R) {
    if (y > h - R && (x < R || x > w - R)) {
      const cx = x < R ? R : w - R, cy = h - R;
      return Math.max(0, Math.hypot(x - cx, y - cy) - R);
    }
    const dx = Math.max(0, -x, x - w), dy = Math.max(0, -y, y - h);
    return Math.hypot(dx, dy);
  }

  // Signed distance to the bar, as bottomglow.frag computes it.
  function sdBar(x, y, w, h, R) {
    const qx = Math.abs(x - w * 0.5) - (w * 0.5 - R), qy = y - (h - R);
    return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - R;
  }

  // A fillet is the r x r square beside the bar's top corner minus the
  // quarter-disc centred at (cx, r); side -1 is the left one.
  function inFillet(x, y, cx, r, side) {
    const sx0 = side < 0 ? cx : cx - r;  // square spans [sx0, sx0 + r]
    if (x < sx0 || x > sx0 + r || y < 0 || y > r) return false;
    return Math.hypot(x - cx, y - r) >= r;
  }

  // Distance to a fillet's arc (its only boundary not shared with the bar or
  // lying on the screen edge), clamped to the arc's end points.
  function dArc(x, y, cx, r, side) {
    const ux = x - cx, uy = y - r, L = Math.hypot(ux, uy);
    const inQuad = uy <= 0 && (side < 0 ? ux >= 0 : ux <= 0);
    if (inQuad) return Math.abs(L - r);
    const ex = cx, ey = 0;                       // tip on the screen edge
    const fx = side < 0 ? cx + r : cx - r, fy = r; // tangent point on the bar's side
    return Math.min(Math.hypot(x - ex, y - ey), Math.hypot(x - fx, y - fy));
  }

  // Exact distance from a point below the screen edge to the notch's
  // silhouette (bar + both fillets); 0 inside it.
  function dSilhouette(x, y, w, h, R, r) {
    const b = dBar(x, y, w, h, R);
    if (b === 0 || r <= 0) return b;
    if (inFillet(x, y, -r, r, -1) || inFillet(x, y, w + r, r, 1)) return 0;
    return Math.min(b, dArc(x, y, -r, r, -1), dArc(x, y, w + r, r, 1));
  }

  // ---- the glow canvas -----------------------------------------------------

  const glowColours = { amber: "#FFB340", green: "#30D158", red: "#FF453A" };

  function hexRGB(hex) {
    const v = parseInt(hex.replace("#", ""), 16);
    return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
  }

  function drawGlow(el, o) {
    const pad = 6;
    const ext = o.reach + pad;
    const dpr = window.devicePixelRatio || 1;
    const k = o.s * dpr; // device px per logical px
    const cssW = (o.w + 2 * o.r + 2 * ext) * o.s, cssH = (o.h + ext) * o.s;
    const c = document.createElement("canvas");
    c.width = Math.round(cssW * dpr);
    c.height = Math.round(cssH * dpr);
    c.style.width = cssW + "px";
    c.style.height = cssH + "px";
    c.style.left = (-ext * o.s) + "px";
    c.style.top = "0px";
    c.className = "glow";
    const ctx = c.getContext("2d");
    const img = ctx.createImageData(c.width, c.height);
    const [cr, cg, cb] = hexRGB(o.color);
    let max = 0;
    for (let j = 0; j < c.height; j++) {
      const y = (j + 0.5) / k;                      // below the screen edge
      for (let i = 0; i < c.width; i++) {
        const x = (i + 0.5) / k - ext - o.r;          // bar coordinates
        let a;
        if (o.style === "bottom") {
          const u = (x - o.w * 0.5) / (o.w * 0.5);
          const across = Math.abs(u) >= 1 ? 0 : Math.pow(Math.cos(Math.PI / 2 * u), 2);
          const d = sdBar(x, y, o.w, o.h, o.R);
          const t = Math.max(0, Math.min(1, (d + 1.5) / 1.0));
          const under = t * t * (3 - 2 * t);
          a = (o.strength / 0.35) * alpha(Math.max(d, 0), o.reach) * across * under;
        } else {
          const d = dSilhouette(x, y, o.w, o.h, o.R, o.r);
          a = d <= 0 ? 0 : alpha(d, o.reach);
        }
        if (a > max) max = a;
        const p = (j * c.width + i) * 4;
        img.data[p] = cr; img.data[p + 1] = cg; img.data[p + 2] = cb;
        img.data[p + 3] = Math.round(a * 255);
      }
    }
    ctx.putImageData(img, 0, 0);
    el.insertBefore(c, el.firstChild);
    el.dataset.glowMax = max.toFixed(3);

    // Self-check: read back the drawn alpha straight below the bar's centre
    // and beside the left fillet's tip, and compare with the curve.
    const read = (x, y) => {
      const i = Math.floor((x + ext + o.r) * k), j = Math.floor(y * k);
      return ctx.getImageData(i, j, 1, 1).data[3] / 255;
    };
    const expect = (dist) => o.style === "bottom"
      ? (o.strength / 0.35) * alpha(dist, o.reach)
      : alpha(dist, o.reach);
    const samples = [];
    for (const t of [0.6, 2, 4, 8, 12, 20, 26, 31, 33, 40]) {
      const px = o.w / 2, py = o.h + t;
      // pixel centre actually sampled, and its exact distance
      const i = Math.floor((px + ext + o.r) * k), j = Math.floor(py * k);
      const cyc = (j + 0.5) / k;
      const dExact = cyc - o.h;
      samples.push({ where: "below-centre", d: +dExact.toFixed(3), drawn: +read(px, py).toFixed(4), curve: +expect(dExact).toFixed(4) });
    }
    if (o.style !== "bottom") {
      for (const t of [2, 8, 20, 31, 33]) {
        const px = -o.r - t, py = 0.3;
        const i = Math.floor((px + ext + o.r) * k), j = Math.floor(py * k);
        const xc = (i + 0.5) / k - ext - o.r, yc = (j + 0.5) / k;
        const dExact = dSilhouette(xc, yc, o.w, o.h, o.R, o.r);
        samples.push({ where: "beside-left-fillet", d: +dExact.toFixed(3), drawn: +read(px, py).toFixed(4), curve: +expect(dExact).toFixed(4) });
      }
    }
    el._glowReport = { reach: o.reach, style: o.style, color: o.color, strength: o.style === "bottom" ? o.strength : 0.35, max: +max.toFixed(4), samples };
  }

  // ---- building a notch ----------------------------------------------------

  // <div class="notch" data-w="180|auto" data-h="32" data-s="1.2"
  //      data-glow="amber|green|red|#hex" data-glow-style="outline|bottom"
  //      data-center="1"> <div class="nc">content, logical px</div> </div>
  function build(el) {
    const d = el.dataset;
    const s = Number(d.s || 1);
    let h = d.h === "auto" ? null : Number(d.h || 32);
    const R = Number(d.r ?? 10);           // bottom radius
    const rReq = Number(d.fillet ?? 10);   // fillet radius
    const content = el.querySelector(":scope > .nc");
    let w = d.w === "auto" || !d.w ? null : Number(d.w);
    if (w === null && content) {
      content.style.zoom = 1;
      content.style.width = "max-content";
      w = Math.ceil(content.getBoundingClientRect().width);
    }
    if (h === null && content) {
      // Grow down to fit the content, as the settings panel and menu do.
      content.style.zoom = 1;
      content.style.width = w + "px";
      content.style.height = "auto";
      h = Math.ceil(content.getBoundingClientRect().height);
    }
    const Rf = Math.max(0, Math.min(R, w / 2, h / 2));
    const r = Math.max(0, Math.min(rReq, h - Rf));
    const W = w + 2 * r;
    el.style.width = W * s + "px";
    el.style.height = h * s + "px";
    if (d.center) el.style.left = `calc(50% - ${(W * s) / 2}px)`;
    el.insertAdjacentHTML("afterbegin", svgShape(w, h, Rf, r, s, d.fill || "#000000"));
    if (content) {
      content.style.left = r * s + "px";
      content.style.width = w + "px";
      content.style.height = h + "px";
      content.style.zoom = s;
    }
    if (d.glow && !/[?&]noglow\b/.test(location.search)) {
      drawGlow(el, {
        w, h, R: Rf, r, s,
        reach: Number(d.reach || 32),
        color: glowColours[d.glow] || d.glow,
        style: d.glowStyle || "outline",
        strength: Number(d.strength || 0.24),
      });
    }
    Object.assign(el.dataset, { bw: w, bh: h, br: Rf, bf: r, bs: s });
  }

  // Geometry of every notch on the page, in card CSS px, for verify tooling
  // (render.sh never reads it; `chromium --dump-dom` does).
  function report() {
    const out = [];
    document.querySelectorAll(".notch").forEach((el) => {
      const q = rectIn(el);
      const s = Number(el.dataset.bs), r = Number(el.dataset.bf);
      out.push({
        id: el.id || null,
        scale: s, w: Number(el.dataset.bw), h: Number(el.dataset.bh),
        bottomRadius: Number(el.dataset.br), fillet: r,
        filletCentres: [[-r, r], [Number(el.dataset.bw) + r, r]],
        barLeft: +(q.x + r * s).toFixed(3), top: +q.y.toFixed(3),
        glow: el._glowReport || null,
      });
    });
    document.body.setAttribute("data-notch-report", JSON.stringify(out));
    return out;
  }

  // Card coordinates of a point given in a notch's bar coordinates.
  function barPoint(el, bx, by) {
    const card = el.closest(".card").getBoundingClientRect();
    const b = el.getBoundingClientRect();
    const s = Number(el.dataset.bs), r = Number(el.dataset.bf);
    return [b.left - card.left + (r + bx) * s, b.top - card.top + by * s];
  }

  function rectIn(el) {
    const card = el.closest(".card").getBoundingClientRect();
    const b = el.getBoundingClientRect();
    return { x: b.left - card.left, y: b.top - card.top, w: b.width, h: b.height };
  }

  // Point on an element's box: fx, fy in 0..1.
  function elPoint(el, fx, fy) {
    const q = rectIn(el);
    return [q.x + q.w * fx, q.y + q.h * fy];
  }

  // ---- annotations ---------------------------------------------------------

  let overlay = null;
  function ensureOverlay(card) {
    if (overlay) return overlay;
    card.insertAdjacentHTML("beforeend",
      `<svg class="overlay" xmlns="http://www.w3.org/2000/svg"><defs></defs></svg>`);
    overlay = card.lastElementChild;
    return overlay;
  }

  const cssVar = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

  // A dashed callout from `a` to `b` (card coordinates), bending through an
  // optional elbow; ends in an arrowhead or a dot.
  function arrow(card, a, b, o = {}) {
    const svg = ensureOverlay(card);
    const color = o.color || "rgba(240,242,252,0.6)";
    const ns = "http://www.w3.org/2000/svg";
    const path = document.createElementNS(ns, "path");
    let dPath;
    if (o.via) {
      dPath = `M ${a[0]} ${a[1]} Q ${o.via[0]} ${o.via[1]} ${b[0]} ${b[1]}`;
    } else if (o.elbow === "h") {
      dPath = `M ${a[0]} ${a[1]} H ${b[0]} V ${b[1]}`;
    } else if (o.elbow === "v") {
      dPath = `M ${a[0]} ${a[1]} V ${b[1]} H ${b[0]}`;
    } else {
      dPath = `M ${a[0]} ${a[1]} L ${b[0]} ${b[1]}`;
    }
    path.setAttribute("d", dPath);
    path.setAttribute("fill", "none");
    path.setAttribute("stroke", color);
    path.setAttribute("stroke-width", o.width || 1.4);
    path.setAttribute("stroke-dasharray", o.dash || "4 4");
    path.setAttribute("stroke-linecap", "round");
    svg.appendChild(path);
    // start dot
    if (o.startDot !== false) {
      const c0 = document.createElementNS(ns, "circle");
      c0.setAttribute("cx", a[0]); c0.setAttribute("cy", a[1]); c0.setAttribute("r", 2.2);
      c0.setAttribute("fill", color);
      svg.appendChild(c0);
    }
    // end: arrowhead along the final tangent
    const len = path.getTotalLength();
    const p1 = path.getPointAtLength(len), p0 = path.getPointAtLength(Math.max(0, len - 3));
    if (o.end === "dot") {
      const c = document.createElementNS(ns, "circle");
      c.setAttribute("cx", p1.x); c.setAttribute("cy", p1.y); c.setAttribute("r", 3.2);
      c.setAttribute("fill", "none"); c.setAttribute("stroke", color); c.setAttribute("stroke-width", 1.6);
      svg.appendChild(c);
    } else if (o.end !== "none") {
      const ang = Math.atan2(p1.y - p0.y, p1.x - p0.x), L = 8, spread = 0.46;
      const h = document.createElementNS(ns, "path");
      h.setAttribute("d", `M ${p1.x - L * Math.cos(ang - spread)} ${p1.y - L * Math.sin(ang - spread)} L ${p1.x} ${p1.y} L ${p1.x - L * Math.cos(ang + spread)} ${p1.y - L * Math.sin(ang + spread)}`);
      h.setAttribute("fill", "none"); h.setAttribute("stroke", color);
      h.setAttribute("stroke-width", 1.6); h.setAttribute("stroke-linecap", "round"); h.setAttribute("stroke-linejoin", "round");
      svg.appendChild(h);
    }
  }

  // A dashed ring around a point (card coordinates), e.g. a fillet. With
  // o.clipTop, nothing is drawn above that y (the screen edge), so the ring
  // reads as hugging the corner rather than sitting on the bezel.
  let clipSerial = 0;
  function ring(card, c, radius, o = {}) {
    const svg = ensureOverlay(card);
    const ns = "http://www.w3.org/2000/svg";
    const color = o.color || "rgba(240,242,252,0.6)";
    const el = document.createElementNS(ns, "circle");
    el.setAttribute("cx", c[0]); el.setAttribute("cy", c[1]); el.setAttribute("r", radius);
    el.setAttribute("fill", "none"); el.setAttribute("stroke", color);
    el.setAttribute("stroke-width", o.width || 1.5);
    el.setAttribute("stroke-dasharray", o.dash || "3.2 3");
    if (o.clipTop != null) {
      const id = "ringclip" + (++clipSerial);
      const cp = document.createElementNS(ns, "clipPath");
      cp.setAttribute("id", id);
      const r = document.createElementNS(ns, "rect");
      r.setAttribute("x", c[0] - radius - 4); r.setAttribute("y", o.clipTop);
      r.setAttribute("width", 2 * radius + 8); r.setAttribute("height", 2 * radius + 8);
      cp.appendChild(r);
      svg.querySelector("defs").appendChild(cp);
      el.setAttribute("clip-path", `url(#${id})`);
    }
    svg.appendChild(el);
    return el;
  }

  // Point on a ring at an angle (degrees, 0 = right, 90 = down).
  function onRing(c, radius, deg) {
    const t = deg * Math.PI / 180;
    return [c[0] + radius * Math.cos(t), c[1] + radius * Math.sin(t)];
  }

  // A dimension line with end ticks and a centred label.
  function dimension(card, a, b, label, o = {}) {
    const svg = ensureOverlay(card);
    const ns = "http://www.w3.org/2000/svg";
    const color = o.color || "rgba(214,219,240,0.55)";
    const g = document.createElementNS(ns, "g");
    const horiz = Math.abs(b[1] - a[1]) < Math.abs(b[0] - a[0]);
    const t = 5;
    const segs = horiz
      ? [[a[0], a[1], b[0], b[1]], [a[0], a[1] - t, a[0], a[1] + t], [b[0], b[1] - t, b[0], b[1] + t]]
      : [[a[0], a[1], b[0], b[1]], [a[0] - t, a[1], a[0] + t, a[1]], [b[0] - t, b[1], b[0] + t, b[1]]];
    for (const [x1, y1, x2, y2] of segs) {
      const l = document.createElementNS(ns, "line");
      l.setAttribute("x1", x1); l.setAttribute("y1", y1); l.setAttribute("x2", x2); l.setAttribute("y2", y2);
      l.setAttribute("stroke", color); l.setAttribute("stroke-width", 1.2);
      g.appendChild(l);
    }
    svg.appendChild(g);
    if (label) {
      const n = document.createElement("div");
      n.className = "note dim-label";
      n.textContent = label;
      n.style.background = o.bg || "transparent";
      n.style.padding = "0 6px";
      n.style.color = o.labelColor || "rgba(214,219,240,0.72)";
      card.appendChild(n);
      const r = n.getBoundingClientRect();
      if (horiz) {
        n.style.left = ((a[0] + b[0]) / 2 - r.width / 2) + "px";
        n.style.top = (a[1] + (o.below ? 8 : -r.height - 6)) + "px";
      } else {
        n.style.left = (a[0] + 10) + "px";
        n.style.top = ((a[1] + b[1]) / 2 - r.height / 2) + "px";
      }
    }
  }

  // Place a tag so a given anchor of it (fx, fy in 0..1) lands on a point.
  function place(el, p, fx = 0, fy = 0.5) {
    const card = el.closest(".card");
    const cr = card.getBoundingClientRect();
    const r = el.getBoundingClientRect();
    const cur = [r.left - cr.left, r.top - cr.top];
    // tags are absolutely positioned relative to the card
    el.style.left = (p[0] - r.width * fx) + "px";
    el.style.top = (p[1] - r.height * fy) + "px";
    return rectIn(el);
  }

  // Boxes of the copy, the illustration and every annotation, plus any text
  // that overflows its box, for verify tooling (`chromium --dump-dom`).
  function layout() {
    const r = (el) => { const q = rectIn(el); return [+q.x.toFixed(2), +q.y.toFixed(2), +q.w.toFixed(2), +q.h.toFixed(2)]; };
    const boxes = [];
    const sel = ".badge, .title, .tagline, .desc, .chip, .install, .footer > span, .screen, .inset, " +
                ".tag, .note, .sub, .spring, .state, .between, .key";
    document.querySelectorAll(sel).forEach((el) => {
      if (el.closest(".notch")) return; // content drawn in a notch is checked by the notch report
      boxes.push({ kind: el.classList[0] || "footer-span", id: el.id || null, text: el.textContent.trim().slice(0, 40), box: r(el),
                   inline: !!el.closest(".between, .state, .pair") && !el.matches(".between, .state, .pair") });
    });
    const overflow = [];
    document.querySelectorAll(".chip, .chip .tx, .install, .tag, .key, .title, .tagline, .desc, .nc, .nc *").forEach((el) => {
      if (el.scrollWidth > el.clientWidth + 1 && getComputedStyle(el).overflow !== "visible") overflow.push(el.className + ": " + el.textContent.trim().slice(0, 30));
    });
    // Children that stick out of their chip, install box or notch content.
    document.querySelectorAll(".chip *, .install *").forEach((el) => {
      const p = el.closest(".chip, .install").getBoundingClientRect(), q = el.getBoundingClientRect();
      if (q.width && (q.right > p.right - 4 || q.left < p.left + 4)) overflow.push("sticks out: " + el.textContent.trim().slice(0, 30));
    });
    document.querySelectorAll(".notch > .nc").forEach((nc) => {
      const n = nc.parentElement, s = Number(n.dataset.bs), f = Number(n.dataset.bf);
      const nb = n.getBoundingClientRect();
      const L = nb.left + f * s, R = nb.right - f * s, B = nb.top + Number(n.dataset.bh) * s;
      nc.querySelectorAll("*").forEach((el) => {
        const q = el.getBoundingClientRect();
        if (q.width && (q.left < L - 0.5 || q.right > R + 0.5 || q.bottom > B + 0.5)) overflow.push("outside notch " + (n.id || "") + ": " + el.className + " " + el.textContent.trim().slice(0, 20));
      });
    });
    const card = document.querySelector(".card").getBoundingClientRect();
    document.body.setAttribute("data-layout-report", JSON.stringify({ w: card.width, h: card.height, boxes, overflow }));
  }

  window.Notch = {
    pathD, svgShape, alpha, dSilhouette, sdBar, build, barPoint, elPoint, rectIn,
    arrow, dimension, place, ring, onRing, layout,
    buildAll() {
      document.querySelectorAll(".notch").forEach(build);
      window.addEventListener("load", () => { report(); layout(); });
    },
    report,
    appIcon(el, size) {
      // A small screen tile with the notch fused to its top edge.
      const w = size * 0.46, h = size * 0.16, R = h * 0.36, r = h * 0.36;
      el.style.width = size + "px";
      el.style.height = size + "px";
      el.insertAdjacentHTML("beforeend", svgShape(w, h, R, r, 1, "#000000"));
    },
  };
})();
