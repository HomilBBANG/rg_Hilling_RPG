class_name SlimeRig
extends Node3D
## The slime's 3D model with a hop pose (source for its baked pixel sprite + shadow caster).

const FRAMES := 8
const DIRECTIONS := 8

var body: Node3D


## colors: optional {"body", "light", "core"} as [r, g, b] (monster kinds, data/monsters.json).
func _init(colors: Variant = null, body_scale := 1.0) -> void:
	body = Node3D.new()
	body.scale = Vector3.ONE * body_scale
	add_child(body)
	var c: Dictionary = colors if colors is Dictionary else {}
	var body_mat := ProtoMesh.mat(_col(c, "body", Color(0.25, 0.72, 0.86)), 0.25)
	var light_mat := ProtoMesh.mat(_col(c, "light", Color(0.55, 0.88, 0.95)), 0.25)
	var core_mat := ProtoMesh.mat(_col(c, "core", Color(0.14, 0.45, 0.62)), 0.3)
	var eye := ProtoMesh.mat(Color(1, 1, 0.92), 0.5, Color(1.0, 0.95, 0.7), 0.6)
	var pupil := ProtoMesh.mat(Color(0.05, 0.05, 0.08))
	ProtoMesh.sphere(body, 0.5, Vector3(0, 0.36, 0), body_mat, Vector3(1.0, 0.75, 1.0), 12, 7)
	ProtoMesh.sphere(body, 0.22, Vector3(0, 0.3, 0.08), core_mat)
	ProtoMesh.sphere(body, 0.18, Vector3(0, 0.68, 0.0), body_mat, Vector3(1, 0.8, 1), 8, 4)
	ProtoMesh.sphere(body, 0.12, Vector3(-0.18, 0.62, -0.12), light_mat, Vector3(1, 0.6, 1), 6, 3)
	for side in [-1.0, 1.0]:
		ProtoMesh.sphere(body, 0.1, Vector3(0.17 * side, 0.48, -0.38), eye)
		ProtoMesh.sphere(body, 0.05, Vector3(0.17 * side, 0.48, -0.46), pupil)


static func _col(c: Dictionary, key: String, fallback: Color) -> Color:
	var a: Variant = c.get(key, null)
	return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array else fallback


## t: 0..1 through one hop cycle (0..0.55 airborne, then squash on landing).
func pose(t: float) -> void:
	var air := clampf(t / 0.55, 0.0, 1.0)
	body.position.y = sin(air * PI) * 0.45 if t < 0.55 else 0.0
	var squash := 1.0
	if t >= 0.55:
		squash = 1.0 - sin((t - 0.55) / 0.45 * PI) * 0.18
	elif air < 0.15:
		squash = 1.15
	body.scale = Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))
