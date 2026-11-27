extends Node
## Networking autoload ("Net"). Host = server (Godot ENet). Clients only talk to the
## server, so the server relays every player's state / profile / voice to everyone else.

signal status(text: String)
signal disconnected
signal state_received(id: int, head: Transform3D, lh: Transform3D, rh: Transform3D, lvl: float)
signal profile_received(id: int, pname: String, color: Color)
signal voice_received(id: int, pcm: PackedByteArray, rate: int)
signal player_left(id: int)

const PORT := 7777

var online := false
var profiles := {}   # peer id -> {"name": String, "color": Color}  (server side)
var my_name := "MONKEY"
var my_color := Color(0.55, 0.35, 0.2)
var _hooked := false


func _hook() -> void:
	if _hooked:
		return
	_hooked = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)


func local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var s: String = a
		if s.begins_with("192.168.") or s.begins_with("10.") or s.begins_with("172."):
			out.append(s)
	return out


func host() -> bool:
	leave()
	_hook()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 8) != OK:
		status.emit("Could not host (port busy?)")
		return false
	multiplayer.multiplayer_peer = peer
	online = true
	profiles[1] = {"name": my_name, "color": my_color}
	var ips := local_ips()
	status.emit("HOSTING - friends join with: " + (", ".join(ips) if ips.size() > 0 else "your Wi-Fi IP"))
	return true


func join(ip: String) -> bool:
	leave()
	_hook()
	var peer := ENetMultiplayerPeer.new()
	if ip.strip_edges().is_empty() or peer.create_client(ip.strip_edges(), PORT) != OK:
		status.emit("Bad address")
		return false
	multiplayer.multiplayer_peer = peer
	status.emit("Joining " + ip + " ...")
	return true


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	profiles.clear()
	disconnected.emit()


# ---------- connection events ----------

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		for pid in profiles:
			recv_profile.rpc_id(id, pid, profiles[pid]["name"], profiles[pid]["color"])
		status.emit("A player joined")


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		profiles.erase(id)
		recv_leave.rpc(id)
		player_left.emit(id)
		status.emit("A player left")


func _on_connected() -> void:
	online = true
	status.emit("Connected!")
	submit_profile.rpc_id(1, my_name, my_color)


func _on_failed() -> void:
	online = false
	status.emit("Could not connect")


func _on_server_lost() -> void:
	status.emit("Host left")
	leave()


# ---------- profile (name + colour) ----------

func send_profile() -> void:
	if not online:
		return
	if multiplayer.is_server():
		profiles[1] = {"name": my_name, "color": my_color}
		recv_profile.rpc(1, my_name, my_color)
	else:
		submit_profile.rpc_id(1, my_name, my_color)


@rpc("any_peer", "reliable")
func submit_profile(pname: String, color: Color) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = pname.substr(0, 14)
	profiles[id] = {"name": pname, "color": color}
	recv_profile.rpc(id, pname, color)
	profile_received.emit(id, pname, color)


@rpc("authority", "reliable")
func recv_profile(id: int, pname: String, color: Color) -> void:
	if id == multiplayer.get_unique_id():
		return
	profile_received.emit(id, pname, color)


@rpc("authority", "reliable")
func recv_leave(id: int) -> void:
	player_left.emit(id)


# ---------- pose + talking level ----------

func send_state(head: Transform3D, lh: Transform3D, rh: Transform3D, lvl: float) -> void:
	if not online:
		return
	if multiplayer.is_server():
		recv_state.rpc(1, head, lh, rh, lvl)
	else:
		submit_state.rpc_id(1, head, lh, rh, lvl)


@rpc("any_peer", "unreliable")
func submit_state(head: Transform3D, lh: Transform3D, rh: Transform3D, lvl: float) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	recv_state.rpc(id, head, lh, rh, lvl)
	state_received.emit(id, head, lh, rh, lvl)


@rpc("authority", "unreliable")
func recv_state(id: int, head: Transform3D, lh: Transform3D, rh: Transform3D, lvl: float) -> void:
	if id == multiplayer.get_unique_id():
		return
	state_received.emit(id, head, lh, rh, lvl)


# ---------- voice chat (8-bit mono PCM) ----------

func send_voice(pcm: PackedByteArray, rate: int) -> void:
	if not online:
		return
	if multiplayer.is_server():
		recv_voice.rpc(1, pcm, rate)
	else:
		submit_voice.rpc_id(1, pcm, rate)


@rpc("any_peer", "unreliable")
func submit_voice(pcm: PackedByteArray, rate: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	recv_voice.rpc(id, pcm, rate)
	voice_received.emit(id, pcm, rate)


@rpc("authority", "unreliable")
func recv_voice(id: int, pcm: PackedByteArray, rate: int) -> void:
	if id == multiplayer.get_unique_id():
		return
	voice_received.emit(id, pcm, rate)
