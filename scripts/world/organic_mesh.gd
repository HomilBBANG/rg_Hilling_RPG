class_name OrganicMesh
extends RefCounted
## Procedural meshes that avoid the "primitive/blocky" look:
## noisy blobs (rocks, foliage clumps), tapered trunks and extruded rounded profiles (camper body).

static var _blob_cache := {}


## Icosphere-like blob with smooth noise displacement. Cached per (seed, roughness).
static func blob(seed: int, roughness := 0.25, subdiv := 2) -> ArrayMesh:
	var key := "%d|%.2f|%d" % [seed, roughness, subdiv]
	if _blob_cache.has(key):
		return _blob_cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 1.4
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 8 + subdiv * 4
	sm.rings = 4 + subdiv * 2
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		var d := 1.0 + noise.get_noise_3dv(v * 1.0) * roughness * 2.0
		verts[i] = v * d
	arrays[Mesh.ARRAY_VERTEX] = verts
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	var mesh := st.commit()
	_blob_cache[key] = mesh
	return mesh


static func blob_instance(parent: Node3D, seed: int, pos: Vector3, scale: Vector3, material: Material, roughness := 0.25, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = blob(seed, roughness)
	mi.position = pos
	mi.scale = scale
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Tapered, slightly bent trunk from `base` going up `height`.
static func trunk(parent: Node3D, base_radius: float, top_radius: float, height: float, pos: Vector3, material: Material, lean_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = base_radius
	m.top_radius = top_radius
	m.height = height
	m.radial_segments = 7
	m.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.rotation_degrees = lean_deg
	# pivot at the base
	mi.position = pos + (Basis.from_euler(lean_deg * PI / 180.0) * Vector3(0, height * 0.5, 0))
	parent.add_child(mi)
	# root flare
	var flare := CylinderMesh.new()
	flare.bottom_radius = base_radius * 1.6
	flare.top_radius = base_radius
	flare.height = base_radius * 1.4
	flare.radial_segments = 7
	flare.rings = 1
	var fi := MeshInstance3D.new()
	fi.mesh = flare
	fi.material_override = material
	fi.position = pos + Vector3(0, base_radius * 0.7, 0)
	parent.add_child(fi)
	return mi


## Rounded rectangle polygon (counter-clockwise), corner radius r, n segments per corner.
static func rounded_rect(min_p: Vector2, max_p: Vector2, r: float, n := 4) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var centers := [Vector2(max_p.x - r, min_p.y + r), Vector2(max_p.x - r, max_p.y - r),
			Vector2(min_p.x + r, max_p.y - r), Vector2(min_p.x + r, min_p.y + r)]
	var start_angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for c in 4:
		for i in n + 1:
			var a: float = start_angles[c] + (PI * 0.5) * float(i) / n
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * r)
	return pts


## Extrudes a counter-clockwise XY profile along Z (total `width`), with bevelled side edges.
## Side band normals are smoothed where neighbouring edges bend less than `smooth_deg`.
static func extrude_profile(profile: PackedVector2Array, width: float, bevel: float, smooth_deg := 35.0) -> ArrayMesh:
	var n := profile.size()
	var edge_normals: Array[Vector2] = []
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		var e := (b - a).normalized()
		edge_normals.append(Vector2(e.y, -e.x))  # outward for CCW polygons
	# Vertex (miter) normals for the inset cap polygon
	var inset := PackedVector2Array()
	for i in n:
		var n0 := edge_normals[(i - 1 + n) % n]
		var n1 := edge_normals[i]
		var m := (n0 + n1).normalized()
		var denom := maxf(0.35, m.dot(n1))
		inset.append(profile[i] - m * (bevel / denom))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := width * 0.5
	var bz := hz - bevel
	var cos_smooth := cos(deg_to_rad(smooth_deg))
	# Band (roof/front/back) between z = -bz .. +bz
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		var ne := edge_normals[i]
		var na := ne
		var nb := ne
		if edge_normals[(i - 1 + n) % n].dot(ne) > cos_smooth:
			na = (edge_normals[(i - 1 + n) % n] + ne).normalized()
		if edge_normals[(i + 1) % n].dot(ne) > cos_smooth:
			nb = (edge_normals[(i + 1) % n] + ne).normalized()
		_quad(st,
			[Vector3(a.x, a.y, bz), Vector3(b.x, b.y, bz), Vector3(b.x, b.y, -bz), Vector3(a.x, a.y, -bz)],
			[Vector3(na.x, na.y, 0), Vector3(nb.x, nb.y, 0), Vector3(nb.x, nb.y, 0), Vector3(na.x, na.y, 0)])
		# Bevels to both caps
		for side in [1.0, -1.0]:
			var z_out: float = side * bz
			var z_in: float = side * hz
			var ia := inset[i]
			var ib := inset[(i + 1) % n]
			var bn_a := (Vector3(na.x, na.y, 0) + Vector3(0, 0, side)).normalized()
			var bn_b := (Vector3(nb.x, nb.y, 0) + Vector3(0, 0, side)).normalized()
			var q := [Vector3(a.x, a.y, z_out), Vector3(b.x, b.y, z_out), Vector3(ib.x, ib.y, z_in), Vector3(ia.x, ia.y, z_in)]
			var qn := [bn_a, bn_b, bn_b, bn_a]
			if side < 0.0:
				q.reverse()
				qn.reverse()
			_quad(st, q, qn)
	# Caps
	var tri := Geometry2D.triangulate_polygon(inset)
	for side in [1.0, -1.0]:
		var z: float = side * hz
		for t in range(0, tri.size(), 3):
			var idx := [tri[t], tri[t + 1], tri[t + 2]]
			var p0 := Vector3(inset[idx[0]].x, inset[idx[0]].y, z)
			var p1 := Vector3(inset[idx[1]].x, inset[idx[1]].y, z)
			var p2 := Vector3(inset[idx[2]].x, inset[idx[2]].y, z)
			if (p2 - p0).cross(p1 - p0).z * side < 0.0:
				idx.reverse()
			for k: int in idx:
				st.set_normal(Vector3(0, 0, side))
				st.add_vertex(Vector3(inset[k].x, inset[k].y, z))
	return st.commit()


## Adds a quad (v0..v3) as two triangles; picks winding so the face matches its normal.
static func _quad(st: SurfaceTool, v: Array, nrm: Array) -> void:
	var face := ((v[2] - v[0]) as Vector3).cross(v[1] - v[0])
	var avg: Vector3 = nrm[0] + nrm[1] + nrm[2] + nrm[3]
	var order := [0, 1, 2, 0, 2, 3]
	if face.dot(avg) < 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k: int in order:
		st.set_normal(nrm[k])
		st.add_vertex(v[k])
