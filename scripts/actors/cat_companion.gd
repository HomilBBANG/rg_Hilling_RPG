class_name CatCompanion
extends CharacterBody3D
## The black cat (신수). One cat whose state follows the scene (GDD 2.5 [확정]: outdoor follow and
## indoor stay are the same animal, never two): each world spawns at most one, from Game flags.
##   ENCOUNTER  stage A: waits on the path, approaches the player and starts following (간택)
##   FOLLOW     outside: trails the player, warps back when left far behind
##   RESCUE     right after a checkpoint wake-up: circles the player, then sits beside them
##   HOME       inside the camper: wanders between spots; pet (E) and snack (R) here
## Follow distances, warp, spots, affection numbers are [미정] prototype values.

enum Mode { ENCOUNTER, FOLLOW, RESCUE, HOME }

const LAYER := 1 << 3
const WALK_SPEED := 2.2
const MAX_SPEED := 7.5
const FOLLOW_GAP := 1.5
const WARP_DISTANCE := 14.0
## Follow speed grows with the distance beyond the gap, so a walking player is trailed at a steady
## pace (no stop-and-go). Velocity eases toward the target speed.
const FOLLOW_GAIN := 2.4
const ACCEL := 14.0
## Stopped this long before sitting down (short pauses keep the walk pose).
const SIT_DELAY := 0.4

var mode := Mode.FOLLOW
var player: PrototypePlayer
var height_func: Callable
var home_spots: Array[Vector3] = []
var sprite: BakedSprite
var interact_range := 1.5

var _rig: CatRig
var _meshes: Array[MeshInstance3D] = []
var _yaw := 0.0
var _phase := 0.0
var _speed_now := 0.0
var _still_t := 0.0
var _trailing := false
var _dir_idx := 0
var _stuck_t := 0.0
var _happy_t := -1.0
var _rescue_t := 0.0
var _rescue_center := Vector3.ZERO
var _spot := Vector3.ZERO
var _spot_wait := 0.0
var _rng := RandomNumberGenerator.new()
var _script_goal := Vector3.INF
var _script_speed := 0.0


func _ready() -> void:
	_rng.seed = 99
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = LAYER
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.16
	cap.height = 0.45
	shape.shape = cap
	shape.position.y = 0.25
	add_child(shape)
	_rig = CatRig.new()
	add_child(_rig)
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi as MeshInstance3D)
	_spot = global_position
	add_to_group("interactable")
	add_to_group("cat")


static func sprite_bake_spec() -> Dictionary:
	return {
		"builder": func(c: int, r: int) -> Node3D:
			var rig := CatRig.new()
			rig.rotation.y = r * TAU / CatRig.DIRECTIONS
			rig.pose_column(c)
			return rig,
		"cols": CatRig.column_count(),
		"rows": CatRig.DIRECTIONS,
		"cell": Vector2(1.3, 1.5),
	}


func use_sprite_sheet(sheet: SpriteSheet) -> void:
	if sheet == null:
		if sprite:
			sprite.queue_free()
			sprite = null
	else:
		if sprite == null:
			sprite = BakedSprite.new()
			sprite.snap_reference = player
			sprite.anchor = self
			sprite.set_silhouette_color(Color(1.0, 0.85, 0.4, 0.45), 1.0)
			add_child(sprite)
		if sprite.sheet != sheet:
			sprite.set_sheet(sheet)
	for mi in _meshes:
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and sprite:
			mi.visible = false
		elif sprite:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		else:
			mi.visible = true
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func start_rescue() -> void:
	mode = Mode.RESCUE
	_rescue_t = 0.0
	_rescue_center = player.global_position


## Cutscene hook (CutsceneRunner): walk to a point, overriding the current mode; Vector3.INF releases.
func scripted_walk_to(goal: Vector3, speed: float) -> void:
	_script_goal = goal
	_script_speed = speed


func scripted_walking() -> bool:
	return _script_goal != Vector3.INF and _flat(_script_goal - global_position).length() > 0.15


func face(pos: Vector3) -> void:
	var d := pos - global_position
	_yaw = atan2(-d.x, -d.z)
	_rig.rotation.y = _yaw


# ---------------------------------------------------------------- interaction (camper interior)

func can_interact() -> bool:
	return mode == Mode.HOME and visible


func prompt_text() -> String:
	return "E 쓰다듬기 · R 간식 주기 (간식 %d개) — 호감도 %d" % [
		Game.player_state.inventory.count("cat_snack"), Game.cat_affection]


func interact(_p: Node) -> void:
	_happy_t = 0.0
	face(player.global_position)
	if Game.hud:
		Game.hud.float_text(global_position + Vector3(0, 0.9, 0), "♥", Color(1.0, 0.55, 0.7))
		Game.boot.hud.toast("고양이를 쓰다듬었다 — 골골골…")


func interact_alt(_p: Node) -> void:
	var inv := Game.player_state.inventory
	if inv.count("cat_snack") <= 0:
		Game.boot.hud.toast("간식이 없다 — 창고에서 고양이 간식을 꺼내 오자")
		return
	inv.remove("cat_snack", 1)
	var before := Game.cat_affection
	Game.add_cat_affection(Game.SNACK_AFFECTION)
	_happy_t = 0.0
	face(player.global_position)
	Game.hud.float_text(global_position + Vector3(0, 0.9, 0), "♥ +%d" % (Game.cat_affection - before), Color(1.0, 0.55, 0.7), true)
	Game.boot.hud.toast("간식을 줬다 — 호감도 %d → %d" % [before, Game.cat_affection])


# ---------------------------------------------------------------- behaviour

func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	var goal := global_position
	var speed := 0.0
	var follow_vel := Vector3.ZERO
	var use_follow := false
	var to_p := _flat(player.global_position - global_position)
	var dist := to_p.length()
	if _happy_t >= 0.0:
		_happy_t += delta
		if _happy_t > 1.8:
			_happy_t = -1.0
	match mode:
		Mode.ENCOUNTER:
			if dist < 3.5 and player.is_targetable():
				goal = player.global_position
				speed = WALK_SPEED
				if dist < 1.4:
					mode = Mode.FOLLOW
					Game.join_cat()
					Game.combat_log.add("검은 고양이가 따라오기 시작했다", "검은 고양이(신수)가 스스로 다가와 주인공을 따라오기 시작했다 — 동행 시작")
					Game.boot.hud.toast("검은 고양이가 졸졸 따라오기 시작했다")
		Mode.FOLLOW:
			if not player.visible:
				return
			if dist > WARP_DISTANCE:
				_warp_behind()
				return
			use_follow = true
			# Hysteresis: start when clearly left behind, stop once back at the gap (no creeping).
			if not _trailing and dist > FOLLOW_GAP + 0.8:
				_trailing = true
			elif _trailing and dist < FOLLOW_GAP + 0.15:
				_trailing = false
			if _trailing:
				follow_vel = to_p.normalized() * clampf((dist - FOLLOW_GAP) * FOLLOW_GAIN, 1.4, MAX_SPEED)
		Mode.RESCUE:
			_rescue_t += delta
			if _rescue_t < 3.0:
				var ang := _rescue_t * 2.1 + 1.2
				goal = _rescue_center + Vector3(cos(ang), 0, sin(ang)) * 0.95
				speed = WALK_SPEED * 0.8
			elif _flat(player.global_position - _rescue_center).length() > 2.0:
				mode = Mode.FOLLOW
		Mode.HOME:
			if dist < 2.2:
				if _happy_t < 0.0:
					_yaw = lerp_angle(_yaw, atan2(-to_p.x, -to_p.z), 1.0 - exp(-6.0 * delta))
			else:
				_spot_wait -= delta
				if _spot_wait <= 0.0 and not home_spots.is_empty():
					_spot = home_spots[_rng.randi() % home_spots.size()]
					_spot_wait = _rng.randf_range(7.0, 13.0)
				goal = _spot
				speed = WALK_SPEED * 0.6
	if _script_goal != Vector3.INF:
		use_follow = false
		goal = _script_goal
		speed = _script_speed
	var desired := follow_vel
	if not use_follow:
		var d := _flat(goal - global_position)
		if speed > 0.0 and d.length() > 0.12:
			desired = d.normalized() * minf(speed, d.length() * 3.0)  # slow down on arrival
	if _happy_t >= 0.0:
		desired = Vector3.ZERO
	velocity = _flat(velocity).move_toward(desired, ACCEL * delta)
	if velocity.length() > 0.3:
		_yaw = lerp_angle(_yaw, atan2(-velocity.x, -velocity.z), 1.0 - exp(-10.0 * delta))
	elif mode == Mode.RESCUE and _rescue_t >= 3.0:
		_yaw = lerp_angle(_yaw, atan2(-to_p.x, -to_p.z), 1.0 - exp(-6.0 * delta))
	move_and_slide()
	if height_func.is_valid():
		global_position.y = height_func.call(global_position.x, global_position.z)
	_speed_now = _flat(get_real_velocity()).length()
	# Caught on a prop (campfire, table, camper) while trailing: rejoin the player instead.
	if use_follow and desired.length() > 1.0 and _speed_now < 0.4:
		_stuck_t += delta
		if _stuck_t > 1.2:
			_stuck_t = 0.0
			_warp_behind()
	else:
		_stuck_t = 0.0


func _warp_behind() -> void:
	var p := player.global_position + Vector3(0.9, 0, 0.9)
	velocity = Vector3.ZERO
	global_position = Vector3(p.x, height_func.call(p.x, p.z) if height_func.is_valid() else 0.0, p.z)


func _process(delta: float) -> void:
	_still_t = 0.0 if _speed_now > 0.25 else _still_t + delta
	var moving := _still_t < SIT_DELAY
	if _speed_now > 0.05:
		_phase += delta * (4.0 + _speed_now * 2.6)
	_rig.rotation.y = _yaw
	var col: int
	if _happy_t >= 0.0:
		var f := int(_happy_t * 3.0) % 2
		_rig.pose_sit(true, f * 0.5)
		col = CatRig.column_for("happy", f)
	elif moving:
		var n: int = CatRig.ANIMS[1][1]
		var f := int(fposmod(_phase, TAU) / TAU * n) % n
		_rig.pose_walk(TAU * f / n, 1.0)
		col = CatRig.column_for("walk", f)
	else:
		_rig.pose_sit(false)
		col = CatRig.column_for("sit", 0)
	if sprite:
		sprite.set_frame(col, _facing_index())


## 8-direction sprite row with hysteresis: switch only when clearly past the boundary, so a path
## running near a 22.5 deg boundary doesn't flip the facing every few frames.
func _facing_index() -> int:
	var step := TAU / CatRig.DIRECTIONS
	if absf(angle_difference(_dir_idx * step, _yaw)) > step * 0.5 + deg_to_rad(8.0):
		_dir_idx = CatRig.direction_index(_yaw)
	return _dir_idx
