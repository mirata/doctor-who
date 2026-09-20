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
| `nerva.tscn` | Second room, reached through the DoorTrigger |
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
