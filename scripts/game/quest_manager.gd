class_name QuestManager
extends RefCounted
## Runtime quest progress (Game.quests). GDD 13 [확정]: NPC / board requests are accepted
## directly, field events start without acceptance, ordinary requests have no time limit, repeat
## requests can be retaken after failure, rewards may be general EXP, life EXP or both (plus gold /
## items). Accept / complete are idempotent so a replayed dialogue never pays twice.

signal changed

## quest id -> {"state": "active"|"completed"|"failed", "progress": {obj: n}, "accepted_at": minutes,
##              "completions": n, "outcome": String}
var entries := {}


func _q(id: String) -> Dictionary:
	return QuestDB.info(id)


## "none" | "active" | "ready" (all objectives met, not reported) | "completed" | "failed"
func state(id: String) -> String:
	var e: Dictionary = entries.get(id, {})
	if e.is_empty():
		return "none"
	if e["state"] == "active" and objectives_done(id):
		return "ready"
	return e["state"]


func is_open(id: String) -> bool:
	return state(id) in ["active", "ready"]


func can_accept(id: String) -> bool:
	var q := _q(id)
	if q.is_empty():
		return false
	var s := state(id)
	if s == "none":
		return true
	return q.get("repeatable", false) and s in ["completed", "failed"]


## Returns "" on success, otherwise why nothing happened.
func accept(id: String) -> String:
	var q := _q(id)
	if q.is_empty():
		return "알 수 없는 퀘스트 %s" % id
	if is_open(id):
		return "이미 진행 중"
	if not can_accept(id):
		return "이미 끝난 의뢰" if state(id) == "completed" else "다시 받을 수 없다"
	var prev: Dictionary = entries.get(id, {})
	entries[id] = {"state": "active", "progress": {}, "accepted_at": Game.total_minutes(),
		"completions": prev.get("completions", 0), "outcome": ""}
	Game.combat_log.add("퀘스트 시작: %s" % q.get("title", id), "%s — %s" % [QuestDB.SOURCE_NAMES.get(q.get("source", ""), ""), q.get("desc", "")], "info")
	if Game.hud:
		Game.hud.toast_quest("퀘스트 시작: " + q.get("title", id))
	changed.emit()
	return ""


func objective_progress(id: String, o: Dictionary) -> int:
	var e: Dictionary = entries.get(id, {})
	var need := int(o.get("count", 1))
	match o.get("type", ""):
		"collect":
			return mini(Game.player_state.inventory.count(str(o.get("item", ""))), need)
		"flag":
			return 1 if Game.narrative.get_flag(str(o.get("flag", ""))) else 0
	return mini(int(e.get("progress", {}).get(o.get("id", ""), 0)), need)


func objective_need(o: Dictionary) -> int:
	return 1 if o.get("type", "") == "flag" else int(o.get("count", 1))


func objectives_done(id: String) -> bool:
	for o: Dictionary in _q(id).get("objectives", []):
		if objective_progress(id, o) < objective_need(o):
			return false
	return true


func advance(id: String, obj_id: String, n := 1) -> String:
	if not is_open(id):
		return "퀘스트 %s가 진행 중이 아니다" % id
	var o := QuestDB.objective(id, obj_id)
	if o.is_empty():
		return "목표 %s 없음" % obj_id
	var was_ready := state(id) == "ready"
	var prog: Dictionary = entries[id]["progress"]
	prog[obj_id] = mini(int(prog.get(obj_id, 0)) + n, objective_need(o))
	_after_progress(id, was_ready)
	return "%s: %s %d/%d" % [QuestDB.title(id), o.get("text", obj_id), objective_progress(id, o), objective_need(o)]


func _after_progress(_id: String, _was_ready: bool) -> void:
	changed.emit()  # the "objectives met" toast comes from update()


## Kill objectives match the monster id prefix (meadow_*, forest_*).
func on_kill(monster_id: String) -> void:
	for id: String in entries:
		if not is_open(id):
			continue
		for o: Dictionary in _q(id).get("objectives", []):
			if o.get("type", "") == "kill" and monster_id.begins_with(str(o.get("target", "?"))):
				var was_ready := state(id) == "ready"
				var prog: Dictionary = entries[id]["progress"]
				if int(prog.get(o["id"], 0)) < objective_need(o):
					prog[o["id"]] = int(prog.get(o["id"], 0)) + 1
					Game.combat_log.add("%s: %s %d/%d" % [QuestDB.title(id), o.get("text", ""), objective_progress(id, o), objective_need(o)], "", "info")
					_after_progress(id, was_ready)


## Collect objectives read the bag live, so "objectives met" is detected by polling.
func _check_ready() -> void:
	for id: String in entries:
		if entries[id]["state"] == "active":
			var ready := objectives_done(id)
			if ready != entries[id].get("_ready", false):
				entries[id]["_ready"] = ready
				if ready and Game.hud:
					Game.hud.toast_quest("목표 달성: %s — 보고하러 가자" % QuestDB.title(id))
				changed.emit()


## Hand in: requires every objective, consumes collected items, pays the (outcome's) rewards.
func complete(id: String, outcome := "") -> String:
	var q := _q(id)
	if state(id) != "ready":
		return "퀘스트 %s: 아직 완료할 수 없다 (%s)" % [q.get("title", id), state(id)]
	if outcome != "" and not q.get("outcomes", {}).has(outcome):
		return "퀘스트 %s: 결과 '%s'가 없다" % [id, outcome]
	if q.get("consume_items", true):
		for o: Dictionary in q.get("objectives", []):
			if o.get("type", "") == "collect":
				Game.player_state.inventory.remove(str(o["item"]), int(o.get("count", 1)))
	var r := QuestDB.rewards_for(id, outcome)
	var st := Game.player_state
	if int(r.get("gen_exp", 0)) > 0:
		st.add_exp(int(r["gen_exp"]))
	st.life_exp += int(r.get("life_exp", 0))
	st.gold += int(r.get("gold", 0))
	var items: Dictionary = r.get("items", {})
	for item_id: String in items:
		st.inventory.add(item_id, int(items[item_id]))  # rewards are handed over even when heavy
	var e: Dictionary = entries[id]
	e["state"] = "completed"
	e["outcome"] = outcome
	e["completions"] = int(e.get("completions", 0)) + 1
	var label := str(q.get("outcomes", {}).get(outcome, {}).get("label", ""))
	var text := "퀘스트 완료: %s%s — 보상 %s" % [q.get("title", id), " (%s)" % label if label != "" else "", QuestDB.reward_text(r)]
	Game.combat_log.add(text, "", "info")
	if Game.hud:
		Game.hud.toast_quest(text)
	st.changed.emit()
	changed.emit()
	return text


func fail(id: String, why: String) -> void:
	if not is_open(id):
		return
	entries[id]["state"] = "failed"
	var q := _q(id)
	var text := "퀘스트 실패: %s — %s%s" % [q.get("title", id), why, " (다시 받을 수 있다)" if q.get("repeatable", false) else ""]
	Game.combat_log.add(text, "", "hurt")
	if Game.hud:
		Game.hud.toast_quest(text)
	changed.emit()


## Minutes left on a timed quest, or -1 without a limit.
func time_left(id: String) -> float:
	var hours := float(_q(id).get("time_limit_hours", 0))
	if hours <= 0.0 or not is_open(id):
		return -1.0
	return maxf(0.0, hours * 60.0 - (Game.total_minutes() - float(entries[id]["accepted_at"])))


## Called every frame by Game: time limits and the "objectives met" toast.
func update() -> void:
	_check_ready()
	for id: String in entries.keys():
		if is_open(id) and float(_q(id).get("time_limit_hours", 0)) > 0.0 and time_left(id) <= 0.0:
			fail(id, "제한 시간이 지났다")


## Field events (accept "auto") start when the player walks into their trigger area.
func check_triggers(pos: Vector3) -> void:
	for id: String in QuestDB.all():
		var q: Dictionary = QuestDB.all()[id]
		if q.get("accept", "") != "auto" or not q.has("trigger") or state(id) != "none":
			continue
		var t: Dictionary = q["trigger"]
		var p: Array = t.get("pos", [0, 0])
		if t.get("type", "") == "reach" and Vector2(pos.x - float(p[0]), pos.z - float(p[1])).length() <= float(t.get("radius", 5)):
			accept(id)


func objectives_text(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for o: Dictionary in _q(id).get("objectives", []):
		var have := objective_progress(id, o)
		var need := objective_need(o)
		out.append("%s %s %d/%d" % ["✔" if have >= need else "·", o.get("text", o.get("id", "")), have, need])
	return out
