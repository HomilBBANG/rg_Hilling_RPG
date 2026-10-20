class_name TopdownCamera
extends Camera3D
## Fixed-angle top-down follow camera. No rotation input by design (GDD 3.1 [확정]).
## In orthogonal mode it snaps its position to the render-texel grid and reports the
## sub-texel remainder to the PixelRenderController, which shifts the displayed image.
## Result: static scenery doesn't shimmer while the camera still scrolls smoothly.

const ZOOM_STEPS: Array[float] = [9.0, 11.0, 13.0, 15.0, 18.0, 22.0]

## Visible world height (metres) of the 1280x720 frame, without the snap margin.
@export var zoom_index := 1
@export var pitch_degrees := 50.0
@export var follow_sharpness := 10.0
@export var ortho_distance := 40.0
@export var perspective_fov := 25.0

var target: Node3D
var render: PixelRenderController
var snap_enabled := true
var orthogonal := true

var _focus := Vector3.ZERO
var _has_focus := false


func _ready() -> void:
	# Run after the player has moved this frame.
	process_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	rotation = Vector3(deg_to_rad(-pitch_degrees), 0.0, 0.0)
	near = 0.5
	far = 160.0
	current = true
	_apply_projection()


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
	return render.render_texel_height() if render else 720


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
	var goal := target.global_position + Vector3(0.0, 0.8, 0.0)
	if not _has_focus:
		_focus = goal
		_has_focus = true
	else:
		_focus = _focus.lerp(goal, 1.0 - exp(-follow_sharpness * delta))

	var b := Basis.from_euler(Vector3(deg_to_rad(-pitch_degrees), 0.0, 0.0))
	var desired := _focus + b.z * _camera_distance()
	var offset := Vector2.ZERO
	if orthogonal and snap_enabled:
		var texel := view_height() / float(_texel_height())
		var local := b.inverse() * desired
		var sx := roundf(local.x / texel) * texel
		var sy := roundf(local.y / texel) * texel
		offset = Vector2(local.x - sx, local.y - sy) / texel
		desired = b * Vector3(sx, sy, local.z)
	global_transform = Transform3D(b, desired)
	if render:
		render.set_subtexel_offset(offset)
