class_name PrototypePlayer
extends CharacterBody3D
## Player: WASD walking/running (SP), one mouse-aimed swing per click whose weapon area must touch
## a monster before the TRPG roll (GDD 4.1/6.2), E/R interaction with the nearest target,
## hit reaction and death hand-off. Stats/bag live in Game.player_state.
## Visual: PlayerRig 3D model, optionally replaced on screen by its baked pixel sprite.

const WALK_SPEED := 3.6
const RUN_SPEED := 6.0
const TURN_SHARPNESS := 14.0
## Extra visual layer for the player's own meshes (excluded from the lantern's shadow casters).
const SELF_LAYER := 1 << 19
## Physics layer 2: the player's body (monsters query it for contact, nothing collides with it).
const BODY_LAYER := 1 << 1
## Weapon contact window inside the swing and reach of the swept area [미정 assumptions].
const HIT_WINDOW := Vector2(0.05, 0.24)
const WEAPON_REACH := 0.8
const WEAPON_RADIUS := 0.62
const HURT_INVULN := 0.5

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
var _swing_hits: Array[Node] = []
var _aim_dir := Vector3.FORWARD
var _winded := false
var _invuln := 0.0
var _flash := 0.0
var _knock := Vector3.ZERO
var _toast_cd := 0.0
## Nearest interactable in range (shown by the HUD, E / R act on it).
var focus: Node3D
var dead := false
## Ignore E/R briefly after getting out of the camper (the same key press must not re-enter).
var _interact_block := 0.0
## False while driving / in cutscenes: no input, hidden from monsters.
var controls_enabled := true


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = BODY_LAYER
	collision_mask = 1
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
	Game.player_state.died.connect(_on_died)


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
		# Wider than the body: the sword sweeps about 1.3 m to either side during the swing.
		"cell": Vector2(3.3, 4.2),
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
	if sprite.sheet != sheet:
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
	if not visible:
		return
	var st := Game.player_state
	var input := scripted_move
	var running := scripted_running
	if input == Vector2.ZERO and controls_enabled and not dead:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		running = Input.is_action_pressed("run")
	var dir := Vector3(input.x, 0.0, input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	# Walking costs no SP; running drains it (GDD 4.2 [확정]). Out of SP: walk until 25 % back.
	if _winded and st.sp >= st.max_sp() * 0.25:
		_winded = false
	if running and dir.length() > 0.05 and not _winded:
		if not st.drain_sp(PlayerState.RUN_SP_PER_SEC * delta):
			_winded = true
	var run_now := running and not _winded and dir.length() > 0.05
	var speed := (RUN_SPEED if run_now else WALK_SPEED) * st.speed_factor()
	velocity = dir * speed + _knock
	_knock = _knock.move_toward(Vector3.ZERO, delta * 20.0)
	move_and_slide()
	global_position.x = clampf(global_position.x, walk_bounds.position.x, walk_bounds.end.x)
	global_position.z = clampf(global_position.z, walk_bounds.position.y, walk_bounds.end.y)
	if height_func.is_valid():
		global_position.y = height_func.call(global_position.x, global_position.z)
	_speed_now = Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if dir.length() > 0.05 and _attack_t < 0.0:
		_turn_towards(atan2(-dir.x, -dir.z), delta)
	if _attack_t >= HIT_WINDOW.x and _attack_t <= HIT_WINDOW.y:
		_weapon_contact()


## Swept weapon area in front of the player during the swing; each monster at most once per swing.
func _weapon_contact() -> void:
	var params := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = WEAPON_RADIUS
	params.shape = sph
	params.transform = Transform3D(Basis(), global_position + _aim_dir * WEAPON_REACH + Vector3(0, 0.45, 0))
	params.collision_mask = SlimeMonster.LAYER
	for h in get_world_3d().direct_space_state.intersect_shape(params, 8):
		var c: Object = h["collider"]
		if c in _swing_hits or not c.has_method("receive_attack"):
			continue
		_swing_hits.append(c)
		c.receive_attack(Game.player_state.combat_profile(), self)


func is_targetable() -> bool:
	return visible and not dead and controls_enabled


## Monster attack that physically touched the body: TRPG roll against the player.
func receive_attack(attacker_profile: Dictionary, from: Node3D) -> void:
	if not is_targetable() or _invuln > 0.0:
		return
	var st := Game.player_state
	var res := Combat.resolve(attacker_profile, st.combat_profile())
	var top := global_position + Vector3(0, 1.9, 0)
	if res["hit"]:
		res["detail"] += " · 주인공 HP %d/%d" % [maxi(0, int(st.hp) - res["damage"]), int(st.max_hp())]
		Game.combat_log.add(Combat.short_text(res), res["detail"], "hurt")
		if Game.hud:
			Game.hud.float_text(top, "-%d" % res["damage"], Color(1.0, 0.35, 0.3), res["crit"])
		_invuln = HURT_INVULN
		_flash = 1.0
		var away := global_position - from.global_position
		away.y = 0.0
		_knock = away.normalized() * 3.5
		st.take_damage(res["damage"])
	else:
		Game.combat_log.add(Combat.short_text(res), res["detail"], "miss")
		if Game.hud:
			Game.hud.float_text(top, "회피", Color(0.75, 0.78, 0.82))


func _on_died() -> void:
	if dead or not is_inside_tree():
		return
	dead = true
	_attack_t = -1.0
	if Game.boot:
		Game.boot.on_player_died(global_position)


## Hide/show while sitting in the camper's driver seat.
func set_driving(on: bool) -> void:
	controls_enabled = not on
	visible = not on
	_interact_block = 0.3
	process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	focus = null


func _turn_towards(target_yaw: float, delta: float) -> void:
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-TURN_SHARPNESS * delta))
	model.rotation.y = _yaw


## One swing towards the mouse cursor (or current facing if no cursor hit).
func start_attack(aim_world: Variant = null) -> void:
	if _attack_t >= 0.0 or dead:
		return
	if not Game.player_state.spend_sp(PlayerState.ATTACK_SP):
		_toast("SP가 부족하다")
		return
	if aim_world == null and Game.view:
		aim_world = Game.view.mouse_on_plane(global_position.y + 0.9)
	if aim_world is Vector3:
		var d: Vector3 = aim_world - global_position
		if Vector2(d.x, d.z).length() > 0.1:
			_yaw = atan2(-d.x, -d.z)
			model.rotation.y = _yaw
	_aim_dir = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	_swing_hits.clear()
	_attack_t = 0.0


func _toast(msg: String) -> void:
	if _toast_cd <= 0.0 and Game.boot:
		Game.boot.hud.toast(msg)
		_toast_cd = 1.0


func _process(delta: float) -> void:
	# The world lives in a SubViewport that gets no input events, so poll Input directly.
	# Click = exactly one swing; holding the button does not repeat (GDD 4.1).
	_toast_cd -= delta
	_invuln = maxf(0.0, _invuln - delta)
	_flash = maxf(0.0, _flash - delta * 5.0)
	_interact_block -= delta
	if controls_enabled and not dead:
		if Input.is_action_just_pressed("attack") and not (Game.hud and Game.hud.blocks_mouse()):
			start_attack()
		_update_focus()
		if _interact_block > 0.0:
			pass
		elif focus and Input.is_action_just_pressed("interact"):
			focus.interact(self)
		elif focus and Input.is_action_just_pressed("interact_alt") and focus.has_method("interact_alt"):
			focus.interact_alt(self)
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
		col = PlayerRig.column_for("idle", 0)
	sprite.set_frame(col, PlayerRig.direction_index(_yaw))
	sprite.set_emission("default", 1.0 if Game.lantern_on else 0.0)
	# Hurt: red flash; invulnerable time blinks slightly.
	sprite.set_flash(Color(1.0, 0.25, 0.2, _flash * 0.7))


func _update_focus() -> void:
	var world := get_parent()
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		var n3 := n as Node3D
		if n3 == null or not world.is_ancestor_of(n3):
			continue
		if n3.has_method("can_interact") and not n3.can_interact():
			continue
		var d := Vector2(n3.global_position.x - global_position.x, n3.global_position.z - global_position.z).length()
		if d < n3.get("interact_range") and d < best_d:
			best_d = d
			best = n3
	focus = best


func face_direction(yaw: float) -> void:
	_yaw = yaw
	model.rotation.y = yaw
