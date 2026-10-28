## Rollback netcode session for one online match (GGPO-style), independent of the transport.
##
## Each tick the game calls advance(local_input). Local input is scheduled `input_delay` frames
## ahead; the opponent's input is predicted (repeat their last known input) until it arrives.
## When a real input differs from the prediction, the sim is restored to that frame and
## re-simulated up to now. Packets carry every input the other side hasn't acknowledged, so
## lost packets don't matter. The side that runs ahead slows down a little so both stay level.
## Every CHECKSUM_INTERVAL confirmed frames both sides exchange a state fingerprint to detect desyncs.
##
## Transport: call receive(bytes) for every packet that arrives, and send the packets that
## take_outgoing() returns (unreliable, unordered is fine).
extends RefCounted

const MatchSim := preload("res://engine/match_sim.gd")

enum { PKT_INPUT = 1, PKT_PING = 2, PKT_PONG = 3, PKT_CHECKSUM = 4 }

const MAX_ROLLBACK := 10         # frames we may run ahead of the opponent's last confirmed input
const MAX_INPUTS_PER_PACKET := 64
const CHECKSUM_INTERVAL := 30
const PING_INTERVAL_MS := 500
const SYNC_WINDOW := 40          # frames of advantage samples averaged for time sync

var sim: MatchSim
var local := 0                   # our player index (0 or 1)
var input_delay := 2
var frame := 0                   # next frame to simulate
var clock: Callable              # () -> int milliseconds

var _local_inputs := {}          # frame -> mask (scheduled)
var _remote_inputs := {}         # frame -> mask (confirmed)
var _predicted := {}             # frame -> mask we used for the opponent
var _states := {}                # frame -> sim state saved before simulating that frame
var _last_remote := -1           # highest frame with every remote input up to it confirmed
var _last_remote_mask := 0
var _remote_ack := -1            # highest local frame the opponent has confirmed
var _rollback_from := -1         # earliest mispredicted frame waiting to be corrected
var _outgoing: Array = []
var _remote_frame := 0           # opponent's frame as of their last packet
var _adv_samples: Array = []
var _skip_credit := 0.0
var _last_ping_ms := -100000
var _pending_sums := {}          # frame -> checksum, not yet confirmed
var _local_checksums := {}       # frame -> checksum (confirmed frames only)
var _remote_checksums := {}

## Measured round-trip time (ms), smoothed.
var rtt_ms := 0.0
var desync_frame := -1
## Stats for the gate test and the HUD.
var stats := {"rollbacks": 0, "rollback_frames": 0, "max_rollback": 0, "stalls": 0, "skips": 0,
		"packets_in": 0, "packets_out": 0}


func _init(match_sim: MatchSim, local_player: int, delay: int, clock_fn: Callable) -> void:
	sim = match_sim
	local = local_player
	input_delay = delay
	clock = clock_fn
	# The first `delay` frames have no input on either side; both peers agree on that.
	for f in input_delay:
		_local_inputs[f] = 0
		_remote_inputs[f] = 0
	_last_remote = input_delay - 1


## Input delay for a measured round trip: hide most of the trip with rollback, the rest with delay.
## Leaving ~2 frames to rollback keeps corrections small and leaves headroom for jitter and loss
## (browser tests at 150-200 ms stalled about once a second with one frame less).
static func delay_for_rtt(rtt: float) -> int:
	var one_way_frames := rtt / 2.0 / (1000.0 / 60.0)
	return clampi(int(ceil(one_way_frames)) - 2, 1, 5)


## One display tick. Returns the presentation events of every frame simulated this tick
## (each tagged with "frame"), or an empty array if we had to wait for the opponent.
func advance(local_mask: int) -> Array:
	var events := []
	_maybe_ping()
	# Time sync: if we're ahead of the opponent, skip an occasional tick so they catch up.
	if _should_skip():
		stats.skips += 1
		_send_inputs()
		return events
	# Never predict further ahead than we can roll back.
	if frame - _last_remote > MAX_ROLLBACK:
		stats.stalls += 1
		_send_inputs()
		return events
	_local_inputs[frame + input_delay] = local_mask
	events.append_array(_apply_rollback())
	events.append_array(_simulate_frame())
	_finalize_checksums()
	_send_inputs()
	return events


func _simulate_frame() -> Array:
	_states[frame] = sim.save_state()
	var remote_mask: int
	if _remote_inputs.has(frame):
		remote_mask = _remote_inputs[frame]
	else:
		remote_mask = _last_remote_mask
		_predicted[frame] = remote_mask
	var mine: int = _local_inputs.get(frame, 0)
	if local == 0:
		sim.step(mine, remote_mask)
	else:
		sim.step(remote_mask, mine)
	var events := []
	for e in sim.events:
		var tagged: Dictionary = e.duplicate()
		tagged.frame = frame
		events.append(tagged)
	frame += 1
	_record_checksum()
	_forget_old()
	return events


func _apply_rollback() -> Array:
	if _rollback_from < 0:
		return []
	var target := frame
	var from := _rollback_from
	_rollback_from = -1
	if not _states.has(from):
		push_error("rollback: no saved state for frame %d" % from)
		return []
	sim.load_state(_states[from])
	frame = from
	var depth := target - from
	stats.rollbacks += 1
	stats.rollback_frames += depth
	stats.max_rollback = maxi(stats.max_rollback, depth)
	var events := []
	while frame < target:
		events.append_array(_simulate_frame())
	return events


## Remember the checksum of every CHECKSUM_INTERVAL-th frame as it is (re)simulated.
func _record_checksum() -> void:
	var f := frame - 1
	if f % CHECKSUM_INTERVAL == 0 and not _local_checksums.has(f):
		_pending_sums[f] = sim.checksum().substr(0, 8).hex_to_int()


## A frame's state is final once the opponent's inputs up to it are confirmed (and any rollback
## they caused has been applied): send its checksum then.
func _finalize_checksums() -> void:
	for f in _pending_sums.keys():
		if f > _last_remote or f >= frame:
			continue
		var sum: int = _pending_sums[f]
		_pending_sums.erase(f)
		_local_checksums[f] = sum
		_compare_checksum(f)
		var buf := StreamPeerBuffer.new()
		buf.put_u8(PKT_CHECKSUM)
		buf.put_u32(f)
		buf.put_u32(sum)
		_outgoing.append(buf.data_array)


func _compare_checksum(f: int) -> void:
	if _local_checksums.has(f) and _remote_checksums.has(f) and _local_checksums[f] != _remote_checksums[f]:
		if desync_frame < 0:
			desync_frame = f
			push_error("DESYNC at frame %d" % f)


func _forget_old() -> void:
	var keep_from := mini(_last_remote, frame - 1) - 2
	for f in _states.keys():
		if f < keep_from:
			_states.erase(f)
	for f in _predicted.keys():
		if f <= _last_remote:
			_predicted.erase(f)
	for f in _local_inputs.keys():
		if f <= _remote_ack and f < frame - MAX_ROLLBACK:
			_local_inputs.erase(f)
	for f in _remote_inputs.keys():
		if f < frame - MAX_ROLLBACK - 2:
			_remote_inputs.erase(f)


# --- time sync ---------------------------------------------------------------------------------

func _should_skip() -> bool:
	if _adv_samples.size() < SYNC_WINDOW / 2:
		return false
	var total := 0.0
	for s in _adv_samples:
		total += s
	var avg: float = total / _adv_samples.size()
	# Both sides measure their own advantage; only the one ahead by more than a frame slows down.
	if avg <= 1.0:
		_skip_credit = 0.0
		return false
	_skip_credit += minf((avg - 1.0) / 8.0, 0.25)   # gentle: at most one skip every 4 ticks
	if _skip_credit >= 1.0:
		_skip_credit -= 1.0
		_adv_samples.clear()
		return true
	return false


# --- packets -----------------------------------------------------------------------------------

func take_outgoing() -> Array:
	var out := _outgoing
	_outgoing = []
	stats.packets_out += out.size()
	return out


func _send_inputs() -> void:
	var latest := frame - 1 + input_delay
	var start := maxi(_remote_ack + 1, 0)
	start = maxi(start, latest - MAX_INPUTS_PER_PACKET + 1)
	var buf := StreamPeerBuffer.new()
	buf.put_u8(PKT_INPUT)
	buf.put_32(frame)
	buf.put_32(_last_remote)
	buf.put_32(start)
	var count := maxi(latest - start + 1, 0)
	buf.put_u8(count)
	for f in range(start, start + count):
		buf.put_u8(_local_inputs.get(f, 0))
	_outgoing.append(buf.data_array)


func _maybe_ping() -> void:
	var now: int = clock.call()
	if now - _last_ping_ms < PING_INTERVAL_MS:
		return
	_last_ping_ms = now
	var buf := StreamPeerBuffer.new()
	buf.put_u8(PKT_PING)
	buf.put_u32(now)
	_outgoing.append(buf.data_array)


func receive(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	stats.packets_in += 1
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	match buf.get_u8():
		PKT_INPUT:
			_receive_inputs(buf)
		PKT_PING:
			var t := buf.get_u32()
			var reply := StreamPeerBuffer.new()
			reply.put_u8(PKT_PONG)
			reply.put_u32(t)
			_outgoing.append(reply.data_array)
		PKT_PONG:
			var sample := float(int(clock.call()) - int(buf.get_u32()))
			rtt_ms = sample if rtt_ms == 0.0 else lerpf(rtt_ms, sample, 0.2)
		PKT_CHECKSUM:
			var f := buf.get_u32()
			_remote_checksums[f] = buf.get_u32()
			_compare_checksum(f)


func _receive_inputs(buf: StreamPeerBuffer) -> void:
	var their_frame := buf.get_32()
	var their_ack := buf.get_32()
	var start := buf.get_32()
	var count := buf.get_u8()
	_remote_ack = maxi(_remote_ack, their_ack)
	if their_frame > _remote_frame:
		_remote_frame = their_frame
	for i in count:
		var f := start + i
		var mask := buf.get_u8()
		if f <= _last_remote or _remote_inputs.has(f):
			continue
		_remote_inputs[f] = mask
		if _predicted.has(f) and _predicted[f] != mask and f < frame:
			_rollback_from = f if _rollback_from < 0 else mini(_rollback_from, f)
	while _remote_inputs.has(_last_remote + 1):
		_last_remote += 1
		_last_remote_mask = _remote_inputs[_last_remote]
	# Frame advantage: how far ahead we are of where the opponent is now (their frame + half the trip).
	var half_trip := rtt_ms / 2.0 / (1000.0 / 60.0)
	_adv_samples.append(float(frame) - (float(their_frame) + half_trip))
	while _adv_samples.size() > SYNC_WINDOW:
		_adv_samples.pop_front()
