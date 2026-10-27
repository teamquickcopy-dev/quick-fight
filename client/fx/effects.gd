## Shared effects library, made once and used by every fighter: light/heavy hit sparks, block spark,
## counter flash, landing/dash dust, CMYK ink splash, shockwave ring, super flash, KO flash.
## Presentation only (its random numbers never touch the sim).
extends RefCounted

const CMYK := [Color("#00aeef"), Color("#ec008c"), Color("#fff200"), Color("#2b2b2b")]

var items: Array = []
var super_dim := 0           # frames of background dimming left (super flash)
var white_flash := 0.0       # KO flash, fades out
var rng := RandomNumberGenerator.new()


func clear() -> void:
	items.clear()
	super_dim = 0
	white_flash = 0.0


func _add(kind: String, pos: Vector2, life: int, color: Color, size: float, vel := Vector2.ZERO, text := "") -> void:
	items.append({"kind": kind, "pos": pos, "age": 0, "life": life, "color": color, "size": size,
			"vel": vel, "text": text, "rot": rng.randf() * TAU})


func hit(pos: Vector2, heavy: bool, counter: bool) -> void:
	var size := 46.0 if heavy else 28.0
	_add("spark", pos, 10 if heavy else 7, Color("#fff6c8"), size)
	if heavy:
		_add("ring", pos, 14, Color(1, 1, 1, 0.8), 70.0)
		ink(pos, 6)
	if counter:
		_add("ring", pos, 18, Color("#ff3b3b"), 90.0)


func block(pos: Vector2) -> void:
	_add("spark", pos, 8, Color("#8fd3ff"), 24.0)
	_add("ring", pos, 10, Color("#8fd3ff"), 40.0)


func armor(pos: Vector2) -> void:
	_add("ring", pos, 12, Color("#ffb347"), 60.0)


func ink(pos: Vector2, count: int) -> void:
	for i in count:
		var c: Color = CMYK[rng.randi_range(0, 3)]
		var v := Vector2(rng.randf_range(-6, 6), rng.randf_range(-9, -2))
		_add("ink", pos, rng.randi_range(18, 30), c, rng.randf_range(5, 11), v)


func dust(feet: Vector2, count := 4) -> void:
	for i in count:
		var v := Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-1.2, -0.2))
		_add("dust", feet + Vector2(rng.randf_range(-20, 20), 0), rng.randi_range(14, 22), Color(0.8, 0.78, 0.72, 0.5), rng.randf_range(8, 14), v)


func shockwave(pos: Vector2) -> void:
	_add("ring", pos, 20, Color(1, 1, 1, 0.9), 160.0)


func label(pos: Vector2, text: String, color: Color) -> void:
	_add("text", pos, 40, color, 28.0, Vector2(0, -0.8), text)


func super_flash(frames: int) -> void:
	super_dim = frames + 6


func ko_flash() -> void:
	white_flash = 1.0


func tick() -> void:
	for it in items:
		it.age += 1
		it.pos += it.vel
		if it.kind == "ink":
			it.vel.y += 0.5
	items = items.filter(func(it): return it.age < it.life)
	super_dim = maxi(super_dim - 1, 0)
	white_flash = maxf(white_flash - 0.06, 0.0)


## World-space effects, drawn with the camera offset.
func draw(ci: CanvasItem, offset: Vector2, font: Font) -> void:
	for it in items:
		var t: float = float(it.age) / it.life
		var p: Vector2 = it.pos + offset
		var c: Color = it.color
		match it.kind:
			"spark":
				var r: float = it.size * (0.5 + t)
				c.a = 1.0 - t
				for i in 8:
					var a: float = it.rot + i * TAU / 8.0
					var inner := r * 0.3
					ci.draw_line(p + Vector2.from_angle(a) * inner, p + Vector2.from_angle(a) * r, c, 4.0 * (1.0 - t) + 1.0)
				ci.draw_circle(p, it.size * 0.35 * (1.0 - t), Color(1, 1, 1, 1.0 - t))
			"ring":
				c.a *= 1.0 - t
				ci.draw_arc(p, it.size * (0.2 + t), 0, TAU, 40, c, 5.0 * (1.0 - t) + 1.0)
			"ink":
				c.a = 1.0 - t * t
				ci.draw_circle(p, it.size * (1.0 - t * 0.5), c)
			"dust":
				c.a *= 1.0 - t
				ci.draw_circle(p, it.size * (0.6 + t), c)
			"text":
				c.a = 1.0 - t * t
				ci.draw_string_outline(font, p - Vector2(80, 0), it.text, HORIZONTAL_ALIGNMENT_CENTER, 160, int(it.size), 8, Color(0, 0, 0, c.a))
				ci.draw_string(font, p - Vector2(80, 0), it.text, HORIZONTAL_ALIGNMENT_CENTER, 160, int(it.size), c)
