#!/usr/bin/env python3
"""Pixel checks on the notification light's particle cloud.

    light_proto_pixels.py nopop <cloud-only grid png> <off png> <on png> <tileW> <tileH> <cols> <frames> <scale> <barW> <barH> <fillet> <radius> <tail>

Reads PNGs by way of `magick ... rgba:-` (no PIL here). `grid` is the cloud
alone (view=1) at 1/60 s steps over several cycles, tile by tile, row by row;
`off` and `on` are one frame with the cloud off and on.

  determinism  a second render of the same frame is byte identical (caller)
  band         added light is zero outside the band the cloud may occupy
  additive     cloud on is never darker than cloud off, anywhere
  no pop       total added light L(t) changes by <= 3% of its mean per frame;
               each 45 px stretch (the ones with at least half the busiest's light) by <= 8% of its own mean
  no aliasing  Pearson correlation of the added-light image at t and t+1/60 s
               is >= 0.6 (static sparkle gives about 0)

Prints JSON: the numbers and a list of named failures.
"""
import json, subprocess, sys
import numpy as np


def read(path):
    size = subprocess.run(["magick", "identify", "-format", "%w %h", path], capture_output=True, text=True, check=True).stdout.split()
    w, h = int(size[0]), int(size[1])
    raw = subprocess.run(["magick", path, "-depth", "8", "rgba:-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.uint8).reshape(h, w, 4)


def main():
    mode = sys.argv[1]
    assert mode == "nopop"
    grid_png, off_png, on_png = sys.argv[2:5]
    tw, th, cols, frames = (int(float(v)) for v in sys.argv[5:9])
    scale = float(sys.argv[9])
    bw, bh, fillet, radius, tail = (float(v) for v in sys.argv[10:15])
    tw_px, th_px = int(round(tw * scale)), int(round(th * scale))
    out = {"failures": []}

    # --- band, additive -------------------------------------------------
    off, on = read(off_png).astype(int), read(on_png).astype(int)
    diff = on[:, :, :3] - off[:, :, :3]
    out["additiveMinDelta"] = int(diff.min())
    if diff.min() < -1:
        out["failures"].append("additive: cloud on is darker than cloud off by %d/255" % -diff.min())
    if (on[:, :, 3] != off[:, :, 3]).any():
        out["failures"].append("additive: alpha changed")
    added = diff.max(axis=2)
    h, w = added.shape
    ys, xs = np.mgrid[0:h, 0:w]
    cx = w / 2 / scale
    # outside the bar's footprint widened by the fillet and the tail's reach,
    # and below the radius, nothing may be added
    lx = (xs + 0.5) / scale
    ly = (ys + 0.5) / scale
    outside = (np.abs(lx - cx) > bw / 2 + fillet + tail * radius + 2) | (ly > bh + radius + 2)
    out["addedOutsideBand"] = int((added[outside] > 1).sum())
    if out["addedOutsideBand"]:
        out["failures"].append("band: %d pixels outside the band have added light" % out["addedOutsideBand"])
    inband = (~outside) & ~((np.abs(lx - cx) < bw / 2) & (ly < bh))   # not under the notch
    out["bandPixels"] = int(inband.sum())
    out["fractionAbove2of255"] = round(float((added[inband] > 2).mean()), 4)
    out["fractionAbove8of255"] = round(float((added[inband] > 8).mean()), 4)

    # --- no pop, no aliasing -------------------------------------------
    grid = read(grid_png)
    lum = []
    stretches = []
    group = max(1, int(round(45 * scale)))
    prev = None
    corr = []
    for f in range(frames):
        r, c = divmod(f, cols)
        tile = grid[r * th_px:(r + 1) * th_px, c * tw_px:(c + 1) * tw_px, :3].astype(np.float64).sum(axis=2)
        lum.append(tile.sum())
        stretches.append([tile[:, g:g + group].sum() for g in range(0, tile.shape[1], group)])
        if prev is not None:
            a, b = prev.ravel(), tile.ravel()
            if a.std() > 0 and b.std() > 0:
                corr.append(float(np.corrcoef(a, b)[0, 1]))
        prev = tile
    lum = np.array(lum)
    st = np.array(stretches)
    mean = lum.mean()
    step = np.abs(np.diff(lum)) / mean
    out["meanLight"] = round(float(mean), 1)
    out["lightRange"] = [round(float(lum.min() / mean), 3), round(float(lum.max() / mean), 3)]
    out["maxFrameChange"] = round(float(step.max()), 4)
    sm = st.mean(axis=0)
    live = sm > 0.5 * sm.max()   # stretches holding a good share of the light; the band's thin edges have a handful of grains
    sstep = np.abs(np.diff(st[:, live], axis=0)) / sm[live]
    out["maxStretchChange"] = round(float(sstep.max()), 4)
    out["minCorrelation"] = round(min(corr), 3)
    out["meanCorrelation"] = round(float(np.mean(corr)), 3)
    if step.max() > 0.03:
        out["failures"].append("no pop: total light changes by %.1f%% in one frame (limit 3%%)" % (100 * step.max()))
    if sstep.max() > 0.08:
        out["failures"].append("no pop: a 45 px stretch changes by %.1f%% in one frame (limit 8%%)" % (100 * sstep.max()))
    if min(corr) < 0.6:
        out["failures"].append("no aliasing: frame-to-frame correlation falls to %.2f (limit 0.6)" % min(corr))
    print(json.dumps(out))


main()
