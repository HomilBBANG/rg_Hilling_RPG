class_name CityBuilder
extends RefCounted
## Towns from region data ("cities" in data/regions/*.json): a stone-walled capital with a castle,
## or a palisaded village; houses on lots off the streets, a paved plaza with a fountain or well,
## market stalls, lamp posts and a name sign at the gate. Placeholder art in the project's
## ProtoMesh style; every building has a collider and fades like trees when it hides the player.
##
## City: {"id", "name", "kind": "capital" | "village", "center": [x, z], "size": [w, d],
##   "gate": "south" | "north" | "east" | "west", "houses": n, "seed": n, "castle": [x, z],
##   "plaza": {"center", "radius"}, "market": bool, "arrival": {"pos", "yaw"}, "parking": {...}}

const WALL_H := 3.4
const WALL_T := 1.2
const GATE_W := 7.0
const LOT := 9.0

static var _plaster := [Color(0.93, 0.88, 0.78), Color(0.88, 0.82, 0.7), Color(0.95, 0.92, 0.86), Color(0.84, 0.78, 0.66)]
static var _roofs := [Color(0.72, 0.3, 0.24), Color(0.36, 0.42, 0.62), Color(0.5, 0.36, 0.26), Color(0.62, 0.42, 0.24)]


static func build(lab: VisualLab, city: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(city.get("seed", 1))
	var c := RegionDB.v3(city["center"])
	var size := TerrainField._v2(city.get("size", null), Vector2(40, 36))
	var village := str(city.get("kind", "village")) == "village"
	var root := Node3D.new()
	root.name = "City_" + str(city.get("id", ""))
	lab.add_child(root)
	lab._block(c.x, c.z, size.length() * 0.5 + 3.0)  # no wild trees / rocks inside
	var gate := str(city.get("gate", "south"))
	if village:
		_palisade(root, c, size, gate)
	else:
		_walls(root, c, size, gate)
	var plaza: Dictionary = city.get("plaza", {})
	var pc := RegionDB.v3(plaza.get("center", city["center"]))
	var pr := float(plaza.get("radius", 6.0))
	_plaza(lab, root, pc, pr, village)
	var avoid: Array[Vector3] = [Vector3(pc.x, pc.z, pr + 5.0)]
	if city.has("castle"):
		var k := RegionDB.v3(city["castle"])
		_castle(lab, root, k)
		avoid.append(Vector3(k.x, k.z, 17.0))
	if city.get("market", false):
		for i in 4:
			var a := TAU * (i + 0.5) / 4.0
			_stall(root, pc + Vector3(cos(a), 0, sin(a)) * (pr + 2.6), rng, a)
	_houses(lab, root, c, size, int(city.get("houses", 8)), avoid, village, rng)
	# name sign outside the gate
	var g := _gate_point(c, size, gate)
	var out := _gate_dir(gate)
	var sign := NatureProps.signpost()
	sign.position = g + out * 3.0 + out.cross(Vector3.UP) * 4.5
	root.add_child(sign)


static func _gate_dir(gate: String) -> Vector3:
	match gate:
		"north":
			return Vector3(0, 0, -1)
		"east":
			return Vector3(1, 0, 0)
		"west":
			return Vector3(-1, 0, 0)
	return Vector3(0, 0, 1)


static func _gate_point(c: Vector3, size: Vector2, gate: String) -> Vector3:
	var d := _gate_dir(gate)
	return c + Vector3(d.x * size.x * 0.5, 0, d.z * size.y * 0.5)


## Stone walls around the rectangle with corner and gate towers; the gate side has a gap.
static func _walls(root: Node3D, c: Vector3, size: Vector2, gate: String) -> void:
	var stone := ProtoMesh.mat(Color(0.7, 0.68, 0.62))
	var dark := ProtoMesh.mat(Color(0.52, 0.5, 0.46))
	var roof := ProtoMesh.mat(Color(0.36, 0.42, 0.62))
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var sides := {"north": [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz)], "south": [Vector3(-hx, 0, hz), Vector3(hx, 0, hz)],
		"west": [Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz)], "east": [Vector3(hx, 0, -hz), Vector3(hx, 0, hz)]}
	for side: String in sides:
		var a: Vector3 = c + sides[side][0]
		var b: Vector3 = c + sides[side][1]
		if side == gate:
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			_wall_seg(root, a, mid - dir * GATE_W * 0.5, stone, dark)
			_wall_seg(root, mid + dir * GATE_W * 0.5, b, stone, dark)
			for s in [-1.0, 1.0]:
				_tower(root, mid + dir * (GATE_W * 0.5 + 1.2) * s, 1.9, 6.0, stone, roof)
			ProtoMesh.box(root, Vector3(GATE_W + 1.0, 1.0, WALL_T + 0.3) if absf(dir.x) > 0.5 else Vector3(WALL_T + 0.3, 1.0, GATE_W + 1.0),
				mid + Vector3(0, 4.6, 0), dark)
		else:
			_wall_seg(root, a, b, stone, dark)
	for corner in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz)]:
		_tower(root, c + corner, 2.4, 6.8, stone, roof)


static func _wall_seg(root: Node3D, a: Vector3, b: Vector3, stone: Material, dark: Material) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var mid := (a + b) * 0.5
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var sz := Vector3(len, WALL_H, WALL_T) if along_x else Vector3(WALL_T, WALL_H, len)
	ProtoMesh.box(root, sz, mid + Vector3(0, WALL_H * 0.5, 0), stone)
	# crenellations
	var n := int(len / 2.0)
	for i in n:
		var t := (i + 0.5) / n
		var p := a.lerp(b, t)
		if i % 2 == 0:
			ProtoMesh.box(root, Vector3(0.9, 0.6, WALL_T + 0.1) if along_x else Vector3(WALL_T + 0.1, 0.6, 0.9), p + Vector3(0, WALL_H + 0.3, 0), dark)
	ProtoMesh.static_box_collider(root, sz + Vector3(0, 2, 0), mid + Vector3(0, WALL_H * 0.5, 0))


static func _tower(root: Node3D, p: Vector3, r: float, h: float, stone: Material, roof: Material) -> void:
	ProtoMesh.cylinder(root, r, h, p + Vector3(0, h * 0.5, 0), stone, Vector3.ZERO, 10)
	ProtoMesh.cone(root, r + 0.4, r * 1.4, p + Vector3(0, h + r * 0.7, 0), roof, 10)
	ProtoMesh.static_cylinder_collider(root, r, h + 2.0, p + Vector3(0, h * 0.5, 0))


## Village: a wooden palisade of log panels with posts, the gate side left open.
static func _palisade(root: Node3D, c: Vector3, size: Vector2, gate: String) -> void:
	var wood := ProtoMesh.mat(Color(0.5, 0.36, 0.22))
	var post := ProtoMesh.mat(Color(0.4, 0.28, 0.17))
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var sides := {"north": [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz)], "south": [Vector3(-hx, 0, hz), Vector3(hx, 0, hz)],
		"west": [Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz)], "east": [Vector3(hx, 0, -hz), Vector3(hx, 0, hz)]}
	for side: String in sides:
		var a: Vector3 = c + sides[side][0]
		var b: Vector3 = c + sides[side][1]
		var len := a.distance_to(b)
		var n := int(ceil(len / 4.0))
		for i in n:
			var p0 := a.lerp(b, float(i) / n)
			var p1 := a.lerp(b, float(i + 1) / n)
			var mid := (p0 + p1) * 0.5
			if side == gate and mid.distance_to((a + b) * 0.5) < GATE_W * 0.5:
				continue
			var along_x := absf(b.x - a.x) > absf(b.z - a.z)
			var sz := Vector3(p0.distance_to(p1), 1.9, 0.3) if along_x else Vector3(0.3, 1.9, p0.distance_to(p1))
			ProtoMesh.box(root, sz, mid + Vector3(0, 0.95, 0), wood)
			ProtoMesh.cylinder(root, 0.18, 2.4, p0 + Vector3(0, 1.2, 0), post, Vector3.ZERO, 6)
			ProtoMesh.static_box_collider(root, sz + Vector3(0, 1, 0), mid + Vector3(0, 0.95, 0))
	var g := _gate_point(c, size, gate)
	var d := _gate_dir(gate).cross(Vector3.UP)
	for s in [-1.0, 1.0]:
		ProtoMesh.cylinder(root, 0.24, 3.4, g + d * GATE_W * 0.5 * s + Vector3(0, 1.7, 0), post, Vector3.ZERO, 6)
	ProtoMesh.box(root, Vector3(GATE_W + 0.6, 0.3, 0.3) if absf(d.x) > 0.5 else Vector3(0.3, 0.3, GATE_W + 0.6), g + Vector3(0, 3.2, 0), post)


static func _plaza(lab: VisualLab, root: Node3D, p: Vector3, r: float, village: bool) -> void:
	var paving := ProtoMesh.mat(Color(0.74, 0.7, 0.62))
	var disc := ProtoMesh.cylinder(root, r, 0.08, p + Vector3(0, 0.03, 0), paving, Vector3.ZERO, 24)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var stone := ProtoMesh.mat(Color(0.62, 0.6, 0.56))
	if village:  # a well with a little roof
		ProtoMesh.cylinder(root, 1.0, 0.8, p + Vector3(0, 0.4, 0), stone, Vector3.ZERO, 10)
		ProtoMesh.cylinder(root, 0.8, 0.05, p + Vector3(0, 0.78, 0), ProtoMesh.mat(Color(0.2, 0.32, 0.4)), Vector3.ZERO, 10)
		var wood := ProtoMesh.mat(Color(0.5, 0.36, 0.22))
		for s in [-1.0, 1.0]:
			ProtoMesh.box(root, Vector3(0.14, 1.9, 0.14), p + Vector3(0.9 * s, 0.95, 0), wood)
		ProtoMesh.prism(root, Vector3(2.4, 0.8, 1.6), p + Vector3(0, 2.2, 0), ProtoMesh.mat(Color(0.62, 0.42, 0.24)))
		ProtoMesh.static_cylinder_collider(root, 1.1, 2.0, p + Vector3(0, 1, 0))
	else:  # fountain
		ProtoMesh.cylinder(root, 2.4, 0.6, p + Vector3(0, 0.3, 0), stone, Vector3.ZERO, 16)
		var water := ProtoMesh.cylinder(root, 2.1, 0.05, p + Vector3(0, 0.6, 0), StylizedMaterials.water(), Vector3.ZERO, 16)
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ProtoMesh.cylinder(root, 0.35, 1.8, p + Vector3(0, 1.2, 0), stone, Vector3.ZERO, 8)
		ProtoMesh.cylinder(root, 0.9, 0.25, p + Vector3(0, 2.1, 0), stone, Vector3.ZERO, 12, 0.6)
		ProtoMesh.static_cylinder_collider(root, 2.5, 2.0, p + Vector3(0, 1, 0))
	# lamp posts around the plaza
	for i in (3 if village else 6):
		var a := TAU * i / (3.0 if village else 6.0) + 0.3
		var lp := CampProps.lantern_post()
		lp.position = p + Vector3(cos(a), 0, sin(a)) * (r - 0.8)
		lp.rotation.y = -a
		root.add_child(lp)
	# benches
	var bench := ProtoMesh.mat(Color(0.55, 0.38, 0.22))
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var bp := p + Vector3(cos(a), 0, sin(a)) * (r * 0.62)
		ProtoMesh.box(root, Vector3(1.6, 0.12, 0.5), bp + Vector3(0, 0.45, 0), bench, Vector3(0, -rad_to_deg(a) + 90.0, 0))


static func _castle(lab: VisualLab, root: Node3D, k: Vector3) -> void:
	var stone := ProtoMesh.mat(Color(0.78, 0.76, 0.7))
	var trim := ProtoMesh.mat(Color(0.6, 0.58, 0.54))
	var roof := ProtoMesh.mat(Color(0.32, 0.38, 0.6))
	var keep := Node3D.new()
	keep.position = k
	root.add_child(keep)
	ProtoMesh.box(keep, Vector3(18, 9, 12), Vector3(0, 4.5, 0), stone)
	ProtoMesh.box(keep, Vector3(18.6, 0.8, 12.6), Vector3(0, 9.2, 0), trim)
	ProtoMesh.box(keep, Vector3(8, 6, 7), Vector3(0, 12, -1), stone)
	ProtoMesh.prism(keep, Vector3(8.6, 4.0, 7.6), Vector3(0, 17, -1), roof)
	for corner in [Vector3(-9, 0, -6), Vector3(9, 0, -6), Vector3(-9, 0, 6), Vector3(9, 0, 6)]:
		ProtoMesh.cylinder(keep, 2.2, 12.0, corner + Vector3(0, 6, 0), stone, Vector3.ZERO, 10)
		ProtoMesh.cone(keep, 2.7, 4.0, corner + Vector3(0, 14, 0), roof, 10)
	# door, windows, banners
	ProtoMesh.box(keep, Vector3(3.2, 4.2, 0.4), Vector3(0, 2.1, 6.05), ProtoMesh.mat(Color(0.32, 0.22, 0.14)))
	var glass := ProtoMesh.mat(Color(0.2, 0.22, 0.3))
	for x in [-6.0, -3.2, 3.2, 6.0]:
		ProtoMesh.box(keep, Vector3(1.0, 1.6, 0.2), Vector3(x, 6.0, 6.05), glass)
	var red := ProtoMesh.mat(Color(0.72, 0.18, 0.2))
	for x in [-4.6, 4.6]:
		ProtoMesh.box(keep, Vector3(1.4, 3.2, 0.1), Vector3(x, 4.0, 6.15), red)
	ProtoMesh.static_box_collider(keep, Vector3(22, 12, 16), Vector3(0, 6, 0))
	lab._register_occluder(keep, 11.0, 14.0)


static func _stall(root: Node3D, p: Vector3, rng: RandomNumberGenerator, a: float) -> void:
	var s := Node3D.new()
	s.position = p
	s.rotation.y = -a + PI * 0.5
	root.add_child(s)
	var wood := ProtoMesh.mat(Color(0.6, 0.44, 0.28))
	ProtoMesh.box(s, Vector3(2.4, 0.9, 0.9), Vector3(0, 0.45, 0), wood)
	for x in [-1.1, 1.1]:
		ProtoMesh.box(s, Vector3(0.1, 2.2, 0.1), Vector3(x, 1.1, -0.4), wood)
	var cols := [Color(0.85, 0.3, 0.28), Color(0.3, 0.55, 0.8), Color(0.35, 0.65, 0.4), Color(0.9, 0.7, 0.3)]
	var c1: Color = cols[rng.randi() % cols.size()]
	for i in 4:
		ProtoMesh.box(s, Vector3(0.62, 0.08, 1.3), Vector3(-0.93 + i * 0.62, 2.25, 0.0), ProtoMesh.mat(c1 if i % 2 == 0 else Color(0.95, 0.93, 0.86)), Vector3(12, 0, 0))
	ProtoMesh.static_box_collider(s, Vector3(2.4, 1.2, 1.0), Vector3(0, 0.6, 0))


## Houses on a grid of lots inside the town, kept off the plaza, castle and streets; each faces
## the nearest street.
static func _houses(lab: VisualLab, root: Node3D, c: Vector3, size: Vector2, count: int, avoid: Array[Vector3], village: bool, rng: RandomNumberGenerator) -> void:
	var lots: Array[Vector3] = []
	var hx := size.x * 0.5 - 5.0
	var hz := size.y * 0.5 - 5.0
	var spacing := LOT * (0.85 if village else 1.0)
	var x := -hx
	while x <= hx:
		var z := -hz
		while z <= hz:
			var p := c + Vector3(x, 0, z)
			var ok := lab.terrain.path_distance(p.x, p.z) > 5.0
			for a in avoid:
				if Vector2(p.x - a.x, p.z - a.y).length() < a.z:
					ok = false
			if ok:
				lots.append(p)
			z += spacing
		x += spacing
	# shuffle (seeded) and take
	for i in range(lots.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t := lots[i]
		lots[i] = lots[j]
		lots[j] = t
	for i in mini(count, lots.size()):
		_house(lab, root, lots[i] + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), village, rng)


static func _house(lab: VisualLab, root: Node3D, p: Vector3, village: bool, rng: RandomNumberGenerator) -> void:
	var h := Node3D.new()
	h.position = p
	# face the nearest street: try the four directions, keep the one closest to a path
	var best := 0
	var best_d := INF
	for i in 4:
		var d := Vector3(sin(i * PI * 0.5), 0, cos(i * PI * 0.5))
		var q := p + d * 5.0
		var pd := lab.terrain.path_distance(q.x, q.z)
		if pd < best_d:
			best_d = pd
			best = i
	h.rotation.y = best * PI * 0.5
	root.add_child(h)
	var w := rng.randf_range(4.6, 6.4) * (0.85 if village else 1.0)
	var d2 := rng.randf_range(4.2, 5.6) * (0.85 if village else 1.0)
	var wall_h := rng.randf_range(2.8, 3.6)
	var wall := ProtoMesh.mat(_plaster[rng.randi() % _plaster.size()] if not village else Color(0.62, 0.46, 0.3).lerp(Color(0.72, 0.56, 0.38), rng.randf()))
	var roof := ProtoMesh.mat(_roofs[rng.randi() % _roofs.size()])
	var trim := ProtoMesh.mat(Color(0.42, 0.3, 0.2))
	ProtoMesh.box(h, Vector3(w, wall_h, d2), Vector3(0, wall_h * 0.5, 0), wall)
	ProtoMesh.box(h, Vector3(w + 0.1, 0.25, d2 + 0.1), Vector3(0, 0.12, 0), trim)
	ProtoMesh.prism(h, Vector3(w + 0.8, 2.0, d2 + 0.8), Vector3(0, wall_h + 1.0, 0), roof)
	ProtoMesh.box(h, Vector3(1.1, 2.0, 0.15), Vector3(0, 1.0, d2 * 0.5 + 0.05), ProtoMesh.mat(Color(0.4, 0.26, 0.16)))
	var glass := ProtoMesh.mat(Color(0.95, 0.85, 0.55), 0.4, Color(1.0, 0.75, 0.4), 0.6)
	for s in [-1.0, 1.0]:
		ProtoMesh.box(h, Vector3(0.8, 0.8, 0.12), Vector3(s * w * 0.3, wall_h * 0.6, d2 * 0.5 + 0.05), glass)
	if rng.randf() < 0.5:
		ProtoMesh.box(h, Vector3(0.6, 1.4, 0.6), Vector3(w * 0.28, wall_h + 1.4, -d2 * 0.15), ProtoMesh.mat(Color(0.5, 0.45, 0.42)))
	ProtoMesh.static_box_collider(h, Vector3(w, wall_h + 1.0, d2), Vector3(0, wall_h * 0.5, 0))
	lab._register_occluder(h, maxf(w, d2) * 0.6, wall_h + 2.0)
