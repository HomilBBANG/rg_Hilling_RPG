class_name CamperVehicle
extends CharacterBody3D
## Drivable camper (GDD 9.1 [확정]; driving feel per CAMPERVAN_DRIVING_HANDOFF / GDD 9.7).
## Arcade top-down control (default): WASD = direction to drive toward ON SCREEN, the camper turns
## toward it and drives forward; Space = brake (priority), hold R = slow straight reverse (A/D
## nudge the heading while reversing). Velocity always points along the body: no sideways slip.
## The legacy car-style controller (W/S throttle, A/D steer) is kept for side-by-side comparison.
## The physics body turns smoothly; the visible model (baked 16-direction sprite + its shadow-only
## 3D source) snaps to the nearest baked direction. All tuning values are temporary.

enum DriveMode { ARCADE, LEGACY }

@export var control := DriveMode.ARCADE
@export_group("Arcade tuning (temporary values)")
@export var max_speed := 6.0          ## m/s
@export var acceleration := 14.0      ## m/s^2
@export var coast_decel := 20.0       ## m/s^2, no input
@export var brake_decel := 35.0       ## m/s^2, Space
@export var max_turn_deg := 480.0     ## deg/s at standstill / low speed
@export var high_speed_turn_deg := 240.0  ## deg/s at max speed (wider arc when fast)
@export var reverse_speed := 3.0      ## m/s, hold R
@export var reverse_turn_deg := 70.0  ## deg/s, A/D while reversing
@export var sharp_turn_slowdown := 0.35  ## speed factor while facing away from the target
@export_group("")

const EXIT_SPEED := 0.6
# Legacy controller (P1 first version)
const LEGACY_MAX_FORWARD := 9.0
const LEGACY_MAX_REVERSE := 3.5
const LEGACY_ACCEL := 4.5
const LEGACY_BRAKE := 10.0
const LEGACY_DRAG := 2.5
const WHEELBASE := 4.4
const MAX_STEER := deg_to_rad(32.0)

var camper: CamperExterior
var base_yaw := 0.0  # radians; sprite direction 0
var height_func: Callable
var walk_bounds := Rect2(-1000, -1000, 2000, 2000)
var driving := false
var speed := 0.0
## Tours: arcade -> {"dir": Vector2 screen dir, "brake": bool, "reverse": bool};
## legacy -> {"steer": float, "throttle": float}. Empty = read the keyboard.
var scripted := {}

var _steer := 0.0
var _shape: BoxShape3D


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 1
	collision_mask = 1
	var shape := CollisionShape3D.new()
	_shape = BoxShape3D.new()
	_shape.size = Vector3(CamperExterior.LENGTH, 3.0, CamperExterior.WIDTH)
	shape.shape = _shape
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
	if control == DriveMode.ARCADE:
		_drive_arcade(delta)
	else:
		_drive_legacy(delta)
	velocity = forward() * speed
	move_and_slide()
	if get_slide_collision_count() > 0:
		# Bumped into something: lose most speed but keep control (turn away / reverse out).
		speed *= 0.3 if control == DriveMode.ARCADE else 0.4
	global_position.x = clampf(global_position.x, walk_bounds.position.x, walk_bounds.end.x)
	global_position.z = clampf(global_position.z, walk_bounds.position.y, walk_bounds.end.y)
	if height_func.is_valid():
		global_position.y = height_func.call(global_position.x, global_position.z)
	_sync_visual()


func _arcade_input() -> Dictionary:
	if not scripted.is_empty():
		return scripted
	return {
		"dir": Input.get_vector("move_left", "move_right", "move_up", "move_down"),
		"brake": Input.is_action_pressed("brake"),
		"reverse": Input.is_action_pressed("reverse"),
	}


## Screen direction (x right, y down) -> heading yaw. The camera never rotates, so screen up = -Z.
static func dir_to_yaw(dir: Vector2) -> float:
	return atan2(-dir.y, dir.x)


func _drive_arcade(delta: float) -> void:
	var inp := _arcade_input()
	var dir: Vector2 = inp.get("dir", Vector2.ZERO)
	# Priority: Space brake > R reverse > WASD target direction.
	if inp.get("brake", false):
		speed = move_toward(speed, 0.0, brake_decel * delta)
		return
	if inp.get("reverse", false):
		if speed > 0.0:
			speed = move_toward(speed, 0.0, brake_decel * delta)
		else:
			speed = move_toward(speed, -reverse_speed, acceleration * delta)
		# A/D: slow heading nudge (counter-clockwise / clockwise seen from above).
		if absf(dir.x) > 0.1:
			_try_rotate(-signf(dir.x) * deg_to_rad(reverse_turn_deg) * delta)
		return
	if dir.length() < 0.1:
		var decel := brake_decel if speed < 0.0 else coast_decel
		speed = move_toward(speed, 0.0, decel * delta)
		return
	if speed < 0.0:  # was reversing: stop first
		speed = move_toward(speed, 0.0, brake_decel * delta)
	var target := dir_to_yaw(dir)
	var diff := angle_difference(rotation.y, target)
	# Tight turns when slow, a wider arc at full speed.
	var t := clampf(absf(speed) / max_speed, 0.0, 1.0)
	var rate := deg_to_rad(lerpf(max_turn_deg, high_speed_turn_deg, t))
	_try_rotate(clampf(diff, -rate * delta, rate * delta))
	# Facing well away from the target (U-turn, sharp corner): ease off while turning.
	var align := cos(absf(angle_difference(rotation.y, target)))
	var target_speed := max_speed * dir.limit_length(1.0).length()
	if align < 0.7:
		target_speed *= lerpf(sharp_turn_slowdown, 1.0, clampf(align / 0.7, 0.0, 1.0))
	if speed < target_speed:
		speed = move_toward(speed, target_speed, acceleration * delta)
	else:
		speed = move_toward(speed, target_speed, coast_decel * delta)


## Rotates unless the turned body would sink deep into an obstacle (a long camper pivoting into a
## tree got stuck); then try half the turn. Shallow overlap is allowed: move_and_slide pushes the
## body back out, so a camper that is merely touching a prop can still turn away from it.
func _try_rotate(amount: float) -> void:
	if absf(amount) < 0.00001:
		return
	for f in [1.0, 0.5]:
		var xf := global_transform
		xf.basis = Basis(Vector3.UP, rotation.y + amount * f)
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = _shape
		params.transform = Transform3D(xf.basis, xf.origin + Vector3(0, 1.5, 0))
		params.collision_mask = collision_mask
		params.exclude = [get_rid()]
		params.margin = -0.08
		if get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty():
			rotation.y += amount * f
			return


func _drive_legacy(delta: float) -> void:
	var input := Vector2(scripted.get("steer", 0.0), scripted.get("throttle", 0.0))
	if scripted.is_empty():
		input = Vector2(Input.get_axis("move_right", "move_left"), Input.get_axis("move_down", "move_up"))
	var throttle := input.y
	if throttle > 0.0:
		speed += (LEGACY_BRAKE if speed < 0.0 else LEGACY_ACCEL) * throttle * delta
	elif throttle < 0.0:
		speed += (LEGACY_BRAKE if speed > 0.0 else LEGACY_ACCEL * 0.7) * throttle * delta
	else:
		speed = move_toward(speed, 0.0, LEGACY_DRAG * delta)
	speed = clampf(speed, -LEGACY_MAX_REVERSE, LEGACY_MAX_FORWARD)
	_steer = move_toward(_steer, input.x * MAX_STEER, delta * 2.5)
	rotation.y += speed / WHEELBASE * tan(_steer) * delta


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
