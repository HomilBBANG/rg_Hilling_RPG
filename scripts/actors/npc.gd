class_name Npc
extends Node3D
## Merchant NPC with a simple daily routine (GDD 10.4 [확정]: works at the stall during opening
## hours, goes home at night; no detailed life simulation). Walks between the house door and the
## counter at opening / closing time and is hidden while at home. Times are [미정] (ShopDB).
## Without a shop (shop_id "") the NPC simply stays at its spot (e.g. the king on his throne).

enum Where { COUNTER, HOME, TO_COUNTER, TO_HOME }

const WALK_SPEED := 1.6

var look := "rosa"
var shop_id := "rosa"
var counter_pos := Vector3.ZERO
var counter_yaw := 0.0
var door_pos := Vector3.ZERO
var height_func: Callable
var player: Node3D
var where := Where.COUNTER
var sprite: BakedSprite

var _rig: NpcRig
var _body: AnimatableBody3D  # solid: the hero, monsters, the cat and the camper can't pass through
var _meshes: Array[MeshInstance3D] = []
var _yaw := 0.0
var _phase := 0.0
## Scripted walking (cutscene actor_move) and chasing (the chapter-1 escape) override the routine.
var chase: Node3D
var chase_speed := 4.2
var _walk_goal := Vector3.INF
var _walk_speed := 2.0


func _ready() -> void:
	_rig = NpcRig.new(look)
	add_child(_rig)
	_body = AnimatableBody3D.new()
	_body.sync_to_physics = false
	_body.collision_layer = PhysLayers.NPC
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.5
	shape.shape = cap
	shape.position.y = 0.75
	_body.add_child(shape)
	add_child(_body)
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi as MeshInstance3D)
	# Start where the clock says, without walking there.
	if _on_duty():
		_set_at(Where.COUNTER)
	else:
		_set_at(Where.HOME)


static func sprite_bake_spec(look_id: String) -> Dictionary:
	return {
		"builder": func(c: int, r: int) -> Node3D:
			var rig := NpcRig.new(look_id)
			rig.rotation.y = r * TAU / NpcRig.DIRECTIONS
			rig.pose_column(c)
			return rig,
		"cols": NpcRig.column_count(),
		"rows": NpcRig.DIRECTIONS,
		"cell": Vector2(2.4, 4.0),
	}


func use_sprite_sheet(sheet: SpriteSheet) -> void:
	if sheet == null:
		if sprite:
			sprite.queue_free()
			sprite = null
	else:
		if sprite == null:
			sprite = BakedSprite.new()
			sprite.anchor = self
			sprite.set_silhouette(false)  # keepers stand behind counters; an x-ray outline only clutters
			add_child(sprite)
		if sprite.sheet != sheet:
			sprite.set_sheet(sheet)
	for mi in _meshes:
		if sprite:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		else:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _on_duty() -> bool:
	return shop_id == "" or ShopDB.is_open(shop_id)


func is_working() -> bool:
	return where == Where.COUNTER


func _set_at(w: Where) -> void:
	where = w
	var p := counter_pos if w == Where.COUNTER else door_pos
	global_position = Vector3(p.x, _ground(p), p.z)
	_yaw = counter_yaw
	visible = w != Where.HOME
	if _body:
		_body.collision_layer = PhysLayers.NPC if visible else 0  # at home: not in the street


func _ground(p: Vector3) -> float:
	return height_func.call(p.x, p.z) if height_func.is_valid() else 0.0


## Solid or not (escape guards pass through the camper they chase; catching is by distance).
func set_solid(on: bool) -> void:
	if _body:
		_body.collision_layer = PhysLayers.NPC if on else 0


func scripted_walk_to(goal: Vector3, speed: float) -> void:
	_walk_goal = goal
	_walk_speed = maxf(speed, 0.5)


func scripted_walking() -> bool:
	return _walk_goal != Vector3.INF


func face(pos: Vector3) -> void:
	var d := pos - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		_yaw = atan2(-d.x, -d.z)


## Walks toward goal; true while still on the way.
func _step_toward(goal: Vector3, speed: float, stop: float, delta: float) -> bool:
	var d := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
	if d.length() <= stop:
		return false
	global_position += d.normalized() * minf(speed * delta, d.length() - stop)
	global_position.y = _ground(global_position)
	_yaw = atan2(-d.x, -d.z)
	return true


func _process(delta: float) -> void:
	if _walk_goal != Vector3.INF or (chase and is_instance_valid(chase)):
		var moving_s := false
		if _walk_goal != Vector3.INF:
			moving_s = _step_toward(_walk_goal, _walk_speed, 0.08, delta)
			if not moving_s:
				_walk_goal = Vector3.INF
		else:
			moving_s = _step_toward(chase.global_position, chase_speed, 1.2, delta)
			if not moving_s:
				face(chase.global_position)
		_animate(moving_s, delta, chase_speed if chase else _walk_speed)
		return
	var open := _on_duty()
	if open and where == Where.HOME:
		_set_at(Where.HOME)
		where = Where.TO_COUNTER
		visible = true
		_body.collision_layer = PhysLayers.NPC
	elif not open and where == Where.COUNTER:
		where = Where.TO_HOME
	var moving := false
	if where == Where.TO_COUNTER or where == Where.TO_HOME:
		var goal := counter_pos if where == Where.TO_COUNTER else door_pos
		var d := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
		if d.length() < 0.08:
			if where == Where.TO_COUNTER:
				_set_at(Where.COUNTER)
			else:
				_set_at(Where.HOME)
		else:
			var step := d.normalized() * minf(WALK_SPEED * delta, d.length())
			global_position += step
			global_position.y = _ground(global_position)
			_yaw = atan2(-d.x, -d.z)
			moving = true
	elif where == Where.COUNTER and player and player.visible:
		var to_p := player.global_position - global_position
		if Vector2(to_p.x, to_p.z).length() < 4.0:
			_yaw = lerp_angle(_yaw, atan2(-to_p.x, -to_p.z), 1.0 - exp(-5.0 * delta))
		else:
			_yaw = lerp_angle(_yaw, counter_yaw, 1.0 - exp(-3.0 * delta))
	_animate(moving, delta, WALK_SPEED)


func _animate(moving: bool, delta: float, speed: float) -> void:
	if moving:
		_phase += delta * 7.0 * maxf(1.0, speed / WALK_SPEED * 0.6)
	_rig.rotation.y = _yaw
	var col: int
	if moving:
		var f := int(fposmod(_phase, TAU) / TAU * 8.0) % 8
		_rig.pose(TAU * f / 8.0, 1.0)
		col = NpcRig.column_for("walk", f)
	else:
		_rig.pose(0.0, 0.0)
		col = NpcRig.column_for("idle", 0)
	if sprite:
		sprite.set_frame(col, NpcRig.direction_index(_yaw))
