## Cutout (puppet) rig: draws a fighter from painted body parts in fighters/<id>/art/
## (built by tools/art/build_fighter.py) on the same skeleton and poses as the gray-box rig,
## so every move's wind-up / strike / recovery timing comes straight from the frame data.
## On top of the pose angles it applies simple body mechanics:
##  - feet near the floor are planted flat (2-bone IK bends the knee to reach them), so they
##    never slide, sink or tilt; kicks and jumps keep the posed leg swing
##  - with "grip" the back hand holds the tool below the front hand (IK for the back arm),
##    two-handed as in the character art; its forearm then crosses in front of the body
##  - knees bend forward, elbows bend down
## Presentation only: reads fighter state, never changes it.
extends RefCounted

const BoxRig := preload("res://fighters/_graybox/box_rig.gd")
const Art := preload("res://fighters/_cutout/art.gd")

const BACK_TINT := Color(0.72, 0.72, 0.78)
const PLANT_RANGE := 26.0     # a posed ankle this close to its floor height gets planted
const GRIP_GAP := 22.0        # back hand sits this far up the tool handle from the front fist

static var _cache := {}

var parts := {}          # name -> {tex, pivot: Vector2, axis: float (radians)}
var lengths := {}
var anchors := {}
var draw_scale := 0.5
var ankle_h := 20.0          # ankle height above the floor (screen px)


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
	ankle_h = cfg.ankle_h
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


## Two-bone IK: the middle joint for a chain from `a` reaching toward `t`.
## `forward_knee` picks the solution bending forward (knees); otherwise the lower one (elbows).
static func _ik(a: Vector2, t: Vector2, l1: float, l2: float, forward_knee: bool) -> Vector2:
	var d := t - a
	var dist := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var off := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
	var j1 := a + Vector2.from_angle(d.angle() + off) * l1
	var j2 := a + Vector2.from_angle(d.angle() - off) * l1
	if forward_knee:
		return j1 if j1.x > j2.x else j2
	return j1 if j1.y > j2.y else j2


## Draws the fighter with its feet at `feet` (screen px).
func draw(ci: CanvasItem, f, feet: Vector2, tint := Color.WHITE) -> void:
	var p := BoxRig.pose(f)
	var spin: float = p.get("spin", 0.0)
	var lean: float = p.lean + spin
	# Local frame: facing right, y down, origin at the feet; mirrored for facing left.
	var base := Transform2D(Vector2(f.facing, 0), Vector2(0, 1), feet)
	var lt: float = lengths.leg_upper_F
	var ls: float = lengths.leg_lower_F
	var hip_center := Vector2(0, -(lt + ls + ankle_h - p.get("drop", 0.0)))
	var pelvis_rot := deg_to_rad(spin + p.lean * 0.3)
	var waist := hip_center - Vector2(0, anchors.hip_F.y).rotated(pelvis_rot)
	var torso_rot := deg_to_rad(lean)
	var torso_dir := Vector2(0, -1).rotated(torso_rot)
	var neck: Vector2 = waist + torso_dir * lengths.torso
	var hip_f: Vector2 = waist + anchors.hip_F.rotated(pelvis_rot)
	var hip_b: Vector2 = waist + anchors.hip_B.rotated(pelvis_rot)
	var sh_f: Vector2 = waist + anchors.shoulder_F.rotated(torso_rot)
	var sh_b: Vector2 = waist + anchors.shoulder_B.rotated(torso_rot)
	# Only plant feet when standing on the floor upright (not airborne, lying or spinning).
	var can_plant: bool = f.airborne == 0 and absf(spin) < 30.0
	var leg_f := _leg(hip_f, p.ft + spin, p.fs + spin, lt, ls, can_plant)
	var leg_b := _leg(hip_b, p.bt + spin, p.bs + spin, lengths.leg_upper_B, lengths.leg_lower_B, can_plant)

	# Front arm (forward kinematics) and the tool in its fist.
	var f_elbow: Vector2 = sh_f + _dir(p.fu + spin) * lengths.arm_upper_F
	var fist: Vector2 = f_elbow + _dir(p.fl + spin) * lengths.arm_lower_F
	var tool_dir := _dir(p.fl + spin + p.get("to", 100.0))
	# Back arm: reach for the handle when gripping, otherwise posed.
	var gripping: bool = parts.has("tool") and p.get("grip", 0.0) >= 0.5
	var b_elbow: Vector2
	var b_wrist: Vector2
	if gripping:
		var target := fist + tool_dir * GRIP_GAP
		b_elbow = _ik(sh_b, target, lengths.arm_upper_B, lengths.arm_lower_B, false)
		b_wrist = b_elbow + (target - b_elbow).normalized() * lengths.arm_lower_B
	else:
		b_elbow = sh_b + _dir(p.bu + spin) * lengths.arm_upper_B
		b_wrist = b_elbow + _dir(p.bl + spin) * lengths.arm_lower_B
	var b_fore := (b_wrist - b_elbow).normalized()

	var back := tint * BACK_TINT
	# Behind the body: back upper arm (and the whole back arm when it isn't gripping), back leg.
	if not gripping:
		_part(ci, base, "arm_lower_B", b_elbow, b_fore, back)
		_part(ci, base, "hand_B", b_wrist, b_fore, back)
	_part(ci, base, "arm_upper_B", sh_b, (b_elbow - sh_b).normalized(), back)
	_draw_leg(ci, base, "B", hip_b, leg_b, back)
	_part(ci, base, "pelvis", waist, Vector2(0, -1).rotated(pelvis_rot), tint)
	_draw_leg(ci, base, "F", hip_f, leg_f, tint)
	_part(ci, base, "torso", waist, torso_dir, tint)
	if gripping:
		# The back forearm crosses in front of the chest (behind the head) to hold the handle.
		_part(ci, base, "arm_lower_B", b_elbow, b_fore, tint * Color(0.9, 0.9, 0.93))
	_part(ci, base, "head", neck, torso_dir.rotated(deg_to_rad(p.lean * 0.4)), tint)
	if parts.has("tool"):
		_part(ci, base, "tool", fist, tool_dir, tint)
	if gripping:
		_part(ci, base, "hand_B", b_wrist, b_fore, tint * Color(0.9, 0.9, 0.93))   # wraps over the handle
	_part(ci, base, "arm_lower_F", f_elbow, (fist - f_elbow).normalized(), tint)
	_part(ci, base, "arm_upper_F", sh_f, (f_elbow - sh_f).normalized(), tint)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Knee and ankle for a leg: posed angles, then planted flat on the floor if the ankle is near it.
## Returns [knee, ankle, planted].
func _leg(hip: Vector2, thigh_deg: float, shin_deg: float, lt: float, ls: float, can_plant: bool) -> Array:
	var knee := hip + _dir(thigh_deg) * lt
	var ankle := knee + _dir(shin_deg) * ls
	var floor_y := -ankle_h
	if can_plant and ankle.y > floor_y - PLANT_RANGE:
		var target := Vector2(ankle.x, floor_y)
		knee = _ik(hip, target, lt, ls, true)
		ankle = knee + (target - knee).normalized() * ls
		return [knee, ankle, true]
	return [knee, ankle, false]


## Boot first (the trouser cuff overlaps its top), then shin, then thigh.
func _draw_leg(ci: CanvasItem, base: Transform2D, side: String, hip: Vector2, leg: Array, tint: Color) -> void:
	var knee: Vector2 = leg[0]
	var ankle: Vector2 = leg[1]
	var shin_dir := (ankle - knee).normalized()
	# A planted boot stays flat; a lifted one points its toe along the swing.
	var foot_dir := Vector2.RIGHT if leg[2] else shin_dir.rotated(-PI / 2.0)
	_part(ci, base, "foot_" + side, ankle, foot_dir, tint)
	_part(ci, base, "leg_lower_" + side, knee, shin_dir, tint)
	_part(ci, base, "leg_upper_" + side, hip, (knee - hip).normalized(), tint)


func _part(ci: CanvasItem, base: Transform2D, name: String, at: Vector2, dir: Vector2, tint: Color) -> void:
	if not parts.has(name):
		return
	var part: Dictionary = parts[name]
	var xf := base * Transform2D(dir.angle() - part.axis, at) \
			* Transform2D(0, Vector2(draw_scale, draw_scale), 0, Vector2.ZERO) * Transform2D(0, -part.pivot)
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture(part.tex, Vector2.ZERO, tint)
