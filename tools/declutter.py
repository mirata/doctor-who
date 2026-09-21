"""Strips the pavement out of the carved props.

The props were cut from a reference image as rectangles, so each one carries a
slab of ground around its feet and often a piece of whatever stood next to it.
They are a single connected blob, so dropping loose fragments does nothing —
the ground has to be flooded away from the edges of the frame.

The flood compares each pixel to the NEIGHBOUR it spread from rather than to
one background colour, so it follows the ground's shading and grime instead of
stopping at the first slab line. That is also why it needs a tolerance: too
high and it walks up into the object through a soft edge.

Originals are kept in props/_raw/ so a bad tolerance is never destructive, and
re-running always works from those rather than eating its own output.

    python tools/declutter.py            # clean everything, default tolerance
    python tools/declutter.py 30         # tighter
    python tools/declutter.py 60 barrel_left phone_box
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

PROPS = "sprites/street/props"
RAW = os.path.join(PROPS, "_raw")

# Carved from the reference. The generated ones (bins, bollard, postbox) are
# drawn clean and must not be touched.
CARVED = ["barrel_left", "barrel_right", "bike_rack", "cardboard_box",
          "phone_box", "skip_large", "skip_small", "wall_lamp"]


def clean(name, tol):
    raw_path = os.path.join(RAW, name + ".png")
    live_path = os.path.join(PROPS, name + ".png")
    if not os.path.exists(raw_path):                 # first run: keep the original
        os.makedirs(RAW, exist_ok=True)
        Image.open(live_path).save(raw_path)

    im = Image.open(raw_path).convert("RGBA")
    a = np.array(im).astype(int)
    h, w = a.shape[:2]
    solid = a[:, :, 3] > 0

    seeds = [(y, x) for x in range(w) for y in (0, h - 1) if solid[y, x]]
    seeds += [(y, x) for y in range(h) for x in (0, w - 1) if solid[y, x]]

    ground = np.zeros((h, w), bool)
    queue = deque()
    for y, x in seeds:
        if not ground[y, x]:
            ground[y, x] = True
            queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        here = a[y, x, :3]
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if not (0 <= ny < h and 0 <= nx < w):
                continue
            if ground[ny, nx] or not solid[ny, nx]:
                continue
            if int(np.abs(a[ny, nx, :3] - here).sum()) <= tol:
                ground[ny, nx] = True
                queue.append((ny, nx))

    out = a.copy()
    out[ground, 3] = 0
    kept = Image.fromarray(out.astype(np.uint8), "RGBA")
    box = kept.getbbox()
    if box is None:
        return name, im.size, None, 0
    kept = kept.crop(box)
    kept.save(live_path)
    return name, im.size, kept.size, int(ground.sum())


def main():
    args = [a for a in sys.argv[1:]]
    # 8 is deliberately timid. The ground and the props share colours and touch
    # smoothly, so a flood that removes ALL the ground also eats into the art:
    # at 14 the phone box starts losing its base, by 20 the barrels hollow out.
    # This takes off what is clearly separable and leaves the rest to hand.
    tol = 8
    if args and args[0].isdigit():
        tol = int(args.pop(0))
    names = args or CARVED
    print("tolerance %d; originals in %s" % (tol, RAW))
    for name in names:
        n, before, after, removed = clean(name, tol)
        if after is None:
            print("  %-15s EVERYTHING removed - tolerance too high" % n)
            continue
        print("  %-15s %-9s -> %-9s  %d px of ground removed"
              % (n, "%dx%d" % before, "%dx%d" % after, removed))


if __name__ == "__main__":
    main()
