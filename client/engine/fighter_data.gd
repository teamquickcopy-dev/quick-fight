## Loads and validates one fighter's data file (fighters/<id>/fighter.json).
## Every number is converted to a whole number in sim units; fractions are rejected so the
## sim stays deterministic. See fighters/README.md for the file format.
extends RefCounted

const R := preload("res://engine/rules.gd")
const B := preload("res://engine/input_bits.gd")

const CATEGORIES := ["light", "heavy", "special", "super", "ultra", "throw"]
const NORMAL_PREFIXES := ["st_", "cr_", "j_"]
const BUTTONS := {"lp": B.LP, "hp": B.HP, "lk": B.LK, "hk": B.HK}
const LEVELS := {"mid": 0, "low": 1, "overhead": 2}
const LEVEL_MID := 0
const LEVEL_LOW := 1
const LEVEL_OVERHEAD := 2
const SPECIAL_DIRS := ["forward", "down", "back"]
const SPECIAL_MOTIONS := {"forward": ["d", "df", "f"], "down": ["f", "d", "df"], "back": ["d", "db", "b"]}

var path := ""
var id := ""
var display_name := ""
var archetype := ""
var color := Color.WHITE        # presentation only, never read by the sim
var rig := "graybox"
var health := 0
var walk_forward := 0
var walk_back := 0
var dash_forward_frames := 0
var dash_forward_speed := 0
var dash_back_frames := 0
var dash_back_speed := 0
var jump_squat := 0
var jump_velocity := 0
var jump_forward := 0
var gravity := 0
var push_w := 0
var push_h := 0
var hurt_stand: Array = []
var hurt_crouch: Array = []
var hurt_air: Array = []

var moves: Array = []           # normalized move dictionaries; index = move id in the sim
var move_index := {}            # name -> index
var normals := {}               # "st_lp" etc. -> index
var specials: Array = []        # [{dir, button, motion, move}]
var throw_move := -1
var super_move := -1
var ultra_move := -1

var errors := PackedStringArray()


static func load_file(file_path: String):
	var d = load("res://engine/fighter_data.gd").new()
	d.path = file_path
	var text := FileAccess.get_file_as_string(file_path)
	if text.is_empty():
		d.errors.append("%s: missing or empty" % file_path)
		return d
	var json := JSON.new()
	if json.parse(text) != OK:
		d.errors.append("%s: JSON error line %d: %s" % [file_path, json.get_error_line(), json.get_error_message()])
		return d
	if typeof(json.data) != TYPE_DICTIONARY:
		d.errors.append("%s: top level must be an object" % file_path)
		return d
	d._parse(json.data)
	return d


## Every fighter folder under res://fighters that has a fighter.json (folders starting with "_" are shared parts).
static func discover(root: String = "res://fighters") -> PackedStringArray:
	var out := PackedStringArray()
	for dir in DirAccess.get_directories_at(root):
		if dir.begins_with("_"):
			continue
		var p := "%s/%s/fighter.json" % [root, dir]
		if FileAccess.file_exists(p):
			out.append(p)
	return out


func ok() -> bool:
	return errors.is_empty()


func move(idx: int) -> Dictionary:
	return moves[idx]


# --- parsing ---------------------------------------------------------------------------------

func _err(where: String, msg: String) -> void:
	errors.append("%s [%s]: %s" % [id if id != "" else path, where, msg])


func _int(d: Dictionary, key: String, where: String, default = null, min_value := 0) -> int:
	if not d.has(key):
		if default == null:
			_err(where, "missing '%s'" % key)
			return 0
		return default
	var v = d[key]
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		_err(where, "'%s' must be a number" % key)
		return 0
	if float(v) != floorf(float(v)):
		_err(where, "'%s' must be a whole number (got %s)" % [key, v])
	var i := int(v)
	if i < min_value:
		_err(where, "'%s' must be >= %d" % [key, min_value])
	return i


func _box(v, where: String) -> Array:
	if typeof(v) != TYPE_ARRAY or v.size() != 4:
		_err(where, "box must be [x, y, w, h]")
		return [0, 0, 1, 1]
	var out := []
	for n in v:
		if typeof(n) != TYPE_FLOAT and typeof(n) != TYPE_INT or float(n) != floorf(float(n)):
			_err(where, "box values must be whole numbers")
			return [0, 0, 1, 1]
		out.append(int(n) * R.FP)
	if out[2] <= 0 or out[3] <= 0:
		_err(where, "box width and height must be positive")
	return out


func _boxes(v, where: String) -> Array:
	if typeof(v) != TYPE_ARRAY or v.is_empty():
		_err(where, "needs at least one box")
		return []
	var out := []
	for b in v:
		out.append(_box(b, where))
	return out


func _parse(d: Dictionary) -> void:
	id = str(d.get("id", ""))
	if id == "":
		_err("root", "missing 'id'")
	display_name = str(d.get("name", id))
	archetype = str(d.get("archetype", ""))
	rig = str(d.get("rig", "graybox"))
	color = Color.from_string(str(d.get("color", "#cccccc")), Color.GRAY)
	health = _int(d, "health", "root", null, 1)

	var walk: Dictionary = d.get("walk", {})
	walk_forward = _int(walk, "forward", "walk")
	walk_back = _int(walk, "back", "walk")
	var dash: Dictionary = d.get("dash", {})
	var df: Dictionary = dash.get("forward", {})
	var db: Dictionary = dash.get("back", {})
	dash_forward_frames = _int(df, "frames", "dash.forward", null, 1)
	dash_forward_speed = _int(df, "speed", "dash.forward")
	dash_back_frames = _int(db, "frames", "dash.back", null, 1)
	dash_back_speed = _int(db, "speed", "dash.back")
	var jump: Dictionary = d.get("jump", {})
	jump_squat = _int(jump, "squat", "jump", null, 1)
	jump_velocity = _int(jump, "velocity", "jump", null, 1)
	jump_forward = _int(jump, "forward", "jump")
	gravity = _int(jump, "gravity", "jump", null, 1)
	var push: Dictionary = d.get("pushbox", {})
	push_w = _int(push, "w", "pushbox", null, 1) * R.FP
	push_h = _int(push, "h", "pushbox", null, 1) * R.FP
	var hurt: Dictionary = d.get("hurtboxes", {})
	hurt_stand = _boxes(hurt.get("stand"), "hurtboxes.stand")
	hurt_crouch = _boxes(hurt.get("crouch"), "hurtboxes.crouch")
	hurt_air = _boxes(hurt.get("air"), "hurtboxes.air")

	var raw_moves = d.get("moves", {})
	if typeof(raw_moves) != TYPE_DICTIONARY:
		_err("moves", "must be an object")
		return
	var names: Array = raw_moves.keys()
	names.sort()  # stable move ids regardless of file order
	for name in names:
		var m := _parse_move(str(name), raw_moves[name])
		move_index[m.name] = moves.size()
		moves.append(m)
	_index_moves()
	# Cancel targets must exist (categories or move names).
	for m in moves:
		for c in m.cancel:
			if not c in CATEGORIES and not move_index.has(c):
				_err(m.name, "cancel target '%s' is not a category or move" % c)


func _parse_move(name: String, raw) -> Dictionary:
	var m := {}
	if typeof(raw) != TYPE_DICTIONARY:
		_err(name, "move must be an object")
		raw = {}
	var src: Dictionary = raw
	m.name = name
	m.category = str(src.get("category", ""))
	if not m.category in CATEGORIES:
		_err(name, "category must be one of %s" % [CATEGORIES])
	m.air = name.begins_with("j_") or bool(src.get("air", false))
	m.crouching = name.begins_with("cr_")
	m.throw = m.category == "throw" or bool(src.get("grab", false))
	m.breakable = bool(src.get("breakable", m.category == "throw"))
	m.meter_cost = _int(src, "meter_cost", name, 0)
	m.flash = _int(src, "flash", name, 0)
	m.cancel = src.get("cancel", [])
	m.input = src.get("input", {})

	var startup := _int(src, "startup", name, 0)
	var active := _int(src, "active", name, 0)
	var recovery := _int(src, "recovery", name, null)
	m.startup = startup
	m.active = active
	m.recovery = recovery

	m.hits = []
	if src.has("hits"):
		for h in src.hits:
			if typeof(h) != TYPE_DICTIONARY:
				_err(name, "each hit must be an object")
				continue
			var merged := src.duplicate()
			merged.erase("hits")
			merged.merge(h, true)
			var repeat := _int(h, "repeat", name, 0)
			var every := _int(h, "every", name, 0)
			if repeat > 0 and every <= 0:
				_err(name, "'repeat' needs 'every'")
			for r in repeat + 1:
				var start := _int(merged, "start", name, null) + r * every
				m.hits.append(_parse_hit(name, merged, start, _int(merged, "active", name, null, 1)))
	elif src.has("damage") or m.throw:
		if active < 1:
			_err(name, "'active' must be >= 1 for a move that hits")
		m.hits.append(_parse_hit(name, src, startup, maxi(active, 1)))
	if m.hits.size() > 30:
		_err(name, "at most 30 hits per move")

	var last_end := startup + active
	var first := 1 << 30
	for h in m.hits:
		last_end = maxi(last_end, h.end)
		first = mini(first, h.start)
	m.first_active = first if not m.hits.is_empty() else last_end
	m.total = last_end + recovery
	if m.total < 1:
		_err(name, "move must last at least 1 frame")

	m.motion = []
	for seg in src.get("motion", []):
		if typeof(seg) != TYPE_ARRAY or seg.size() != 3:
			_err(name, "motion entries are [from, to, vx]")
			continue
		m.motion.append([int(seg[0]), int(seg[1]), int(seg[2])])

	var armor = src.get("armor", [])
	m.armor_from = int(armor[0]) if armor.size() == 3 else -1
	m.armor_to = int(armor[1]) if armor.size() == 3 else -1
	m.armor_hits = int(armor[2]) if armor.size() == 3 else 0

	var inv: Dictionary = src.get("invuln", {})
	m.inv_from = _int(inv, "from", name, -1, -1)
	m.inv_to = _int(inv, "to", name, -1, -1)
	m.inv_strike = bool(inv.get("strike", false))
	m.inv_throw = bool(inv.get("throw", false))
	m.inv_projectile = bool(inv.get("projectile", false))

	m.hurt_extend = []
	if src.has("hurt_extend"):
		m.hurt_extend = _boxes(src.hurt_extend, name + ".hurt_extend")
	return m


func _parse_hit(name: String, src: Dictionary, start: int, active: int) -> Dictionary:
	var h := {}
	h.start = start
	h.end = start + active
	h.damage = _int(src, "damage", name, null)
	h.chip = _int(src, "chip", name, 0)
	h.box = _box(src.get("box"), name + ".box")
	if src.get("category", "") == "throw" or bool(src.get("grab", false)):
		h.hitstun = 0
		h.blockstun = 0
		h.pushback = 0
		h.level = LEVEL_MID
		h.knockdown = true
	else:
		h.hitstun = _int(src, "hitstun", name, null, 1)
		h.blockstun = _int(src, "blockstun", name, null, 1)
		h.pushback = _int(src, "pushback", name, 0) * R.FP
		var lvl := str(src.get("level", "mid"))
		if not LEVELS.has(lvl):
			_err(name, "level must be mid, low or overhead")
		h.level = LEVELS.get(lvl, LEVEL_MID)
		h.knockdown = bool(src.get("knockdown", false))
	var strength := str(src.get("strength", "light" if src.get("category", "") == "light" else "heavy"))
	h.heavy = strength == "heavy"
	h.hitstop = R.HITSTOP_HEAVY if h.heavy else R.HITSTOP_LIGHT
	var launch = src.get("launch", [])
	h.launch = launch.size() == 2
	h.launch_vx = int(launch[0]) if h.launch else 0
	h.launch_vy = int(launch[1]) if h.launch else 0
	return h


func _index_moves() -> void:
	for i in moves.size():
		var m: Dictionary = moves[i]
		match m.category:
			"light", "heavy":
				var ok_name := false
				for p in NORMAL_PREFIXES:
					if m.name.begins_with(p) and BUTTONS.has(m.name.substr(p.length())):
						ok_name = true
				if not ok_name:
					_err(m.name, "normals are named st_/cr_/j_ + lp/hp/lk/hk")
				var btn: String = m.name.get_slice("_", 1)
				var expected := "light" if btn in ["lp", "lk"] else "heavy"
				if m.category != expected:
					_err(m.name, "a %s button normal must have category '%s'" % [btn, expected])
				normals[m.name] = i
			"throw":
				if throw_move >= 0:
					_err(m.name, "only one throw")
				throw_move = i
			"super":
				super_move = i
			"ultra":
				ultra_move = i
			"special":
				var inp: Dictionary = m.input
				var dir := str(inp.get("dir", ""))
				var btn := str(inp.get("button", ""))
				if not dir in SPECIAL_DIRS or not btn in ["hp", "hk"]:
					_err(m.name, "special input must be {dir: forward|down|back, button: hp|hk}")
					continue
				for s in specials:
					if s.dir == dir and s.button == BUTTONS[btn]:
						_err(m.name, "input %s+%s is used twice" % [dir, btn])
				specials.append({"dir": dir, "button": BUTTONS[btn], "motion": SPECIAL_MOTIONS[dir], "move": i})
	for p in NORMAL_PREFIXES:
		for btn in BUTTONS:
			if not normals.has(p + btn):
				_err("moves", "missing normal %s%s" % [p, btn])
	if throw_move < 0:
		_err("moves", "missing throw")
	if super_move < 0 or moves[super_move].meter_cost != R.METER_PER_BAR:
		_err("moves", "needs a super costing 1 bar (%d)" % R.METER_PER_BAR)
	if ultra_move < 0 or moves[ultra_move].meter_cost != R.METER_MAX:
		_err("moves", "needs an ultra costing 3 bars (%d)" % R.METER_MAX)
