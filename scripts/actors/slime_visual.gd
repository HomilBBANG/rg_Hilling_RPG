class_name SlimeVisual
extends Node3D
## P0 placeholder fantasy monster: a hopping slime that wanders around its home point.
## No AI/combat (P1). Only here to test readability by day and night.

@export var wander_radius := 3.5
@export var hop_interval := 1.1

var height_func: Callable

var _rig: SlimeRig
var sprite: BakedSprite
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _hop_t := 0.0
var _from := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _materials: Array[StandardMaterial3D] = []
var _meshes: Array[MeshInstance3D] = []
var _silhouette_mat: ShaderMaterial
var _silhouette_on := true


func _ready() -> void:
	_rng.seed = 7
	_home = position
	_from = position
	_target = position
	_rig = SlimeRig.new()
	add_child(_rig)
	_setup_silhouette(Color(1.0, 0.35, 0.3, 0.45))
	add_to_group("enemies")


static func sprite_bake_spec(colors: Variant = null, body_scale := 1.0) -> Dictionary:
	return {
		"builder": func(c: int, r: int) -> Node3D:
			var rig := SlimeRig.new(colors, body_scale)
			rig.rotation.y = r * TAU / SlimeRig.DIRECTIONS
			rig.pose(float(c) / SlimeRig.FRAMES)
			return rig,
		"cols": SlimeRig.FRAMES,
		"rows": SlimeRig.DIRECTIONS,
		"cell": Vector2(1.6, 2.8) * maxf(1.0, body_scale),
	}


func use_sprite_sheet(sheet: SpriteSheet) -> void:
	if sheet == null:
		if sprite:
			sprite.queue_free()
			sprite = null
	else:
		if sprite == null:
			sprite = BakedSprite.new()
			sprite.anchor = self
			sprite.set_silhouette_color(Color(1.0, 0.35, 0.3, 0.45), 1.0)
			add_child(sprite)
		sprite.set_sheet(sheet)
	for mi in _meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if sprite else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	set_silhouette(_silhouette_on)


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
		_meshes.append(mi as MeshInstance3D)


func set_silhouette(on: bool) -> void:
	_silhouette_on = on
	for m in _materials:
		m.next_pass = _silhouette_mat if on and sprite == null else null
	if sprite:
		sprite.set_silhouette(on)


func _process(delta: float) -> void:
	_hop_t += delta
	var t := clampf(_hop_t / hop_interval, 0.0, 1.0)
	var air := clampf(t / 0.55, 0.0, 1.0)
	var p := _from.lerp(_target, smoothstep(0.0, 1.0, air))
	var ground: float = height_func.call(p.x, p.z) if height_func.is_valid() else 0.0
	position = Vector3(p.x, ground, p.z)
	_rig.pose(t)
	if t >= 1.0:
		_next_hop()
	var to := _target - _from
	if Vector2(to.x, to.z).length() > 0.05:
		_rig.rotation.y = lerp_angle(_rig.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-8.0 * delta))
	if sprite:
		var dir := posmod(roundi(_rig.rotation.y / (TAU / SlimeRig.DIRECTIONS)), SlimeRig.DIRECTIONS)
		sprite.set_frame(mini(int(t * SlimeRig.FRAMES), SlimeRig.FRAMES - 1), dir)


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
