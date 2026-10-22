class_name CamperVehicle
extends CharacterBody3D
## Drivable camper (GDD 9.1 [확정]; driving feel per CAMPERVAN_DRIVING_HANDOFF / GDD 9.7).
## HEADING control (default, user's choice — GTA-style car driving relative to the camper's nose):
## W = gas; S = brake while rolling forward, then (held after a short stop) a slow reverse; W + S
## together = brake and stay put; A/D steer left/right like a car — only while rolling, sharper the
## faster it goes up to a limit, and reversing swings the back toward the A/D side as a real car
## does. Let go and it rolls to a stop. Velocity always points along the body: no sideways slip.
## Kept for comparison: ARCADE (WASD = screen direction, auto back-off when wedged) and LEGACY
## (first P1 version: slow car-style W/S throttle + A/D steering wheel).
## The physics body turns smoothly; the visible model (baked 16-direction sprite + its shadow-only
## 3D source) snaps to the nearest baked direction. All tuning values are temporary.

enum DriveMode { HEADING, ARCADE, LEGACY }

@export var control := DriveMode.HEADING
@export_group("Heading tuning (temporary values)")
@export var heading_max_speed := 6.0      ## m/s, W
@export var heading_reverse_speed := 2.2  ## m/s, S after stopping (slow reverse)
@export var heading_accel := 8.0          ## m/s^2, W
@export var heading_reverse_accel := 3.0  ## m/s^2, reversing
@export var heading_brake := 16.0         ## m/s^2, S while rolling forward / W while reversing / W+S
@export var heading_coast := 7.0          ## m/s^2, no W/S
@export var heading_reverse_delay := 0.3  ## s standing still with S held before it backs up
@export var heading_turn_radius := 4.6    ## m, tightest turn at full lock (yaw rate = speed / radius)
@export var heading_turn_deg := 80.0      ## deg/s, cap on the turn rate at speed
@export var heading_steer_rate := 6.0     ## how fast the wheel follows A/D (lock per second)
@export_group("")
@export_group("Arcade tuning (temporary values)")
@export var max_speed := 6.0          ## m/s
@export var acceleration := 14.0      ## m/s^2
@export var coast_decel := 20.0       ## m/s^2, no input
@export var max_turn_deg := 480.0     ## deg/s at standstill / low speed
@export var high_speed_turn_deg := 240.0  ## deg/s at max speed (wider arc when fast)
@export var sharp_turn_slowdown := 0.35  ## speed factor while facing away from the target
@export var unstick_speed := 3.0      ## m/s, automatic back-off when wedged
@export var unstick_time := 0.6       ## s of back-off per attempt
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
## Engine power from fuel / durability (Game.camper_power): 0 = it only rolls to a stop.
var power := 1.0
## Turning speed factor from upgrades (마력 부스터).
var turn_mult := 1.0
## Tours: heading / legacy -> {"throttle": -1..1 (W/S), "steer": -1..1 (A = +1, D = -1)};
## arcade -> {"dir": Vector2 screen dir}. Empty = read the keyboard.
var scripted := {}

var _steer := 0.0
var _stopped_t := 0.0  # time standing still with S held (GTA-style: brake, pause, then reverse)
var _shape: BoxShape3D
var _blocked_t := 0.0
var _unstick_t := 0.0
var _unstick_dir := -1.0  # -1 back off, +1 creep forward


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = PhysLayers.WORLD
	collision_mask = PhysLayers.CAMPER_MASK
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
	match control:
		DriveMode.HEADING:
			_drive_heading(delta)
		DriveMode.ARCADE:
			_drive_arcade(delta)
		_:
			_drive_legacy(delta)
	velocity = forward() * speed
	move_and_slide()
	if get_slide_collision_count() > 0:
		if control == DriveMode.LEGACY:
			speed *= 0.4
		elif _head_on(get_last_slide_collision().get_normal(), signf(speed)):
			# Hit something head-on: lose most speed but keep control (turn away / back off).
			# Grazing a wall while sliding along it keeps speed.
			speed *= 0.3
	global_position.x = clampf(global_position.x, walk_bounds.position.x, walk_bounds.end.x)
	global_position.z = clampf(global_position.z, walk_bounds.position.y, walk_bounds.end.y)
	if height_func.is_valid():
		global_position.y = height_func.call(global_position.x, global_position.z)
	_sync_visual()


## W/S/A/D relative to the nose: x = steer (A +1, D -1), y = throttle (W +1, S -1).
func _wheel_input() -> Vector2:
	if not scripted.is_empty():
		return Vector2(scripted.get("steer", 0.0), scripted.get("throttle", 0.0))
	return Vector2(Input.get_axis("move_right", "move_left"), Input.get_axis("move_down", "move_up"))


## Gas / brake-reverse keys separately (W + S together means "hold still", which an axis hides).
## Tours: {"throttle": 1 / -1, "steer", "brake": true = both held}.
func _pedals() -> Vector2i:
	if not scripted.is_empty():
		if scripted.get("brake", false):
			return Vector2i(1, 1)
		var th := float(scripted.get("throttle", 0.0))
		return Vector2i(1 if th > 0.05 else 0, 1 if th < -0.05 else 0)
	return Vector2i(1 if Input.is_action_pressed("move_up") else 0, 1 if Input.is_action_pressed("move_down") else 0)


func _drive_heading(delta: float) -> void:
	var pedals := _pedals()
	var gas := pedals.x == 1
	var back := pedals.y == 1
	if gas and back:
		speed = move_toward(speed, 0.0, heading_brake * delta)  # both: brake and stay put
		_stopped_t = 0.0
	elif gas:
		_stopped_t = 0.0
		if speed < -0.05:
			speed = move_toward(speed, 0.0, heading_brake * delta)  # reversing: brake first
		elif power > 0.0:
			speed = move_toward(speed, heading_max_speed * power, heading_accel * delta)
		else:
			speed = move_toward(speed, 0.0, heading_coast * delta)
	elif back:
		if speed > 0.05:
			speed = move_toward(speed, 0.0, heading_brake * delta)  # rolling forward: brake
			_stopped_t = 0.0
		else:
			_stopped_t += delta
			if _stopped_t >= heading_reverse_delay and power > 0.0:
				speed = move_toward(speed, -heading_reverse_speed * minf(power, 1.0), heading_reverse_accel * delta)
	else:
		speed = move_toward(speed, 0.0, heading_coast * delta)
		_stopped_t = 0.0
	# Steering like a car: the wheel eases toward A/D, the body only turns while rolling (yaw rate =
	# speed / turn radius, capped), and the sign follows the motion so reversing swings the back
	# toward the steered side.
	var want := _wheel_input().x
	_steer = move_toward(_steer, want, heading_steer_rate * delta)
	if absf(_steer) > 0.01 and absf(speed) > 0.05:
		var rate := minf(absf(speed) / heading_turn_radius, deg_to_rad(heading_turn_deg) * turn_mult)
		_try_rotate(signf(speed) * _steer * rate * delta)


func _arcade_input() -> Dictionary:
	if not scripted.is_empty():
		return scripted
	return {"dir": Input.get_vector("move_left", "move_right", "move_up", "move_down")}


## Screen direction (x right, y down) -> heading yaw. The camera never rotates, so screen up = -Z.
static func dir_to_yaw(dir: Vector2) -> float:
	return atan2(-dir.y, dir.x)


func _drive_arcade(delta: float) -> void:
	var dir: Vector2 = _arcade_input().get("dir", Vector2.ZERO)
	if dir.length() < 0.1:
		_unstick_t = 0.0
		_blocked_t = 0.0
		speed = move_toward(speed, 0.0, coast_decel * delta)
		return
	var target := dir_to_yaw(dir)
	var diff := angle_difference(rotation.y, target)
	# Tight turns when slow, a wider arc at full speed.
	var t := clampf(absf(speed) / max_speed, 0.0, 1.0)
	var rate := deg_to_rad(lerpf(max_turn_deg, high_speed_turn_deg, t))
	var turned := _try_rotate(clampf(diff, -rate * delta, rate * delta))
	if _unstick_t > 0.0:
		# Wedged: move straight back (or forward) a little while still turning toward the target.
		_unstick_t -= delta
		if absf(angle_difference(rotation.y, target)) < deg_to_rad(10.0):
			_unstick_t = 0.0  # facing where the player wants to go: drive on
		elif _unstick_t <= 0.0 and not turned and absf(diff) > deg_to_rad(15.0):
			_unstick_t = unstick_time  # still no room to turn: keep going without a pause
			if _blocked_toward(_unstick_dir):
				_unstick_dir = -_unstick_dir
		speed = move_toward(speed, unstick_speed * _unstick_dir, acceleration * delta)
		return
	# Can't turn toward where the player wants to go (body wedged against a wall / tree):
	# back off by itself, or creep forward if the way back is blocked too.
	if not turned and absf(diff) > deg_to_rad(15.0):
		_blocked_t += delta
		if _blocked_t > 0.12:
			_blocked_t = 0.0
			_unstick_t = unstick_time
			_unstick_dir = 1.0 if _blocked_toward(-1.0) and not _blocked_toward(1.0) else -1.0
			return
	else:
		_blocked_t = 0.0
	if speed < 0.0:
		speed = move_toward(speed, 0.0, coast_decel * delta)
	# Facing well away from the target (U-turn, sharp corner): ease off while turning.
	var align := cos(absf(angle_difference(rotation.y, target)))
	var target_speed := max_speed * dir.limit_length(1.0).length() * power
	if align < 0.7:
		target_speed *= lerpf(sharp_turn_slowdown, 1.0, clampf(align / 0.7, 0.0, 1.0))
	if speed < target_speed:
		speed = move_toward(speed, target_speed, acceleration * delta)
	else:
		speed = move_toward(speed, target_speed, coast_decel * delta)


## True when a collision normal faces straight against the motion (head-on, not grazing).
func _head_on(normal: Vector3, dir_sign: float) -> bool:
	return Vector3(normal.x, 0.0, normal.z).normalized().dot(forward() * dir_sign) < -0.7


## Would moving 0.4 m forward (+1) / backward (-1) run head-on into something?
func _blocked_toward(dir_sign: float) -> bool:
	var col := KinematicCollision3D.new()
	if not test_move(global_transform, forward() * dir_sign * 0.4, col):
		return false
	return _head_on(col.get_normal(), dir_sign)


## Rotates unless the turned body would sink deep into an obstacle (a long camper pivoting into a
## tree got stuck); then try half the turn. Shallow overlap is allowed: move_and_slide pushes the
## body back out, so a camper that is merely touching a prop can still turn away from it.
func _try_rotate(amount: float) -> bool:
	if absf(amount) < 0.00001:
		return true
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
			return true
	return false


func _drive_legacy(delta: float) -> void:
	var input := _wheel_input()
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
