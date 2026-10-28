## Screen flow: Title -> Mode -> (CPU level) -> Character select -> Fight -> results.
## Menus work with either player's controls (LP confirm, LK back), Enter/Esc, or tap/click.
extends Node2D

const FD := preload("res://engine/fighter_data.gd")
const Cpu := preload("res://engine/cpu.gd")
const FightScreen := preload("res://ui/fight_screen.gd")
const BoxRig := preload("res://fighters/_graybox/box_rig.gd")
const Fighter := preload("res://engine/fighter.gd")

enum Screen { TITLE, MODE, LEVEL, SELECT, CONTROLS, FIGHT }

const MODES := [
	["Versus CPU", "cpu"], ["Versus 2P", "versus"], ["Training", "training"], ["Controls", "controls"],
]

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


func _ready() -> void:
	font = ThemeDB.fallback_font
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
	return OS.has_feature("web") and JavaScriptBridge.eval("window.qfStartPressed === true", true) == true


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


## In 2P both players pick at once with their own controls; otherwise P1 picks both sides.
func _select_input() -> void:
	var n := roster.size()
	if n == 0:
		return
	if mode == "versus":
		for p in [0, 1]:
			_cursor_input(p, p + 1)
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
	match action:
		"rematch":
			_start_fight()
		"select":
			_go(Screen.SELECT)
		_:
			_go(Screen.MODE)
	queue_redraw()


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
					if picked[0] and picked[1]:
						_start_fight()


# --- drawing -----------------------------------------------------------------------------------

func _item_rect(i: int) -> Rect2:
	return Rect2(440, 270 + i * 64, 400, 52)


func _card_rect(i: int) -> Rect2:
	var n := roster.size()
	var w := 220.0
	var gap := 30.0
	var x0 := 640.0 - (n * w + (n - 1) * gap) / 2.0
	return Rect2(x0 + i * (w + gap), 180, w, 340)


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
		var sides := []
		for s in [0, 1]:
			if cursor[s] == i and (mode == "versus" or s == 0 or picked[0]):
				sides.append(s)
		for s in sides:
			var c := Color("#ff5050") if s == 0 else Color("#4a9cff")
			draw_rect(r.grow(4 + s * 6), c, false, 4.0 if not picked[s] else 8.0)
		BoxRig.draw(self, preview[i], Vector2(r.get_center().x, r.end.y - 70), d.color)
		_text(Vector2(r.position.x, r.end.y - 34), d.display_name.to_upper(), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_text(Vector2(r.position.x, r.end.y - 10), d.archetype, 18, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var hint := "P1: A/D + J     P2: arrows + numpad 4" if mode == "versus" else "A/D to move, J to pick, U to go back"
	_text(Vector2(0, 600), hint, 20, Color(1, 1, 1, 0.6))
	_text(Vector2(0, 640), "Stage: Gray Box", 20, Color(1, 1, 1, 0.6))


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
