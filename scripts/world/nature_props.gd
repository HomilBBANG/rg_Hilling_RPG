class_name NatureProps
extends RefCounted
## Builders for low-poly nature props: 3 tree types, 2 bush types, 2 rock types,
## fence, shed, signpost, campfire ring. Faceted primitives so silhouettes survive pixelation.
## Tree canopies get unique materials (stored in meta "fade_mats") so they can fade when
## they cover the player.

enum TreeKind { PINE, BROADLEAF, BIRCH }


static func _fade_mat(color: Color) -> StandardMaterial3D:
	var m := ProtoMesh.unique_mat(color, 0.95)
	return m


static func tree(kind: TreeKind, scale: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var fade: Array[StandardMaterial3D] = []
	var bark := ProtoMesh.mat(Color(0.36, 0.24, 0.15))
	match kind:
		TreeKind.PINE:
			var g := _fade_mat(Color(0.14, 0.36, 0.22).lerp(Color(0.1, 0.3, 0.2), rng.randf()))
			fade.append(g)
			ProtoMesh.cylinder(root, 0.18, 1.4, Vector3(0, 0.7, 0), bark, Vector3.ZERO, 6)
			ProtoMesh.cone(root, 1.45, 1.9, Vector3(0, 1.8, 0), g)
			ProtoMesh.cone(root, 1.1, 1.6, Vector3(0, 2.75, 0), g)
			ProtoMesh.cone(root, 0.72, 1.3, Vector3(0, 3.6, 0), g)
		TreeKind.BROADLEAF:
			var g := _fade_mat(Color(0.3, 0.52, 0.2).lerp(Color(0.24, 0.46, 0.18), rng.randf()))
			fade.append(g)
			ProtoMesh.cylinder(root, 0.22, 2.2, Vector3(0, 1.1, 0), bark, Vector3.ZERO, 6, 0.16)
			ProtoMesh.cylinder(root, 0.08, 0.9, Vector3(0.35, 2.0, 0), bark, Vector3(0, 0, -40), 5)
			ProtoMesh.sphere(root, 1.35, Vector3(0, 3.0, 0), g, Vector3(1, 0.85, 1), 7, 4)
			ProtoMesh.sphere(root, 0.9, Vector3(0.85, 2.6, 0.2), g, Vector3.ONE, 6, 4)
			ProtoMesh.sphere(root, 0.85, Vector3(-0.7, 2.75, -0.35), g, Vector3.ONE, 6, 4)
			ProtoMesh.sphere(root, 0.75, Vector3(0.1, 3.7, 0.1), g, Vector3.ONE, 6, 4)
		TreeKind.BIRCH:
			var g := _fade_mat(Color(0.56, 0.66, 0.24).lerp(Color(0.48, 0.62, 0.22), rng.randf()))
			fade.append(g)
			var white := ProtoMesh.mat(Color(0.88, 0.86, 0.8))
			var mark := ProtoMesh.mat(Color(0.15, 0.14, 0.13))
			ProtoMesh.cylinder(root, 0.13, 3.2, Vector3(0, 1.6, 0), white, Vector3.ZERO, 6, 0.1)
			ProtoMesh.box(root, Vector3(0.27, 0.06, 0.27), Vector3(0, 0.9, 0), mark, Vector3(0, 20, 0))
			ProtoMesh.box(root, Vector3(0.25, 0.05, 0.25), Vector3(0, 1.7, 0), mark, Vector3(0, 60, 0))
			ProtoMesh.sphere(root, 0.95, Vector3(0, 3.5, 0), g, Vector3(1, 1.45, 1), 6, 4)
	root.scale = Vector3.ONE * scale
	root.rotation.y = rng.randf() * TAU
	root.set_meta("fade_mats", fade)
	return root


static func bush(flowering: bool, scale: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var g := ProtoMesh.mat(Color(0.2, 0.42, 0.18) if not flowering else Color(0.26, 0.48, 0.22))
	ProtoMesh.sphere(root, 0.6, Vector3(0, 0.4, 0), g, Vector3(1.2, 0.8, 1.0), 7, 4)
	ProtoMesh.sphere(root, 0.45, Vector3(0.5, 0.32, 0.2), g, Vector3.ONE, 6, 3)
	if flowering:
		var petal := ProtoMesh.mat(Color(0.95, 0.55, 0.7) if rng.randf() < 0.5 else Color(0.97, 0.92, 0.6))
		for i in 6:
			var a := rng.randf() * TAU
			ProtoMesh.sphere(root, 0.09, Vector3(cos(a) * 0.55, 0.55 + rng.randf() * 0.2, sin(a) * 0.45), petal, Vector3.ONE, 4, 2)
	root.scale = Vector3.ONE * scale
	root.rotation.y = rng.randf() * TAU
	return root


static func rock(flat: bool, scale: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var stone := ProtoMesh.mat(Color(0.52, 0.52, 0.5).lerp(Color(0.45, 0.43, 0.4), rng.randf()))
	var moss := ProtoMesh.mat(Color(0.32, 0.45, 0.22))
	if flat:
		ProtoMesh.box(root, Vector3(1.4, 0.45, 1.0), Vector3(0, 0.15, 0), stone, Vector3(4, 0, 6))
		ProtoMesh.box(root, Vector3(0.7, 0.35, 0.6), Vector3(0.5, 0.45, 0.1), stone, Vector3(-8, 30, 0))
	else:
		ProtoMesh.sphere(root, 0.7, Vector3(0, 0.35, 0), stone, Vector3(1.2, 0.85, 1.0), 6, 4)
		ProtoMesh.sphere(root, 0.4, Vector3(0.6, 0.2, 0.3), stone, Vector3.ONE, 5, 3)
		ProtoMesh.sphere(root, 0.35, Vector3(-0.1, 0.78, -0.1), moss, Vector3(1.3, 0.35, 1.2), 5, 3)
	root.scale = Vector3.ONE * scale
	root.rotation.y = rng.randf() * TAU
	return root


static func grass_tuft(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var g := ProtoMesh.mat(Color(0.42, 0.62, 0.26).lerp(Color(0.34, 0.55, 0.22), rng.randf()))
	for i in 3:
		var m := ProtoMesh.cone(root, 0.07, 0.4 + rng.randf() * 0.2, Vector3((i - 1) * 0.08, 0.2, rng.randf() * 0.08), g, 4)
		m.rotation_degrees.z = (i - 1) * 18.0
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.rotation.y = rng.randf() * TAU
	return root


## Fence from a to b (local ground y given per post by height_func).
static func fence(parent: Node3D, a: Vector3, b: Vector3, height_func: Callable) -> void:
	var wood := ProtoMesh.mat(Color(0.55, 0.38, 0.22))
	var dir := b - a
	var count := maxi(1, int(dir.length() / 1.8))
	var yaw := atan2(-dir.z, dir.x)
	for i in count + 1:
		var p := a + dir * (float(i) / count)
		p.y = height_func.call(p.x, p.z)
		ProtoMesh.box(parent, Vector3(0.14, 1.1, 0.14), p + Vector3(0, 0.55, 0), wood)
		if i < count:
			var q := a + dir * ((i + 0.5) / count)
			q.y = height_func.call(q.x, q.z)
			for ry in [0.45, 0.85]:
				ProtoMesh.box(parent, Vector3(dir.length() / count, 0.08, 0.06), q + Vector3(0, ry, 0), wood, Vector3(0, rad_to_deg(yaw), 0))
		ProtoMesh.static_box_collider(parent, Vector3(0.3, 4, 0.3), p)
	var mid := (a + b) * 0.5
	mid.y = height_func.call(mid.x, mid.z)
	ProtoMesh.static_box_collider(parent, Vector3(dir.length(), 4, 0.2), mid, Vector3(0, rad_to_deg(yaw), 0))


static func shed() -> Node3D:
	var root := Node3D.new()
	var wood := ProtoMesh.mat(Color(0.6, 0.43, 0.27))
	var dark := ProtoMesh.mat(Color(0.32, 0.22, 0.14))
	var roof := _fade_mat(Color(0.62, 0.25, 0.18))
	ProtoMesh.box(root, Vector3(3.2, 2.2, 2.6), Vector3(0, 1.1, 0), wood)
	var r := ProtoMesh.prism(root, Vector3(3.8, 1.3, 3.0), Vector3(0, 2.85, 0), roof, Vector3(0, 90, 0))
	r.scale = Vector3(1.0, 1.0, 1.25)
	ProtoMesh.box(root, Vector3(0.9, 1.7, 0.05), Vector3(0.5, 0.85, 1.31), dark)
	ProtoMesh.box(root, Vector3(0.6, 0.5, 0.05), Vector3(-0.8, 1.35, 1.31), ProtoMesh.mat(Color(0.15, 0.2, 0.28), 0.2))
	ProtoMesh.static_box_collider(root, Vector3(3.2, 6, 2.6), Vector3(0, 1.0, 0))
	root.set_meta("fade_mats", [roof] as Array[StandardMaterial3D])
	return root


static func signpost() -> Node3D:
	var root := Node3D.new()
	var wood := ProtoMesh.mat(Color(0.55, 0.38, 0.22))
	ProtoMesh.box(root, Vector3(0.12, 1.6, 0.12), Vector3(0, 0.8, 0), wood)
	ProtoMesh.box(root, Vector3(1.0, 0.32, 0.06), Vector3(0.3, 1.35, 0), ProtoMesh.mat(Color(0.75, 0.6, 0.38)), Vector3(0, 0, -6))
	return root


static func campfire_ring(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var stone := ProtoMesh.mat(Color(0.5, 0.5, 0.48))
	var log_mat := ProtoMesh.mat(Color(0.35, 0.22, 0.12))
	for i in 8:
		var a := i * TAU / 8.0
		ProtoMesh.sphere(root, 0.18, Vector3(cos(a) * 0.65, 0.1, sin(a) * 0.65), stone, Vector3(1, 0.7, 1), 5, 3)
	ProtoMesh.cylinder(root, 0.07, 0.8, Vector3(0, 0.12, 0), log_mat, Vector3(0, 30, 80), 5)
	ProtoMesh.cylinder(root, 0.07, 0.8, Vector3(0, 0.16, 0), log_mat, Vector3(0, -40, 80), 5)
	# Two log seats
	for s in [-1.0, 1.0]:
		ProtoMesh.cylinder(root, 0.22, 1.4, Vector3(s * 1.7, 0.22, 0.3 * s), log_mat, Vector3(0, 10 * s, 90), 7)
	root.rotation.y = rng.randf() * TAU
	return root
