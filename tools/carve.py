"""Carves props and ground tiles out of a reference street image.

  python tools/carve.py

Props: cut from a bounding box, then the background is removed by flooding in
from the box edges with a colour tolerance and keeping the largest remaining
blob. Ground: cut as a 64x32 diamond with the baked lighting flattened, so the
tile repeats without banding.
"""
import os
import numpy as np
from PIL import Image
from collections import deque

SRC = "C:/Projects/pixel-snapper-py/output/magnific_please-use-a-similar-isom_3zXWnXpREY.png"
OUT = "sprites/street/props"
OUT_GROUND = "sprites/street/ground"
TILE_W, TILE_H = 64, 32

PROPS = {
    # name:            (x0,  y0,  x1,  y1,  tolerance)
    "phone_box":        (262,  96, 302, 182, 42),
    "barrel_left":      (114, 158, 148, 202, 40),
    "barrel_right":     (132, 142, 168, 194, 40),
    "skip_large":       (186, 124, 232, 176, 38),
    "skip_small":       (160, 136, 196, 172, 38),
    "cardboard_box":    (202, 152, 238, 182, 38),
    "bike_rack":        (362, 172, 424, 208, 34),
    "wall_lamp":        (252,  52, 288,  96, 46),
}

GROUND = {
    # name:        centre of a clean, evenly lit patch
    "cobble_road":  (262, 224),
    "pavement_r":   (410, 206),
    "pavement_l":   (100, 214),
}

def flood_background(rgb, tol, palette=None):
    """Mark pixels reachable from the border that match the background.

    `palette` is a set of background colours sampled from a ring around the
    object; matching against all of them peels off ground that a single median
    colour leaves behind, which is what happens when a prop is tonally close to
    the pavement it stands on."""
    h, w, _ = rgb.shape
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append((y, x)); seen[y, x] = True
    for y in range(h):
        for x in (0, w - 1):
            if not seen[y, x]:
                q.append((y, x)); seen[y, x] = True
    if palette is None or len(palette) == 0:
        palette = np.array([np.median([rgb[y, x] for y, x in list(q)], axis=0)], float)
    bg = np.zeros((h, w), bool)
    while q:
        y, x = q.popleft()
        if np.abs(palette - rgb[y, x].astype(float)).sum(axis=1).min() > tol:
            continue
        bg[y, x] = True
        for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
            ny, nx = y+dy, x+dx
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return bg

def largest_blob(mask):
    h, w = mask.shape
    best, seen = None, np.zeros((h, w), bool)
    for sy in range(h):
        for sx in range(w):
            if not mask[sy, sx] or seen[sy, sx]:
                continue
            q = deque([(sy, sx)]); seen[sy, sx] = True; blob = []
            while q:
                y, x = q.popleft(); blob.append((y, x))
                for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
                    ny, nx = y+dy, x+dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True; q.append((ny, nx))
            if best is None or len(blob) > len(best):
                best = blob
    out = np.zeros((h, w), bool)
    for y, x in best or []:
        out[y, x] = True
    return out

def background_palette(im, box, pad=5):
    """Colours found in a ring just outside the object's box — i.e. the ground
    and wall it is standing against."""
    x0, y0, x1, y1 = box
    outer = np.array(im.crop((max(0, x0-pad), max(0, y0-pad), x1+pad, y1+pad)).convert("RGB"))
    inner = np.zeros(outer.shape[:2], bool)
    inner[pad:pad+(y1-y0), pad:pad+(x1-x0)] = True
    ring = outer[~inner]
    # Only the colours the ring is actually MADE of. Taking every unique colour
    # sweeps in the object's own tones (the ring clips neighbouring props and
    # shadows) and then everything matches the background.
    from collections import Counter
    counts = Counter(map(tuple, ring))
    common = [c for c, n in counts.most_common(10) if n >= max(3, 0.01 * len(ring))]
    return np.array(common, float) if common else np.array([np.median(ring, axis=0)], float)

def carve_props(im):
    report = []
    for name, (x0, y0, x1, y1, tol) in PROPS.items():
        rgb = np.array(im.crop((x0, y0, x1, y1)).convert("RGB"))
        keep = largest_blob(~flood_background(rgb, tol))
        rgba = np.dstack([rgb, np.where(keep, 255, 0).astype(np.uint8)])
        ys, xs = np.where(keep)
        if len(ys) == 0:
            report.append((name, 0, 0, 0)); continue
        tight = rgba[ys.min():ys.max()+1, xs.min():xs.max()+1]
        Image.fromarray(tight, "RGBA").save(os.path.join(OUT, name + ".png"))
        report.append((name, tight.shape[1], tight.shape[0],
                       100.0 * keep.sum() / keep.size))
    return report

def diamond_mask(w, h):
    yy, xx = np.mgrid[0:h, 0:w]
    return (np.abs((xx - (w-1)/2.0) / (w/2.0)) + np.abs((yy - (h-1)/2.0) / (h/2.0))) <= 1.0

def flatten_lighting(rgb):
    """Divide out the local brightness so the baked light gradient goes away and
    only the texture remains — otherwise a repeated tile shows obvious banding."""
    f = rgb.astype(float)
    lum = f.mean(axis=2, keepdims=True)
    k = 9
    pad = np.pad(lum[:, :, 0], k//2, mode="edge")
    blur = np.zeros_like(lum[:, :, 0])
    for dy in range(k):
        for dx in range(k):
            blur += pad[dy:dy+lum.shape[0], dx:dx+lum.shape[1]]
    blur /= k * k
    target = float(blur.mean())
    scale = np.clip(target / np.maximum(blur, 1.0), 0.6, 1.7)[:, :, None]
    return np.clip(f * scale, 0, 255).astype(np.uint8)

def carve_ground(im):
    report = []
    mask = diamond_mask(TILE_W, TILE_H)
    for name, (cx, cy) in GROUND.items():
        box = (cx - TILE_W//2, cy - TILE_H//2, cx + TILE_W//2, cy + TILE_H//2)
        rgb = np.array(im.crop(box).convert("RGB"))
        flat = flatten_lighting(rgb)
        for tag, data in (("raw", rgb), ("flat", flat)):
            rgba = np.dstack([data, np.where(mask, 255, 0).astype(np.uint8)])
            Image.fromarray(rgba, "RGBA").save(os.path.join(OUT_GROUND, "%s_%s.png" % (name, tag)))
        # how much banding would a repeat show? compare opposite edges
        seam = float(np.abs(flat[:, 0].astype(int) - flat[:, -1].astype(int)).mean())
        raw_seam = float(np.abs(rgb[:, 0].astype(int) - rgb[:, -1].astype(int)).mean())
        report.append((name, raw_seam, seam))
    return report

def main():
    im = Image.open(SRC).convert("RGB")
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(OUT_GROUND, exist_ok=True)
    print("props carved:")
    for name, w, h, fill in carve_props(im):
        print("   %-15s %3dx%-3d  %.0f%% of its box kept" % (name, w, h, fill))
    print("\nground tiles (64x32 diamonds), edge mismatch = how visible a repeat seam is:")
    for name, raw, flat in carve_ground(im):
        print("   %-13s raw %5.1f  ->  lighting-flattened %5.1f" % (name, raw, flat))

if __name__ == "__main__":
    main()
