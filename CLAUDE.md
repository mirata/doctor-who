# Doctor Who — CLAUDE.md

## Project Overview

A Doctor Who themed isometric adventure game built in Godot 4.6. The current scene is a TARDIS secondary console room. The player controls Tom Baker's Doctor with 8-directional movement, isometric depth sorting, and ambient audio.

**Engine:** Godot 4.6.2 stable  
**Main Scene:** `secondaryconsole.tscn`  
**Viewport:** 640×320 internal, launched maximised with integer scaling (4× on a 2560-wide screen), letterboxed  
**Texture filter:** Nearest-neighbour everywhere (pixel art)

---

## Controls

| Action | Input |
|--------|-------|
| Walk to a spot | Left mouse click |
| Talk to someone | Click them, or E when near |
| Advance dialogue | Click the balloon, or Space / Enter (`ui_accept`) |
| Skip the typing effect | Escape (`ui_cancel`), or click while it types |
| Move left | A |
| Move right | D |
| Move up | W |
| Move down | S |

Clicking pathfinds across the room's navigation mesh; WASD still works and
cancels the current click destination.

---

## Key Files

| File | Purpose |
|------|---------|
| `secondaryconsole.tscn` | Console room — layout, audio, Player instance |
| `levels/street.tscn` | London street, built from tiles — reached through the DoorTrigger |
| `scene_door.gd` | `Area2D` that fades to `target_scene` when a body enters |
| `levels/street_tileset.tres` | The street `TileSet`: collision + navigation per tile |
| `sprites/street/ASSETS.md` | **What to paint** — every sheet, its cell size and anchor |
| `sprites/street/floors.png` | 96x48 floor diamonds |
| `sprites/street/kerbs.png` | 96x64 kerbs (a floor tile plus a lip) |
| `sprites/street/walls.png` | 96x162 wall panels, one storey of one face |
| `sprites/street/props/` | free-standing objects, sized by their own artwork |
| `sprites/street/TILESET.md` | Measurements and the original grid analysis |
| `nerva.tscn` | Superseded by the street; kept but no longer linked |
| `character.gd` | **`Character` base class** — movement, pathfinding, animation, idle/run state |
| `camera_follow.gd` | Camera that gives on acceleration but locks at constant speed |
| `dialogue/*.dialogue` | Conversations, in Dialogue Manager's script format |
| `dialogue/balloon/tardis_balloon.*` | The pixel-art dialogue balloon |
| `fonts/PressStart2P-Regular.ttf` | Pixel font for UI text (SIL OFL, licence alongside) |
| `addons/dialogue_manager/` | Third-party: Dialogue Manager 4.1.0 |
| `nav_region.gd` | Re-bakes a room's navmesh from live collision geometry on load |
| `navigation/secondaryconsole_nav.tres` | Walkable floor outline for the console room |
| `player.tscn` / `player.gd` | **The Doctor.** Walks on WASD. Owns the camera |
| `sarah.tscn` / `sarah.gd` | **Sarah Jane.** Follows the Doctor by breadcrumb trail |
| `animations/character_animations.tres` | Shared animation library — retiming a walk here changes it for everyone |
| `animations/character_state_machine.tres` | Shared idle/run state machine |
| `console_sounds.gd` | Randomised ambient console beeps every 5–20 s |
| `fade_in.gd` | Black-screen fade-in on scene start (2.5 s tween) |
| `ambient_music.gd` | **BROKEN** — wrong path, redundant with TARDISAmbient node; ignore or delete |
| `animations/player_idle_blend.tres` | 2D blend space for idle (5 directions) |
| `animations/player_walk_blend.tres` | 2D blend space for walking (5 directions) |
| `addons/iso_sorter/` | Custom isometric depth sorting addon |

---

## Player (`player.tscn`)

The Doctor lives in one place and is **instanced** into each room, never copied.
Rooms carry a `Player` node with `instance=ExtResource(...)` pointing at
`player.tscn`; the only thing a room overrides is `position`, which acts as its
spawn point.

Anything that belongs to the character — sprite sheet, `hframes`, collision
shape, camera, the AnimationPlayer's whole library, the AnimationTree and the
movable IsoSorter — belongs in `player.tscn` so every room picks the change up
for free. Adding a new room means instancing `player.tscn` and setting its
position, nothing more.

> Both rooms previously held hand-copied Player subtrees, which is how `nerva`
> was left on the old 25-frame sheet when the Doctor was upgraded. Don't
> reintroduce a per-room copy.

---

## Characters

Everyone who walks around a room extends **`Character`** (`character.gd`).
The base owns movement, the blend-space positions, sprite flipping and the
idle/run state machine. A subclass only decides *where* to walk:

```gdscript
## Direction to walk this frame. Zero means stand still.
func _decide_direction() -> Vector2
## Speed this frame. Override to vary it situationally.
func _current_speed() -> float
## Called on the idle→run and run→idle edges.
func _on_started_walking() / _on_stopped_walking()
```

The Doctor returns the WASD vector and plays footsteps on the edges; Sarah
returns a direction along her breadcrumb trail. Nothing about facing,
flipping or animation lives in either subclass.

Both characters use the **same** `character_animations.tres` and
`character_state_machine.tres`, and each has exactly one `Sprite2D` child named
`Sprite` — the base finds it by type, and the animation tracks address it as
`Sprite:frame`. A character whose sprite node is named anything else will not
animate.

### Walking is intent, not progress
`move_direction` drives the animation, **not** `velocity`. After
`move_and_slide`, `velocity` is the *resolved* motion, and sliding along a wall
built of 24x12 collision diamonds resolves to zero on some frames and not
others: the character glides along in the idle frame while `flip_h`, taken from
`velocity.x`, flickers as the tangent changes sign. Someone pressed against a
wall is still walking. Measured holding a direction into a wall for 111 frames:
**111 run, 0 idle, 0 facing flips**.

The blend position was already taken from intent for the same reason; the idle
condition and the flip now are too.

### Giving up on a route
Intent-driven animation needs something to end the intent, or a character
wedged on a corner walks on the spot forever — the path says "that way", the
collision says no, and nothing notices the two disagree.

`Character._check_progress()` measures **actual travel**, not path progress, so
sliding along a wall toward the goal still counts. After `stuck_seconds` (0.6)
without covering `stuck_distance` (2 px) it calls `_on_stuck()`, which by
default clears the destination — and since the animation follows intent, the
character goes idle by itself. Measured: gives up after 0.58 s, idle 5 frames
later.

It applies to **navigation only**. Holding a direction against a wall is the
player's business and they can see what is happening.

> Sarah overrides `_on_stuck()`. Clearing her destination is not enough on its
> own: she re-targets the Doctor the very next frame, so she would re-wedge on
> the same corner every 0.6 s. She now waits where she is until he has moved
> far enough that the route would be a different one.

### Pixel-grid movement

The viewport is 640x320, so **nothing can move less than one pixel**. With
`snap_2d_transforms_to_pixel` a fractional step per frame renders as an uneven
stutter, and no amount of camera work fixes it — the motion simply does not land
on the grid.

`speed` must therefore be a multiple of the physics tick rate (60). At the old
100 px/s that was 1.6666 px/frame, and the world scrolled in a repeating
**1, 2, 2** cadence (a 20 Hz wobble) while the sprite's snapped offset from the
camera flipped between -1 and -2. At **120** it is exactly 2 px/frame: cadence
2, 2, 2 and a fixed sprite offset.

**Diagonals are still fractional** — normalising gives 120 x 0.7071 = 1.4142
px/frame and a 1, 2, 1, 1, 2 cadence. Fixing that means quantising the eight
directions to whole-pixel vectors, which forces diagonal travel to be either
~41% faster (2 px per axis) or ~29% slower (1 px per axis) than cardinal. That
is a game-feel decision, deliberately not taken.

When diagnosing anything like this, measure the **rendered** result — log
`round()` of the camera and sprite positions frame by frame. World-space
transforms will look perfectly smooth while the screen stutters.

### Camera

`Player/Camera2D` runs `camera_follow.gd` with `top_level = true`, driving its
own global position rather than inheriting the Doctor's.

**Do not turn Godot's `position_smoothing_enabled` back on.** It trails a moving
target by `velocity / smoothing_speed` — a permanent ~20 px lag at walking pace.
The offset itself is harmless, but with `snap_2d_transforms_to_pixel` the camera
and the sprite cross pixel boundaries at different moments, so the sprite
shimmers by a pixel the entire time it moves. Measured with it on, the Doctor's
on-screen position swung 40.6 px and changed whole-pixel position on 413 of 517
frames.

The replacement feeds the target's measured velocity forward, so the camera
travels at exactly their speed and the spring only absorbs *changes* in speed:

| Export | Default | Meaning |
|--------|---------|---------|
| `slack_seconds` | 0.18 | How long the camera takes to pick up speed when they start or speed up. Deliberately one-directional — see below. 0 makes it rigid |
| `follow_speed` | 8.0 | How sharply the drift is recovered afterwards |

Two details that are easy to get wrong, both of which produced visible faults:

- **The slack only applies to speeding up.** Easing *out* of a speed means the
  camera coasts on after they have stopped, so it sails past and springs back.
  Measured with a symmetric ease: 7.07 px past him, taking ~90 frames to return.
  Direction is always taken from the target exactly, and speed drops instantly.
- **Correct the error after travelling, not before.** Doing it first leaves the
  camera permanently one frame of travel ahead (+2.00 px at 120 px/s), which
  then has to unwind every time they stop.

Measured now: 5.6 px of give while getting going, **0.00 px** of overshoot on
stopping, and a resting offset of **0.00 px** — at constant speed the camera
sits exactly on him, so both snap to the pixel grid identically. Velocity is
measured from the target's actual position change, so walking into a wall counts
as standing still.

### Navigation

`Character` exposes the pathfinding both characters use:

```gdscript
set_destination(world_position)   # snapped onto the navmesh
direction_to_destination()        # steering for this frame, ZERO once arrived
has_destination() / clear_destination() / get_destination()
```

A room provides a `Navigation` (`NavigationRegion2D`) node and is in the
`navigation_source` group; characters carry a `NavigationAgent2D`. **A room with
no navigation mesh is fine** — `set_destination` falls back to straight-line
steering, which is what `nerva.tscn` currently does.

The mesh is **outline minus static colliders**. The outline in
`secondaryconsole_nav.tres` is the floor boundary; drag its points in the
editor. Colliders inside it are carved out, so moving a wall updates
pathfinding for free. Source geometry is parsed from the `navigation_source`
group, not the region's children — with the default mode the editor's *Bake
NavigationPolygon* button finds no colliders and silently bakes a bare outline.

The room is a **single flat plane**: stairs are ordinary corridors in the mesh
and need no links. A genuine second storey overlapping this one in screen space
would need `NavigationLink2D`.

#### Things that will bite you here
- **`agent_radius` must equal the character collision radius**, currently
  **4** for both. The baked mesh is not the floor — it is the set of positions a
  character's *centre* may occupy, i.e. the floor eroded by the body radius. Set
  it below the body and paths are generated through gaps the body cannot fit,
  so it wedges against walls while the agent insists the path is fine. Measured
  with a 6 px body: at 3 and 4 the Doctor stalled on 2 of 6 destinations, at 5
  on 1 of 6, at 6 and 7 on none — the cliff is exactly at the body radius.
  **To change the visible inset, move the body and the agent together**;
  measured walkable mesh by radius: 6 -> 514 sample points, 4 -> 890, 3 -> 953,
  each with 0 stalls of 8 destinations and no stranded islands. The body
  radius lives in `player.tscn` and `sarah.tscn` as a `CircleShape2D`, and both
  must match or the mesh is wrong for one of them.
- **Do not use `is_navigation_finished()` alone for arrival.** The path is built
  asynchronously and the agent reports "finished" in the frames before it
  exists, which reads as an instant arrival. Measure distance to the target.
- **Do not query the map before it has synchronised.** `map_get_closest_point`
  errors and returns the origin, sending characters walking to (0, 0). Gate on
  `map_get_iteration_id(map) > 0`, and re-check every frame rather than latching
  when a destination is set — regions register over the first few frames.
- **Characters must not block each other.** Sarah adds a mutual collision
  exception with the Doctor in `_ready()`. Without it she blocks him bodily and
  neither can resolve it: he cannot get past, and she only moves once he is far
  away. She keeps out of his way in `_after_move()` instead — see below.
- **After editing the outline, check for islands** — a walkable patch cut off
  from the rest strands whoever clicks on it. Path from the spawn to a grid of
  mesh points and confirm every one is reachable.

### Sarah's following

She routes to the Doctor through the navigation mesh, so she goes around the
furniture and up the stairs rather than walking into things.

Her pace is **continuous, not on/off**: speed is `his pace + (gap - wanted gap)
x catch_up_gain`, so the further behind she is the harder she pushes, and at the
right distance she is moving at exactly his speed. That is a stable equilibrium
— drop back and the gain pushes her on, crowd him and she eases off — so she
holds station instead of stopping dead and sprinting again. An earlier on/off
version stopped at one distance and restarted at another, which read as a
stop-start shuffle over any real distance.

Her speed is also rounded to whole pixels per frame (60 / 120 / 180 / 240), for
the same reason his is: fractional steps stutter on a 640x320 viewport. It also
gives the burst distinct gears rather than a sliding speed.

| Export | Default | Meaning |
|--------|---------|---------|
| `follow_distance` | 90 px | The gap she settles into while he walks |
| `stop_distance` | 55 px | The gap she closes to once he stops |
| `catch_up_gain` | 2.0 | Extra speed per pixel she is behind — this is the burst |
| `max_speed` | 240 | Ceiling on the burst |
| `repath_distance` | 20 px | How far he moves before she re-routes |
| `personal_space` | 14 px | How close he gets before she gives way |
| `yield_speed` | 300 | Ceiling on how fast she is shouldered aside |

#### Giving way rather than colliding
There is **no hard collision between the two of them** — that is what guarantees
he can never be wedged against her, and it is verified by checking that none of
his slide collisions are ever her. Instead, `_after_move()` nudges *her* out of
*his* way whenever he comes within `personal_space`, using `move_and_collide` so
walls still stop her.

Two things this got wrong on the way, both worth keeping in mind if it is
retuned:

- **The yield ceiling must stay well above walking speed.** At 90 px/s against
  his 120 he simply outran her giving way and passed straight through.
- **She sidesteps, she does not back away.** Pushing her directly along his
  heading just shoves her across the room ahead of him and he never gets past;
  the push is biased perpendicular to his heading, towards whichever side she
  already leans.

If she is cornered and cannot give way, he passes through her. That is the
deliberate fallback: a visual overlap for a moment beats a stuck player.

Measured over a long straight walk: she settles to a constant gap of ~100 px
(2.6 m) with **zero** swing, moving at his exact speed, and closes to precisely
`stop_distance` when he stops. Starting 240 px behind she bursts at 240 px/s and
gears down through 180 to 120 as she arrives. Because the gain gives a band of
valid resting gaps rather than a single point, the settled distance varies by up
to ~30 px depending on how she approached; raise `catch_up_gain` to narrow it.

---

## Player Script (`player.gd`)

### State machine
```
State { IDLE, RUN, ATTACK, DEAD }
```
State transitions happen at the bottom of `movement_loop()` based on whether `motion` is non-zero.

### Animation tree parameters
The AnimationTree uses a state machine with two blend-space states. Both must be kept in sync:
```gdscript
animation_tree.set("parameters/Idle/blend_position", last_facing)
animation_tree.set("parameters/Run/blend_position", last_facing)
animation_tree.set("parameters/conditions/Idle", is_idle)
animation_tree.set("parameters/conditions/Run", !is_idle)
```

### Blend position convention
- `last_facing` is a **normalised Vector2** with `abs(x)` and **negated y**.
- The y-axis is negated because Godot's screen-space y goes down but the blend space treats up as positive.
- `last_facing` only updates when `move_direction != Vector2.ZERO`, so it persists when the player is idle or stuck against a wall.
- Blend position is driven by **input direction** (`move_direction`), not `velocity`, so it is correct even when the player is pressed against a wall.
- Default `last_facing` is `Vector2.UP` (facing north).

### Sprite flipping
`Sprite.flip_h` is set only when `velocity.x != 0`, preserving the last horizontal facing during idle. The spritesheet only contains right-facing frames; left movement is handled by flipping.

---

## Tile levels

`levels/street.tscn` is built from a `TileSet` rather than a painted backdrop.
The full analysis behind the grid is in `sprites/street/TILESET.md`; the
practical points:

- **Two grids, split by job.** `tile_size` is a property of the **TileSet**,
  not of the tilemap, so different layers can run at different resolutions.
  The visible floor is back on **96x48**, which is the size a floor is
  comfortable to author and to paint in the editor; navigation and collision
  run on an invisible **24x12** layer underneath.
- That is what reconciles "floors are handy large" with "detail needs to be
  smaller", and it is better than stamping one big tile as 4x4 slices: painting
  a big floor tile no longer forces a big navigation cell, and nobody has to
  place sixteen pieces to lay one paving slab. 336 floor cells, 5376 nav cells.
- **The two grids do not share an origin.** Godot puts a cell's *corner* on the
  origin, so the centre of big cell (0,0) and the centre of the 4x4 of fine
  cells it covers differ by `(-36, 0)`. The `Floor` layer's position is
  **measured** from the two layers at build time rather than hard-coded — see
  `_fine_centre_of_big()`.
- `tools/make_tiles.py` slices each drawn floor by deciding every pixel's
  sub-cell from its position in tile space. Drawing 4x4 overlapping masks
  instead loses ~5% of pixels along the seams and the joins show; the analytic
  partition is lossless (measured 0.27 mean colour difference, invisible).
- **96x48 art tiles, 2:1 isometric** — the same projection the console room art
  already uses, so tiles and hand-painted rooms mix freely. One tile is a
  building **bay** — the spacing between window centres in the reference art —
  rather than a person-sized square.
- The tilesheet uses **96x144 cells with the footprint diamond in the bottom
  48 px**, and every tile sets `texture_origin = (0, -48)` to lift the art so
  that footprint lands on its cell. Blocks are just taller art in the same cell.
- `tools/make_tiles.py` generates the sheet **and `tiles.json`**, which is the
  single source of truth for tile names and whether each is walkable or solid.
  `tools/build_street.gd` reads that file, so the two cannot drift apart — only
  `TW`/`TH`/`CELL` still need keeping in step by hand.
- `TILE_W`/`TILE_H` at the top of the generator drive cell size, block heights
  and every pattern, so the whole set rescales from one value. Keep
  `TILE_W = 2 * TILE_H`.
- **Never bind a tile dimension as a default argument.** Python evaluates those
  once at import, so `def diamond(cx, cy, w=TILE_W, h=TILE_H)` ignored
  `at_size()` and drew every quarter-native tile at the big size — the kerbs
  came out as blobs filling their cell, and 90 pixels of the floor sheet were
  wrong. Resolve inside the body: `w = TILE_W if w is None else w`.

### Sliced vs quarter-native art
Both fill the same 4x4 of quarter cells, and which one a floor uses is what
decides whether it *looks* large-tiled:

| | drawn at | reads as |
|---|---|---|
| **Sliced** (`cobble_a`, `flagstone_b`, ...) | 96x48, then cut into 4x4 | big stones — the pattern is just cut up |
| **Quarter-native** (`q_flag`, `q_cobble`, `q_road`, ...) | 24x12 | small stones, one per fine cell |

`_stamp_floor()` picks between them by name: a name the grid catalogue holds on
its own is quarter-native and gets `SUB x SUB` individually chosen tiles (from
`QUARTER_FAMILY`, so neighbours vary); anything else is stamped as its slices.
Changing a floor's look is one entry in `GROUND_KEY`. The street uses fine
paving and big cobbles on purpose — the road wants large stones.

### Thin walls
`q_wall_a` / `q_wall_b` (plus `_low`) are quarter-sized brick walls, a quarter
cell deep, for boundaries and partitions where a 96 px block is far too much.
Placed as runs in `WALL_RUNS`, stepping in quarters:

- **The two orientations are separate artwork.** `a` runs south-east, `b`
  south-west. There is no rotating a sprite in this projection, so a run with
  the wrong axis reads as a row of disconnected posts.
- They are drawn with three faces — long face, end cap, top — because a single
  quad at 24 px reads as a painted stripe rather than a wall.
- A quarter cell only leaves **2 tile-heights** of headroom above the floor
  diamond. Anything taller gets sheared off flat against the cell top.

**`at_size()` must swap `U` along with `TILE_W`/`TILE_H`.** Heights are written
in tile-heights, so leaving `U` at the big tile's 48 silently builds every
quarter block four times too tall — which looks like "the low variant isn't
working", because both get clipped to the same flat ceiling.

### Placing a sprite on the tile grid
Two helpers in the build script, and using the wrong one misaligns the art:

| helper | for | anchors on |
|---|---|---|
| `_big_to_local()` | blocks, kerbs, props, characters, the door | the centre of a **big** cell |
| `_quarter_to_local()` | thin walls — anything one fine cell in size | the centre of a **fine** cell |

Both take big-cell coordinates and accept fractions; in `_quarter_to_local` a
0.25 step is one fine cell, which is the convention the collision painting uses
too, so a quarter sprite and its collision cannot disagree.

**Godot places cell (0,0) with its CORNER on the origin, not its centre**, and a
big cell spans `SUB x SUB` fine cells, so its centre sits `SUB-1` fine rows
below the first of them. Together that is `(GRID.x / 2, ART.y / 2)` = **(12, 24)**
— exactly the error left behind when the layers moved to the quarter grid and
this helper kept computing `((x-y) * 48, (x+y) * 24)`.

The symptom is worth recognising because it does not look like a placement bug:
collision is painted on the tile grid and stays correct, so the *art* drifts off
the geometry. You walk through walls you can see and collide with nothing you
can, characters stand on top of blocks, and Y-sort compares the wrong row so
occlusion inverts near anything solid. `_assert_alignment()` now checks both
helpers against `layer.map_to_local()` on every build and prints loudly.

Verified after the fix: 131 of 131 solid sprites stand on their own collision
cell (the other 56 are kerbs, deliberately walkable, and free-standing props,
which carry their own `StaticBody2D`), 0 walkable cells overlap a solid one, and
**0 of 5712 frames** walking all eight directions from six spots ended inside
solid geometry.

### Wide, flat things cannot be Y-sorted
**Y-sort judges a sprite by a single point, so it cannot express "wide but
flat".** A kerb is 96 px of art sorting from its diamond centre, and its lip
reaches 48 px either side of the y it is judged by — so a character standing on
the pavement just *north* of that point is legitimately behind the kerb and
still gets drawn over, with the kerb line cutting across their shins. Measured
at big (6, 3.7): the kerbs at (6,4) and (7,4) sort 7 px and 31 px below him.

Since a 4 px lip could only ever hide 4 px of a 96 px character, the answer is
that it should not occlude at all — and a thing that never occludes and never
sorts is exactly what a **tile** is. Kerbs are a `Kerbs` TileMapLayer at
`z_index = -50`: above `Ground` (-100) and `Decals` (-99), below everything that
walks. **`z_index` takes precedence over y-sorting**, so they are out of the
contest by construction rather than by sorting them more cleverly.

That also makes them paintable in the editor, and turns 48 `Sprite2D` nodes
into one layer.

Verified across 264 positions along both kerb lines (comparing z first, then y,
the way the renderer does): kerbs draw over the player **0** times, while
buildings and thin walls still do 212 times — those are tall enough that
occluding is correct.

Use `Props` (Y-sorted) only for things tall enough that hiding a character is
the right answer. Anything flatter than it is wide belongs on a fixed
`z_index`, and if it never occludes at all it should be a tile.

#### Tiles taller than a cell need their own atlas source
`texture_region_size` is per **source**, not per tileset, so a `TileSet` can mix
cell sizes. Kerb art is 24x36 against a 24x12 grid, so it lives in source 1
(`tiles_quarter.png`) with `texture_origin = (0, -12)` lifting the art so its
footprint diamond lands on the cell instead of the middle of the region — the
same offset the wall sprites use, `-(QUARTER_CELL.y - GRID.y) / 2`.

This is the general way to make *any* block art into tiles. Only do it for
things that must not occlude: `tiles.json` carries a `kind` per quarter tile,
and the builder turns `kerb` into tiles while everything else stays a sprite.

#### Quarter-native art needs its detail thinned out
Two things that looked fine at 96x48 and were wrong at 24x12, both because
there are now **16 tiles where there was one**:

- **Roll variants per big cell, not per fine cell.** Rolling per tile scattered
  weeds and chips sixteen times as thickly and the kerb read as speckled.
- **Drop per-tile edge highlights.** `block()`'s `cap` lights the top-back
  edges, which is right on one 96 px kerb and turns a run of quarter kerbs into
  a lattice of light lines. `t_kerb(cap=False)` for the quarter set.

Laid up in a grid the quarter kerbs are gap-free (measured: 0 transparent
pixels inside the field) and show faces only at the outer boundary, which is
what a continuous kerb should do.

### Solid things have to be carved out of the navmesh
Collision and navigation are independent: the paving stone under a wall is still
a walkable tile, so without carving a character paths **straight into** the wall
and grinds along it until it can slide past.

`_carve_navigation()` runs last, after every solid thing is placed, and moves
each cell under collision from `Ground` to `GroundBlocked` — a layer with
`navigation_enabled = false`. Same art, same position, no navigation polygon.
Duplicating every floor tile as a non-navigating twin would work too and doubles
the tileset for nothing.

Measured after: crossing a low wall walks 211 px against a 54 px straight line
(it routes around the end), building interiors sit 59 px off-mesh, and all four
pavement corners still reach each other — carving is the easiest way to
accidentally strand part of a level, so re-check reachability after changing it.

### Props are sprites, not tiles
**A prop's size comes from its artwork, not from the tile grid.** That is what
lets a 36 px bin stand on a 96 px floor tile.

Anything free-standing — phone box, bins, skips, boxes, bike rack — is a
`Sprite2D` under `Props`, placed at a tile cell plus a sub-tile nudge, with a
small `StaticBody2D` circle at its foot sized to what it actually occupies. The
artwork in `sprites/street/props/` was carved from the reference image, so the
proportions are the reference's.

> Drawing props as *tiles* was a mistake worth not repeating: a tile is 96 px
> wide by definition, so every prop came out 96 px wide — a phone box at 96x134
> instead of 40x86, a dustbin the size of a skip. The tile grid should only
> govern the floor and the walls that follow it.

The generated furniture is now drawn at its **own** footprint by `PROP_ART` /
`write_props()` in the generator, which emits one PNG per object into
`sprites/street/props/` beside the carved artwork. Heights already came from
`REF` in pixels, so only the footprint width needed saying — a dustbin is 28 px
across, a bollard 12, a skip 48.

Cropping each to its ink means the bottom edge is the front of the base, which
is the same anchor the carved props use, so `_place_props()` needs no special
case for either kind.

`at_size()` takes a `cell_h` for this: a phone box is 86 px tall on a 28 px
footprint, far past the default `TILE_H * (1 + TALLEST)` headroom, and without
it the art is sheared off at the cell top.

**`BLOCK_KEY` is walls only.** Street furniture in the `BLOCKS` map comes out as
a 96 px cube — crates and barrels laid that way were the size of a garden shed
and sat on top of the correctly-sized props, hiding them. Anything that is not
a building wall belongs in `PROPS`.

A prop with `"blocks": 0` is scenery you walk past rather than an obstacle, and
gets no `StaticBody2D` — a wall lamp, for instance.

**Props carve navigation too.** They collide with a circle rather than a tile,
so `_carve_prop()` takes the floor out from under each blocker, widened by the
body radius since the navmesh is where a character's *centre* may go. Without
it a character paths straight through a bin and grinds around it. Measured
after: 100 cells carved under 24 blockers, and 132 of 132 sampled spots across
both pavements and the road still reachable — carving near a prop is an easy
way to strand a corner, so re-check after moving things.

### Art the builder does not place
Generating a variant does not place it. If something is drawn but never seen,
check it against this list before assuming a bug:

- **Big kerbs and steps** (`kerb_worn`, `kerb_gutter`, `kerb_corner`, `step`…) —
  superseded by the quarter-native kerb tiles.
- **Tile-sized blocks** (`crate`, `barrel`, `plinth`, `stone_blk`, `iron_blk`,
  `brick_blk`) — spare parts for when a full 96 px cube is actually wanted.
  They are deliberately not scattered as scenery; see `BLOCK_KEY` above.
- **Decals** are placed by scanning for `layer == "decal"`, and thin walls by
  building `q_wall_<axis>` at runtime, so neither appears as a literal in the
  build script. They are in use.

### Feature sizes come from the reference, in pixels
`REF` at the top of `make_tiles.py` holds sizes measured off the reference art —
brick course 8 px, window 32x52, door 32x64, cobble 16 px, paving slab 30 px —
and the painters use those **in pixels**, not as fractions of a face.

That distinction matters. Sized as fractions, a window drawn at "half the face"
came out half the size of the reference's, and every change of tile size
silently rescaled the architecture with it. In pixels, brick stays brick whether
it is on a kerb or a two-storey wall, and the tile size can change again without
redrawing anything.

The tile width follows from the same measurement: a wall face spans `TILE_W / 2`,
the reference's window bays sit ~45 px apart, so `TILE_W = 96` fits one window
per tile with brick either side.

### Scattering variants
A letter in the level map names a **list** of tiles, and which one a cell gets is
hashed from its coordinates — so a run of cobbles varies without hand-placing
every stone, and a rebuild always produces the same street. Add a variant by
adding it to the list; no map editing needed.

**Decals are scattered procedurally**, not hand-placed: `_scatter_decals()`
walks the floor and drops one on `DECAL_DENSITY` percent of cells, chosen by the
same coordinate hash, so it is stable between rebuilds. They are the cheapest
way to stop a tiled floor looking stamped.

> A decal tile is *mostly transparent*, so the diamond clip must **intersect**
> the existing alpha rather than replace it. `Image.putalpha(mask)` overwrites
> it, which turns every unpainted pixel opaque black and paints black diamonds
> across the floor.

Current set: **51 tiles** — 16 floors, 28 blocks, 7 decals.

- floors: cobble x3, cracked, puddle, manhole, flagstone x2, cracked, drain,
  road x2, patch, puddle, gutter, dirt
- kerbs and steps: kerb x5 plus corner and dropped, step x2
- structure: plinth, stone, brick, crate, barrel, iron, brick wall, window,
  door, poster, pipe, stone wall
- obstacles: phone box, trash can x3, skip, bollard, postbox
- decals: paper x2, litter, grime x2, stain, scatter

The kerb lip is **4 px**, measured off the reference — a kerb is a lip you step
over, not a step you climb, and at 12 px it read as the latter.

### Tiles do not Y-sort against nodes
**Anything that must occlude a character has to be a `Sprite2D`, not a tile.**
Measured in 4.6: an identical wall placed as a `Sprite2D` sibling occludes the
Doctor correctly, while the same wall as a tile draws *behind* him — and that
holds whether he is a sibling of the `TileMapLayer` or a child of it, built that
way or reparented at runtime. A Y-sorted `TileMapLayer` sorts its tiles among
themselves; it does not merge them into the surrounding node sort.

So the street splits the job like this:

| Node | Visible | Grid | Job |
|------|---------|------|-----|
| `Floor` (`TileMapLayer`) | yes, `z −100` | 96x48 | the floor, art only |
| `Nav` (`TileMapLayer`) | **no** | 24x12 | **navigation** |
| `Blocks` (`TileMapLayer`) | **no** | 24x12 | **collision** |
| `Decals` (`TileMapLayer`) | yes, `z −99` | 24x12 | litter and grime |
| `Kerbs` (`TileMapLayer`) | yes, `z −50` | 24x12 | the kerb lip; never sorts |
| `Walls` (`Node2D`) | yes | — | facade panels, `IsoSorter` LINE |
| `Props` (`Node2D`) | yes | — | prop sprites, `IsoSorter` POINT |

An invisible `TileMapLayer` still collides and still bakes navigation
(`visible = false` does not touch either), which is what lets the fine grid do
that work while the coarse one does the drawing.

### The Blocks layer looks empty and still collides
It is not empty — it is painted with a tile that has **no art**, on a layer with
`visible = false`, and **hiding a `TileMapLayer` does not disable its physics**.
It still builds collision bodies from the TileSet's physics layer. That is the
whole arrangement: collision is painted once on an invisible layer while the
art is drawn separately as wall sprites, because tiles do not Y-sort against
nodes.

The `collision` and `walkable` marker tiles are **tinted** (magenta and green)
rather than blank, so ticking the layer's eye in the editor shows what is
solid. Nothing is drawn in game because both layers ship hidden.

**The scene is not the source.** `BLOCKS` in `tools/build_street.gd` is — one
letter per 96x48 cell — and the next build overwrites anything edited by hand
in the scene.

The build prints a walkability map every run: one character per big cell,
saying what is blocked and which of the four sources did it.

### Collision comes from the BLOCKS map, not from the walls
`_paint_collision()` marks **all `SUB x SUB` fine cells of every `BLOCKS` cell**
solid. A building is solid across its whole footprint, not just along the face
you can see — so you cannot walk behind a wall panel, because behind it is
inside the building. The panels are decoration on a solid block; moving one
does not move its collision, and the `BLOCKS` map is the thing to edit.

Props add their own `StaticBody2D` circles, and `_paint_corner_nooks()` closes
inside corners.

### Getting between the two rooms
| From | Trigger sits at | Goes to |
|------|-----------------|---------|
| Console room | the doorway in the **north-west** wall, world `(60, -62)` | the street |
| Street | the **top-left (west) end**, big cell `(1.0, 2.6)` | the console room |

Both are plain `Area2D` + `scene_door.gd`. Two things to keep true when moving
either one, both checked after the last move:

- **The trigger must be on the navmesh**, or click-to-move cannot reach it. The
  console doorway measures 0 px off the mesh, 115 px and 7 hops from the
  player's start.
- **A spawn must not sit inside the opposite trigger**, or arriving bounces you
  straight back. The street spawn is 96 px clear of the way home, which is why
  the characters arrive at big `(3.0, 3.0)` rather than on the doorstep.

The street's return point has **no artwork** — it is an invisible area on the
pavement. A TARDIS sprite there is still to do.

### Buildings are faces, not cubes
A building is not a block with a top — it is the **wall faces** you can see,
covered by panel sprites. One panel is `PANEL_BAYS` bays wide (a bay is 48 px,
the reference's window spacing) and one storey tall, and they stack sideways
into runs and upwards into storeys.

Worked out once so it is not re-derived every time:

| face | runs from | hidden by | consecutive faces join along |
|------|-----------|-----------|------------------------------|
| `l` | west vertex → south vertex | cell `(x, y+1)` | `+x` (down-right) |
| `r` | south vertex → east vertex | cell `(x+1, y)` | `−y` (up-right) |

`_spawn_facades()` finds runs of exposed faces, chops each into panels and
stacks storeys. Nothing is authored per wall: the `BLOCKS` map says where the
buildings are and the facades follow.

**A panel must never be wider than the run it sits in.** Laying every run in
whole `PANEL_BAYS` steps overruns any run that is not a multiple of it — a
one-cell run got a two-bay panel, which carried on into the building and drew
its *interior* face over anything standing in the corner. Runs are chopped with
`min(bays, remaining)` and a short panel crops its art from the left, which is
the start of the run for both facings. The build prints
`covering N of N exposed faces` and says `MISMATCH` if the two ever disagree.

**Only the south-west and south-east faces of anything are ever visible.** A
building on the *near* side of the street therefore presents its back to the
camera and stands between the camera and the pavement, so its wall occludes
whoever is walking there — correctly, and disastrously: a single 112 px storey
hides a 96 px character **outright**. Measured before the fix, the row-13
panels covered 9156 px² of a 9216 px character box.

So the near side draws **no facade at all** (`STOREYS_BY_BLOCK` maps it to 0)
and is bounded by a knee-high `WALL_RUNS` wall instead, which stops you walking
off without swallowing anyone. Its collision still comes from `BLOCKS`.

**Rule of thumb: nothing on the near side of a walkable area may be taller than
a character.** The far side can be as tall as you like.

#### Panel variations are composed, not drawn
A panel is a list of **bay** kinds, so "window + door" is a line in
`PANEL_LAYOUTS` rather than a new painter. Bays live in `BAYS` and each one
paints inside a `u` range. 20 layouts x 2 facings = 40 segments from about a
dozen small painters, and adding "boarded window next to a vent" costs one
line.

Ground-floor layouts are prefixed `g_` and drawn in stone; upper storeys are
brick. A string course caps every panel, which is what makes storeys stack
without a visible join.

Both facings are **separate artwork**. They are mirror images geometrically,
but the two faces catch different light, so a flipped panel reads wrong.

**The two facings slope opposite ways, and everything derived from the base has
to follow the artwork.** An `r` base starts low at the south vertex and rises to
the east vertex; an `l` base starts high at the west vertex and falls to the
south vertex. `_panel_base()` returning one shape for both put the sort line
across the grain of the picture *and* hung every `l` panel half its rise off the
ground — the walls floated, with a black gap along their feet. Checked on every
build: `41 of 41` panel bases land on the cell vertex they claim, sloping the
way their facing does.

#### Inside corners slice a character in half
A walkable cell whose **south-east neighbour is a building** sits behind that
building in depth, so the building correctly draws over anyone standing there.
But a wall panel's left edge is a straight vertical line — the building's
corner — so the character is cut cleanly down the middle rather than partly
hidden. Measured at the alcove's east cell: **744 of 1494** pixels visible, and
fully visible a quarter-cell west.

The occlusion is right; *standing there* is what is wrong, and an inside corner
of a recess has nothing in it anyway. `_paint_corner_nooks()` makes those cells
solid. Only a recess can produce one — ordinary pavement has pavement to its
south-east — so on this map it is exactly one cell.

Measured over **233 standable positions**, comparing each character's visible
pixels with the walls shown against with them hidden: one spot remains, with 31
of 1494 pixels covered, which is a hairline along a corner rather than a slice.

#### A stacked wall must sort as ONE object
Every storey of a wall shares the same base line, so giving each its own
`IsoSorter` makes the comparison return *equal* and the draw order fall back to
registration order. That is invisible for an `r` wall, whose upper storey sits
clear above a character — but an **`l` upper storey reaches down to
`anchor.y − 63` while a character's head is at `anchor.y − 74`**. The 11 px
overlap lands right across the hat and flickers as they walk.

So storeys above the ground are **children of the ground panel**: one sort
line, one `z_index`, and the whole wall draws together. `_spawn_wall()` builds
the stack; only the ground panel gets a sorter.

#### A wall's line stops at its ends
`IsoSortingManager._compare_point_pts()` used to follow a LINE sorter's base
*infinitely*, so a character standing past the end of a short wall was judged
behind it and drawn through. The alcove's one-bay side wall runs
`(300,240) → (348,216)`, slope −0.5; a character at x=290 is 10 px clear of its
west end, but the extrapolated line put them exactly on it — which is why it
flickered rather than failing consistently.

The comparison now **clamps to the segment**: outside its x-range it compares
against the nearer endpoint instead of extrapolating. Outside a footprint an
object has no depth to claim.

#### Measuring occlusion
Counting "pixels that differ with the walls shown vs hidden" is **not** a
measure of clipping — the background differs too, which is worth tens of pixels
and drowns the signal. Render four ways at each spot (walls×character on/off),
take the pixels that belong to the character, and count how many of those fail
to show. That is exact: it reported 0 where the pixel-difference method
reported 30.

Verified after the fix: **0 covered character pixels** at 80 positions hugging
the walls along both pavements.

> Sweep *standable* positions. An earlier sweep flagged spots inside building
> footprints where collision means nobody can stand, which is noise.

#### Registering sorters is deferred, or loading is cubic
`IsoSortingManager.register_sorter()` used to call `_rebuild_static_deps()` for
**every** static sorter as it arrived. That rebuild is O(n^2), so loading a
scene with n of them was O(n^3).

It went unnoticed while the street sorted by Y and registered nothing. Switching
the level to `IsoSorter` and adding the near-side boundary took it to **190
static sorters**, and `add_child()` on the street scene started taking **1941
ms** — two seconds of black screen behind the fade, which reads as a slow load
rather than as a sorting problem.

Registration now just sets a dirty flag and the graph is rebuilt once, in
`_process`. Measured: enter-tree **1941 ms -> 1 ms**, with a single 59 ms frame
for the deferred rebuild, then a steady 16.7 ms. Sorting unchanged at 280 of
280 probes.

> Ablation is the way to find this sort of thing, but only if the ablation
> really happens: switching the sorters off before `add_child` proves nothing,
> because `levels/street.gd` switches them straight back on in its `_ready`.
> The first measurement said sorters were innocent for exactly that reason.

### Sorting: the street uses IsoSorter, not Y-sort
**Y-sort judges a sprite by a single point, and a wall does not have one** —
its depth is the *line* of its foot. A character standing near one end of a
96 px panel sorts wrong against a point taken from the middle, by up to half
the panel's rise. That is the same failure that put the kerb lip across the
Doctor's shins, and it is not tunable.

So wall panels carry `IsoSorter` in **LINE** mode with the two ends of their
base, and props and characters carry it in POINT mode. Every storey of a wall
shares the **same** base line, so a two-storey wall sorts as one wall.

**The two systems cannot both be active** — `IsoSorter` writes `z_index` every
frame, which overrides Y-sort entirely. `levels/street.gd` switches the
characters' sorters *on* in `_ready()`; it has to be done in code because
`IsoSorter` reads `enabled` in its own `_ready` (which runs first) and a
property override set while building the scene is not serialised onto a node
inside an instanced scene.

The floor, decals and kerbs stay out of the sort entirely: they are pinned at
`z −100/−99/−50`, below the `0`-and-up that `IsoSortingManager` assigns.

Measured over every wall panel — 5 points along each base line, 7 and 16 px
either side — sorting is correct at **817 of 820** probes. The three misses are
all on one panel at a run boundary and are worth chasing if they ever show.

### Tile art must not overhang its cell
**Godot silently drops tile art that overhangs the layer, in a band along the
top and left of the map as deep as the overhang.** Reproduced in isolation: a
uniform 6x6 block of one tile loses its first two rows *and* first two columns.

The floor was hit by this. Its art lives in a 96x144 cell with the footprint in
the bottom 48 px, and the atlas source was pointed at the whole cell with
`texture_origin` compensating — which does not help, because the art still
stands 96 px proud of a 48 px tile. Two rows of the map vanished, which reads
as "the floor stops short of the buildings" rather than as a tiling bug.

The fix is to give the floor a region that is **just the footprint**:
`texture_region_size = 96x48` pointed at the bottom third of each art cell, and
no `texture_origin` at all. `FLOOR_COORDS` holds the remapped atlas coordinates.

Where the art genuinely needs the height — a kerb's lip stands 24 px above its
24x12 cell — pad the layer with fully transparent cells instead, so the band
that gets dropped is empty. `_pad_for_overhang()`.

So: **a tile whose region is bigger than its tile size is a liability.** Prefer
resizing the region; pad only when the height is the point.

### One sheet per job
`sprites/street/ASSETS.md` is the asset spec — cell sizes, anchors and what
places each sheet. Keep it true; it is what says which files are worth painting.

The build ends by printing **ART ACTUALLY PLACED**, gathered as it places
things rather than inferred. That is how to tell live art from leftovers: a
generator will happily keep emitting sheets nothing references.

It caught a lot of that. The floor was sliced into 16 pieces per tile for the
quarter grid and then went back to whole 96x48 tiles, leaving **256 sliced
tiles and 8 quarter-native floors** that nothing placed; blocks became wall
panels and props, leaving **28 block tiles** unreferenced. `decals.png` went
from 378 tiles to 114.

Block art is kept in `blocks.png` — a solid cube may be wanted somewhere — but
it is out of the active sheets and labelled so, rather than sitting among the
art that is live.

### Regenerating the level
`tools/build_street.gd` builds both the `TileSet` and the scene:

```
godot --headless --path . --script res://tools/build_street.gd
```

Editing the generated scene in the editor is fine — just know re-running this
overwrites it.

**Reload Godot after a rebuild.** The editor caches both the scene and the
imported textures, so a rebuild made while it is open shows the *old* level —
including old tile art, which is how a freshly tinted collision layer still
looks blank. File > Reload Saved Scene, and let it reimport.

**When instancing a character into a built scene, give an owner to the instance
root only.** Setting owners on its children makes Godot serialise them as brand
new nodes, so the saved scene gains a second `Sprite`, `AnimationPlayer` and
`AnimationTree` alongside the real ones. Two animation trees then drive the same
sprite and the character stops animating — with no error to point at it. Check
by counting: each character should have exactly one of each.

### Collision and navigation come free
The `TileSet` carries a physics layer and a navigation layer, and `TileMapLayer`
bakes both. Painting a floor tile gives pathfinding; painting a block gives
collision. Verified on the street: 336 of 336 floor cells navigable, a route
across the whole level, and zero frames spent inside a solid tile when walking
into a building. No hand-traced outline, no `nav_region.gd`.

**Mark things you step over as walkable, not solid.** The kerbs were solid at
first, which made an unbroken barrier down both sides of the road and split the
level into three disconnected navigation strips — the path across it stopped
122 px short. A 4 px kerb is scenery, not an obstacle.

---

## Dialogue

Uses **Dialogue Manager 4.1.0** (Nathan Hoad), which targets Godot 4.6+. Added
as a vendored copy under `addons/dialogue_manager/`, plugin enabled and the
`DialogueManager` autoload registered in `project.godot`. The C# half of the
addon was deleted on install — this is a GDScript-only project.

### Talking to someone
A character becomes interactable by getting a `DialogueActionable2D` child with
a `dialogue_resource` and a `cue` (Sarah has one named `Actionable`). Its
collision shape is what a click has to hit, so it is sized to the drawn figure,
not to the much smaller movement collider.

`player.gd` drives it two ways:
- **Clicking** an actionable walks the Doctor to it and starts the conversation
  once he is within `interact_distance` (34 px).
- **Pressing `interact`** talks to whatever is already within that distance.

He turns to face them first. While dialogue runs, `_in_dialogue` makes
`_decide_direction()` return zero and input is ignored, so the balloon owns the
keyboard — otherwise WASD walks him around mid-conversation.

### The balloon
`dialogue/balloon/tardis_balloon.tscn` is registered as
`dialogue_manager/runtime/balloon_path`, so `show_dialogue_balloon()` uses it
everywhere. Its script is a **copy** of the addon's example balloon rather than
a subclass, so an addon update cannot silently restyle the game; the flow
control is theirs, the presentation is ours.

#### The frame
The panel's border is an **embossed 9-patch**, `sprites/ui/dialogue_frame.png`
(16x16), applied as a `StyleBoxTexture` with **5 px slice margins**.

A `StyleBoxFlat` cannot do this: it has a single `border_color`, so every edge
is the same shade and the frame reads as a drawn-on hairline. An embossed frame
needs the top and left lit and the bottom and right shaded — per-pixel control,
which means a texture.

**Getting the slice margin right matters more than it looks.** It must be at
least large enough to contain the corner artwork; set it smaller and the corner
rounding falls into the stretchable edge strip and smears along the whole edge.
To find it, take the smallest `m` for which rows `m..h-m` are identical to each
other and columns `m..w-m` likewise — that is the point past which the artwork
stops varying along its length. For the current frame that is 5, while its
visible border is only 4 px thick.

`axis_stretch_horizontal/vertical = 1` (tile, not stretch) keeps the bands crisp
at any panel size. Content margins (10/8) are measured in from the panel edge,
so they include the border thickness.

If you redraw the frame, re-run that uniformity check rather than assuming the
margin still fits.

#### Everything else
- **8 px font**, imported with `antialiasing=0`, `hinting=0`,
  `subpixel_positioning=0`. Without those three the text is greyscale-blended
  and looks wrong next to the sprites.
- **Opaque fill.** Translucency lets the busy room show through and makes the
  text harder to read.

> The copied example balloon injects a "This is an example balloon" banner in
> `_ready()`. It is removed in our copy; if you ever re-copy it, delete that
> block again.

**The balloon scene must connect two signals**, which the addon's example scene
carries and a hand-built one will not:

```
[connection signal="gui_input" from="Balloon" to="." method="_on_balloon_gui_input"]
[connection signal="response_selected" from="Balloon/CenterContainer/ResponsesMenu" to="." method="_on_responses_menu_response_selected"]
```

Both advancing *and* choosing a response live inside those handlers, so without
the first connection a conversation opens and can never be advanced — by mouse
or keyboard — and without the second, responses do nothing.

A conversation ends when its flow reaches `=> END` or the end of the file; there
is no bail-out key. `ui_cancel` only skips the typing animation.

Typing speed is `seconds_per_step` on the balloon's `DialogueLabel`, currently
**0.04** (25 characters/second, so a 48-character line takes ~1.9 s). The addon
default of 0.02 reads as a blur at this text size. Individual lines can override
it inline with `[speed=N]`, and `[wait=N]` pauses mid-line.

### Writing dialogue
`~ cue` marks an entry point, `Name: line` is a spoken line, `- option` is a
response, `=> cue` jumps and `=> END` finishes. `[[a|b|c]]` picks one at random.

---

## Isometric Depth Sorting (iso_sorter addon)

Every visible sprite has a child `IsoSorter` node. The singleton `IsoSortingManager` (autoload) resolves z-order each frame via topological sort.

### Sort types
| Mode | Use for | Config |
|------|---------|--------|
| `POINT` | Chairs, point objects | Single `sort_offset_1` Vector2 |
| `LINE` | Walls, rails, long objects | `sort_offsets` Array[Vector2] (minimum 2 points) |

### Sprite categories
- **`render_below_all = true`** → floor/ground layer (z = −1000…)
- **`is_movable = false`** → static; sorted once on scene load
- **`is_movable = true`** → player and future moving objects; re-sorted every frame

### Sort bounds (why things sometimes draw in the wrong order)
Two sorters are only compared when their `get_bounds()` rects overlap — the
comparison is skipped otherwise as an optimisation. **If the bounds are wrong,
the sort silently falls back to registration order**, which looks like a sprite
stubbornly drawing on top of something it is standing behind.

`get_bounds()` uses the sprite's frame when it can find one. It looks at the
sorter's parent *and* the parent's children, because characters hang the sorter
off a `CharacterBody2D` with the `Sprite2D` beside it rather than under it.
Without that second lookup it falls back to a fixed 48x48 box around the sort
point: the Doctor and Sarah are 96 px tall, so they sorted correctly only when
within ~48 px of each other and Sarah drew over him at every normal following
distance.

It also divides the texture by `hframes`/`vframes` — a spritesheet's texture is
the whole strip, so a 45-frame sheet would otherwise report bounds 4320 px wide.

### Adding a new sprite to the scene
1. Add the `Sprite2D` (or `StaticBody2D` with sprite child).
2. Add an `IsoSorter` child node.
3. Choose `POINT` or `LINE` mode.
4. Drag the green handles in the editor to set sort point(s) at the sprite's "ground contact" position in isometric space.
5. Mark `is_movable = true` only if the object moves at runtime.

---

## Animation System

### Structure
```
AnimationPlayer          ← stores all animation frames
AnimationTree
  └── StateMachine
        ├── Idle  ← BlendSpace2D (player_idle_blend.tres)
        └── Run   ← BlendSpace2D (player_walk_blend.tres)
```

### Blend space layout (same for idle and walk)
| Blend point | Animation |
|-------------|-----------|
| (0, 1)      | north     |
| (1, 0)      | east      |
| (0, −1)     | south     |
| (0.7, 0.7)  | northeast |
| (0.7, −0.7) | southeast |

Blend mode is **Discrete** — it snaps to the nearest animation rather than interpolating between frames.

### Spritesheet (`tombaker3.png`)
45 frames of 96×96 in a single row, `hframes = 45`:

| Frames | Animation |
|--------|-----------|
| 0–4 | idle s, se, e, ne, n |
| 5–12 | walk s |
| 13–20 | walk se |
| 21–28 | walk e |
| 29–36 | walk ne |
| 37–44 | walk n |

Walk cycles are 8 frames held for 0.075 s each — a 0.6 s stride. To retime the
walk, change `length` and respace `times` on the five `walk *` animations
together; they must always match or the cycle will stutter at the loop point.
At 100 px/s movement this covers 60 px per cycle, so if the feet visibly slip,
retime here rather than changing `speed`.

West and southwest directions are mirrored from east/southeast using `flip_h`.
The figure's feet sit 33 px below the frame centre, same as the old 86×86 sheet,
so `TomBaker.offset = Vector2(0, -26)` still plants him on the floor correctly.

---

## Audio System

| Node | File | Notes |
|------|------|-------|
| `TARDISAmbient` (AudioStreamPlayer) | `audio/console/console-ambient.mp3` | Autoplay, −19.5 dB background loop |
| `ConsoleSounds` (AudioStreamPlayer2D) | `audio/console/console1-9.mp3` | Random pick every 5–20 s via Timer |

`console_sounds.gd` creates its own `Timer` child in `_ready()` — do not add a Timer node manually in the scene. The gap between noises is `min_interval`/`max_interval` on that node (20–55 s).

Footstep volume is `footsteps_volume_db` on the player (−30 dB); the player builds its own `AudioStreamPlayer` in `_ready()`, so there is no node to select in the scene.

`audio/characters/footsteps.mp3` exists but is **not yet wired up**.

---

## Known Issues / Technical Debt

| Issue | Location | Detail |
|-------|----------|--------|
| `ambient_music.gd` broken | Root scene | Wrong path `res://console-ambient.mp3`; TARDISAmbient already handles this — safe to delete the script |
| Footsteps not implemented | `player.gd` | `audio/characters/footsteps.mp3` exists, not played |
| `boundary-s2.png` unused | `sprites/secondaryconsole/` | Asset present, not referenced in scene |
| ATTACK / DEAD states stub | `player.gd` | State enum entries exist but no logic yet |
| Old manual animation code | `player.gd` | `update_animation()` and `animation_playback` references are commented out — can be deleted |

---

## Project Conventions

- **No `cd` before git commands** — git operates on the working tree automatically.
- **Pixel art:** Always set `texture_filter = 1` (nearest-neighbour) on new sprites.
- **Isometric Y-axis:** Screen Y increases downward; blend space Y is inverted (negate velocity/direction Y before setting blend position).
- **Blend position X:** Always `abs(x)` — left movement is handled by `flip_h`, not separate animations.
- **`last_facing` pattern:** Use a cached direction variable that only updates when input is non-zero, so the animation holds its last direction at rest or when blocked.
- **IsoSorter on everything:** Any new visible sprite in the scene needs an IsoSorter child or it will render at a fixed z and likely clip through other objects.
- **Input actions:** Use the named actions (`"left"`, `"right"`, `"up"`, `"down"`) — do not read raw keys.
- **One player, instanced:** Never copy the Player subtree into a room. Instance `player.tscn` and set its `position`.
- **New characters extend `Character`:** override `_decide_direction()`; never reimplement facing or animation.
- **Scale:** ~39 px per metre (a character is ~71 px tall ≈ 1.8 m). Use it when a distance is specified in metres.
- **Re-saving a scene from a script drops its `uid`:** `ResourceSaver.save(PackedScene, ...)` writes `[gd_scene format=3]` with no UID, which breaks `run/main_scene` and any `target_scene` referring to it. Put the UID back in the header afterwards.
- **Integer scaling:** `window/stretch/scale_mode="integer"` keeps pixels square when maximised. Switching it to `"fractional"` fills the screen but makes pixel sizes uneven.
