class_name CamperVehicle
extends CharacterBody3D
## Drivable camper (GDD 9.1 [확정]: the player drives it directly). The physics body turns
## smoothly; the visible model (baked 16-direction sprite + its shadow-only 3D source) snaps to
## the nearest baked direction. W/S throttle & brake/reverse, A/D steer, E (slow) to get out.
## Speeds / steering / no fuel use are [미정] prototype values.

const MAX_FORWARD := 9.0
const MAX_REVERSE := 3.5
const ACCEL := 4.5
const BRAKE := 10.0
const DRAG := 2.5
const WHEELBASE := 4.4
const MAX_STEER := deg_to_rad(32.0)
const EXIT_SPEED := 0.6

var camper: CamperExterior
var base_yaw := 0.0  # radians; sprite direction 0
var height_func: Callable
var walk_bounds := Rect2(-1000, -1000, 2000, 2000)
var driving := false
var speed := 0.0
var scripted_input := Vector2.ZERO  # tours: x = steer, y = throttle (-1..1)

var _steer := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 1
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CamperExterior.LENGTH, 3.0, CamperExterior.WIDTH)
	shape.shape = box
	shape.position.y = 1.5
	add_child(shape)
	camper = CamperExterior.new()
	camper.name = "Camper"
	camper.with_collider = false
	add_child(camper)
	_sync_visual()


func yaw() -> float:
	return rotation.y


func forward() -> Vector3:
	return Vector3(cos(rotation.y), 0.0, -sin(rotation.y))


func _physics_process(delta: float) -> void:
	if not driving:
		return
	var input := scripted_input
	if input == Vector2.ZERO:
		input = Vector2(Input.get_axis("move_right", "move_left"), Input.get_axis("move_down", "move_up"))
	var throttle := input.y
	if throttle > 0.0:
		speed += (BRAKE if speed < 0.0 else ACCEL) * throttle * delta
	elif throttle < 0.0:
		speed += (BRAKE if speed > 0.0 else ACCEL * 0.7) * throttle * delta
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)
	speed = clampf(speed, -MAX_REVERSE, MAX_FORWARD)
	_steer = move_toward(_steer, input.x * MAX_STEER, delta * 2.5)
	rotation.y += speed / WHEELBASE * tan(_steer) * delta
	velocity = forward() * speed
	move_and_slide()
	if get_slide_collision_count() > 0:
		speed *= 0.4
	global_position.x = clampf(global_position.x, walk_bounds.position.x, walk_bounds.end.x)
	global_position.z = clampf(global_position.z, walk_bounds.position.y, walk_bounds.end.y)
	if height_func.is_valid():
		global_position.y = height_func.call(global_position.x, global_position.z)
	_sync_visual()


func sprite_direction() -> int:
	var step := TAU / CamperExterior.SPRITE_DIRECTIONS
	return posmod(roundi((rotation.y - base_yaw) / step), CamperExterior.SPRITE_DIRECTIONS)


## Model turned to the baked direction so sprite and shadow agree.
func _sync_visual() -> void:
	var dir := sprite_direction()
	var snapped := base_yaw + dir * TAU / CamperExterior.SPRITE_DIRECTIONS
	camper.rotation.y = snapped - rotation.y
	camper.set_sprite_dir(dir)


func can_exit() -> bool:
	return absf(speed) < EXIT_SPEED


## Where the driver steps out: beside the cab on the door (camera) side, else the far side.
func exit_position() -> Vector3:
	for local in [Vector3(2.4, 0, 2.0), Vector3(2.4, 0, -2.0), Vector3(-4.6, 0, 0)]:
		var p := camper.to_global(local)
		var params := PhysicsShapeQueryParameters3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.35
		params.shape = sph
		params.transform = Transform3D(Basis(), p + Vector3(0, 0.9, 0))
		params.collision_mask = 1
		if get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty():
			return p
	return camper.to_global(Vector3(2.4, 0, 2.0))
