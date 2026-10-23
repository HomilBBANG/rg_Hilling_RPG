class_name EscapeSequence
extends Node
## Chapter 1's last stretch (user story): the camper fell on the king, the hero is wanted and
## flees in the camper. Guards (Npc look "guard") run after the camper through the capital; reaching
## the south gate (the south_road exit, bootstrap.travel) is the escape. A guard at a camper that
## has (almost) stopped — or at the hero on foot — catches up: back to the plaza and try again.
## Positions: data/story.json "wish_ceremony" (camper_wish = where the camper starts).

const CATCH_RADIUS := 1.9
const CATCH_SECONDS := 1.0
const SLOW_SPEED := 2.0
const GRACE_SECONDS := 3.0  ## after a (re)start: guards gape for a moment, nobody can catch yet

var world: VisualLab
var guards: Array[Npc] = []
var caught_count := 0
var _catch_t := 0.0
var _grace := 0.0
var _resetting := false
var _spec := {}
var _guard_homes: Array[Vector3] = []


func begin() -> void:
	_spec = CutsceneData.story().get("wish_ceremony", {})
	for n in world.npcs:  # the ceremony guards join the chase
		if n.look == "guard":
			guards.append(n)
			_guard_homes.append(n.global_position)
	for p: Array in _spec.get("escape_guards", []):
		var g := world.spawn_story_npc("guard", Vector3(float(p[0]), 0, float(p[1])), PI)
		guards.append(g)
		_guard_homes.append(g.global_position)
	for g in guards:
		g.set_solid(false)
		g.chase_speed = 4.2
	_place_start()
	if Game.hud:
		Game.hud.toast_quest("수배! 경비병에게 붙잡히기 전에 캠핑카를 몰고 남문으로 도망쳐라")


func _place_start() -> void:
	var w: Dictionary = CutsceneData.story().get("camper_wish", {})
	var p := RegionDB.v3(w.get("pos", [0, 0]))
	world.vehicle.speed = 0.0
	world.vehicle.global_position = Vector3(p.x, world.ground_height(p.x, p.z), p.z)
	world.vehicle.rotation.y = float(w.get("yaw", -PI * 0.5))
	world.vehicle.visible = true
	if not world.vehicle.driving:
		world.enter_vehicle()
	world.camera.snap_to_target()
	_grace = GRACE_SECONDS
	_catch_t = 0.0


func target() -> Node3D:
	return world.vehicle if world.vehicle.driving else world.player


func _physics_process(delta: float) -> void:
	if _resetting or Game.narrative.get_flag("story.escaped"):
		for g in guards:
			if is_instance_valid(g):
				g.chase = null
		return
	if Game.hud and (Game.hud.dialogue_active() or (Game.hud.cutscene and Game.hud.cutscene.playing)):
		return
	_grace = maxf(0.0, _grace - delta)
	var t := target()
	if _grace > GRACE_SECONDS - 1.2:  # the guards gape at the crushed king before they react
		for g in guards:
			if is_instance_valid(g):
				g.chase = null
		return
	var slow := not world.vehicle.driving or absf(world.vehicle.speed) < SLOW_SPEED
	var near := false
	for g in guards:
		if not is_instance_valid(g):
			continue
		g.chase = t
		var d := Vector2(g.global_position.x - t.global_position.x, g.global_position.z - t.global_position.z).length()
		near = near or d < CATCH_RADIUS + (1.6 if world.vehicle.driving else 0.0)
	_catch_t = _catch_t + delta if near and slow and _grace <= 0.0 else maxf(0.0, _catch_t - delta * 2.0)
	if _catch_t >= CATCH_SECONDS:
		_caught()


func _caught() -> void:
	_resetting = true
	_catch_t = 0.0
	caught_count += 1
	for g in guards:
		g.chase = null
	if Game.hud:
		await Game.hud.fade_to(1.0, 0.5, "경비병에게 붙잡힐 뻔했다…!\n\n다시 — 멈추지 말고 남문까지 달려라")
	for i in guards.size():
		var h := _guard_homes[i]
		guards[i].global_position = Vector3(h.x, world.ground_height(h.x, h.z), h.z)
	if world.vehicle.driving:
		world.vehicle.speed = 0.0
	_place_start()
	await get_tree().create_timer(0.3).timeout
	if Game.hud:
		await Game.hud.fade_to(0.0, 0.5)
	_resetting = false
