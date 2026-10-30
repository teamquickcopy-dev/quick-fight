## Screen flow: Title -> Mode -> (CPU level) -> Character select -> Fight -> results.
## Online: Character select -> Online (quick match / room code) -> Fight; the connection stays up
## between fights for rematch / change fighter.
## Menus work with either player's controls (LP confirm, LK back), Enter/Esc, or tap/click.
extends Node2D

const FD := preload("res://engine/fighter_data.gd")
const Cpu := preload("res://engine/cpu.gd")
const FightScreen := preload("res://ui/fight_screen.gd")
const Rigs := preload("res://fighters/rigs.gd")
const Stage := preload("res://stages/painted/stage.gd")
const Art := preload("res://fighters/_cutout/art.gd")
const Fighter := preload("res://engine/fighter.gd")
const Online := preload("res://net/online.gd")
const Rollback := preload("res://net/rollback.gd")

enum Screen { TITLE, MODE, LEVEL, SELECT, CONTROLS, FIGHT, ONLINE }

const MODES := [
	["Versus CPU", "cpu"], ["Versus 2P", "versus"], ["Online", "online"], ["Training", "training"],
	["Controls", "controls"],
]
const ONLINE_ITEMS := ["Quick match", "Create room", "Join room", "Back"]

var screen := Screen.TITLE
var index := 0
var roster: Array = []      # FighterData, discovered from fighters/
var mode := "cpu"
var level := Cpu.Level.SENIOR
var cursor := [0, 1]
var picked := [false, false]
var fight: Node2D
var font: Font
var t := 0
var preview: Array = []     # idle puppets on the select screen
var load_error := ""
var online: Online
var online_status := ""
var room_code := ""
var entering_code := false
var code_entry := ""
var my_ready := {}
var peer_ready := {}


func _ready() -> void:
	font = ThemeDB.fallback_font
	# Fighter art is drawn at about half its texture size: mipmaps keep it smooth (inherited by the fight).
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for p in FD.discover():
		var d: FD = FD.load_file(p)
		if d.ok():
			roster.append(d)
		else:
			load_error += "%s\n" % "\n".join(d.errors)
			push_error("\n".join(d.errors))
	roster.sort_custom(func(a, b): return a.id < b.id)
	if roster.size() > 1:
		cursor = [0, 1]
	for d in roster:
		preview.append(Fighter.new(d))
	online = Online.new()
	add_child(online)
	online.status_changed.connect(func(text): online_status = text)
	online.room_code.connect(_on_room_code)
	online.connected.connect(_send_ready)
	online.control_received.connect(_on_control)
	online.disconnected.connect(_on_disconnected)
	_mark_title_shown()


## Lets the load-time test read when the game's own title is up. On the web the page's HTML
## title (web/shell.html) is shown first and sets window.qfTitleShownAt itself.
func _mark_title_shown() -> void:
	var text_server := TextServerManager.get_primary_interface().get_name()
	if text_server == "Dummy":
		push_error("No text server in this build: text won't render (see tools/web_template_profile.py)")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.qfGameTitleAt = performance.now(); window.qfTextServer = '%s';" % text_server, true)
	print("title screen shown after %d ms" % Time.get_ticks_msec())


## The web page's title screen already asked for "Press any button": skip ours once it's pressed.
func _web_start_pressed() -> bool:
	# eval returns the JS boolean as a number here, so convert rather than compare with `== true`.
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("window.qfStartPressed === true ? 1 : 0", true))


func _process(_delta: float) -> void:
	t += 1
	if screen == Screen.FIGHT:
		return
	for f in preview:
		f.state_frame += 1
	match screen:
		Screen.TITLE:
			if Controls.menu("accept") or _any_button() or _web_start_pressed():
				_go(Screen.MODE)
		Screen.MODE:
			_list_nav(MODES.size())
			if Controls.menu("accept"):
				_pick_mode(index)
			elif Controls.menu("back"):
				_go(Screen.TITLE)
		Screen.LEVEL:
			_list_nav(3)
			if Controls.menu("accept"):
				level = index
				_go(Screen.SELECT)
			elif Controls.menu("back"):
				_go(Screen.MODE)
		Screen.CONTROLS:
			if Controls.menu("accept") or Controls.menu("back"):
				_go(Screen.MODE)
		Screen.SELECT:
			_select_input()
		Screen.ONLINE:
			_online_input()
	queue_redraw()


func _any_button() -> bool:
	for p in [1, 2]:
		for b in ["lp", "hp", "lk", "hk"]:
			if Input.is_action_just_pressed("p%d_%s" % [p, b]):
				return true
	return false


func _go(s: int) -> void:
	screen = s
	index = 0
	if s == Screen.SELECT:
		picked = [false, false]
	if s == Screen.LEVEL:
		index = Cpu.Level.SENIOR


func _list_nav(n: int) -> void:
	if Controls.menu("up"):
		index = (index + n - 1) % n
	elif Controls.menu("down"):
		index = (index + 1) % n


func _pick_mode(i: int) -> void:
	mode = MODES[i][1]
	match mode:
		"controls":
			_go(Screen.CONTROLS)
		"cpu":
			_go(Screen.LEVEL)
		_:
			_go(Screen.SELECT)
	if mode == "online":
		online_status = "" if Online.webrtc_available() else "Online play needs the browser build for now."


## In 2P both players pick at once with their own controls; otherwise P1 picks both sides.
func _select_input() -> void:
	var n := roster.size()
	if n == 0:
		return
	if mode == "versus":
		for p in [0, 1]:
			_cursor_input(p, p + 1)
	elif mode == "online":
		_cursor_input(0, 0)
		if picked[0]:
			_go(Screen.ONLINE)
			if online.state == Online.State.CONNECTED:
				_send_ready()   # changed fighter between matches
			return
	else:
		var side := 0 if not picked[0] else 1
		_cursor_input(side, 0)
	if picked[0] and picked[1]:
		_start_fight()
	elif Controls.menu("back") and not picked[0] and not picked[1]:
		_go(Screen.MODE)


func _cursor_input(side: int, player: int) -> void:
	var n := roster.size()
	if picked[side]:
		if Controls.menu("back", player):
			picked[side] = false
		return
	if Controls.menu("left", player):
		cursor[side] = (cursor[side] + n - 1) % n
	elif Controls.menu("right", player):
		cursor[side] = (cursor[side] + 1) % n
	elif Controls.menu("accept", player):
		picked[side] = true


func _start_fight() -> void:
	screen = Screen.FIGHT
	fight = FightScreen.new()
	add_child(fight)
	fight.setup({"mode": mode, "p1": roster[cursor[0]], "p2": roster[cursor[1]], "level": level})
	fight.finished.connect(_on_fight_finished)
	queue_redraw()


func _on_fight_finished(action: String) -> void:
	fight.queue_free()
	fight = null
	if mode == "online":
		_after_online_fight(action)
		queue_redraw()
		return
	match action:
		"rematch":
			_start_fight()
		"select":
			_go(Screen.SELECT)
		_:
			_go(Screen.MODE)
	queue_redraw()


# --- online ------------------------------------------------------------------------------------

func _online_input() -> void:
	if entering_code:
		return   # handled in _unhandled_input
	if online.state != Online.State.IDLE:
		if Controls.menu("back"):
			online.leave()
			online_status = ""
			room_code = ""
		return
	_list_nav(ONLINE_ITEMS.size())
	if Controls.menu("accept"):
		_online_choose(index)
	elif Controls.menu("back"):
		_go(Screen.SELECT)


func _online_choose(i: int) -> void:
	if ONLINE_ITEMS[i] == "Back":
		_go(Screen.SELECT)
		return
	if not Online.webrtc_available():
		return
	room_code = ""
	my_ready = {}
	peer_ready = {}
	match ONLINE_ITEMS[i]:
		"Quick match":
			online.quick_match()
		"Create room":
			online.create_room()
		"Join room":
			if OS.has_feature("web"):
				var code = JavaScriptBridge.eval("prompt('Room code (4 letters)') || ''", true)
				if str(code).strip_edges().length() == 4:
					online.join_room(str(code).strip_edges())
			else:
				entering_code = true
				code_entry = ""


func _unhandled_input(event: InputEvent) -> void:
	if not entering_code or not event is InputEventKey or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if k == KEY_ESCAPE:
		entering_code = false
	elif k == KEY_BACKSPACE:
		code_entry = code_entry.left(-1)
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		if code_entry.length() == 4:
			entering_code = false
			online.join_room(code_entry)
	elif k >= KEY_A and k <= KEY_Z and code_entry.length() < 4:
		code_entry += char(k)
	get_viewport().set_input_as_handled()


## Both players send "ready" with their fighter; the host then sends "start" for both.
func _on_room_code(code: String) -> void:
	room_code = code
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.qfRoomCode = '%s';" % code, true)   # read by tests/web/online_test.js


func _send_ready() -> void:
	my_ready = {"type": "ready", "fighter": roster[cursor[0]].id, "lag": online.added_lag_ms,
			"version": Online.PROTOCOL_VERSION}
	online.send_control(my_ready)
	online_status = "Waiting for your opponent…"
	if online.is_host and not peer_ready.is_empty():
		_host_start()


func _on_control(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"ready":
			if int(msg.get("version", 0)) != Online.PROTOCOL_VERSION:
				online.leave()
				online_status = "Your opponent has a different version of the game."
				return
			peer_ready = msg
			if screen == Screen.ONLINE and my_ready.is_empty():
				online_status = "Opponent is ready"
			if online.is_host and not my_ready.is_empty():
				_host_start()
		"start":
			if not online.is_host:
				_start_online_fight(msg, 1)


func _find_fighter(id: String) -> FD:
	for d in roster:
		if d.id == id:
			return d
	return null


func _host_start() -> void:
	# Input delay from the measured ping, plus any debug lag either player added, plus one frame
	# each way: the pre-match ping skips the per-frame processing that in-fight packets go through.
	var rtt: float = online.rtt_ms + online.added_lag_ms + int(peer_ready.get("lag", 0)) + 2000.0 / 60.0
	var msg := {"type": "start", "p1": my_ready.fighter, "p2": peer_ready.fighter,
			"delay": Rollback.delay_for_rtt(rtt), "rtt": int(rtt)}
	online.send_control(msg)
	_start_online_fight(msg, 0)


func _start_online_fight(msg: Dictionary, local: int) -> void:
	var p1 := _find_fighter(str(msg.p1))
	var p2 := _find_fighter(str(msg.p2))
	my_ready = {}
	peer_ready = {}
	if p1 == null or p2 == null:
		online.leave()
		online_status = "Your opponent picked a fighter you don't have."
		return
	screen = Screen.FIGHT
	fight = FightScreen.new()
	add_child(fight)
	fight.setup({"mode": "online", "p1": p1, "p2": p2, "online": online, "local": local,
			"delay": int(msg.delay)})
	fight.finished.connect(_on_fight_finished)


func _after_online_fight(action: String) -> void:
	match action:
		"rematch":
			_go(Screen.ONLINE)
			if online.state == Online.State.CONNECTED:
				_send_ready()
		"select":
			_go(Screen.SELECT)
		"new_opponent":
			_go(Screen.ONLINE)
			online.quick_match()
		_:
			online.leave()
			online_status = ""
			_go(Screen.MODE)


func _on_disconnected(reason: String) -> void:
	my_ready = {}
	peer_ready = {}
	room_code = ""
	online_status = reason
	if screen == Screen.FIGHT and fight != null and mode == "online":
		fight.show_disconnected(reason)


# --- tap / click -------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if screen == Screen.FIGHT:
		return
	var pos := Vector2.INF
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	if pos == Vector2.INF:
		return
	pos = get_global_transform_with_canvas().affine_inverse() * pos
	match screen:
		Screen.TITLE:
			_go(Screen.MODE)
		Screen.MODE:
			for i in MODES.size():
				if _item_rect(i).has_point(pos):
					_pick_mode(i)
		Screen.LEVEL:
			for i in 3:
				if _item_rect(i).has_point(pos):
					level = i
					_go(Screen.SELECT)
		Screen.CONTROLS:
			_go(Screen.MODE)
		Screen.SELECT:
			for i in roster.size():
				if _card_rect(i).has_point(pos):
					var side := 0 if not picked[0] else 1
					cursor[side] = i
					picked[side] = true
					if mode == "online":
						_go(Screen.ONLINE)
					elif picked[0] and picked[1]:
						_start_fight()
		Screen.ONLINE:
			if online.state == Online.State.IDLE and not entering_code:
				for i in ONLINE_ITEMS.size():
					if _item_rect(i).has_point(pos):
						_online_choose(i)


# --- drawing -----------------------------------------------------------------------------------

func _item_rect(i: int) -> Rect2:
	return Rect2(440, 270 + i * 64, 400, 52)


func _card_rect(i: int) -> Rect2:
	var n := roster.size()
	var w := 240.0
	var gap := 28.0
	var x0 := 640.0 - (n * w + (n - 1) * gap) / 2.0
	return Rect2(x0 + i * (w + gap), 160, w, 380)


func _text(pos: Vector2, s: String, size: int, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER, width := 1280.0) -> void:
	draw_string_outline(font, pos, s, align, width, size, maxi(4, size / 5), Color(0, 0, 0, 0.85))
	draw_string(font, pos, s, align, width, size, color)


func _draw() -> void:
	if screen == Screen.FIGHT:
		return
	draw_rect(Rect2(0, 0, 1280, 720), Color("#14151b"))
	# CMYK stripes as a placeholder brand mark.
	var cmyk := [Color("#00aeef"), Color("#ec008c"), Color("#fff200"), Color("#2b2b2b")]
	for i in 4:
		draw_rect(Rect2(0, 700 - i * 6, 1280, 6), cmyk[i])
	match screen:
		Screen.TITLE:
			_text(Vector2(0, 250), "QUICK FIGHT", 96, Color("#fff2a8"))
			_text(Vector2(0, 320), "DESIGN TEAM", 52, Color("#00aeef"))
			_text(Vector2(0, 420), "gray-box prototype", 22, Color(1, 1, 1, 0.5))
			if (t / 30) % 2 == 0:
				_text(Vector2(0, 520), "Press any button", 30)
			if load_error != "":
				_text(Vector2(0, 600), "Fighter data errors (see log)", 18, Color("#ff6060"))
		Screen.MODE:
			_text(Vector2(0, 170), "SELECT MODE", 48, Color("#fff2a8"))
			for i in MODES.size():
				_item(i, MODES[i][0])
		Screen.LEVEL:
			_text(Vector2(0, 170), "CPU LEVEL", 48, Color("#fff2a8"))
			for i in 3:
				_item(i, Cpu.LEVEL_NAMES[i])
		Screen.CONTROLS:
			_draw_controls()
		Screen.SELECT:
			_draw_select()
		Screen.ONLINE:
			_draw_online()


func _item(i: int, label: String) -> void:
	var r := _item_rect(i)
	var sel := i == index
	draw_rect(r, Color("#f3d34a") if sel else Color(1, 1, 1, 0.07))
	_text(Vector2(r.position.x, r.position.y + 36), label, 28, Color.BLACK if sel else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_select() -> void:
	var title := "CHOOSE YOUR DESIGNER"
	if mode != "versus" and picked[0]:
		title = "CHOOSE OPPONENT" if mode == "cpu" else "CHOOSE TRAINING DUMMY"
	_text(Vector2(0, 120), title, 44, Color("#fff2a8"))
	for i in roster.size():
		var d: FD = roster[i]
		var r := _card_rect(i)
		draw_rect(r, Color(1, 1, 1, 0.06))
		var portrait := Art.ui(d, "portrait")
		if portrait:
			draw_texture_rect_region(portrait, r, Art.portrait_region(d, portrait, r.size))
		else:
			Rigs.draw(self, preview[i], Vector2(r.get_center().x, r.end.y - 70), d.color)
		draw_rect(Rect2(r.position.x, r.end.y - 72, r.size.x, 72), Color(0, 0, 0, 0.7))
		var sides := []
		for s in [0, 1]:
			if cursor[s] == i and (mode == "versus" or s == 0 or picked[0]):
				sides.append(s)
		for s in sides:
			var c := Color("#ff5050") if s == 0 else Color("#4a9cff")
			draw_rect(r.grow(4 + s * 6), c, false, 4.0 if not picked[s] else 8.0)
		_text(Vector2(r.position.x, r.end.y - 34), d.display_name.to_upper(), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_text(Vector2(r.position.x, r.end.y - 10), d.archetype, 18, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var hint := "P1: A/D + J     P2: arrows + numpad 4" if mode == "versus" else "A/D to move, J to pick, U to go back"
	_text(Vector2(0, 600), hint, 20, Color(1, 1, 1, 0.6))
	var stage_id := Stage.pick_id(roster[cursor[0]].id, roster[cursor[1]].id)
	_text(Vector2(0, 640), "Stage: %s" % Stage.STAGES[stage_id], 20, Color(1, 1, 1, 0.6))


func _draw_online() -> void:
	_text(Vector2(0, 120), "ONLINE", 48, Color("#fff2a8"))
	_text(Vector2(0, 165), "Playing as %s" % roster[cursor[0]].display_name.to_upper(), 22, Color(1, 1, 1, 0.7))
	if entering_code:
		_text(Vector2(0, 330), "Type the room code, then Enter", 26)
		_text(Vector2(0, 420), (code_entry + "____").left(4), 72, Color("#4ac3ff"))
		return
	if online.state == Online.State.IDLE:
		for i in ONLINE_ITEMS.size():
			_item(i, ONLINE_ITEMS[i])
		if online_status != "":
			_text(Vector2(0, 560), online_status, 22, Color("#ff9090"))
		return
	if room_code != "" and online.state == Online.State.WAITING:
		_text(Vector2(0, 300), "Room code", 26, Color(1, 1, 1, 0.7))
		_text(Vector2(0, 390), room_code, 96, Color("#4ac3ff"))
		_text(Vector2(0, 450), "Send this code to your opponent", 22, Color(1, 1, 1, 0.7))
	else:
		var lines := online_status.split("\n")
		for i in lines.size():
			_text(Vector2(0, 340 + i * 40), lines[i], 30)
	_text(Vector2(0, 600), "U / Esc to cancel", 20, Color(1, 1, 1, 0.5))


func _draw_controls() -> void:
	_text(Vector2(0, 110), "CONTROLS", 48, Color("#fff2a8"))
	var rows := [
		["", "Player 1", "Player 2", "Gamepad"],
		["Move / jump / crouch", "W A S D", "Arrows", "Stick / D-pad"],
		["Light Punch", Controls.describe(1, "lp"), Controls.describe(2, "lp"), "X / Square"],
		["Heavy Punch", Controls.describe(1, "hp"), Controls.describe(2, "hp"), "Y / Triangle"],
		["Light Kick", Controls.describe(1, "lk"), Controls.describe(2, "lk"), "A / Cross"],
		["Heavy Kick", Controls.describe(1, "hk"), Controls.describe(2, "hk"), "B / Circle"],
		["Block", "Hold back", "Hold back", "Hold back"],
		["Throw", "LP + LK (close)", "LP + LK", "X + A"],
		["Super (1 bar)", "HP + HK", "HP + HK", "Y + B"],
		["Ultra (3 bars)", "Down + HP + HK", "Down + HP + HK", "Down + Y + B"],
		["Specials", "Forward/Down/Back + HP or HK", "(classic motions: +10% damage)", ""],
		["Pause", "Esc", "Esc", "Start"],
	]
	var cols := [120.0, 420.0, 680.0, 920.0]
	for r in rows.size():
		for c in 4:
			var col := Color("#fff2a8") if r == 0 or c == 0 else Color.WHITE
			_text(Vector2(cols[c], 170 + r * 36), rows[r][c], 20, col, HORIZONTAL_ALIGNMENT_LEFT, 300)
	_text(Vector2(0, 650), "Press J or Enter to go back", 20, Color(1, 1, 1, 0.6))
