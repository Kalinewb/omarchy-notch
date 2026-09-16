#!/usr/bin/env python3
"""Compare a rendered bottom-glow PNG with its formula, pixel by pixel.

    bottomglow_pixels.py <png> <barX> <W> <H> <R> <colour> <size> <strength>

Expected alpha at a pixel centre = strength / 0.35 × curve(d) × cos²(π u / 2),
with d the pixel's distance to the bar's outline (brute force, dense
polyline: sides, bottom corners, bottom) and u its position across the bar,
-1 at the left side, +1 at the right, zero glow outside. curve() is glow.js's
Hermite spline through (6, .35) (20, .18) (50, .07) (80, 0), distances scaled
by size / 80. Prints one JSON object.
"""
import json, math, subprocess, sys
import numpy as np

png, bx = sys.argv[1], float(sys.argv[2])
W, H, R = map(float, sys.argv[3:6])
colour, SIZE, STRENGTH = sys.argv[6], float(sys.argv[7]), float(sys.argv[8])

K = SIZE / 80.0
KNOTS = [(6 * K, 0.35), (20 * K, 0.18), (50 * K, 0.07), (80 * K, 0.0)]
def slopes():
    m = [0.0]
    for i in range(1, len(KNOTS) - 1):
        h0, h1 = KNOTS[i][0] - KNOTS[i-1][0], KNOTS[i+1][0] - KNOTS[i][0]
        s0, s1 = (KNOTS[i][1] - KNOTS[i-1][1]) / h0, (KNOTS[i+1][1] - KNOTS[i][1]) / h1
        m.append(0.0 if s0 * s1 <= 0 else 3 * (h0 + h1) / ((2 * h1 + h0) / s0 + (h1 + 2 * h0) / s1))
    return m + [0.0]
M = slopes()
def curve(d):
    d = np.asarray(d, dtype=float); out = np.zeros_like(d)
    out[d <= KNOTS[0][0]] = KNOTS[0][1]
    for i in range(len(KNOTS) - 1):
        (d0, a0), (d1, a1) = KNOTS[i], KNOTS[i+1]
        sel = (d > d0) & (d <= d1); h = d1 - d0; t = (d[sel] - d0) / h
        out[sel] = (2*t**3 - 3*t**2 + 1) * a0 + (t**3 - 2*t**2 + t) * h * M[i] + (-2*t**3 + 3*t**2) * a1 + (t**3 - t**2) * h * M[i+1]
    return out

def arc(cx, cy, r, a0, a1, step=0.02):
    n = max(2, int(abs(a1 - a0) * r / step)); t = np.linspace(a0, a1, n)
    return np.stack([cx + r * np.cos(t), cy + r * np.sin(t)], 1)
def seg(x0, y0, x1, y1, step=0.02):
    n = max(2, int(math.hypot(x1 - x0, y1 - y0) / step)); t = np.linspace(0, 1, n)
    return np.stack([x0 + (x1 - x0) * t, y0 + (y1 - y0) * t], 1)
outline = np.concatenate([seg(0, 0, 0, H - R), arc(R, H - R, R, math.pi, math.pi / 2), seg(R, H, W - R, H),
                          arc(W - R, H - R, R, math.pi / 2, 0), seg(W, H - R, W, 0)])

raw = subprocess.run(["magick", png, "-depth", "8", "rgba:-"], capture_output=True, check=True).stdout
w, h = map(int, subprocess.run(["magick", "identify", "-format", "%w %h", png], capture_output=True, text=True).stdout.split())
img = np.frombuffer(raw, dtype=np.uint8).reshape(h, w, 4).astype(float) / 255
alpha = img[:, :, 3]

yy, xx = np.mgrid[0:h, 0:w]
cx = (xx + 0.5 - bx).ravel(); cy = (yy + 0.5).ravel()
in_bar = (cx >= 0) & (cx <= W) & (cy <= H)
in_bar &= ~((cx < R) & (cy > H - R) & (np.hypot(cx - R, cy - (H - R)) > R))
in_bar &= ~((cx > W - R) & (cy > H - R) & (np.hypot(cx - (W - R), cy - (H - R)) > R))
# The fillets are part of the notch's silhouette (drawn black by Island.qml),
# not glow territory: the F×F square beside each top corner minus its disc.
F = 10.0
fl = (cx >= -F) & (cx <= 0) & (cy >= 0) & (cy <= F) & (np.hypot(cx + F, cy - F) >= F)
fr = (cx >= W) & (cx <= W + F) & (cy >= 0) & (cy <= F) & (np.hypot(cx - W - F, cy - F) >= F)
in_bar |= fl | fr
d = np.full(cx.shape, -1.0)
pts = np.stack([cx[~in_bar], cy[~in_bar]], 1)
best = np.full(len(pts), np.inf)
for chunk in np.array_split(outline, max(1, len(outline) // 2000)):
    best = np.minimum(best, np.sqrt(((pts[:, None, :] - chunk[None, :, :]) ** 2).sum(-1)).min(1))
d[~in_bar] = best
u = (cx - W / 2) / (W / 2)
across = np.where(np.abs(u) >= 1, 0.0, np.cos(math.pi / 2 * u) ** 2)
expected = np.where(in_bar, 0.0, (STRENGTH / 0.35) * curve(np.maximum(d, 0)) * across)

# Pixels within 1 px of the silhouette (bar or fillet) are the notch's own
# antialiased edge, drawn over the glow: left out.
near_fillet = ((cx >= -F - 1) & (cx <= 1) & (cy <= F + 1)) | ((cx >= W - 1) & (cx <= W + F + 1) & (cy <= F + 1))
keep = (~in_bar) & (d >= 1.0) & ~near_fillet
a = alpha.ravel()
err = np.abs(a[keep] - expected[keep])
res = {"pixelsCompared": int(keep.sum()), "maxError": float(err.max()), "meanError": float(err.mean())}
res["maxAlpha"] = float(a[keep].max())
res["outsideBarWidthMaxAlpha"] = float(a[keep & ((cx < 0) | (cx > W))].max())
res["besideSidesMaxAlpha"] = float(a[keep & (cy < H - R)].max())
res["beyondReachNonZero"] = int(((~in_bar) & (d > SIZE + 0.5) & (a > 0)).sum())
res["imageEdgeMaxAlpha"] = float(max(alpha[:, 0].max(), alpha[:, -1].max(), alpha[-1, :].max()))
res["symmetry"] = float(np.abs(alpha - alpha[:, ::-1]).max()) if abs((bx + W / 2) - w / 2) < 0.01 else None

# Along the row just below the edge: alpha at u = 0, ±0.25, ±0.5, ±0.75, ±0.9.
row = int(math.floor(H + 2))
def at_u(uu):
    i = int(math.floor(bx + W / 2 + uu * W / 2))
    return round(float(alpha[row, i]), 4)
res["acrossRow"] = {"d": round(row + 0.5 - H, 3), "values": {str(uu): at_u(uu) for uu in (-0.9, -0.75, -0.5, -0.25, 0, 0.25, 0.5, 0.75, 0.9)}}
vals = [at_u(uu) for uu in (0, 0.25, 0.5, 0.75, 0.9)]
res["fallsTowardEdges"] = all(vals[i] >= vals[i + 1] for i in range(len(vals) - 1)) and vals[0] > vals[-1]
# Down the middle.
col = alpha[:, int(math.floor(bx + W / 2))]
res["downMiddle"] = {str(dd): round(float(col[int(math.floor(H + dd))]), 4) for dd in (1, 4, 8, 16, 24, 32, 48)}
want = np.array([int(colour[k:k+2], 16) / 255 for k in (1, 3, 5)])
# Judged where alpha >= 0.15. An 8-bit channel stored at alpha a can be off by
# up to 1/(255·a) once unpremultiplied, so the allowed error is that bound.
COLOUR_ALPHA = 0.15
vis = keep & (a >= COLOUR_ALPHA)
res["colourMaxError"] = float(np.abs(img[:, :, :3].reshape(-1, 3)[vis] - want).max()) if vis.any() else None
res["colourBound"] = 1 / (255 * COLOUR_ALPHA)
res["colourPixels"] = int(vis.sum())
ii, jj = int(math.floor(bx + W / 2)), int(H / 2)
res["insideNotch"] = [round(float(v), 3) for v in img[jj, ii]]
print(json.dumps(res))
