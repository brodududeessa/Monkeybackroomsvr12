class_name Monkey
extends Node3D
## Procedural monkey avatar: head, body, tail, two arms/hands, name tag.
## Eyes grow when the monkey talks and the pupils follow `look_target` (world position).

var fur := StandardMaterial3D.new()
var muzzle_mat := StandardMaterial3D.new()
var head := Node3D.new()
var body := Node3D.new()
var arm_l: Node3D
var arm_r: Node3D
var hand_l: MeshInstance3D
var hand_r: MeshInstance3D
var label := Label3D.new()
var eyes: Array = []          # each entry: [eye MeshInstance3D, pupil MeshInstance3D]
var talk_until := 0.0
var look_target = null        # Vector3 (world) or null = look straight ahead
var eye_scale := 1.0
var voice_player: AudioStreamPlayer3D
var voice_playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	_build()


func _sphere(r: float, mat: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _make_arm() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.035
	cy.bottom_radius = 0.035
	cy.height = 1.0
	cy.radial_segments = 8
	mi.mesh = cy
	mi.material_override = fur
	mi.rotation_degrees = Vector3(90, 0, 0)   # cylinder axis -> local Z
	n.add_child(mi)
	return n


func _build() -> void:
	fur.albedo_color = Color(0.55, 0.35, 0.2)
	muzzle_mat.albedo_color = Color(0.8, 0.65, 0.5)
	add_child(head)
	add_child(body)

	# head (forward = -Z)
	_sphere(0.13, fur, Vector3.ZERO, head)
	_sphere(0.075, muzzle_mat, Vector3(0, -0.045, -0.09), head)
	_sphere(0.05, fur, Vector3(0.14, 0.0, 0.0), head)
	_sphere(0.05, fur, Vector3(-0.14, 0.0, 0.0), head)

	var white := StandardMaterial3D.new()
	white.albedo_color = Color.WHITE
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var black := StandardMaterial3D.new()
	black.albedo_color = Color.BLACK
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for sx in [-1.0, 1.0]:
		var eye := _sphere(0.032, white, Vector3(sx * 0.055, 0.035, -0.105), head)
		var pupil := _sphere(0.015, black, Vector3(0, 0, -0.021), eye)
		eyes.append([eye, pupil])

	# body + tail
	var bm := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.17
	cm.height = 0.6
	bm.mesh = cm
	bm.material_override = fur
	body.add_child(bm)
	var tail := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.02
	tm.bottom_radius = 0.025
	tm.height = 0.5
	tail.mesh = tm
	tail.material_override = fur
	tail.position = Vector3(0, -0.15, 0.25)
	tail.rotation_degrees = Vector3(50, 0, 0)
	body.add_child(tail)

	# hands + arms (positioned in world space every frame)
	hand_l = _sphere(0.055, fur, Vector3.ZERO, self)
	hand_r = _sphere(0.055, fur, Vector3.ZERO, self)
	arm_l = _make_arm()
	arm_r = _make_arm()

	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.0025
	label.outline_size = 12
	label.text = "MONKEY"
	add_child(label)


func set_profile(pname: String, color: Color) -> void:
	fur.albedo_color = color
	muzzle_mat.albedo_color = color.lightened(0.45)
	label.text = pname


func _update_arm(arm: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		arm.visible = false
		return
	arm.visible = true
	var dir := d / length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var bs := Basis.looking_at(dir, up)
	bs.z = bs.z * length
	arm.global_transform = Transform3D(bs, (a + b) * 0.5)


## head / lh / rh are world transforms of the headset and the two controllers.
func set_pose(h: Transform3D, l: Transform3D, r: Transform3D) -> void:
	head.global_transform = h
	var yaw := h.basis.get_euler().y
	var yb := Basis(Vector3.UP, yaw)
	var bpos := h.origin + Vector3(0, -0.45, 0)
	body.global_transform = Transform3D(yb, bpos)
	hand_l.global_transform = l
	hand_r.global_transform = r
	_update_arm(arm_l, bpos + yb * Vector3(-0.2, 0.2, 0), l.origin)
	_update_arm(arm_r, bpos + yb * Vector3(0.2, 0.2, 0), r.origin)
	label.global_position = h.origin + Vector3(0, 0.3, 0)


func hear(level: float) -> void:
	if level > 0.015:
		talk_until = Time.get_ticks_msec() / 1000.0 + 0.3


func is_talking() -> bool:
	return Time.get_ticks_msec() / 1000.0 < talk_until


func push_voice(pcm: PackedByteArray, rate: int) -> void:
	if voice_player == null:
		voice_player = AudioStreamPlayer3D.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = rate
		gen.buffer_length = 0.4
		voice_player.stream = gen
		voice_player.unit_size = 6.0
		head.add_child(voice_player)
		voice_player.play()
		voice_playback = voice_player.get_stream_playback()
	if voice_playback == null:
		return
	var n := mini(pcm.size(), voice_playback.get_frames_available())
	if n <= 0:
		return
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		var s := (float(pcm[i]) - 128.0) / 128.0
		frames[i] = Vector2(s, s)
	voice_playback.push_buffer(frames)


func _process(dt: float) -> void:
	var target_scale := 1.6 if is_talking() else 1.0
	eye_scale = lerpf(eye_scale, target_scale, clampf(dt * 16.0, 0.0, 1.0))
	for e in eyes:
		var eye: MeshInstance3D = e[0]
		var pupil: MeshInstance3D = e[1]
		eye.scale = Vector3.ONE * eye_scale
		var dir := Vector3(0, 0, -1)
		if look_target != null:
			var local := head.to_local(look_target) - eye.position
			if local.length() > 0.01:
				dir = local.normalized()
		if dir.z > -0.25:
			dir.z = -0.25
			dir = dir.normalized()
		pupil.position = dir * 0.021
