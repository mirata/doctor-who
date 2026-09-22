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

@export_category("Light pools")
## How many flat rings a pool falls off in. Everything else on screen is a
## handful of flat tones, so a smoothly fading light reads as modern lighting
## laid over pixel art. 6 is a bullseye, 16 is nearly smooth.
@export_range(2, 32) var bands: int = 10:
	set(value):
		bands = maxi(2, value)
		_build_textures()
## How fast the rings darken outwards. 1 is linear, which gives a flat disc
## with a hard rim; 2 is roughly inverse-square.
@export_range(0.5, 4.0, 0.1) var falloff: float = 2.0:
	set(value):
		falloff = value
		_build_textures()
## How far the band edges are broken up by ordered dithering, in bands.
## 0 is hard rings; 1 scatters a whole band's width, which is the classic
## look; past about 1.5 the rings stop reading as rings at all.
@export_range(0.0, 2.0, 0.05) var dither: float = 0.4:
	set(value):
		dither = value
		_build_textures()

## Which ordered matrix the dithering uses. A plain threshold turns a ramp into
## hard rings; varying the threshold in a fixed small pattern trades that hard
## edge for a checker that averages to the same brightness - which is how this
## was done when there were not enough colours to do anything else.
##
## The two read quite differently, and it is a look rather than a quality
## setting: **4x4** gives 16 threshold levels over a 4 px tile, so the stipple
## is fine and the transition between rings is gradual - a VGA sort of look.
## **2x2** has only 4 levels over a 2 px tile, so the dots are coarse, obvious
## and regular, and each ring keeps a harder edge with a chunky checker on it -
## closer to an Amiga or EGA look.
##
## Coarser is not worse here. At a 640x320 viewport scaled 4x, a 2x2 dot is a
## visible 8 px block on screen, which is the kind of thing this art is made
## of anyway.
enum DitherPattern {
	BAYER_4X4,  ## fine stipple, gradual - the default
	BAYER_2X2,  ## coarse, chunky, more obviously dithered
}

@export var dither_pattern: DitherPattern = DitherPattern.BAYER_4X4:
	set(value):
		dither_pattern = value
		_build_textures()

const BAYER_4 := [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]
const BAYER_2 := [
	[0, 2],
	[3, 1],
]


## The matrix in use. Both are square and hold every value from 0 to n*n-1
## exactly once, which is what makes the stipple average out to the value it
## replaced rather than biasing it lighter or darker.
func _dither_matrix() -> Array:
	return BAYER_2 if dither_pattern == DitherPattern.BAYER_2X2 else BAYER_4

var _tint: CanvasModulate
var _lights: Array[Light2D] = []
var _phase: float = 0.0


func _ready() -> void:
	_collect()
	_build_textures()
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


## One texture per light, generated rather than a GradientTexture2D, because
## dithering needs per-pixel control and a gradient resource cannot give it.
##
## Built at RUNTIME, not at build time, for two reasons: an ImageTexture
## serialises into the scene as its raw pixels (~180 KB a light), and doing it
## here makes `bands`, `falloff` and `dither` live knobs in the inspector
## instead of a rebuild each time.
func _build_textures() -> void:
	if _lights.is_empty():
		if not is_node_ready():
			return
		_collect()
	for light in _lights:
		var radius: float = float(light.get_meta("radius", 96.0))
		light.texture = _pool_texture(radius)
		light.texture_scale = 1.0


## A banded, dithered pool of light. White, so the light's own `color` picks
## the hue.
##
## The texture is `2r x r` and the node is NOT scaled: a pool lying on the
## floor is an ellipse, and getting that from the texture's own proportions
## rather than from `scale = (1, 0.5)` avoids resampling - and resampling a
## dither pattern is exactly how you lose it.
func _pool_texture(radius: float) -> ImageTexture:
	var w: int = maxi(2, int(round(radius * 2.0)))
	var h: int = maxi(2, int(round(radius)))
	var data := PackedByteArray()
	data.resize(w * h * 2)                  # FORMAT_LA8: luminance + alpha
	var cx: float = w * 0.5
	var cy: float = h * 0.5
	var last: float = float(bands - 1)
	# hoisted: this is per-texture, not per-pixel
	var matrix: Array = _dither_matrix()
	var n: int = matrix.size()
	var spread: float = float(n * n)
	for y in h:
		for x in w:
			# normalised distance in ellipse space, so the rings are circles
			# on the ground rather than on the screen
			var dx: float = (float(x) + 0.5 - cx) / cx
			var dy: float = (float(y) + 0.5 - cy) / cy
			var t: float = sqrt(dx * dx + dy * dy)
			var a: float = 0.0
			if t < 1.0:
				# quantise the RADIUS, not the brightness, so the rings stay
				# evenly spaced and only their values follow the falloff
				var threshold: float = (float(matrix[y % n][x % n]) + 0.5) / spread - 0.5
				var level: float = t * float(bands) + threshold * dither
				var band: int = clampi(int(floor(level)), 0, bands - 1)
				a = pow(1.0 - float(band) / last, falloff)
			var i: int = (y * w + x) * 2
			data[i] = 255
			data[i + 1] = int(round(clampf(a, 0.0, 1.0) * 255.0))
	return ImageTexture.create_from_image(
		Image.create_from_data(w, h, false, Image.FORMAT_LA8, data))


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
