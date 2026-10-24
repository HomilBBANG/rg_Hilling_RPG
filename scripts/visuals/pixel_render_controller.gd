class_name PixelRenderController
extends Control
## Renders a 3D world into a low-res SubViewport and shows it upscaled with nearest filtering.
## HUD/UI must live outside this control (e.g. a CanvasLayer) so text stays sharp.
##
## Two pipelines can be compared (GRAPHICS_PROTOTYPE.md section 2):
##  - SUBVIEWPORT: SubViewport has the low resolution itself, TextureRect does integer upscale.
##  - SCALING_3D:  SubViewport stays at output resolution, Viewport.scaling_3d_mode = NEAREST
##                 renders only the 3D at a fraction of it.
## Both keep a 1-texel margin so the pixel-snapping camera can be compensated by sub-texel
## offsets of the displayed image (smooth scrolling without world shimmer).

enum Pipeline { SUBVIEWPORT, SCALING_3D }

const OUTPUT_SIZE := Vector2i(1920, 1080)
## Integer upscale factors for 1920x1080: x6 / x4 / x3 / x1.
const PRESETS: Array[Dictionary] = [
	{"name": "PXL-COARSE", "size": Vector2i(320, 180)},
	{"name": "PXL-MID", "size": Vector2i(480, 270)},
	{"name": "PXL-SOFT", "size": Vector2i(640, 360)},
	{"name": "3D-NATIVE", "size": Vector2i(1920, 1080)},
]
const MARGIN_TEXELS := 1

signal settings_changed

@export var preset_index := 2  # PXL-SOFT 640x360 (x3): enough pixels for readable character detail
@export var pipeline: Pipeline = Pipeline.SUBVIEWPORT
## Mode 3: limited colour levels + ordered dither.
@export var post_enabled := false
## Colour grade (split toning, saturation, vignette). 0 = raw render.
@export var grade_strength := 1.0

var viewport: SubViewport
var display: TextureRect
## World scenes are added under this node.
var world_root: Node3D

var _grade_material: ShaderMaterial
var _texel_screen := 4.0


func _ready() -> void:
	# Parent is a plain Node, so anchors would resolve to zero size: size explicitly.
	position = Vector2.ZERO
	size = Vector2(OUTPUT_SIZE)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	viewport = SubViewport.new()
	viewport.name = "WorldViewport"
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.positional_shadow_atlas_size = 4096
	viewport.audio_listener_enable_3d = true
	add_child(viewport)

	world_root = Node3D.new()
	world_root.name = "WorldRoot"
	viewport.add_child(world_root)

	display = TextureRect.new()
	display.name = "Display"
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)

	_grade_material = ShaderMaterial.new()
	_grade_material.shader = preload("res://shaders/pixel_grade.gdshader")
	display.material = _grade_material

	apply_settings()


func preset_name() -> String:
	return PRESETS[preset_index]["name"]


func render_size() -> Vector2i:
	return PRESETS[preset_index]["size"]


func pipeline_name() -> String:
	if preset_index == PRESETS.size() - 1:
		return "원본 3D (픽셀화 OFF)"
	return "M1 SubViewport 확대" if pipeline == Pipeline.SUBVIEWPORT else "M2 3D 스케일링(nearest)"


## Size of one render texel in screen (output) pixels.
func texel_screen_size() -> float:
	return _texel_screen


func set_preset(index: int) -> void:
	preset_index = clampi(index, 0, PRESETS.size() - 1)
	apply_settings()


func toggle_pipeline() -> void:
	pipeline = Pipeline.SCALING_3D if pipeline == Pipeline.SUBVIEWPORT else Pipeline.SUBVIEWPORT
	apply_settings()


func set_post_enabled(on: bool) -> void:
	post_enabled = on
	apply_settings()


func apply_settings() -> void:
	if viewport == null:
		return
	var rs := render_size()
	var factor := maxi(1, OUTPUT_SIZE.y / rs.y)
	_texel_screen = float(factor)
	var margin_px := MARGIN_TEXELS * factor
	if pipeline == Pipeline.SCALING_3D and factor > 1:
		viewport.size = OUTPUT_SIZE + Vector2i(margin_px, margin_px) * 2
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_NEAREST
		viewport.scaling_3d_scale = 1.0 / factor
		display.size = Vector2(viewport.size)
	else:
		viewport.size = rs + Vector2i(MARGIN_TEXELS, MARGIN_TEXELS) * 2
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 1.0
		display.size = Vector2(viewport.size * factor)
	display.position = Vector2(-margin_px, -margin_px)

	# In SCALING_3D the texture is full-res, so per-texel effects must work on factor-sized blocks.
	var block := factor if pipeline == Pipeline.SCALING_3D else 1
	_grade_material.set_shader_parameter("block_size", float(block))
	_grade_material.set_shader_parameter("dither_enabled", post_enabled)
	_grade_material.set_shader_parameter("grade_strength", grade_strength)
	settings_changed.emit()


## Colour-grade looks selected by the camera style.
const GRADE_PROFILES := {
	"soft": {"shadow_color": Color(0.16, 0.09, 0.28), "saturation": 1.05, "contrast": 1.0, "luma_bands": 0.0, "band_strength": 0.0, "shadow_push": 0.0,
		"shadow_tint": Color(0.86, 0.88, 1.04), "highlight_tint": Color(1.02, 0.98, 0.92), "vignette": 0.22},
	# shadows pushed toward a clear deep blue (the water reference), not violet; light vignette
	"deadcells": {"saturation": 1.15, "contrast": 1.08, "luma_bands": 0.0, "band_strength": 0.0, "shadow_push": 0.45,
		"shadow_color": Color(0.08, 0.17, 0.38), "shadow_tint": Color(0.82, 0.88, 1.1), "highlight_tint": Color(1.04, 1.0, 0.94), "vignette": 0.12},
}
var grade_profile := "soft"


func set_grade_profile(name: String) -> void:
	if not GRADE_PROFILES.has(name) or _grade_material == null:
		return
	grade_profile = name
	var p: Dictionary = GRADE_PROFILES[name]
	for k: String in p:
		_grade_material.set_shader_parameter(k, p[k])


## Sunlight shafts over the picture (0 = none), see pixel_grade.gdshader.
func set_sun_rays(v: float) -> void:
	if _grade_material:
		_grade_material.set_shader_parameter("sun_rays", v)


func set_grade_strength(v: float) -> void:
	grade_strength = v
	apply_settings()


## Vertical texel count the camera must cover (render height incl. margin) and the
## world->texel ratio the camera should use for snapping.
func render_texel_height() -> int:
	return render_size().y


## Sub-texel compensation from a snapping camera (in render texels, +x right, +y up).
func set_subtexel_offset(offset_texels: Vector2) -> void:
	var margin_px := MARGIN_TEXELS * _texel_screen
	display.position = Vector2(-margin_px, -margin_px) \
			+ Vector2(-offset_texels.x, offset_texels.y) * _texel_screen


## Converts a position on this control (screen space) to SubViewport coordinates.
func screen_to_viewport(screen_pos: Vector2) -> Vector2:
	var local := screen_pos - display.global_position
	return local * Vector2(viewport.size) / display.size


## World position -> screen (canvas) position, for sharp HUD text over the pixel world.
func world_to_screen(p: Vector3) -> Variant:
	var cam := get_world_camera()
	if cam == null or cam.is_position_behind(p):
		return null
	var vp := cam.unproject_position(p)
	return display.global_position + vp * display.size / Vector2(viewport.size)


func get_world_camera() -> Camera3D:
	return viewport.get_camera_3d()


## Mouse ray hit on the horizontal plane y = plane_y. Returns null if no camera / no hit.
func mouse_on_plane(plane_y: float) -> Variant:
	var cam := get_world_camera()
	if cam == null:
		return null
	var vp_pos := screen_to_viewport(display.get_global_mouse_position())
	var origin := cam.project_ray_origin(vp_pos)
	var dir := cam.project_ray_normal(vp_pos)
	return Plane(Vector3.UP, plane_y).intersects_ray(origin, dir)
