class_name SpriteBaker
extends Node
## "Model -> render -> pixel sprite" pipeline (the Dead Cells approach).
## Renders a grid of posed 3D model instances with a fixed orthographic camera (same pitch and
## texel size as the game camera) into atlases in a few frames:
##   albedo   (ambient-only, sRGB)      -> sprite colour
##   normal   (view space, HDR floats)  -> dynamic lighting on the card
##   depth    (metres vs. anchor plane) -> correct occlusion in the 3D world
##   emission (per variant, HDR)        -> lamps, eyes, lantern
## No anti-aliasing anywhere, so every texel is a hard pixel.

const CAMERA_DISTANCE := 50.0

var _vp: SubViewport
var _cam: Camera3D
var _env: Environment
var _root: Node3D
var _normal_mat: ShaderMaterial
var _depth_mat: ShaderMaterial
var busy := false


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.name = "BakeViewport"
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(64, 64)
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 1.0
	_cam.far = CAMERA_DISTANCE * 2.0
	_vp.add_child(_cam)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	we.environment = _env
	_vp.add_child(we)
	_normal_mat = ShaderMaterial.new()
	_normal_mat.shader = preload("res://shaders/bake_normal.gdshader")
	_depth_mat = ShaderMaterial.new()
	_depth_mat.shader = preload("res://shaders/bake_depth.gdshader")
	_depth_mat.set_shader_parameter("anchor_view_z", -CAMERA_DISTANCE)


## spec keys:
##   builder: Callable(col: int, row: int) -> Node3D   (posed model, origin = sprite anchor)
##   cols, rows: int; cell: Vector2 (metres); texel: float (metres per pixel); pitch: float (deg)
##   emission: Dictionary name -> Callable(instances: Array[Node3D]) that sets the lamp state
##   albedo_setup: Callable(instances) (optional, e.g. lamps off for the colour pass)
func bake(spec: Dictionary) -> SpriteSheet:
	while busy:
		await get_tree().process_frame
	busy = true
	var sheet := SpriteSheet.new()
	sheet.cols = spec["cols"]
	sheet.rows = spec["rows"]
	sheet.texel = spec["texel"]
	sheet.pitch = spec["pitch"]
	sheet.screen_px = spec.get("screen_px", sheet.screen_px)
	var cell: Vector2 = spec["cell"]
	sheet.cell_px = Vector2i(ceili(cell.x / sheet.texel), ceili(cell.y / sheet.texel))
	# Same parity as the render viewport: the card's pixel grid then matches the screen grid
	# with plain rounding (no half-texel offset that could flip between frames).
	if (sheet.screen_px.x - sheet.cell_px.x) % 2 != 0:
		sheet.cell_px.x += 1
	if (sheet.screen_px.y - sheet.cell_px.y) % 2 != 0:
		sheet.cell_px.y += 1
	sheet.cell_m = Vector2(sheet.cell_px) * sheet.texel
	_vp.size = Vector2i(sheet.cell_px.x * sheet.cols, sheet.cell_px.y * sheet.rows)

	var basis := Basis.from_euler(Vector3(deg_to_rad(-sheet.pitch), 0.0, 0.0))
	_cam.global_transform = Transform3D(basis, basis.z * CAMERA_DISTANCE)
	_cam.size = sheet.cell_m.y * sheet.rows

	_root = Node3D.new()
	_vp.add_child(_root)
	var instances: Array[Node3D] = []
	for r in sheet.rows:
		for c in sheet.cols:
			var inst: Node3D = spec["builder"].call(c, r)
			var off := basis.x * (c - (sheet.cols - 1) * 0.5) * sheet.cell_m.x \
					+ basis.y * ((sheet.rows - 1) * 0.5 - r) * sheet.cell_m.y
			inst.position += off
			_root.add_child(inst)
			inst.process_mode = Node.PROCESS_MODE_DISABLED
			for p in inst.find_children("*", "GPUParticles3D", true, false):
				(p as GPUParticles3D).visible = false
			instances.append(inst)
	var meshes: Array[GeometryInstance3D] = []
	for inst in instances:
		for m in inst.find_children("*", "GeometryInstance3D", true, false):
			meshes.append(m as GeometryInstance3D)
	var originals: Array[Material] = []
	for m in meshes:
		originals.append(m.material_override)

	# 1) albedo: ambient white light only
	if spec.has("albedo_setup"):
		spec["albedo_setup"].call(instances)
	_hide_lights()
	_env.ambient_light_color = Color.WHITE
	_env.ambient_light_energy = 1.0
	_vp.use_hdr_2d = false
	var albedo_img := await _render()
	# 2) emission variants: no light at all, only emissive surfaces remain
	_env.ambient_light_energy = 0.0
	_vp.use_hdr_2d = true
	var emissions: Dictionary = spec.get("emission", {})
	if emissions.is_empty():
		emissions = {"default": Callable()}
	for key: String in emissions:
		var setup: Callable = emissions[key]
		if setup.is_valid():
			setup.call(instances)
		# Setups toggle lamps (and with them their Light3D nodes): real lights must never
		# reach the bake, only emissive surfaces.
		_hide_lights()
		var img := await _render()
		sheet.emission[key] = ImageTexture.create_from_image(img)
		sheet.images["emission_" + key] = img
	# 3) normal + 4) depth with override materials
	for m in meshes:
		m.material_override = _normal_mat
	var normal_img := await _render()
	for m in meshes:
		m.material_override = _depth_mat
	var depth_img := await _render()
	for i in meshes.size():
		meshes[i].material_override = originals[i]

	sheet.albedo = ImageTexture.create_from_image(albedo_img)
	sheet.normal = ImageTexture.create_from_image(normal_img)
	sheet.depth = ImageTexture.create_from_image(depth_img)
	sheet.images["albedo"] = albedo_img
	sheet.images["normal"] = normal_img
	sheet.images["depth"] = depth_img
	_root.queue_free()
	_root = null
	busy = false
	return sheet


func _hide_lights() -> void:
	for l in _root.find_children("*", "Light3D", true, false):
		(l as Light3D).visible = false


func _render() -> Image:
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()


## Writes a sheet's maps as viewable PNGs (normal/depth/emission remapped to 8-bit).
static func export_sheet(sheet: SpriteSheet, dir: String, prefix: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	sheet.images["albedo"].save_png(dir.path_join(prefix + "_albedo.png"))
	var n: Image = sheet.images["normal"].duplicate()
	n.convert(Image.FORMAT_RGBA8)
	n.save_png(dir.path_join(prefix + "_normal.png"))
	var d: Image = sheet.images["depth"]
	var a: Image = sheet.images["albedo"]
	var dv := Image.create(d.get_width(), d.get_height(), false, Image.FORMAT_RGBA8)
	for y in d.get_height():
		for x in d.get_width():
			if a.get_pixel(x, y).a < 0.5:
				dv.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var v := clampf(d.get_pixel(x, y).r / 6.0 + 0.5, 0.0, 1.0)
				dv.set_pixel(x, y, Color(v, v, v, 1))
	dv.save_png(dir.path_join(prefix + "_depth.png"))
	for k: String in sheet.images:
		if k.begins_with("emission_"):
			var e: Image = sheet.images[k].duplicate()
			e.convert(Image.FORMAT_RGBA8)
			e.save_png(dir.path_join(prefix + "_" + k + ".png"))
