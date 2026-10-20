class_name CatRig
extends Node3D
## Temporary model of the black cat (신수, GDD 2.2/2.3): chibi proportions like the protagonist,
## big head, short legs, glowing yellow eyes so it still reads at night. Faces -Z.
## Source for the cat's baked pixel sprite and its live shadow-only caster.

## Sprite columns [animation, frames]; rows are 8 facing directions.
const ANIMS := [["sit", 1], ["walk", 6], ["happy", 2]]
const DIRECTIONS := 8

var torso: Node3D
var head: Node3D
var _legs: Array[Node3D] = []  # FL, FR, BL, BR
var _tail: Array[Node3D] = []
var _eyes: Array[MeshInstance3D] = []
var _eye_open: Material
var _eye_closed: Material


func _init() -> void:
	var fur := ProtoMesh.mat(Color(0.17, 0.16, 0.21))
	var fur_light := ProtoMesh.mat(Color(0.25, 0.23, 0.3))
	var ear_in := ProtoMesh.mat(Color(0.55, 0.36, 0.42))
	_eye_open = ProtoMesh.mat(Color(0.98, 0.84, 0.28), 0.5, Color(1.0, 0.82, 0.3), 0.5)
	_eye_closed = fur_light
	torso = Node3D.new()
	torso.position = Vector3(0, 0.16, 0.14)
	add_child(torso)
	ProtoMesh.sphere(torso, 0.17, Vector3(0, 0.06, -0.12), fur, Vector3(0.9, 0.8, 1.3), 10, 6)
	ProtoMesh.sphere(torso, 0.125, Vector3(0, 0.1, -0.26), fur, Vector3.ONE, 8, 5)
	head = Node3D.new()
	head.position = Vector3(0, 0.2, -0.32)
	torso.add_child(head)
	ProtoMesh.sphere(head, 0.155, Vector3(0, 0.07, -0.03), fur, Vector3(1.08, 0.92, 0.95), 10, 6)
	ProtoMesh.sphere(head, 0.065, Vector3(0, 0.015, -0.14), fur_light, Vector3(1.25, 0.7, 0.8), 6, 4)
	for side in [-1.0, 1.0]:
		ProtoMesh.cylinder(head, 0.06, 0.13, Vector3(0.088 * side, 0.2, -0.02), fur, Vector3(0, 0, -16.0 * side), 4, 0.0)
		ProtoMesh.cylinder(head, 0.03, 0.07, Vector3(0.086 * side, 0.19, -0.05), ear_in, Vector3(0, 0, -16.0 * side), 4, 0.0)
		var eye := ProtoMesh.sphere(head, 0.034, Vector3(0.062 * side, 0.085, -0.16), _eye_open, Vector3(1.0, 1.15, 0.6), 6, 4)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_eyes.append(eye)
	for spec in [[-0.075, -0.27], [0.075, -0.27], [-0.08, 0.0], [0.08, 0.0]]:
		var leg := Node3D.new()
		leg.position = Vector3(spec[0], 0.01, spec[1])
		torso.add_child(leg)
		ProtoMesh.cylinder(leg, 0.045, 0.17, Vector3(0, -0.085, 0), fur, Vector3.ZERO, 6)
		ProtoMesh.sphere(leg, 0.052, Vector3(0, -0.16, -0.015), fur, Vector3(1.0, 0.6, 1.25), 6, 3)
		_legs.append(leg)
	var parent: Node3D = torso
	var pos := Vector3(0, 0.08, 0.1)
	for i in 3:
		var seg := Node3D.new()
		seg.position = pos
		parent.add_child(seg)
		ProtoMesh.capsule(seg, 0.04 - i * 0.004, 0.15, Vector3(0, 0.07, 0), fur)
		_tail.append(seg)
		parent = seg
		pos = Vector3(0, 0.13, 0)
	pose_walk(0.0, 0.0)


static func column_count() -> int:
	var n := 0
	for a: Array in ANIMS:
		n += a[1]
	return n


static func column_for(anim: String, frame: int) -> int:
	var c := 0
	for a: Array in ANIMS:
		if a[0] == anim:
			return c + clampi(frame, 0, a[1] - 1)
		c += a[1]
	return 0


static func direction_index(yaw: float) -> int:
	return posmod(roundi(yaw / (TAU / DIRECTIONS)), DIRECTIONS)


func _set_eyes(open: bool) -> void:
	for e in _eyes:
		e.material_override = _eye_open if open else _eye_closed
		e.scale = Vector3(1.0, 1.15, 0.6) if open else Vector3(1.1, 0.45, 0.6)


func _tail_pose(a: float, b: float, c: float, sway := 0.0) -> void:
	_tail[0].rotation = Vector3(a, 0, sway)
	_tail[1].rotation = Vector3(b, 0, sway * 0.6)
	_tail[2].rotation = Vector3(c, 0, sway * 0.4)


## phase: radians through the gait; moving 0..1.
func pose_walk(phase: float, moving: float) -> void:
	_set_eyes(true)
	torso.rotation = Vector3.ZERO
	torso.position = Vector3(0, 0.16 + absf(sin(phase * 2.0)) * 0.012 * moving, 0.14)
	head.rotation = Vector3(0, 0, 0)
	var s := sin(phase) * 0.6 * moving
	_legs[0].rotation = Vector3(s, 0, 0)
	_legs[1].rotation = Vector3(-s, 0, 0)
	_legs[2].rotation = Vector3(-s, 0, 0)
	_legs[3].rotation = Vector3(s, 0, 0)
	for l in _legs:
		l.scale = Vector3.ONE
	_tail_pose(0.55, -0.35, -0.45, sin(phase) * 0.25 * moving)


## Sitting upright: rear down, front legs straight, tail curled on the ground.
func pose_sit(happy := false, t := 0.0) -> void:
	_set_eyes(not happy)
	var a := 0.5
	torso.rotation = Vector3(a, 0, 0)
	torso.position = Vector3(0, 0.12, 0.14)
	head.rotation = Vector3(-a + (0.18 if happy else 0.0), 0, sin(t * TAU) * 0.12 if happy else 0.0)
	_legs[0].rotation = Vector3(-a, 0, 0)
	_legs[1].rotation = Vector3(-a, 0, 0)
	_legs[0].scale = Vector3(1, 1.45, 1)
	_legs[1].scale = Vector3(1, 1.45, 1)
	_legs[2].rotation = Vector3(1.1, 0, 0)
	_legs[3].rotation = Vector3(1.1, 0, 0)
	_legs[2].scale = Vector3.ONE
	_legs[3].scale = Vector3.ONE
	if happy:
		_tail_pose(-0.3, -0.15, -0.35, (t - 0.5) * 0.5)  # tail straight up
	else:
		_tail_pose(1.5, 0.6, 0.5, 0.9)


func pose_column(col: int) -> void:
	var c := col
	for anim: Array in ANIMS:
		if c < anim[1]:
			match anim[0]:
				"sit":
					pose_sit(false)
				"walk":
					pose_walk(TAU * c / anim[1], 1.0)
				"happy":
					pose_sit(true, float(c) / anim[1])
			return
		c -= anim[1]
