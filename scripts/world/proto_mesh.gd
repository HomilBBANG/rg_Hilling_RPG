class_name ProtoMesh
extends RefCounted
## Small helpers for building low-poly placeholder models from primitive meshes.
## All prototype art in this project is generated here (no external assets).

static var _materials := {}


static func mat(color: Color, roughness := 0.9, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%s|%.2f" % [color.to_html(), roughness, emission.to_html(), emission_energy]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	_stylize(m)
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_materials[key] = m
	return m


## Unique (non-cached) material, for things whose parameters change at runtime.
static func unique_mat(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	_stylize(m)
	return m


## Flat cel look: toon diffuse with a very small roughness gives a hard two-tone
## light/shadow edge (Godot's toon smoothness = roughness). No specular blobs.
## Roughness < 0.8 also marks these as hard props for the optional outline pass.
static func _stylize(m: StandardMaterial3D) -> void:
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 0.06


static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material, rot_deg := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _add(parent, m, pos, material, rot_deg, shadows)


static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, rot_deg := Vector3.ZERO, segments := 8, top_radius := -1.0) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top_radius < 0.0 else top_radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return _add(parent, m, pos, material, rot_deg)


static func cone(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, segments := 7) -> MeshInstance3D:
	return cylinder(parent, radius, height, pos, material, Vector3.ZERO, segments, 0.0)


static func sphere(parent: Node3D, radius: float, pos: Vector3, material: Material, scale := Vector3.ONE, segments := 8, rings := 5) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = rings
	var mi := _add(parent, m, pos, material)
	mi.scale = scale
	return mi


static func capsule(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 8
	m.rings = 2
	return _add(parent, m, pos, material, rot_deg)


## Triangular prism (roof). Size x = width (ridge along z), y = height, z = depth.
static func prism(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = size
	return _add(parent, m, pos, material, rot_deg)


static func static_box_collider(parent: Node3D, size: Vector3, pos: Vector3, rot_deg := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	parent.add_child(body)
	return body


static func static_cylinder_collider(parent: Node3D, radius: float, height: float, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = radius
	cs.height = height
	shape.shape = cs
	body.add_child(shape)
	parent.add_child(body)
	return body
