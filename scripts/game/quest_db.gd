@tool
class_name QuestDB
extends RefCounted
## Quest definitions as data (res://data/quests/<quest_id>.json), so new quests need no code.
##
## { "version": 1, "quest_id": "quest.rosa.jelly", "title": "", "desc": "",
##   "giver": "rosa",            speaker id (data/speakers.json)
##   "source": "npc" | "board" | "event" | "story",   GDD 13.1 acquisition routes (story = main line)
##   "accept": "direct" | "auto",           formal requests are accepted directly; field events start on their own
##   "repeatable": false,                   repeat requests can be retaken after success or failure (13.3)
##   "time_limit_hours": 0,                 0 = no limit (13.3: only urgent / special quests)
##   "objectives": [ {"id": "jelly", "type": "collect", "item": "slime_jelly", "count": 5, "text": ""},
##                   {"id": "slimes", "type": "kill", "target": "meadow", "count": 4},
##                   {"id": "talk", "type": "count", "count": 1},   advanced by quest_advance actions
##                   {"id": "seen", "type": "flag", "flag": "some.flag"} ],
##   "consume_items": true,               collect items are handed over on completion
##   "rewards": {"gen_exp": 0, "life_exp": 0, "gold": 0, "items": {"bread": 2}, "recipes": []},   13.4 / 14.4
##   "outcomes": {"key": {"label": "", "rewards": {...}}},   optional alternative resolutions (13.2)
##   "trigger": {"type": "reach", "region": "meadow", "pos": [x, z], "radius": 6},   auto events only
##   "test_only": true }                   placeholder data, not real story content

const DIR := "res://data/quests"
const SOURCE_NAMES := {"npc": "NPC 의뢰", "board": "게시판 의뢰", "event": "현장 사건", "story": "메인 이야기"}
const ACCEPT_NAMES := {"direct": "직접 수락 (대화·게시판·컷씬)", "auto": "자동 시작 (현장에 닿으면)"}
const OBJECTIVE_TYPES := {"collect": "아이템 모으기", "kill": "몬스터 처치", "count": "횟수 (대화·컷씬이 올림)", "flag": "이야기 플래그"}
## Flags the game code itself sets (data files can set more with set_flag actions / steps).
const CODE_FLAGS := ["story.arrived", "story.new_game_seen", "story.pass_reached", "story.nest_found", "story.nest_entered",
	"story.dragon_signs", "story.dragon_met", "story.dragon_angry", "story.dragon_left", "story.camper_received",
	"story.king_dead", "story.wanted", "story.escaped", "story.chapter1_done", "story.chapter1_note"]

static var _cache := {}
static var _cache_time := -1


static func all() -> Dictionary:
	# Re-read at most once a second so the editor sees freshly added files.
	var now := Time.get_ticks_msec() / 1000
	if now != _cache_time:
		_cache_time = now
		_cache = {}
		for p in DialogueData.list_files(DIR):
			var d: Variant = DialogueData.read_json(p)
			if d is Dictionary and d.has("quest_id"):
				_cache[d["quest_id"]] = d
	return _cache


static func reload() -> void:
	_cache_time = -1


static func path_for(quest_id: String) -> String:
	return DIR.path_join(quest_id + ".json")


static func valid_id(id: String) -> bool:
	return id.begins_with("quest.") and id.length() > 6 and id.is_valid_filename() and not id.contains(" ")


static func info(quest_id: String) -> Dictionary:
	return all().get(quest_id, {})


static func title(quest_id: String) -> String:
	return str(info(quest_id).get("title", quest_id))


static func objective(quest_id: String, obj_id: String) -> Dictionary:
	for o: Dictionary in info(quest_id).get("objectives", []):
		if o.get("id", "") == obj_id:
			return o
	return {}


static func rewards_for(quest_id: String, outcome := "") -> Dictionary:
	var q := info(quest_id)
	if outcome != "" and q.get("outcomes", {}).has(outcome):
		return q["outcomes"][outcome].get("rewards", {})
	return q.get("rewards", {})


static func reward_text(r: Dictionary) -> String:
	var parts := PackedStringArray()
	if int(r.get("gen_exp", 0)) > 0:
		parts.append("일반 EXP +%d" % int(r["gen_exp"]))
	if int(r.get("life_exp", 0)) > 0:
		parts.append("생활 EXP +%d" % int(r["life_exp"]))
	if int(r.get("gold", 0)) > 0:
		parts.append("%d 골드" % int(r["gold"]))
	var items: Dictionary = r.get("items", {})
	for id: String in items:
		parts.append("%s ×%d" % [ItemDB.item_name(id), int(items[id])])
	for rid in r.get("recipes", []):
		parts.append("레시피: %s" % RecipeDB.recipe_name(str(rid)))
	return ", ".join(parts) if not parts.is_empty() else "없음"


# ---------------------------------------------------------------- editor side (퀘스트 tab)

static func _rewards_normalized(r: Variant) -> Dictionary:
	var src: Dictionary = r if r is Dictionary else {}
	var out := {"gen_exp": int(src.get("gen_exp", 0)), "life_exp": int(src.get("life_exp", 0)), "gold": int(src.get("gold", 0)),
		"items": {}}
	var items: Variant = src.get("items", {})
	if items is Dictionary:
		for k in items:
			out["items"][str(k)] = int(items[k])
	var recipes: Variant = src.get("recipes", [])
	if recipes is Array and not recipes.is_empty():
		var rs := []
		for x in recipes:
			rs.append(str(x))
		out["recipes"] = rs
	return out


## Stable key order and integer numbers so a saved file diffs cleanly; missing keys get defaults.
static func normalized(d: Dictionary) -> Dictionary:
	var out := {"version": 1, "quest_id": str(d.get("quest_id", "")), "title": str(d.get("title", "")), "desc": str(d.get("desc", "")),
		"giver": str(d.get("giver", "")), "source": str(d.get("source", "npc")), "accept": str(d.get("accept", "direct")),
		"repeatable": bool(d.get("repeatable", false)), "time_limit_hours": DialogueData.intified(float(d.get("time_limit_hours", 0)))}
	if d.has("trigger") and d["trigger"] is Dictionary:
		var t: Dictionary = d["trigger"]
		var p: Variant = t.get("pos", [0, 0])
		out["trigger"] = {"type": str(t.get("type", "reach")), "region": str(t.get("region", "meadow")),
			"pos": [DialogueData.intified(float(p[0])), DialogueData.intified(float(p[1]))] if p is Array and p.size() >= 2 else [0, 0],
			"radius": DialogueData.intified(float(t.get("radius", 5)))}
	var objs := []
	for o: Variant in d.get("objectives", []):
		if not o is Dictionary:
			continue
		var t := str(o.get("type", "count"))
		var n := {"id": str(o.get("id", "")), "type": t}
		match t:
			"collect":
				n["item"] = str(o.get("item", ""))
				n["count"] = maxi(1, int(o.get("count", 1)))
			"kill":
				n["target"] = str(o.get("target", ""))
				n["count"] = maxi(1, int(o.get("count", 1)))
			"flag":
				n["flag"] = str(o.get("flag", ""))
			_:
				n["count"] = maxi(1, int(o.get("count", 1)))
		n["text"] = str(o.get("text", ""))
		objs.append(n)
	out["objectives"] = objs
	out["consume_items"] = bool(d.get("consume_items", true))
	out["rewards"] = _rewards_normalized(d.get("rewards", {}))
	var src_oc: Variant = d.get("outcomes", {})
	if src_oc is Dictionary and not (src_oc as Dictionary).is_empty():
		var oc := {}
		for k in src_oc:
			var v: Variant = src_oc[k]
			oc[str(k)] = {"label": str(v.get("label", "") if v is Dictionary else ""), "rewards": _rewards_normalized(v.get("rewards", {}) if v is Dictionary else {})}
		out["outcomes"] = oc
	if d.get("test_only", false):
		out["test_only"] = true
	return out


static func new_doc(quest_id: String, title := "") -> Dictionary:
	return normalized({"quest_id": quest_id, "title": title if title != "" else quest_id, "desc": "", "giver": "", "source": "npc",
		"accept": "direct", "objectives": [{"id": "obj_1", "type": "count", "count": 1, "text": "새 목표"}], "consume_items": true})


static func save(d: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(path_for(str(d["quest_id"])), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(normalized(d), "  ", false) + "\n")
	f.close()
	reload()
	return OK


## Where a quest is used: dialogue actions / conditions and cutscene quest steps.
## [{"kind": "dialogue"|"cutscene", "id": "...", "node": "...", "what": "수락"|"목표 진행"|"완료"|"조건"|...}]
static func references(quest_id: String) -> Array:
	var out := []
	for p in DialogueData.list_files(DialogueData.DIALOGUE_DIR):
		var d: Variant = DialogueData.read_json(p)
		if not d is Dictionary:
			continue
		for n: Dictionary in d.get("nodes", []):
			var nid := str(n.get("id", ""))
			if n.get("type", "") == "action" and str(n.get("args", {}).get("quest_id", "")) == quest_id:
				out.append({"kind": "dialogue", "id": str(d.get("dialogue_id", "")), "node": nid,
					"what": str(DialogueData.ACTIONS.get(n.get("action", ""), {}).get("label", n.get("action", ""))), "action": str(n.get("action", ""))})
			if n.get("type", "") == "condition" and str(n.get("check", {}).get("quest_id", "")) == quest_id:
				out.append({"kind": "dialogue", "id": str(d.get("dialogue_id", "")), "node": nid, "what": "조건", "action": ""})
			for o: Dictionary in n.get("options", []):
				if str(o.get("condition", {}).get("quest_id", "")) == quest_id:
					out.append({"kind": "dialogue", "id": str(d.get("dialogue_id", "")), "node": nid, "what": "선택지 조건", "action": ""})
	for p in DialogueData.list_files(DialogueData.CUTSCENE_DIR):
		var d: Variant = DialogueData.read_json(p)
		if not d is Dictionary:
			continue
		var steps: Array = d.get("steps", [])
		for i in steps.size():
			var s: Dictionary = steps[i]
			if s.get("type", "") == "quest" and str(s.get("quest_id", "")) == quest_id:
				out.append({"kind": "cutscene", "id": str(d.get("cutscene_id", "")), "node": "단계 %d" % (i + 1),
					"what": "시작" if s.get("action", "accept") == "accept" else "완료", "action": "quest_" + str(s.get("action", "accept"))})
	return out


## Flags that something sets: code flags + set_flag actions / steps in the data files.
static func known_flags() -> PackedStringArray:
	var out := PackedStringArray(CODE_FLAGS)
	for p in DialogueData.list_files(DialogueData.DIALOGUE_DIR):
		var d: Variant = DialogueData.read_json(p)
		if d is Dictionary:
			for n: Dictionary in d.get("nodes", []):
				if n.get("type", "") == "action" and n.get("action", "") == "set_flag":
					var k := str(n.get("args", {}).get("key", ""))
					if k != "" and not out.has(k):
						out.append(k)
	for p in DialogueData.list_files(DialogueData.CUTSCENE_DIR):
		var d: Variant = DialogueData.read_json(p)
		if d is Dictionary:
			for s: Dictionary in d.get("steps", []):
				if s.get("type", "") == "set_flag":
					var k2 := str(s.get("key", ""))
					if k2 != "" and not out.has(k2):
						out.append(k2)
	out.sort()
	return out


static func _validate_rewards(r: Dictionary, where: String, out: Array) -> void:
	for k in r.get("items", {}):
		if not ItemDB.ITEMS.has(str(k)):
			out.append({"severity": "error", "message": "%s: 없는 보상 아이템 '%s'" % [where, k]})
		elif int(r["items"][k]) < 1:
			out.append({"severity": "error", "message": "%s: 보상 아이템 '%s' 개수가 0" % [where, k]})
	for rid in r.get("recipes", []):
		if not RecipeDB.all().has(str(rid)):
			out.append({"severity": "error", "message": "%s: 없는 보상 레시피 '%s' (data/recipes.json)" % [where, rid]})
	for k in ["gen_exp", "life_exp", "gold"]:
		if int(r.get(k, 0)) < 0:
			out.append({"severity": "error", "message": "%s: %s가 음수" % [where, k]})


## [{"severity": "error"|"warning", "message": ""}]. refs = references(quest_id) when known (the
## "no way to get it" warning needs them; pass null to skip that check).
static func validate(d: Dictionary, refs: Variant = null) -> Array:
	var out := []
	var id := str(d.get("quest_id", ""))
	if not valid_id(id):
		out.append({"severity": "error", "message": "퀘스트 ID는 'quest.'로 시작하는 파일 이름이어야 한다 ('%s')" % id})
	if str(d.get("title", "")).strip_edges() == "":
		out.append({"severity": "error", "message": "제목이 비었다"})
	if str(d.get("desc", "")).strip_edges() == "":
		out.append({"severity": "warning", "message": "설명이 비었다 (퀘스트 기록에 보임)"})
	var source := str(d.get("source", ""))
	if not SOURCE_NAMES.has(source):
		out.append({"severity": "error", "message": "알 수 없는 종류 '%s'" % source})
	var accept := str(d.get("accept", ""))
	if not ACCEPT_NAMES.has(accept):
		out.append({"severity": "error", "message": "알 수 없는 받는 방식 '%s'" % accept})
	var giver := str(d.get("giver", ""))
	if giver != "" and giver != "board" and not DialogueData.speakers().has(giver):
		out.append({"severity": "error", "message": "없는 의뢰인 '%s' (data/speakers.json)" % giver})
	if source == "npc" and giver in ["", "board"]:
		out.append({"severity": "warning", "message": "NPC 의뢰인데 의뢰인이 없다"})
	if source == "board" and giver != "board":
		out.append({"severity": "warning", "message": "게시판 의뢰는 의뢰인을 '게시판'으로 두는 것이 보통"})
	if float(d.get("time_limit_hours", 0)) < 0.0:
		out.append({"severity": "error", "message": "제한 시간이 음수"})
	if accept == "auto":
		var t: Variant = d.get("trigger", null)
		if not t is Dictionary:
			out.append({"severity": "error", "message": "자동 시작 퀘스트에는 시작 조건(지역·위치·반경)이 필요하다"})
		else:
			if str(t.get("type", "")) != "reach":
				out.append({"severity": "error", "message": "알 수 없는 시작 조건 종류 '%s'" % t.get("type", "")})
			if not RegionDB.all().has(str(t.get("region", ""))):
				out.append({"severity": "error", "message": "시작 조건: 없는 지역 '%s'" % t.get("region", "")})
			if float(t.get("radius", 0)) <= 0.0:
				out.append({"severity": "error", "message": "시작 조건: 반경이 0 이하"})
	elif d.has("trigger"):
		out.append({"severity": "warning", "message": "시작 조건은 받는 방식이 '자동 시작'일 때만 쓰인다"})
	var objs: Array = d.get("objectives", [])
	if objs.is_empty():
		out.append({"severity": "error", "message": "목표가 하나도 없다 (받자마자 완료 가능)"})
	var ids := {}
	var monsters := MonsterDB.all().keys()
	var flags := known_flags()
	for o: Dictionary in objs:
		var oid := str(o.get("id", ""))
		if oid == "" or ids.has(oid) or oid.contains(" "):
			out.append({"severity": "error", "message": "목표 ID가 비었거나 겹치거나 띄어쓰기가 있다 ('%s')" % oid})
		ids[oid] = true
		var t := str(o.get("type", ""))
		if not OBJECTIVE_TYPES.has(t):
			out.append({"severity": "error", "message": "목표 %s: 알 수 없는 종류 '%s'" % [oid, t]})
			continue
		if t != "flag" and int(o.get("count", 1)) < 1:
			out.append({"severity": "error", "message": "목표 %s: 개수가 1보다 작다" % oid})
		match t:
			"collect":
				if not ItemDB.ITEMS.has(str(o.get("item", ""))):
					out.append({"severity": "error", "message": "목표 %s: 없는 아이템 '%s'" % [oid, o.get("item", "")]})
			"kill":
				var target := str(o.get("target", ""))
				var hit := false
				for m: String in monsters:
					hit = hit or m.begins_with(target)
				if target == "" or not hit:
					out.append({"severity": "error", "message": "목표 %s: '%s'(으)로 시작하는 몬스터가 없다 (data/monsters.json)" % [oid, target]})
			"flag":
				var fl := str(o.get("flag", ""))
				if fl == "":
					out.append({"severity": "error", "message": "목표 %s: 플래그 키가 비었다" % oid})
				elif not flags.has(fl):
					out.append({"severity": "warning", "message": "목표 %s: 플래그 '%s'를 세우는 곳이 없다 (코드·대화·컷씬)" % [oid, fl]})
			"count":
				if refs is Array:
					var advanced := false
					for r: Dictionary in refs:
						advanced = advanced or r.get("action", "") == "quest_advance"
					if not advanced:
						out.append({"severity": "warning", "message": "목표 %s: 횟수를 올리는 '퀘스트 목표 진행' 액션이 어떤 대화에도 없다 (코드가 올리는 목표라면 무시)" % oid})
		if str(o.get("text", "")).strip_edges() == "":
			out.append({"severity": "warning", "message": "목표 %s: 표시 글자가 비었다" % oid})
	_validate_rewards(d.get("rewards", {}), "보상", out)
	var oc: Dictionary = d.get("outcomes", {})
	for k in oc:
		if str(k) == "" or str(k).contains(" "):
			out.append({"severity": "error", "message": "결과 분기 키가 비었거나 띄어쓰기가 있다 ('%s')" % k})
		if str(oc[k].get("label", "")).strip_edges() == "":
			out.append({"severity": "warning", "message": "결과 '%s': 이름이 비었다" % k})
		_validate_rewards(oc[k].get("rewards", {}), "결과 '%s'" % k, out)
	if refs is Array and source == "npc":
		var accepted := false
		for r: Dictionary in refs:
			accepted = accepted or r.get("action", "") == "quest_accept"
		if not accepted:
			out.append({"severity": "warning", "message": "받을 길이 없다 — 어떤 대화·컷씬에도 '퀘스트 수락'이 없다 (게시판 의뢰는 게시판에 저절로 뜸)"})
	return out
