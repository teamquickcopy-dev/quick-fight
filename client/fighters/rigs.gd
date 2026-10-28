## Picks how a fighter is drawn: its cutout rig (painted parts) when it has built art,
## otherwise the gray-box rig in its placeholder colour.
extends RefCounted

const BoxRig := preload("res://fighters/_graybox/box_rig.gd")
const CutoutRig := preload("res://fighters/_cutout/cutout_rig.gd")


## `color` is the gray-box colour; `tint` multiplies cutout art (e.g. recolours P2 in a mirror match).
static func draw(ci: CanvasItem, f, feet: Vector2, color: Color, tint := Color.WHITE) -> void:
	var rig = CutoutRig.for_fighter(f.data)
	if rig != null:
		rig.draw(ci, f, feet, tint)
	else:
		BoxRig.draw(ci, f, feet, color)
