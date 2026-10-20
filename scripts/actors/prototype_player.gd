class_name PrototypePlayer
extends CharacterBody3D
## P0 visual-test player: WASD walking, one swing motion, belt lantern. No stats/combat (P1).
## Visual: PlayerRig 3D model, optionally replaced on screen by its baked pixel sprite.

const WALK_SPEED := 3.6
const RUN_SPEED := 6.0
const TURN_SHARPNESS := 14.0
## Extra visual layer for the player's own meshes (excluded from the lantern's shadow casters).
const SELF_LAYER := 1 << 19

## Callable(x: float, z: float) -> float giving ground height. Set by the world.
var height_func: Callable
## Optional bounds clamp (x/z rect) set by the world.
var walk_bounds := Rect2(-1000, -1000, 2000, 2000)
## Scripted movement for automated capture tours (Vector2.ZERO = use keyboard).
var scripted_move := Vector2.ZERO
var scripted_running := false

var model: PlayerRig
var lantern_light: OmniLight3D
var silhouette_enabled := true
## Pre-rendered pixel sprite (Dead Cells-style pipeline). null = draw the 3D model directly.
var sprite: BakedSprite

var _silhouette_mat: ShaderMaterial
var _mesh_materials: Array[StandardMaterial3D] = []
var _meshes: Array[MeshInstance3D] = []
var _mesh_shadow_modes: Array[int] = []
var _walk_phase := 0.0
var _yaw := 0.0
var _attack_t := -1.0
var _speed_now := 0.0
var _lantern_state := false


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)
	model = PlayerRig.new()
	model.name = "Model"
	add_child(model)
	lantern_light = OmniLight3D.new()
	lantern_light.position = Vector3(-0.1, 0.1, -0.1)
	lantern_light.light_color = Color(1.0, 0.76, 0.48)
	lantern_light.light_energy = 1.8
	lantern_light.omni_range = 8.0
	lantern_light.omni_attenuation = 1.1
	lantern_light.shadow_enabled = true
	lantern_light.shadow_bias = 0.08
	# The lantern hangs on the body: don't let the body itself cast its shadow
	# (otherwise a huge wedge of darkness follows the player).
	lantern_light.shadow_caster_mask = 0xFFFFF & ~SELF_LAYER
	lantern_light.light_cull_mask = 0xFFFFF & ~SELF_LAYER
	lantern_light.visible = false
	model.lantern_anchor.add_child(lantern_light)
	_setup_silhouette(Color(1.0, 0.95, 0.8, 0.4))
	add_to_group("player")


## Bake request for SpriteBaker: every animation column x 8 facing directions.
static func sprite_bake_spec() -> Dictionary:
	return {
		"builder": func(c: int, r: int) -> Node3D:
			var rig := PlayerRig.new()
			rig.rotation.y = PlayerRig.direction_yaw(r)
			rig.pose_column(c)
			return rig,
		"cols": PlayerRig.column_count(),
		"rows": PlayerRig.DIRECTIONS,
		# Cell is centred on the feet, so its half-height must exceed the projected head height
		# (~2.05 m * cos(pitch)); 2.7 m clipped the top of the head.
		"cell": Vector2(2.7, 4.2),
		"albedo_setup": func(insts: Array[Node3D]) -> void:
			for i in insts:
				(i as PlayerRig).set_lantern(false),
		"emission": {
			"default": func(insts: Array[Node3D]) -> void:
				for i in insts:
					(i as PlayerRig).set_lantern(true),
		},
	}


## Switch to the baked sprite (or back to the 3D model with null).
## The 3D rig stays as a shadow-only caster so the shadow keeps animating.
func use_sprite_sheet(sheet: SpriteSheet) -> void:
	if sheet == null:
		if sprite:
			sprite.queue_free()
			sprite = null
		_set_rig_visible(true)
		return
	if sprite == null:
		sprite = BakedSprite.new()
		sprite.name = "Sprite"
		sprite.anchor = self
		sprite.set_silhouette_color(Color(1.0, 0.95, 0.8, 0.4))
		# Own layer only: the hip lantern sits practically inside the body and turned the
		# sprite into speckle at night; it still lights the surroundings.
		sprite.layers = SELF_LAYER
		add_child(sprite)
	sprite.set_sheet(sheet)
	sprite.set_silhouette(silhouette_enabled)
	_set_rig_visible(false)


func _set_rig_visible(on: bool) -> void:
	for i in _meshes.size():
		var mi := _meshes[i]
		var orig: int = _mesh_shadow_modes[i]
		if orig == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			mi.visible = on  # non-casting parts (lantern glass) simply disappear
		else:
			mi.cast_shadow = orig if on else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	set_silhouette(silhouette_enabled)


## "X-ray" pass: draws the character only where something else covers it.
func _setup_silhouette(color: Color) -> void:
	_silhouette_mat = ShaderMaterial.new()
	_silhouette_mat.shader = preload("res://shaders/occluded_silhouette.gdshader")
	_silhouette_mat.set_shader_parameter("color", color)
	_silhouette_mat.render_priority = 1
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.layers = 1 | SELF_LAYER
		var m := m3.material_override.duplicate() as StandardMaterial3D
		m3.material_override = m
		_mesh_materials.append(m)
		_meshes.append(m3)
		_mesh_shadow_modes.append(m3.cast_shadow)
	set_silhouette(silhouette_enabled)


func set_silhouette(on: bool) -> void:
	silhouette_enabled = on
	var rig_sil := on and sprite == null
	for m in _mesh_materials:
		m.next_pass = _silhouette_mat if rig_sil else null
	if sprite:
		sprite.set_silhouette(on)


func _physics_process(delta: float) -> void:
	var input := scripted_move
	var running := scripted_running
	if input == Vector2.ZERO:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		running = Input.is_action_pressed("run")
	var dir := Vector3(input.x, 0.0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var speed := RUN_SPEED if running else WALK_SPEED
	velocity = dir * speed
	move_and_slide()
	global_position.x = clampf(global_position.x, walk_bounds.position.x, walk_bounds.end.x)
	global_position.z = clampf(global_position.z, walk_bounds.position.y, walk_bounds.end.y)
	if height_func.is_valid():
		global_position.y = height_func.call(global_position.x, global_position.z)
	_speed_now = Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if dir.length() > 0.05 and _attack_t < 0.0:
		_turn_towards(atan2(-dir.x, -dir.z), delta)


func _turn_towards(target_yaw: float, delta: float) -> void:
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-TURN_SHARPNESS * delta))
	model.rotation.y = _yaw


## One swing towards the mouse cursor (or current facing if no cursor hit).
func start_attack(aim_world: Variant = null) -> void:
	if _attack_t >= 0.0:
		return
	if aim_world == null and Game.view:
		aim_world = Game.view.mouse_on_plane(global_position.y + 0.9)
	if aim_world is Vector3:
		var d: Vector3 = aim_world - global_position
		if Vector2(d.x, d.z).length() > 0.1:
			_yaw = atan2(-d.x, -d.z)
			model.rotation.y = _yaw
	_attack_t = 0.0


func _process(delta: float) -> void:
	# The world lives in a SubViewport that gets no input events, so poll Input directly.
	# Click = exactly one swing; holding the button does not repeat (GDD 4.1).
	if Input.is_action_just_pressed("attack"):
		start_attack()
	var on := Game.lantern_on
	if _lantern_state != on:
		_lantern_state = on
		lantern_light.visible = on
		model.set_lantern(on)
	_animate(delta)


func _animate(delta: float) -> void:
	var moving := _speed_now > 0.2
	if moving:
		_walk_phase += delta * _speed_now * 2.6
	else:
		_walk_phase = lerpf(_walk_phase, roundf(_walk_phase / PI) * PI, 1.0 - exp(-10.0 * delta))
	if _attack_t >= 0.0:
		_attack_t += delta
		if _attack_t >= PlayerRig.ATTACK_TIME + 0.08:
			_attack_t = -1.0
	model.pose(_walk_phase, 1.0 if moving else 0.0, _attack_t)
	if sprite:
		_update_sprite_frame(moving)


func _update_sprite_frame(moving: bool) -> void:
	var col: int
	if _attack_t >= 0.0:
		var n: int = PlayerRig.ANIMS[2][1]
		col = PlayerRig.column_for("attack", int(clampf(_attack_t / PlayerRig.ATTACK_TIME, 0.0, 1.0) * (n - 1) + 0.5))
	elif moving:
		var n: int = PlayerRig.ANIMS[1][1]
		col = PlayerRig.column_for("walk", int(fposmod(_walk_phase, TAU) / TAU * n) % n)
	else:
		col = PlayerRig.column_for("idle", int(Time.get_ticks_msec() / 600) % 2)
	sprite.set_frame(col, PlayerRig.direction_index(_yaw))
	sprite.set_emission("default", 1.0 if Game.lantern_on else 0.0)


func face_direction(yaw: float) -> void:
	_yaw = yaw
	model.rotation.y = yaw
