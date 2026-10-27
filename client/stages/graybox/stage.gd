## Gray-box stage: the 4 scrolling layers from the design doc (back wall, midground, fight floor,
## foreground props) as flat shapes, with one moving element and floor marks every 100 px
## so spacing can be judged. Real stages (print_floor, design_studio) replace this later.
extends RefCounted

const R := preload("res://engine/rules.gd")

const NAME := "Gray Box"
const GROUND_Y := 640.0
const WIDTH := R.STAGE_WIDTH / R.FP

const WALL := Color("#2a2d36")
const WALL_LINE := Color("#343845")
const MID := Color("#3a3f4c")
const FLOOR := Color("#4a4f5c")
const FLOOR_LINE := Color("#5b6170")
const FRONT := Color("#1d1f26")


## `cam_x` = left edge of the screen in stage px; `shake` = screen offset.
func draw(ci: CanvasItem, cam_x: float, frame: int, shake: Vector2) -> void:
	var w := ci.get_viewport_rect().size.x
	# Layer 1: back wall (slowest parallax).
	ci.draw_rect(Rect2(Vector2.ZERO, Vector2(w, GROUND_Y)), WALL)
	var p1 := cam_x * 0.3
	var x := -fmod(p1, 160.0)
	while x < w:
		ci.draw_line(Vector2(x, 0) + shake, Vector2(x, GROUND_Y) + shake, WALL_LINE, 2.0)
		x += 160.0
	# Layer 2: midground machines; one sliding "printer head" is the moving element.
	var p2 := cam_x * 0.6
	for i in 7:
		var mx := i * 330.0 - p2 + shake.x
		ci.draw_rect(Rect2(mx, GROUND_Y - 230 + shake.y, 220, 230), MID)
		ci.draw_rect(Rect2(mx + 10, GROUND_Y - 220 + shake.y, 200, 14), MID.lightened(0.12))
		var head := 10.0 + (sin(frame * 0.03 + i) * 0.5 + 0.5) * 170.0
		ci.draw_rect(Rect2(mx + head, GROUND_Y - 226 + shake.y, 30, 22), Color("#6c7385"))
	# Layer 3: fight floor (moves 1:1 with the fighters).
	ci.draw_rect(Rect2(0, GROUND_Y + shake.y, w, 720 - GROUND_Y + 20), FLOOR)
	var start := floorf(cam_x / 100.0) * 100.0
	var mark := start
	while mark < cam_x + w + 100:
		var sx := mark - cam_x + shake.x
		var major := int(mark) % 500 == 0
		ci.draw_line(Vector2(sx, GROUND_Y + shake.y), Vector2(sx, GROUND_Y + (18 if major else 8) + shake.y), FLOOR_LINE, 2.0)
		mark += 100.0
	ci.draw_line(Vector2(0, GROUND_Y + shake.y), Vector2(w, GROUND_Y + shake.y), FLOOR_LINE.lightened(0.2), 3.0)
	# Stage walls.
	for edge in [R.STAGE_MARGIN / R.FP, WIDTH - R.STAGE_MARGIN / R.FP]:
		var ex: float = edge - cam_x + shake.x
		ci.draw_line(Vector2(ex, GROUND_Y - 300 + shake.y), Vector2(ex, GROUND_Y + shake.y), Color("#e05555"), 3.0)


## Layer 4: foreground props, drawn over the fighters (fastest parallax).
func draw_front(ci: CanvasItem, cam_x: float, shake: Vector2) -> void:
	var p4 := cam_x * 1.35
	for i in 5:
		var fx := i * 620.0 - p4 + 80.0 + shake.x
		ci.draw_rect(Rect2(fx, 690 + shake.y, 140, 40), FRONT)
