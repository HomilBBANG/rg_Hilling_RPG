class_name NatureProps
extends RefCounted
## Stylized nature props: organic noisy blobs + foliage/rock shaders instead of raw primitives.
## Tree canopies get unique materials (meta "fade_mats") so they can dither-fade over the player.

enum TreeKind { PINE, BROADLEAF, BIRCH, BLOSSOM }

const PALETTES := {
	# [base, light, dark] — after the user's reference tree: lime top, fresh mid green, deep green underside
	TreeKind.BROADLEAF: [Color(0.38, 0.56, 0.22), Color(0.55, 0.69, 0.29), Color(0.21, 0.4, 0.19)],
	TreeKind.PINE: [Color(0.22, 0.43, 0.26), Color(0.36, 0.56, 0.28), Color(0.11, 0.28, 0.22)],
	TreeKind.BIRCH: [Color(0.46, 0.62, 0.23), Color(0.62, 0.74, 0.33), Color(0.29, 0.46, 0.19)],
	TreeKind.BLOSSOM: [Color(0.93, 0.62, 0.7), Color(1.0, 0.86, 0.88), Color(0.66, 0.36, 0.47)],
}


static func _bark() -> StandardMaterial3D:
	return ProtoMesh.mat(Color(0.42, 0.29, 0.2))


static func tree(kind: TreeKind, scale: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var pal: Array = PALETTES[kind]
	var leaves := StylizedMaterials.foliage(pal[0], pal[1], pal[2], rng.randf_range(-1.0, 1.0))
	var seed := rng.randi() % 1000
	var lean := Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
	match kind:
		TreeKind.PINE:
			OrganicMesh.trunk(root, 0.2, 0.1, 2.0, Vector3.ZERO, _bark(), lean * 0.4)
			var tiers := [[1.55, 1.2, 1.25], [1.3, 1.1, 2.0], [1.02, 1.0, 2.75], [0.72, 0.95, 3.45], [0.4, 0.8, 4.05]]
			for t: Array in tiers:
				var c := ProtoMesh.cylinder(root, t[0], t[1], Vector3(0, t[2], 0), leaves, Vector3(0, rng.randf() * 60.0, 0), 9, t[0] * 0.18)
				c.material_override = leaves
		TreeKind.BIRCH:
			var white := ProtoMesh.mat(Color(0.92, 0.9, 0.84))
			var mark := ProtoMesh.mat(Color(0.18, 0.16, 0.15))
			OrganicMesh.trunk(root, 0.13, 0.08, 3.4, Vector3.ZERO, white, lean)
			for i in 4:
				ProtoMesh.box(root, Vector3(0.2, 0.05, 0.08), Vector3(0.04, 0.6 + i * 0.6, 0.1), mark, Vector3(0, rng.randf() * 180.0, 0))
			OrganicMesh.blob_instance(root, seed, Vector3(0, 3.4, 0), Vector3(0.95, 1.35, 0.95), leaves)
			OrganicMesh.blob_instance(root, seed + 1, Vector3(0.45, 2.9, 0.2), Vector3(0.6, 0.75, 0.6), leaves)
			OrganicMesh.blob_instance(root, seed + 2, Vector3(-0.35, 4.1, -0.1), Vector3(0.55, 0.7, 0.55), leaves)
		_:
			var small := kind == TreeKind.BLOSSOM
			var h := 2.0 if small else 2.4
			OrganicMesh.trunk(root, 0.24, 0.14, h, Vector3.ZERO, _bark(), lean)
			ProtoMesh.cylinder(root, 0.08, 1.1, Vector3(0.4, h - 0.3, 0.1), _bark(), Vector3(0, 0, -48), 5, 0.04)
			ProtoMesh.cylinder(root, 0.07, 0.9, Vector3(-0.32, h - 0.2, -0.2), _bark(), Vector3(30, 0, 40), 5, 0.04)
			var cy := h + 0.8
			var s := 0.8 if small else 1.0
			OrganicMesh.blob_instance(root, seed, Vector3(0, cy, 0), Vector3(1.45, 1.1, 1.4) * s, leaves)
			var ring := 5
			for i in ring:
				var a := TAU * i / ring + rng.randf() * 0.6
				var r := rng.randf_range(0.8, 1.15) * s
				OrganicMesh.blob_instance(root, seed + 3 + i, Vector3(cos(a) * r, cy + rng.randf_range(-0.55, 0.35), sin(a) * r),
					Vector3.ONE * rng.randf_range(0.7, 0.95) * s, leaves)
			OrganicMesh.blob_instance(root, seed + 11, Vector3(0.1, cy + 0.85 * s, 0.05), Vector3(0.85, 0.7, 0.85) * s, leaves)
	root.scale = Vector3.ONE * scale
	root.rotation.y = rng.randf() * TAU
	root.set_meta("fade_mats", [leaves])
	return root


static func bush(kind: int, scale: float, rng: RandomNumberGenerator) -> Node3D:
	## kind 0 = plain, 1 = flowering, 2 = berries
	var root := Node3D.new()
	var leaves := StylizedMaterials.foliage(Color(0.34, 0.53, 0.21), Color(0.51, 0.66, 0.27), Color(0.18, 0.37, 0.17), rng.randf_range(-1, 1))
	leaves.set_shader_parameter("wind_strength", 0.05)  # low and stiff: less sway than canopies
	var seed := rng.randi() % 1000
	OrganicMesh.blob_instance(root, seed, Vector3(0, 0.38, 0), Vector3(0.65, 0.45, 0.6), leaves)
	OrganicMesh.blob_instance(root, seed + 1, Vector3(0.45, 0.28, 0.15), Vector3(0.42, 0.32, 0.42), leaves)
	OrganicMesh.blob_instance(root, seed + 2, Vector3(-0.38, 0.26, -0.1), Vector3(0.38, 0.3, 0.4), leaves)
	if kind > 0:
		var dot_color := Color(0.98, 0.94, 0.85) if rng.randf() < 0.5 else Color(0.96, 0.62, 0.74)
		if kind == 2:
			dot_color = Color(0.85, 0.16, 0.18)
		var dm := ProtoMesh.mat(dot_color, 0.6)
		for i in 9:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.25, 0.6)
			var p := Vector3(cos(a) * r, 0.5 + rng.randf() * 0.25, sin(a) * r * 0.8)
			ProtoMesh.sphere(root, 0.065, p, dm, Vector3.ONE, 5, 3).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.scale = Vector3.ONE * scale
	root.rotation.y = rng.randf() * TAU
	return root


static func rock(big: bool, scale: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var mat := StylizedMaterials.rock(0.55 if big else 0.25)
	var seed := rng.randi() % 1000
	if big:
		OrganicMesh.blob_instance(root, seed, Vector3(0, 0.35, 0), Vector3(0.95, 0.62, 0.8), mat, 0.32)
		OrganicMesh.blob_instance(root, seed + 1, Vector3(0.7, 0.18, 0.35), Vector3(0.42, 0.3, 0.4), mat, 0.3)
		OrganicMesh.blob_instance(root, seed + 2, Vector3(-0.55, 0.12, 0.45), Vector3(0.25, 0.18, 0.25), mat, 0.3)
	else:
		OrganicMesh.blob_instance(root, seed, Vector3(0, 0.12, 0), Vector3(0.32, 0.2, 0.28), mat, 0.3)
	root.scale = Vector3.ONE * scale
	root.rotation.y = rng.randf() * TAU
	return root


static func log_prop(length: float, radius: float) -> Node3D:
	var root := Node3D.new()
	var bark := _bark()
	var wood := ProtoMesh.mat(Color(0.86, 0.7, 0.48))
	var ring := ProtoMesh.mat(Color(0.7, 0.52, 0.32))
	ProtoMesh.cylinder(root, radius, length, Vector3(0, radius, 0), bark, Vector3(0, 0, 90), 8)
	for s in [-1.0, 1.0]:
		ProtoMesh.cylinder(root, radius * 0.92, 0.03, Vector3(s * length * 0.5, radius, 0), wood, Vector3(0, 0, 90), 8)
		ProtoMesh.cylinder(root, radius * 0.45, 0.035, Vector3(s * length * 0.5, radius, 0), ring, Vector3(0, 0, 90), 8)
	return root


static func stump(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	OrganicMesh.trunk(root, 0.32, 0.28, 0.45, Vector3.ZERO, _bark())
	ProtoMesh.cylinder(root, 0.27, 0.03, Vector3(0, 0.46, 0), ProtoMesh.mat(Color(0.86, 0.7, 0.48)), Vector3.ZERO, 8)
	ProtoMesh.cylinder(root, 0.12, 0.035, Vector3(0, 0.465, 0), ProtoMesh.mat(Color(0.7, 0.52, 0.32)), Vector3.ZERO, 8)
	root.rotation.y = rng.randf() * TAU
	return root


static func mushrooms(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var stem := ProtoMesh.mat(Color(0.95, 0.92, 0.84))
	var cap := ProtoMesh.mat(Color(0.86, 0.25, 0.2))
	var dot := ProtoMesh.mat(Color(1, 0.97, 0.9))
	for i in 3:
		var p := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var h := rng.randf_range(0.1, 0.18)
		ProtoMesh.cylinder(root, 0.03, h, p + Vector3(0, h * 0.5, 0), stem, Vector3.ZERO, 6)
		ProtoMesh.sphere(root, 0.09, p + Vector3(0, h, 0), cap, Vector3(1, 0.55, 1), 8, 4)
		ProtoMesh.sphere(root, 0.02, p + Vector3(0.03, h + 0.045, 0.02), dot, Vector3.ONE, 4, 2)
	return root


## Wooden fence from a to b with slightly uneven posts.
static func fence(parent: Node3D, a: Vector3, b: Vector3, height_func: Callable, rng: RandomNumberGenerator) -> void:
	var wood := ProtoMesh.mat(Color(0.62, 0.44, 0.27))
	var wood_dark := ProtoMesh.mat(Color(0.48, 0.33, 0.2))
	var dir := b - a
	var count := maxi(1, int(dir.length() / 1.6))
	var yaw := rad_to_deg(atan2(-dir.z, dir.x))
	for i in count + 1:
		var p := a + dir * (float(i) / count)
		p.y = height_func.call(p.x, p.z)
		var h := rng.randf_range(0.95, 1.15)
		ProtoMesh.box(parent, Vector3(0.13, h, 0.13), p + Vector3(0, h * 0.5, 0), wood_dark, Vector3(rng.randf_range(-4, 4), yaw, rng.randf_range(-4, 4)))
		ProtoMesh.box(parent, Vector3(0.16, 0.05, 0.16), p + Vector3(0, h + 0.01, 0), wood, Vector3(0, yaw + 45.0, 0))
		if i < count:
			var q := a + dir * ((i + 0.5) / count)
			q.y = height_func.call(q.x, q.z)
			for ry in [0.42, 0.78]:
				ProtoMesh.box(parent, Vector3(dir.length() / count + 0.1, 0.07, 0.05), q + Vector3(0, ry, 0), wood,
					Vector3(0, yaw, rng.randf_range(-2.5, 2.5)))
	var mid := (a + b) * 0.5
	mid.y = height_func.call(mid.x, mid.z)
	ProtoMesh.static_box_collider(parent, Vector3(dir.length(), 4, 0.25), mid, Vector3(0, yaw, 0))


static func shed() -> Node3D:
	var root := Node3D.new()
	var wood := ProtoMesh.mat(Color(0.66, 0.48, 0.3))
	var plank := ProtoMesh.mat(Color(0.56, 0.4, 0.25))
	var dark := ProtoMesh.mat(Color(0.32, 0.22, 0.14))
	var roof := ProtoMesh.unique_mat(Color(0.7, 0.32, 0.24), 0.85)
	var trim := ProtoMesh.mat(Color(0.93, 0.88, 0.76))
	ProtoMesh.box(root, Vector3(3.2, 2.2, 2.6), Vector3(0, 1.1, 0), wood)
	for i in 5:
		ProtoMesh.box(root, Vector3(0.04, 2.2, 0.02), Vector3(-1.4 + i * 0.7, 1.1, 1.31), plank)
	var r := ProtoMesh.prism(root, Vector3(3.8, 1.3, 3.0), Vector3(0, 2.85, 0), roof, Vector3(0, 90, 0))
	r.scale = Vector3(1.0, 1.0, 1.25)
	ProtoMesh.box(root, Vector3(0.9, 1.7, 0.05), Vector3(0.5, 0.85, 1.33), dark)
	ProtoMesh.box(root, Vector3(1.0, 0.08, 0.06), Vector3(0.5, 1.74, 1.34), trim)
	ProtoMesh.box(root, Vector3(0.6, 0.5, 0.05), Vector3(-0.8, 1.35, 1.33), ProtoMesh.mat(Color(0.2, 0.28, 0.38), 0.2))
	ProtoMesh.box(root, Vector3(0.7, 0.06, 0.06), Vector3(-0.8, 1.08, 1.36), trim)
	ProtoMesh.box(root, Vector3(0.7, 0.15, 0.2), Vector3(-0.8, 1.0, 1.42), ProtoMesh.mat(Color(0.5, 0.33, 0.2)))
	ProtoMesh.static_box_collider(root, Vector3(3.2, 6, 2.6), Vector3(0, 1.0, 0))
	root.set_meta("fade_mats", [roof])
	return root


static func signpost() -> Node3D:
	var root := Node3D.new()
	var wood := ProtoMesh.mat(Color(0.55, 0.38, 0.22))
	ProtoMesh.box(root, Vector3(0.12, 1.6, 0.12), Vector3(0, 0.8, 0), wood)
	ProtoMesh.box(root, Vector3(1.0, 0.3, 0.06), Vector3(0.3, 1.35, 0.02), ProtoMesh.mat(Color(0.82, 0.66, 0.42)), Vector3(0, 0, -6))
	ProtoMesh.box(root, Vector3(0.8, 0.26, 0.06), Vector3(-0.25, 1.0, 0.02), ProtoMesh.mat(Color(0.76, 0.6, 0.38)), Vector3(0, 0, 5))
	return root
