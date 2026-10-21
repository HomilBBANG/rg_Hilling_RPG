class_name CutsceneRunner
extends Node
## Plays a cutscene's step list (res://data/cutscenes/<cutscene_id>.json) in the running game.
## Called from a dialogue's CutsceneCall node. The camera stays the fixed top-down camera: steps
## only show captions, wait, move / turn actors and set flags. Full timeline editing is out of scope.
##
## { "version": 1, "cutscene_id": "cutscene.cat.first_appearance", "title": "", "test_only": true,
##   "steps": [ {"type": "caption", "text": "", "seconds": 2.0},
##              {"type": "wait", "seconds": 0.5},
##              {"type": "actor_move", "actor": "cat", "to": "player", "offset": [1.0, 0.8], "speed": 2.0},
##              {"type": "actor_face", "actor": "cat", "target": "player"},
##              {"type": "set_flag", "key": "", "value": true} ] }

signal finished

const STEP_TYPES := ["caption", "wait", "actor_move", "actor_face", "set_flag"]
const MAX_MOVE_SECONDS := 6.0

var playing := false
var _skip := false


static func info(cutscene_id: String) -> Dictionary:
	return DialogueData.cutscenes().get(cutscene_id, {})


## Advance key: finish the current caption / wait early (no whole-cutscene skip yet).
func hurry() -> void:
	_skip = true


func play(cutscene_id: String) -> void:
	var data := info(cutscene_id)
	playing = true
	if data.is_empty():
		push_warning("[cutscene] unknown id " + cutscene_id)
	for s: Dictionary in data.get("steps", []):
		_skip = false
		match s.get("type", ""):
			"caption":
				if Game.hud:
					Game.hud.show_caption(str(s.get("text", "")))
				await _wait(float(s.get("seconds", 2.0)))
				if Game.hud:
					Game.hud.show_caption("")
			"wait":
				await _wait(float(s.get("seconds", 0.5)))
			"actor_move":
				await _move(s)
			"actor_face":
				var a := _actor(str(s.get("actor", "")))
				var p := _player()
				if a and p and a.has_method("face"):
					a.face(p.global_position)
			"set_flag":
				Game.narrative.set_flag(str(s.get("key", "")), bool(s.get("value", true)))
	playing = false
	finished.emit()


func _wait(t: float) -> void:
	var left := t
	while left > 0.0 and not _skip:
		await get_tree().process_frame
		left -= get_process_delta_time()


func _player() -> Node3D:
	var w: Node = Game.boot.world if Game.boot else null
	return w.get("player") if w else null


func _actor(id: String) -> Node3D:
	var w: Node = Game.boot.world if Game.boot else null
	if w == null:
		return null
	match id:
		"cat":
			return w.get("cat")
		"player":
			return _player()
	for n in w.get("npcs") if w.get("npcs") != null else []:
		if n.look == id:
			return n
	return null


## Walks a scripted actor toward the target; the cat uses its own scripted-move hook.
func _move(s: Dictionary) -> void:
	var a := _actor(str(s.get("actor", "")))
	if a == null:
		return
	var off: Array = s.get("offset", [0, 0])
	var goal: Vector3
	if str(s.get("to", "player")) == "player" and _player():
		goal = _player().global_position + Vector3(float(off[0]), 0, float(off[1]))
	else:
		var to: Array = s.get("to", [0, 0])
		goal = Vector3(float(to[0]), 0, float(to[1]))
	var speed := float(s.get("speed", 2.0))
	if a.has_method("scripted_walk_to"):
		a.scripted_walk_to(goal, speed)
		var t := 0.0
		while a.call("scripted_walking") and t < MAX_MOVE_SECONDS and not _skip:
			await get_tree().process_frame
			t += get_process_delta_time()
		a.scripted_walk_to(Vector3.INF, 0.0)
	else:
		a.global_position = Vector3(goal.x, a.global_position.y, goal.z)
