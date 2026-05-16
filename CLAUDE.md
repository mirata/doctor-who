# Doctor Who — CLAUDE.md

## Project Overview

A Doctor Who themed isometric adventure game built in Godot 4.6. The current scene is a TARDIS secondary console room. The player controls Tom Baker's Doctor with 8-directional movement, isometric depth sorting, and ambient audio.

**Engine:** Godot 4.6.2 stable  
**Main Scene:** `secondaryconsole.tscn`  
**Viewport:** 640×320 internal, rendered at 1280×720 (2× pixel-perfect upscale)  
**Texture filter:** Nearest-neighbour everywhere (pixel art)

---

## Controls

| Action | Key |
|--------|-----|
| Move left | A |
| Move right | D |
| Move up | W |
| Move down | S |

---

## Key Files

| File | Purpose |
|------|---------|
| `secondaryconsole.tscn` | Root scene — room layout, player, audio |
| `player.gd` | Player movement, state machine, animation control |
| `console_sounds.gd` | Randomised ambient console beeps every 5–20 s |
| `fade_in.gd` | Black-screen fade-in on scene start (2.5 s tween) |
| `ambient_music.gd` | **BROKEN** — wrong path, redundant with TARDISAmbient node; ignore or delete |
| `animations/player_idle_blend.tres` | 2D blend space for idle (5 directions) |
| `animations/player_walk_blend.tres` | 2D blend space for walking (5 directions) |
| `addons/iso_sorter/` | Custom isometric depth sorting addon |

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
`TomBaker.flip_h` is set only when `velocity.x != 0`, preserving the last horizontal facing during idle. The spritesheet only contains right-facing frames; left movement is handled by flipping.

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

### Spritesheet (`tombaker2.png`)
25 frames in a single row. Covers 5 directions × 5 stances. West and southwest directions are mirrored from east/southeast using `flip_h`.

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
