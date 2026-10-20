class_name PrototypePlayer
extends CharacterBody3D
## P0 visual-test player: procedural low-poly person, WASD walking, one swing motion,
## belt lantern. No stats/combat logic (that is P1).

const WALK_SPEED := 3.6
const RUN_SPEED := 6.0
const TURN_SHARPNESS := 14.0
const ATTACK_TIME := 0.32
## Extra visual layer for the player's own meshes (excluded from the lantern's shadow casters).
const SELF_LAYER := 1 << 19

## Callable(x: float, z: float) -> float giving ground height. Set by the world.
var height_func: Callable
## Optional bounds clamp (x/z rect) set by the world.
var walk_bounds := Rect2(-1000, -1000, 2000, 2000)
## Scripted movement for automated capture tours (Vector2.ZERO = use keyboard).
var scripted_move := Vector2.ZERO
var scripted_running := false

var model: Node3D
var lantern_light: OmniLight3D
var silhouette_enabled := true

var _hips: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _lantern_glass: MeshInstance3D
var _glass_on: Material
var _glass_off: Material
var _silhouette_mat: ShaderMaterial
var _mesh_materials: Array[StandardMaterial3D] = []
var _walk_phase := 0.0
var _yaw := 0.0
var _attack_t := -1.0
var _speed_now := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)
	_build_model()
	add_to_group("player")


func _build_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)

	var skin := ProtoMesh.mat(Color(0.93, 0.74, 0.6))
	var hair := ProtoMesh.mat(Color(0.22, 0.14, 0.09))
	var jacket := ProtoMesh.mat(Color(0.78, 0.33, 0.2))
	var shirt := ProtoMesh.mat(Color(0.93, 0.89, 0.78))
	var pants := ProtoMesh.mat(Color(0.2, 0.24, 0.38))
	var shoes := ProtoMesh.mat(Color(0.16, 0.12, 0.1))
	var leather := ProtoMesh.mat(Color(0.42, 0.27, 0.15))
	var pack := ProtoMesh.mat(Color(0.36, 0.42, 0.26))
	var steel := ProtoMesh.mat(Color(0.78, 0.8, 0.84), 0.35)
	var dark := ProtoMesh.mat(Color(0.08, 0.07, 0.07))

	_hips = Node3D.new()
	_hips.position.y = 0.86
	model.add_child(_hips)

	# Legs
	_leg_l = _limb(_hips, Vector3(-0.12, 0.0, 0.0))
	_leg_r = _limb(_hips, Vector3(0.12, 0.0, 0.0))
	for leg: Node3D in [_leg_l, _leg_r]:
		ProtoMesh.capsule(leg, 0.11, 0.78, Vector3(0, -0.39, 0), pants)
		ProtoMesh.box(leg, Vector3(0.18, 0.1, 0.3), Vector3(0, -0.8, -0.05), shoes)

	# Torso (jacket over shirt, belt, backpack)
	ProtoMesh.box(_hips, Vector3(0.48, 0.56, 0.3), Vector3(0, 0.3, 0), jacket)
	ProtoMesh.box(_hips, Vector3(0.2, 0.4, 0.04), Vector3(0, 0.34, -0.15), shirt)
	ProtoMesh.box(_hips, Vector3(0.5, 0.08, 0.32), Vector3(0, 0.03, 0), leather)
	ProtoMesh.box(_hips, Vector3(0.38, 0.44, 0.2), Vector3(0, 0.32, 0.24), pack)
	ProtoMesh.box(_hips, Vector3(0.42, 0.1, 0.22), Vector3(0, 0.58, 0.24), leather)

	# Head
	ProtoMesh.box(_hips, Vector3(0.14, 0.08, 0.14), Vector3(0, 0.62, 0), skin)
	ProtoMesh.sphere(_hips, 0.2, Vector3(0, 0.8, 0), skin)
	ProtoMesh.sphere(_hips, 0.215, Vector3(0, 0.86, 0.04), hair, Vector3(1.0, 0.8, 1.0))
	ProtoMesh.box(_hips, Vector3(0.05, 0.06, 0.03), Vector3(-0.075, 0.8, -0.185), dark)
	ProtoMesh.box(_hips, Vector3(0.05, 0.06, 0.03), Vector3(0.075, 0.8, -0.185), dark)

	# Arms
	_arm_l = _limb(_hips, Vector3(-0.31, 0.52, 0.0))
	_arm_r = _limb(_hips, Vector3(0.31, 0.52, 0.0))
	for arm: Node3D in [_arm_l, _arm_r]:
		ProtoMesh.capsule(arm, 0.08, 0.58, Vector3(0, -0.26, 0), jacket)
		ProtoMesh.sphere(arm, 0.085, Vector3(0, -0.56, 0), skin)
	# Placeholder iron sword in right hand (blade continues the arm line).
	ProtoMesh.box(_arm_r, Vector3(0.05, 0.16, 0.05), Vector3(0, -0.64, 0), leather)
	ProtoMesh.box(_arm_r, Vector3(0.22, 0.04, 0.06), Vector3(0, -0.72, 0), steel)
	ProtoMesh.box(_arm_r, Vector3(0.07, 0.62, 0.02), Vector3(0, -1.04, 0), steel)

	# Belt lantern on the left hip (GDD 10.3: 허리띠에 끼우는 등불)
	var lantern := Node3D.new()
	lantern.position = Vector3(-0.3, 0.0, -0.06)
	_hips.add_child(lantern)
	ProtoMesh.box(lantern, Vector3(0.12, 0.03, 0.12), Vector3(0, 0.08, 0), dark)
	ProtoMesh.box(lantern, Vector3(0.12, 0.03, 0.12), Vector3(0, -0.1, 0), dark)
	_glass_off = ProtoMesh.mat(Color(0.55, 0.5, 0.35), 0.4)
	_glass_on = ProtoMesh.mat(Color(1.0, 0.85, 0.5), 0.4, Color(1.0, 0.7, 0.3), 3.0)
	_lantern_glass = ProtoMesh.box(lantern, Vector3(0.1, 0.15, 0.1), Vector3(0, -0.01, 0), _glass_off)
	_lantern_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	lantern_light.visible = false
	lantern.add_child(lantern_light)

	_setup_silhouette(Color(1.0, 0.95, 0.8, 0.4))


func _limb(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## "X-ray" pass: draws the character only where something else covers it.
func _setup_silhouette(color: Color) -> void:
	_silhouette_mat = ShaderMaterial.new()
	_silhouette_mat.shader = preload("res://shaders/occluded_silhouette.gdshader")
	_silhouette_mat.set_shader_parameter("color", color)
	_silhouette_mat.render_priority = 1
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1 | SELF_LAYER
		var m := (mi as MeshInstance3D).material_override.duplicate() as StandardMaterial3D
		(mi as MeshInstance3D).material_override = m
		_mesh_materials.append(m)
	set_silhouette(silhouette_enabled)


func set_silhouette(on: bool) -> void:
	silhouette_enabled = on
	for m in _mesh_materials:
		m.next_pass = _silhouette_mat if on else null


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
	if lantern_light.visible != on:
		lantern_light.visible = on
		_lantern_glass.material_override = _glass_on if on else _glass_off
	_animate(delta)


func _animate(delta: float) -> void:
	var moving := _speed_now > 0.2
	if moving:
		_walk_phase += delta * _speed_now * 2.6
	else:
		_walk_phase = lerpf(_walk_phase, roundf(_walk_phase / PI) * PI, 1.0 - exp(-10.0 * delta))
	var swing := sin(_walk_phase) * (0.65 if moving else 0.0)
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	_arm_l.rotation.x = -swing * 0.7
	_arm_r.rotation = Vector3(swing * 0.5 + 0.25, 0.0, 0.0)
	_hips.position.y = 0.86 + absf(sin(_walk_phase)) * (0.05 if moving else 0.0)

	if _attack_t >= 0.0:
		_attack_t += delta
		var t := clampf(_attack_t / ATTACK_TIME, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - t, 3.0)
		# Horizontal slash: arm raised forward, sweeping right -> left.
		_arm_r.rotation = Vector3(deg_to_rad(80.0), deg_to_rad(lerpf(75.0, -80.0, e)), 0.0)
		_hips.rotation.y = deg_to_rad(lerpf(20.0, -15.0, e))
		if _attack_t >= ATTACK_TIME + 0.08:
			_attack_t = -1.0
			_hips.rotation.y = 0.0


func face_direction(yaw: float) -> void:
	_yaw = yaw
	model.rotation.y = yaw
