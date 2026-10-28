## Online connection: signaling server (WebSocket) + one WebRTC peer connection with two data
## channels: "inputs" (unreliable, unordered: rollback packets) and "control" (reliable: menu
## messages like ready / rematch). Owned by main.gd so it survives between fights.
##
## Flow: connect_server() -> quick_match() / create_room() / join_room(code) -> "matched"
## (host makes the WebRTC offer) -> channels open -> ping a few times -> both players send
## "ready" with their fighter -> host sends "start" -> fight.
extends Node

signal status_changed(text: String)
signal room_code(code: String)
signal connected()                          # data channels open, ping measured
signal control_received(msg: Dictionary)
signal disconnected(reason: String)

const PROTOCOL_VERSION := 1
const PINGS_BEFORE_READY := 5
const CONNECT_TIMEOUT_MS := 20000

enum State { IDLE, SERVER, WAITING, NEGOTIATING, CONNECTED }

var state := State.IDLE
var is_host := false
var rtt_ms := 0.0
var server_url := ""
var _ws := WebSocketPeer.new()
var _ws_open := false
var _pending_request: Dictionary = {}
var _rtc: WebRTCPeerConnection
var _inputs: WebRTCDataChannel
var _control: WebRTCDataChannel
var _ice_servers: Array = []
var _pings_sent := 0
var _ping_samples: Array = []
var _matched_at := 0
var _input_handler: Callable                # (PackedByteArray) -> void, set by the fight
## Debug: extra one-way delay (ms) and loss added to outgoing input packets, to test bad
## connections on a good network. Set from the URL (?lag=75&loss=0.01) or the F10 key.
var added_lag_ms := 0
var added_loss := 0.0
var _delayed: Array = []                     # [send_at_ms, bytes]


func _ready() -> void:
	server_url = _default_server_url()
	if OS.has_feature("web"):
		var q: String = str(JavaScriptBridge.eval("location.search", true))
		for part in q.trim_prefix("?").split("&"):
			var kv := part.split("=")
			if kv.size() != 2:
				continue
			match kv[0]:
				"server": server_url = kv[1].uri_decode()
				"lag": added_lag_ms = int(kv[1])
				"loss": added_loss = float(kv[1])


## Same origin as the page in production (Caddy proxies /ws); a local dev server otherwise.
static func _default_server_url() -> String:
	if OS.has_feature("web"):
		var proto: String = str(JavaScriptBridge.eval("location.protocol", true))
		var host: String = str(JavaScriptBridge.eval("location.host", true))
		if not host.begins_with("127.0.0.1") and not host.begins_with("localhost"):
			return ("wss://" if proto == "https:" else "ws://") + host + "/ws"
	var env := OS.get_environment("QF_SERVER")
	return env if env != "" else "ws://127.0.0.1:8000/ws"


static func webrtc_available() -> bool:
	return OS.has_feature("web") or ClassDB.class_exists("WebRTCLibPeerConnection")


# --- requests ----------------------------------------------------------------------------------

func quick_match() -> void:
	_request({"type": "quick_match"}, "Looking for an opponent…")


func create_room() -> void:
	_request({"type": "create_room"}, "Creating room…")


func join_room(code: String) -> void:
	_request({"type": "join_room", "code": code}, "Joining room %s…" % code.to_upper())


func _request(msg: Dictionary, status: String) -> void:
	leave()
	_pending_request = msg
	state = State.SERVER
	status_changed.emit("Connecting to server…")
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_ws = WebSocketPeer.new()
		var err := _ws.connect_to_url(server_url)
		if err != OK:
			_fail("Can't reach the server (%s)" % server_url)
			return
	_ws_open = false
	_matched_at = Time.get_ticks_msec()
	status_changed.emit(status)


## Leave the current match or queue, keeping the server connection.
func leave() -> void:
	if _control and _control.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		send_control({"type": "bye"})
	if _rtc:
		_rtc.close()
	_rtc = null
	_inputs = null
	_control = null
	_delayed.clear()
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws_send({"type": "leave"})
		_ws_send({"type": "cancel"})
	state = State.IDLE


func set_input_handler(handler: Callable) -> void:
	_input_handler = handler


func send_input(bytes: PackedByteArray) -> void:
	if _inputs == null or _inputs.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return
	if added_lag_ms > 0 or added_loss > 0.0:
		if randf() < added_loss:
			return
		_delayed.append([Time.get_ticks_msec() + added_lag_ms, bytes])
		return
	_inputs.put_packet(bytes)


func send_control(msg: Dictionary) -> void:
	if _control and _control.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		_control.put_packet(JSON.stringify(msg).to_utf8_buffer())


# --- polling -----------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_poll_server()
	_poll_rtc()


func _ws_send(msg: Dictionary) -> void:
	_ws.send_text(JSON.stringify(msg))


func _poll_server() -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if state == State.SERVER or state == State.WAITING:
			_fail("Can't reach the server")
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _ws_open:
		_ws_open = true
		if not _pending_request.is_empty():
			_ws_send(_pending_request)
			_pending_request = {}
	while _ws.get_available_packet_count() > 0:
		var msg = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
		if msg is Dictionary:
			_on_server(msg)
	if state == State.NEGOTIATING and Time.get_ticks_msec() - _matched_at > CONNECT_TIMEOUT_MS:
		_fail("Couldn't connect to the opponent")


func _on_server(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"queued":
			state = State.WAITING
			status_changed.emit("Looking for an opponent…")
		"room_created":
			state = State.WAITING
			room_code.emit(msg.code)
			status_changed.emit("Room code: %s\nWaiting for your opponent to join…" % msg.code)
		"matched":
			is_host = msg.role == "host"
			_ice_servers = msg.get("ice_servers", [])
			_start_rtc()
		"signal":
			_on_signal(msg.get("data", {}))
		"peer_left":
			if state != State.IDLE:
				_fail("Opponent left")
		"error":
			_fail({"room_not_found": "No room with that code", "message_too_large": "Network error"}.get(msg.reason, "Server error: %s" % msg.reason))


func _start_rtc() -> void:
	state = State.NEGOTIATING
	_matched_at = Time.get_ticks_msec()
	status_changed.emit("Opponent found. Connecting…")
	_rtc = WebRTCPeerConnection.new()
	var cfg := {"iceServers": _ice_servers}
	if _rtc.initialize(cfg) != OK:
		_fail("WebRTC isn't available here")
		return
	_rtc.session_description_created.connect(_on_description)
	_rtc.ice_candidate_created.connect(_on_candidate)
	# Negotiated channels: both sides create them with the same ids, no extra handshake.
	_inputs = _rtc.create_data_channel("inputs", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
	_control = _rtc.create_data_channel("control", {"negotiated": true, "id": 2})
	_pings_sent = 0
	_ping_samples.clear()
	if is_host:
		_rtc.create_offer()


func _on_description(kind: String, sdp: String) -> void:
	_rtc.set_local_description(kind, sdp)
	_ws_send({"type": "signal", "data": {"kind": kind, "sdp": sdp}})


func _on_candidate(media: String, index: int, cand: String) -> void:
	_ws_send({"type": "signal", "data": {"media": media, "index": index, "candidate": cand}})


func _on_signal(d: Dictionary) -> void:
	if _rtc == null:
		return
	if d.has("sdp"):
		_rtc.set_remote_description(d.kind, d.sdp)   # an offer makes us answer automatically
	elif d.has("candidate"):
		_rtc.add_ice_candidate(d.media, int(d.index), d.candidate)


func _poll_rtc() -> void:
	if _rtc == null:
		return
	_rtc.poll()
	var now := Time.get_ticks_msec()
	while not _delayed.is_empty() and _delayed[0][0] <= now:
		var item = _delayed.pop_front()
		if _inputs and _inputs.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			_inputs.put_packet(item[1])
	if _rtc.get_connection_state() == WebRTCPeerConnection.STATE_FAILED:
		_fail("Connection to the opponent failed")
		return
	if _rtc.get_connection_state() == WebRTCPeerConnection.STATE_DISCONNECTED and state == State.CONNECTED:
		_fail("Connection lost")
		return
	if _inputs:
		while _inputs.get_available_packet_count() > 0:
			var pkt := _inputs.get_packet()
			if _input_handler.is_valid():
				_input_handler.call(pkt)
	if _control:
		if state == State.NEGOTIATING and _control.get_ready_state() == WebRTCDataChannel.STATE_OPEN \
				and _inputs.get_ready_state() == WebRTCDataChannel.STATE_OPEN and _pings_sent == 0:
			status_changed.emit("Connected. Measuring ping…")
			_send_ping()
		while _control and _control.get_available_packet_count() > 0:
			var msg = JSON.parse_string(_control.get_packet().get_string_from_utf8())
			if msg is Dictionary:
				_on_control(msg)


func _send_ping() -> void:
	_pings_sent += 1
	send_control({"type": "ping", "t": Time.get_ticks_msec()})


func _on_control(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"ping":
			send_control({"type": "pong", "t": msg.t})
		"pong":
			_ping_samples.append(float(Time.get_ticks_msec() - int(msg.t)))
			if _pings_sent < PINGS_BEFORE_READY:
				_send_ping()
			elif state == State.NEGOTIATING:
				_ping_samples.sort()
				rtt_ms = _ping_samples[_ping_samples.size() / 2]   # without debug lag; see main.gd
				state = State.CONNECTED
				status_changed.emit("Connected (%d ms)" % rtt_ms)
				connected.emit()
		"bye":
			_fail("Opponent left")
		_:
			control_received.emit(msg)


func _fail(reason: String) -> void:
	var was := state
	if _rtc:
		_rtc.close()
	_rtc = null
	_inputs = null
	_control = null
	state = State.IDLE
	if was != State.IDLE:
		disconnected.emit(reason)
	status_changed.emit(reason)
