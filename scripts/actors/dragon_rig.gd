class_name DragonRig
extends Node3D
## Prototype dragon body built from primitives (forward = -Z, ~9 m nose to tail, root on the
## ground). The boss script drives it through a few pose values; the rig turns them into joint
## angles every frame:
##   neck (raise / lower), jaw (0 shut .. 1 wide), wings (0 folded .. 1 spread) + flap speed,
##   walk (leg swing speed), glow (fire in the mouth), sleep (head on the ground), dead (collapse),
##   lift (height off the ground while flying), flash (white hit flash).

var neck := 0.0
var jaw := 0.0
var wings := 0.0
var flap := 0.0
var walk := 0.0
var glow := 0.0
var sleep := 0.0
var dead := 0.0
var lift := 0.0
var flash := 0.0

var mouth: Node3D  ## fire breath comes out of here (points forward)
var _body: Node3D
var _neck: Node3D
var _head: Node3D
var _jaw: Node3D
var _wing_l: Node3D
var _wing_r: Node3D
var _tail: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _mats: Array[StandardMaterial3D] = []
var _mouth_glow: MeshInstance3D
var _mouth_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _time := 0.0


func _init() -> void:
	var scale_mat := _mat(Color(0.5, 0.12, 0.11))
	var dark := _mat(Color(0.3, 0.07, 0.08))
	var belly := _mat(Color(0.86, 0.6, 0.36))
	var membrane := _mat(Color(0.38, 0.09, 0.12))
	var bone := ProtoMesh.mat(Color(0.92, 0.86, 0.72))
	_eye_mat = ProtoMesh.mat(Color(1.0, 0.85, 0.2), 0.4, Color(1.0, 0.75, 0.15), 2.5)
	_body = Node3D.new()
	add_child(_body)
	# torso + belly
	ProtoMesh.sphere(_body, 1.0, Vector3(0, 1.55, 0.1), scale_mat, Vector3(1.25, 0.95, 2.1), 12, 8)
	ProtoMesh.sphere(_body, 0.9, Vector3(0, 1.25, 0.0), belly, Vector3(1.05, 0.7, 1.8), 10, 6)
	for i in 6:  # back spikes
		var s := ProtoMesh.cone(_body, 0.22 - i * 0.02, 0.6 - i * 0.05, Vector3(0, 2.45 - abs(i - 2) * 0.08, -1.2 + i * 0.55), dark, 5)
		s.rotation_degrees.x = 20.0
	# legs: front pair under the chest, back pair under the hips
	for spec in [[-0.95, -1.0], [0.95, -1.0], [-1.05, 1.15], [1.05, 1.15]]:
		var leg := Node3D.new()
		leg.position = Vector3(spec[0], 1.25, spec[1])
		_body.add_child(leg)
		ProtoMesh.capsule(leg, 0.34, 1.3, Vector3(0, -0.55, 0), scale_mat)
		ProtoMesh.box(leg, Vector3(0.6, 0.25, 0.75), Vector3(0, -1.15, -0.15), dark)
		for c in [-0.18, 0.0, 0.18]:
			var claw := ProtoMesh.cone(leg, 0.07, 0.3, Vector3(c, -1.2, -0.55), bone, 4)
			claw.rotation_degrees.x = -90.0
		_legs.append(leg)
	# neck + head
	_neck = Node3D.new()
	_neck.position = Vector3(0, 2.0, -1.7)
	_body.add_child(_neck)
	ProtoMesh.capsule(_neck, 0.45, 1.9, Vector3(0, 0.55, -0.55), scale_mat, Vector3(-50, 0, 0))
	ProtoMesh.capsule(_neck, 0.32, 1.2, Vector3(0, 0.45, -0.35), belly, Vector3(-50, 0, 0))
	_head = Node3D.new()
	_head.position = Vector3(0, 1.15, -1.25)
	_neck.add_child(_head)
	ProtoMesh.box(_head, Vector3(0.95, 0.7, 1.1), Vector3(0, 0.05, -0.35), scale_mat)
	ProtoMesh.box(_head, Vector3(0.7, 0.4, 0.8), Vector3(0, -0.02, -1.15), scale_mat)
	for x in [-0.22, 0.22]:  # nostrils
		ProtoMesh.sphere(_head, 0.06, Vector3(x, 0.18, -1.5), dark, Vector3.ONE, 5, 3)
	for x in [-0.36, 0.36]:
		ProtoMesh.sphere(_head, 0.1, Vector3(x, 0.2, -0.72), _eye_mat, Vector3(1, 0.7, 1), 6, 4)
		var horn := ProtoMesh.cone(_head, 0.13, 0.9, Vector3(x * 0.9, 0.45, 0.15), bone, 6)
		horn.rotation_degrees = Vector3(70, 0, -x * 40.0)
	for i in 3:  # crest spikes
		var c2 := ProtoMesh.cone(_head, 0.1, 0.4, Vector3(0, 0.45, 0.0 + i * 0.25), dark, 4)
		c2.rotation_degrees.x = 55.0
	_jaw = Node3D.new()
	_jaw.position = Vector3(0, -0.25, -0.55)
	_head.add_child(_jaw)
	ProtoMesh.box(_jaw, Vector3(0.62, 0.18, 1.05), Vector3(0, -0.05, -0.55), belly)
	for x in [-0.22, 0.0, 0.22]:  # teeth
		var t := ProtoMesh.cone(_jaw, 0.05, 0.16, Vector3(x, 0.08, -0.95), bone, 4)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mouth = Node3D.new()
	mouth.position = Vector3(0, -0.15, -1.55)
	_head.add_child(mouth)
	_mouth_mat = ProtoMesh.unique_mat(Color(1.0, 0.5, 0.15))
	_mouth_mat.emission_enabled = true
	_mouth_mat.emission = Color(1.0, 0.45, 0.1)
	_mouth_glow = ProtoMesh.sphere(_head, 0.28, Vector3(0, -0.1, -1.2), _mouth_mat, Vector3(1, 0.6, 1.4), 8, 5)
	_mouth_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mouth_glow.visible = false
	# wings: an arm bone with a membrane trailing back from it
	for side in [-1.0, 1.0]:
		var w := Node3D.new()
		w.position = Vector3(0.75 * side, 2.35, -0.6)
		_body.add_child(w)
		ProtoMesh.capsule(w, 0.12, 3.3, Vector3(1.6 * side, 0.05, 0), dark, Vector3(0, 0, 90))
		ProtoMesh.box(w, Vector3(3.1, 0.06, 2.3), Vector3(1.6 * side, 0, 1.15), membrane)
		ProtoMesh.prism(w, Vector3(1.4, 0.06, 1.4), Vector3(3.1 * side, 0, 0.6), membrane, Vector3(0, 45, 0))
		var tip := ProtoMesh.cone(w, 0.08, 0.4, Vector3(3.3 * side, 0.05, 0), bone, 4)
		tip.rotation_degrees.z = -90.0 * side
		if side < 0.0:
			_wing_l = w
		else:
			_wing_r = w
	# tail: a chain of shrinking segments ending in a spade
	var parent: Node3D = _body
	var pos := Vector3(0, 1.45, 1.9)
	for i in 6:
		var seg := Node3D.new()
		seg.position = pos
		parent.add_child(seg)
		var r := 0.48 - i * 0.065
		ProtoMesh.capsule(seg, r, 1.1, Vector3(0, 0, 0.45), scale_mat, Vector3(90, 0, 0))
		if i % 2 == 0:
			var sp := ProtoMesh.cone(seg, r * 0.45, 0.35, Vector3(0, r + 0.1, 0.4), dark, 4)
			sp.rotation_degrees.x = 30.0
		_tail.append(seg)
		parent = seg
		pos = Vector3(0, -0.12 if i < 2 else -0.04, 0.85)
	ProtoMesh.prism(parent, Vector3(0.8, 0.08, 0.9), Vector3(0, 0, 1.15), dark, Vector3(0, 45, 0))


func _mat(c: Color) -> StandardMaterial3D:
	var m := ProtoMesh.unique_mat(c)
	m.emission_enabled = true
	m.emission = Color.BLACK
	_mats.append(m)
	return m


func _process(delta: float) -> void:
	_time += delta
	var t := _time
	var breathe := sin(t * 1.6) * (0.03 if sleep > 0.5 else 0.05)
	_body.position.y = lift + breathe * (1.0 - dead)
	_body.rotation.z = lerpf(0.0, deg_to_rad(68.0), dead)
	_body.position.x = lerpf(0.0, 0.9, dead)
	# neck: raised / lowered; sleeping or dead lays the head down on the ground
	var down := maxf(sleep, dead)
	_neck.rotation.x = lerpf(neck * 0.6, -0.75, down)
	_head.rotation.x = lerpf(-neck * 0.35, 0.55, down)
	_jaw.rotation.x = jaw * 0.75
	# wings
	var spread := maxf(wings, dead * 0.8)
	var fold_z := lerpf(deg_to_rad(72.0), deg_to_rad(8.0), spread)
	var fold_y := lerpf(deg_to_rad(-55.0), 0.0, spread)
	var beat := sin(t * flap) * 0.55 * minf(flap / 8.0, 1.0) * (1.0 - dead)
	_wing_l.rotation = Vector3(0, -fold_y, -fold_z + beat)
	_wing_r.rotation = Vector3(0, fold_y, fold_z - beat)
	# tail sway (slower asleep, still when dead)
	for i in _tail.size():
		var amp := (0.08 if sleep > 0.5 else 0.16) * (1.0 - dead)
		_tail[i].rotation.y = sin(t * 1.4 - i * 0.6) * amp + (0.18 * dead if i > 0 else 0.0)
		_tail[i].rotation.x = 0.02 * i
	# legs
	for i in _legs.size():
		var ph := (0.0 if i in [0, 3] else PI)
		_legs[i].rotation.x = sin(t * walk + ph) * 0.45 * minf(walk / 6.0, 1.0)
		if lift > 0.3:
			_legs[i].rotation.x = 0.6  # tucked while flying
	_mouth_glow.visible = glow > 0.05
	_mouth_glow.scale = Vector3.ONE * (0.6 + glow * 0.8)
	_mouth_mat.emission_energy_multiplier = 1.0 + glow * 4.0
	_eye_mat.emission_energy_multiplier = lerpf(2.5, 0.0, maxf(dead, sleep * 0.9))
	for m in _mats:
		m.emission = Color(flash, flash, flash) * 0.8
