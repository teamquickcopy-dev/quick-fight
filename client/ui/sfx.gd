## Sound effects (autoload "Sfx"): the cartoon sounds in sfx/*.ogg, made by tools/audio/make_sfx.py.
## Sfx.play("hit_heavy") from anywhere. A small pool of players lets sounds overlap; each play gets
## a slightly random pitch so repeated hits don't sound the same. Presentation only.
extends Node

const VOICES := 10
const SAME_SOUND_GAP_MS := 35    # the same sound asked for twice this close together plays once

var muted := false
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func _stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var path := "res://sfx/%s.ogg" % name
		_streams[name] = AudioStreamOggVorbis.load_from_buffer(FileAccess.get_file_as_bytes(path)) \
				if FileAccess.file_exists(path) else null
	return _streams[name]


## `volume` in dB; `jitter` = random pitch spread (0.08 = +-8%).
func play(name: String, volume := 0.0, jitter := 0.06, pitch := 1.0) -> void:
	if muted:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -1000)) < SAME_SOUND_GAP_MS:
		return
	_last[name] = now
	var s := _stream(name)
	if s == null:
		return
	# Use a free voice, otherwise the oldest one.
	var p: AudioStreamPlayer = null
	for i in VOICES:
		var cand := _players[(_next + i) % VOICES]
		if not cand.playing:
			p = cand
			break
	if p == null:
		p = _players[_next]
	_next = (_players.find(p) + 1) % VOICES
	p.stream = s
	p.volume_db = volume
	p.pitch_scale = pitch * (1.0 + randf_range(-jitter, jitter))
	p.play()
