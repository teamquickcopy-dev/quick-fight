## Prints a frame-by-frame trace of a scripted input sequence (debug helper, not a test).
extends RefCounted
var t

func trace(sim, p0: Array, p1: Array, frames: int) -> void:
	for i in frames:
		sim.step(p0[i] if i < p0.size() else 0, p1[i] if i < p1.size() else 0)
		var a = sim.fighters[0]
		var b = sim.fighters[1]
		var ev: Array = sim.events.map(func(e): return e.t + ("(" + e.move + ")" if e.has("move") else ""))
		print("%3d frz=%d | A %-9s mv=%-16s mf=%2d conn=%d x=%d | B %-9s stun=%2d x=%d | %s" % [i, sim.freeze,
			a.state_name(), a.cur_move().get("name", "-"), a.move_frame, a.connected, a.x / 100,
			b.state_name(), b.stun, b.x / 100, ev])
