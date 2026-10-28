## Cutout (puppet) rig: draws a fighter from painted body parts in fighters/<id>/art/
## (built by tools/art/build_fighter.py) on the same skeleton and poses as the gray-box rig,
## so every move's wind-up / strike / recovery timing comes straight from the frame data.
## Presentation only: reads fighter state, never changes it.
extends RefCounted

const BoxRig := preload("res://fighters/_graybox/box_rig.gd")
const Art := preload("res://fighters/_cutout/art.gd")

const BACK_TINT := Color(0.72, 0.72, 0.78)

static var _cache := {}

var parts := {}          # name -> {tex, pivot: Vector2, axis: float (radians)}
var lengths := {}
var anchors := {}
var draw_scale := 0.5
var sole := 20.0


## The cutout rig for a fighter, or null if it has no built art (then the gray-box rig is used).
static func for_fighter(data) -> Variant:
	if _cache.has(data.id):
		return _cache[data.id]
	var rig = null
	var path := "res://fighters/%s/art/rig.json" % data.id
	if data.rig == "cutout" and FileAccess.file_exists(path):
		rig = load("res://fighters/_cutout/cutout_rig.gd").new()
		if not rig._load(path):
			rig = null
	_cache[data.id] = rig
	return rig


func _load(path: String) -> bool:
	var cfg = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not cfg is Dictionary:
		push_error("bad rig file %s" % path)
		return false
	var dir := path.get_base_dir()
	draw_scale = cfg.draw_scale
	sole = cfg.sole
	for k in cfg.lengths:
		lengths[k] = float(cfg.lengths[k])
	for k in cfg.anchors:
		anchors[k] = Vector2(cfg.anchors[k][0], cfg.anchors[k][1])
	for name in cfg.parts:
		var p: Dictionary = cfg.parts[name]
		var tex := Art.texture(dir.path_join(p.texture))
		if tex == null:
			return false
		var pivot := Vector2(p.pivot[0], p.pivot[1])
		var tip := Vector2(p.tip[0], p.tip[1])
		parts[name] = {"tex": tex, "pivot": pivot, "axis": (tip - pivot).angle()}
	return true


static func _dir(deg: float) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(sin(r), cos(r))   # 0 = straight down, positive = forward (local frame faces right)


## Draws the fighter with its feet at `feet` (screen px).
func draw(ci: CanvasItem, f, feet: Vector2, tint := Color.WHITE) -> void:
	var p := BoxRig.pose(f)
	var spin: float = p.get("spin", 0.0)
	var lean: float = p.lean + spin
	# Local frame: facing right, y down, origin at the feet; mirrored for facing left.
	var base := Transform2D(Vector2(f.facing, 0), Vector2(0, 1), feet)
	var legs: float = lengths.leg_upper_F + lengths.leg_lower_F + sole
	var hip_center := Vector2(0, -(legs - p.get("drop", 0.0)))
	var pelvis_rot := deg_to_rad(spin + p.lean * 0.3)
	var waist := hip_center - Vector2(0, anchors.hip_F.y).rotated(pelvis_rot)
	var torso_rot := deg_to_rad(lean)
	var torso_dir := Vector2(0, -1).rotated(torso_rot)
	var neck: Vector2 = waist + torso_dir * lengths.torso
	var hip_f: Vector2 = waist + anchors.hip_F.rotated(pelvis_rot)
	var hip_b: Vector2 = waist + anchors.hip_B.rotated(pelvis_rot)
	var sh_f: Vector2 = waist + anchors.shoulder_F.rotated(torso_rot)
	var sh_b: Vector2 = waist + anchors.shoulder_B.rotated(torso_rot)

	var back := tint * BACK_TINT
	# Back arm and leg first (behind the body), then body, then the front limbs.
	var b_elbow := _limb(ci, base, "arm_upper_B", sh_b, p.bu + spin, back, false)
	var b_wrist := _limb(ci, base, "arm_lower_B", b_elbow, p.bl + spin, back)
	_part(ci, base, "hand_B", b_wrist, _dir(p.bl + spin), back)
	_limb(ci, base, "arm_upper_B", sh_b, p.bu + spin, back)
	var b_knee := _limb(ci, base, "leg_upper_B", hip_b, p.bt + spin, back, false)
	_limb(ci, base, "leg_lower_B", b_knee, p.bs + spin, back)
	_limb(ci, base, "leg_upper_B", hip_b, p.bt + spin, back)
	_part(ci, base, "pelvis", waist, Vector2(0, -1).rotated(pelvis_rot), tint)
	var f_knee := _limb(ci, base, "leg_upper_F", hip_f, p.ft + spin, tint, false)
	_limb(ci, base, "leg_lower_F", f_knee, p.fs + spin, tint)
	_limb(ci, base, "leg_upper_F", hip_f, p.ft + spin, tint)
	_part(ci, base, "torso", waist, torso_dir, tint)
	_part(ci, base, "head", neck, torso_dir.rotated(deg_to_rad(p.lean * 0.4)), tint)
	var f_elbow := _limb(ci, base, "arm_upper_F", sh_f, p.fu + spin, tint, false)
	var fist := _limb(ci, base, "arm_lower_F", f_elbow, p.fl + spin, tint, false)
	if parts.has("tool"):
		_part(ci, base, "tool", fist, _dir(p.fl + spin + p.get("to", 100.0)), tint)
	_limb(ci, base, "arm_lower_F", f_elbow, p.fl + spin, tint)
	_limb(ci, base, "arm_upper_F", sh_f, p.fu + spin, tint)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Joint at the end of a bone; draws the bone's part unless `draw` is false (used to compute joints first).
func _limb(ci: CanvasItem, base: Transform2D, name: String, from: Vector2, deg: float, tint: Color, draw := true) -> Vector2:
	var d := _dir(deg)
	if draw:
		_part(ci, base, name, from, d, tint)
	return from + d * lengths[name]


func _part(ci: CanvasItem, base: Transform2D, name: String, at: Vector2, dir: Vector2, tint: Color) -> void:
	if not parts.has(name):
		return
	var part: Dictionary = parts[name]
	var xf := base * Transform2D(dir.angle() - part.axis, at) \
			* Transform2D(0, Vector2(draw_scale, draw_scale), 0, Vector2.ZERO) * Transform2D(0, -part.pivot)
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture(part.tex, Vector2.ZERO, tint)
