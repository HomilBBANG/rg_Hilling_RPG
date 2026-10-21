@tool
class_name DialogueData
extends RefCounted
## Dialogue file format v1 (UTF-8 JSON in res://data/dialogues/<dialogue_id>.json), shared by the
## editor plugin, its preview and the game. Content is data: nothing here is ever eval'd.
##
## { "version": 1, "dialogue_id": "dialogue.npc.rosa.main",
##   "metadata": {"title": "", "tags": [], "notes": ""},
##   "start_node_id": "start",
##   "nodes": [ {"id": "start", "type": "start"},
##              {"id": "line_01", "type": "line", "speaker_id": "rosa", "text": "..."},
##              {"id": "choice_01", "type": "choice", "options": [{"port": "yes", "text": "...", "condition": {...}}]},
##              {"id": "cond_01", "type": "condition", "check": {"kind": "quest", "quest_id": "...", "state": "ready"}},
##              {"id": "act_01", "type": "action", "action": "quest_accept", "args": {"quest_id": "..."}},
##              {"id": "cut_01", "type": "cutscene", "cutscene_id": "..."},
##              {"id": "end", "type": "end", "complete_event": ""} ],
##   "connections": [ {"from": "start", "port": "next", "to": "line_01"}, ... ],
##   "editor_positions": {"start": [x, y], ...} }
##
## Outgoing links live only in "connections" (one target per port); node ids are stable
## ([A-Za-z0-9_]) so renaming the title or moving a node never breaks links.

const VERSION := 1
const DIALOGUE_DIR := "res://data/dialogues"
const QUEST_DIR := "res://data/quests"
const CUTSCENE_DIR := "res://data/cutscenes"
const SPEAKERS_PATH := "res://data/speakers.json"

const NODE_TYPES := ["start", "line", "choice", "condition", "action", "cutscene", "end"]
const TYPE_NAMES := {"start": "시작", "line": "대사", "choice": "선택지", "condition": "조건",
	"action": "액션", "cutscene": "컷씬 호출", "end": "종료"}

## Only these commands exist; each maps to an existing game API (NarrativeState / QuestManager).
## Arg types: text, bool, int, quest, objective, outcome, event.
const ACTIONS := {
	"set_flag": {"label": "플래그 설정", "args": [{"name": "key", "type": "text", "label": "플래그 키"},
		{"name": "value", "type": "bool", "label": "값 (켜기)", "default": true}]},
	"quest_accept": {"label": "퀘스트 수락", "args": [{"name": "quest_id", "type": "quest", "label": "퀘스트"}]},
	"quest_advance": {"label": "퀘스트 목표 진행", "args": [{"name": "quest_id", "type": "quest", "label": "퀘스트"},
		{"name": "objective", "type": "objective", "label": "목표"}, {"name": "amount", "type": "int", "label": "양", "default": 1}]},
	"quest_complete": {"label": "퀘스트 완료(보상)", "args": [{"name": "quest_id", "type": "quest", "label": "퀘스트"},
		{"name": "outcome", "type": "outcome", "label": "결과(분기)", "default": ""}]},
	"mark_event_complete": {"label": "이벤트 완료 기록", "args": [{"name": "event_id", "type": "event", "label": "이벤트 ID"}]},
	"learn_recipe": {"label": "레시피 가르치기", "args": [{"name": "recipe_id", "type": "recipe", "label": "레시피"}]},
}

## Read-only queries for Condition nodes and choice-option conditions.
const QUEST_STATES := ["none", "active", "ready", "completed", "failed"]
const QUEST_STATE_NAMES := {"none": "받지 않음", "active": "진행 중", "ready": "목표 달성(보고 전)",
	"completed": "완료", "failed": "실패"}
const CONDITIONS := {
	"flag": {"label": "플래그가 켜져 있다", "fields": [{"name": "key", "type": "text", "label": "플래그 키"}]},
	"quest": {"label": "퀘스트 상태", "fields": [{"name": "quest_id", "type": "quest", "label": "퀘스트"},
		{"name": "state", "type": "quest_state", "label": "상태", "default": "active"}]},
	"item": {"label": "아이템 보유 (이상)", "fields": [{"name": "item", "type": "item", "label": "아이템"},
		{"name": "count", "type": "int", "label": "개수", "default": 1}]},
	"gold": {"label": "골드 보유 (이상)", "fields": [{"name": "amount", "type": "int", "label": "골드", "default": 10}]},
	"event": {"label": "이벤트 완료됨", "fields": [{"name": "event_id", "type": "event", "label": "이벤트 ID"}]},
}

const ID_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"


# ---------------------------------------------------------------- files

static func path_for(dialogue_id: String) -> String:
	return DIALOGUE_DIR.path_join(dialogue_id + ".json")


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var txt := FileAccess.get_file_as_string(path)
	var j := JSON.new()
	if j.parse(txt) != OK:
		push_warning("JSON 오류 %s:%d %s" % [path, j.get_error_line(), j.get_error_message()])
		return null
	return j.data


static func load_dialogue(dialogue_id: String) -> Dictionary:
	var d: Variant = read_json(path_for(dialogue_id))
	return normalized(d) if d is Dictionary else {}


## Pretty, stable JSON so diffs stay readable.
static func to_json(doc: Dictionary) -> String:
	return JSON.stringify(normalized(doc), "  ", false) + "\n"


static func save_dialogue(doc: Dictionary, path := "") -> Error:
	if path == "":
		path = path_for(doc["dialogue_id"])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json(doc))
	f.close()
	return OK


static func list_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if f.ends_with(".json"):
			out.append(dir.path_join(f))
	out.sort()
	return out


## Summary of every dialogue file for the editor list / search.
static func list_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in list_files(DIALOGUE_DIR):
		var d: Variant = read_json(p)
		if not d is Dictionary:
			out.append({"id": p.get_file().get_basename(), "path": p, "title": "(읽기 오류)", "tags": [], "speakers": [], "text": ""})
			continue
		var speakers := PackedStringArray()
		var text := PackedStringArray()
		for n: Dictionary in d.get("nodes", []):
			if n.get("speaker_id", "") != "" and not speakers.has(n["speaker_id"]):
				speakers.append(n["speaker_id"])
			text.append(str(n.get("text", "")))
			for o: Dictionary in n.get("options", []):
				text.append(str(o.get("text", "")))
		var meta: Dictionary = d.get("metadata", {})
		out.append({"id": d.get("dialogue_id", ""), "path": p, "title": meta.get("title", ""),
			"tags": meta.get("tags", []), "speakers": speakers, "text": "\n".join(text)})
	return out


static func new_doc(dialogue_id: String, title := "") -> Dictionary:
	return normalized({
		"dialogue_id": dialogue_id, "metadata": {"title": title, "tags": [], "notes": ""},
		"start_node_id": "start",
		"nodes": [{"id": "start", "type": "start"}, {"id": "line_01", "type": "line", "speaker_id": "narrator", "text": ""},
			{"id": "end", "type": "end"}],
		"connections": [{"from": "start", "port": "next", "to": "line_01"}, {"from": "line_01", "port": "next", "to": "end"}],
		"editor_positions": {"start": [0, 120], "line_01": [260, 80], "end": [620, 120]},
	})


## JSON numbers load as floats: turn whole numbers back into ints so a save never rewrites
## "count": 5 as 5.0 (keeps hand-written files and diffs stable).
static func intified(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)) and absf(v) < 1e12:
		return int(roundf(v))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = intified(v[k])
		return out
	if v is Array:
		var arr := []
		for x in v:
			arr.append(intified(x))
		return arr
	return v


## Fills missing keys so older / hand-written files load the same way everywhere.
static func normalized(d: Dictionary) -> Dictionary:
	var doc: Dictionary = intified(d)
	doc["version"] = int(doc.get("version", VERSION))
	doc["dialogue_id"] = str(doc.get("dialogue_id", ""))
	var meta: Dictionary = doc.get("metadata", {})
	meta["title"] = str(meta.get("title", ""))
	meta["tags"] = meta.get("tags", [])
	meta["notes"] = str(meta.get("notes", ""))
	doc["metadata"] = meta
	doc["start_node_id"] = str(doc.get("start_node_id", "start"))
	doc["nodes"] = doc.get("nodes", [])
	doc["connections"] = doc.get("connections", [])
	var pos = doc.get("editor_positions", {})
	doc["editor_positions"] = pos if pos is Dictionary else {}
	# stable key order for diffs
	var ordered := {}
	for k in ["version", "dialogue_id", "metadata", "start_node_id", "nodes", "connections", "editor_positions"]:
		ordered[k] = doc[k]
	return ordered


# ---------------------------------------------------------------- catalog (ids the validator / editor know)

static func speakers() -> Dictionary:
	var d: Variant = read_json(SPEAKERS_PATH)
	return d.get("speakers", {}) if d is Dictionary else {}


static func speaker_name(id: String) -> String:
	return str(speakers().get(id, {}).get("name", id))


## Dialogue an NPC opens when talked to (data, so writers re-point it without code).
static func talk_dialogue(speaker_id: String) -> String:
	return str(speakers().get(speaker_id, {}).get("talk", ""))


static func cutscenes() -> Dictionary:
	var out := {}
	for p in list_files(CUTSCENE_DIR):
		var d: Variant = read_json(p)
		if d is Dictionary and d.has("cutscene_id"):
			out[d["cutscene_id"]] = d
	return out


## Readable list of a cutscene's steps (editor preview; the game plays them with CutsceneRunner).
static func cutscene_steps_text(cutscene_id: String) -> String:
	var parts := PackedStringArray()
	for s: Dictionary in cutscenes().get(cutscene_id, {}).get("steps", []):
		match s.get("type", ""):
			"caption":
				parts.append("자막 \"%s\"" % s.get("text", ""))
			"wait":
				parts.append("대기 %.1f초" % float(s.get("seconds", 0.5)))
			"actor_move":
				parts.append("%s 이동" % s.get("actor", "?"))
			"actor_face":
				parts.append("%s 바라보기" % s.get("actor", "?"))
			"set_flag":
				parts.append("플래그 %s" % s.get("key", ""))
			_:
				parts.append("알 수 없는 단계 %s" % s.get("type", ""))
	return " → ".join(parts)


static func catalog() -> Dictionary:
	return {"speakers": speakers(), "quests": QuestDB.all(), "cutscenes": cutscenes(), "items": ItemDB.ITEMS, "recipes": RecipeDB.all()}


# ---------------------------------------------------------------- graph helpers

static func node_by_id(doc: Dictionary, id: String) -> Dictionary:
	for n: Dictionary in doc["nodes"]:
		if n.get("id", "") == id:
			return n
	return {}


static func out_ports(n: Dictionary) -> PackedStringArray:
	match n.get("type", ""):
		"start", "line", "action", "cutscene":
			return PackedStringArray(["next"])
		"condition":
			return PackedStringArray(["true", "false"])
		"choice":
			var ports := PackedStringArray()
			for o: Dictionary in n.get("options", []):
				ports.append(str(o.get("port", "")))
			return ports
	return PackedStringArray()


static func has_input(n: Dictionary) -> bool:
	return n.get("type", "") != "start"


static func target(doc: Dictionary, from: String, port: String) -> String:
	for c: Dictionary in doc["connections"]:
		if c.get("from", "") == from and c.get("port", "") == port:
			return str(c.get("to", ""))
	return ""


static func valid_id(id: String) -> bool:
	if id == "":
		return false
	for ch in id:
		if not ID_CHARS.contains(ch):
			return false
	return true


static func unique_id(doc: Dictionary, prefix: String) -> String:
	var i := 1
	while true:
		var id := "%s_%02d" % [prefix, i]
		if node_by_id(doc, id).is_empty():
			return id
		i += 1
	return ""


# ---------------------------------------------------------------- conditions (query API only)

static func eval_condition(check: Dictionary, ctx: DialogueContext) -> bool:
	match check.get("kind", ""):
		"flag":
			return ctx.get_flag(str(check.get("key", "")))
		"quest":
			return ctx.quest_state(str(check.get("quest_id", ""))) == str(check.get("state", "active"))
		"item":
			return ctx.item_count(str(check.get("item", ""))) >= int(check.get("count", 1))
		"gold":
			return ctx.gold() >= int(check.get("amount", 0))
		"event":
			return ctx.event_done(str(check.get("event_id", "")))
	return false


static func condition_text(check: Dictionary) -> String:
	match check.get("kind", ""):
		"flag":
			return "플래그 %s" % check.get("key", "?")
		"quest":
			return "%s = %s" % [check.get("quest_id", "?"), QUEST_STATE_NAMES.get(check.get("state", ""), check.get("state", "?"))]
		"item":
			return "%s ≥ %d" % [ItemDB.ITEMS.get(check.get("item", ""), {}).get("name", check.get("item", "?")), int(check.get("count", 1))]
		"gold":
			return "골드 ≥ %d" % int(check.get("amount", 0))
		"event":
			return "이벤트 %s 완료" % check.get("event_id", "?")
	return "(조건 없음)"


static func action_text(n: Dictionary) -> String:
	var spec: Dictionary = ACTIONS.get(n.get("action", ""), {})
	if spec.is_empty():
		return "알 수 없는 액션 '%s'" % n.get("action", "")
	var args: Dictionary = n.get("args", {})
	var parts := PackedStringArray()
	for a: Dictionary in spec["args"]:
		var v = args.get(a["name"], a.get("default", ""))
		if str(v) != "":
			parts.append(str(v))
	return "%s %s" % [spec["label"], " · ".join(parts)]


## One- or two-line summary shown on the graph node.
static func node_summary(n: Dictionary) -> String:
	match n.get("type", ""):
		"start":
			return "대화 시작"
		"line":
			var t := str(n.get("text", "")).replace("\n", " ")
			if t.length() > 38:
				t = t.substr(0, 37) + "…"
			return "%s: %s" % [speaker_name(str(n.get("speaker_id", ""))), t if t != "" else "(빈 대사)"]
		"choice":
			return "선택지 %d개" % n.get("options", []).size()
		"condition":
			return condition_text(n.get("check", {}))
		"action":
			return action_text(n)
		"cutscene":
			return "▶ %s" % n.get("cutscene_id", "?")
		"end":
			var ev := str(n.get("complete_event", ""))
			return "대화 종료" + (" · 이벤트 %s 완료" % ev if ev != "" else "")
	return "?"


# ---------------------------------------------------------------- validation

## Returns [{"severity": "error"|"warning", "node": id, "message": String}]. The editor shows
## these; the game refuses nothing but stops safely at a broken link.
static func validate(doc: Dictionary, cat := {}) -> Array[Dictionary]:
	if cat.is_empty():
		cat = catalog()
	var out: Array[Dictionary] = []
	var err := func(node: String, msg: String) -> void:
		out.append({"severity": "error", "node": node, "message": msg})
	var warn := func(node: String, msg: String) -> void:
		out.append({"severity": "warning", "node": node, "message": msg})
	if int(doc.get("version", 0)) != VERSION:
		err.call("", "지원하지 않는 버전 %s (지원: %d)" % [doc.get("version"), VERSION])
	var did := str(doc.get("dialogue_id", ""))
	if did == "":
		err.call("", "dialogue_id가 비어 있다")
	elif not did.begins_with("dialogue."):
		warn.call("", "dialogue_id는 'dialogue.'로 시작하길 권장 (%s)" % did)
	var ids := {}
	var starts := []
	for n: Dictionary in doc.get("nodes", []):
		var id := str(n.get("id", ""))
		if not valid_id(id):
			err.call(id, "노드 ID '%s'는 영문·숫자·_만 쓸 수 있다" % id)
		if ids.has(id):
			err.call(id, "중복된 노드 ID '%s'" % id)
		ids[id] = n
		var t := str(n.get("type", ""))
		if not NODE_TYPES.has(t):
			err.call(id, "알 수 없는 노드 종류 '%s'" % t)
			continue
		if t == "start":
			starts.append(id)
		_validate_node(n, cat, err, warn)
	if starts.size() == 0:
		err.call("", "시작(Start) 노드가 없다")
	elif starts.size() > 1:
		err.call(starts[1], "시작 노드는 하나만 둘 수 있다 (%s)" % ", ".join(starts))
	var sid := str(doc.get("start_node_id", ""))
	if not ids.has(sid) or ids[sid].get("type", "") != "start":
		err.call("", "start_node_id '%s'가 시작 노드를 가리키지 않는다" % sid)
	# connections
	var used := {}
	for c: Dictionary in doc.get("connections", []):
		var f := str(c.get("from", ""))
		var to := str(c.get("to", ""))
		var port := str(c.get("port", ""))
		if not ids.has(f):
			err.call("", "연결의 출발 노드 '%s'가 없다" % f)
			continue
		if not ids.has(to):
			err.call(f, "'%s'의 %s 연결 대상 '%s'가 없다" % [f, port, to])
			continue
		if not out_ports(ids[f]).has(port):
			err.call(f, "'%s'에는 '%s' 출력이 없다" % [f, port])
		if not has_input(ids[to]):
			err.call(to, "시작 노드로는 연결할 수 없다")
		var key := f + "|" + port
		if used.has(key):
			err.call(f, "'%s'의 '%s' 출력이 여러 곳에 연결됨" % [f, port])
		used[key] = true
	for id: String in ids:
		var n: Dictionary = ids[id]
		for port in out_ports(n):
			if not used.has(id + "|" + port):
				var what: String = {"next": "다음", "true": "참", "false": "거짓"}.get(port, "선택지 '%s'" % port)
				err.call(id, "연결 없는 출력: %s" % what)
	# reachability
	if ids.has(sid):
		var seen := {sid: true}
		var stack := [sid]
		while not stack.is_empty():
			var cur: String = stack.pop_back()
			for c: Dictionary in doc.get("connections", []):
				if c.get("from", "") == cur and ids.has(c.get("to", "")) and not seen.has(c["to"]):
					seen[c["to"]] = true
					stack.append(c["to"])
		var has_end := false
		for id: String in ids:
			if not seen.has(id):
				warn.call(id, "시작에서 도달할 수 없는 노드")
			elif ids[id].get("type", "") == "end":
				has_end = true
		if not has_end:
			warn.call("", "시작에서 도달 가능한 종료(End) 노드가 없다")
	return out


static func _validate_node(n: Dictionary, cat: Dictionary, err: Callable, warn: Callable) -> void:
	var id := str(n.get("id", ""))
	match n.get("type", ""):
		"line":
			if str(n.get("text", "")).strip_edges() == "":
				err.call(id, "대사가 비어 있다")
			var sp := str(n.get("speaker_id", ""))
			if not cat["speakers"].has(sp):
				err.call(id, "등록되지 않은 화자 '%s' (data/speakers.json)" % sp)
		"choice":
			var opts: Array = n.get("options", [])
			if opts.is_empty():
				err.call(id, "선택지가 하나도 없다")
			var ports := {}
			for o: Dictionary in opts:
				var port := str(o.get("port", ""))
				if not valid_id(port):
					err.call(id, "선택지 포트 이름 '%s'가 올바르지 않다" % port)
				if ports.has(port):
					err.call(id, "선택지 포트 '%s' 중복" % port)
				ports[port] = true
				if str(o.get("text", "")).strip_edges() == "":
					err.call(id, "선택지 '%s'의 문구가 비어 있다" % port)
				if o.has("condition") and not (o["condition"] as Dictionary).is_empty():
					_validate_check(id, o["condition"], cat, err)
		"condition":
			_validate_check(id, n.get("check", {}), cat, err)
		"action":
			var a := str(n.get("action", ""))
			if not ACTIONS.has(a):
				err.call(id, "지원하지 않는 액션 '%s'" % a)
				return
			var args: Dictionary = n.get("args", {})
			var qid := str(args.get("quest_id", ""))
			for spec: Dictionary in ACTIONS[a]["args"]:
				var v = args.get(spec["name"], spec.get("default", null))
				match spec["type"]:
					"text", "event":
						if str(v if v != null else "").strip_edges() == "":
							err.call(id, "%s: '%s' 값이 비어 있다" % [ACTIONS[a]["label"], spec["label"]])
					"quest":
						if not cat["quests"].has(str(v)):
							err.call(id, "존재하지 않는 퀘스트 ID '%s'" % v)
					"recipe":
						if not cat.get("recipes", {}).has(str(v)):
							err.call(id, "존재하지 않는 레시피 ID '%s' (data/recipes.json)" % v)
					"objective":
						var q: Dictionary = cat["quests"].get(qid, {})
						var found := false
						for o: Dictionary in q.get("objectives", []):
							found = found or o.get("id", "") == str(v)
						if not q.is_empty() and not found:
							err.call(id, "퀘스트 '%s'에 목표 '%s'가 없다" % [qid, v])
					"outcome":
						var q2: Dictionary = cat["quests"].get(qid, {})
						if str(v if v != null else "") != "" and not q2.is_empty() and not q2.get("outcomes", {}).has(str(v)):
							err.call(id, "퀘스트 '%s'에 결과 '%s'가 없다" % [qid, v])
		"cutscene":
			if not cat["cutscenes"].has(str(n.get("cutscene_id", ""))):
				err.call(id, "존재하지 않는 컷씬 ID '%s' (data/cutscenes)" % n.get("cutscene_id", ""))


static func _validate_check(id: String, check: Dictionary, cat: Dictionary, err: Callable) -> void:
	var kind := str(check.get("kind", ""))
	if not CONDITIONS.has(kind):
		err.call(id, "알 수 없는 조건 종류 '%s'" % kind)
		return
	match kind:
		"flag":
			if str(check.get("key", "")).strip_edges() == "":
				err.call(id, "조건: 플래그 키가 비어 있다")
		"quest":
			if not cat["quests"].has(str(check.get("quest_id", ""))):
				err.call(id, "조건: 존재하지 않는 퀘스트 ID '%s'" % check.get("quest_id", ""))
			if not QUEST_STATES.has(str(check.get("state", ""))):
				err.call(id, "조건: 알 수 없는 퀘스트 상태 '%s'" % check.get("state", ""))
		"item":
			if not cat["items"].has(str(check.get("item", ""))):
				err.call(id, "조건: 존재하지 않는 아이템 ID '%s'" % check.get("item", ""))
		"event":
			if str(check.get("event_id", "")).strip_edges() == "":
				err.call(id, "조건: 이벤트 ID가 비어 있다")
