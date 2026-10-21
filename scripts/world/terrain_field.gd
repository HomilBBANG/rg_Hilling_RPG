class_name TerrainField
extends RefCounted
## Height + ground-colour field for an outdoor region, and its vertex-coloured mesh (in chunks,
## so the renderer culls what the fixed camera can't see). Layout: grass, winding dirt paths,
## ponds / lakes with sand rims, mounds / hills, forest patches and raised edges that frame the
## play area. The constants are the old starting meadow's layout (the default); regions pass their
## own layout (data/regions/*.json "terrain").

const MIN := Vector2(-44.0, -40.0)
const MAX := Vector2(56.0, 44.0)
const CELL := 0.5
const CHUNK := 32.0          # metres per terrain mesh piece
const PATH_BUCKET := 12.0    # path segments are looked up in buckets of this size
const PATH_REACH := 10.0     # path_distance is exact up to this far; beyond, it only says "far"

const POND_CENTER := Vector2(12.0, 19.0)
const POND_RADIUS := 6.5
const WATER_LEVEL := -0.45
const CAMP_CENTER := Vector2(-4.5, -0.5)

## Dirt path centre line (x, z).
const PATH: PackedVector2Array = [
	Vector2(-30, 8), Vector2(-19, 8.5), Vector2(-9, 7.2), Vector2(0, 6.8), Vector2(6, 5.0), Vector2(11, 2),
	Vector2(17, -2), Vector2(23, -7), Vector2(30, -10), Vector2(37, -8), Vector2(42, -2),
	Vector2(42, 6), Vector2(36, 13), Vector2(27, 17), Vector2(21, 23), Vector2(14, 30),
	Vector2(4, 32),
]
const MOUNDS := [
	[Vector2(-20, 16), 1.6, 5.0],
	[Vector2(44, 24), 2.0, 6.5],
	[Vector2(-26, -18), 1.3, 5.0],
	[Vector2(6, -16), 0.9, 4.0],
]
const FOREST_CENTER := Vector2(31.0, -21.0)
const FOREST_RADIUS := 15.0

var bounds_min := MIN
var bounds_max := MAX
var pond_center := POND_CENTER  ## the first pond (fishing spots, older code)
var pond_radius := POND_RADIUS  ## 0 = no pond
var ponds: Array = [[POND_CENTER, POND_RADIUS]]  ## [[center Vector2, radius], ...] ponds and lakes
var camp_center := CAMP_CENTER  ## Vector2.INF = no flattened camp clearing
var paths: Array[PackedVector2Array] = [PATH]
var mounds: Array = MOUNDS
var forest_center := FOREST_CENTER  ## the first forest
var forest_radius := FOREST_RADIUS
var forests: Array = [[FOREST_CENTER, FOREST_RADIUS]]  ## [[center Vector2, radius], ...]
var hill_noise := 0.45
var clearings: Array = []  ## [[center Vector2, radius], ...] flattened ground (towns)

var _buckets := {}  # Vector2i bucket -> PackedInt32Array of segment ids
var _seg_a := PackedVector2Array()
var _seg_b := PackedVector2Array()

var _noise := FastNoiseLite.new()
var _tone := FastNoiseLite.new()


static func _v2(a: Variant, fallback: Vector2) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and (a as Array).size() >= 2 else fallback


## layout keys (all optional): min, max, pond {center, radius} | null, ponds [{center, radius}],
## camp_center | null, paths [[[x, z], ...], ...], mounds [[[x, z], height, width], ...],
## forest {center, radius}, forests [{center, radius}], clearings [{center, radius}] (flattened
## for towns), hill_noise, seed.
func _init(layout := {}) -> void:
	if layout.has("min"):
		bounds_min = _v2(layout["min"], MIN)
		bounds_max = _v2(layout["max"], MAX)
	if layout.has("pond") or layout.has("ponds"):
		ponds = []
		var pd: Variant = layout.get("pond", null)
		if pd is Dictionary:
			ponds.append([_v2(pd["center"], POND_CENTER), float(pd["radius"])])
		for p: Dictionary in layout.get("ponds", []):
			ponds.append([_v2(p["center"], Vector2.ZERO), float(p["radius"])])
		pond_radius = float(ponds[0][1]) if not ponds.is_empty() else 0.0
		pond_center = ponds[0][0] if not ponds.is_empty() else Vector2(1e6, 1e6)
	if layout.has("camp_center"):
		camp_center = _v2(layout["camp_center"], Vector2.INF) if layout["camp_center"] != null else Vector2.INF
	if layout.has("paths"):
		paths = []
		for line: Array in layout["paths"]:
			var pts := PackedVector2Array()
			for pt: Array in line:
				pts.append(Vector2(float(pt[0]), float(pt[1])))
			paths.append(pts)
	if layout.has("mounds"):
		mounds = []
		for m: Array in layout["mounds"]:
			mounds.append([_v2(m[0], Vector2.ZERO), float(m[1]), float(m[2])])
	if layout.has("forest") or layout.has("forests"):
		forests = []
		var fo: Variant = layout.get("forest", null)
		if fo is Dictionary:
			forests.append([_v2(fo["center"], FOREST_CENTER), float(fo["radius"])])
		for f: Dictionary in layout.get("forests", []):
			forests.append([_v2(f["center"], Vector2.ZERO), float(f["radius"])])
		if not forests.is_empty():
			forest_center = forests[0][0]
			forest_radius = forests[0][1]
	for c: Dictionary in layout.get("clearings", []):
		clearings.append([_v2(c["center"], Vector2.ZERO), float(c["radius"])])
	hill_noise = float(layout.get("hill_noise", hill_noise))
	_noise.seed = int(layout.get("seed", 11))
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.045
	_tone.seed = 5
	_tone.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_tone.frequency = 0.09
	_index_paths()


## Buckets every path segment by area, so a distance query only looks at nearby segments
## (big regions have long roads and the height / colour / grass code asks millions of times).
func _index_paths() -> void:
	for line in paths:
		for i in line.size() - 1:
			var id := _seg_a.size()
			_seg_a.append(line[i])
			_seg_b.append(line[i + 1])
			var lo := line[i].min(line[i + 1]) - Vector2.ONE * PATH_REACH
			var hi := line[i].max(line[i + 1]) + Vector2.ONE * PATH_REACH
			for bx in range(floori(lo.x / PATH_BUCKET), floori(hi.x / PATH_BUCKET) + 1):
				for bz in range(floori(lo.y / PATH_BUCKET), floori(hi.y / PATH_BUCKET) + 1):
					var key := Vector2i(bx, bz)
					var ids: PackedInt32Array = _buckets.get(key, PackedInt32Array())
					ids.append(id)
					_buckets[key] = ids  # packed arrays are copied: store the grown one back


## Distance to the nearest path centre line; exact within PATH_REACH, otherwise some value
## beyond it (callers only test short distances).
func path_distance(x: float, z: float) -> float:
	var ids: Variant = _buckets.get(Vector2i(floori(x / PATH_BUCKET), floori(z / PATH_BUCKET)), null)
	if ids == null:
		return PATH_REACH * 2.0
	var p := Vector2(x, z)
	var best := PATH_REACH * 2.0
	for id in (ids as PackedInt32Array):
		var a := _seg_a[id]
		var ab := _seg_b[id] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Signed distance to the nearest pond / lake rim (negative = in the water).
func pond_distance(x: float, z: float) -> float:
	var best := 1e6
	for i in ponds.size():
		var c: Vector2 = ponds[i][0]
		var r: float = ponds[i][1]
		var p := Vector2(x, z) - c
		if p.length() - r > 8.0:
			best = minf(best, p.length() - r)
			continue
		# slightly irregular rim, a different wobble per pond
		var wobble := (sin(p.angle() * 3.0 + i) * 0.6 + sin(p.angle() * 5.0 + 1.0 + i * 2.0) * 0.3) * minf(1.0, r / 6.5)
		best = minf(best, p.length() - r - wobble)
	return best


## 0..1 how deep inside a forest patch the point is (1 = well inside).
func forest_mask(x: float, z: float) -> float:
	var m := 0.0
	for f: Array in forests:
		var fd := Vector2(x, z).distance_to(f[0])
		m = maxf(m, 1.0 - smoothstep(float(f[1]) - 6.0, float(f[1]) + 3.0, fd))
	return m


func height(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * hill_noise
	for m: Array in mounds:
		var d := Vector2(x, z).distance_to(m[0])
		h += m[1] * exp(-(d * d) / (m[2] * m[2]))
	# Raised rim around the playable area
	var edge := minf(minf(x - bounds_min.x, bounds_max.x - x), minf(z - bounds_min.y, bounds_max.y - z))
	h += (1.0 - smoothstep(0.0, 9.0, edge)) * 3.5
	# Flatten the path and the camp clearing
	var pd := path_distance(x, z)
	h = lerpf(h * 0.25, h, smoothstep(1.0, 4.0, pd))
	if camp_center != Vector2.INF:
		var cd := Vector2(x, z).distance_to(camp_center)
		h = lerpf(0.0, h, smoothstep(5.0, 9.0, cd))
	for c: Array in clearings:
		h = lerpf(0.0, h, smoothstep(float(c[1]), float(c[1]) + 8.0, Vector2(x, z).distance_to(c[0])))
	# Pond basin
	var wd := pond_distance(x, z)
	h = lerpf(-1.3, h, smoothstep(-2.5, 1.8, wd))
	return h


## Ground colour at a terrain vertex (colours are interpolated across faces).
func ground_color(x: float, z: float, rng: RandomNumberGenerator) -> Color:
	var tone := _tone.get_noise_2d(x, z)
	var jitter := rng.randf()
	var wd := pond_distance(x, z)
	if wd < -1.0:
		return Color(0.33, 0.36, 0.3)  # pond bed (seen through water)
	if wd < 1.0 + jitter * 0.6:
		return Color(0.82, 0.74, 0.52).lerp(Color(0.76, 0.68, 0.48), jitter)
	var pd := path_distance(x, z)
	var edge_noise := tone * 0.45 + jitter * 0.35
	if pd < 1.25 + edge_noise:
		var dirt := Color(0.62, 0.47, 0.3).lerp(Color(0.56, 0.42, 0.27), jitter)
		return dirt
	var grass_a := Color(0.4, 0.62, 0.27)
	var grass_b := Color(0.35, 0.56, 0.24)
	var grass_c := Color(0.46, 0.67, 0.3)
	var c: Color
	if tone > 0.25:
		c = grass_c
	elif tone < -0.2:
		c = grass_b
	else:
		c = grass_a
	if jitter < 0.15:
		c = c.darkened(0.05)
	elif jitter > 0.88:
		c = c.lightened(0.04)
	c = c.lerp(Color(0.26, 0.44, 0.2), forest_mask(x, z) * 0.7)
	if pd < 2.0 + edge_noise:
		c = c.lerp(Color(0.55, 0.5, 0.3), 0.35)
	return c


## Vertex masks for the stylized terrain shader: r = path, g = shore, b = forest, a = camp wear.
func masks(x: float, z: float) -> Color:
	var pd := path_distance(x, z)
	var wd := pond_distance(x, z)
	var cd := Vector2(x, z).distance_to(camp_center) if camp_center != Vector2.INF else 1e6
	return Color(
		1.0 - smoothstep(0.4, 2.4, pd),
		1.0 - smoothstep(-0.6, 2.2, wd),
		forest_mask(x, z),
		1.0 - smoothstep(2.0, 7.0, cd))


## The whole terrain as pieces of CHUNK metres (seamless: they share the height grid and its
## smooth normals). Returns [ArrayMesh, ...].
func build_chunks(stylized_material: Material = null) -> Array[ArrayMesh]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var nx := int((bounds_max.x - bounds_min.x) / CELL)
	var nz := int((bounds_max.y - bounds_min.y) / CELL)
	var row := nx + 1
	var heights := PackedFloat32Array()
	heights.resize(row * (nz + 1))
	var colors := PackedColorArray()
	colors.resize(row * (nz + 1))
	for iz in nz + 1:
		for ix in row:
			var x := bounds_min.x + ix * CELL
			var z := bounds_min.y + iz * CELL
			heights[iz * row + ix] = height(x, z)
			colors[iz * row + ix] = masks(x, z) if stylized_material else ground_color(x, z, rng)
	var material: Material = stylized_material
	if material == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		material = m
	var step := int(CHUNK / CELL)
	var out: Array[ArrayMesh] = []
	for cz in range(0, nz, step):
		for cx in range(0, nx, step):
			out.append(_chunk_mesh(heights, colors, row, nx, nz, cx, cz, mini(cx + step, nx), mini(cz + step, nz), material))
	return out


func _chunk_mesh(heights: PackedFloat32Array, colors: PackedColorArray, row: int, nx: int, nz: int,
		x0: int, z0: int, x1: int, z1: int, material: Material) -> ArrayMesh:
	var w := x1 - x0 + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var i := iz * row + ix
			verts.append(Vector3(bounds_min.x + ix * CELL, heights[i], bounds_min.y + iz * CELL))
			# Smooth normal from central differences (toon light stays clean on gentle slopes).
			var hl := heights[iz * row + maxi(ix - 1, 0)]
			var hr := heights[iz * row + mini(ix + 1, nx)]
			var hd := heights[maxi(iz - 1, 0) * row + ix]
			var hu := heights[mini(iz + 1, nz) * row + ix]
			normals.append(Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized())
			cols.append(colors[i])
	var indices := PackedInt32Array()
	for iz in z1 - z0:
		for ix in x1 - x0:
			var i00 := iz * w + ix
			var i10 := i00 + 1
			var i01 := i00 + w
			var i11 := i01 + 1
			# Clockwise (seen from above) = front face in Godot.
			indices.append_array([i00, i10, i11, i00, i11, i01])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh
