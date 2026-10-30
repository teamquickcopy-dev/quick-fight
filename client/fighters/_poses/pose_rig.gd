## Pose-picture rig: draws a fighter as one finished picture per pose (fighters/<id>/art/pose_*.webp,
## cut from the pose sheets by tools/art/build_poses.py), the way hand-drawn fighting games do.
## poses.json "map" says which picture shows for each state and move; a move shows its wind-up
## pose during startup, its strike pose on the active frames (one per hit for multi-hit moves) and
## its recovery pose, all timed by the sim's frame data. Small touches sell the motion: breathing
## in the stance, a snap on the first strike frame, a shake when hit, a spin for rolls.
## Presentation only: reads fighter state, never changes it. Returns false from draw() when a
## picture is missing, so rigs.gd can fall back to the cutout rig.
extends RefCounted

const Fighter := preload("res://engine/fighter.gd")
const Art := preload("res://fighters/_cutout/art.gd")

const WALK_FRAMES := 9       # ticks per walk-cycle picture
const SNAP_FRAMES := 3       # first strike frames drawn stretched forward
const SHAKE_FRAMES := 8      # hit shake length
const RECOVER_HOLD := 0.5    # share of recovery that keeps the strike pose (no recover pose)

static var _cache := {}

var draw_scale := 0.8
var poses := {}      # name -> {tex, anchor: Vector2}
var map := {}


## The pose rig for a fighter, or null when it has no pose pictures.
static func for_fighter(data) -> Variant:
	if _cache.has(data.id):
		return _cache[data.id]
	var rig = null
	var path := "res://fighters/%s/art/poses.json" % data.id
	if FileAccess.file_exists(path):
		rig = load("res://fighters/_poses/pose_rig.gd").new()
		if not rig._load(path):
			rig = null
	_cache[data.id] = rig
	return rig


func _load(path: String) -> bool:
	var cfg = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not cfg is Dictionary:
		push_error("bad pose file %s" % path)
		return false
	draw_scale = cfg.draw_scale
	map = cfg.map
	var dir := path.get_base_dir()
	for name in cfg.poses:
		var p: Dictionary = cfg.poses[name]
		var tex := Art.texture(dir.path_join(p.texture))
		if tex == null:
			return false
		poses[name] = {"tex": tex, "anchor": Vector2(p.anchor[0], p.anchor[1])}
	return true


## Draws the fighter with its feet at `feet`. False if this state has no picture.
func draw(ci: CanvasItem, f, feet: Vector2, tint := Color.WHITE) -> bool:
	var look := pick(f)
	var name: String = look.get("pose", "")
	if not poses.has(name):
		return false
	var p: Dictionary = poses[name]
	var sx: float = look.get("sx", 1.0)
	var sy: float = look.get("sy", 1.0)
	var at: Vector2 = feet + Vector2(look.get("dx", 0.0) * f.facing, 0.0)
	var xf := Transform2D(0.0, Vector2(f.facing * draw_scale * sx, draw_scale * sy), 0.0, at)
	var spin: float = look.get("spin", 0.0)
	if spin != 0.0:
		# Rolls turn around the middle of the picture.
		var mid: Vector2 = p.tex.get_size() / 2.0 - p.anchor
		xf = xf * Transform2D(spin, mid) * Transform2D(0.0, -mid)
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture(p.tex, -p.anchor, tint)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


func _m(key: String, i := 0) -> String:
	var v = map.get(key, "")
	if v is Array:
		return v[posmod(i, v.size())] if not v.is_empty() else ""
	return v


## The picture for the fighter's current state: {pose, sx, sy, dx, spin}.
func pick(f) -> Dictionary:
	var sf: int = f.state_frame
	match f.state:
		Fighter.IDLE:
			return {"pose": _m("idle"), "sy": 1.0 + sin(sf * 0.08) * 0.012}
		Fighter.WALK_F:
			return {"pose": _m("walk", sf / WALK_FRAMES)}
		Fighter.WALK_B:
			return {"pose": _m("walk", -sf / WALK_FRAMES)}
		Fighter.CROUCH:
			return {"pose": _m("crouch")}
		Fighter.JUMP_SQUAT:
			return {"pose": _m("jump_squat"), "sy": 0.96}
		Fighter.LAND:
			return {"pose": _m("land")}
		Fighter.AIR:
			return {"pose": _m("jump_up" if f.vy > 0 else "jump_down")}
		Fighter.DASH_F:
			return {"pose": _m("dash_f")}
		Fighter.DASH_B:
			return {"pose": _m("dash_b")}
		Fighter.ATTACK:
			return _attack(f)
		Fighter.THROWING:
			return {"pose": _m("throwing")}
		Fighter.HITSTUN:
			var shake := maxf(0.0, 1.0 - sf / float(SHAKE_FRAMES)) * (4.0 if sf % 2 == 0 else -4.0)
			var pose := _m("hit_crouch") if f.crouching else _m("hit", f.combo_hits)
			return {"pose": pose, "dx": shake}
		Fighter.BLOCKSTUN:
			var push := maxf(0.0, 1.0 - sf / 6.0) * (2.0 if sf % 2 == 0 else -2.0)
			return {"pose": _m("block_low" if f.crouching else "block"), "dx": push}
		Fighter.THROW_TECH:
			return {"pose": _m("throw_tech")}
		Fighter.JUGGLE:
			return {"pose": _m("juggle")}
		Fighter.THROWN:
			return {"pose": _m("thrown")}
		Fighter.KNOCKDOWN:
			return {"pose": _m("knockdown")}
		Fighter.GETUP:
			return {"pose": _m("getup")}
		Fighter.KO:
			return {"pose": _m("ko_air" if f.airborne else "ko")}
		Fighter.WIN:
			return {"pose": _m("win") if sf >= 10 else _m("idle")}
	return {"pose": _m("idle")}


func _attack(f) -> Dictionary:
	if f.move < 0:
		return {"pose": _m("idle")}
	var m: Dictionary = f.cur_move()
	var keys: Dictionary = map.get("moves", {}).get(m.name, {})
	var base := _m("crouch") if m.crouching else (_m("jump_down") if f.airborne else _m("idle"))
	if keys.is_empty():
		return {"pose": ""}   # no pictures for this move: let the cutout rig draw it
	var mf: int = f.move_frame
	var strike = keys.get("strike", base)
	if m.hits.is_empty():
		# No hitbox (a roll or dash move): wind-up briefly, then the strike pose for the rest.
		if mf < 4:
			return {"pose": keys.get("wind", base)}
		var out := {"pose": strike[0] if strike is Array else strike}
		if keys.get("spin", false):
			out.spin = (mf - 4) * 0.45
		return out
	if mf < m.first_active:
		return {"pose": keys.get("wind", base)}
	var last_end: int = m.first_active
	for i in m.hits.size():
		var h: Dictionary = m.hits[i]
		last_end = maxi(last_end, h.end)
		if mf >= h.start and mf < h.end:
			var pose: String = strike[mini(i, strike.size() - 1)] if strike is Array else strike
			var t: int = mf - h.start
			if t < SNAP_FRAMES:
				# Snap: the first strike frames are stretched forward a little.
				var k := 1.0 - t / float(SNAP_FRAMES)
				return {"pose": pose, "sx": 1.0 + 0.07 * k, "sy": 1.0 - 0.03 * k, "dx": 4.0 * k}
			return {"pose": pose}
	if mf < last_end:
		# Between hits of a multi-hit move: hold the last strike.
		var i := 0
		for j in m.hits.size():
			if mf >= m.hits[j].end:
				i = j
		return {"pose": strike[mini(i, strike.size() - 1)] if strike is Array else strike}
	var last: String = strike[strike.size() - 1] if strike is Array else strike
	if keys.has("recover"):
		return {"pose": keys.recover}
	var hold := last_end + int((m.total - last_end) * RECOVER_HOLD)
	return {"pose": last if mf < hold else base}
