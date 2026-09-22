@tool
extends Node2D

## Night over the street.
##
## Two halves, and they do different jobs:
##
##   `Tint`   a CanvasModulate, which MULTIPLIES the whole canvas. That is what
##            makes it night - everything goes dark and slightly blue at once,
##            including art that has not been thought about yet.
##   lights   PointLight2D children, which ADD back. Multiply alone gives a
##            flat blue picture; it only reads as night once something warm is
##            punched through it.
##
## A CanvasModulate only touches its own canvas, so the dialogue balloon
## (CanvasLayer 100) and the fade (layer 128) stay at full brightness - which
## is what you want, and is why the tint is not applied as a full-screen rect.
##
## `night` drives both, so there is one number to animate and the lamps cannot
## be left burning in daylight.

## 0 is full day, 1 is full night.
@export_range(0.0, 1.0, 0.01) var night: float = 1.0:
	set(value):
		night = clampf(value, 0.0, 1.0)
		_apply()

## The canvas tint at either end. Night is a desaturated blue rather than a
## dark grey: a flat brightness drop reads as "the monitor is turned down",
## while a hue shift reads as moonlight.
@export var day_tint: Color = Color(1.0, 1.0, 1.0):
	set(value):
		day_tint = value
		_apply()
@export var night_tint: Color = Color(0.46, 0.53, 0.82):
	set(value):
		night_tint = value
		_apply()

## Seconds for a whole day -> night -> day. 0 holds still at `night`, which is
## the default: a cycle running under a conversation is a distraction.
@export var cycle_seconds: float = 0.0

var _tint: CanvasModulate
var _lights: Array[Light2D] = []
var _phase: float = 0.0


func _ready() -> void:
	_collect()
	_apply()
	set_process(cycle_seconds > 0.0 and not Engine.is_editor_hint())
	# start the cycle wherever `night` already is, so turning it on does not
	# jump the sky
	_phase = acos(clampf(1.0 - 2.0 * night, -1.0, 1.0)) / TAU


func _collect() -> void:
	_tint = get_node_or_null("Tint") as CanvasModulate
	_lights.clear()
	for child in get_children():
		if child is Light2D:
			_lights.append(child)


## The energy a light was BUILT with, kept in metadata rather than read off the
## node. `_apply` writes `energy`, so reading it back would ratchet the lamps
## down to nothing over a few calls - and metadata is serialised into the
## scene, so it survives a save from the editor.
func _authored(light: Light2D) -> float:
	if not light.has_meta("night_energy"):
		light.set_meta("night_energy", light.energy)
	return float(light.get_meta("night_energy"))


func _apply() -> void:
	if _tint == null:
		# exported setters fire during load, before _ready has found anything
		if not is_node_ready():
			return
		_collect()
		if _tint == null:
			return
	_tint.color = day_tint.lerp(night_tint, night)
	for light in _lights:
		light.energy = _authored(light) * night
		light.visible = night > 0.01      # a lamp lit at noon looks like a bug


func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta / cycle_seconds, 1.0)
	# cosine rather than a triangle: dusk and dawn should take their time and
	# midnight should sit still for a while
	night = 0.5 - 0.5 * cos(_phase * TAU)
