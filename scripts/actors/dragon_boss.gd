class_name DragonBoss
extends SlimeMonster
## The dragon of the nest — the main quest's goal. User design: it **can't be beaten in a fight**;
## the way through is talking it into leaving the nest (it returns on another continent later).
## Sleeps on its hoard; coming close wakes it and it speaks first (dialogue.story.dragon_parley).
## Answer well and it flies off for good; anger it (wrong answers, or hitting it) and it fights
## for a while — blades bounce off its scales — then calms down and listens again (E to talk).
## While angry it uses these patterns:
##   물기   front, close: a red circle in front of the head, then the bite
##   꼬리   all around, close: a red ring, then a full spin that shoves the player away
##   화염   front, mid range: a red cone, then 1.6 s of fire that keeps burning whoever stands in it
##   덮치기 from half HP: takes off, a red circle follows the player, then it dives onto that spot
## Every attack shows its area on the ground first; walking out of it is the dodge (no timing
## input, GDD 6.1). Its hits still go through the TRPG roll (6.2). It never leaves the lair (boss
## chase rule, 7.3). All numbers are [미정] prototype values (data/monsters.json "dragon").

const WAKE_RADIUS := 10.0
const FRONT_DEG := 55.0
const ATTACK_NAMES := {"bite": "물기", "tail": "꼬리 휘두르기", "fire": "화염 숨결", "slam": "덮치기"}
const FIRE_RANGE := 11.0
const FIRE_HALF_DEG := 28.0
const DIVE_RADIUS := 4.0
const PARLEY := "dialogue.story.dragon_parley"
const ANGER_SECONDS := 22.0  ## how long an angry dragon fights before it calms down
const LEAVE_SECONDS := 4.5
const TAIL_RADIUS := 5.6
const BITE_RADIUS := 2.3
const BITE_REACH := 3.8

var rig: DragonRig
var arena_center := Vector3.ZERO
var arena_radius := 16.0
var attacks := {}
var phase := 1
## sleep, wake, talk, listen, fight, bite, tail, breath, dive, rage, return, leave, dead
var mode := "sleep"
var interact_range := 6.5  ## E = talk while it listens (InteractPoint duck type)
var _angry_t := 0.0
var _hint_shown := false
var _t := 0.0
var _cd := 2.0
var _breath_cd := 3.0
var _dive_cd := 0.0
var _tick := 0.0
var _hit_done := false
var _rage_pending := false
var _spot := Vector3.ZERO      # where the current attack lands (bite circle / dive target)
var _from := Vector3.ZERO      # dive start
var _decal: MeshInstance3D
var _decal_mat: StandardMaterial3D
var _fire: CPUParticles3D
var _fire_light: OmniLight3D
var _shapes: Array[CollisionShape3D] = []


func _ready() -> void:
	_rng.seed = hash(monster_id)
	var def := MonsterDB.info(kind)
	display_name = str(def.get("name", "드래곤"))
	aggressive = true
	max_hp = int(def.get("hp", 150))
	exp_reward = int(def.get("exp", 300))
	profile = profile.merged(def.get("profile", {}), true)
	profile["name"] = display_name
	attacks = def.get("attacks", {})
	arena_radius = float(def.get("arena_radius", 16.0))
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = LAYER
	collision_mask = PhysLayers.WORLD | PhysLayers.PLAYER
	var body := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 1.25
	cap.height = 4.8
	body.shape = cap
	body.rotation.x = PI * 0.5
	body.position = Vector3(0, 1.4, 0.2)
	add_child(body)
	_shapes = [body]
	for spec in [[Vector3(0, 1.0, -2.4), 1.1], [Vector3(0, 1.7, -3.6), 0.95]]:  # chest, head: low enough for a sword
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = spec[1]
		cs.shape = sph
		cs.position = spec[0]
		add_child(cs)
		_shapes.append(cs)
	rig = DragonRig.new()
	rig.sleep = 1.0
	add_child(rig)
	hp = max_hp
	home = Vector3(global_position.x, 0.0, global_position.z)
	arena_center = home
	if world and world.region.has("arena"):
		arena_center = RegionDB.v3(world.region["arena"]["center"])
		arena_radius = float(world.region["arena"].get("radius", arena_radius))
	_yaw = PI  # asleep facing the lair's entrance (south)
	rotation.y = _yaw
	_build_effects()
	add_to_group("enemies")
	add_to_group("interactable")


func prompt_text() -> String:
	return "E 드래곤에게 말 걸기"


func can_interact() -> bool:
	return mode == "listen"


func interact(_p: Node) -> void:
	_start_talk()


## No baked sprite: the dragon stays a 3D model (much bigger than the sprite cell).
func use_sprite_sheet(_sheet: SpriteSheet) -> void:
	pass


func set_silhouette(_on: bool) -> void:
	pass


func _build_effects() -> void:
	_decal_mat = StandardMaterial3D.new()
	_decal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_decal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_decal_mat.albedo_color = Color(1.0, 0.16, 0.08, 0.6)
	_decal_mat.vertex_color_use_as_albedo = true
	_decal_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_decal = MeshInstance3D.new()
	_decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_decal.material_override = _decal_mat
	_decal.visible = false
	_decal.top_level = true
	add_child(_decal)
	_fire = CPUParticles3D.new()
	_fire.emitting = false
	_fire.amount = 90
	_fire.lifetime = 0.75
	_fire.local_coords = false
	_fire.direction = Vector3(0, -0.05, -1)
	_fire.spread = FIRE_HALF_DEG * 0.7
	_fire.initial_velocity_min = 12.0
	_fire.initial_velocity_max = 16.0
	_fire.gravity = Vector3(0, 1.5, 0)
	_fire.damping_min = 4.0
	_fire.damping_max = 6.0
	_fire.scale_amount_min = 0.7
	_fire.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.5, 1.6))
	curve.add_point(Vector2(1, 2.4))
	_fire.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.6))
	ramp.set_color(1, Color(0.5, 0.08, 0.02, 0.0))
	ramp.add_point(0.35, Color(1.0, 0.5, 0.1))
	_fire.color_ramp = ramp
	var puff := SphereMesh.new()
	puff.radius = 0.25
	puff.height = 0.5
	puff.radial_segments = 6
	puff.rings = 3
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material = pm
	_fire.mesh = puff
	rig.mouth.add_child(_fire)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.5, 0.2)
	_fire_light.light_energy = 0.0
	_fire_light.omni_range = 12.0
	rig.mouth.add_child(_fire_light)


# ---------------------------------------------------------------- helpers

## Name + subject particle (드래곤이 / 와이번이가 → 받침이 있으면 "이", 없으면 "가").
func _subj() -> String:
	var last := display_name.unicode_at(display_name.length() - 1)
	var batchim := last >= 0xAC00 and last <= 0xD7A3 and (last - 0xAC00) % 28 != 0
	return display_name + ("이" if batchim else "가")


func _forward() -> Vector3:
	return Vector3(-sin(_yaw), 0, -cos(_yaw))


func _angle_to(v: Vector3) -> float:
	return rad_to_deg(absf(angle_difference(_yaw, atan2(-v.x, -v.z))))


func _turn_to(v: Vector3, delta: float, speed: float) -> void:
	if v.length() < 0.1:
		return
	var want := atan2(-v.x, -v.z)
	var diff := angle_difference(_yaw, want)
	_yaw += clampf(diff, -speed * delta, speed * delta)


func _in_arena(p: Vector3, margin := 0.0) -> bool:
	return _flat(p - arena_center).length() < arena_radius + margin


func _windup(key: String) -> float:
	return float(attacks.get(key, {}).get("windup", 1.0)) * (0.75 if phase == 2 else 1.0)


func _speed() -> float:
	return 2.6 if phase == 1 else 3.4


func _set_mode(m: String) -> void:
	mode = m
	_t = 0.0
	_hit_done = false
	_tick = 0.0
	if m in ["fight", "sleep", "return"]:
		_decal.visible = false


## Red area on the ground: a disc (radius r at pos) or a cone along the dragon's heading. A faint
## fill with a solid rim, so the edge to step over is clear and the ground still shows through.
func _show_disc(pos: Vector3, r: float) -> void:
	_decal.mesh = _area_mesh(r, 180.0, 36)
	_decal.global_transform = Transform3D(Basis(), Vector3(pos.x, _ground(pos) + 0.07, pos.z))
	_decal.visible = true


func _show_cone() -> void:
	_decal.mesh = _area_mesh(FIRE_RANGE, FIRE_HALF_DEG, 14)
	_decal.visible = true
	_place_cone()


## Fan of half_deg either side of -Z (180 = full disc): fill alpha 0.3, rim band alpha 1.
func _area_mesh(r: float, half_deg: float, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fill := Color(1, 1, 1, 0.3)
	var edge := Color(1, 1, 1, 1)
	var inner := r - minf(0.35, r * 0.12)
	for i in n:
		var a0 := deg_to_rad(-half_deg + 2.0 * half_deg * i / n)
		var a1 := deg_to_rad(-half_deg + 2.0 * half_deg * (i + 1) / n)
		var d0 := Vector3(sin(a0), 0, -cos(a0))
		var d1 := Vector3(sin(a1), 0, -cos(a1))
		for v: Array in [[Vector3.ZERO, fill], [d0 * inner, fill], [d1 * inner, fill],
				[d0 * inner, edge], [d0 * r, edge], [d1 * r, edge], [d0 * inner, edge], [d1 * r, edge], [d1 * inner, edge]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
	if half_deg < 180.0:  # straight sides of the cone get a rim too
		for a: float in [-half_deg, half_deg]:
			var d := Vector3(sin(deg_to_rad(a)), 0, -cos(deg_to_rad(a)))
			var side := d.cross(Vector3.UP) * (0.3 if a < 0.0 else -0.3)
			for v: Vector3 in [Vector3.ZERO, d * r, d * r + side, Vector3.ZERO, d * r + side, side]:
				st.set_color(edge)
				st.add_vertex(v)
	return st.commit()


func _place_cone() -> void:
	var head := global_position + _forward() * 2.6
	_decal.global_transform = Transform3D(Basis(Vector3.UP, _yaw), Vector3(head.x, _ground(head) + 0.07, head.z))


func _ground(p: Vector3) -> float:
	return height_func.call(p.x, p.z) if height_func.is_valid() else 0.0


func _player_in_cone(p: Vector3) -> bool:
	var head := global_position + _forward() * 2.6
	var v := _flat(p - head)
	return v.length() < FIRE_RANGE and _angle_to(v) < FIRE_HALF_DEG + 4.0


## One attack landing on the player: the TRPG roll with that attack's profile, plus a shove.
func _hit(key: String, shove_from := Vector3.INF, shove := 0.0) -> void:
	var p := _player()
	if p == null or not p.is_targetable():
		return
	var prof: Dictionary = profile.merged(attacks.get(key, {}), true)
	prof["name"] = "%s(%s)" % [display_name, ATTACK_NAMES.get(key, key)]
	var hp0 := Game.player_state.hp
	p.receive_attack(prof, self)
	if shove > 0.0 and Game.player_state.hp < hp0 and shove_from != Vector3.INF:
		p.shove(_flat(p.global_position - shove_from).normalized() * shove)


# ---------------------------------------------------------------- AI

func engage() -> void:
	if mode == "sleep" and _player_valid():
		_set_mode("wake")
		state = State.CHASE
		if Game.hud:
			Game.hud.show_caption("%s 깨어났다!" % _subj())
		Game.combat_log.add("%s 깨어났다" % _subj(), "거대한 눈이 주인공을 내려다본다 — 싸워서는 이길 수 없는 상대다.", "info")


## The dragon speaks (dialogue.story.dragon_parley); what it decides comes back as flags.
func _start_talk() -> void:
	_decal.visible = false
	_fire.emitting = false
	rig.lift = 0.0
	Game.narrative.set_flag("story.dragon_angry", false)
	if Game.hud:
		Game.hud.show_caption("")
	_set_mode("talk")
	state = State.WANDER
	if not (Game.hud and Game.hud.start_dialogue(PARLEY)):
		_set_mode("listen")


## Angry: fights for a while (it can't be hurt), then calms down and listens again.
func _anger() -> void:
	Game.narrative.set_flag("story.dragon_angry", false)
	_angry_t = ANGER_SECONDS
	_cd = 1.2
	state = State.CHASE
	_set_mode("fight")
	if Game.hud:
		Game.hud.show_caption("%s 화났다! — 싸워서는 이길 수 없다. 공격을 피하며 진정되기를 기다리자" % _subj())
	Game.combat_log.add("%s 화났다" % _subj(), "칼은 비늘에 튕겨 나간다. 붉은 범위를 피하며 물러나 있으면 진정하고 다시 이야기를 들어 준다.", "info")


## Persuaded: rears up, spreads its wings and flies out of the nest for good.
func _start_leave() -> void:
	_set_mode("leave")
	state = State.WANDER
	if Game.hud:
		Game.hud.show_caption("")
	for sh in _shapes:
		sh.set_deferred("disabled", true)
	Game.combat_log.add("%s 둥지를 떠난다" % _subj(), "대화로 설득했다 — 드래곤은 바다 건너 다른 땅으로 날아갔다.", "info")


func _finish_leave() -> void:
	mode = "dead"
	state = State.DEAD
	visible = false
	remove_from_group("enemies")
	remove_from_group("interactable")
	var dfd: Dictionary = Game.field.get("defeated", {})
	dfd[monster_id] = Game.total_minutes()  # gone for good: never respawns (GDD 7.4 once-only)
	Game.field["defeated"] = dfd
	if world and "monsters" in world:
		world.monsters.erase(self)
	if Game.hud and Game.hud.cutscene:
		Game.hud.cutscene.play("cutscene.dragon_departs")
	queue_free()


func _physics_process(delta: float) -> void:
	if mode == "dead":
		return
	_t += delta
	_cd = maxf(0.0, _cd - delta)
	_breath_cd = maxf(0.0, _breath_cd - delta)
	_dive_cd = maxf(0.0, _dive_cd - delta)
	var p := _player()
	var to_p := _flat(p.global_position - global_position) if p else Vector3.ZERO
	var dist := to_p.length()
	var move := Vector3.ZERO
	match mode:
		"sleep":
			if _player_valid() and dist < WAKE_RADIUS and _in_arena(p.global_position, 2.0):
				engage()
		"wake":
			_turn_to(to_p, delta, 1.2)
			if _t > 1.8:
				_start_talk()
		"talk":
			_turn_to(to_p, delta, 1.5)
			if _t > 0.3 and not (Game.hud and Game.hud.dialogue_active()):
				if Game.narrative.get_flag("story.dragon_left"):
					_start_leave()
				elif Game.narrative.get_flag("story.dragon_angry"):
					_anger()
				else:
					_set_mode("listen")
		"listen":
			if dist < arena_radius:
				_turn_to(to_p, delta, 1.0)
		"leave":
			var tl := _t
			if tl > 1.0:
				var k := clampf((tl - 1.0) / (LEAVE_SECONDS - 1.0), 0.0, 1.0)
				rig.lift = k * k * 18.0
				move = Vector3(0, 0, -1) * k * 7.0
				_yaw = lerp_angle(_yaw, 0.0, 1.0 - exp(-2.0 * delta))  # turns north, out over the sea
			if tl > LEAVE_SECONDS:
				_finish_leave()
				return
		"rage":
			if _t > 1.5:
				if Game.hud:
					Game.hud.show_caption("")
				_set_mode("fight")
		"return":
			var back := home - _flat(global_position)
			if back.length() < 0.8:
				_set_mode("listen")
				state = State.WANDER
				if Game.hud:
					Game.hud.show_caption("%s 숨을 고른다 — 다시 말을 걸 수 있다 (E)" % _subj())
			else:
				_turn_to(back, delta, 1.6)
				move = back.normalized() * _speed()
		"fight":
			_angry_t -= delta
			if not _player_valid() or not _in_arena(p.global_position, 2.0) or _angry_t <= 0.0:
				_set_mode("return")
			elif _rage_pending:
				_rage_pending = false
				_set_mode("rage")
			else:
				_turn_to(to_p, delta, 1.4 if phase == 1 else 2.0)
				if _cd <= 0.0:
					_choose_attack(dist, _angle_to(to_p))
				if mode == "fight" and dist > 4.6:
					move = to_p.normalized() * _speed()
		"bite":
			var w := _windup("bite")
			if _t < w:
				_show_disc(_spot, BITE_RADIUS)
			elif not _hit_done:
				_hit_done = true
				_decal.visible = false
				if p and _flat(p.global_position - _spot).length() < BITE_RADIUS + 0.3:
					_hit("bite")
			elif _t > w + 0.8:
				_end_attack(1.0)
		"tail":
			var w := _windup("tail")
			if _t < w:
				_show_disc(global_position, TAIL_RADIUS)
			elif not _hit_done:
				_hit_done = true
				_decal.visible = false
				if dist < TAIL_RADIUS + 0.3:
					_hit("tail", global_position, 11.0)
			elif _t > w + 1.0:
				_end_attack(1.0)
		"breath":
			var w := _windup("fire")
			if _t < w:
				_place_cone()
			elif _t < w + 1.6:
				if not _fire.emitting:
					_fire.emitting = true
				_turn_to(to_p, delta, 0.35 if phase == 1 else 0.85)  # the flame sweeps after the player
				_place_cone()
				_tick -= delta
				if _tick <= 0.0:
					_tick = 0.55
					if p and _player_in_cone(p.global_position):
						_hit("fire")
			else:
				_fire.emitting = false
				_decal.visible = false
				if _t > w + 2.4:
					_end_attack(1.2)
		"dive":
			_dive(delta, p)
	rotation.y = _yaw
	velocity = move
	if mode != "dive":
		move_and_slide()
	global_position.y = _ground(global_position)


func _choose_attack(dist: float, ang: float) -> void:
	var front := ang < FRONT_DEG
	if phase == 2 and _dive_cd <= 0.0 and dist > 6.0:
		_from = global_position
		_set_mode("dive")
		for s in _shapes:
			s.disabled = true  # passes over the player while airborne
		return
	if dist < TAIL_RADIUS - 0.4 and (not front or (dist < 3.0 and _rng.randf() < 0.35)):
		_set_mode("tail")
		return
	if front and dist < BITE_REACH + BITE_RADIUS:
		_spot = global_position + _forward() * BITE_REACH
		_set_mode("bite")
		return
	if front and _breath_cd <= 0.0 and dist < FIRE_RANGE:
		_set_mode("breath")
		_show_cone()
		return


func _end_attack(cooldown: float) -> void:
	_cd = cooldown * (0.7 if phase == 2 else 1.0)
	if mode == "breath":
		_breath_cd = 5.0 if phase == 1 else 3.5
	if mode == "dive":
		_dive_cd = 7.0
	_set_mode("fight")


## Take off (0.8 s) → a red circle follows the player (1.2 s) → it stops (0.5 s) → dive (0.35 s)
## → impact → recover. The landing spot stays inside the lair.
func _dive(_delta: float, p: PrototypePlayer) -> void:
	var t := _t
	if t < 0.8:
		rig.lift = smoothstep(0.0, 0.8, t) * 6.0
	elif t < 2.0:
		if p:
			_spot = _clamp_arena(p.global_position)
		_show_disc(_spot, DIVE_RADIUS)
	elif t < 2.5:
		_decal_mat.albedo_color.a = 0.6 + 0.35 * sin(t * 30.0)
	elif t < 2.85:
		var k := (t - 2.5) / 0.35
		var pos := _from.lerp(_spot, k)
		global_position = Vector3(pos.x, _ground(pos), pos.z)
		rig.lift = (1.0 - k) * 6.0
		var v := _flat(_spot - _from)
		if v.length() > 0.5:
			_yaw = atan2(-v.x, -v.z)
	elif not _hit_done:
		_hit_done = true
		rig.lift = 0.0
		_decal.visible = false
		_decal_mat.albedo_color.a = 0.6
		global_position = Vector3(_spot.x, _ground(_spot), _spot.z)
		for s in _shapes:
			s.disabled = false
		if p and _flat(p.global_position - _spot).length() < DIVE_RADIUS + 0.3:
			_hit("slam", _spot, 10.0)
		if Game.hud:
			Game.hud.float_text(_spot + Vector3(0, 1.0, 0), "쿵!", Color(1.0, 0.7, 0.4), true)
	elif t > 3.9:
		_end_attack(1.2)


func _clamp_arena(p: Vector3) -> Vector3:
	var v := _flat(p - arena_center)
	var r := arena_radius - 3.5
	if v.length() > r:
		v = v.normalized() * r
	return arena_center + v


# ---------------------------------------------------------------- taking hits / dying

## Blades bounce off: no damage, ever (user design — it can't be beaten in a fight). Hitting a
## sleeping or listening dragon makes it angry.
func receive_attack(_attacker_profile: Dictionary, _from: Node3D) -> void:
	if mode in ["dead", "leave", "talk"]:
		return
	_flash = 0.6
	Game.combat_log.add("칼날이 비늘에 튕겨 나갔다", "드래곤에게는 상처 하나 나지 않는다 — 싸워서는 이길 수 없다. 대화로 설득해 보자.", "miss")
	if Game.hud:
		Game.hud.float_text(global_position + Vector3(0, 3.4, 0), "튕겨 나감", Color(0.8, 0.82, 0.86))
		if not _hint_shown:
			_hint_shown = true
			Game.boot.hud.toast("칼이 통하지 않는다… 싸워서는 이길 수 없다. 진정시킨 뒤 말을 걸어 보자")
	if mode in ["sleep", "wake", "listen", "return"]:
		_anger()
	elif mode == "fight":
		_angry_t = maxf(_angry_t, 8.0)  # keeps it angry a little longer


func receive_ram(_damage: int, from: Node3D) -> void:
	receive_attack({}, from)


func is_engaged() -> bool:
	return mode not in ["sleep", "wake", "talk", "listen", "return", "leave", "dead"]


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 5.0)
	rig.flash = _flash
	var k := 1.0 - exp(-6.0 * delta)
	var want := {"neck": 0.0, "jaw": 0.0, "wings": 0.0, "flap": 0.0, "walk": 0.0, "glow": 0.0, "sleep": 0.0}
	match mode:
		"sleep":
			want["sleep"] = 1.0
		"wake", "rage":
			want["neck"] = 1.0
			want["jaw"] = 1.0
			want["wings"] = 1.0
			want["flap"] = 6.0
		"talk", "listen":
			want["neck"] = 0.8
			want["jaw"] = 0.15 + 0.15 * sin(_t * 2.0) if mode == "talk" else 0.0
			want["wings"] = 0.15
		"leave":
			want["neck"] = 1.0
			want["wings"] = 1.0
			want["flap"] = 8.0 if _t > 0.8 else 2.0
			want["jaw"] = 0.5 if _t < 1.0 else 0.0
		"fight", "return":
			want["walk"] = 7.0 if velocity.length() > 0.3 else 0.0
			want["wings"] = 0.25
		"bite":
			var w := _windup("bite")
			want["neck"] = 1.0 if _t < w else -0.8
			want["jaw"] = 0.6 if _t < w else (1.0 if _t < w + 0.2 else 0.0)
		"tail":
			var w := _windup("tail")
			want["wings"] = 0.5
			if _t >= w and _t < w + 0.45:
				rig.rotation.y = -TAU * (_t - w) / 0.45  # the whole body spins once
			else:
				rig.rotation.y = 0.0
		"breath":
			var w := _windup("fire")
			want["neck"] = 0.9 if _t < w else -0.3
			want["jaw"] = 0.3 if _t < w else 1.0
			want["glow"] = clampf(_t / w, 0.0, 1.0) if _t < w + 1.6 else 0.0
			want["wings"] = 0.5
		"dive":
			want["wings"] = 1.0
			want["flap"] = 9.0 if _t < 2.5 else 0.0
			want["jaw"] = 1.0 if _t > 2.4 and _t < 3.0 else 0.0
		"dead":
			rig.dead = minf(1.0, rig.dead + delta * 0.8)
	if mode != "tail":
		rig.rotation.y = 0.0
	for key: String in want:
		rig.set(key, lerpf(float(rig.get(key)), float(want[key]), k))
	_fire_light.light_energy = lerpf(_fire_light.light_energy, 4.0 if _fire.emitting else rig.glow * 1.5, k)
	if mode == "breath" and _t < _windup("fire") and _decal.visible:
		_decal_mat.albedo_color.a = 0.4 + 0.4 * clampf(_t / _windup("fire"), 0.0, 1.0)
	elif mode in ["bite", "tail"]:
		_decal_mat.albedo_color.a = 0.65 + 0.3 * sin(_t * 18.0)
