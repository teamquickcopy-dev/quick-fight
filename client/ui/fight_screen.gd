## One match on screen: fixed 60-tick sim loop (independent of the display refresh rate),
## input routing (players, CPU, training dummy), camera, effects, HUD, pause menu and
## Training tools. Everything that decides the fight lives in engine/; this only presents it.
extends Node2D

signal finished(action: String)   # "rematch", "select", "menu"

const B := preload("res://engine/input_bits.gd")
const R := preload("res://engine/rules.gd")
const FD := preload("res://engine/fighter_data.gd")
const Fighter := preload("res://engine/fighter.gd")
const MatchSim := preload("res://engine/match_sim.gd")
const Cpu := preload("res://engine/cpu.gd")
const Rigs := preload("res://fighters/rigs.gd")
const Effects := preload("res://fx/effects.gd")
const Stage := preload("res://stages/painted/stage.gd")
const Rollback := preload("res://net/rollback.gd")
const Art := preload("res://fighters/_cutout/art.gd")

const TICK_USEC := 1000000 / R.TICKS_PER_SECOND
const MAX_CATCHUP := 4
const GROUND_Y := Stage.GROUND_Y
const INKY_MOVES := ["squeegee_swing", "heat_press", "full_bleed"]   # hits that also splat ink
const DUMMY_MODES := ["Stand", "Crouch", "Jump", "Block stand", "Block crouch", "Block all", "CPU", "Player 2"]

## mode: "cpu" | "versus" | "training" | "online"; p1/p2: FighterData; level: CPU level;
## online only: online (net/online.gd), local (0/1 = which side we play), delay (input delay)
var cfg: Dictionary
var sim: MatchSim
var cpu: Cpu
var fx := Effects.new()
var stage := Stage.new("print_floor")
var font: Font
var colors: Array = []
var tints: Array = [Color.WHITE, Color.WHITE]

var _acc := 0
var _last := 0
var ticks := 0
var cam_x := 0.0                 # left edge of the view, in stage px (for parallax)
var cam_center := 0.0            # stage px at the middle of the screen
var zoom := 1.0
var bg_layer: Node2D             # back wall / machines (screen space)
var world_layer: Node2D          # floor, fighters, effects (stage space, zoomed)
var slowmo := 1                  # Training: F5 runs the game at 1/4 speed
var shake := 0.0
var shake_offset := Vector2.ZERO

var menu_open := false
var menu_items: Array = []
var menu_index := 0
var menu_title := ""
var results_winner := -1          # shows the winner's / loser's expressions on the results menu

var announce := ""
var announce_sub := ""
var announce_t := 0
var combo := [{"hits": 0, "dmg": 0, "t": 0}, {"hits": 0, "dmg": 0, "t": 0}]
var counter_t := [0, 0]
var hp_trail := [1.0, 1.0]

# Training
var show_boxes := false
var dummy_mode := 0
var frame_info := ""
var move_info := ""
var training_cpu: Cpu

# Performance overlay (F9)
var show_perf := false
var tick_us := 0
var _fps_frames := 0
var _fps_time := 0
var fps := 0

# Online
var session: Rollback
var online_dead := false
var _prev_state := [-1, -1]        # for state-change sounds
var _seen_events := {}           # dedupes events replayed by rollback: key -> frame
## Tests can supply player 1's input instead of the keyboard: () -> int mask.
var local_input := Callable()


func setup(config: Dictionary) -> void:
	cfg = config
	font = ThemeDB.fallback_font
	var training: bool = cfg.mode == "training"
	sim = MatchSim.new(cfg.p1, cfg.p2, training)
	var c1: Color = cfg.p1.color
	var c2: Color = cfg.p2.color
	if cfg.p1.id == cfg.p2.id:
		c2 = Color.from_hsv(fmod(c2.h + 0.5, 1.0), c2.s, c2.v * 0.9)  # mirror match: recolor P2
	colors = [c1, c2]
	tints = [Color.WHITE, Color(0.78, 0.86, 1.0) if cfg.p1.id == cfg.p2.id else Color.WHITE]
	stage = Stage.new(Stage.pick_id(cfg.p1.id, cfg.p2.id))
	var seed := int(Time.get_unix_time_from_system())
	if cfg.mode == "cpu":
		cpu = Cpu.new(1, cfg.get("level", Cpu.Level.SENIOR), seed)
	training_cpu = Cpu.new(1, Cpu.Level.SENIOR, seed)
	if cfg.mode == "online":
		session = Rollback.new(sim, cfg.local, cfg.delay, func() -> int: return Time.get_ticks_msec())
		cfg.online.set_input_handler(session.receive)
	fx.clear()
	_last = Time.get_ticks_usec()
	_acc = 0
	menu_open = false
	cam_center = R.STAGE_WIDTH / R.FP / 2.0
	zoom = 1.5
	cam_x = cam_center - 640.0 / zoom
	# Draw order by z_index: background, then the zoomed world, then this node (HUD, menus).
	bg_layer = Node2D.new()
	bg_layer.z_index = -2
	bg_layer.draw.connect(func(): _draw_bg(bg_layer))
	add_child(bg_layer)
	world_layer = Node2D.new()
	world_layer.z_index = -1
	world_layer.draw.connect(func(): _draw_world(world_layer))
	add_child(world_layer)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := now - _last
	_last = now
	_fps_frames += 1
	_fps_time += elapsed
	if _fps_time >= 500000:
		fps = roundi(_fps_frames * 1000000.0 / _fps_time)
		_fps_frames = 0
		_fps_time = 0
		if OS.has_feature("web"):
			# Read by the browser tests (tests/web/load_test.js, tests/web/online_test.js).
			JavaScriptBridge.eval("window.qfStats = %s;" % JSON.stringify(_stats()), true)

	var online_mode: bool = cfg.mode == "online"
	if menu_open:
		_menu_input()
	elif Input.is_action_just_pressed("pause"):
		if online_mode:
			_open_menu("MENU", ["Resume", "Leave match"])   # the fight keeps running online
		else:
			_open_menu("PAUSED", ["Resume", "Restart", "Character select", "Main menu"])
	if (not menu_open or online_mode) and not online_dead:
		_acc = mini(_acc + elapsed, TICK_USEC * slowmo * MAX_CATCHUP)
		while _acc >= TICK_USEC * slowmo:
			_tick()
			_acc -= TICK_USEC * slowmo
	_update_camera()
	queue_redraw()
	bg_layer.queue_redraw()
	world_layer.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_F1:
			show_boxes = not show_boxes
		KEY_F9:
			show_perf = not show_perf
		KEY_F10:
			if cfg.mode == "online":
				# Debug: add 75 ms each way to outgoing input packets (applies to new packets).
				cfg.online.added_lag_ms = 0 if cfg.online.added_lag_ms > 0 else 75
	if cfg.mode != "training":
		return
	match event.physical_keycode:
		KEY_F2:
			sim.infinite_meter = not sim.infinite_meter
		KEY_F3:
			dummy_mode = (dummy_mode + 1) % DUMMY_MODES.size()
		KEY_F4:
			_reset_training()
		KEY_F5:
			slowmo = 4 if slowmo == 1 else 1


func _reset_training() -> void:
	var c := R.STAGE_WIDTH / 2
	sim.fighters[0].reset_round(c - R.START_GAP / 2, 1)
	sim.fighters[1].reset_round(c + R.START_GAP / 2, -1)
	fx.clear()


# --- simulation ----------------------------------------------------------------------------------

func _tick() -> void:
	ticks += 1
	var m0: int = local_input.call() if local_input.is_valid() else Controls.mask(1)
	var m1 := 0
	match cfg.mode:
		"cpu":
			m1 = cpu.next_input(sim)
		"versus":
			m1 = Controls.mask(2)
		"training":
			m1 = _dummy_input()
	var t0 := Time.get_ticks_usec()
	if cfg.mode == "online":
		var events: Array = session.advance(0 if menu_open else m0)
		for bytes in session.take_outgoing():
			cfg.online.send_input(bytes)
		for e in events:
			if _fresh(e):
				_on_event(e)
	else:
		sim.step(m0, m1)
		for e in sim.events:
			_on_event(e)
	tick_us = Time.get_ticks_usec() - t0
	_state_sounds()
	fx.tick()
	announce_t = maxi(announce_t - 1, 0)
	for i in 2:
		combo[i].t = maxi(combo[i].t - 1, 0)
		counter_t[i] = maxi(counter_t[i] - 1, 0)
		var f = sim.fighters[i]
		var ratio: float = float(f.health) / f.data.health
		hp_trail[i] = ratio if ratio > hp_trail[i] else move_toward(hp_trail[i], ratio, 0.006 if f.state != Fighter.HITSTUN else 0.0)
	if sim.phase == MatchSim.Phase.OVER and (not menu_open or menu_items[0] == "Resume"):
		var w: int = sim.match_winner
		var items := ["Rematch", "Character select", "Main menu"]
		if cfg.mode == "online":
			items = ["Rematch", "Change fighter", "New opponent", "Main menu"]
		_open_menu("DRAW" if w == 2 else "%s WINS" % sim.fighters[w].data.display_name.to_upper(), items)
		results_winner = w


## Sounds for state changes the sim has no event for: jump, dash, launched into the air.
func _state_sounds() -> void:
	for i in 2:
		var st: int = sim.fighters[i].state
		if st != _prev_state[i]:
			match st:
				Fighter.AIR:
					if _prev_state[i] == Fighter.JUMP_SQUAT:
						Sfx.play("jump", -5.0, 0.08)
				Fighter.DASH_F, Fighter.DASH_B:
					Sfx.play("dash", -6.0)
				Fighter.JUGGLE:
					Sfx.play("launch", -4.0, 0.05)
			_prev_state[i] = st


## Rollback can replay frames: show each event (spark, announcement) once per frame it happened in.
func _fresh(e: Dictionary) -> bool:
	var key := "%s|%d|%d" % [e.t, e.frame, e.get("p", -1)]
	if _seen_events.has(key):
		return false
	_seen_events[key] = e.frame
	if _seen_events.size() > 400:
		for k in _seen_events.keys():
			if _seen_events[k] < session.frame - 120:
				_seen_events.erase(k)
	return true


func show_disconnected(reason: String) -> void:
	online_dead = true
	_open_menu(reason.to_upper(), ["New opponent", "Main menu"])


func _stats() -> Dictionary:
	var out := {"fps": fps, "tick_us": tick_us, "ticks": ticks, "phase": sim.phase, "frame": sim.frame,
			"hp": [sim.fighters[0].health, sim.fighters[1].health]}
	if session:
		out.merge({"rtt": int(session.rtt_ms), "delay": session.input_delay, "desync": session.desync_frame,
				"checked": session._local_checksums.size()})
		out.merge(session.stats)
	return out


func _dummy_input() -> int:
	var d = sim.fighters[1]
	var p = sim.fighters[0]
	var back: int = d.back_bit()
	match DUMMY_MODES[dummy_mode]:
		"Crouch":
			return B.DOWN
		"Jump":
			return B.UP
		"Block stand":
			return back
		"Block crouch":
			return back | B.DOWN
		"Block all":
			# Reads the attack's height directly (a perfect blocker for practising mix-ups).
			if p.state == Fighter.ATTACK and not p.cur_move().hits.is_empty():
				var lvl: int = p.cur_move().hits[0].level
				return back | (B.DOWN if lvl == FD.LEVEL_LOW and not p.airborne else 0)
			return back | B.DOWN
		"CPU":
			return training_cpu.next_input(sim)
		"Player 2":
			return Controls.mask(2)
	return 0


func _world(x: int, y: int) -> Vector2:
	return Vector2(float(x) / R.FP, GROUND_Y - float(y) / R.FP)


func _on_event(e: Dictionary) -> void:
	match e.t:
		"hit":
			Sfx.play("counter" if e.counter else ("hit_heavy" if e.heavy else "hit_light"))
			if e.counter:
				Sfx.play("hit_heavy", -3.0)
			if e.move in INKY_MOVES:
				Sfx.play("splat", -2.0)
			var pos := _world(e.x, e.y)
			fx.hit(pos, e.heavy, e.counter)
			var p: int = e.p
			combo[p].hits = e.combo
			combo[p].dmg = sim.fighters[p].combo_damage
			combo[p].t = 90
			if e.counter:
				counter_t[1 - p] = 60
				fx.label(pos + Vector2(0, -40), "COUNTER", Color("#ff5050"))
			if cfg.mode == "training":
				frame_info = "%s  dmg %d  %s" % [e.move, e.dmg, ("on hit %+d" % e.adv) if e.adv != 0 or e.move.begins_with("st_") else "knockdown/launch"]
		"block":
			Sfx.play("block", -4.0)
			fx.block(_world(e.x, e.y))
			if cfg.mode == "training":
				frame_info = "blocked  on block %+d" % e.adv
		"armor":
			fx.armor(_world(e.x, e.y))
			fx.label(_world(e.x, e.y) + Vector2(0, -40), "ARMOR", Color("#ffb347"))
		"shake":
			shake = maxf(shake, e.amount)
		"knockdown":
			Sfx.play("knockdown")
			var f = sim.fighters[e.p]
			fx.dust(_world(f.x, 0), 8)
			shake = maxf(shake, 4.0)
		"land":
			Sfx.play("land", -8.0)
			var lf = sim.fighters[e.p]
			fx.dust(_world(lf.x, 0), 3)
		"move":
			match e.category:
				"light":
					Sfx.play("whoosh_light", -6.0, 0.12)
				"heavy", "special":
					Sfx.play("whoosh_heavy", -3.0, 0.1)
				"throw":
					Sfx.play("grab", -4.0)
			var mf = sim.fighters[e.p]
			if e.p == 0:
				# By name: online, events can arrive after a rollback moved the sim past this move.
				var m: Dictionary = mf.data.moves[mf.data.move_index[e.move]]
				move_info = "%s  startup %d  active %d  recovery %d" % [m.name, m.first_active, m.active if m.hits.size() <= 1 else m.hits.size(), m.recovery]
			if e.category in ["super", "ultra"]:
				fx.shockwave(_world(mf.x, 110 * R.FP))
		"super_flash":
			Sfx.play("super", 0.0, 0.0)
			fx.super_flash(e.frames)
		"grab":
			Sfx.play("grab")
		"tech":
			Sfx.play("block")
			fx.label(_world(e.x, e.y), "THROW BREAK", Color("#8fd3ff"))
		"round_start":
			Sfx.play("round", -4.0, 0.0)
			var final_round: bool = sim.wins[0] == R.ROUNDS_TO_WIN - 1 and sim.wins[1] == R.ROUNDS_TO_WIN - 1
			_announce("FINAL ROUND" if final_round else "ROUND %d" % e.round, "", 80)
		"fight":
			Sfx.play("fight", -2.0, 0.0)
			_announce("FIGHT!", "", 50)
		"ko":
			Sfx.play("ko", 0.0, 0.0)
			fx.ko_flash()
			shake = 12.0
			_announce("K.O.", "PERFECT" if e.perfect else "", 120)
		"time":
			_announce("TIME", "", 120)
		"match_over":
			if e.winner < 2:
				Sfx.play("win", -2.0, 0.0)
				_announce("%s WINS" % sim.fighters[e.winner].data.display_name.to_upper(), "Press Super (HP + HK) for the finisher!", 120)
		"finisher":
			Sfx.play("hit_heavy")
			Sfx.play("splat", 0.0, 0.0, 0.7)
			var loser = sim.fighters[1 - e.p]
			for i in 4:
				fx.ink(_world(loser.x, 100 * R.FP), 10)
			fx.shockwave(_world(loser.x, 100 * R.FP))
			shake = 14.0
			_announce("FINISHER!", "", 110)


func _announce(text: String, sub: String, frames: int) -> void:
	announce = text
	announce_sub = sub
	announce_t = frames


## Fighting-game camera: follows the midpoint and zooms in when the fighters are close
## (up to 1.5x), out when they're apart, never showing past the stage edges.
func _update_camera() -> void:
	var a: float = float(sim.fighters[0].x) / R.FP
	var b: float = float(sim.fighters[1].x) / R.FP
	var target_zoom := clampf(1280.0 / (absf(a - b) + 380.0), 1.0, 1.5)
	zoom = lerpf(zoom, target_zoom, 0.06)
	var half := 640.0 / zoom
	var stage_w: float = R.STAGE_WIDTH / R.FP
	cam_center = lerpf(cam_center, clampf((a + b) / 2.0, half, stage_w - half), 0.15)
	cam_x = cam_center - half
	world_layer.transform = Transform2D(0, Vector2(zoom, zoom), 0,
			Vector2(640.0 - cam_center * zoom, GROUND_Y - GROUND_Y * zoom) + shake_offset)
	if shake > 0.1:
		shake_offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake) * 0.6)
		shake *= 0.85
	else:
		shake = 0.0
		shake_offset = Vector2.ZERO


# --- menu (pause and results) --------------------------------------------------------------------

func _open_menu(title: String, items: Array) -> void:
	results_winner = -1
	menu_open = true
	menu_title = title
	menu_items = items
	menu_index = 0


func _menu_input() -> void:
	if Controls.menu("up"):
		menu_index = (menu_index + menu_items.size() - 1) % menu_items.size()
	elif Controls.menu("down"):
		menu_index = (menu_index + 1) % menu_items.size()
	elif Controls.menu("accept"):
		_menu_choose(menu_items[menu_index])
	elif menu_items[0] == "Resume" and (Controls.menu("back") or Input.is_action_just_pressed("pause")):
		_menu_choose("Resume")


func _menu_choose(item: String) -> void:
	match item:
		"Resume":
			menu_open = false
			_last = Time.get_ticks_usec()
		"Restart", "Rematch":
			finished.emit("rematch")
		"Character select", "Change fighter":
			finished.emit("select")
		"New opponent":
			finished.emit("new_opponent")
		"Main menu", "Leave match":
			finished.emit("menu")


func _input(event: InputEvent) -> void:
	# Tap / click support for the menu (phones and tablets until touch controls arrive).
	if not menu_open:
		return
	var pos := Vector2.INF
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	if pos == Vector2.INF:
		return
	pos = get_global_transform_with_canvas().affine_inverse() * pos
	for i in menu_items.size():
		if _menu_rect(i).has_point(pos):
			menu_index = i
			_menu_choose(menu_items[i])
			get_viewport().set_input_as_handled()
			return


func _menu_rect(i: int) -> Rect2:
	return Rect2(440, 300 + i * 56, 400, 48)


# --- drawing -------------------------------------------------------------------------------------

## Background layer (screen space): back wall and machines; dimmed during a super flash.
func _draw_bg(ci: CanvasItem) -> void:
	stage.draw_back(ci, cam_x, ticks, shake_offset)


## World layer (stage px, zoomed by the camera): floor, shadows, fighters, effects, hitboxes.
func _draw_world(ci: CanvasItem) -> void:
	stage.draw_floor(ci)
	if fx.super_dim > 0:
		ci.draw_rect(Rect2(-2000, -2000, 6000, 4000), Color(0, 0, 0, 0.55))
	for f in sim.fighters:
		var lift := clampf(1.0 - float(f.y) / R.FP / 300.0, 0.4, 1.0)
		ci.draw_set_transform(_world(f.x, 0), 0, Vector2(1, 0.22))
		ci.draw_circle(Vector2.ZERO, 46 * lift, Color(0, 0, 0, 0.35 * lift))
	ci.draw_set_transform(Vector2.ZERO)
	# The attacker is drawn on top.
	var order := [0, 1]
	if sim.fighters[0].state == Fighter.ATTACK and sim.fighters[1].state != Fighter.ATTACK:
		order = [1, 0]
	for i in order:
		var f = sim.fighters[i]
		Rigs.draw(ci, f, _world(f.x, f.y), colors[i], tints[i])
	fx.draw(ci, Vector2.ZERO, font)
	if show_boxes:
		_draw_boxes(ci)


## Screen layer: foreground props, flashes, HUD, menus.
func _draw() -> void:
	stage.draw_front(self, cam_x, shake_offset)
	if fx.white_flash > 0.0:
		draw_rect(Rect2(0, 0, 1280, 720), Color(1, 1, 1, fx.white_flash * 0.7))
	_draw_hud()
	if menu_open:
		_draw_menu()


func _rect(b: Array) -> Rect2:
	return Rect2(_world(b[0], b[1] + b[3]), Vector2(float(b[2]) / R.FP, float(b[3]) / R.FP))


func _draw_boxes(ci: CanvasItem) -> void:
	for f in sim.fighters:
		ci.draw_rect(_rect(f.push_box()), Color(1, 0.9, 0.2, 0.8), false, 1.0)
		for hb in f.hurtboxes():
			var r := _rect(hb)
			ci.draw_rect(r, Color(0.2, 0.9, 0.4, 0.18))
			ci.draw_rect(r, Color(0.2, 0.9, 0.4, 0.9), false, 2.0)
		for ah in f.active_hits():
			var r := _rect(ah[1])
			ci.draw_rect(r, Color(1, 0.2, 0.2, 0.3))
			ci.draw_rect(r, Color(1, 0.2, 0.2, 1), false, 2.0)


func _text(pos: Vector2, s: String, size: int, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(font, pos, s, align, width, size, maxi(4, size / 5), Color(0, 0, 0, 0.85))
	draw_string(font, pos, s, align, width, size, color)


func _draw_hud() -> void:
	var w := 470.0
	for i in 2:
		var f = sim.fighters[i]
		var left := i == 0
		var x0 := 96.0 if left else 1280.0 - 96.0 - w
		var y0 := 28.0
		# Face icon at the outer end of the bar.
		var face_rect := Rect2(20.0 if left else 1280.0 - 84.0, 14.0, 64.0, 64.0)
		draw_rect(face_rect.grow(3), colors[i].lightened(0.2))
		var face := Art.ui(f.data, "face")
		if face:
			draw_texture_rect(face, face_rect, false)
		else:
			draw_rect(face_rect, colors[i].darkened(0.3))
			_text(Vector2(face_rect.position.x, face_rect.end.y - 18), f.data.display_name.left(1), 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 64)
		draw_rect(Rect2(x0 - 3, y0 - 3, w + 6, 30), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(x0, y0, w, 24), Color("#3a1414"))
		var ratio: float = float(f.health) / f.data.health
		# Bars drain toward the outer edge, anchored at the centre like classic fighters.
		var trail_w: float = w * hp_trail[i]
		var hp_w: float = w * ratio
		if left:
			draw_rect(Rect2(x0 + w - trail_w, y0, trail_w, 24), Color("#e04040"))
			draw_rect(Rect2(x0 + w - hp_w, y0, hp_w, 24), Color("#f3d34a") if ratio > 0.25 else Color("#ff8c3a"))
		else:
			draw_rect(Rect2(x0, y0, trail_w, 24), Color("#e04040"))
			draw_rect(Rect2(x0, y0, hp_w, 24), Color("#f3d34a") if ratio > 0.25 else Color("#ff8c3a"))
		var name: String = f.data.display_name.to_upper()
		if cfg.mode == "cpu" and i == 1:
			name += "  (CPU: %s)" % Cpu.LEVEL_NAMES[cpu.level]
		if cfg.mode == "online" and i == cfg.local:
			name += "  (YOU)"
		_text(Vector2(x0, y0 + 52), name, 20, colors[i].lightened(0.3), HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT, w)
		# Round wins
		for r in R.ROUNDS_TO_WIN:
			var px := (x0 + w - 14 - r * 22) if left else (x0 + 14 + r * 22)
			draw_circle(Vector2(px, y0 + 44), 7, Color(0, 0, 0, 0.7))
			if r < sim.wins[i]:
				draw_circle(Vector2(px, y0 + 44), 5, Color("#ffd84a"))
		# Meter: 3 bars
		var mx := 40.0 if left else 1280.0 - 40.0 - 270.0
		var bars: int = f.meter / R.METER_PER_BAR
		for b in R.METER_BARS:
			var bx := mx + b * 90.0
			draw_rect(Rect2(bx, 676, 84, 16), Color(0, 0, 0, 0.7))
			var fill := clampf(float(f.meter - b * R.METER_PER_BAR) / R.METER_PER_BAR, 0.0, 1.0)
			var col := Color("#4ac3ff") if fill >= 1.0 else Color("#2a6a8c")
			if fill >= 1.0 and bars == R.METER_BARS:
				col = Color("#ff4ad8") if (ticks / 6) % 2 == 0 else Color("#ffd84a")
			draw_rect(Rect2(bx + 2, 678, 80 * fill, 12), col)
		_text(Vector2(mx + (0 if left else 0), 668), "SUPER" if bars >= 1 else "", 16, Color("#4ac3ff"),
				HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT, 266)
		# Combo counter on the attacker's side.
		var defender: int = 1 - i
		if combo[defender].t > 0 and combo[defender].hits >= 2:
			var cx := 60.0 if left else 1280.0 - 260.0
			_text(Vector2(cx, 250), "%d HITS" % combo[defender].hits, 44, Color("#ffd84a"))
			_text(Vector2(cx, 280), "%d damage" % combo[defender].dmg, 20)
		if counter_t[i] > 0:
			_text(Vector2(60.0 if left else 1280.0 - 260.0, 200), "COUNTER", 30, Color("#ff5050"))
	# Timer
	draw_rect(Rect2(600, 18, 80, 56), Color(0, 0, 0, 0.7))
	var tstr := "--" if cfg.mode == "training" else "%02d" % sim.seconds_left()
	_text(Vector2(600, 64), tstr, 44, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 80)
	# Announcer
	if announce_t > 0:
		var pop := 1.0 + maxf(0.0, (announce_t - 70) / 30.0) * 0.4
		_text(Vector2(0, 330), announce, int(84 * pop), Color("#fff2a8"), HORIZONTAL_ALIGNMENT_CENTER, 1280)
		if announce_sub != "":
			_text(Vector2(0, 380), announce_sub, 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 1280)
	if cfg.mode == "training":
		_draw_training()
	if session:
		var ping_col := Color("#9fffa0") if session.rtt_ms < 120 else (Color("#ffd84a") if session.rtt_ms < 220 else Color("#ff6060"))
		_text(Vector2(600, 96), "%d ms" % session.rtt_ms, 16, ping_col, HORIZONTAL_ALIGNMENT_CENTER, 80)
		if session.desync_frame >= 0:
			_text(Vector2(0, 140), "DESYNC at frame %d" % session.desync_frame, 24, Color("#ff4040"), HORIZONTAL_ALIGNMENT_CENTER, 1280)
		if show_perf:
			var st: Dictionary = session.stats
			_text(Vector2(440, 160), "delay %d  rollbacks %d (max %d)  stalls %d  skips %d  lag+%d ms" % [
				session.input_delay, st.rollbacks, st.max_rollback, st.stalls, st.skips, cfg.online.added_lag_ms],
				16, Color("#9fffa0"), HORIZONTAL_ALIGNMENT_CENTER, 400)
	if show_perf:
		_text(Vector2(560, 110), "%d fps   sim %d us/tick   mem %d MB" % [fps, tick_us, int(OS.get_static_memory_usage() / 1048576.0)], 16, Color("#9fffa0"), HORIZONTAL_ALIGNMENT_CENTER, 160)


func _draw_training() -> void:
	draw_rect(Rect2(40, 100, 470, 140), Color(0, 0, 0, 0.55))
	var lines := [
		"TRAINING   F1 hitboxes: %s   F2 infinite meter: %s" % ["on" if show_boxes else "off", "on" if sim.infinite_meter else "off"],
		"F3 dummy: %s   F4 reset   F5 slow-mo%s   Esc pause" % [DUMMY_MODES[dummy_mode], " ON" if slowmo > 1 else ""],
		move_info,
		frame_info,
		"P1 state: %s   P2 state: %s" % [sim.fighters[0].state_name(), sim.fighters[1].state_name()],
	]
	for i in lines.size():
		_text(Vector2(52, 124 + i * 24), lines[i], 16, Color("#e8e8e8") if i != 3 else Color("#ffd84a"))


func _draw_menu() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.6))
	if results_winner >= 0 and results_winner < 2:
		var winner = sim.fighters[results_winner]
		var loser = sim.fighters[1 - results_winner]
		var win_art := Art.ui(winner.data, "expr_laugh")
		var lose_art := Art.ui(loser.data, "expr_dizzy")
		if win_art:
			var r := Rect2(70, 200, 320, 320)
			draw_rect(r.grow(5), Color("#fff2a8"))
			draw_texture_rect(win_art, r, false)
		if lose_art:
			var r2 := Rect2(940, 300, 220, 220)
			draw_rect(r2.grow(4), Color(1, 1, 1, 0.4))
			draw_texture_rect(lose_art, r2, false, Color(0.75, 0.75, 0.75))
	_text(Vector2(0, 250), menu_title, 56, Color("#fff2a8"), HORIZONTAL_ALIGNMENT_CENTER, 1280)
	for i in menu_items.size():
		var r := _menu_rect(i)
		var sel := i == menu_index
		draw_rect(r, Color("#f3d34a") if sel else Color(1, 1, 1, 0.08))
		_text(Vector2(r.position.x, r.position.y + 34), menu_items[i], 26, Color.BLACK if sel else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
