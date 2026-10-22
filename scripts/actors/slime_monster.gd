class_name SlimeMonster
extends CharacterBody3D
## P1 basic monster (GDD 7.1 일반 몬스터: approach + basic attack only).
## Hops around its home; 선공(aggressive) slimes engage a player who comes close, passive ones
## only fight back. An engaged slime calls same-species slimes nearby into the fight (GDD 7.2),
## gives up past its leash distance or when the player is inside a safe checkpoint (7.3).
## Attack = a lunge hop; damage only if its body physically touches the player (6.2).
## Ranges, timings and stats are [미정] prototype values (notes/IMPLEMENTATION_ASSUMPTIONS.md).

enum State { WANDER, CHASE, ATTACK, HURT, RETURN, DEAD }

const LAYER := 1 << 2  # physics layer 3: monsters
const RADIUS := 0.42
const SPECIES := &"slime"
const NIGHT_AGGRO_MULT := 1.4  # night is a bit more dangerous (GDD 10.2)

var monster_id := ""
## Monster definition (data/monsters.json): name, 선공 flag, HP, EXP, combat profile, colours, loot.
var kind := "meadow_slime"
## Body size from the kind (boss slimes are big): collision, contact and lunge reach scale with it.
var body_scale := 1.0
var display_name := "슬라임"
var aggressive := false
var home := Vector3.ZERO
var wander_radius := 3.5
var aggro_radius := 6.0
var join_radius := 8.0
var leash := 14.0
var max_hp := 9
var hp := 9
var exp_reward := 6  ## general EXP for the kill [미정]
var profile := {"name": "슬라임", "hit_bonus": 2, "crit_chance": 5, "phys": "1d4", "str_mult": 1.0,
	"ac": 9, "armor": 0}
var height_func: Callable
var world: Node
var state := State.WANDER
var sprite: BakedSprite

var _rig: SlimeRig
var _meshes: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _silhouette_mat: ShaderMaterial
var _silhouette_on := true
var _rng := RandomNumberGenerator.new()
var _hop_t := 0.0
var _hop_time := 1.1
var _hop_vel := Vector3.ZERO
var _hop_rest := false
var _yaw := 0.0
var _hurt_t := 0.0
var _knock := Vector3.ZERO
var _flash := 0.0
var _attack_done := false
var _cooldown := 0.0


func _ready() -> void:
	_rng.seed = hash(monster_id) if monster_id != "" else randi()
	var def := MonsterDB.info(kind)
	display_name = str(def.get("name", display_name))
	aggressive = bool(def.get("aggressive", aggressive))
	max_hp = int(def.get("hp", max_hp))
	exp_reward = int(def.get("exp", exp_reward))
	profile = profile.merged(def.get("profile", {}), true)
	profile["name"] = display_name
	body_scale = float(def.get("scale", 1.0))
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = LAYER
	collision_mask = PhysLayers.MONSTER_MASK
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = RADIUS * body_scale
	shape.shape = sph
	shape.position.y = RADIUS * body_scale
	add_child(shape)
	_rig = SlimeRig.new(def.get("colors", null), float(def.get("scale", 1.0)))
	add_child(_rig)
	_setup_silhouette(Color(1.0, 0.35, 0.3, 0.45))
	hp = max_hp
	home = Vector3(global_position.x, 0.0, global_position.z)
	_yaw = _rng.randf() * TAU
	_start_hop(Vector3.ZERO, 1.1)
	add_to_group("enemies")


static func sprite_bake_spec(kind_id := "meadow_slime") -> Dictionary:
	var def := MonsterDB.info(kind_id)
	return SlimeVisual.sprite_bake_spec(def.get("colors", null), float(def.get("scale", 1.0)))


func use_sprite_sheet(sheet: SpriteSheet) -> void:
	if sheet == null:
		if sprite:
			sprite.queue_free()
			sprite = null
	else:
		if sprite == null:
			sprite = BakedSprite.new()
			sprite.anchor = self
			sprite.set_silhouette_color(Color(1.0, 0.35, 0.3, 0.45), 1.0)
			add_child(sprite)
		if sprite.sheet != sheet:
			sprite.set_sheet(sheet)
	for mi in _meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if sprite else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	set_silhouette(_silhouette_on)


func _setup_silhouette(color: Color) -> void:
	_silhouette_mat = ShaderMaterial.new()
	_silhouette_mat.shader = preload("res://shaders/occluded_silhouette.gdshader")
	_silhouette_mat.set_shader_parameter("color", color)
	_silhouette_mat.set_shader_parameter("self_bias", 1.0)
	_silhouette_mat.render_priority = 1
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override.duplicate() as StandardMaterial3D
		(mi as MeshInstance3D).material_override = m
		_materials.append(m)
		_meshes.append(mi as MeshInstance3D)


func set_silhouette(on: bool) -> void:
	_silhouette_on = on
	for m in _materials:
		m.next_pass = _silhouette_mat if on and sprite == null else null
	if sprite:
		sprite.set_silhouette(on)


# ---------------------------------------------------------------- AI

func _player() -> PrototypePlayer:
	return world.player if world else null


func _player_valid() -> bool:
	var p := _player()
	return p != null and p.is_targetable() and not world.is_safe(p.global_position)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func engage() -> void:
	if state == State.DEAD or state == State.CHASE or state == State.ATTACK or state == State.HURT:
		return
	if not _player_valid():
		return
	state = State.CHASE
	if world and world.has_method("alert_species"):
		world.alert_species(self)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var p := _player()
	var to_player := _flat(p.global_position - global_position) if p else Vector3.ZERO
	var dist := to_player.length()
	var from_home := _flat(global_position - home).length()
	match state:
		State.WANDER:
			var radius := aggro_radius * (NIGHT_AGGRO_MULT if Game.is_night() else 1.0)
			if aggressive and dist < radius and _player_valid():
				engage()
		State.CHASE, State.ATTACK:
			if not _player_valid() or from_home > leash:
				_give_up()
		State.RETURN:
			if from_home < 0.8:
				hp = max_hp  # resets after giving up [미정 assumption]
				state = State.WANDER
		State.HURT:
			_hurt_t -= delta
			if _hurt_t <= 0.0:
				state = State.CHASE if _player_valid() else State.RETURN
				_start_hop(Vector3.ZERO, 0.25, true)
	# hop motion
	_hop_t += delta
	var t := clampf(_hop_t / _hop_time, 0.0, 1.0)
	var airborne := not _hop_rest and t < 0.55
	velocity = (_hop_vel if airborne else Vector3.ZERO) + _knock
	_knock = _knock.move_toward(Vector3.ZERO, delta * 22.0)
	move_and_slide()
	if height_func.is_valid():
		global_position.y = height_func.call(global_position.x, global_position.z)
	if state == State.ATTACK and not _attack_done and t > 0.3 and t < 0.6:
		_try_contact()
	if t >= 1.0 and state != State.HURT:
		_next_hop(to_player, dist)


func _give_up() -> void:
	state = State.RETURN


func _next_hop(to_player: Vector3, dist: float) -> void:
	match state:
		State.WANDER:
			# GDD 9.4: in dangerous places aggressive monsters go for a parked, unattended camper
			var bait: Vector3 = world.camper_bait(self) if aggressive and world and world.has_method("camper_bait") else Vector3.INF
			if bait != Vector3.INF:
				var to := _flat(bait - global_position)
				if to.length() < 1.3:
					if _cooldown <= 0.0:
						_cooldown = 5.0
						_start_hop(to.normalized() * 0.5, 0.6)
						world.hit_camper(self)
					else:
						_start_hop(Vector3.ZERO, 0.5, true)
				else:
					_start_hop(to.normalized() * minf(1.4, to.length() - 0.8), 0.8)
				return
			var ang := _rng.randf() * TAU
			var r := _rng.randf_range(0.6, 1.4)
			var cand := _flat(global_position) + Vector3(cos(ang), 0.0, sin(ang)) * r
			if _flat(cand - home).length() > wander_radius:
				cand = _flat(global_position) + (home - _flat(global_position)).normalized() * r
			_start_hop(cand - _flat(global_position), 1.1)
		State.CHASE, State.ATTACK:
			var reach := (RADIUS * body_scale - RADIUS) * 2.0
			if dist < 1.7 + reach and _cooldown <= 0.0:
				state = State.ATTACK
				_attack_done = false
				_cooldown = 1.3
				_start_hop(to_player.normalized() * minf(dist + 0.2, 1.5), 0.6)
			else:
				state = State.CHASE
				var step := minf(1.5, maxf(0.0, dist - 1.0 - reach))
				if step < 0.3:
					_start_hop(Vector3.ZERO, 0.4, true)  # waiting for the next lunge
				else:
					_start_hop(to_player.normalized() * step, 0.7)
		State.RETURN:
			var back := home - _flat(global_position)
			_start_hop(back.normalized() * minf(1.6, back.length()), 0.6)


func _start_hop(offset: Vector3, duration: float, rest := false) -> void:
	_hop_t = 0.0
	_hop_time = duration
	_hop_rest = rest or offset.length() < 0.05
	_hop_vel = offset / (duration * 0.55) if not _hop_rest else Vector3.ZERO
	if offset.length() > 0.05:
		_yaw = atan2(-offset.x, -offset.z)


func _try_contact() -> void:
	var p := _player()
	if p == null or not p.is_targetable():
		return
	var params := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = RADIUS * body_scale + 0.08
	params.shape = sph
	params.transform = Transform3D(Basis(), global_position + Vector3(0, RADIUS * body_scale, 0))
	params.collision_mask = PrototypePlayer.BODY_LAYER
	var hits := get_world_3d().direct_space_state.intersect_shape(params, 4)
	for h in hits:
		if h["collider"] == p:
			_attack_done = true
			p.receive_attack(profile, self)
			return


## Called by the player's weapon after physical contact.
func receive_attack(attacker_profile: Dictionary, from: Node3D) -> void:
	if state == State.DEAD:
		return
	var res := Combat.resolve(attacker_profile, profile)
	var top := global_position + Vector3(0, 1.1, 0)
	if res["hit"]:
		hp -= res["damage"]
		res["detail"] += " · 남은 HP %d/%d" % [maxi(hp, 0), max_hp]
		Game.combat_log.add(Combat.short_text(res), res["detail"], "crit" if res["crit"] else "hit")
		if Game.hud:
			Game.hud.float_text(top, ("치명타 %d" if res["crit"] else "%d") % res["damage"],
				Color(1.0, 0.62, 0.2) if res["crit"] else Color(1.0, 0.96, 0.85), res["crit"])
		_flash = 1.0
		var away := _flat(global_position - from.global_position).normalized()
		_knock = away * (5.5 if res["crit"] else 4.0)
		if hp <= 0:
			_die()
			return
		state = State.HURT
		_hurt_t = 0.28
		_hop_t = _hop_time  # interrupt the hop
		_hop_rest = true
		if world and world.has_method("alert_species"):
			world.alert_species(self)
	else:
		Game.combat_log.add(Combat.short_text(res), res["detail"], "miss")
		if Game.hud:
			Game.hud.float_text(top, "빗나감", Color(0.75, 0.78, 0.82))
		engage()


## Run over by the camper (VisualLab): no to-hit roll, a heavy shove; the camper pays in durability.
func receive_ram(damage: int, from: Node3D) -> void:
	if state == State.DEAD:
		return
	var dmg := maxi(1, damage - int(profile.get("armor", 0)))
	hp -= dmg
	Game.combat_log.add("캠핑카 들이받기 → %s %d" % [display_name, dmg], "캠핑카가 %s을(를) 들이받음 — 피해 %d (방어 %d 뺌) · 남은 HP %d/%d" % [
		display_name, dmg, int(profile.get("armor", 0)), maxi(hp, 0), max_hp], "hit")
	if Game.hud:
		Game.hud.float_text(global_position + Vector3(0, 1.1, 0), "%d" % dmg, Color(1.0, 0.62, 0.2), true)
	_flash = 1.0
	_knock = _flat(global_position - from.global_position).normalized() * 8.0
	if hp <= 0:
		_die()
		return
	state = State.HURT
	_hurt_t = 0.35
	_hop_t = _hop_time
	_hop_rest = true
	if world and world.has_method("alert_species"):
		world.alert_species(self)


func _die() -> void:
	state = State.DEAD
	Game.player_state.add_exp(exp_reward)
	Game.combat_log.add("%s 처치 · EXP +%d" % [display_name, exp_reward], "%s 처치 — 일반 EXP +%d (보유 %d / 레벨업 %d) · 시체를 조사해 전리품을 얻을 수 있다" % [
		display_name, exp_reward, Game.player_state.gen_exp, Game.player_state.exp_to_next()], "death")
	if Game.hud:
		Game.hud.float_text(global_position + Vector3(0, 1.4, 0), "EXP +%d" % exp_reward, Color(0.6, 0.85, 1.0))
	Game.quests.on_kill(monster_id)
	if world and world.has_method("on_monster_killed"):
		world.on_monster_killed(self)
	queue_free()


## Loot table per kind (data/monsters.json) [미정 numbers].
func roll_loot() -> Inventory:
	return MonsterDB.roll_loot(kind, _rng)


func is_engaged() -> bool:
	return state == State.CHASE or state == State.ATTACK or state == State.HURT


func _process(delta: float) -> void:
	var t := clampf(_hop_t / _hop_time, 0.0, 1.0)
	_rig.pose(t if not _hop_rest else 0.9)
	_rig.rotation.y = lerp_angle(_rig.rotation.y, _yaw, 1.0 - exp(-10.0 * delta))
	_flash = maxf(0.0, _flash - delta * 6.0)
	if sprite:
		var dir := posmod(roundi(_rig.rotation.y / (TAU / SlimeRig.DIRECTIONS)), SlimeRig.DIRECTIONS)
		var f := mini(int((t if not _hop_rest else 0.9) * SlimeRig.FRAMES), SlimeRig.FRAMES - 1)
		sprite.set_frame(f, dir)
		sprite.set_flash(Color(1, 1, 1, _flash * 0.85))
