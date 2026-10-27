## Per-player input history: button press ages (for buffering and chords), double-tap dashes
## and motion detection. All state is saved/restored for rollback.
extends RefCounted

const B := preload("res://engine/input_bits.gd")
const R := preload("res://engine/rules.gd")

const HISTORY := 32
const AGE_CAP := 99

var history := PackedInt32Array()     # ring buffer of cleaned masks, newest at `head`
var head := 0
var current := 0
var previous := 0
var press_age := PackedInt32Array()   # frames since each bit was last pressed (AGE_CAP = never/consumed)
var dash_age := PackedInt32Array()    # [left, right]: frames since a double-tap was completed


func _init() -> void:
	reset()


func reset() -> void:
	history.resize(HISTORY)
	history.fill(0)
	head = 0
	current = 0
	previous = 0
	press_age.resize(8)
	press_age.fill(AGE_CAP)
	dash_age.resize(2)
	dash_age.fill(AGE_CAP)


## Feed one frame of input. While `frozen` (hit-stop, super flash) ages don't advance,
## so presses made during the freeze are still fresh when it ends.
func push(raw_mask: int, frozen: bool) -> void:
	var mask := B.clean(raw_mask)
	previous = current
	current = mask
	if not frozen:
		for i in 8:
			press_age[i] = mini(press_age[i] + 1, AGE_CAP)
		for i in 2:
			dash_age[i] = mini(dash_age[i] + 1, AGE_CAP)
	for i in 8:
		var bit := 1 << i
		if mask & bit and not previous & bit:
			if bit == B.LEFT or bit == B.RIGHT:
				var d := 0 if bit == B.LEFT else 1
				# The previous press of this direction is still in press_age: a double tap.
				if press_age[i] <= R.DASH_WINDOW:
					dash_age[d] = 0
			press_age[i] = 0
	head = (head + 1) % HISTORY
	history[head] = mask


func held(bits: int) -> bool:
	return current & bits == bits


func age(bit: int) -> int:
	return press_age[B.index(bit)]


func pressed(bit: int, window: int = R.INPUT_BUFFER) -> bool:
	return age(bit) <= window


## Both buttons pressed within the buffer, and close enough together to count as one input.
func chord(a: int, b: int) -> bool:
	var aa := age(a)
	var ab := age(b)
	return aa <= R.INPUT_BUFFER and ab <= R.INPUT_BUFFER and absi(aa - ab) <= R.CHORD_WINDOW


## Mark presses as used so one press can't start two moves.
func consume(bits: int) -> void:
	for i in 8:
		if bits & (1 << i):
			press_age[i] = AGE_CAP


func dashed(screen_dir: int) -> bool:
	return dash_age[0 if screen_dir < 0 else 1] <= 1


func consume_dash() -> void:
	dash_age.fill(AGE_CAP)


## Mask `frames_ago` frames back (0 = this frame).
func at(frames_ago: int) -> int:
	return history[(head - frames_ago + HISTORY * 2) % HISTORY]


## Directions in motion steps: "d" any down, "df"/"db" down diagonals, "f"/"b" forward/back
## without down. Steps must appear in order within MOTION_WINDOW frames.
func motion(steps: Array, facing: int) -> bool:
	var fwd := B.RIGHT if facing > 0 else B.LEFT
	var back := B.LEFT if facing > 0 else B.RIGHT
	var step := 0
	for ago in range(R.MOTION_WINDOW - 1, -1, -1):
		var m := at(ago)
		if _matches(steps[step], m, fwd, back):
			step += 1
			if step == steps.size():
				return true
	return false


static func _matches(step: String, m: int, fwd: int, back: int) -> bool:
	var down := m & B.DOWN != 0
	match step:
		"d": return down
		"df": return down and m & fwd != 0
		"db": return down and m & back != 0
		"f": return m & fwd != 0 and not down
		"b": return m & back != 0 and not down
	return false


func save() -> Array:
	return [history.duplicate(), head, current, previous, press_age.duplicate(), dash_age.duplicate()]


func restore(s: Array) -> void:
	history = s[0].duplicate()
	head = s[1]
	current = s[2]
	previous = s[3]
	press_age = s[4].duplicate()
	dash_age = s[5].duplicate()
