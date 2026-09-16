#!/usr/bin/env python3
"""Compare a rendered glow PNG with the curve, pixel by pixel.

    glow_pixels.py <png> <barX> <W> <H> <R> <F> <colour> <size>

Distances are NOT taken from the shader's formula. The notch's outline -- left
fillet arc, left side, bottom-left arc, bottom, bottom-right arc, right side,
right fillet arc -- is traced as a dense polyline (0.02 px steps), and each
pixel centre's distance to it is measured by brute force. The expected alpha
is glow.js's curve at that distance, re-implemented here from the same knots.
Prints one JSON object.
"""
import json, math, subprocess, sys
import numpy as np

png, bx, W, H, R, F, colour, SIZE = sys.argv[1], float(sys.argv[2]), *map(float, sys.argv[3:7]), sys.argv[7], float(sys.argv[8])

# glow.js's full-size knots, with every distance scaled to reach zero at SIZE.
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
    d = np.asarray(d, dtype=float)
    out = np.zeros_like(d)
    out[d <= KNOTS[0][0]] = KNOTS[0][1]
    for i in range(len(KNOTS) - 1):
        (d0, a0), (d1, a1) = KNOTS[i], KNOTS[i+1]
        sel = (d > d0) & (d <= d1)
        h = d1 - d0; t = (d[sel] - d0) / h
        out[sel] = (2*t**3 - 3*t**2 + 1) * a0 + (t**3 - 2*t**2 + t) * h * M[i] + (-2*t**3 + 3*t**2) * a1 + (t**3 - t**2) * h * M[i+1]
    return out

# The outline, in bar coordinates (y down).
def arc(cx, cy, r, a0, a1, step=0.02):
    n = max(2, int(abs(a1 - a0) * r / step))
    t = np.linspace(a0, a1, n)
    return np.stack([cx + r * np.cos(t), cy + r * np.sin(t)], 1)
def seg(x0, y0, x1, y1, step=0.02):
    n = max(2, int(math.hypot(x1 - x0, y1 - y0) / step))
    t = np.linspace(0, 1, n)
    return np.stack([x0 + (x1 - x0) * t, y0 + (y1 - y0) * t], 1)
outline = np.concatenate([
    arc(-F, F, F, -math.pi / 2, 0) if F > 0 else np.zeros((0, 2)),   # left fillet: (-F,0) → (0,F)
    seg(0, F, 0, H - R),
    arc(R, H - R, R, math.pi, math.pi / 2),                         # bottom-left
    seg(R, H, W - R, H),
    arc(W - R, H - R, R, math.pi / 2, 0),                           # bottom-right
    seg(W, H - R, W, F),
    arc(W + F, F, F, math.pi, 3 * math.pi / 2) if F > 0 else np.zeros((0, 2)),  # right fillet: (W,F) → (W+F,0)
])

def inside(x, y):
    """Whether bar-coordinate points are inside the silhouette."""
    in_bar = (x >= 0) & (x <= W) & (y <= H)
    corner_l = (x < R) & (y > H - R) & (np.hypot(x - R, y - (H - R)) > R)
    corner_r = (x > W - R) & (y > H - R) & (np.hypot(x - (W - R), y - (H - R)) > R)
    in_bar &= ~corner_l & ~corner_r
    fl = (x >= -F) & (x <= 0) & (y >= 0) & (y <= F) & (np.hypot(x + F, y - F) >= F)
    fr = (x >= W) & (x <= W + F) & (y >= 0) & (y <= F) & (np.hypot(x - W - F, y - F) >= F)
    return in_bar | fl | fr

raw = subprocess.run(["magick", png, "-depth", "8", "rgba:-"], capture_output=True, check=True).stdout
w, h = map(int, subprocess.run(["magick", "identify", "-format", "%w %h", png], capture_output=True, text=True).stdout.split())
img = np.frombuffer(raw, dtype=np.uint8).reshape(h, w, 4).astype(float) / 255
alpha = img[:, :, 3]

def dist(xs, ys):
    """Brute-force distance from bar-coordinate points to the outline."""
    pts = np.stack([xs, ys], 1)
    best = np.full(len(pts), np.inf)
    for chunk in np.array_split(outline, max(1, len(outline) // 2000)):
        dd = np.sqrt(((pts[:, None, :] - chunk[None, :, :]) ** 2).sum(-1)).min(1)
        best = np.minimum(best, dd)
    return best

res = {}
barX = bx
def px_at(x, y):   # bar coords → pixel indices
    return int(math.floor(barX + x)), int(math.floor(y))

# 1. Every pixel, against the curve, outside the silhouette (and below the
#    screen edge). Pixels whose centre is within 1 px of the outline are left
#    out: the notch's own antialiased edge is drawn over them.
yy, xx = np.mgrid[0:h, 0:w]
cx = (xx + 0.5 - barX).ravel(); cy = (yy + 0.5).ravel()
out_mask = ~inside(cx, cy)
d = np.full(cx.shape, -1.0)
d[out_mask] = dist(cx[out_mask], cy[out_mask])
keep = out_mask & (d >= 1.0)
err = np.abs(alpha.ravel()[keep] - curve(d[keep]))
res["pixelsCompared"] = int(keep.sum())
res["maxError"] = float(err.max())
res["meanError"] = float(err.mean())
worst = np.argmax(np.where(keep, np.abs(alpha.ravel() - curve(np.maximum(d, 0))), -1))
res["worst"] = {"x": float(cx[worst]), "y": float(cy[worst]), "distance": float(d[worst]), "alpha": float(alpha.ravel()[worst]), "expected": float(curve([d[worst]])[0])}
res["nonZeroBeyondReach"] = int(((d > SIZE + 0.5) & (alpha.ravel() > 0)).sum())
res["maxDistanceOfNonZero"] = float(d[alpha.ravel() > 0].max())
res["imageEdgeMaxAlpha"] = float(max(alpha[:, 0].max(), alpha[:, -1].max(), alpha[-1, :].max()))

# 2. The knot distances, in three directions: the pixel nearest each knot, its
#    exact distance, its alpha, and the curve at that exact distance.
def probe(name, fn):
    rows = []
    for dd, _ in KNOTS:
        x, y = fn(dd)
        i, j = px_at(x, y)
        md = float(dist(np.array([i + 0.5 - barX]), np.array([j + 0.5]))[0])
        rows.append({"d": round(dd, 3), "measuredDistance": round(md, 3), "alpha": round(float(alpha[j, i]), 4),
                     "curve": round(float(curve([md])[0]), 4), "curveAtKnot": round(float(curve([dd])[0]), 4)})
    res[name] = rows
probe("belowBottom", lambda dd: (W / 2 - 0.5, H + dd))
# Along the screen edge, out from the tip of the left fillet: the outline's
# nearest point there is the tip itself, so the glow follows the fillet's
# curve onto the screen edge rather than a rectangle's side.
probe("screenEdgeBeyondFillet", lambda dd: (-F - dd, 0.5))
diag = math.sqrt(0.5)
probe("cornerDiagonal", lambda dd: (R - (R + dd) * diag, H - R + (R + dd) * diag))

# 3. Colour: every visible glow pixel carries exactly the glow colour.
want = np.array([int(colour[k:k+2], 16) / 255 for k in (1, 3, 5)])
vis = keep & (alpha.ravel() >= 0.3)   # 8-bit colour is too coarse to judge at lower alpha
rgb = img[:, :, :3].reshape(-1, 3)[vis]
res["colourMaxError"] = float(np.abs(rgb - want).max()) if vis.any() else None

# 4. Under the notch: nothing but the notch.
inner = inside(cx, cy) & (d == -1.0)
ii, jj = int(math.floor(barX + W / 2)), int(H / 2)
res["insideNotch"] = [round(float(v), 3) for v in img[jj, ii]]

# 5. Smoothness down the middle: the largest change between neighbouring
#    pixels, and the largest change in that change.
col = alpha[:, int(math.floor(barX + W / 2))]
start = int(math.ceil(H)) + 1
steps = np.diff(col[start:])
res["maxStep"] = float(np.abs(steps).max())
res["maxStepChange"] = float(np.abs(np.diff(steps)).max())
res["profile"] = [round(float(v), 4) for v in col[start - 1:start + 90]]
print(json.dumps(res))
