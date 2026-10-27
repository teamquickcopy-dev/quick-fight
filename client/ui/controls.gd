## Keyboard / gamepad bindings, turned into one input mask per player per tick.
## The sim never reads devices: the fight screen calls mask() and passes the result in, which is
## what lets online play later swap in masks from the network layer.
## Bindings are InputMap actions (p1_up, p1_lp, ...) so the Settings screen can remap them later.
extends Node

const B := preload("res://engine/input_bits.gd")

const BITS := {
	"up": B.UP, "down": B.DOWN, "left": B.LEFT, "right": B.RIGHT,
	"lp": B.LP, "hp": B.HP, "lk": B.LK, "hk": B.HK,
}

const KEYS := {
	1: {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D,
		"lp": KEY_J, "hp": KEY_K, "lk": KEY_U, "hk": KEY_I},
	2: {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"lp": KEY_KP_4, "hp": KEY_KP_5, "lk": KEY_KP_7, "hk": KEY_KP_8},
}

## Layout from the design doc: X/Square = LP, Y/Triangle = HP, A/Cross = LK, B/Circle = HK.
const PAD_BUTTONS := {
	"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT,
	"right": JOY_BUTTON_DPAD_RIGHT, "lp": JOY_BUTTON_X, "hp": JOY_BUTTON_Y, "lk": JOY_BUTTON_A,
	"hk": JOY_BUTTON_B,
}
const PAD_AXES := {
	"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0],
	"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
}
const STICK_DEADZONE := 0.5


func _ready() -> void:
	for p in [1, 2]:
		for name in BITS:
			var action := "p%d_%s" % [p, name]
			if not InputMap.has_action(action):
				InputMap.add_action(action, STICK_DEADZONE)
			var key := InputEventKey.new()
			key.physical_keycode = KEYS[p][name]
			InputMap.action_add_event(action, key)
			var btn := InputEventJoypadButton.new()
			btn.device = p - 1
			btn.button_index = PAD_BUTTONS[name]
			InputMap.action_add_event(action, btn)
			if PAD_AXES.has(name):
				var ax := InputEventJoypadMotion.new()
				ax.device = p - 1
				ax.axis = PAD_AXES[name][0]
				ax.axis_value = PAD_AXES[name][1]
				InputMap.action_add_event(action, ax)
	_add("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_add("menu_accept", [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER], [])
	_add("menu_back", [KEY_BACKSPACE], [JOY_BUTTON_BACK])


func _add(action: String, keys: Array, pad: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in pad:
		for dev in [0, 1]:
			var e := InputEventJoypadButton.new()
			e.device = dev
			e.button_index = b
			InputMap.action_add_event(action, e)


## Current input mask for player 1 or 2 (screen directions).
func mask(p: int) -> int:
	var m := 0
	for name in BITS:
		if Input.is_action_pressed("p%d_%s" % [p, name]):
			m |= BITS[name]
	return m


## Menu helpers: either player's controls navigate, LP confirms, LK goes back.
func menu(action: String, p := 0) -> bool:
	var players := [1, 2] if p == 0 else [p]
	for i in players:
		match action:
			"accept":
				if Input.is_action_just_pressed("p%d_lp" % i):
					return true
			"back":
				if Input.is_action_just_pressed("p%d_lk" % i):
					return true
			_:
				if Input.is_action_just_pressed("p%d_%s" % [i, action]):
					return true
	if p != 2:
		if action == "accept" and Input.is_action_just_pressed("menu_accept"):
			return true
		if action == "back" and (Input.is_action_just_pressed("menu_back") or Input.is_action_just_pressed("pause")):
			return true
	return false


## Human-readable binding for the controls screen.
func describe(p: int, name: String) -> String:
	return OS.get_keycode_string(KEYS[p][name])
