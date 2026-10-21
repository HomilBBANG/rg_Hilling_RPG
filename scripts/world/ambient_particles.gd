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
	p.add_child(WindDrift.make(pm, Vector3(0.0, 0.25, 0.0), 1.0))
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


## Campfire smoke: a few soft grey puffs that rise and are blown downwind (WindDrift).
## Puffs are several texels wide and fade in/out, so they read as smoke, not as sparkle.
static func smoke(pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Smoke"
	p.amount = 7
	p.lifetime = 3.2
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 7, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.55
	pm.gravity = Vector3(0.0, 0.15, 0.0)
	pm.damping_min = 0.2
	pm.damping_max = 0.4
	pm.scale_min = 0.7
	pm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(1.0, 1.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.74, 0.72, 0.0))
	g.set_color(1, Color(0.85, 0.85, 0.85, 0.0))
	g.add_point(0.2, Color(0.72, 0.71, 0.7, 0.55))
	g.add_point(0.65, Color(0.82, 0.82, 0.82, 0.3))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.28, 0.28)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _round_mask()  # round puffs instead of squares
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(WindDrift.make(pm, Vector3(0.0, 0.15, 0.0), 0.6))
	return p


## A few leaves blown along by the wind around `follow` (the player): sparse, 2-3 texels wide,
## drifting slowly - motion you can read, not ground sparkle.
static func leaves(follow: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "BlowingLeaves"
	p.amount = 10
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.local_coords = false
	p.position = Vector3(-6.0, 3.0, -2.0)
	p.visibility_aabb = AABB(Vector3(-20, -6, -16), Vector3(40, 12, 32))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9.0, 1.2, 7.0)
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, -0.12, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	pm.damping_min = 0.4
	pm.damping_max = 0.6
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 3.0
	var g := Gradient.new()
	# Leaf greens / autumn browns, darker than the grass so they read against it.
	g.set_color(0, Color(0.3, 0.45, 0.16, 0.0))
	g.set_color(1, Color(0.55, 0.36, 0.14, 0.0))
	g.add_point(0.06, Color(0.3, 0.45, 0.16, 1.0))
	g.add_point(0.5, Color(0.42, 0.42, 0.14, 1.0))
	g.add_point(0.92, Color(0.55, 0.36, 0.14, 1.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.15, 0.1)  # ~5 x 3 texels: reads as a leaf, not a speck
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var drift := WindDrift.make(pm, Vector3(0, -0.12, 0), 0.8)
	drift.follow = follow
	drift.follow_offset = Vector3(-6.0, 3.0, -2.0)
	p.add_child(drift)
	return p


static var _round_tex: Texture2D


## Soft-edged disc mask (alpha), sampled with nearest filtering into a pixel circle.
static func _round_mask() -> Texture2D:
	if _round_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.75, Color(1, 1, 1, 1))
		g.add_point(0.8, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 16
		t.height = 16
		_round_tex = t
	return _round_tex
