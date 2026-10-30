## Painted stage: one wide background painting (stages/painted/<name>.webp, 1920x720, made from
## art/source/stages/) that pans with the camera at a slower speed than the fighters, so the
## room feels deep. The painting includes the floor; the fighters stand at GROUND_Y on it.
## Same drawing interface as the gray-box stage. Falls back to it when the picture is missing.
extends RefCounted

const R := preload("res://engine/rules.gd")
const Art := preload("res://fighters/_cutout/art.gd")
const GrayBox := preload("res://stages/graybox/stage.gd")

const GROUND_Y := GrayBox.GROUND_Y
const WIDTH := R.STAGE_WIDTH / R.FP
const STAGES := {"print_floor": "The Print Floor", "design_studio": "The Design Studio"}

var name := ""
var tex: Texture2D
var _fallback := GrayBox.new()


## The stage for a match: picked from the two fighters, so both sides of an online match agree.
static func pick_id(p1_id: String, p2_id: String) -> String:
	return STAGES.keys()[(p1_id + "/" + p2_id).hash() % STAGES.size()]


func _init(id: String) -> void:
	name = STAGES.get(id, id)
	tex = Art.texture("res://stages/painted/%s.webp" % id)


## Layers 1-2: the painting, in screen space. `cam_x` = left edge of the view in stage px.
func draw_back(ci: CanvasItem, cam_x: float, frame: int, shake: Vector2) -> void:
	if tex == null:
		_fallback.draw_back(ci, cam_x, frame, shake)
		return
	var view := ci.get_viewport_rect().size
	var s := view.y / tex.get_height()
	var w := tex.get_width() * s
	# Pan across the painting as the camera moves from one stage edge to the other.
	var t := clampf(cam_x / maxf(1.0, WIDTH - view.x / 1.5), 0.0, 1.0)
	var x := -(w - view.x) * t
	# Slightly oversized so the screen shake never shows an edge.
	ci.draw_texture_rect(tex, Rect2(Vector2(x, 0) + shake * 0.5 - Vector2(8, 8), Vector2(w, view.y) + Vector2(16, 16)), false)


## Layer 3: the floor is part of the painting; only the gray-box stage draws one.
func draw_floor(ci: CanvasItem) -> void:
	if tex == null:
		_fallback.draw_floor(ci)


## Layer 4: no foreground props yet.
func draw_front(_ci: CanvasItem, _cam_x: float, _shake: Vector2) -> void:
	pass
