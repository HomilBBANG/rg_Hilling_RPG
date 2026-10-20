class_name TerrainField
extends RefCounted
## Height + ground-colour field for the outdoor lab, and a flat-shaded vertex-coloured mesh.
## Layout: grass meadow, a winding dirt path, a pond with sand rim, gentle mounds,
## a forest patch and raised edges that frame the play area.

const MIN := Vector2(-44.0, -40.0)
const MAX := Vector2(56.0, 44.0)
const CELL := 0.5

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

var _noise := FastNoiseLite.new()
var _tone := FastNoiseLite.new()


func _init() -> void:
	_noise.seed = 11
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.045
	_tone.seed = 5
	_tone.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_tone.frequency = 0.09


func path_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for i in PATH.size() - 1:
		var a := PATH[i]
		var b := PATH[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func pond_distance(x: float, z: float) -> float:
	# Slightly irregular rim
	var p := Vector2(x, z) - POND_CENTER
	var wobble := sin(p.angle() * 3.0) * 0.6 + sin(p.angle() * 5.0 + 1.0) * 0.3
	return p.length() - wobble


func height(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * 0.45
	for m: Array in MOUNDS:
		var d := Vector2(x, z).distance_to(m[0])
		h += m[1] * exp(-(d * d) / (m[2] * m[2]))
	# Raised rim around the playable area
	var edge := minf(minf(x - MIN.x, MAX.x - x), minf(z - MIN.y, MAX.y - z))
	h += (1.0 - smoothstep(0.0, 9.0, edge)) * 3.5
	# Flatten the path and the camp clearing
	var pd := path_distance(x, z)
	h = lerpf(h * 0.25, h, smoothstep(1.0, 4.0, pd))
	var cd := Vector2(x, z).distance_to(CAMP_CENTER)
	h = lerpf(0.0, h, smoothstep(5.0, 9.0, cd))
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
	var fd := Vector2(x, z).distance_to(FOREST_CENTER)
	if fd < FOREST_RADIUS + 3.0:
		c = c.lerp(Color(0.26, 0.44, 0.2), (1.0 - smoothstep(FOREST_RADIUS - 6.0, FOREST_RADIUS + 3.0, fd)) * 0.7)
	if pd < 2.0 + edge_noise:
		c = c.lerp(Color(0.55, 0.5, 0.3), 0.35)
	return c


## Vertex masks for the stylized terrain shader: r = path, g = shore, b = forest, a = camp wear.
func masks(x: float, z: float) -> Color:
	var pd := path_distance(x, z)
	var wd := pond_distance(x, z)
	var fd := Vector2(x, z).distance_to(FOREST_CENTER)
	var cd := Vector2(x, z).distance_to(CAMP_CENTER)
	return Color(
		1.0 - smoothstep(0.4, 2.4, pd),
		1.0 - smoothstep(-0.6, 2.2, wd),
		1.0 - smoothstep(FOREST_RADIUS - 6.0, FOREST_RADIUS + 3.0, fd),
		1.0 - smoothstep(2.0, 7.0, cd))


func build_mesh(stylized_material: Material = null) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var nx := int((MAX.x - MIN.x) / CELL)
	var nz := int((MAX.y - MIN.y) / CELL)
	var row := nx + 1
	var heights := PackedFloat32Array()
	heights.resize(row * (nz + 1))
	for iz in nz + 1:
		for ix in row:
			heights[iz * row + ix] = height(MIN.x + ix * CELL, MIN.y + iz * CELL)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(row * (nz + 1))
	normals.resize(verts.size())
	colors.resize(verts.size())
	for iz in nz + 1:
		for ix in row:
			var i := iz * row + ix
			var x := MIN.x + ix * CELL
			var z := MIN.y + iz * CELL
			verts[i] = Vector3(x, heights[i], z)
			# Smooth normal from central differences (toon light stays clean on gentle slopes).
			var hl := heights[iz * row + maxi(ix - 1, 0)]
			var hr := heights[iz * row + mini(ix + 1, nx)]
			var hd := heights[maxi(iz - 1, 0) * row + ix]
			var hu := heights[mini(iz + 1, nz) * row + ix]
			normals[i] = Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized()
			if stylized_material:
				colors[i] = masks(x, z)
			else:
				colors[i] = ground_color(x, z, rng)
	var indices := PackedInt32Array()
	for iz in nz:
		for ix in nx:
			var i00 := iz * row + ix
			var i10 := i00 + 1
			var i01 := i00 + row
			var i11 := i01 + 1
			# Clockwise (seen from above) = front face in Godot.
			indices.append_array([i00, i10, i11, i00, i11, i01])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if stylized_material:
		mesh.surface_set_material(0, stylized_material)
	else:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		mesh.surface_set_material(0, m)
	return mesh
