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
| `floors.png` | **64×32** | 17 tones (+blank) | the ground: flat diamonds, no pattern |
| `kerbs.png` | **64×48** | 33 (+15 spare) | a pavement tile whose edge hangs |
| `walls.png` | **64×122** | 38 | one storey of a building face |
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
`W·H/2` pixels, so a tile must cover precisely that — rows of 2, 6, 10 … W−2
and back down. `iso_mask()` builds it; `close_to_mask()` then fills anything
the painter left short, because masking multiplies alpha and can only ever
remove. Measured after: **0 seam pixels** anywhere in the floor.

---

## floors.png — 64×32, laid out 3 x 6 (192x192, square)

**Flat diamonds, one tone each, no pattern.** A pattern drawn into a 64x32 tile
fights the eye at this size and is awkward to repaint; a ramp of tones reads as
a surface and takes its detail from the decals layer instead. Recolouring a
surface is then one pixel.

Six pavement tones (`pave_1`..`pave_6`, light to dark), six road
(`road_1`..`road_6`), three dirt, two shade, plus `blank` — a transparent tile
used to pad layers whose art overhangs. 18 slots is exactly 3 x 6, which at a
2:1 tile is a **square sheet**.

**The art must not exceed 64x32**: Godot drops tile art that overhangs its
cell, in a band along the top and left of the whole map, which reads as "the
floor stops short" rather than as a tiling bug.

A letter in `GROUND` (in `tools/build_street.gd`) names a **list** of tones and
which one a cell gets is hashed from its coordinates, so a surface mottles
slightly instead of being one flat colour.

## kerbs.png — 64×48, laid out 6 x 8 (384x384, square)

A pavement tile with the drop to the road **hanging below** it: the floor
diamond in the **top 32 px**, then the lip below it.

**A kerb is two choices — which surface, and how far it drops** — so the sheet
is that grid rather than a hand-picked list: `<tone>_edge`, `<tone>_edge_low`
and `<tone>_edge_high` for every floor tone a footway can be made of (the six
pavement tones, three dirt, two shade). 11 x 3 = **33**, and a new floor tone
brings its three kerbs with it for free. Road tones are excluded — a road has
no kerb, it is what the kerb drops *to*.

The drops are 3 / 6 / 10 px against the reference's 6 px kerb: `_low` is a
dropped crossing, `_high` a raised footway. A kerb is a lip you step over, not
a step you climb — at 12 px it reads as the latter, which is why the tall one
stops at 10.

The cell allows a lip of up to **16 px**, more than the tallest drawn here, so
a taller variation can be painted straight into the spare rows and nothing else
needs changing. 6 x 8 is exactly square at a 64x48 cell, and the 15 unused
slots are there to paint into without reshuffling the index.

Keep the diamond in the top 32 px wherever the lip ends: the tile is anchored
on its footprint, not on the art, so a taller lip grows downward over the road
rather than lifting the pavement. And keep the cell height **even** — the
anchor is `-(cell_h - 32) / 2`, and an odd cell puts the footprint on half a
pixel.

Not a raised block — a raised block hides its own faces, because the next tile
along the run covers them.

One of these goes on **every pavement cell**, not just the row beside the road.
Where the neighbour is more pavement its top covers the hanging face, so the
footway reads as continuous; where the neighbour is road, that is a floor tile
on the layer below and cannot cover anything, so the lip shows. Corners come
out right without being special-cased.

The surface is exactly the matching floor tone, so the footway is seamless
against the plain floor beside it.

## walls.png — 64×122

One **storey** of one **face**, one bay wide. The base line runs corner to
corner across the 64 px width, rising 32 px for the `_r` facing and falling
32 px for the `_l` facing. Above that is 88 px of storey, plus margin.

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
