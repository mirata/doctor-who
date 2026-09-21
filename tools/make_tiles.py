"""Generates sprites/street/tiles.png and tiles.json - the street tileset.

  python tools/make_tiles.py

TILE_W/TILE_H are the ground diamond; cell size, block heights and all the
patterns derive from them, so the whole set rescales from one value. Keep
TILE_W = 2 * TILE_H: the game is 2:1 isometric throughout.

tiles.json is the single source of truth for what each tile is called and
whether it is walkable or solid; tools/build_street.gd reads it.
"""
import json
import random

import numpy as np
from PIL import Image, ImageChops, ImageDraw

# A wall face spans TILE_W/2 across. The reference's window bays are ~45 px
# apart, so TILE_W = 96 puts one window per tile with brick either side.
TILE_W, TILE_H = 96, 48
COLS = 8

# The grid Godot works on is a QUARTER of the art tile. Floors are drawn big and
# sliced into SUB x SUB pieces that reassemble invisibly, so painting a floor is
# still one stamp while props, thin walls, collision and pathfinding all get to
# work at quarter resolution.
SUB = 4
TALLEST = 2.0                                  # tallest block, in tile-heights
CELL_W, CELL_H = TILE_W, int(TILE_H * (1 + TALLEST))
U = TILE_H                                     # one tile-height

# Feature sizes measured off the reference art, in pixels. Keeping them in
# pixels rather than as fractions of the face means they stay the right size if
# the tile size changes again.
REF = {
    "course": 8,        # brick course height
    "win_w": 32, "win_h": 52, "win_sill": 14,
    "door_w": 32, "door_h": 64,
    "cobble": 16,       # one cobble stone across
    "flag": 30,         # one paving slab across
    "kerb": 4,          # the kerb lip is a thin band, not a step
    "phone_h": 86, "can_h": 40, "skip_h": 52, "bollard_h": 30, "post_h": 62,
}

C = {
    "cobble":    (0x46, 0x40, 0x45), "cobble_lo": (0x39, 0x34, 0x39),
    "cobble_hi": (0x55, 0x4e, 0x52), "mortar":    (0x1d, 0x1c, 0x24),
    "flag":      (0x5c, 0x52, 0x4c), "flag_lo":   (0x4a, 0x42, 0x3e),
    "flag_hi":   (0x6b, 0x60, 0x58),
    "road":      (0x32, 0x2c, 0x2e), "road_lo":   (0x26, 0x21, 0x23),
    "road_hi":   (0x3d, 0x36, 0x38),
    "dirt":      (0x4a, 0x3a, 0x2c), "dirt_lo":   (0x3a, 0x2d, 0x22),
    "water":     (0x3a, 0x42, 0x50), "water_hi":  (0x5a, 0x66, 0x76),
    "brick":     (0x6d, 0x51, 0x3b), "brick_l":   (0x52, 0x34, 0x25),
    "brick_r":   (0x3e, 0x27, 0x20),
    "stone":     (0x5c, 0x4c, 0x41), "stone_l":   (0x4a, 0x40, 0x3c),
    "stone_r":   (0x35, 0x30, 0x35),
    "wood":      (0x79, 0x5a, 0x3f), "wood_l":    (0x67, 0x42, 0x2c),
    "wood_r":    (0x46, 0x31, 0x29),
    "iron":      (0x30, 0x2e, 0x30), "iron_hi":   (0x4a, 0x47, 0x48),
    "glass":     (0x28, 0x2c, 0x33),
    "hi":        (0x9f, 0x7e, 0x56), "poster":    (0xa8, 0x93, 0x6a),
    "stone_hi":  (0x72, 0x63, 0x57), "moss":      (0x46, 0x52, 0x33),
    "moss_hi":   (0x5c, 0x6b, 0x40),
    "phone":     (0x8c, 0x2f, 0x2a), "phone_dk":  (0x5e, 0x1e, 0x1c),
    "phone_hi":  (0xa8, 0x44, 0x3a),
    "can":       (0x4a, 0x47, 0x42), "can_dk":    (0x33, 0x31, 0x2e),
    "can_hi":    (0x63, 0x5f, 0x58),
    "paper":     (0xb5, 0xad, 0x99), "paper_dk":  (0x8a, 0x82, 0x70),
    "grime":     (0x22, 0x1f, 0x22), "rust":      (0x6b, 0x40, 0x28),
}

CX, CY = TILE_W // 2, CELL_H - TILE_H // 2      # footprint centre inside a cell


# ---------------------------------------------------------------- geometry --
def ground(a, b):
    """Tile-space (a, b in 0..1 along the two iso axes) -> pixel."""
    return (CX + (a - b) * TILE_W / 2.0, CY - TILE_H / 2.0 + (a + b) * TILE_H / 2.0)


def diamond(cx, cy, w=None, h=None):
    """The footprint diamond.

    w/h default to the CURRENT tile size and must be resolved here rather than
    as default arguments: Python binds those once at import, so `w=TILE_W` would
    ignore at_size() and draw every quarter-native tile at the big size."""
    w = TILE_W if w is None else w
    h = TILE_H if h is None else h
    return [(cx, cy - h / 2), (cx + w / 2 - 1, cy), (cx, cy + h / 2 - 1), (cx - w / 2, cy)]


def face_pt(side, u, v, h):
    """A point on a block's visible face. u runs 0..1 across it, v 0..1 up it."""
    if side == "l":
        return (CX - TILE_W / 2 + u * TILE_W / 2, CY + u * TILE_H / 2 - v * h)
    return (CX + u * TILE_W / 2, CY + TILE_H / 2 - u * TILE_H / 2 - v * h)


# ------------------------------------------------------------------ floors --
def floor_base(d, col):
    d.polygon(diamond(CX, CY), fill=col)


def cobbles(d, seed, n=None, base="cobble"):
    n = n or max(2, int(round(TILE_W / float(REF["cobble"]))))
    rnd = random.Random(seed)
    shades = [C[base], C[base + "_lo"], C[base + "_hi"]]
    for i in range(n):
        for j in range(n):
            x, y = ground((i + 0.5) / n, (j + 0.5) / n)
            d.polygon(diamond(x, y, TILE_W / n - 1, TILE_H / n - 1), fill=rnd.choice(shades))


def flagstones(d, seed, n=None, base="flag"):
    n = n or max(1, int(round(TILE_W / float(REF["flag"]))))
    rnd = random.Random(seed)
    shades = [C[base], C[base + "_lo"], C[base + "_hi"]]
    for i in range(n):
        for j in range(n):
            x, y = ground((i + 0.5) / n, (j + 0.5) / n)
            d.polygon(diamond(x, y, TILE_W / n - 2, TILE_H / n - 2), fill=rnd.choice(shades))


def speckle(d, seed, col, count):
    rnd = random.Random(seed)
    for _ in range(count):
        d.point(ground(rnd.random(), rnd.random()), fill=col)


def cracks(d, seed, col, n=3):
    rnd = random.Random(seed)
    for _ in range(n):
        a, b = rnd.uniform(.1, .9), rnd.uniform(.1, .9)
        pts = [ground(a, b)]
        for _ in range(rnd.randint(3, 6)):
            a = min(.97, max(.03, a + rnd.uniform(-.18, .18)))
            b = min(.97, max(.03, b + rnd.uniform(-.18, .18)))
            pts.append(ground(a, b))
        d.line(pts, fill=col)


def puddle(d, size=0.5):
    x, y = ground(0.5, 0.5)
    w, h = TILE_W * size, TILE_H * size
    d.ellipse([x - w / 2, y - h / 2, x + w / 2, y + h / 2], fill=C["water"])
    d.ellipse([x - w / 3, y - h / 3, x + w / 6, y], outline=C["water_hi"])


def drain(d):
    x, y = ground(0.5, 0.5)
    d.polygon(diamond(x, y, TILE_W * .45, TILE_H * .45), fill=C["iron"])
    for k in range(-2, 3):
        d.line([ground(0.5 + k * .05, 0.34), ground(0.5 + k * .05, 0.66)], fill=C["mortar"])


def manhole(d):
    x, y = ground(0.5, 0.5)
    d.polygon(diamond(x, y, TILE_W * .5, TILE_H * .5), fill=C["iron"])
    d.polygon(diamond(x, y, TILE_W * .38, TILE_H * .38), outline=C["iron_hi"])


# ------------------------------------------------------------------ blocks --
def block(d, h, top, left, right, cap=None):
    d.polygon([face_pt("l", 0, 0, h), face_pt("l", 1, 0, h),
               face_pt("l", 1, 1, h), face_pt("l", 0, 1, h)], fill=left)
    d.polygon([face_pt("r", 0, 0, h), face_pt("r", 1, 0, h),
               face_pt("r", 1, 1, h), face_pt("r", 0, 1, h)], fill=right)
    d.polygon(diamond(CX, CY - h), fill=top)
    if cap:
        d.line([(CX - TILE_W / 2, CY - h), (CX, CY - h - TILE_H / 2)], fill=cap)
        d.line([(CX, CY - h - TILE_H / 2), (CX + TILE_W / 2 - 1, CY - h)], fill=cap)


def coursing(d, h, courses, joint, seed=0):
    """Brick courses on both faces, with staggered vertical joints. `courses` is
    ignored in favour of the reference's course height, so bricks stay the same
    size on a low kerb and a full wall."""
    courses = max(1, int(round(h / float(REF["course"]))))
    for side in ("l", "r"):
        for k in range(1, courses):
            v = k / float(courses)
            d.line([face_pt(side, 0, v, h), face_pt(side, 1, v, h)], fill=joint)
        for k in range(courses):
            v0, v1 = k / float(courses), (k + 1) / float(courses)
            offset = 0.5 if k % 2 else 0.0
            for m in range(4):
                u = (m + offset) / 4.0
                if 0.0 < u < 1.0:
                    d.line([face_pt(side, u, v0, h), face_pt(side, u, v1, h)], fill=joint)


def opening(d, h, side, u0, u1, v0, v1, fill, frame):
    d.polygon([face_pt(side, u0, v0, h), face_pt(side, u1, v0, h),
               face_pt(side, u1, v1, h), face_pt(side, u0, v1, h)],
              fill=fill, outline=frame)


def opening_px(d, h, side, w_px, h_px, base_px, fill, frame):
    """An opening w_px wide and h_px tall, sitting base_px up the wall, centred
    across the face. Sizes come from the reference rather than from fractions."""
    face_w = TILE_W / 2.0
    u0 = max(0.04, 0.5 - (w_px / 2.0) / face_w)
    u1 = min(0.96, 0.5 + (w_px / 2.0) / face_w)
    v0 = min(0.94, base_px / float(h))
    v1 = min(0.97, (base_px + h_px) / float(h))
    opening(d, h, side, u0, u1, v0, v1, fill, frame)
    return u0, u1, v0, v1


# ------------------------------------------------------------------- tiles --
def t_cobble(seed, wet=False, crack=False):
    def f(d):
        floor_base(d, C["mortar"])
        cobbles(d, seed)
        if crack:
            cracks(d, seed + 1, C["mortar"])
        if wet:
            puddle(d, size=0.55)
    return f


def t_flag(seed, crack=False, with_drain=False):
    def f(d):
        floor_base(d, C["mortar"])
        flagstones(d, seed)
        if crack:
            cracks(d, seed + 1, C["mortar"], 2)
        if with_drain:
            drain(d)
    return f


def t_road(seed, patch=False, wet=False):
    def f(d):
        floor_base(d, C["road"])
        speckle(d, seed, C["road_lo"], TILE_W)
        speckle(d, seed + 9, C["road_hi"], TILE_W // 3)
        if patch:
            x, y = ground(0.5, 0.5)
            d.polygon(diamond(x, y, TILE_W * .6, TILE_H * .6), fill=C["road_lo"])
        if wet:
            puddle(d, size=0.45)
    return f


def t_simple(col, seed, fleck):
    def f(d):
        floor_base(d, C[col])
        speckle(d, seed, C[fleck], TILE_W)
    return f


def t_manhole():
    def f(d):
        floor_base(d, C["mortar"])
        cobbles(d, 21)
        manhole(d)
    return f


def t_gutter():
    def f(d):
        floor_base(d, C["road_lo"])
        d.line([ground(0, .5), ground(1, .5)], fill=C["mortar"])
        speckle(d, 33, C["road"], TILE_W // 2)
    return f


def t_kerb(height=None, worn=False, gutter=False, weeds=False,
           dropped=False, corner=False, seed=0, cap=True):
    """Kerbs are low blocks; the variations are all about what has happened to
    the top edge and the gutter line at their foot."""
    def f(d):
        h = height if height is not None else (
            max(2, REF["kerb"] // 2) if dropped else REF["kerb"])
        # `cap` lights the top-back edges. Wanted on a 96 px kerb, but at the
        # quarter size it draws a highlight on EVERY tile, and a run of them
        # turns a smooth lip into a lattice of light lines.
        block(d, h, C["stone"], C["stone_l"], C["stone_r"],
              C["stone_hi"] if cap else None)
        rnd = random.Random(seed)
        if worn:                      # chips out of the top edge
            for _ in range(3):
                a = rnd.uniform(.15, .85)
                x, y = ground(a, 0.0)
                d.polygon([(x, y - h), (x + 3, y - h + 2), (x - 2, y - h + 3)],
                          fill=C["stone_r"])
            for _ in range(6):
                d.point(ground(rnd.random(), rnd.random()), fill=C["stone_r"])
        if gutter:                    # dark channel along the foot
            d.line([face_pt("r", 0, 0.02, h), face_pt("r", 1, 0.02, h)], fill=C["mortar"])
            d.line([face_pt("l", 0, 0.02, h), face_pt("l", 1, 0.02, h)], fill=C["mortar"])
        if weeds:                     # tufts pushing through the joint
            for _ in range(5):
                u = rnd.uniform(.1, .9)
                side = rnd.choice(("l", "r"))
                x, y = face_pt(side, u, 0.05, h)
                d.line([(x, y), (x + rnd.choice((-1, 1)), y - rnd.randint(2, 4))],
                       fill=rnd.choice((C["moss"], C["moss_hi"])))
        if corner:                    # chamfered nose, as kerbs have at a corner
            x, y = ground(0.5, 0.5)
            d.polygon(diamond(x, y - h, TILE_W * .5, TILE_H * .5), fill=C["stone_hi"])
    return f


def t_block(h, top, left, right, cap=None, courses=0, seed=0):
    def f(d):
        block(d, h, C[top], C[left], C[right], C[cap] if cap else None)
        if courses:
            coursing(d, h, courses, C["mortar"], seed)
    return f


def t_wall(courses=6, window=False, door=False, poster=False, pipe=False):
    def f(d):
        h = U * 2
        block(d, h, C["brick"], C["brick_l"], C["brick_r"])
        coursing(d, h, courses, C["mortar"])
        if window:
            for side in ("l", "r"):
                u0, u1, v0, v1 = opening_px(d, h, side, REF["win_w"], REF["win_h"],
                                            REF["win_sill"], C["glass"], C["stone"])
                mid = (u0 + u1) / 2.0
                d.line([face_pt(side, mid, v0, h), face_pt(side, mid, v1, h)], fill=C["stone"])
                v_mid = (v0 + v1) / 2.0     # sash bar
                d.line([face_pt(side, u0, v_mid, h), face_pt(side, u1, v_mid, h)], fill=C["stone"])
        if door:
            u0, u1, v0, v1 = opening_px(d, h, "r", REF["door_w"], REF["door_h"],
                                        0, C["wood_r"], C["wood"])
            mid = (u0 + u1) / 2.0
            d.line([face_pt("r", mid, v0, h), face_pt("r", mid, v1, h)], fill=C["wood_l"])
        if poster:
            opening_px(d, h, "l", 22, 30, REF["win_sill"] + 10, C["poster"], C["mortar"])
        if pipe:
            d.line([face_pt("r", .12, .0, h), face_pt("r", .12, 1.0, h)], fill=C["iron"])
            d.line([face_pt("r", .15, .0, h), face_pt("r", .15, 1.0, h)], fill=C["iron_hi"])
    return f


def t_stone_wall():
    def f(d):
        h = U * 2
        block(d, h, C["stone"], C["stone_l"], C["stone_r"])
        coursing(d, h, 3, C["mortar"], seed=5)
    return f


def t_barrel():
    def f(d):
        h = U
        block(d, h, C["wood"], C["wood_l"], C["wood_r"], C["hi"])
        for v in (.3, .7):
            for side in ("l", "r"):
                d.line([face_pt(side, 0, v, h), face_pt(side, 1, v, h)], fill=C["iron"])
    return f


# ------------------------------------------------------------ obstacles --
def t_phone_box():
    """The red box. Tall enough to hide a character standing behind it."""
    def f(d):
        h = REF["phone_h"]
        block(d, h, C["phone_hi"], C["phone_dk"], C["phone"])
        for side in ("l", "r"):
            for row in range(4):           # glazing bars
                v0 = 0.30 + row * 0.16
                opening(d, h, side, .18, .82, v0, v0 + .13, C["glass"], C["phone_dk"])
            d.line([face_pt(side, 0, .26, h), face_pt(side, 1, .26, h)], fill=C["phone_dk"])
            d.line([face_pt(side, 0, .94, h), face_pt(side, 1, .94, h)], fill=C["phone_hi"])
    return f


def t_can(height_key="can_h", lid=True, rusty=False, tipped=False):
    def f(d):
        h = REF[height_key]
        body, dark = (C["rust"], C["can_dk"]) if rusty else (C["can"], C["can_dk"])
        block(d, h, C["can_hi"] if lid else dark, dark, body)
        for v in (.25, .55, .85):          # hoops
            for side in ("l", "r"):
                d.line([face_pt(side, 0, v, h), face_pt(side, 1, v, h)], fill=C["can_dk"])
        if lid:
            # An overhanging lid, which is most of what makes a bin read as a
            # bin. Without it the block is a featureless slab at this size -
            # the hoop lines alone are 1 px on a 14 px face and vanish.
            over = 1.14
            d.polygon(diamond(CX, CY - h + 2, TILE_W * over, TILE_H * over), fill=dark)
            d.polygon(diamond(CX, CY - h, TILE_W * over, TILE_H * over), fill=C["can_hi"])
            d.line([(CX - TILE_W * over / 2, CY - h),
                    (CX, CY - h - TILE_H * over / 2)], fill=C["iron_hi"])
        if tipped:                         # rubbish spilling out of the top
            rnd = random.Random(3)
            for _ in range(8):
                x, y = ground(rnd.uniform(.3, .9), rnd.uniform(.3, .9))
                d.point((x, y - h * .1), fill=rnd.choice((C["paper"], C["paper_dk"])))
    return f


def t_skip():
    """The bigger trade bin - a lidded steel box."""
    def f(d):
        h = REF["skip_h"]
        block(d, h, C["can_hi"], C["can_dk"], C["can"])
        for side in ("l", "r"):
            d.line([face_pt(side, 0, .82, h), face_pt(side, 1, .82, h)], fill=C["can_dk"])
            for u in (.3, .7):             # ribs
                d.line([face_pt(side, u, .05, h), face_pt(side, u, .8, h)], fill=C["can_dk"])
    return f


def t_bollard():
    def f(d):
        h = REF["bollard_h"]
        block(d, h, C["iron_hi"], C["iron"], C["iron"])
        for side in ("l", "r"):
            d.line([face_pt(side, 0, .8, h), face_pt(side, 1, .8, h)], fill=C["iron_hi"])
    return f


def t_postbox():
    def f(d):
        h = REF["post_h"]
        block(d, h, C["phone_hi"], C["phone_dk"], C["phone"])
        opening(d, h, "r", .3, .7, .62, .72, C["mortar"], C["phone_dk"])   # slot
    return f


# --------------------------------------------------------------- decals ----
# Overlays for the Decals layer: mostly transparent, drawn on top of a floor to
# break up the repeat. They carry neither collision nor navigation.
def t_decal(seed, papers=0, grime=0, specks=0, stain=False):
    def f(d):
        rnd = random.Random(seed)
        if stain:
            x, y = ground(rnd.uniform(.35, .65), rnd.uniform(.35, .65))
            w, hh = TILE_W * .45, TILE_H * .45
            d.ellipse([x - w/2, y - hh/2, x + w/2, y + hh/2], fill=C["grime"])
        for _ in range(grime):
            a, b = rnd.uniform(.15, .85), rnd.uniform(.15, .85)
            x, y = ground(a, b)
            w, hh = rnd.randint(6, 16), rnd.randint(3, 7)
            d.ellipse([x - w/2, y - hh/2, x + w/2, y + hh/2], fill=C["grime"])
        for _ in range(papers):
            a, b = rnd.uniform(.2, .8), rnd.uniform(.2, .8)
            x, y = ground(a, b)
            w, hh = rnd.randint(7, 11), rnd.randint(4, 6)
            d.polygon([(x, y - hh), (x + w, y), (x, y + hh), (x - w, y)],
                      fill=rnd.choice((C["paper"], C["paper_dk"])))
            d.line([(x - w + 2, y), (x + w - 2, y)], fill=C["paper_dk"])
        for _ in range(specks):
            d.point(ground(rnd.random(), rnd.random()),
                    fill=rnd.choice((C["paper_dk"], C["grime"], C["moss"])))
    return f


#         name               kind    walk   solid  painter
TILES = [
    ("cobble_a",        "flat",  True,  False, t_cobble(1)),
    ("cobble_b",        "flat",  True,  False, t_cobble(7)),
    ("cobble_c",        "flat",  True,  False, t_cobble(13)),
    ("cobble_cracked",  "flat",  True,  False, t_cobble(17, crack=True)),
    ("cobble_puddle",   "flat",  True,  False, t_cobble(23, wet=True)),
    ("cobble_manhole",  "flat",  True,  False, t_manhole()),
    ("flagstone_a",     "flat",  True,  False, t_flag(3)),
    ("flagstone_b",     "flat",  True,  False, t_flag(11)),
    ("flagstone_crack", "flat",  True,  False, t_flag(19, crack=True)),
    ("flagstone_drain", "flat",  True,  False, t_flag(27, with_drain=True)),
    ("road_a",          "flat",  True,  False, t_road(5)),
    ("road_b",          "flat",  True,  False, t_road(15)),
    ("road_patch",      "flat",  True,  False, t_road(25, patch=True)),
    ("road_puddle",     "flat",  True,  False, t_road(31, wet=True)),
    ("gutter",          "flat",  True,  False, t_gutter()),
    ("dirt",            "flat",  True,  False, t_simple("dirt", 41, "dirt_lo")),
    ("kerb",            "kerb", True,  False, t_kerb()),
    ("kerb_worn",       "kerb", True,  False, t_kerb(worn=True, seed=2)),
    ("kerb_gutter",     "kerb", True,  False, t_kerb(gutter=True)),
    ("kerb_weeds",      "kerb", True,  False, t_kerb(weeds=True, seed=4)),
    ("kerb_dropped",    "kerb", True,  False, t_kerb(dropped=True)),
    ("kerb_corner",     "kerb", True,  False, t_kerb(corner=True)),
    ("kerb_tall",       "kerb", True,  False, t_kerb(height=REF["kerb"] + 3, worn=True, seed=8)),
    ("step",            "kerb", True,  False, t_block(REF["kerb"] * 3, "stone", "stone_l", "stone_r")),
    ("step_worn",       "kerb", True,  False, t_kerb(height=REF["kerb"] * 3, worn=True, weeds=True, seed=6)),
    ("plinth",          "block", False, True,  t_block(U // 2, "stone", "stone_l", "stone_r", courses=1)),
    ("stone_blk",       "block", False, True,  t_block(U, "stone", "stone_l", "stone_r", courses=2, seed=2)),
    ("brick_blk",       "block", False, True,  t_block(U, "brick", "brick_l", "brick_r", courses=3)),
    ("crate",           "block", False, True,  t_block(U, "wood", "wood_l", "wood_r", cap="hi")),
    ("barrel",          "block", False, True,  t_barrel()),
    ("iron_blk",        "block", False, True,  t_block(U, "iron", "iron", "iron", cap="iron_hi")),
    ("brick_wall",      "block", False, True,  t_wall()),
    ("wall_window",     "block", False, True,  t_wall(window=True)),
    ("wall_door",       "block", False, True,  t_wall(door=True)),
    ("wall_poster",     "block", False, True,  t_wall(poster=True)),
    ("wall_pipe",       "block", False, True,  t_wall(pipe=True)),
    ("stone_wall",      "block", False, True,  t_stone_wall()),
    ("phone_box",       "block", False, True,  t_phone_box()),
    ("trash_can",       "block", False, True,  t_can()),
    ("trash_can_rusty", "block", False, True,  t_can(rusty=True)),
    ("trash_can_full",  "block", False, True,  t_can(lid=False, tipped=True)),
    ("trash_skip",      "block", False, True,  t_skip()),
    ("bollard",         "block", False, True,  t_bollard()),
    ("postbox",         "block", False, True,  t_postbox()),
    ("decal_paper_a",   "decal", False, False, t_decal(1, papers=3, specks=6)),
    ("decal_paper_b",   "decal", False, False, t_decal(9, papers=2, specks=10)),
    ("decal_litter",    "decal", False, False, t_decal(17, papers=1, specks=22)),
    ("decal_grime_a",   "decal", False, False, t_decal(23, grime=4)),
    ("decal_grime_b",   "decal", False, False, t_decal(31, grime=6, specks=8)),
    ("decal_stain",     "decal", False, False, t_decal(37, stain=True, grime=2)),
    ("decal_scatter",   "decal", False, False, t_decal(43, specks=30)),
]


def at_size(w, h, paint, cell_h=None):
    """Renders a painter at a different tile size and hands back the cell.

    The drawing helpers read TILE_W/TILE_H from module scope, so quarter-native
    art is made by swapping those for the duration rather than threading a size
    through every function."""
    global TILE_W, TILE_H, CELL_W, CELL_H, CX, CY, U
    keep = (TILE_W, TILE_H, CELL_W, CELL_H, CX, CY, U)
    TILE_W, TILE_H = w, h
    CELL_W, CELL_H = w, int(h * (1 + TALLEST)) if cell_h is None else cell_h
    CX, CY = CELL_W // 2, CELL_H - TILE_H // 2
    U = TILE_H          # heights are in tile-heights, so this has to move too
    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    paint(ImageDraw.Draw(cell))
    out = cell, CELL_W, CELL_H, TILE_W, TILE_H
    TILE_W, TILE_H, CELL_W, CELL_H, CX, CY, U = keep
    return out


def t_thin_wall(axis="a", across=0.0, thick=0.24, low=False, courses=True):
    """A wall a fraction of a cell thick, running along one isometric axis.

    Drawn as three faces rather than one, because a single quad at this size
    reads as a flat slab: the cap tells you how thin it is, and the end cap
    stops a run looking like a painted stripe.

    `axis` is which way it runs ("a" heads north-east, "b" north-west),
    `across` where it sits in the cell (0 is the far edge) and `thick` how deep.
    """
    def f(d):
        # a quarter cell only leaves 2 tile-heights of headroom above the
        # floor diamond, so a wall taller than that gets its top sheared off
        h = U * 0.85 if low else U * 1.8
        near = across + thick

        def up(p, lift=h):
            return (p[0], p[1] - lift)

        if axis == "a":
            far_0, far_1 = ground(0, across), ground(1, across)
            near_0, near_1 = ground(0, near), ground(1, near)
            end_a, end_b = near_1, far_1        # the east end is the visible one
            face_col, cap_col, end_col = C["brick_r"], C["brick"], C["brick_l"]
        else:
            far_0, far_1 = ground(across, 0), ground(across, 1)
            near_0, near_1 = ground(near, 0), ground(near, 1)
            end_a, end_b = near_1, far_1        # the west end
            face_col, cap_col, end_col = C["brick_l"], C["brick"], C["brick_r"]

        # the long face, the end cap, then the top - painted back to front
        d.polygon([up(near_0), up(near_1), near_1, near_0], fill=face_col)
        d.polygon([up(end_a), up(end_b), end_b, end_a], fill=end_col)
        d.polygon([up(far_0), up(far_1), up(near_1), up(near_0)], fill=cap_col)

        if courses:
            n = max(2, int(round(h / float(REF["course"]))))
            for k in range(1, n):
                lift = h * k / float(n)
                d.line([up(near_0, lift), up(near_1, lift)], fill=C["mortar"])
            # a coping course along the top edge, as brick walls tend to have
            d.line([up(near_0, h - 1), up(near_1, h - 1)], fill=C["stone_l"])


    return f


def slice_floor(cell):
    """Cuts a drawn floor diamond into SUB x SUB sub-diamonds.

    Each pixel is assigned to exactly one sub-cell from its position in tile
    space, so the pieces are a true partition — drawing SUB x SUB overlapping
    masks instead loses ~5% of pixels along the seams."""
    sw, sh = TILE_W // SUB, TILE_H // SUB
    src = np.array(cell.crop((0, CELL_H - TILE_H, TILE_W, CELL_H)))
    yy, xx = np.mgrid[0:TILE_H, 0:TILE_W]
    px = (xx + 0.5 - TILE_W / 2.0) / (TILE_W / 2.0)     # a - b
    py = (yy + 0.5) / (TILE_H / 2.0)                    # a + b
    A, B = (py + px) / 2.0, (py - px) / 2.0
    ai = np.clip(np.floor(A * SUB).astype(int), 0, SUB - 1)
    bi = np.clip(np.floor(B * SUB).astype(int), 0, SUB - 1)
    inside = (A >= 0) & (A < 1) & (B >= 0) & (B < 1) & (src[:, :, 3] > 0)

    out = {}
    for i in range(SUB):
        for j in range(SUB):
            sel = inside & (ai == i) & (bi == j)
            ox = int(TILE_W / 2 + (i - j) * sw / 2 - sw / 2)
            oy = int((i + j) * sh / 2)
            buf = np.zeros((sh, sw, 4), np.uint8)
            ys, xs = np.where(sel)
            ly, lx = ys - oy, xs - ox
            keep = (ly >= 0) & (ly < sh) & (lx >= 0) & (lx < sw)
            buf[ly[keep], lx[keep]] = src[ys[keep], xs[keep]]
            out[(i, j)] = Image.fromarray(buf, "RGBA")
    return out


# Drawn at the QUARTER size and placed one cell at a time - the fine detail the
# sliced big floors cannot give you.
QUARTER_TILES = [
    ("q_flag",      "flat",  True,  False, t_flag(51)),
    ("q_flag_b",    "flat",  True,  False, t_flag(57)),
    ("q_cobble",    "flat",  True,  False, t_cobble(61)),
    ("q_cobble_b",  "flat",  True,  False, t_cobble(67)),
    ("q_road",      "flat",  True,  False, t_road(71)),
    ("q_dirt",      "flat",  True,  False, t_simple("dirt", 73, "dirt_lo")),
    ("q_grate",     "flat",  True,  False, t_flag(79, with_drain=True)),
    ("q_puddle",    "flat",  True,  False, t_road(83, wet=True)),
]
# Thin walls in both orientations. A run needs the matching one or it reads as
# a row of disconnected posts - there is no rotating a sprite in this projection.
QUARTER_BLOCKS = [
    ("q_wall_a",     "block", False, True, t_thin_wall("a", across=0.38)),
    ("q_wall_b",     "block", False, True, t_thin_wall("b", across=0.38)),
    ("q_wall_a_low", "block", False, True, t_thin_wall("a", across=0.38, low=True)),
    ("q_wall_b_low", "block", False, True, t_thin_wall("b", across=0.38, low=True)),
]


# Street furniture, drawn at the size the OBJECT is rather than the size a tile
# is. Painted by the same functions as the tile versions - they take their
# heights from REF in pixels, so only the footprint needs saying. The width is
# the diamond across its base; a dustbin is about half a metre, a skip a couple.
PROP_ART = [
    ("trash_can",       28, t_can()),
    ("trash_can_rusty", 28, t_can(rusty=True)),
    ("trash_can_full",  28, t_can(lid=False, tipped=True)),
    ("trash_skip",      48, t_skip()),
    ("bollard",         12, t_bollard()),
    ("postbox",         26, t_postbox()),
]


def write_props():
    """Emits the furniture as individual PNGs beside the carved props, cropped
    to their ink so the bottom edge is the front of the base - the same anchor
    the carved artwork uses, so the level places them with no special case."""
    made = []
    for name, fw, paint in PROP_ART:
        fh = max(2, fw // 2)                      # 2:1, like every other footprint
        tall = max(REF[k] for k in ("phone_h", "post_h", "skip_h", "can_h"))
        cell, cw, ch, tw, th = at_size(fw, fh, paint, cell_h=fh + tall + 4)
        box = cell.getbbox()
        if box is None:
            continue
        cell.crop(box).save("sprites/street/props/%s.png" % name)
        made.append("%s %dx%d" % (name, box[2] - box[0], box[3] - box[1]))
    return made


def main():
    rows = (len(TILES) + COLS - 1) // COLS
    sheet = Image.new("RGBA", (COLS * CELL_W, rows * CELL_H), (0, 0, 0, 0))
    art = {}                       # name -> [col, row] in the big art sheet
    kinds = {}
    floors, decals, kerbs = [], [], []

    for i, (name, kind, walk, solid, paint) in enumerate(TILES):
        cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        paint(ImageDraw.Draw(cell))
        if kind in ("flat", "decal"):
            mask = Image.new("L", (CELL_W, CELL_H), 0)
            ImageDraw.Draw(mask).polygon(diamond(CX, CY), fill=255)
            # Intersect with what is already there. Replacing the alpha outright
            # makes a decal's unpainted area opaque black.
            cell.putalpha(ImageChops.multiply(cell.getchannel("A"), mask))
        col, row = i % COLS, i // COLS
        sheet.alpha_composite(cell, (col * CELL_W, row * CELL_H))
        art[name] = [col, row]
        kinds[kind] = kinds.get(kind, 0) + 1
        if kind == "flat":
            floors.append((name, cell))
        elif kind == "decal":
            decals.append((name, cell))
        elif kind == "kerb":
            kerbs.append((name, cell))

    # No blocks.png. Every tile used to be composited into one sheet, which is
    # why it still carried copies of the floors and decals that now live in
    # their own files - and nothing referenced any of it once blocks became
    # wall panels and props. The PAINTERS are all still here (t_crate, t_block,
    # t_wall...), so reviving a solid cube is a matter of emitting a sheet
    # again; the stale image is not worth keeping around to confuse things.

    # ---- floors on their own sheet, at the size of the diamond ------------
    # The floor layer draws a 96x48 region, so that is what the sheet holds.
    # A cell bigger than the tile overhangs, and Godot drops overhanging art in
    # a band along the top and left of the map - see CLAUDE.md.
    # a fully transparent tile, for padding layers whose art overhangs
    floors = floors + [("blank", Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0)))]
    fcols = 8
    frows = (len(floors) + fcols - 1) // fcols
    fsheet = Image.new("RGBA", (fcols * TILE_W, frows * TILE_H), (0, 0, 0, 0))
    floor_index = {}
    for n, (name, cell) in enumerate(floors):
        c, r = n % fcols, n // fcols
        fsheet.alpha_composite(cell.crop((0, CELL_H - TILE_H, TILE_W, CELL_H)),
                               (c * TILE_W, r * TILE_H))
        floor_index[name] = [c, r]
    fsheet.save("sprites/street/floors.png")

    # ---- kerbs, at the same footprint as a floor tile ---------------------
    # A kerb is a floor tile with a lip, so it is drawn 96 px wide like one.
    # The cell is 16 px taller than the tile to hold the lip, which means it
    # overhangs by a third of a tile - the Kerbs layer is padded for that.
    kcols = 8
    krows = (len(kerbs) + kcols - 1) // kcols
    ksheet = Image.new("RGBA", (kcols * TILE_W, krows * KERB_CELL_H), (0, 0, 0, 0))
    kerb_index = {}
    for n, (name, cell) in enumerate(kerbs):
        c, r = n % kcols, n // kcols
        ksheet.alpha_composite(cell.crop((0, CELL_H - KERB_CELL_H, TILE_W, CELL_H)),
                               (c * TILE_W, r * KERB_CELL_H))
        kerb_index[name] = [c, r]
    ksheet.save("sprites/street/kerbs.png")

    # ---- the quarter-grid sheet Godot actually lays down -------------------
    sw, sh = TILE_W // SUB, TILE_H // SUB
    grid_tiles = {}
    pieces = []
    # Only DECALS are sliced. The floor is drawn from whole 96x48 tiles, so
    # slicing it produced 256 tiles nothing ever placed.
    for name, cell in decals:
        for (i, j), piece in sorted(slice_floor(cell).items()):
            pieces.append(("%s@%d%d" % (name, i, j), piece, name, i, j, True))

    # ---- tiles drawn natively at the quarter size -------------------------
    qart = {}
    qw, qh = TILE_W // SUB, TILE_H // SUB
    for name, kind, walk, solid, paint in QUARTER_BLOCKS:
        cell, cw, ch, tw, th = at_size(qw, qh, paint)
        qart[name] = (cell, kind)  # taller than a grid cell: its own atlas source

    # The collision and navigation markers.
    #
    # These are TINTED rather than blank. Both layers ship with visible = false,
    # so nothing is drawn in game - but a blank tile on a hidden layer that
    # still collides looks like an empty layer with mysterious collision, which
    # is exactly as confusing as it sounds. Tick the layer's eye in the editor
    # and you can see what is solid.
    def marker(rgba):
        img = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
        ImageDraw.Draw(img).polygon(
            [(sw / 2, -0.5), (sw - 1, sh / 2), (sw / 2, sh - 0.5), (0, sh / 2)],
            fill=rgba)
        return img

    solid = marker((0xd2, 0x3b, 0xb8, 110))      # magenta: solid
    pieces.append(("collision", solid, "collision", 0, 0, False))
    # ...and a matching walkable one. Navigation lives on its own invisible
    # quarter-resolution layer now that the visible floor is back to 96x48:
    # painting a big floor tile no longer has to mean a big navigation cell.
    pieces.append(("walkable", marker((0x4c, 0xc2, 0x6a, 90)), "walkable", 0, 0, False))

    gcols = 16
    grows = (len(pieces) + gcols - 1) // gcols
    gsheet = Image.new("RGBA", (gcols * sw, grows * sh), (0, 0, 0, 0))
    for n, (tile_name, piece, parent, i, j, is_decal) in enumerate(pieces):
        c, r = n % gcols, n // gcols
        gsheet.alpha_composite(piece, (c * sw, r * sh))
        grid_tiles[tile_name] = {
            "atlas": [c, r],
            "parent": parent, "sub": [i, j],
            "walkable": (not is_decal) and tile_name != "collision",
            "solid": tile_name == "collision",
            "layer": ("decal" if is_decal else
                      {"collision": "collision", "walkable": "walkable"}.get(
                          tile_name, "ground")),
        }
    gsheet.save("sprites/street/decals.png")

    # quarter-native blocks are taller than a cell, so they live on their own
    # small art sheet and get drawn as sprites like the big blocks do
    qcell_w, qcell_h = (list(qart.values())[0][0].size if qart else (0, 0))
    qsheet = Image.new("RGBA", (max(1, len(qart)) * max(1, qcell_w), max(1, qcell_h)), (0, 0, 0, 0))
    qart_index = {}
    for n, (name, (cell, kind)) in enumerate(sorted(qart.items())):
        qsheet.alpha_composite(cell, (n * qcell_w, 0))
        qart_index[name] = {"atlas": [n, 0], "kind": kind}
    qsheet.save("sprites/street/thin_walls.png")

    prop_sizes = write_props()
    panels, pw, ph = write_panels()

    with open("sprites/street/tiles.json", "w", newline="\n") as f:
        json.dump({
            "art_tile_size": [TILE_W, TILE_H],
            "art_cell_size": [CELL_W, CELL_H],
            "sub": SUB,
            "grid_tile_size": [sw, sh],
            # kind "kerb" -> placed as tiles; anything else -> drawn as a sprite
            "quarter_art_cell": [qcell_w, qcell_h],
            "floor_names": [n for n, _ in floors if n != "blank"],
            "floor_cell": [TILE_W, TILE_H],
            "kerb_cell": [TILE_W, KERB_CELL_H],
            "kerbs": kerb_index,        # kerbs.png, a floor diamond plus a lip
            "floors": floor_index,      # floors.png, one 96x48 diamond per cell
            "panel_cell": [PANEL_W, panel_size()[1]],
            "panel_height": PANEL_H,
            "panel_rise": PANEL_RISE,
            "panels": panels,           # wall faces: sprites with an IsoSorter
            "quarter_art": qart_index,
            "grid": grid_tiles,         # for the tilemaps: floors, decals, collision
        }, f, indent=2)

    print("props/         %s" % ", ".join(prop_sizes))
    print("walls.png      %dx%d  |  %d segments at %dx%d (%d layouts x 2 facings, %d bays each)"
          % (pw * 2, ph * (len(PANEL_LAYOUTS) + 1), len(panels), pw, ph,
             len(PANEL_LAYOUTS) + 1, PANEL_BAYS))
    print("floors.png     %s  |  %d floor tiles at %dx%d" % (fsheet.size, len(floors), TILE_W, TILE_H))
    print("kerbs.png      %s  |  %d kerbs at %dx%d" % (ksheet.size, len(kerbs), TILE_W, KERB_CELL_H))
    print("thin_walls.png %s  |  %d at %dx%d" % (qsheet.size, len(qart_index), qcell_w, qcell_h))
    print("decals.png     %s  |  %d tiles at %dx%d (%d decals x %d slices + 2 markers)"
          % (gsheet.size, len(grid_tiles), sw, sh, len(decals), SUB * SUB))




# ============================================================ wall panels ==
# A building facade is built from single-face PANELS rather than from cubes.
#
# One panel is a segment of wall - PANEL_BAYS bays wide and one storey tall -
# drawn as the parallelogram of a single wall face. Runs of them stack sideways
# along a wall and upwards into storeys, and each carries an IsoSorter so it
# sorts against the LINE of its base rather than a single point, which is what
# a long wall actually needs and what Y-sort cannot express.
#
# Sides: "r" faces south-east and its base rises to the right; "l" faces
# south-west and its base falls to the right. Mirror images geometrically, but
# not tonally - the two faces catch different light.
#
# Variations are COMPOSED, not drawn one by one: a panel is a list of bay
# kinds, so "window + door" costs a line in PANEL_LAYOUTS rather than a new
# painter. A bay is the reference's window spacing, half a floor tile.

BAY_W = 48                       # one bay: the reference's window spacing
BAY_RISE = 24                    # how far the base climbs across one bay
PANEL_BAYS = 2                   # bays per panel - the segment size
PANEL_H = 112                    # one storey
PANEL_PAD = 1

KERB_CELL_H = TILE_H + 16        # the diamond, plus headroom for the lip
PANEL_W = BAY_W * PANEL_BAYS
PANEL_RISE = BAY_RISE * PANEL_BAYS


def panel_size(h=PANEL_H):
    return PANEL_W, PANEL_PAD + h + PANEL_RISE + 1


def panel_pt(side, u, v, h=PANEL_H):
    """A point on a panel. u runs 0..1 across it, v runs 0..1 up it."""
    x = u * (PANEL_W - 1)
    climb = PANEL_RISE * (1.0 - u) if side == "r" else PANEL_RISE * u
    return (x, PANEL_PAD + h + climb - v * h)


def panel_quad(side, u0, u1, v0, v1, h=PANEL_H):
    return [panel_pt(side, u0, v0, h), panel_pt(side, u1, v0, h),
            panel_pt(side, u1, v1, h), panel_pt(side, u0, v1, h)]


def bay_span(i):
    """The u range of bay i."""
    return i / float(PANEL_BAYS), (i + 1) / float(PANEL_BAYS)


def within(u0, u1, w_px):
    """Centres something w_px wide in the u range u0..u1."""
    mid = (u0 + u1) / 2.0
    half = (w_px / 2.0) / PANEL_W
    return max(u0 + 0.02, mid - half), min(u1 - 0.02, mid + half)


def panel_courses(d, side, h, colour, course=None, seed=0, per_bay=4):
    """Brick courses with staggered perpends, matching the block art.

    `per_bay` bricks to a bay, alternating half a brick each course, and the
    course height comes from REF so a brick is the same size here as on any
    other piece of masonry."""
    step = course or REF["course"]
    n = max(1, int(round(h / float(step))))
    for k in range(1, n):
        v = k / float(n)
        d.line([panel_pt(side, 0, v, h), panel_pt(side, 1, v, h)], fill=colour)
    bricks = per_bay * PANEL_BAYS
    for k in range(n):
        v0, v1 = k / float(n), (k + 1) / float(n)
        offset = 0.5 if k % 2 else 0.0
        for m in range(bricks):
            u = (m + offset) / float(bricks)
            if 0.0 < u < 1.0:
                d.line([panel_pt(side, u, v0, h), panel_pt(side, u, v1, h)], fill=colour)


# ------------------------------------------------------------------ bays --
# Each takes the drawing context, the side, the storey height and the u range
# of its own bay, and paints inside it. The treatments follow the block art:
# brick with a stone surround to the windows and a wooden door.

def bay_plain(d, side, h, u0, u1, seed=0):
    pass


def bay_window(d, side, h, u0, u1, lit=False, boarded=False, seed=0):
    a, b = within(u0, u1, REF["win_w"])
    v0 = REF["win_sill"] / float(h) + 0.16
    v1 = min(0.93, v0 + REF["win_h"] / float(h))
    d.polygon(panel_quad(side, a, b, v0, v1, h),
              fill=C["hi"] if lit else C["glass"], outline=C["stone"])
    if boarded:
        for k in range(3):
            v = v0 + (v1 - v0) * (0.2 + k * 0.3)
            d.line([panel_pt(side, a, v, h), panel_pt(side, b, v, h)], fill=C["wood_r"])
        return
    mid = (a + b) / 2.0                      # mullion
    d.line([panel_pt(side, mid, v0, h), panel_pt(side, mid, v1, h)], fill=C["stone"])
    v_mid = (v0 + v1) / 2.0                  # sash bar
    d.line([panel_pt(side, a, v_mid, h), panel_pt(side, b, v_mid, h)], fill=C["stone"])


def bay_door(d, side, h, u0, u1, shop=False, seed=0):
    a, b = within(u0, u1, REF["door_w"])
    v1 = min(0.86, REF["door_h"] / float(h))
    d.polygon(panel_quad(side, a, b, 0.0, v1, h),
              fill=C["glass"] if shop else C["wood_r"], outline=C["wood"])
    mid = (a + b) / 2.0
    if shop:
        vs = v1 * 0.32
        d.polygon(panel_quad(side, a, b, 0.0, vs, h), fill=C["wood_r"])
        d.line([panel_pt(side, a, vs, h), panel_pt(side, b, vs, h)], fill=C["wood"])
    d.line([panel_pt(side, mid, 0.0, h), panel_pt(side, mid, v1, h)], fill=C["wood_l"])
    d.line([panel_pt(side, a - .02, v1, h), panel_pt(side, b + .02, v1, h)],
           fill=C["stone"])               # lintel


def bay_shop(d, side, h, u0, u1, seed=0):
    a, b = within(u0, u1, BAY_W - 10)
    v0, v1 = 0.14, 0.58
    d.polygon(panel_quad(side, a, b, v0, v1, h), fill=C["glass"], outline=C["stone"])
    for k in (0.33, 0.66):
        u = a + (b - a) * k
        d.line([panel_pt(side, u, v0, h), panel_pt(side, u, v1, h)], fill=C["stone"])
    d.line([panel_pt(side, a, v0, h), panel_pt(side, b, v0, h)], fill=C["stone"])
    d.polygon(panel_quad(side, a, b, v1 + .02, v1 + .09, h),
              fill=C["wood_r"], outline=C["wood"])          # fascia


def bay_pipe(d, side, h, u0, u1, seed=0):
    u = u1 - 0.05 if side == "r" else u0 + 0.05
    d.line([panel_pt(side, u, 0, h), panel_pt(side, u, 1.0, h)], fill=C["iron"])
    d.line([panel_pt(side, u + .012, 0, h), panel_pt(side, u + .012, 1.0, h)],
           fill=C["iron_hi"])


def bay_poster(d, side, h, u0, u1, sign=False, seed=0):
    rnd = random.Random(seed + 5)
    if sign:
        a, b = within(u0, u1, BAY_W - 10)
        d.polygon(panel_quad(side, a, b, .62, .78, h), fill=C["wood_r"],
                  outline=C["wood"])
        for k in range(3):
            v = .66 + k * .035
            d.line([panel_pt(side, a + .01, v, h), panel_pt(side, b - .01, v, h)],
                   fill=C["poster"])
    else:
        a, b = within(u0, u1, 22)
        v0 = (REF["win_sill"] + 10) / float(h) + 0.14
        d.polygon(panel_quad(side, a, b, v0, v0 + 30.0 / h, h),
                  fill=C["poster"], outline=C["mortar"])
        for k in range(4):
            v = v0 + 0.04 + k * 0.035
            d.line([panel_pt(side, a + .01, v, h),
                    panel_pt(side, a + (b - a) * rnd.uniform(.5, .9), v, h)],
                   fill=C["mortar"])


def bay_vent(d, side, h, u0, u1, seed=0):
    a, b = within(u0, u1, 22)
    v0, v1 = 0.52, 0.66
    d.polygon(panel_quad(side, a, b, v0, v1, h), fill=C["mortar"], outline=C["stone"])
    for k in range(3):
        v = v0 + (v1 - v0) * (0.25 + k * 0.25)
        d.line([panel_pt(side, a, v, h), panel_pt(side, b, v, h)], fill=C["iron_hi"])


BAYS = {
    "plain":   bay_plain,
    "window":  bay_window,
    "win_lit": lambda *a, **k: bay_window(*a, lit=True, **k),
    "win_out": lambda *a, **k: bay_window(*a, boarded=True, **k),
    "door":    bay_door,
    "shopdoor": lambda *a, **k: bay_door(*a, shop=True, **k),
    "shop":    bay_shop,
    "pipe":    bay_pipe,
    "poster":  bay_poster,
    "sign":    lambda *a, **k: bay_poster(*a, sign=True, **k),
    "vent":    bay_vent,
}

# name -> (stone?, bay kinds). Brick throughout, as the block art is; stone is
# kept for the odd civic frontage rather than being the whole ground floor.
PANEL_LAYOUTS = [
    ("plain",        False, ("plain", "plain")),
    ("plain_b",      False, ("plain", "plain")),
    ("windows",      False, ("window", "window")),
    ("window_plain", False, ("window", "plain")),
    ("plain_window", False, ("plain", "window")),
    ("window_lit",   False, ("win_lit", "window")),
    ("window_out",   False, ("win_out", "plain")),
    ("window_pipe",  False, ("window", "pipe")),
    ("poster",       False, ("poster", "plain")),
    ("sign",         False, ("plain", "sign")),
    ("vent",         False, ("vent", "plain")),
    ("pipe",         False, ("pipe", "plain")),
    ("g_plain",      False, ("plain", "plain")),
    ("g_door",       False, ("door", "plain")),
    ("g_door_win",   False, ("door", "window")),
    ("g_windows",    False, ("window", "window")),
    ("g_shop",       False, ("shop", "shop")),
    ("g_shopdoor",   False, ("shop", "shopdoor")),
    ("g_door_pipe",  False, ("door", "pipe")),
    ("g_stone",      True,  ("window", "plain")),
]


def paint_panel(d, side, stone, kinds, h=PANEL_H, seed=0):
    body = (C["stone_l"] if side == "l" else C["stone_r"]) if stone else \
           (C["brick_l"] if side == "l" else C["brick_r"])
    d.polygon(panel_quad(side, 0, 1, 0, 1, h), fill=body)
    panel_courses(d, side, h, C["mortar"],
                  course=REF["course"] * 2 if stone else None,
                  seed=seed + 3, per_bay=2 if stone else 4)
    for i, kind in enumerate(kinds[:PANEL_BAYS]):
        u0, u1 = bay_span(i)
        BAYS[kind](d, side, h, u0, u1, seed=seed + i * 7)
    # a string course capping the storey, which is what makes them stack
    d.line([panel_pt(side, 0, 0.995, h), panel_pt(side, 1, 0.995, h)],
           fill=C["stone"])


def paint_quoin(d, side, h=PANEL_H):
    """The dressed-stone corner column the reference puts at every junction.
    One bay wide, so it butts against a panel rather than replacing one."""
    body = C["stone_l"] if side == "l" else C["stone_r"]
    u1 = 1.0 / PANEL_BAYS
    d.polygon(panel_quad(side, 0, u1, 0, 1, h), fill=body)
    n = max(2, int(round(h / (REF["course"] * 2.5))))
    for k in range(1, n):
        v = k / float(n)
        d.line([panel_pt(side, 0, v, h), panel_pt(side, u1, v, h)], fill=C["mortar"])
    for k in range(n):
        v0, v1 = k / float(n), (k + 1) / float(n)
        u = u1 * (0.62 if k % 2 else 0.38)
        d.line([panel_pt(side, u, v0, h), panel_pt(side, u, v1, h)], fill=C["mortar"])
    d.line([panel_pt(side, 0, 0, h), panel_pt(side, 0, 1, h)], fill=C["stone_hi"])


def write_panels():
    """One sheet of wall segments, both facings, indexed by name."""
    pw, ph = panel_size()
    rows = len(PANEL_LAYOUTS) + 1                 # +1 for the quoin
    sheet = Image.new("RGBA", (pw * 2, ph * rows), (0, 0, 0, 0))
    index = {}
    for row, (name, stone, kinds) in enumerate(PANEL_LAYOUTS):
        for col, side in enumerate(("l", "r")):
            cell = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
            paint_panel(ImageDraw.Draw(cell), side, stone, kinds, PANEL_H, row)
            sheet.alpha_composite(cell, (col * pw, row * ph))
            index["%s_%s" % (name, side)] = [col, row]
    for col, side in enumerate(("l", "r")):
        cell = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
        paint_quoin(ImageDraw.Draw(cell), side, PANEL_H)
        sheet.alpha_composite(cell, (col * pw, (rows - 1) * ph))
        index["quoin_%s" % side] = [col, rows - 1]
    sheet.save("sprites/street/walls.png")
    return index, pw, ph

if __name__ == "__main__":
    main()
