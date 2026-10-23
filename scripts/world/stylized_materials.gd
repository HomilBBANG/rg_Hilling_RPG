class_name StylizedMaterials
extends RefCounted
## Factory/cache for the stylized shader materials and their procedural noise textures.
## `set_stylized(false)` flattens every registered material (used by camera style A).

static var _noise_large: NoiseTexture2D
static var _noise_detail: NoiseTexture2D
static var _registered: Array[ShaderMaterial] = []
static var _rock_cache := {}
static var stylized := true
static var detail := 1.0
static var wind := 1.0


static func _noise(seed: int, freq: float, size: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	return t


static func noise_large() -> NoiseTexture2D:
	if _noise_large == null:
		_noise_large = _noise(21, 0.012, 256)
	return _noise_large


static func noise_detail() -> NoiseTexture2D:
	if _noise_detail == null:
		_noise_detail = _noise(77, 0.03, 256)
	return _noise_detail


static func _make(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("noise_detail", noise_detail())
	m.set_shader_parameter("stylized", 1.0 if stylized else 0.0)
	m.set_shader_parameter("detail", detail)
	m.set_shader_parameter("wind_scale", wind)
	_registered.append(m)
	return m


static func terrain() -> ShaderMaterial:
	var m := _make(preload("res://shaders/terrain_stylized.gdshader"))
	m.set_shader_parameter("noise_large", noise_large())
	return m


## Stylised water (water_stylized.gdshader). Sea mode: the plane around a region, its shallows
## and foam come from the distance to the land rectangle (x0, z0, x1, z1).
static func water(sea := false, land := Vector4.ZERO) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/water_stylized.gdshader")
	m.set_shader_parameter("noise_tex", noise_detail())
	m.set_shader_parameter("sea", sea)
	if sea:
		m.set_shader_parameter("land_rect", land)
	return m


## Unique per call so individual trees can fade / shift hue.
static func foliage(base: Color, light: Color, dark: Color, hue_shift := 0.0) -> ShaderMaterial:
	var m := _make(preload("res://shaders/foliage_stylized.gdshader"))
	m.set_shader_parameter("leaf_base", base)
	m.set_shader_parameter("leaf_light", light)
	m.set_shader_parameter("leaf_dark", dark)
	m.set_shader_parameter("hue_shift", hue_shift)
	return m


static func rock(moss_amount := 0.5, tint := Color.WHITE) -> ShaderMaterial:
	var key := "%.2f|%s" % [moss_amount, tint.to_html()]
	if _rock_cache.has(key):
		return _rock_cache[key]
	var m := _make(preload("res://shaders/rock_stylized.gdshader"))
	m.set_shader_parameter("moss_amount", moss_amount)
	m.set_shader_parameter("stone_base", Color(0.62, 0.61, 0.6) * tint)
	m.set_shader_parameter("stone_light", Color(0.8, 0.78, 0.72) * tint)
	m.set_shader_parameter("stone_dark", Color(0.42, 0.42, 0.46) * tint)
	_rock_cache[key] = m
	return m


static func set_stylized(on: bool) -> void:
	stylized = on
	for m in _registered:
		if is_instance_valid(m):
			m.set_shader_parameter("stylized", 1.0 if on else 0.0)


## 0 = flat cel colours (single colour per surface), 1 = painted detail.
static func set_detail(v: float) -> void:
	detail = v
	for m in _registered:
		if is_instance_valid(m):
			m.set_shader_parameter("detail", v)


## Global gentle wind (grass, bushes, canopies): 1 = on, 0 = still.
static func set_wind(v: float) -> void:
	wind = v
	for m in _registered:
		if is_instance_valid(m):
			m.set_shader_parameter("wind_scale", v)


static func register(m: ShaderMaterial) -> void:
	m.set_shader_parameter("detail", detail)
	m.set_shader_parameter("wind_scale", wind)
	_registered.append(m)


## Drop references to materials of a freed world.
static func clear_registry() -> void:
	_registered.clear()
	_rock_cache.clear()
