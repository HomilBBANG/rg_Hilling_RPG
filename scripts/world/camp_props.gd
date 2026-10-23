class_name CampProps
extends RefCounted
## Cosy camp-life props around the camper.

static func _checker_texture(a: Color, b: Color, cells: int) -> ImageTexture:
	var img := Image.create(cells, cells, false, Image.FORMAT_RGB8)
	for y in cells:
		for x in cells:
			img.set_pixel(x, y, a if (x + y) % 2 == 0 else b)
	return ImageTexture.create_from_image(img)


static func picnic_rug(size: Vector2) -> Node3D:
	var root := Node3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_texture = _checker_texture(Color(0.86, 0.36, 0.33), Color(0.97, 0.93, 0.84), 8)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(3, 2, 1)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.roughness = 0.9
	ProtoMesh.box(root, Vector3(size.x, 0.02, size.y), Vector3(0, 0.012, 0), m)
	return root


static func chair(fabric: Color) -> Node3D:
	## Folding camp chair facing local -Z.
	var root := Node3D.new()
	var frame := ProtoMesh.mat(Color(0.25, 0.26, 0.28), 0.5)
	var cloth := ProtoMesh.mat(fabric, 0.9)
	for s in [-1.0, 1.0]:
		ProtoMesh.box(root, Vector3(0.03, 0.62, 0.03), Vector3(s * 0.26, 0.28, 0.0), frame, Vector3(30, 0, 0))
		ProtoMesh.box(root, Vector3(0.03, 0.62, 0.03), Vector3(s * 0.26, 0.28, 0.0), frame, Vector3(-30, 0, 0))
		ProtoMesh.box(root, Vector3(0.05, 0.04, 0.45), Vector3(s * 0.29, 0.6, 0.02), frame)
	ProtoMesh.box(root, Vector3(0.52, 0.05, 0.44), Vector3(0, 0.42, 0.0), cloth, Vector3(-8, 0, 0))
	ProtoMesh.box(root, Vector3(0.52, 0.5, 0.05), Vector3(0, 0.7, 0.24), cloth, Vector3(-15, 0, 0))
	return root


static func folding_table() -> Node3D:
	var root := Node3D.new()
	var wood := ProtoMesh.mat(Color(0.78, 0.6, 0.38))
	var wood_dark := ProtoMesh.mat(Color(0.6, 0.43, 0.26))
	var metal := ProtoMesh.mat(Color(0.35, 0.36, 0.38), 0.5)
	for i in 5:
		ProtoMesh.box(root, Vector3(0.9, 0.04, 0.11), Vector3(0, 0.68, -0.24 + i * 0.12), wood if i % 2 == 0 else wood_dark)
	for sx in [-0.38, 0.38]:
		for sz in [-0.24, 0.24]:
			ProtoMesh.box(root, Vector3(0.03, 0.68, 0.03), Vector3(sx, 0.34, sz), metal)
	# Items: lantern, mugs, cutting board with bread, fruit bowl
	var lantern_body := ProtoMesh.mat(Color(0.2, 0.36, 0.34), 0.5)
	ProtoMesh.box(root, Vector3(0.12, 0.03, 0.12), Vector3(-0.28, 0.72, 0.05), lantern_body)
	ProtoMesh.box(root, Vector3(0.09, 0.13, 0.09), Vector3(-0.28, 0.8, 0.05), ProtoMesh.mat(Color(1.0, 0.86, 0.55), 0.4, Color(1.0, 0.75, 0.4), 1.5))
	ProtoMesh.box(root, Vector3(0.12, 0.03, 0.12), Vector3(-0.28, 0.88, 0.05), lantern_body)
	ProtoMesh.cylinder(root, 0.045, 0.09, Vector3(0.05, 0.745, -0.1), ProtoMesh.mat(Color(0.92, 0.48, 0.38)), Vector3.ZERO, 8)
	ProtoMesh.cylinder(root, 0.045, 0.09, Vector3(0.17, 0.745, 0.08), ProtoMesh.mat(Color(0.38, 0.62, 0.72)), Vector3.ZERO, 8)
	ProtoMesh.box(root, Vector3(0.28, 0.02, 0.18), Vector3(0.25, 0.71, -0.12), wood_dark)
	ProtoMesh.sphere(root, 0.07, Vector3(0.25, 0.75, -0.12), ProtoMesh.mat(Color(0.86, 0.62, 0.32)), Vector3(1.4, 0.7, 1.0), 6, 3)
	ProtoMesh.cylinder(root, 0.1, 0.05, Vector3(-0.05, 0.725, 0.15), ProtoMesh.mat(Color(0.95, 0.92, 0.85)), Vector3.ZERO, 10)
	ProtoMesh.sphere(root, 0.04, Vector3(-0.07, 0.765, 0.14), ProtoMesh.mat(Color(0.85, 0.2, 0.18)), Vector3.ONE, 5, 3)
	ProtoMesh.sphere(root, 0.04, Vector3(-0.02, 0.765, 0.17), ProtoMesh.mat(Color(0.98, 0.72, 0.25)), Vector3.ONE, 5, 3)
	return root


static func cooler() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = OrganicMesh.extrude_profile(OrganicMesh.rounded_rect(Vector2(-0.32, 0.0), Vector2(0.32, 0.38), 0.06, 2), 0.4, 0.03)
	body.material_override = ProtoMesh.mat(Color(0.3, 0.6, 0.72), 0.6)
	root.add_child(body)
	ProtoMesh.box(root, Vector3(0.66, 0.07, 0.42), Vector3(0, 0.41, 0), ProtoMesh.mat(Color(0.96, 0.95, 0.9)))
	ProtoMesh.box(root, Vector3(0.3, 0.04, 0.05), Vector3(0, 0.46, 0), ProtoMesh.mat(Color(0.25, 0.26, 0.28)))
	return root


static func firewood_pile(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var rows := [[4, 0.0], [3, 0.2], [2, 0.4]]
	for r: Array in rows:
		for i in r[0]:
			var l := NatureProps.log_prop(rng.randf_range(0.8, 0.95), 0.1)
			l.rotation_degrees.y = 90.0 + rng.randf_range(-6, 6)
			l.position = Vector3(0, r[1], (i - (r[0] - 1) * 0.5) * 0.21)
			root.add_child(l)
	# Chopping stump with an axe
	var stump := NatureProps.stump(rng)
	stump.position = Vector3(1.0, 0, 0.3)
	root.add_child(stump)
	ProtoMesh.box(root, Vector3(0.04, 0.55, 0.04), Vector3(1.05, 0.68, 0.32), ProtoMesh.mat(Color(0.62, 0.45, 0.28)), Vector3(0, 0, -25))
	ProtoMesh.box(root, Vector3(0.18, 0.1, 0.03), Vector3(0.98, 0.48, 0.32), ProtoMesh.mat(Color(0.7, 0.72, 0.75), 0.3), Vector3(0, 0, -25))
	return root


static func campfire(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var stone := StylizedMaterials.rock(0.0)
	for i in 9:
		var a := TAU * i / 9.0
		OrganicMesh.blob_instance(root, 50 + i, Vector3(cos(a) * 0.62, 0.08, sin(a) * 0.62), Vector3(0.17, 0.12, 0.15) * rng.randf_range(0.85, 1.2), stone, 0.3)
	ProtoMesh.cylinder(root, 0.5, 0.02, Vector3(0, 0.01, 0), ProtoMesh.mat(Color(0.22, 0.18, 0.16)), Vector3.ZERO, 10)
	for a in [20.0, 80.0, 140.0]:
		var l := NatureProps.log_prop(0.75, 0.07)
		l.rotation_degrees = Vector3(0, a, 18)
		l.position = Vector3(0, 0.02, 0)
		root.add_child(l)
	var flame := CampfireFlame.new()
	flame.position = Vector3(0, 0.08, 0)
	root.add_child(flame)
	return root


static func potted_plant(rng: RandomNumberGenerator, flowering: bool) -> Node3D:
	var root := Node3D.new()
	var pot := ProtoMesh.mat(Color(0.8, 0.45, 0.3))
	ProtoMesh.cylinder(root, 0.17, 0.3, Vector3(0, 0.15, 0), pot, Vector3.ZERO, 9, 0.21)
	ProtoMesh.cylinder(root, 0.23, 0.05, Vector3(0, 0.31, 0), ProtoMesh.mat(Color(0.86, 0.52, 0.36)), Vector3.ZERO, 9)
	var leaves := StylizedMaterials.foliage(Color(0.36, 0.55, 0.22), Color(0.53, 0.68, 0.28), Color(0.2, 0.39, 0.18))
	OrganicMesh.blob_instance(root, rng.randi() % 500, Vector3(0, 0.5, 0), Vector3(0.26, 0.24, 0.26), leaves)
	if flowering:
		var c := Color(0.96, 0.6, 0.72) if rng.randf() < 0.5 else Color(0.99, 0.85, 0.4)
		for i in 5:
			var a := TAU * i / 5.0
			ProtoMesh.sphere(root, 0.05, Vector3(cos(a) * 0.16, 0.62, sin(a) * 0.16), ProtoMesh.mat(c), Vector3.ONE, 5, 3)
	return root


static func lantern_post() -> Node3D:
	var root := Node3D.new()
	var wood := ProtoMesh.mat(Color(0.5, 0.35, 0.22))
	ProtoMesh.box(root, Vector3(0.1, 1.9, 0.1), Vector3(0, 0.95, 0), wood)
	ProtoMesh.box(root, Vector3(0.5, 0.07, 0.07), Vector3(0.2, 1.85, 0), wood)
	var frame := ProtoMesh.mat(Color(0.2, 0.2, 0.22))
	ProtoMesh.box(root, Vector3(0.16, 0.03, 0.16), Vector3(0.38, 1.66, 0), frame)
	ProtoMesh.box(root, Vector3(0.12, 0.17, 0.12), Vector3(0.38, 1.56, 0), ProtoMesh.mat(Color(1.0, 0.86, 0.55), 0.4, Color(1.0, 0.72, 0.38), 2.0))
	ProtoMesh.box(root, Vector3(0.16, 0.03, 0.16), Vector3(0.38, 1.46, 0), frame)
	var l := OmniLight3D.new()
	l.position = Vector3(0.38, 1.5, 0)
	l.light_color = Color(1.0, 0.75, 0.45)
	l.light_energy = 0.9
	l.omni_range = 4.0
	root.add_child(l)
	return root


static func crate_stack() -> Node3D:
	var root := Node3D.new()
	var wood := ProtoMesh.mat(Color(0.72, 0.55, 0.34))
	var slat := ProtoMesh.mat(Color(0.58, 0.42, 0.25))
	for spec in [[Vector3(0, 0.22, 0), 0.0], [Vector3(0.48, 0.2, 0.05), 12.0], [Vector3(0.15, 0.62, 0.02), -8.0]]:
		var p: Vector3 = spec[0]
		var s := 0.44 if p.y < 0.5 else 0.38
		ProtoMesh.box(root, Vector3(s, s, s), p, wood, Vector3(0, spec[1], 0))
		ProtoMesh.box(root, Vector3(s + 0.01, 0.05, s + 0.01), p + Vector3(0, s * 0.25, 0), slat, Vector3(0, spec[1], 0))
	ProtoMesh.sphere(root, 0.07, Vector3(0.12, 0.85, 0.0), ProtoMesh.mat(Color(0.85, 0.22, 0.18)), Vector3.ONE, 5, 3)
	ProtoMesh.sphere(root, 0.07, Vector3(0.22, 0.85, 0.06), ProtoMesh.mat(Color(0.95, 0.65, 0.2)), Vector3.ONE, 5, 3)
	return root


static func clothesline(a: Vector3, b: Vector3) -> Node3D:
	var root := Node3D.new()
	var pole := ProtoMesh.mat(Color(0.5, 0.35, 0.22))
	for p in [a, b]:
		ProtoMesh.box(root, Vector3(0.07, 1.8, 0.07), p + Vector3(0, 0.9, 0), pole)
	var dir := b - a
	var yaw := rad_to_deg(atan2(-dir.z, dir.x))
	ProtoMesh.box(root, Vector3(dir.length(), 0.015, 0.015), (a + b) * 0.5 + Vector3(0, 1.7, 0), ProtoMesh.mat(Color(0.9, 0.9, 0.86)), Vector3(0, yaw, 0))
	var cloth_cols := [Color(0.95, 0.85, 0.45), Color(0.45, 0.65, 0.85), Color(0.95, 0.95, 0.92), Color(0.9, 0.5, 0.45)]
	for i in 4:
		var t := 0.2 + i * 0.2
		# Pegged at the top on the line; the cloth swings with the wind (WindSway).
		var peg := WindSway.new()
		peg.position = a.lerp(b, t) + Vector3(0, 1.68, 0)
		peg.strength = 0.32
		root.add_child(peg)
		ProtoMesh.box(peg, Vector3(0.38, 0.45, 0.02), Vector3(0, -0.23, 0), ProtoMesh.mat(cloth_cols[i]), Vector3(0, yaw, randf_range(-4, 4)))
	return root
