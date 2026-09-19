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
| `nerva.tscn` | Second room, reached through the DoorTrigger |
| `character.gd` | **`Character` base class** — movement, pathfinding, animation, idle/run state |
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
- **`agent_radius` must be >= the character collision radius (6).** Measured:
  at 3 and 4 the Doctor stalled on 2 of 6 destinations, at 5 on 1 of 6, at 6 and
  7 on none. Below the body radius, paths hug walls the body cannot fit through
  and he grinds to a halt against them.
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
  away.
- **After editing the outline, check for islands** — a walkable patch cut off
  from the rest strands whoever clicks on it. Path from the spawn to a grid of
  mesh points and confirm every one is reachable.

### Sarah's following

She routes to the Doctor through the navigation mesh whenever he gets too far
ahead, so she goes around the furniture and up the stairs rather than walking
into things.

| Export | Default | Meaning |
|--------|---------|---------|
| `follow_distance` | 90 px | She sets off past this |
| `close_enough` | 55 px | ...and stops inside this. The gap is what stops her twitching |
| `catch_up_speed` | 1.25 | Speed multiplier while closing; her trail is longer than the straight line |
| `repath_distance` | 20 px | How far he moves before she re-routes |

`follow_distance` is deliberately **below** 3 m. It's the distance she *reacts*
at, not the worst case — the gap keeps opening while she gets going. Measured
over a winding route the peak gap is 118 px (3.0 m) and the mean 66 px (1.7 m).
Retune by measuring the peak, not by setting this to 3 m. With pathfinding the
measured peak is 90 px (2.3 m) and the mean 56 px (1.4 m).

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

`console_sounds.gd` creates its own `Timer` child in `_ready()` — do not add a Timer node manually in the scene.

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
