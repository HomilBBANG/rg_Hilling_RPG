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
## Equipment swap action (GDD 6.5 [확정]: put the old piece away, take the new one out; it applies
## when the motion ends). Length, slow walking allowed, no attacks, not cancelled by hits [미정].
const SWAP_TIME := 0.6
const SWAP_MOVE_FACTOR := 0.6

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
var _running := false  # running this frame (Shift with SP, moving): middle-aged trot
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
## Consumable / spell in progress: {"kind": "item"|"spell", "id", "t", "time", "move", "anim", "label"}.
var _use := {}
var _swap_t := -1.0
var _swap_action: Callable
var _swap_done_text := ""
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
	model.set_gear(Game.player_state.visual_gear())
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


## Bake request for SpriteBaker: every animation column x 8 facing directions, with the given
## visible gear (weapon / shield / belt lantern). One sheet per gear combination (cached by name).
static func sprite_bake_spec(g := {"main": "iron_sword", "off": "", "lantern": true}) -> Dictionary:
	return {
		"builder": func(c: int, r: int) -> Node3D:
			var rig := PlayerRig.new()
			rig.set_gear(g)
			rig.rotation.y = PlayerRig.direction_yaw(r)
			rig.pose_column(c)
			return rig,
		"cols": PlayerRig.column_count(),
		"rows": PlayerRig.DIRECTIONS,
		# Cell is centred on the feet, so its half-height must exceed the projected head height
		# (~2.05 m * cos(pitch)); 2.7 m clipped the top of the head.
		# Wider than the body: the weapon sweeps to either side during the swing.
		"cell": Vector2(PlayerRig.cell_width(g), 4.2),
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
	var typing := get_viewport().gui_get_focus_owner() is LineEdit  # naming the camper etc.
	if input == Vector2.ZERO and controls_enabled and not dead and not typing:
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
	_running = run_now
	var speed := (RUN_SPEED if run_now else WALK_SPEED) * st.speed_factor()
	if is_swapping():
		speed *= SWAP_MOVE_FACTOR
	if is_using():
		speed *= _use["move"]
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
		if is_using():
			cancel_use("피격")
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


## Extra push from a heavy blow (the dragon's tail / dive), on top of the usual hit knockback.
func shove(v: Vector3) -> void:
	_knock += Vector3(v.x, 0.0, v.z)


func _on_died() -> void:
	if dead or not is_inside_tree():
		return
	dead = true
	_attack_t = -1.0
	_use = {}
	if Game.boot:
		Game.boot.on_player_died(global_position)


## Dialogue / cutscene lock: no movement, attacks or interaction until it ends. The camera is
## untouched. On release a short block stops the key that closed the dialogue from re-opening it.
func set_talking(on: bool) -> void:
	controls_enabled = not on
	scripted_move = Vector2.ZERO
	_interact_block = 0.3
	if on:
		cancel_use("대화")
		focus = null


## Hide/show while sitting in the camper's driver seat.
func set_driving(on: bool) -> void:
	_use = {}
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
	if is_swapping():
		_toast("장비 교체 중에는 공격할 수 없다")
		return
	if is_using():
		_toast("%s 중에는 공격할 수 없다" % _use["label"])
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
	if is_using():
		_use["t"] += delta
		if _use["t"] >= _use["time"]:
			_finish_use()
	if _swap_t >= 0.0:
		_swap_t += delta
		if _swap_t >= SWAP_TIME:
			_finish_swap()
	if controls_enabled and not dead:
		if Input.is_action_just_pressed("attack") and not (Game.hud and Game.hud.blocks_mouse()):
			start_attack()
		_update_focus()
		for i in PlayerState.QUICK_ITEM_SLOTS:
			if Input.is_action_just_pressed("quick_item_%d" % (i + 1)):
				use_quick_item(i)
		for i in PlayerState.QUICK_SKILL_SLOTS:
			if Input.is_action_just_pressed("quick_skill_%d" % (i + 1)):
				use_quick_skill(i)
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
	if _running and moving and _attack_t < 0.0 and not is_using():
		model.pose_run(_walk_phase)
	if is_using():
		model.pose_action(_use["anim"], use_frame())
	if sprite:
		_update_sprite_frame(moving)


func _update_sprite_frame(moving: bool) -> void:
	var col: int
	if is_using():
		col = PlayerRig.column_for(_use["anim"], use_frame())
	elif _attack_t >= 0.0:
		var n: int = PlayerRig.ANIMS[2][1]
		col = PlayerRig.column_for("attack", int(clampf(_attack_t / PlayerRig.ATTACK_TIME, 0.0, 1.0) * (n - 1) + 0.5))
	elif moving and _running:
		var nr: int = PlayerRig.ANIMS[6][1]
		col = PlayerRig.column_for("run", int(fposmod(_walk_phase, TAU) / TAU * nr) % nr)
	elif moving:
		var n: int = PlayerRig.ANIMS[1][1]
		col = PlayerRig.column_for("walk", int(fposmod(_walk_phase, TAU) / TAU * n) % n)
	else:
		col = PlayerRig.column_for("idle", 0)
	sprite.set_frame(col, PlayerRig.direction_index(_yaw))
	sprite.set_emission("default", 1.0 if Game.lantern_on else 0.0)
	# Hurt: red flash. Swapping gear: soft pale pulse.
	if _flash > 0.01 or not is_swapping():
		sprite.set_flash(Color(1.0, 0.25, 0.2, _flash * 0.7))
	else:
		sprite.set_flash(Color(0.75, 0.88, 1.0, 0.18 + 0.12 * sin(_swap_t * 25.0)))


# ---------------------------------------------------------------- consumables & spells (GDD 6.4, 5.3)

func is_using() -> bool:
	return not _use.is_empty()


func use_frame() -> int:
	return int(_use.get("t", 0.0) * 4.0) % 2


func use_progress() -> float:
	return clampf(_use["t"] / _use["time"], 0.0, 1.0) if is_using() else 0.0


func use_label() -> String:
	return _use.get("label", "")


func _can_start_action() -> bool:
	return not dead and controls_enabled and not is_swapping() and not is_using() and _attack_t < 0.0


func use_quick_item(slot: int) -> void:
	var id: String = Game.player_state.quick_items[slot]
	if id == "":
		_toast("소모품 퀵슬롯 %d이 비어 있다 (Tab에서 등록)" % (slot + 1))
		return
	begin_use_item(id)


func use_quick_skill(slot: int) -> void:
	var id: String = Game.player_state.quick_skills[slot]
	if id == "":
		_toast("스킬·마법 퀵슬롯 %d이 비어 있다 (C에서 등록)" % (slot + 5))
		return
	begin_cast(id)


## Starts the common use motion of the item's kind; it is applied and consumed when it ends.
func begin_use_item(id: String) -> bool:
	var st := Game.player_state
	if not ItemDB.is_consumable(id) or st.inventory.count(id) <= 0:
		_toast("%s이(가) 없다" % ItemDB.item_name(id))
		return false
	if not _can_start_action():
		_toast("지금은 사용할 수 없다")
		return false
	var info := ItemDB.info(id)
	var learn: String = info["effect"].get("learn", "")
	if learn != "" and learn in st.spells:
		_toast("이미 배운 마법이다")
		return false
	var kind: Dictionary = ItemDB.USE_TYPES[info["use"]]
	_use = {"kind": "item", "id": id, "t": 0.0, "time": kind["time"], "move": kind["move"], "anim": kind["anim"],
		"label": "%s %s" % [info["name"], kind["name"]]}
	_float_status(_use["label"] + "…")
	return true


## Spells come only from the skill/magic quickslots (GDD 5.3); MP/SP are paid when the cast ends.
func begin_cast(id: String) -> bool:
	var st := Game.player_state
	var sp_info: Dictionary = ItemDB.SPELLS[id]
	if st.cooldowns.get(id, 0.0) > 0.0:
		_toast("%s 재사용 대기 %.1f초" % [sp_info["name"], st.cooldowns[id]])
		return false
	if st.mp < sp_info["mp"] or st.sp < sp_info["sp"]:
		_toast("MP가 부족하다" if st.mp < sp_info["mp"] else "SP가 부족하다")
		return false
	if not _can_start_action():
		_toast("지금은 시전할 수 없다")
		return false
	_use = {"kind": "spell", "id": id, "t": 0.0, "time": sp_info["time"], "move": sp_info["move"],
		"anim": sp_info["anim"], "label": "%s 시전" % sp_info["name"]}
	_float_status(_use["label"] + "…")
	return true


## Generic timed action for life activities (gathering, fishing): the same motion rules as using an
## item (GDD 6.4 style) - a hit cancels it and nothing is gained. on_done runs when it completes.
func begin_task(label: String, time: float, move: float, anim: String, on_done: Callable, on_cancel := Callable()) -> bool:
	if not _can_start_action():
		_toast("지금은 할 수 없다")
		return false
	_use = {"kind": "task", "t": 0.0, "time": time, "move": move, "anim": anim, "label": label,
		"done": on_done, "cancel": on_cancel}
	return true


## Ends a long task without a message (the fishing session decides when it is over).
func end_task() -> void:
	if is_using() and _use["kind"] == "task":
		_use = {}


func cancel_use(reason: String) -> void:
	if not is_using():
		return
	var label: String = _use["label"]
	var item: bool = _use["kind"] == "item"
	var task: bool = _use["kind"] == "task"
	var on_cancel: Callable = _use.get("cancel", Callable())
	_use = {}
	if on_cancel.is_valid():
		on_cancel.call(reason)
	var msg := "%s 중단(%s) — %s%s" % [label, reason, "아무것도 얻지 못했다" if task else "효과 없음", ", 아이템 유지" if item else ""]
	Game.combat_log.add(msg, "", "info")
	if Game.boot:
		Game.boot.hud.toast(msg)


func _finish_use() -> void:
	var st := Game.player_state
	var u := _use
	_use = {}
	var summary := ""
	if u["kind"] == "task":
		(u["done"] as Callable).call()
		return
	if u["kind"] == "item":
		if st.inventory.remove(u["id"], 1) <= 0:
			return
		summary = st.apply_effect(ItemDB.info(u["id"])["effect"])
		Game.combat_log.add("%s 사용 — %s" % [ItemDB.item_name(u["id"]), summary], "", "info")
	else:
		var sp_info: Dictionary = ItemDB.SPELLS[u["id"]]
		if st.mp < sp_info["mp"] or st.sp < sp_info["sp"]:
			cancel_use("자원 부족")
			return
		st.mp -= sp_info["mp"]
		st.sp -= sp_info["sp"]
		st.cooldowns[u["id"]] = sp_info["cooldown"]
		summary = st.apply_effect(sp_info["effect"])
		Game.combat_log.add("%s 시전 — %s (MP -%d)" % [sp_info["name"], summary, sp_info["mp"]], "", "info")
	_float_status(summary, Color(0.6, 1.0, 0.65))


func _float_status(text: String, color := Color(0.75, 0.88, 1.0)) -> void:
	if Game.hud:
		Game.hud.float_text(global_position + Vector3(0, 2.0, 0), text, color)


func is_swapping() -> bool:
	return _swap_t >= 0.0


## Starts the swap motion; `action` (the actual equip / unequip) runs when it ends.
func begin_gear_change(action: Callable, done_text: String) -> bool:
	if is_swapping() or is_using() or dead:
		return false
	_swap_t = 0.0
	_swap_action = action
	_swap_done_text = done_text
	_attack_t = -1.0
	if Game.hud:
		Game.hud.float_text(global_position + Vector3(0, 2.0, 0), "장비 교체…", Color(0.75, 0.88, 1.0))
	return true


func _finish_swap() -> void:
	_swap_t = -1.0
	if _swap_action.is_valid():
		_swap_action.call()
	apply_gear()
	if Game.boot and _swap_done_text != "":
		Game.boot.hud.toast(_swap_done_text)


## Model, shadow caster and sprite sheet follow the equipped weapon / shield / lantern belt.
func apply_gear() -> void:
	var g := Game.player_state.visual_gear()
	if PlayerState.gear_key(g) == PlayerState.gear_key(model.gear):
		return
	model.set_gear(g)
	# New meshes (weapon, shield) get the same treatment as the rest of the rig.
	for i in range(_meshes.size() - 1, -1, -1):
		if not is_instance_valid(_meshes[i]):
			_meshes.remove_at(i)
			_mesh_materials.remove_at(i)
			_mesh_shadow_modes.remove_at(i)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3 in _meshes:
			continue
		m3.layers = 1 | SELF_LAYER
		var m := m3.material_override.duplicate() as StandardMaterial3D
		m3.material_override = m
		_mesh_materials.append(m)
		_meshes.append(m3)
		_mesh_shadow_modes.append(m3.cast_shadow)
	_set_rig_visible(sprite == null)
	if not Game.player_state.has_lantern():
		Game.lantern_on = false
	Game.sprites_dirty = true


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


func facing_yaw() -> float:
	return _yaw
