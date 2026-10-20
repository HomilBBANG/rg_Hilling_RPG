class_name AmbientParticles
extends RefCounted
## Pixel-sized glowing particles (campfire embers, floating motes / fireflies).
## Quads are ~1 render texel so they read as single bright pixels after pixelation.


static func _quad_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 1.0
	return m


static func _fade_ramp(a: Color, b: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(a, 0.0))
	g.set_color(1, Color(b, 0.0))
	g.add_point(0.15, a)
	g.add_point(0.7, b)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func embers(parent: Node3D, pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Embers"
	p.amount = 12
	p.lifetime = 1.6
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.28
	pm.direction = Vector3.UP
	pm.spread = 22.0
	pm.initial_velocity_min = 0.7
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0.15, 0.25, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.color_ramp = _fade_ramp(Color(1.0, 0.85, 0.4), Color(1.0, 0.3, 0.15))
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	q.material = _quad_material(Color(1.0, 0.65, 0.3), 4.0)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## Slow floating motes in a box around the emitter (attach to the player).
static func motes(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Motes"
	p.amount = 18
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.local_coords = false
	p.position = Vector3(0, 1.0, -1.5)
	p.visibility_aabb = AABB(Vector3(-16, -4, -14), Vector3(32, 10, 28))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12.0, 1.4, 9.0)
	pm.direction = Vector3(0.3, 1.0, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 2.5
	pm.color_ramp = _fade_ramp(Color(1.0, 0.95, 0.65), Color(0.7, 0.95, 0.85))
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.04, 0.04)
	q.material = _quad_material(Color(1.0, 0.92, 0.6), 1.4)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p
