extends Node2D

## A tile level whose depth comes from the IsoSorter, not from Y-sorting.
##
## Y-sort judges a sprite by a single point, which a long wall does not have —
## its depth is the LINE of its foot, and a character standing near one end of
## a panel sorts wrong against a point taken from the middle. The wall panels
## therefore carry `IsoSorter` in LINE mode, and once anything in the scene
## uses it everything that interleaves with it has to, since IsoSorter writes
## `z_index` every frame and that overrides Y-sort entirely.
##
## The floor, decals and kerbs are exempt: they are TileMapLayers pinned below
## everything that walks (z −100/−99/−50), so they never enter the sort.
##
## The characters' sorters must be switched on explicitly. `IsoSorter` reads
## `enabled` in its own `_ready`, which runs before this one, and a property
## override set while building the scene is not serialised onto a node inside
## an instanced scene — so the flag cannot simply be authored into the .tscn.

func _ready() -> void:
	_set_iso_sorters(self, true)


func _set_iso_sorters(node: Node, on: bool) -> void:
	for child in node.get_children():
		if child is IsoSorter:
			(child as IsoSorter).enabled = on
		else:
			_set_iso_sorters(child, on)
