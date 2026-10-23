class_name CutsceneRunner
extends Node
## Plays a cutscene (CutsceneData format, res://data/cutscenes/<cutscene_id>.json) in the running
## game: from a dialogue's CutsceneCall node, from the new-game story sequence (data/story.json)
## or from the editor's "게임에서 실행". The camera stays the fixed top-down camera; steps draw
## on the CutsceneOverlay (illustration, narration, letterbox, fade), speak through the dialogue
## window (line), show captions, wait, move / turn actors and set flags.
##
## Keys: E / Space / Enter / click = next (finish typing, skip a wait); ESC = skip the whole
## cutscene when it is "skippable". Skipping still applies what the steps change (flags, where
## actors end up, what the screen ends on). The player is locked while it plays and the HUD hides.

signal finished

const MAX_MOVE_SECONDS := 6.0

var playing := false
var current := ""
var step_index := -1
var skippable := false
var overlay: CutsceneOverlay
var dialogue: DialogueBox
var _skip := false       # finish the current step
var _skip_all := false   # finish every remaining step at once
var _advance := false    # a key press waiting to be used by a line / narration
var _locked_player := false
var _partner := ""


static func info(cutscene_id: String) -> Dictionary:
	return DialogueData.cutscenes().get(cutscene_id, {})


## Advance key: finish typing / the current wait, or go on from a narration or line.
func hurry() -> void:
	_skip = true
	_advance = true


func skip_all() -> void:
	if playing and skippable:
		_skip_all = true
		_skip = true
		_advance = true


## Key routing while a cutscene plays on its own (bootstrap). Returns true when used.
func handle_key(ev: InputEvent) -> bool:
	if ev.is_action("interact") or (ev is InputEventKey and ev.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]):
		hurry()
		return true
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		hurry()
		return true
	return false


## keep_black: leave the screen black at the end (the next cutscene in a sequence fades in).
func play(cutscene_id: String, keep_black := false) -> void:
	var data := info(cutscene_id)
	if data.is_empty():
		push_warning("[cutscene] unknown id " + cutscene_id)
	playing = true
	current = cutscene_id
	skippable = bool(data.get("skippable", false))
	_skip_all = false
	_partner = ""
	for s: Dictionary in data.get("steps", []):
		var sp := str(s.get("speaker_id", ""))
		if s.get("type", "") == "line" and sp not in ["", "player", "narrator"]:
			_partner = sp
			break
	var p := _player()
	_locked_player = p != null and p.controls_enabled
	if _locked_player:
		p.set_talking(true)
	var steps: Array = data.get("steps", [])
	for i in steps.size():
		step_index = i
		_skip = _skip_all
		_advance = false
		await _step(steps[i])
	step_index = -1
	if dialogue:
		dialogue.end_cutscene_line()
	if Game.hud:
		Game.hud.show_caption("")
	if overlay:
		var was_black := overlay.is_black()
		overlay.reset(true)
		if was_black and not keep_black:
			await overlay.fade(false, 0.4).finished
	if _locked_player and is_instance_valid(p):
		p.set_talking(false)
	playing = false
	current = ""
	finished.emit()


func _step(s: Dictionary) -> void:
	match s.get("type", ""):
		"fade":
			if overlay:
				var tw := overlay.fade(s.get("to", "black") == "black", 0.0 if _skip_all else float(s.get("seconds", 1.0)))
				await _until_tween(tw)
		"image":
			if overlay:
				var tw := overlay.show_image(str(s.get("path", "")), 0.0 if _skip_all else float(s.get("seconds", 0.6)))
				await _until_tween(tw)
		"narration":
			if overlay:
				overlay.show_narration(str(s.get("text", "")), _skip_all)
				_advance = false
				while overlay.narration_revealing() and not _advance:
					await get_tree().process_frame
				overlay.finish_reveal()
				_advance = false
				_skip = _skip_all  # the key that finished the typing doesn't also skip the hold
				var secs := float(s.get("seconds", 0.0))
				if secs > 0.0:
					await _wait(secs)
				else:
					await _wait_advance()
				await _until_tween(overlay.hide_narration(0.0 if _skip_all else 0.25))
		"line":
			if dialogue and not _skip_all:
				dialogue.present_cutscene_line(str(s.get("speaker_id", "")), str(s.get("text", "")), str(s.get("expression", "")), _partner)
				_advance = false
				await _wait_advance()
		"caption":
			if Game.hud:
				Game.hud.show_caption(str(s.get("text", "")))
			await _wait(float(s.get("seconds", 2.0)))
			if Game.hud:
				Game.hud.show_caption("")
		"wait":
			await _wait(float(s.get("seconds", 0.5)))
		"letterbox":
			if overlay:
				await _until_tween(overlay.set_letterbox(bool(s.get("on", true)), 0.0 if _skip_all else 0.5))
		"actor_move":
			await _move(s)
		"actor_face":
			var a := _actor(str(s.get("actor", "")))
			var b := _actor(str(s.get("target", "player")))
			if a and b:
				if a is PrototypePlayer:
					var d := b.global_position - a.global_position
					(a as PrototypePlayer).face_direction(atan2(-d.x, -d.z))
				elif a.has_method("face"):
					a.face(b.global_position)
		"quest":
			var qid := str(s.get("quest_id", ""))
			if s.get("action", "accept") == "complete":
				Game.quests.complete(qid, "")
			else:
				Game.quests.accept(qid)
		"set_flag":
			Game.narrative.set_flag(str(s.get("key", "")), bool(s.get("value", true)))
		"camper_drop":
			var w: Node = Game.boot.world if Game.boot else null
			var who := _actor(str(s.get("target", "king")))
			if w and w.has_method("drop_camper"):
				var at: Vector3 = who.global_position if who else Vector3(Game.camper.get("pos", Vector3.ZERO))
				await w.drop_camper(at, 0.0 if _skip_all else float(s.get("seconds", 1.0)), who)
		"actor_hide":
			var h := _actor(str(s.get("actor", "")))
			if h:
				h.visible = false
	if dialogue and s.get("type", "") != "line":
		dialogue.end_cutscene_line()


func _wait(t: float) -> void:
	var left := t
	while left > 0.0 and not _skip:
		await get_tree().process_frame
		left -= get_process_delta_time()


func _wait_advance() -> void:
	while not _advance and not _skip_all:
		await get_tree().process_frame


func _until_tween(tw: Tween) -> void:
	while tw and tw.is_valid() and tw.is_running():
		if _skip_all:
			tw.custom_step(100.0)
			break
		await get_tree().process_frame


func _player() -> PrototypePlayer:
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


## Walks an actor toward the target (another actor + offset, or a point). The player and the cat
## walk with their own movement; other actors are placed there.
func _move(s: Dictionary) -> void:
	var a := _actor(str(s.get("actor", "")))
	if a == null:
		return
	var off: Array = s.get("offset", [0, 0])
	var to: Variant = s.get("to", "player")
	var goal: Vector3
	if to is String:
		var target := _actor(to)
		if target == null:
			return
		goal = target.global_position + Vector3(float(off[0]), 0, float(off[1]))
	else:
		goal = Vector3(float(to[0]) + float(off[0]), 0, float(to[1]) + float(off[1]))
	var speed := float(s.get("speed", 2.0))
	if a is PrototypePlayer:
		var pl := a as PrototypePlayer
		pl.scripted_running = speed >= 4.0
		var t := 0.0
		while t < MAX_MOVE_SECONDS and not _skip_all:
			var d := Vector2(goal.x - pl.global_position.x, goal.z - pl.global_position.z)
			if d.length() < 0.15:
				break
			pl.scripted_move = d.normalized() * clampf(d.length() * 2.0, 0.35, 1.0)
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		pl.scripted_move = Vector2.ZERO
		pl.scripted_running = false
		if _skip_all:
			pl.global_position = Vector3(goal.x, pl.global_position.y, goal.z)
	elif a.has_method("scripted_walk_to"):
		a.scripted_walk_to(goal, speed)
		var t := 0.0
		while a.call("scripted_walking") and t < MAX_MOVE_SECONDS and not _skip_all:
			await get_tree().process_frame
			t += get_process_delta_time()
		a.scripted_walk_to(Vector3.INF, 0.0)
		if _skip_all:
			a.global_position = Vector3(goal.x, a.global_position.y, goal.z)
	else:
		a.global_position = Vector3(goal.x, a.global_position.y, goal.z)
