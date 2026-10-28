## Loads fighter art (WebP files exported as-is, see tools/art/build_fighter.py) into textures at
## runtime, with a cache. Missing files return null, so fighters without art fall back to gray-box.
extends RefCounted

static var _cache := {}


static func texture(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.new()
		var err := img.load_webp_from_buffer(FileAccess.get_file_as_bytes(path))
		if err == OK:
			img.generate_mipmaps()   # smooth when drawn smaller than the source
			tex = ImageTexture.create_from_image(img)
		else:
			push_error("can't decode %s" % path)
	_cache[path] = tex
	return tex


## Source rect of a fighter's portrait that fills a `size`-shaped card, centred on the face.
static func portrait_region(data, tex: Texture2D, size: Vector2) -> Rect2:
	var focus := Vector2(0.5, 0.4)
	var rig_path := "res://fighters/%s/art/rig.json" % data.id
	if FileAccess.file_exists(rig_path):
		var cfg = JSON.parse_string(FileAccess.get_file_as_string(rig_path))
		if cfg is Dictionary and cfg.has("portrait_focus"):
			focus = Vector2(cfg.portrait_focus[0], cfg.portrait_focus[1])
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var w := minf(tw, th * size.x / size.y)
	var h := minf(th, tw * size.y / size.x)
	var x := clampf(focus.x * tw - w / 2.0, 0.0, tw - w)
	var y := clampf(focus.y * th - h / 2.0, 0.0, th - h)
	return Rect2(x, y, w, h)


## UI art for a fighter: "portrait", "face" or "expr_<name>". Null if the fighter has none.
static func ui(data, name: String) -> Texture2D:
	return texture("res://fighters/%s/art/%s.webp" % [data.id, name])
