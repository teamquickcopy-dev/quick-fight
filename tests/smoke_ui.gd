## UI smoke test: boots the main scene, walks menus into each mode, runs fights for a few
## seconds of game time, opens pause. Fails (via tests/run.sh-style error grep) on script errors.
## Run: godot --headless --path client -s ../tests/smoke_ui.gd
extends SceneTree

var main
var frame := 0
var step := 0


func _initialize() -> void:
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		main._go(main.Screen.MODE)
	if frame == 10:
		_start("cpu")
	if frame == 400:
		_check("cpu")
		main.fight._open_menu("PAUSED", ["Resume", "Restart", "Character select", "Main menu"])
	if frame == 410:
		main.fight._menu_choose("Main menu")
	if frame == 420:
		_start("training")
	if frame == 430:
		main.fight.show_boxes = true
		main.fight.dummy_mode = 6
	if frame == 700:
		_check("training")
		main.fight._menu_choose("Character select")
	if frame == 710:
		_start("versus")
	if frame == 900:
		_check("versus")
		print("SMOKE OK")
		quit(0)
	return false


func _start(mode: String) -> void:
	main.mode = mode
	main.cursor = [0, 1]
	main.picked = [true, true]
	main._start_fight()
	# Headless frames run faster than real time; feed the fixed-tick loop directly.
	main.fight.set_process(false)
	_drive(mode)


func _drive(_mode: String) -> void:
	pass


func _check(mode: String) -> void:
	var f = main.fight
	for i in 240:
		f._tick()
		f._update_camera()
		f.queue_redraw()
	print("%s: phase %d, ticks %d, P1 %s hp %d, P2 %s hp %d" % [mode, f.sim.phase, f.ticks,
		f.sim.fighters[0].state_name(), f.sim.fighters[0].health, f.sim.fighters[1].state_name(), f.sim.fighters[1].health])
