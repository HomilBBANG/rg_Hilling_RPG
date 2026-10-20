class_name GroundCover
extends RefCounted
## MultiMesh grass tufts, flowers and pebbles. Cheap density that breaks up flat ground.


static func _tuft_mesh() -> ArrayMesh:
	# Five thin blades fanning out; UV.y = 0 at root, 1 at tip.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := [[-0.07, 0.26, -18.0], [0.0, 0.34, 0.0], [0.07, 0.28, 16.0], [-0.03, 0.22, 40.0], [0.04, 0.24, -38.0]]
	for b: Array in blades:
		var x: float = b[0]
		var h: float = b[1]
		var yaw := deg_to_rad(b[2] * 2.2)
		var lean := Vector3(x * 1.4, 0, 0)
		var w := 0.035
		var right := Vector3(cos(yaw), 0, sin(yaw)) * w
		var base := Vector3(x, 0, 0)
		var tip := base + Vector3(0, h, 0) + lean
		for v in [[base - right, 0.0], [tip, 1.0], [base + right, 0.0]]:
			st.set_uv(Vector2(0, v[1]))
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	return st.commit()


static func _flower_mesh() -> ArrayMesh:
	# Stem (UV.x 0), 4-petal flat star (UV.x 2), centre (UV.x 1).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.22
	for v in [Vector3(-0.012, 0, 0), Vector3(0, h, 0), Vector3(0.012, 0, 0)]:
		st.set_uv(Vector2(0, v.y / h))
		st.add_vertex(v)
	var c := Vector3(0, h, 0)
	for i in 4:
		var a := TAU * i / 4.0
		var p0 := c + Vector3(cos(a - 0.5), 0, sin(a - 0.5)) * 0.05
		var p1 := c + Vector3(cos(a), 0.01, sin(a)) * 0.11
		var p2 := c + Vector3(cos(a + 0.5), 0, sin(a + 0.5)) * 0.05
		for v in [c, p1, p0, c, p2, p1]:
			st.set_uv(Vector2(2.0, 1.0))
			st.add_vertex(v)
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		for v in [c + Vector3(0, 0.012, 0), c + Vector3(cos(a1), 0, sin(a1)) * 0.03 + Vector3(0, 0.012, 0), c + Vector3(cos(a0), 0, sin(a0)) * 0.03 + Vector3(0, 0.012, 0)]:
			st.set_uv(Vector2(1.0, 1.0))
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _multimesh(mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color], material: Material, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## accept(x, z) -> float density 0..1 at that point (0 = never place).
static func build(parent: Node3D, area: Rect2, count: int, height_func: Callable, accept: Callable, rng: RandomNumberGenerator) -> void:
	var tuft_t: Array[Transform3D] = []
	var tuft_c: Array[Color] = []
	var flower_t: Array[Transform3D] = []
	var flower_c: Array[Color] = []
	var petal_colors := [Color(0.98, 0.95, 0.88), Color(0.99, 0.84, 0.38), Color(0.93, 0.6, 0.78), Color(0.66, 0.6, 0.95), Color(0.98, 0.62, 0.42)]
	var patch_noise := FastNoiseLite.new()
	patch_noise.seed = 9
	patch_noise.frequency = 0.08
	var tries := 0
	while tuft_t.size() < count and tries < count * 6:
		tries += 1
		var x := rng.randf_range(area.position.x, area.end.x)
		var z := rng.randf_range(area.position.y, area.end.y)
		var dens: float = accept.call(x, z)
		var patch := patch_noise.get_noise_2d(x, z) * 0.5 + 0.5
		if rng.randf() > dens * (0.35 + patch * 0.9):
			continue
		var y: float = height_func.call(x, z)
		var s := rng.randf_range(0.75, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s))
		tuft_t.append(Transform3D(basis, Vector3(x, y, z)))
		var v := rng.randf_range(0.85, 1.12)
		tuft_c.append(Color(v * rng.randf_range(0.95, 1.05), v, v * rng.randf_range(0.9, 1.0)))
		# Flowers cluster in noise patches
		if patch > 0.62 and rng.randf() < 0.22:
			var fs := rng.randf_range(0.8, 1.2)
			var fp := Vector3(x + rng.randf_range(-0.2, 0.2), y, z + rng.randf_range(-0.2, 0.2))
			flower_t.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * fs), fp))
			var pick := int(floor(patch_noise.get_noise_2d(x * 3.0, z * 3.0) * 2.5 + 2.5)) % petal_colors.size()
			flower_c.append(petal_colors[pick])
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = preload("res://shaders/grass_blades.gdshader")
	var flower_mat := ShaderMaterial.new()
	flower_mat.shader = preload("res://shaders/grass_blades.gdshader")
	flower_mat.set_shader_parameter("is_flower", true)
	flower_mat.set_shader_parameter("root_color", Color(0.3, 0.52, 0.24))
	flower_mat.set_shader_parameter("wind_strength", 0.03)
	StylizedMaterials.register(grass_mat)
	var g := _multimesh(_tuft_mesh(), tuft_t, tuft_c, grass_mat, false)
	g.name = "GrassTufts"
	parent.add_child(g)
	var f := _multimesh(_flower_mesh(), flower_t, flower_c, flower_mat, false)
	f.name = "Flowers"
	f.add_to_group("flowers")
	parent.add_child(f)


## Small stones (shared blob mesh) scattered by `accept`.
static func pebbles(parent: Node3D, area: Rect2, count: int, height_func: Callable, accept: Callable, rng: RandomNumberGenerator) -> void:
	var t: Array[Transform3D] = []
	var c: Array[Color] = []
	var tries := 0
	while t.size() < count and tries < count * 20:
		tries += 1
		var x := rng.randf_range(area.position.x, area.end.x)
		var z := rng.randf_range(area.position.y, area.end.y)
		if rng.randf() > accept.call(x, z):
			continue
		var s := rng.randf_range(0.06, 0.16)
		var b := Basis.from_euler(Vector3(rng.randf() * 0.4, rng.randf() * TAU, rng.randf() * 0.4)).scaled(Vector3(s, s * 0.6, s * rng.randf_range(0.8, 1.2)))
		t.append(Transform3D(b, Vector3(x, height_func.call(x, z) + s * 0.25, z)))
		c.append(Color.WHITE)
	var m := _multimesh(OrganicMesh.blob(404, 0.3), t, c, StylizedMaterials.rock(0.0), false)
	m.name = "Pebbles"
	parent.add_child(m)
