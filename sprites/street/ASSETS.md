# Street assets — what to paint

Everything in `levels/street.tscn` comes from the files below. If a sheet is not
listed here, nothing places it.

All art is 2:1 isometric (a tile is twice as wide as it is tall) and
nearest-neighbour. `tools/make_tiles.py` generates placeholder versions of every
one of these; replacing a file by hand is the intended path — keep the cell size
and the anchor and nothing else has to change.

---

## The four that matter

| Sheet | Cell | Count | What it is |
|---|---|---|---|
| `floors.png` | **96×48** | 16 (+1 blank) | the ground: cobbles, paving, road |
| `kerbs.png` | **96×64** | 9 | a floor tile with a lip |
| `walls.png` | **96×162** | 42 | one storey of a building face |
| `props/*.png` | any size | 14 | free-standing objects |

Plus two supporting sheets: `decals.png` (24×12 litter overlays) and
`thin_walls.png` (24×36 knee-high walls).

---

## floors.png — 96×48

One diamond per cell, filling the cell exactly. **The art must not exceed
96×48**: Godot drops tile art that overhangs its cell, in a band along the top
and left of the whole map, which reads as "the floor stops short" rather than as
a tiling bug.

Present: `cobble_a/b/c`, `cobble_cracked`, `cobble_puddle`, `cobble_manhole`,
`flagstone_a/b`, `flagstone_crack`, `flagstone_drain`, `road_a/b`, `road_patch`,
`road_puddle`, `gutter`, `dirt`. `blank` is a transparent padding tile — leave it.

A letter in `GROUND` (in `tools/build_street.gd`) names a **list** of these, and
which one a cell gets is hashed from its coordinates. Adding a variant means
adding it to a list in `FLOOR_KEY`; no map editing.

## kerbs.png — 96×64

The same 96×48 footprint as a floor tile, sitting in the **bottom 48 px**, with
16 px of headroom above it for the lip. The lip is **4 px** — measured off the
reference; a kerb is something you step over, not a step you climb.

Present: `kerb`, `kerb_worn`, `kerb_gutter`, `kerb_weeds`, `kerb_dropped`,
`kerb_corner`, `kerb_tall`, `step`, `step_worn`.

Kerbs never sort against anything — they are pinned below everything that walks,
because 96 px of art judged from one point puts its lip across the shins of
anyone standing just north of it.

## walls.png — 96×162

One **storey** of one **face**, two bays wide. The footprint is the bottom of the
cell: the base line runs corner to corner across the 96 px width, rising 48 px
for the `_r` facing and falling 48 px for the `_l` facing. Above that is 112 px
of storey, plus 1 px of margin.

**The two facings are separate artwork.** They are mirror images geometrically,
but the two faces catch different light, so a flipped `_r` does not read as an
`_l`. Every name exists twice, `<name>_l` and `<name>_r`.

Brick throughout, with a **stone surround** to the windows and a wooden door —
the same treatment as the old block art. Ground-floor layouts are prefixed
`g_`; `g_stone` is the one stone frontage. A brick is a quarter of a bay wide
and `REF["course"]` tall, so it matches masonry anywhere else.

Panels stack sideways into runs and upwards into storeys, so the left and right
edges must tile and the top must meet the bottom.

21 layouts x 2 facings = 42 panels: `plain`, `plain_b`, `windows`,
`window_plain`, `plain_window`, `window_lit`, `window_out`, `window_pipe`,
`poster`, `sign`, `vent`, `pipe`, `quoin`, and the ground-floor `g_plain`,
`g_door`, `g_door_win`, `g_windows`, `g_shop`, `g_shopdoor`, `g_door_pipe`,
`g_stone`.

## props/*.png — any size

**A prop's size comes from its artwork, not from the tile grid** — that is what
lets a 28 px bin stand on a 96 px floor tile. Crop to the ink: the bottom edge of
the image is the front of the base, and that is what gets placed on the floor.

Present: `phone_box`, `postbox`, `bollard`, `trash_can`, `trash_can_rusty`,
`trash_can_full`, `trash_skip`, `skip_large`, `skip_small`, `barrel_left`,
`barrel_right`, `cardboard_box`, `bike_rack`, `wall_lamp`.

## decals.png — 24×12

Litter and grime scattered over the floor, at quarter resolution so it clusters
rather than stamping a whole 96 px tile at a time. Each of the 7 decals is stored
as its 16 slices. **Mostly transparent** — a decal is an overlay, not a tile.

Also holds two fully transparent markers, `collision` and `walkable`, which are
never drawn; they carry the physics and navigation layers.

## thin_walls.png — 24×36

Knee-high walls for boundaries and forecourts: `q_wall_a`, `q_wall_b` and their
`_low` variants. `a` runs south-east, `b` south-west — again, separate artwork,
not mirrored.

These bound the **near** side of the street. Nothing on the near side may be
taller than a character, or it hides them.

---

## There is no blocks.png

Every tile used to be composited into one sheet, so it carried copies of the
floors and decals as well as the cubes — and nothing referenced any of it once
blocks became wall panels and props.

The **painters** are all still in `tools/make_tiles.py` (`t_wall`, `t_block`,
`t_crate`...), so reviving a solid cube means emitting a sheet again. The stale
image is not kept, because a sheet that looks current but is never drawn is
worse than no sheet.

Drawing scenery as cubes was the original mistake anyway: a tile is 96 px wide
by definition, so every prop came out 96 px wide.
