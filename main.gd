extends Node3D
## Monkey Backrooms VR - everything is built from code so the project has no binary assets.
##
## Locomotion (gorilla style): touch a surface with a hand and pull/push - your body moves
## opposite to your hand and keeps its momentum when you let go.
## Fallbacks: left stick walks, right stick snap-turns.
## Point at the lobby computer with either controller and pull the trigger.

const BACK_ORIGIN := Vector3(200, 0, 0)   # backrooms live far away from the lobby, same scene
const CELL := 4.0
const MAZE_N := 12
const WALL_H := 3.0
const HAND_R := 0.09
const MAZE_SEED := 1337                    # same seed on every device = same maze
const TALK_THRESHOLD := 0.02

# --- player rig ---
var rig: CharacterBody3D
var origin: XROrigin3D
var cam: XRCamera3D
var ctrl := {}
var rays := {}
var lasers := {}
var hand_mats: Array = []
var prev_hand := {}
var vel := Vector3.ZERO
var snap_cd := 0.0
var query: PhysicsShapeQueryParameters3D

# --- multiplayer / voice ---
var monkeys := {}                          # peer id -> Monkey
var preview: Monkey
var speaker := -1                          # -1 nobody, 0 me, >0 remote peer id
var local_lvl := 0.0
var local_talk_until := 0.0
var send_t := 0.0
var cap: AudioEffectCapture
var mic_player: AudioStreamPlayer

# --- lobby computer state ---
var rgb := [140, 90, 50]
var name_text := "MONKEY"
var ip_text := "192.168."
var typing := "name"
var chan_labels: Array = [null, null, null]
var swatch_mat := StandardMaterial3D.new()
var name_btn: Area3D
var ip_btn: Area3D
var status_label: Label3D
var light_mat := StandardMaterial3D.new()


func _ready() -> void:
	_setup_xr()
	_setup_env()
	_build_lobby()
	_build_backrooms()
	_build_rig()
	_setup_mic()
	Net.status.connect(_on_status)
	Net.disconnected.connect(_on_disconnected)
	Net.state_received.connect(_on_state)
	Net.profile_received.connect(_on_profile)
	Net.voice_received.connect(_on_voice)
	Net.player_left.connect(_on_left)
	_apply_profile()


# ====================================================================== setup

func _setup_xr() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
	else:
		push_warning("OpenXR not initialised - running flat (no controllers).")


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.97, 0.85)
	env.ambient_light_energy = 0.9
	we.environment = env
	add_child(we)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material, collide := true) -> Node3D:
	var holder: Node3D
	if collide:
		holder = StaticBody3D.new()
	else:
		holder = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	holder.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		holder.add_child(cs)
	holder.position = pos
	parent.add_child(holder)
	return holder


func _label(parent: Node, pos: Vector3, text: String, size := 48, color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.002
	l.position = pos
	l.modulate = color
	l.outline_size = 6
	parent.add_child(l)
	return l


## Pointable 3D button. Faces +Z. Trigger-clicking it calls `cb`.
func _button(parent: Node, pos: Vector3, size: Vector2, text: String, cb: Callable,
		color := Color(0.2, 0.25, 0.32), font_px := 44) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 2
	a.collision_mask = 0
	a.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, size.y, 0.12)
	cs.shape = bs
	a.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y, 0.04)
	mi.mesh = bm
	mi.material_override = _mat(color)
	a.add_child(mi)
	var lb := Label3D.new()
	lb.name = "Text"
	lb.text = text
	lb.font_size = font_px
	lb.pixel_size = 0.002
	lb.outline_size = 4
	lb.position = Vector3(0, 0, 0.025)
	a.add_child(lb)
	a.set_meta("action", cb)
	parent.add_child(a)
	return a


# ====================================================================== lobby

func _build_lobby() -> void:
	var root := Node3D.new()
	root.name = "Lobby"
	add_child(root)
	var floor_m := _mat(Color(0.33, 0.36, 0.4))
	var wall_m := _mat(Color(0.5, 0.56, 0.66))
	var ceil_m := _mat(Color(0.8, 0.8, 0.86))
	_box(root, Vector3(12.4, 0.2, 12.4), Vector3(0, -0.1, 0), floor_m)
	_box(root, Vector3(12.4, 0.2, 12.4), Vector3(0, 4.1, 0), ceil_m)
	_box(root, Vector3(12.4, 4.2, 0.2), Vector3(0, 2, -6.1), wall_m)
	_box(root, Vector3(12.4, 4.2, 0.2), Vector3(0, 2, 6.1), wall_m)
	_box(root, Vector3(0.2, 4.2, 12.4), Vector3(-6.1, 2, 0), wall_m)
	_box(root, Vector3(0.2, 4.2, 12.4), Vector3(6.1, 2, 0), wall_m)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color.WHITE
	lamp.emission_enabled = true
	lamp.emission = Color(1, 1, 1)
	for x in [-3.0, 3.0]:
		for z in [-3.0, 3.0]:
			_box(root, Vector3(1.6, 0.05, 1.6), Vector3(x, 3.97, z), lamp, false)
	_build_ui(root)
	preview = Monkey.new()
	root.add_child(preview)


func _build_ui(parent: Node) -> void:
	# screen backdrop on the north wall
	_box(parent, Vector3(5.0, 3.2, 0.1), Vector3(0, 1.55, -5.5), _mat(Color(0.03, 0.05, 0.08)))
	var z := -5.4
	_label(parent, Vector3(-0.8, 2.95, z), "MONKEY COMPUTER", 72, Color(0.5, 1.0, 0.6))

	# RGB sliders (-/+ buttons)
	var chans := ["R", "G", "B"]
	for i in 3:
		var y := 2.55 - i * 0.3
		_button(parent, Vector3(-1.5, y, z), Vector2(0.28, 0.24), "-", _chg.bind(i, -16), Color(0.5, 0.15, 0.15))
		chan_labels[i] = _label(parent, Vector3(-0.75, y, z), chans[i] + " 000", 48)
		_button(parent, Vector3(0.0, y, z), Vector2(0.28, 0.24), "+", _chg.bind(i, 16), Color(0.15, 0.5, 0.2))
	# colour swatch
	_box(parent, Vector3(0.7, 0.7, 0.03), Vector3(0.85, 2.25, z - 0.01), swatch_mat, false)

	# name / ip fields
	name_btn = _button(parent, Vector3(-0.95, 1.65, z), Vector2(1.5, 0.3), "", _select.bind("name"), Color(0.2, 0.3, 0.2), 38)
	ip_btn = _button(parent, Vector3(0.65, 1.65, z), Vector2(1.5, 0.3), "", _select.bind("ip"), Color(0.2, 0.25, 0.32), 38)

	# actions
	_button(parent, Vector3(1.9, 2.55, z), Vector2(0.85, 0.3), "HOST", _do_host, Color(0.15, 0.45, 0.2))
	_button(parent, Vector3(1.9, 2.2, z), Vector2(0.85, 0.3), "JOIN", _do_join, Color(0.15, 0.3, 0.55))
	_button(parent, Vector3(1.9, 1.85, z), Vector2(0.85, 0.3), "ENTER\nBACKROOMS", _goto_backrooms, Color(0.6, 0.5, 0.1), 30)
	_button(parent, Vector3(1.9, 2.95, z), Vector2(0.6, 0.25), "LEAVE", _do_leave, Color(0.5, 0.15, 0.15), 32)
	status_label = _label(parent, Vector3(0, 0.07, z), "Set your name + colour, then HOST or JOIN", 36, Color(1, 0.9, 0.5))

	# keyboard
	var rows := ["1234567890.", "QWERTYUIOP", "ASDFGHJKL_", "ZXCVBNM"]
	var ys := [1.25, 0.93, 0.61, 0.29]
	for r in rows.size():
		var s: String = rows[r]
		var total := s.length() * 0.4
		for k in s.length():
			var x := -total / 2.0 + 0.2 + k * 0.4
			_button(parent, Vector3(x, ys[r], z), Vector2(0.34, 0.28), s[k], _key.bind(s[k]), Color(0.18, 0.2, 0.28), 44)
	_button(parent, Vector3(1.9, 0.29, z), Vector2(0.8, 0.28), "DEL", _del, Color(0.5, 0.2, 0.2), 40)


func _chg(i: int, delta: int) -> void:
	rgb[i] = clampi(rgb[i] + delta, 0, 255)
	_apply_profile()


func _select(which: String) -> void:
	typing = which
	_refresh_fields()


func _key(ch: String) -> void:
	if typing == "name":
		if name_text.length() < 12:
			name_text += ch
	else:
		if ip_text.length() < 15:
			ip_text += ch
	_apply_profile()


func _del() -> void:
	if typing == "name":
		name_text = name_text.substr(0, maxi(0, name_text.length() - 1))
	else:
		ip_text = ip_text.substr(0, maxi(0, ip_text.length() - 1))
	_apply_profile()


func _refresh_fields() -> void:
	name_btn.get_node("Text").text = "NAME: " + name_text + ("_" if typing == "name" else "")
	ip_btn.get_node("Text").text = "IP: " + ip_text + ("_" if typing == "ip" else "")
	(name_btn.get_node("Mesh") as MeshInstance3D).material_override.albedo_color = Color(0.2, 0.4, 0.2) if typing == "name" else Color(0.18, 0.2, 0.28)
	(ip_btn.get_node("Mesh") as MeshInstance3D).material_override.albedo_color = Color(0.2, 0.4, 0.2) if typing == "ip" else Color(0.18, 0.2, 0.28)


func _apply_profile() -> void:
	var col := Color8(rgb[0], rgb[1], rgb[2])
	Net.my_name = name_text if name_text != "" else "MONKEY"
	Net.my_color = col
	preview.set_profile(Net.my_name, col)
	for m in hand_mats:
		(m as StandardMaterial3D).albedo_color = col
	swatch_mat.albedo_color = col
	var chans := ["R", "G", "B"]
	for i in 3:
		(chan_labels[i] as Label3D).text = "%s %03d" % [chans[i], rgb[i]]
	_refresh_fields()
	Net.send_profile()


func _do_host() -> void:
	Net.my_name = name_text
	Net.host()


func _do_join() -> void:
	Net.join(ip_text)


func _do_leave() -> void:
	Net.leave()
	_on_status("Left the game")


func _goto_backrooms() -> void:
	rig.global_position = BACK_ORIGIN + Vector3(0, 0.05, 0)
	vel = Vector3.ZERO


func _goto_lobby() -> void:
	rig.global_position = Vector3(0, 0.05, 0)
	vel = Vector3.ZERO


func _on_status(text: String) -> void:
	if status_label:
		status_label.text = text


# ====================================================================== backrooms

func _wallpaper() -> StandardMaterial3D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for x in 32:
		for y in 32:
			var stripe := (x % 8) < 2
			img.set_pixel(x, y, Color(0.70, 0.62, 0.24) if stripe else Color(0.82, 0.74, 0.34))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	return m


func _gen_maze(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = MAZE_SEED
	# vw[i][j]: wall on the west side of cell (i,j); hw[i][j]: wall on the north side
	var vw: Array = []
	for i in range(n + 1):
		var col: Array = []
		for j in range(n):
			col.append(true)
		vw.append(col)
	var hw: Array = []
	for i in range(n):
		var col: Array = []
		for j in range(n + 1):
			col.append(true)
		hw.append(col)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var visited := {Vector2i(0, 0): true}
	var stack: Array = [Vector2i(0, 0)]
	while stack.size() > 0:
		var c: Vector2i = stack.back()
		var nb: Array = []
		for d in dirs:
			var q: Vector2i = c + d
			if q.x >= 0 and q.x < n and q.y >= 0 and q.y < n and not visited.has(q):
				nb.append(d)
		if nb.is_empty():
			stack.pop_back()
			continue
		var pick: Vector2i = nb[rng.randi() % nb.size()]
		_open_wall(vw, hw, c, pick)
		visited[c + pick] = true
		stack.append(c + pick)
	# knock out extra walls so it feels like open rooms, not just a maze
	for k in range(n * n / 3):
		var c2 := Vector2i(rng.randi() % n, rng.randi() % n)
		var d2: Vector2i = dirs[rng.randi() % 4]
		var q2 := c2 + d2
		if q2.x >= 0 and q2.x < n and q2.y >= 0 and q2.y < n:
			_open_wall(vw, hw, c2, d2)
	return [vw, hw]


func _open_wall(vw: Array, hw: Array, c: Vector2i, d: Vector2i) -> void:
	if d == Vector2i(1, 0):
		vw[c.x + 1][c.y] = false
	elif d == Vector2i(-1, 0):
		vw[c.x][c.y] = false
	elif d == Vector2i(0, 1):
		hw[c.x][c.y + 1] = false
	else:
		hw[c.x][c.y] = false


func _build_backrooms() -> void:
	var root := Node3D.new()
	root.name = "Backrooms"
	add_child(root)
	var wall_m := _wallpaper()
	var floor_m := _mat(Color(0.5, 0.45, 0.25))
	var ceil_m := _mat(Color(0.75, 0.72, 0.55))
	light_mat.albedo_color = Color(1, 1, 0.9)
	light_mat.emission_enabled = true
	light_mat.emission = Color(1, 0.98, 0.8)
	var span := MAZE_N * CELL
	var mid := BACK_ORIGIN + Vector3((MAZE_N - 1) * CELL / 2.0, 0, (MAZE_N - 1) * CELL / 2.0)
	_box(root, Vector3(span + 1, 0.2, span + 1), mid + Vector3(0, -0.1, 0), floor_m)
	_box(root, Vector3(span + 1, 0.2, span + 1), mid + Vector3(0, WALL_H + 0.1, 0), ceil_m)
	for i in MAZE_N:
		for j in MAZE_N:
			if (i + j) % 2 == 0:
				_box(root, Vector3(1.6, 0.05, 0.7), BACK_ORIGIN + Vector3(i * CELL, WALL_H - 0.03, j * CELL), light_mat, false)

	var maze := _gen_maze(MAZE_N)
	var vw: Array = maze[0]
	var hw: Array = maze[1]
	var vmesh := BoxMesh.new()
	vmesh.size = Vector3(0.3, WALL_H, CELL + 0.3)
	var vshape := BoxShape3D.new()
	vshape.size = vmesh.size
	var hmesh := BoxMesh.new()
	hmesh.size = Vector3(CELL + 0.3, WALL_H, 0.3)
	var hshape := BoxShape3D.new()
	hshape.size = hmesh.size
	for i in range(MAZE_N + 1):
		for j in range(MAZE_N):
			if vw[i][j]:
				_wall(root, vmesh, vshape, BACK_ORIGIN + Vector3((i - 0.5) * CELL, WALL_H / 2.0, j * CELL), wall_m)
	for i in range(MAZE_N):
		for j in range(MAZE_N + 1):
			if hw[i][j]:
				_wall(root, hmesh, hshape, BACK_ORIGIN + Vector3(i * CELL, WALL_H / 2.0, (j - 0.5) * CELL), wall_m)

	# way home: panel on the north wall of the spawn cell
	_button(root, BACK_ORIGIN + Vector3(0, 1.5, -CELL / 2.0 + 0.2), Vector2(1.3, 0.45), "BACK TO LOBBY", _goto_lobby, Color(0.5, 0.15, 0.15), 40)


func _wall(parent: Node, mesh: Mesh, shape: Shape3D, pos: Vector3, mat: Material) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	parent.add_child(sb)


# ====================================================================== player rig

func _build_rig() -> void:
	rig = CharacterBody3D.new()
	rig.collision_layer = 4
	rig.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap_shape := CapsuleShape3D.new()
	cap_shape.radius = 0.25
	cap_shape.height = 1.0
	cs.shape = cap_shape
	cs.position.y = 0.55
	rig.add_child(cs)
	add_child(rig)
	origin = XROrigin3D.new()
	rig.add_child(origin)
	cam = XRCamera3D.new()
	origin.add_child(cam)

	for side in ["l", "r"]:
		var c := XRController3D.new()
		c.tracker = "left_hand" if side == "l" else "right_hand"
		origin.add_child(c)
		ctrl[side] = c
		prev_hand[side] = null

		var hm := _mat(Color(0.55, 0.35, 0.2))
		hand_mats.append(hm)
		var hmesh := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		hmesh.mesh = sm
		hmesh.material_override = hm
		c.add_child(hmesh)

		var ray := RayCast3D.new()
		ray.target_position = Vector3(0, 0, -5)
		ray.collision_mask = 2
		ray.collide_with_areas = true
		ray.collide_with_bodies = false
		ray.enabled = true
		c.add_child(ray)
		rays[side] = ray

		var laser := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.004
		lm.bottom_radius = 0.004
		lm.height = 1.0
		laser.mesh = lm
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.4, 1.0, 0.7)
		lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		laser.material_override = lmat
		laser.rotation_degrees = Vector3(90, 0, 0)
		laser.visible = false
		c.add_child(laser)
		lasers[side] = laser

		c.button_pressed.connect(_on_button.bind(side))

	query = PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = HAND_R
	query.shape = sph
	query.collision_mask = 1
	rig.global_position = Vector3(0, 0.05, 0)


func _on_button(bname: String, side: String) -> void:
	if bname != "trigger_click":
		return
	var ray: RayCast3D = rays[side]
	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	var col := ray.get_collider()
	if col != null and col.has_meta("action"):
		var cb: Callable = col.get_meta("action")
		(ctrl[side] as XRController3D).trigger_haptic_pulse("haptic", 0.0, 0.6, 0.08, 0.0)
		var mi := col.get_node_or_null("Mesh") as MeshInstance3D
		if mi:
			mi.scale = Vector3(1, 1, 0.3)
			var tw := create_tween()
			tw.tween_property(mi, "scale", Vector3.ONE, 0.15)
		cb.call()


# ====================================================================== locomotion

func _physics_process(dt: float) -> void:
	if rig == null or ctrl.size() < 2:
		return
	var space := get_world_3d().direct_space_state
	var pull := Vector3.ZERO
	var touching := 0
	for side in ["l", "r"]:
		var c: XRController3D = ctrl[side]
		var delta_local := Vector3.ZERO
		if prev_hand[side] != null:
			delta_local = c.position - (prev_hand[side] as Vector3)
		prev_hand[side] = c.position
		query.transform = Transform3D(Basis(), c.global_position)
		if space.intersect_shape(query, 1).size() > 0:
			pull += -(origin.global_transform.basis * delta_local)
			touching += 1

	if touching > 0:
		vel = (pull / float(touching) / dt).limit_length(10.0)
	else:
		vel.y -= 9.8 * dt
		if rig.is_on_floor():
			vel.x = move_toward(vel.x, 0.0, 12.0 * dt)
			vel.z = move_toward(vel.z, 0.0, 12.0 * dt)
		else:
			vel.x *= 1.0 - 0.3 * dt
			vel.z *= 1.0 - 0.3 * dt

	# comfort fallbacks: left stick walks, right stick snap-turns
	var st: Vector2 = (ctrl["l"] as XRController3D).get_vector2("primary")
	if st.length() > 0.15:
		var yaw := cam.global_transform.basis.get_euler().y
		var dir := Basis(Vector3.UP, yaw) * Vector3(st.x, 0, -st.y)
		vel.x = dir.x * 2.5
		vel.z = dir.z * 2.5
	snap_cd -= dt
	var rs: Vector2 = (ctrl["r"] as XRController3D).get_vector2("primary")
	if absf(rs.x) > 0.7 and snap_cd <= 0.0:
		rig.rotate_y(deg_to_rad(-30.0 * signf(rs.x)))
		snap_cd = 0.3

	rig.velocity = vel
	rig.move_and_slide()
	vel = rig.velocity


# ====================================================================== voice + frame loop

func _setup_mic() -> void:
	OS.request_permissions()
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Mic")
	AudioServer.set_bus_volume_db(idx, -80.0)   # captured but never played back to yourself
	cap = AudioEffectCapture.new()
	AudioServer.add_bus_effect(idx, cap)
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = "Mic"
	add_child(mic_player)
	mic_player.play()
	get_tree().on_request_permissions_result.connect(_on_permission)


func _on_permission(_perm: String, granted: bool) -> void:
	if granted and mic_player:
		mic_player.play()


func _pump_mic() -> void:
	if cap == null:
		return
	var n := cap.get_frames_available()
	if n <= 0:
		local_lvl *= 0.9
		return
	var buf := cap.get_buffer(n)
	var step := maxi(1, roundi(AudioServer.get_mix_rate() / 16000.0))
	var out := PackedByteArray()
	var sum := 0.0
	var i := 0
	while i < n:
		var s := clampf((buf[i].x + buf[i].y) * 0.5, -1.0, 1.0)
		out.append(int(s * 127.0) + 128)
		sum += s * s
		i += step
	local_lvl = sqrt(sum / maxf(float(out.size()), 1.0))
	if local_lvl > TALK_THRESHOLD:
		local_talk_until = Time.get_ticks_msec() / 1000.0 + 0.3
	if Net.online and local_lvl > 0.012:
		Net.send_voice(out, int(AudioServer.get_mix_rate() / step))


func _process(dt: float) -> void:
	if cam == null:
		return
	_pump_mic()
	var now := Time.get_ticks_msec() / 1000.0
	var local_talking := now < local_talk_until
	if local_talking:
		preview.talk_until = local_talk_until

	# who is the current speaker? (sticky until they stop)
	var ok := false
	if speaker == 0:
		ok = local_talking
	elif monkeys.has(speaker):
		ok = (monkeys[speaker] as Monkey).is_talking()
	if not ok:
		speaker = -1
		if local_talking:
			speaker = 0
		else:
			for id in monkeys:
				if (monkeys[id] as Monkey).is_talking():
					speaker = id
					break
	var spos = null
	if speaker == 0:
		spos = cam.global_position
	elif speaker > 0:
		spos = (monkeys[speaker] as Monkey).head.global_position
	for id in monkeys:
		(monkeys[id] as Monkey).look_target = spos if speaker != id else null

	# lobby preview monkey: bobs gently and always looks at you
	var t := now
	var hp := Vector3(-3.2, 1.25 + sin(t * 2.0) * 0.03, -3.0)
	var hb := Basis(Vector3.UP, PI)
	preview.set_pose(Transform3D(hb, hp),
		Transform3D(hb, hp + Vector3(-0.35, -0.45 + sin(t * 2.0 + 1.0) * 0.05, 0.1)),
		Transform3D(hb, hp + Vector3(0.35, -0.45 + sin(t * 2.0 + 2.0) * 0.05, 0.1)))
	preview.look_target = cam.global_position

	# laser pointers
	for side in ["l", "r"]:
		var ray: RayCast3D = rays[side]
		var laser: MeshInstance3D = lasers[side]
		if ray.is_colliding():
			var d := ray.global_position.distance_to(ray.get_collision_point())
			(laser.mesh as CylinderMesh).height = d
			laser.position = Vector3(0, 0, -d / 2.0)
			laser.visible = true
		else:
			laser.visible = false

	# flickering fluorescent lights
	light_mat.emission_energy_multiplier = 0.2 if randf() < 0.008 else 1.0

	# broadcast my pose ~30x per second
	send_t += dt
	if send_t > 1.0 / 30.0:
		send_t = 0.0
		Net.send_state(cam.global_transform, (ctrl["l"] as XRController3D).global_transform,
			(ctrl["r"] as XRController3D).global_transform, local_lvl)


# ====================================================================== remote players

func _get_monkey(id: int) -> Monkey:
	if not monkeys.has(id):
		var m := Monkey.new()
		add_child(m)
		monkeys[id] = m
	return monkeys[id]


func _on_state(id: int, h: Transform3D, l: Transform3D, r: Transform3D, lvl: float) -> void:
	var m := _get_monkey(id)
	m.set_pose(h, l, r)
	m.hear(lvl)


func _on_profile(id: int, pname: String, color: Color) -> void:
	_get_monkey(id).set_profile(pname, color)


func _on_voice(id: int, pcm: PackedByteArray, rate: int) -> void:
	_get_monkey(id).push_voice(pcm, rate)


func _on_left(id: int) -> void:
	if monkeys.has(id):
		(monkeys[id] as Monkey).queue_free()
		monkeys.erase(id)


func _on_disconnected() -> void:
	for id in monkeys:
		(monkeys[id] as Monkey).queue_free()
	monkeys.clear()
	speaker = -1
