class_name CampfireFlame
extends Node3D
## Small animated campfire flame (emissive cones) with a flickering warm light.
## The flame leans and flutters with the shared wind; smoke puffs drift downwind.

const LEAN := 0.55  # radians of lean per unit wind

var _pivot: Node3D
var _outer: MeshInstance3D
var _inner: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	var outer_mat := ProtoMesh.mat(Color(1.0, 0.45, 0.15), 0.8, Color(1.0, 0.4, 0.1), 3.5)
	var inner_mat := ProtoMesh.mat(Color(1.0, 0.85, 0.35), 0.8, Color(1.0, 0.8, 0.3), 4.5)
	# Cones hang from a pivot at their base so leaning tilts the tip, not the whole fire.
	_pivot = Node3D.new()
	add_child(_pivot)
	_outer = ProtoMesh.cone(_pivot, 0.28, 0.7, Vector3(0, 0.35, 0), outer_mat, 6)
	_inner = ProtoMesh.cone(_pivot, 0.16, 0.45, Vector3(0.03, 0.25, 0.02), inner_mat, 5)
	for m in [_outer, _inner]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.6, 0)
	_light.light_color = Color(1.0, 0.62, 0.3)
	_light.light_energy = 1.2
	_light.omni_range = 4.5
	add_child(_light)
	add_child(AmbientParticles.smoke(Vector3(0, 0.75, 0)))


func _process(delta: float) -> void:
	_t += delta
	var w := Wind.offset(global_position)
	var gust := w.length()
	# Stronger, faster flicker in a gust.
	var f := 1.0 + sin(_t * 11.0) * (0.08 + gust * 0.05) + sin(_t * 17.3 + 1.0) * (0.06 + gust * 0.04)
	_outer.scale = Vector3(1.0 / f, f * (1.0 - gust * 0.12), 1.0 / f)
	_inner.scale = Vector3(f, 1.0 / f * 1.05, f)
	_outer.rotation.y = _t * 0.7
	# Lean the tips downwind (+X tilt = -Z rotation, +Z tilt = +X rotation), with a flutter.
	var flutter := 1.0 + sin(_t * 7.0) * 0.18
	_pivot.rotation = Vector3(w.y * LEAN * flutter, 0.0, -w.x * LEAN * flutter)
	_light.position = Vector3(w.x * 0.15, 0.6, w.y * 0.15)
	_light.light_energy = 1.1 + (f - 1.0) * 2.0
