# Street assets — what to paint

Everything in `levels/street.tscn` comes from the files below. If a sheet is not
listed here, nothing places it.

All art is 2:1 isometric (a tile is twice as wide as it is tall) and
nearest-neighbour. `tools/make_tiles.py` generates placeholder versions of every
one of these; replacing a file by hand is the intended path — keep the cell size
and the anchor and nothing else has to change.

---

## The three that matter

| Sheet | Cell | Count | What it is |
|---|---|---|---|
| `surfaces.png` | **64×64** | 86 | the ground: floors AND kerbs, every tone at every height |
| `walls.png` | **64×122** | 40 | one storey of a building face |
| `props/*.png` | any size | 14 | free-standing objects |

Plus two supporting sheets: `decals.png` (16×8 litter overlays) and
`thin_walls.png` (16×24 knee-high walls).

## The tile size, and why it is 64×32

64×32 is the standard isometric tile and it is **legal**, which not every size
is. Three rules, and the fine grid has to pass them too:

1. **W = 2H**, or the diamond edge is not a clean two-across-one-down staircase
   and neighbours sawtooth against each other.
2. **Both dimensions even.** A cell sits at `((x−y)·W/2, (x+y)·H/2)`; an odd
   dimension puts that on half a pixel and smears the whole grid.
3. The **fine grid** `(W/SUB, H/SUB)` must satisfy 1 and 2 as well, since
   collision, navigation and decals are laid on it. 64×32 with SUB 4 gives
   16×8 — even, and finer than what came before.

**A diamond drawn as a polygon does not tile.** Its edges are whatever the
rasteriser decides. The exact shape is fixed by area: one lattice cell is
`W·H/2` pixels, so a tile must cover precisely that — rows of 4, 8, 12 … W and
back down to 4, which is H−1 rows. `iso_mask()` builds it; `close_to_mask()` then fills anything
the painter left short, because masking multiplies alpha and can only ever
remove. Measured after: **0 seam pixels** anywhere in the floor.

---

## surfaces.png — 64×64 cell on a 64×32 tile, laid out 10 x 9 (640x576)

**Floors and kerbs are one list.** A kerb is not a different kind of thing from
a floor — it is a floor that stands a little proud of what is next to it. They
used to be two sheets on two layers, which meant every pavement cell carried a
flat tile *and* an edge tile and the map had to say the same thing twice. Now a
cell picks `pave_4` or `pave_4_t6` and that is the whole decision.

**Flat diamonds, one tone each, no pattern.** A pattern drawn into a 64x32 tile
fights the eye at this size and is awkward to repaint; a ramp of tones reads as
a surface and takes its detail from the decals layer instead.

17 tones — six pavement (`pave_1`..`pave_6`, light to dark), six road, three
dirt, two shade — each at **five heights**: flat, and `_t3`, `_t6`, `_t12`,
`_t24`. Plus `blank`, a transparent tile used to pad the layer where its art
overhangs. 86 in a 10 x 9 grid.

### Anchored to the BOTTOM of the cell
The base diamond — where the surface meets the ground — is in the **bottom
32 px** of the cell, and height is drawn **upwards** from there into the spare
32 px above.

That is the only anchoring that works on a single layer. Anchored to the top,
height hangs *below* the footprint, and the tile in front is drawn after it and
paints straight over it — measured, **0 visible kerb pixels** anywhere on the
street. Anchored to the bottom, height rises into the cells *behind*, which are
drawn earlier, so a raised surface occludes what is behind it and nothing can
cover its face.

It is also the same convention as the wall panels, so there is one rule.

### A face only shows where the neighbour is lower
Nothing knows where "the kerb" is. Every pavement cell is the same raised tile;
inside a field of one height, every face is covered by the tile in front of it
(measured: **0 px** of face visible in the interior, at every height). The face
appears exactly where the surface meets something lower — along the road, and
at corners — for free.

> A raised surface only ever shows its **south-west and south-east** faces.
> That is the projection, not a bug: the far pavement shows its kerb against
> the road, the near pavement shows its kerb on the side away from it.

### Every edge steps 2 across for 1 down
Both the surface and its faces come from the same mask: `_extrude()` drags the
footprint's silhouette downwards, so a face cannot step differently from the
surface above it. Drawing the faces as polygons instead put their west corner
one pixel outside the diamond and produced a 2, 2, **3** step in the lower
edge.

**Every step of every edge is 2 across, 1 down — including into the points.**
That comes from the row widths: `4, 8, 12 … 64, 60 … 4`, which has a single
widest row and puts real one-row points at x=0 and x=63.

The obvious `2, 6 … 62, 62 … 6, 2` has the same area and also tiles, but its
widest row appears twice, so the extremes are a 2x2 stub that stops at x=1.
Flat that is invisible; raised it becomes a two-column vertical bar at every
point, and consecutive kerb faces stop two columns short of each other.

If you repaint these by hand the one rule that matters is **2 px across for
every 1 px down**, on the surface edge and the face edge alike, with no step
of 1 or 3 anywhere. Verified by listing the first opaque pixel of every row of
every tile: steps of only 0 and 2, across all 85 tiles.

You have more freedom than the generator takes. Nothing stops a painted tile
from filling columns 0 and 63 — it just must not leave a gap, and the tile in
front will draw over anything extra.

### Limits
- **Height ceiling is 32 px** — the spare cell above the base. Higher needs a
  taller cell, not a taller drawing: art that overhangs its cell is dropped by
  Godot in a band along the top and left of the whole map.
- **Keep the cell height even.** The anchor is `+(cell_h - 32) / 2`, and an odd
  cell puts the base on half a pixel.
- **A character on a raised surface is drawn `t` px into it.** Navigation is a
  single flat plane, so a character's feet sit on the *base*, while the surface
  is drawn `t` px higher. At the 6 px kerb this is invisible. Much above ~8 px
  and placement would have to be lifted to match, which nothing does yet — so
  treat `_t12` and `_t24` as scenery to walk *past*, not to stand on.

A letter in `GROUND` (in `tools/build_street.gd`) names a **list** of surfaces
and which one a cell gets is hashed from its coordinates, so a surface mottles
slightly instead of being one flat colour. Height lives in the name, so the
pavement letters carry the kerb and there is no second map to keep in step.

## walls.png — 64×122, laid out 4 pairs x 5 rows (512x610)

One **storey** of one **face**, one bay wide. The base runs corner to corner
across the 64 px width, rising 32 px for the `_r` facing and falling 32 px for
`_l`. Above that is 88 px of storey, plus margin.

### Every edge steps 2 across for 1 down
The base climbs `PANEL_RISE` (32) across `PANEL_W` (64) — exactly 2:1 — and the
silhouette is built **column by column** from that rule, not drawn as a
polygon. A polygon's slanted edges are whatever the rasteriser decides, which
is what stopped the floor diamond tiling, and on a wall it showed as a base
stepping 2, 2, 3.

**Everything drawn on top is then clipped to that silhouette**, so no amount of
brickwork, window frame or string course can push a pixel past the outline. The
features are free to be sloppy at the edges; the outline is not.

**The first and last columns are single-column runs; everything between is
two.** That is what lets panels join: panel A's last column and panel B's first
are both half-steps at the same height, so together they make the two-wide run
the staircase wants.

Verified across all 40 segments: silhouette steps of only 0 and 1, every column
exactly 88 px tall, every panel rising exactly 32 over 64 columns — and on a
run of four panels, every interior run exactly 2 columns with only the two ends
of the whole wall as half-steps.

If you repaint these, that is the rule to keep, ends included — a two-column
run at the end of a panel makes a three-column step where it meets the next one.

### The rest of the contract
**A bay is two cells, not one.** A cell's wall face is only `TILE_W/2` = 32 px
across — too narrow to hold a 36 px door, which is why doors kept coming out
shorter than the Doctor while they were pegged to the tile. A panel is one
64 px bay = two cell faces, and it is placed two cells at a time.

The naming is the contract: **`g_*` is a ground floor, anything else an upper
storey**. The builder sorts them by that prefix, so adding a layout needs no
change anywhere else — and cannot leave a hole by being forgotten.

Architecture is sized against the **character**: the Doctor is 76 px for
1.8 m, so ~42 px to the metre. Life size would be an 84 px door and a 127 px
storey; these are drawn at about 3/4 of that on purpose, so the street reads as
something you look over rather than up at. A door is 36 x 66 px.

**The two facings are separate artwork.** They are mirror images geometrically,
but the two faces catch different light, so a flipped `_r` does not read as an
`_l`. Every name exists twice, `<name>_l` and `<name>_r`.

Brick throughout, with a **stone surround** to the windows and a wooden door. A
brick is a quarter of a bay wide and `REF["course"]` tall, so it matches masonry
anywhere else. Panels stack sideways into runs and upwards into storeys, so the
left and right edges must tile and the top must meet the bottom.

**The entry count is a multiple of the 4 pairs per row on purpose**, so the last
row is full — a ragged final row wastes sheet and reads as a mistake.

19 layouts + `quoin` = 20 entries x 2 facings = **40 segments**: `plain`,
`plain_b`, `window`, `window_b`, `window_lit`, `window_out`, `pipe`, `poster`,
`sign`, `vent`, and the ground-floor `g_plain`, `g_door`, `g_window`, `g_shop`,
`g_shopdoor`, `g_pipe`, `g_stone`, `g_stone_door`, `g_window_lit`.

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

## Hand-painted sheets are never overwritten

`tools/make_tiles.py` records the sha256 of everything it writes in
`sprites/street/.generated.json`, and on the next run it compares before
writing. A sheet whose bytes have moved on is **kept**, and the run says so:

```
  KEPT sprites/street/walls.png - painted over since it was generated, left alone
```

So painting over a placeholder is all it takes to adopt it — there is no flag
to set and no risk that a routine regeneration eats a day's work. A file with
no record at all is also kept, on the same reasoning: better to skip and say so
than to overwrite something whose origin is unknown.

Two things to know:

- **To go back to the placeholder**, delete the file (or its manifest entry)
  and re-run. There is no force switch, deliberately.
- **The manifest is written at the END of a run**, once every sheet is out.
  Without that the hash of a sheet the run just changed is never recorded, and
  the *next* run reads its own output as hand-painting and refuses to touch it
  — the guard latching onto everything it makes. Writing it last also means a
  crash mid-run leaves the old record standing rather than a half-updated one.

`walls.png` is currently hand-painted and has no entry. Keep it that way.

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
