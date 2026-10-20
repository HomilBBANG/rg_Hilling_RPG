class_name SlimeVisual
extends Node3D
## P0 placeholder fantasy monster: a hopping slime that wanders around its home point.
## No AI/combat (P1). Only here to test readability by day and night.

@export var wander_radius := 3.5
@export var hop_interval := 1.1

var height_func: Callable

var _body: MeshInstance3D
var _rig: Node3D
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _hop_t := 0.0
var _from := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _materials: Array[StandardMaterial3D] = []
var _silhouette_mat: ShaderMaterial


func _ready() -> void:
	_rng.seed = 7
	_home = position
	_from = position
	_target = position
	_rig = Node3D.new()
	add_child(_rig)
	var body_mat := ProtoMesh.mat(Color(0.25, 0.72, 0.86), 0.25)
	var core_mat := ProtoMesh.mat(Color(0.14, 0.45, 0.62), 0.3)
	var eye := ProtoMesh.mat(Color(1, 1, 0.92), 0.5, Color(1.0, 0.95, 0.7), 0.6)
	var pupil := ProtoMesh.mat(Color(0.05, 0.05, 0.08))
	_body = ProtoMesh.sphere(_rig, 0.5, Vector3(0, 0.36, 0), body_mat, Vector3(1.0, 0.75, 1.0), 10, 6)
	ProtoMesh.sphere(_rig, 0.22, Vector3(0, 0.3, 0.08), core_mat)
	ProtoMesh.sphere(_rig, 0.18, Vector3(0, 0.68, 0.0), body_mat, Vector3(1, 0.8, 1), 8, 4)
	for side in [-1.0, 1.0]:
		ProtoMesh.sphere(_rig, 0.1, Vector3(0.17 * side, 0.48, -0.38), eye)
		ProtoMesh.sphere(_rig, 0.05, Vector3(0.17 * side, 0.48, -0.46), pupil)
	_setup_silhouette(Color(1.0, 0.35, 0.3, 0.45))
	add_to_group("enemies")


func _setup_silhouette(color: Color) -> void:
	var sil := ShaderMaterial.new()
	sil.shader = preload("res://shaders/occluded_silhouette.gdshader")
	sil.set_shader_parameter("color", color)
	sil.set_shader_parameter("self_bias", 1.0)
	sil.render_priority = 1
	_silhouette_mat = sil
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override.duplicate() as StandardMaterial3D
		m.next_pass = sil
		(mi as MeshInstance3D).material_override = m
		_materials.append(m)


func set_silhouette(on: bool) -> void:
	for m in _materials:
		m.next_pass = _silhouette_mat if on else null


func _process(delta: float) -> void:
	_hop_t += delta
	var t := clampf(_hop_t / hop_interval, 0.0, 1.0)
	# 0..0.55 airborne hop, rest is a squash/idle wobble on the ground.
	var air := clampf(t / 0.55, 0.0, 1.0)
	var p := _from.lerp(_target, smoothstep(0.0, 1.0, air))
	var ground: float = height_func.call(p.x, p.z) if height_func.is_valid() else 0.0
	position = Vector3(p.x, ground, p.z)
	var hop_h := sin(air * PI) * 0.45 if t < 0.55 else 0.0
	_rig.position.y = hop_h
	var squash := 1.0
	if t >= 0.55:
		squash = 1.0 - sin((t - 0.55) / 0.45 * PI) * 0.18
	elif air < 0.15:
		squash = 1.15
	_rig.scale = Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))
	if t >= 1.0:
		_next_hop()
	var to := _target - _from
	if Vector2(to.x, to.z).length() > 0.05:
		_rig.rotation.y = lerp_angle(_rig.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-8.0 * delta))


func _next_hop() -> void:
	_hop_t = 0.0
	_from = Vector3(position.x, 0.0, position.z)
	var ang := _rng.randf() * TAU
	var r := _rng.randf_range(0.6, 1.4)
	var cand := _from + Vector3(cos(ang), 0.0, sin(ang)) * r
	var off := cand - _home
	if Vector2(off.x, off.z).length() > wander_radius:
		cand = _from + (_home - _from).normalized() * r
	_target = Vector3(cand.x, 0.0, cand.z)
