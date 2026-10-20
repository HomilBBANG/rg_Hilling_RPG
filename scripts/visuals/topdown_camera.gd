class_name TopdownCamera
extends Camera3D
## Fixed-angle top-down follow camera. No rotation input by design (GDD 3.1 [확정]).
## In orthogonal mode it snaps its position to the render-texel grid and reports the
## sub-texel remainder to the PixelRenderController, which shifts the displayed image.
## Result: static scenery doesn't shimmer while the camera still scrolls smoothly.

const ZOOM_STEPS: Array[float] = [8.0, 9.0, 10.0, 11.0, 13.0, 15.0, 18.0, 22.0]

## Camera comparison styles (P0 visual direction test). Pitch = degrees below horizon.
## A reproduces the previous functional prototype view; B/C are the reworked looks.
const STYLES: Array[Dictionary] = [
	{"id": "A", "name": "A 기능형 탑다운(기존)", "pitch": 50.0, "zoom": 3, "offset": Vector3.ZERO,
		"outline": false, "grade": false, "ssao": false, "fog": false, "stylized": false},
	{"id": "B", "name": "B 개선된 탑다운", "pitch": 62.0, "zoom": 2, "offset": Vector3(0, 0, -1.6),
		"outline": true, "grade": true, "ssao": true, "fog": false, "stylized": true},
	{"id": "C", "name": "C 기울어진 디오라마 탑다운", "pitch": 40.0, "zoom": 2, "offset": Vector3(0, 0, -1.0),
		"outline": true, "grade": true, "ssao": true, "fog": true, "stylized": true},
	# D: C's camera + a Dead Cells-like pixel look: flat colours with two-tone cel light,
	# violet shadows, warm key light, light bloom, a few particles.
	{"id": "D", "name": "D 데드셀풍 픽셀", "pitch": 40.0, "zoom": 3, "offset": Vector3(0, 0, -1.0),
		"outline": true, "grade": true, "ssao": false, "fog": true, "stylized": true, "look": "deadcells", "detail": 0.0,
		"foliage_outline": true},
]

## Visible world height (metres) of the output frame, without the snap margin.
@export var zoom_index := 2
@export var pitch_degrees := 40.0
## World-space shift of the look-at point (composition: keep the player a bit below centre).
@export var focus_offset := Vector3.ZERO
@export var follow_sharpness := 10.0
@export var ortho_distance := 40.0
@export var perspective_fov := 25.0

var target: Node3D
var render: PixelRenderController
var snap_enabled := true
## Rigid texel-locked follow (no smoothing). Off = smoothed follow with sub-texel scrolling.
var pixel_lock := true
var orthogonal := true

var outline_enabled := true

var _focus := Vector3.ZERO
var _has_focus := false
var _outline_quad: MeshInstance3D


func _ready() -> void:
	# Run after the player has moved this frame.
	process_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	rotation = Vector3(deg_to_rad(-pitch_degrees), 0.0, 0.0)
	near = 0.5
	far = 160.0
	current = true
	_apply_projection()
	_build_outline_quad()


func _build_outline_quad() -> void:
	# The outline pass needs the depth/normal buffers of the Forward+ renderer.
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	_outline_quad = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_outline_quad.mesh = quad
	_outline_quad.extra_cull_margin = 16384.0
	_outline_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/pixel_outline_post.gdshader")
	m.render_priority = 10
	_outline_quad.material_override = m
	_outline_quad.position = Vector3(0, 0, -1.0)
	add_child(_outline_quad)
	_update_outline_quad()


func set_outline(on: bool) -> void:
	outline_enabled = on
	_update_outline_quad()


## Leaf-clump outlines only (pixel-art trees), independent of the full outline pass.
var foliage_outline := false


func set_foliage_outline(on: bool) -> void:
	foliage_outline = on
	_update_outline_quad()


func _update_outline_quad() -> void:
	if _outline_quad == null:
		return
	_outline_quad.visible = outline_enabled or foliage_outline
	(_outline_quad.material_override as ShaderMaterial).set_shader_parameter("foliage_only", foliage_outline and not outline_enabled)


func outline_supported() -> bool:
	return _outline_quad != null


func set_look(look: String) -> void:
	if _outline_quad == null:
		return
	var m := _outline_quad.material_override as ShaderMaterial
	var dc := look == "deadcells"
	# D: thin dark 1-px silhouette outlines only (no rim light, no crease highlights).
	m.set_shader_parameter("rim_enabled", false)
	m.set_shader_parameter("highlight_enabled", not dc)
	m.set_shader_parameter("outline_darkness", 0.72 if dc else 0.42)
	m.set_shader_parameter("outline_tint_amount", 0.55 if dc else 0.0)
	m.set_shader_parameter("outline_tint", Color(0.1, 0.08, 0.13))


func apply_style(style: Dictionary) -> void:
	set_look(style.get("look", "soft"))
	pitch_degrees = style["pitch"]
	zoom_index = style["zoom"]
	focus_offset = style["offset"]
	set_outline(style["outline"])
	snap_to_target()


func view_height() -> float:
	return ZOOM_STEPS[zoom_index]


func zoom(step: int) -> void:
	zoom_index = clampi(zoom_index + step, 0, ZOOM_STEPS.size() - 1)
	_apply_projection()


func toggle_projection() -> void:
	orthogonal = not orthogonal
	_apply_projection()


func snap_to_target() -> void:
	_has_focus = false


func _texel_height() -> int:
	return render.render_texel_height() if render else 1080


func _apply_projection() -> void:
	var h := float(_texel_height())
	var margin := PixelRenderController.MARGIN_TEXELS * 2.0
	if orthogonal:
		projection = PROJECTION_ORTHOGONAL
		size = view_height() * (h + margin) / h
	else:
		projection = PROJECTION_PERSPECTIVE
		fov = perspective_fov * (h + margin) / h


func _camera_distance() -> float:
	if orthogonal:
		return ortho_distance
	return view_height() * 0.5 / tan(deg_to_rad(perspective_fov) * 0.5)


func _process(delta: float) -> void:
	_apply_projection()
	if target == null or not is_instance_valid(target):
		return
	var goal := target.global_position + Vector3(0.0, 0.8, 0.0) + focus_offset
	if not _has_focus:
		_focus = goal
		_has_focus = true
	else:
		_focus = _focus.lerp(goal, 1.0 - exp(-follow_sharpness * delta))

	var b := Basis.from_euler(Vector3(deg_to_rad(-pitch_degrees), 0.0, 0.0))
	var desired := _focus + b.z * _camera_distance()
	var offset := Vector2.ZERO
	if orthogonal and snap_enabled and pixel_lock:
		# Rigid follow on the texel grid: camera = snapped(target) + whole-texel offset, the same
		# rounding the sprite card uses, so the player never jitters by a texel against the
		# camera (a smoothed camera stepping 2/3 texels per frame out of phase did).
		var texel := view_height() / float(_texel_height())
		var lt := b.inverse() * target.global_position
		var lo := b.inverse() * (Vector3(0.0, 0.8, 0.0) + focus_offset + b.z * _camera_distance())
		desired = b * Vector3(roundf(lt.x / texel) * texel + roundf(lo.x / texel) * texel,
				roundf(lt.y / texel) * texel + roundf(lo.y / texel) * texel, lt.z + lo.z)
	elif orthogonal and snap_enabled:
		var texel := view_height() / float(_texel_height())
		var local := b.inverse() * desired
		var sx := roundf(local.x / texel) * texel
		var sy := roundf(local.y / texel) * texel
		offset = Vector2(local.x - sx, local.y - sy) / texel
		desired = b * Vector3(sx, sy, local.z)
	global_transform = Transform3D(b, desired)
	if render:
		render.set_subtexel_offset(offset)
