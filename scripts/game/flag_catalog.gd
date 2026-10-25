@tool
class_name FlagCatalog
extends RefCounted
## Every story flag the project knows and where it comes from, for the editors' pickers and the
## "플래그 목록" dialog. A flag is a named on/off switch in the save (NarrativeState): something sets
## it (game code, a dialogue action, a cutscene step, a story spot in a region) and something reads
## it (a dialogue condition, a quest objective). Events ("event.<id>") are flags too: an End node
## or the 이벤트 완료 기록 action sets them once.
##
## all() -> {flag: {"desc": String, "origin": String, "set_by": PackedStringArray, "used_by": PackedStringArray}}

## What the game code's own flags mean (QuestDB.CODE_FLAGS).
const CODE_FLAG_DESC := {
	"story.arrived": "새 세상에 떨어짐 (새 게임 시작)",
	"story.new_game_seen": "새 게임 컷씬을 끝까지 봄",
	"story.pass_reached": "잿빛 산길에 도착함",
	"story.nest_found": "드래곤 둥지 입구를 찾음",
	"story.nest_entered": "드래곤 둥지 안에 들어감",
	"story.dragon_signs": "불탄 짐수레(드래곤 흔적)를 봄",
	"story.dragon_met": "드래곤을 만남",
	"story.dragon_angry": "드래곤이 화나서 공격 중",
	"story.dragon_left": "드래곤을 말로 내보냄",
	"story.camper_received": "소원으로 캠핑카를 받음",
	"story.king_dead": "왕이 캠핑카에 깔림",
	"story.wanted": "수배됨 (왕도 출입 불가)",
	"story.escaped": "왕도에서 탈출함 (섬 전체가 적)",
	"story.portal_entered": "포탈에 들어감 — 챕터 1 끝",
	"story.chapter1_done": "챕터 1 완료",
	"story.chapter1_note": "챕터 1 끝 안내문을 봄",
}

static var _cache := {}
static var _cache_time := -1


static func all() -> Dictionary:
	var now := Time.get_ticks_msec() / 1000
	if now == _cache_time:
		return _cache
	_cache_time = now
	var out := {}
	var add := func(flag: String, how: String, who: String, desc := "") -> void:
		if flag == "":
			return
		if not out.has(flag):
			out[flag] = {"desc": desc, "origin": "", "set_by": PackedStringArray(), "used_by": PackedStringArray()}
		if desc != "" and out[flag]["desc"] == "":
			out[flag]["desc"] = desc
		var arr: PackedStringArray = out[flag][how]
		if not arr.has(who):
			arr.append(who)
		out[flag][how] = arr
	for f: String in QuestDB.CODE_FLAGS:
		add.call(f, "set_by", "게임 코드", CODE_FLAG_DESC.get(f, ""))
	for p in DialogueData.list_files(DialogueData.DIALOGUE_DIR):
		var d: Variant = DialogueData.read_json(p)
		if not d is Dictionary:
			continue
		var did := str(d.get("dialogue_id", p.get_file().get_basename()))
		var title := str(d.get("metadata", {}).get("title", ""))
		var where := "대화 '%s'" % (title if title != "" else did)
		for n: Dictionary in d.get("nodes", []):
			var nid := str(n.get("id", ""))
			match str(n.get("type", "")):
				"action":
					var a := str(n.get("action", ""))
					if a == "set_flag":
						add.call(str(n.get("args", {}).get("key", "")), "set_by", "%s · 노드 %s (액션 플래그 설정)" % [where, nid])
					elif a == "mark_event_complete":
						add.call("event." + str(n.get("args", {}).get("event_id", "")), "set_by", "%s · 노드 %s (이벤트 완료 기록)" % [where, nid], "이벤트")
				"condition":
					_add_check(add, n.get("check", {}), "%s · 조건 노드 %s" % [where, nid])
				"choice":
					for o: Dictionary in n.get("options", []):
						var oc: Variant = o.get("condition", {})
						if oc is Dictionary and not (oc as Dictionary).is_empty():
							_add_check(add, oc, "%s · 선택지 %s '%s'" % [where, nid, o.get("text", "")])
				"end":
					var ev := str(n.get("complete_event", ""))
					if ev != "":
						add.call("event." + ev, "set_by", "%s · 종료 노드 %s" % [where, nid], "이벤트")
	for p in DialogueData.list_files(DialogueData.CUTSCENE_DIR):
		var d: Variant = DialogueData.read_json(p)
		if not d is Dictionary:
			continue
		var cid := str(d.get("cutscene_id", p.get_file().get_basename()))
		var steps: Array = d.get("steps", [])
		for i in steps.size():
			var s: Dictionary = steps[i]
			if s.get("type", "") == "set_flag":
				add.call(str(s.get("key", "")), "set_by", "컷씬 '%s' · %d번째 단계" % [cid, i + 1])
	for qid: String in QuestDB.all():
		var q: Dictionary = QuestDB.all()[qid]
		for o: Dictionary in q.get("objectives", []):
			if o.get("type", "") == "flag":
				add.call(str(o.get("flag", "")), "used_by", "퀘스트 '%s' · 목표 %s" % [q.get("title", qid), o.get("id", "")])
	for rid: String in RegionDB.all():
		var r: Dictionary = RegionDB.all()[rid]
		for t: Dictionary in r.get("story_triggers", []) if r.get("story_triggers") is Array else []:
			add.call(str(t.get("flag", "")), "set_by", "지역 '%s' · 이야기 장소 %s (밟으면)" % [r.get("name", rid), t.get("id", "")])
	for f: String in out:
		var e: Dictionary = out[f]
		if f.begins_with("event."):
			e["origin"] = "이벤트"
		elif QuestDB.CODE_FLAGS.has(f):
			e["origin"] = "게임"
		elif (e["set_by"] as PackedStringArray).is_empty():
			e["origin"] = "읽기만"
		else:
			e["origin"] = str(e["set_by"][0]).get_slice(" ", 0)
	_cache = out
	return out


static func _add_check(add: Callable, check: Dictionary, where: String) -> void:
	match str(check.get("kind", "")):
		"flag":
			add.call(str(check.get("key", "")), "used_by", where)
		"event":
			add.call("event." + str(check.get("event_id", "")), "used_by", where, "이벤트")


## Sorted flag names (events excluded unless with_events).
static func names(with_events := false) -> PackedStringArray:
	var out := PackedStringArray()
	for f: String in all():
		if with_events or not f.begins_with("event."):
			out.append(f)
	out.sort()
	return out


## Sorted event ids (without the "event." prefix).
static func event_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f: String in all():
		if f.begins_with("event."):
			out.append(f.trim_prefix("event."))
	out.sort()
	return out


## One-line label for pickers: "story.wanted — 수배됨 [게임]".
static func label(flag: String) -> String:
	var e: Dictionary = all().get(flag, {})
	if e.is_empty():
		return flag
	var d := str(e["desc"])
	return "%s — %s [%s]" % [flag, d, e["origin"]] if d != "" else "%s [%s]" % [flag, e["origin"]]


## Multi-line explanation for an info label.
static func describe(flag: String) -> String:
	if flag == "":
		return "플래그 = 이야기 진행을 기억하는 이름표(켜짐/꺼짐). 위 목록에서 고르거나 새 이름을 적으면 됩니다 (예: story.met_rosa)."
	var e: Dictionary = all().get(flag, {})
	if e.is_empty():
		return "'%s'는 새 플래그입니다. 어딘가에서 켜 줘야 합니다 (대화 액션 '플래그 설정', 컷씬 단계, 지역의 이야기 장소)." % flag
	var parts := PackedStringArray()
	if str(e["desc"]) != "":
		parts.append("뜻: " + str(e["desc"]))
	parts.append("켜는 곳: " + (", ".join(e["set_by"]) if not (e["set_by"] as PackedStringArray).is_empty() else "없음 — 아직 아무도 켜지 않음!"))
	parts.append("쓰는 곳: " + (", ".join(e["used_by"]) if not (e["used_by"] as PackedStringArray).is_empty() else "없음"))
	return "\n".join(parts)
