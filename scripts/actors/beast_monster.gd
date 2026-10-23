class_name BeastMonster
extends SlimeMonster
## Field beasts that are not slimes (data/monsters.json "class": "beast"): 식충식물, 늑대, 고슴도치.
## Same AI graphs, combat rolls, loot and respawn as the slimes; a different body (BeastRig),
## gait ("walk" / "rooted") and special moves started by the AI graph's action nodes:
##   독액 뱉기 (spit)    a red circle where the hero stands, then a blob of venom flies there;
##                       inside the circle when it lands = to-hit roll, a hit also poisons
##   물기 (bite)         a small red circle in front, then a lunge with the jaws
##   할퀴기 (claw)       a red fan in front, then a wide swipe of the paw
##   가시 세우고 돌진 (charge)  curls up (spines out) behind a red lane, rolls down it — touching
##                       the body = to-hit roll — then sits dizzy for a moment
## Every move shows its area on the ground first; stepping out of it is the dodge (GDD 6.1, the
## same as the dragon). Hits still go through the TRPG roll (6.2). Moves are not interrupted by
## being hit. Numbers per move: data/monsters.json "attacks" [미정].

const STRIKE_TIME := 0.16
const PLAYER_RADIUS := 0.3

var body := "wolf"
var rig: BeastRig
var attacks := {}
var _atk := {}
var _shots: Array[Dictionary] = []
var _decal: MeshInstance3D
var _decal_mat: StandardMaterial3D
var _walk_phase := 0.0
var _clock := 0.0


func _build_body(def: Dictionary) -> Node3D:
	body = str(def.get("body", "wolf"))
	attacks = def.get("attacks", {})
	rig = BeastRig.new(body)
	add_child(rig)
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
	return rig


func sprite_target() -> Array:
	return [BeastRig.sprite_bake_spec(body), "beast|" + body]


# ---------------------------------------------------------------- moves

func _special_attack(action: String, n: Dictionary, to_player: Vector3, dist: float) -> bool:
	if not attacks.has(action):
		return false
	var a: Dictionary = attacks[action]
	var dir := to_player.normalized() if dist > 0.01 else _forward()
	_yaw = atan2(-dir.x, -dir.z)
	state = State.ATTACK
	_cooldown = MonsterAI.param(n, "cooldown")
	_atk = {"key": action, "t": 0.0, "windup": float(a.get("windup", 0.6)), "dir": dir, "done": false,
		"fired": false, "rolled": 0.0, "dizzy": -1.0}
	match action:
		"spit":
			var pl := _player()
			_atk["spot"] = _flat(pl.global_position) if pl else _flat(global_position) + dir * 4.0
			_show_disc(_atk["spot"], float(a.get("radius", 1.1)))
		"bite":
			_atk["spot"] = _flat(global_position) + dir * float(a.get("reach", 1.2))
			_show_disc(_atk["spot"], float(a.get("radius", 0.9)))
		"claw":
			_decal.mesh = _area_mesh(float(a.get("range", 1.8)), float(a.get("half_deg", 65.0)), 14)
			_place_on_self()
			_decal.visible = true
		"charge":
			_atk["length"] = MonsterAI.param(n, "distance")
			_decal.mesh = _lane_mesh(_atk["length"], float(a.get("width", 1.1)))
			_place_on_self()
			_decal.visible = true
	_hop_rest = true  # the base hop clock waits until the move is over
	_hop_t = 0.0
	_hop_time = 1000.0
	return true


func _forward() -> Vector3:
	return Vector3(-sin(_yaw), 0, -cos(_yaw))


func _ground(p: Vector3) -> float:
	return height_func.call(p.x, p.z) if height_func.is_valid() else 0.0


func _show_disc(pos: Vector3, r: float) -> void:
	_decal.mesh = _area_mesh(r, 180.0, 28)
	_decal.global_transform = Transform3D(Basis(), Vector3(pos.x, _ground(pos) + 0.07, pos.z))
	_decal.visible = true


func _place_on_self() -> void:
	var p := global_position
	_decal.global_transform = Transform3D(Basis(Vector3.UP, _yaw), Vector3(p.x, _ground(p) + 0.07, p.z))


## Fan of half_deg either side of -Z (180 = full disc): fill alpha 0.3, rim band alpha 1.
static func _area_mesh(r: float, half_deg: float, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fill := Color(1, 1, 1, 0.3)
	var edge := Color(1, 1, 1, 1)
	var inner := r - minf(0.25, r * 0.15)
	for i in n:
		var a0 := deg_to_rad(-half_deg + 2.0 * half_deg * i / n)
		var a1 := deg_to_rad(-half_deg + 2.0 * half_deg * (i + 1) / n)
		var d0 := Vector3(sin(a0), 0, -cos(a0))
		var d1 := Vector3(sin(a1), 0, -cos(a1))
		for v: Array in [[Vector3.ZERO, fill], [d0 * inner, fill], [d1 * inner, fill],
				[d0 * inner, edge], [d0 * r, edge], [d1 * r, edge], [d0 * inner, edge], [d1 * r, edge], [d1 * inner, edge]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
	if half_deg < 180.0:
		for a: float in [-half_deg, half_deg]:
			var d := Vector3(sin(deg_to_rad(a)), 0, -cos(deg_to_rad(a)))
			var side := d.cross(Vector3.UP) * (0.2 if a < 0.0 else -0.2)
			for v: Vector3 in [Vector3.ZERO, d * r, d * r + side, Vector3.ZERO, d * r + side, side]:
				st.set_color(edge)
				st.add_vertex(v)
	return st.commit()


## Straight lane from the body along -Z (the charge): fill + rim on both sides and the far end.
static func _lane_mesh(length: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var rim := 0.18
	var quads := [[Vector2(-hw + rim, 0), Vector2(hw - rim, -length + rim), Color(1, 1, 1, 0.3)],
		[Vector2(-hw, 0), Vector2(-hw + rim, -length), Color(1, 1, 1, 1)],
		[Vector2(hw - rim, 0), Vector2(hw, -length), Color(1, 1, 1, 1)],
		[Vector2(-hw + rim, -length + rim), Vector2(hw - rim, -length), Color(1, 1, 1, 1)]]
	for q: Array in quads:
		var a: Vector2 = q[0]
		var b: Vector2 = q[1]
		for v: Vector2 in [a, Vector2(b.x, a.y), b, a, b, Vector2(a.x, b.y)]:
			st.set_color(q[2])
			st.add_vertex(Vector3(v.x, 0, v.y))
	return st.commit()


func _attack_profile(key: String) -> Dictionary:
	var a: Dictionary = attacks.get(key, {})
	var prof := profile.duplicate()
	for k in ["hit_bonus", "crit_chance", "phys", "elem"]:
		if a.has(k):
			prof[k] = a[k]
	prof["name"] = "%s(%s)" % [display_name, a.get("label", MonsterAI.ACTIONS.get(key, {}).get("label", key))]
	return prof


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if gait == "rooted":
		_knock = Vector3.ZERO
	_update_shots(delta)
	if _atk.is_empty():
		super(delta)
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if state == State.HURT:
		state = State.ATTACK  # a hit doesn't break a move
	_atk["t"] += delta
	var key: String = _atk["key"]
	var a: Dictionary = attacks.get(key, {})
	var t: float = _atk["t"]
	var w: float = _atk["windup"]
	var dir: Vector3 = _atk["dir"]
	var vel := Vector3.ZERO
	match key:
		"bite", "claw":
			if t >= w and t < w + STRIKE_TIME:
				vel = dir * float(a.get("lunge", 1.0 if key == "bite" else 0.4)) / STRIKE_TIME
				if not _atk["done"] and t >= w + STRIKE_TIME * 0.5:
					_resolve_melee(key, a)
			elif t >= w + STRIKE_TIME:
				_decal.visible = false
				if t >= w + STRIKE_TIME + float(a.get("recover", 0.45)):
					_end_attack()
					return
		"spit":
			if t >= w and not _atk["fired"]:
				_atk["fired"] = true
				_fire_spit(a)
			if t >= w + float(a.get("recover", 0.6)):
				_end_attack()
				return
		"charge":
			if t < w:
				if t < w * 0.6:  # keeps turning to the hero while curling up, then locks the lane
					var pl := _player()
					if pl and _player_valid():
						var to := _flat(pl.global_position - global_position)
						if to.length() > 0.2:
							dir = to.normalized()
							_atk["dir"] = dir
							_yaw = atan2(-dir.x, -dir.z)
				_place_on_self_lane(dir)
			elif float(_atk["dizzy"]) < 0.0:
				var speed := float(a.get("speed", 9.0))
				vel = dir * speed
				_atk["rolled"] = float(_atk["rolled"]) + speed * delta
				if not _atk["done"]:
					_try_charge_hit(dir, a)
				var blocked := float(_atk["rolled"]) > 0.8 and get_real_velocity().length() < speed * 0.25
				if float(_atk["rolled"]) >= float(_atk["length"]) or blocked:
					_atk["dizzy"] = t
					_decal.visible = false
			elif t - float(_atk["dizzy"]) >= float(a.get("recover", 1.1)):
				_end_attack()
				return
	velocity = vel + _knock
	_knock = _knock.move_toward(Vector3.ZERO, delta * 22.0)
	move_and_slide()
	if height_func.is_valid():
		global_position.y = height_func.call(global_position.x, global_position.z)


## The lane stays where the charge started; only its heading follows during the wind-up.
func _place_on_self_lane(dir: Vector3) -> void:
	var p := global_position
	_decal.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), Vector3(p.x, _ground(p) + 0.07, p.z))


func _end_attack() -> void:
	_atk = {}
	if _shots.is_empty():
		_decal.visible = false
	state = State.CHASE if provoked else State.WANDER
	_start_hop(Vector3.ZERO, 0.15, true)


func _resolve_melee(key: String, a: Dictionary) -> void:
	_atk["done"] = true
	var pl := _player()
	if pl == null or not _player_valid():
		return
	var d := _flat(pl.global_position - global_position)
	var hit := false
	if key == "bite":
		hit = _flat(pl.global_position).distance_to(_atk["spot"]) < float(a.get("radius", 0.9)) + PLAYER_RADIUS
	else:
		var fwd: Vector3 = _atk["dir"]
		hit = d.length() < float(a.get("range", 1.8)) + PLAYER_RADIUS \
			and (d.length() < 0.5 or rad_to_deg(fwd.angle_to(d.normalized())) < float(a.get("half_deg", 65.0)))
	if hit:
		pl.receive_attack(_attack_profile(key), self)


func _try_charge_hit(dir: Vector3, a: Dictionary) -> void:
	var pl := _player()
	if pl == null or not _player_valid():
		return
	if _flat(pl.global_position - global_position).length() < RADIUS * body_scale + PLAYER_RADIUS + 0.1:
		_atk["done"] = true
		if pl.receive_attack(_attack_profile("charge"), self):
			pl.shove(dir * float(a.get("shove", 4.0)))


func _fire_spit(a: Dictionary) -> void:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	sm.radial_segments = 8
	sm.rings = 4
	ball.mesh = sm
	ball.material_override = ProtoMesh.mat(Color(0.55, 0.85, 0.2), 0.4, Color(0.5, 0.9, 0.2), 0.8)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	ball.top_level = true
	add_child(ball)
	var from := rig.mouth_position()
	var spot: Vector3 = _atk["spot"]
	var to := Vector3(spot.x, _ground(spot) + 0.1, spot.z)
	ball.global_position = from
	_shots.append({"node": ball, "from": from, "to": to, "t": 0.0, "dur": float(a.get("flight", 0.6)),
		"r": float(a.get("radius", 1.1)), "a": a})


func _update_shots(delta: float) -> void:
	for s: Dictionary in _shots.duplicate():
		s["t"] = float(s["t"]) + delta
		var k := clampf(float(s["t"]) / float(s["dur"]), 0.0, 1.0)
		var node: MeshInstance3D = s["node"]
		node.global_position = (s["from"] as Vector3).lerp(s["to"], k) + Vector3(0, sin(k * PI) * 1.4, 0)
		if k >= 1.0:
			_shots.erase(s)
			_land_spit(s)
			node.queue_free()
			if _shots.is_empty() and (_atk.is_empty() or _atk["key"] == "spit"):
				_decal.visible = false


func _land_spit(s: Dictionary) -> void:
	var to: Vector3 = s["to"]
	var splash := CPUParticles3D.new()
	splash.one_shot = true
	splash.amount = 18
	splash.lifetime = 0.5
	splash.explosiveness = 1.0
	splash.direction = Vector3.UP
	splash.spread = 70.0
	splash.initial_velocity_min = 1.5
	splash.initial_velocity_max = 3.0
	splash.gravity = Vector3(0, -9.0, 0)
	splash.scale_amount_min = 0.5
	splash.scale_amount_max = 1.0
	var drop := SphereMesh.new()
	drop.radius = 0.05
	drop.height = 0.1
	drop.radial_segments = 4
	drop.rings = 2
	drop.material = ProtoMesh.mat(Color(0.55, 0.85, 0.2), 0.4, Color(0.5, 0.9, 0.2), 0.6)
	splash.mesh = drop
	splash.top_level = true
	add_child(splash)
	splash.global_position = to
	splash.emitting = true
	get_tree().create_timer(1.0).timeout.connect(splash.queue_free)
	var pl := _player()
	if pl == null or not _player_valid():
		return
	if _flat(pl.global_position).distance_to(_flat(to)) >= float(s["r"]) + PLAYER_RADIUS:
		return
	if pl.receive_attack(_attack_profile("spit"), self):
		var po: Dictionary = (s["a"] as Dictionary).get("poison", {})
		if not po.is_empty():
			Game.player_state.apply_poison(float(po.get("seconds", 6.0)), int(po.get("damage", 1)), display_name)


func receive_ram(damage: int, from: Node3D) -> void:
	super(damage, from)
	if gait == "rooted":
		_knock = Vector3.ZERO


func _die() -> void:
	_decal.visible = false
	super()


# ---------------------------------------------------------------- look

func _process(delta: float) -> void:
	_clock += delta
	rig.rotation.y = lerp_angle(rig.rotation.y, _yaw, 1.0 - exp(-12.0 * delta))
	_flash = maxf(0.0, _flash - delta * 6.0)
	var anim := "idle"
	var tt := fmod(_clock * 0.45, 1.0) if body == "plant" else 0.0
	if not _atk.is_empty():
		var key: String = _atk["key"]
		var t: float = _atk["t"]
		var w: float = _atk["windup"]
		match key:
			"bite", "claw":
				anim = key
				tt = 0.0 if t < w else (1.0 if t < w + STRIKE_TIME + 0.1 else 2.0)
			"spit":
				anim = "spit"
				tt = 0.0 if t < w else (1.0 if t < w + 0.25 else 2.0)
			"charge":
				anim = "ball" if float(_atk["dizzy"]) < 0.0 or t - float(_atk["dizzy"]) < 0.35 else "idle"
				tt = fmod(float(_atk["rolled"]) / 0.47, 1.0)
		if _decal.visible:
			_decal_mat.albedo_color.a = 0.45 + 0.4 * clampf(t / maxf(w, 0.01), 0.0, 1.0) if t < w else 0.85
	else:
		var spd := Vector2(velocity.x, velocity.z).length()
		if spd > 0.15 and body != "plant":
			anim = "run" if body == "wolf" else "walk"
			_walk_phase = fmod(_walk_phase + delta * spd / (1.7 if body == "wolf" else 0.55), 1.0)
			tt = _walk_phase
	rig.pose(anim, tt)
	if sprite:
		var n := BeastRig.frames_of(body, anim)
		var f := int(tt) if anim in ["bite", "claw", "spit"] else mini(int(tt * n), n - 1)
		var dir := posmod(roundi(rig.rotation.y / (TAU / BeastRig.DIRECTIONS)), BeastRig.DIRECTIONS)
		sprite.set_frame(BeastRig.column_for(body, anim, f), dir)
		sprite.set_flash(Color(1, 1, 1, _flash * 0.85))
