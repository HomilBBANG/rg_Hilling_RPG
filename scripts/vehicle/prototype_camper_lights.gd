class_name PrototypeCamperLights
extends Node3D
## Camper exterior lights for the F toggle (GDD 4.1/10.3 [확정]: F = camper exterior light on/off).
## Headlights are shadowed spot lights; the porch light helps the camp area at night.

var _spots: Array[SpotLight3D] = []
var _omnis: Array[OmniLight3D] = []
var _lamp_meshes: Array[MeshInstance3D] = []
var _tail_meshes: Array[MeshInstance3D] = []
var _on_mat: Material
var _off_mat: Material
var _tail_on: Material
var _tail_off: Material
var _state := false


func build(camper: Node3D) -> void:
	_on_mat = ProtoMesh.mat(Color(1, 0.98, 0.9), 0.2, Color(1.0, 0.95, 0.8), 4.0)
	_off_mat = ProtoMesh.mat(Color(0.75, 0.78, 0.8), 0.2)
	_tail_on = ProtoMesh.mat(Color(1, 0.2, 0.15), 0.3, Color(1.0, 0.1, 0.05), 3.0)
	_tail_off = ProtoMesh.mat(Color(0.5, 0.1, 0.08), 0.3)
	var hl := CamperExterior.HEADLIGHT_LOCAL
	var tl := CamperExterior.TAILLIGHT_LOCAL
	for side in [-1.0, 1.0]:
		var lamp_pos := Vector3(hl.x, hl.y, side * hl.z)
		_lamp_meshes.append(ProtoMesh.cylinder(camper, 0.13, 0.06, lamp_pos, _off_mat, Vector3(0, 0, 90), 10))
		_tail_meshes.append(ProtoMesh.box(camper, Vector3(0.05, 0.36, 0.16), Vector3(tl.x, tl.y, side * tl.z), _tail_off))
		var spot := SpotLight3D.new()
		spot.position = lamp_pos + Vector3(0.1, 0, 0)
		# SpotLight shines along local -Z; turn to +X and tilt slightly down.
		spot.rotation_degrees = Vector3(-9.0, -90.0, 0.0)
		spot.light_color = Color(1.0, 0.96, 0.86)
		spot.light_energy = 7.0
		spot.spot_range = 24.0
		spot.spot_angle = 24.0
		spot.spot_attenuation = 0.8
		spot.shadow_enabled = true
		spot.shadow_bias = 0.05
		spot.visible = false
		camper.add_child(spot)
		_spots.append(spot)
	# Porch light above the door + a faint red rear marker
	var porch := OmniLight3D.new()
	# Just in front of the lamp above the door.
	porch.position = CamperExterior.DOOR_LOCAL + Vector3(0.0, 2.3, 0.5)
	porch.light_color = Color(1.0, 0.86, 0.62)
	porch.light_energy = 1.6
	porch.omni_range = 6.5
	# Shadowless: a low porch light behind the player throws long shadow wedges that hurt readability.
	porch.shadow_enabled = false
	porch.visible = false
	camper.add_child(porch)
	_omnis.append(porch)
	_lamp_meshes.append(ProtoMesh.box(camper, Vector3(0.25, 0.08, 0.12), CamperExterior.DOOR_LOCAL + Vector3(0, 2.6, 0.08), _off_mat))
	var rear := OmniLight3D.new()
	rear.position = Vector3(-4.0, 1.0, 0.0)
	rear.light_color = Color(1.0, 0.15, 0.1)
	rear.light_energy = 0.6
	rear.omni_range = 3.0
	rear.visible = false
	camper.add_child(rear)
	_omnis.append(rear)
	_apply(Game.camper_lights_on)


func _process(_delta: float) -> void:
	if _state != Game.camper_lights_on:
		_apply(Game.camper_lights_on)


func _apply(on: bool) -> void:
	_state = on
	for s in _spots:
		s.visible = on
	for o in _omnis:
		o.visible = on
	for m in _lamp_meshes:
		m.material_override = _on_mat if on else _off_mat
	for m in _tail_meshes:
		m.material_override = _tail_on if on else _tail_off
