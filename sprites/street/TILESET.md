# London Street — tileset analysis and spec

Working notes for replacing `nerva.tscn` with a tile-built London street, so
levels can be assembled from reusable parts instead of generating whole
backgrounds.

## What the reference actually is

Measured from the supplied screenshot (482x269), ignoring the UI and characters.

| Property | Measurement |
|---|---|
| Projection | **2:1 isometric**, slope 0.5, 26.57 deg |
| Native scale | 1x — the pixel runs match the console room's, so it is not upscaled |
| Cobble unit | **16 x 8** diamond lattice |
| Brick course | 7 px |
| Palette | 228 distinct colours, reducible to 28 without visible loss |

**The existing game shares the projection.** `main.png` measures slope ±0.505
on both floor axes, i.e. the same 2:1. Anything drawn to this spec drops
straight into the current scenes with the current characters.

**The reference is not internally consistent.** Measured slopes across the image
run 0.495, 0.535, 0.540, 0.565 — the right facade and cobbles are true 2:1, the
left facade and pavement are a few degrees off. That is generated art wobbling,
and it is exactly what makes it unusable as tiles: two pieces cut from it will
not line up. Hand-drawn tiles will be exact everywhere.

## Grid

**Ground tile: 64 x 32.**

(Originally speced at 32x16 off the cobble lattice; doubled after seeing it in
engine — at 32 the tiles read as too fine for the scale of scenery we want, and
a character stood four tiles tall. At 64 a character is a little over two tiles,
which is what the reference art does.)

Chosen because the cobble lattice is 16x8, so 32x16 is the smallest authoring
unit that is not a single stone; a character's footprint (27 px wide) is then
almost exactly one tile; and the 640x320 viewport is a round 20 x 20 tiles.

| | Screen vector |
|---|---|
| One tile along the X axis | `(+32, +16)` |
| One tile along the Y axis | `(-32, +16)` |
| Wall storey height | **64 px** (2 tile-heights) |

Characters are 71 px tall — about 4.4 tile-heights, or one and a half storeys.
That matches the reference, where the figures reach just past the ground-floor
window heads.

Anchor every tile and prop by the **centre of its ground footprint**, which is
where the existing `IsoSorter` sort point wants to be.

## Tile inventory

Ground (32x16, flat):
- cobble x3 variants, so runs do not visibly repeat
- cobble with puddle / with drain cover
- flagstone pavement x2 variants
- kerb: two edge orientations plus inner and outer corner
- gutter strip

Walls (32 wide x 48 tall above the footprint, two facings — NE and NW):
- plain brick
- brick with window (dark, and lit as a separate tile)
- brick with door
- brick with poster x2
- stone plinth (the ground course) and parapet (the top course)
- inner corner, outer corner

Props (free-standing sprites, not tiles):
- gas lamp, wall-mounted
- cardboard box, large and small
- wooden crate
- newspaper / litter x3
- basement railing run
- wall vent grate
- drainpipe

## Do not bake the lighting in

Most of the reference's atmosphere is a warm pool under the lamp falling off
into near-black — 26.8% of the scene is pure black. If that is painted into the
tiles, they can only ever be used at that one distance from that one lamp, and
tiling them will produce visible bands of light and shade.

Draw every tile **flat and neutrally lit**, then light the scene at runtime with
`CanvasModulate` for the night tint plus `PointLight2D` on each lamp. The tiles
stay reusable and the lamps become placeable.

## What tiles buy us beyond reuse

The current console room has its walkable area hand-authored twice over: a
`CollisionPolygon2D` set and a separate navigation outline that has to be kept
in step with it. A Godot `TileSet` carries a physics layer and a navigation
layer **per tile**, and `TileMapLayer` bakes both automatically. Painting a
floor tile would give collision and pathfinding for free, and `nav_region.gd`
plus the hand-traced outline could go.

## The open question: sorting

Two depth systems would be in play and they do not compose — `IsoSorter` writes
`z_index` directly, while `TileMapLayer` y-sorts within itself.

The likely split is: **ground on a `TileMapLayer`** (flat, always beneath
everything, fixed z, no sorting needed), with **walls and props as ordinary
sprites carrying `IsoSorter`**, exactly as the console room does now. That keeps
one proven sorting system for everything that can occlude a character, at the
cost of not being able to paint walls with the tilemap editor.

Worth prototyping both on a single corner before committing.

## Files here

- `palette.png` / `palette.txt` — 28 colours lifted from the reference; the
  `.txt` is a GIMP/Aseprite palette
- `tile_template.png` — 200x80 guide sheet: ground diamond, wall NE, wall NW,
  corner and prop cells, magenta guides on transparent, with the anchor pixel
  marked in cyan
