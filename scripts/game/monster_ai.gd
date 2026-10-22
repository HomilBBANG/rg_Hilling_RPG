@tool
class_name MonsterAI
extends RefCounted
## Monster AI as editable decision graphs (res://data/ai/<ai_id>.json), made in the editor's
## 몬스터 AI tab. Each time a monster finishes a hop it walks its graph from "start": condition
## nodes pick the "true" / "false" branch, "engage" marks it as fighting (and can call others of
## its species) and goes on, and the first action node reached is what it does next.
## A monster's graph: data/monsters.json "ai", or by default ai.slime.aggressive / ai.slime.passive
## from its 선공 flag (GDD 7.1-7.3: simple monsters approach + attack; 선공 / 반격; joining a fight;
## giving up past their area). The dragon keeps its own boss script.
##
## File: {"version": 1, "ai_id", "title", "notes", "start_node_id": "start",
##        "nodes": [{"id", "type": "start"|"condition"|"engage"|"action", "check"|"action": kind,
##                   "params": {...}}],
##        "connections": [{"from", "port": "next"|"true"|"false", "to"}], "editor_positions": {id: [x, y]}}

const DIR := "res://data/ai"
const MONSTERS_PATH := "res://data/monsters.json"
const MAX_STEPS := 32

const NODE_TYPES := ["start", "condition", "engage", "action"]
const TYPE_NAMES := {"start": "시작", "condition": "조건", "engage": "싸움 시작", "action": "행동"}

## Conditions: label, help, params [{name, label, default, min, max, step}].
const CHECKS := {
	"provoked": {"label": "싸우는 중인가", "help": "주인공에게 맞았거나(반격), 먼저 덤볐거나, 동료의 부름에 끼어든 상태", "params": []},
	"player_near": {"label": "주인공이 가까운가", "help": "주인공이 이 거리 안에 있고 노릴 수 있는 상태(쉼터 밖)", "params": [
		{"name": "distance", "label": "거리 (m)", "default": 6.0, "min": 0.5, "max": 40.0, "step": 0.5},
		{"name": "night_mult", "label": "밤 배율", "default": 1.4, "min": 1.0, "max": 3.0, "step": 0.1}]},
	"player_in_reach": {"label": "덮칠 수 있는가", "help": "주인공이 덮치기 거리 안 + 다시 덮칠 준비가 됨 (몸집이 크면 거리도 늘어남)", "params": [
		{"name": "reach", "label": "덮치기 거리 (m)", "default": 1.7, "min": 0.5, "max": 6.0, "step": 0.1}]},
	"player_gone": {"label": "주인공을 놓쳤는가", "help": "주인공이 쓰러졌거나, 쉼터 안이거나, 운전·대화 중", "params": []},
	"far_from_home": {"label": "자리에서 멀어졌는가", "help": "처음 자리에서 이 거리보다 멀리 쫓아옴 (추적 포기 거리)", "params": [
		{"name": "distance", "label": "거리 (m)", "default": 14.0, "min": 2.0, "max": 80.0, "step": 1.0}]},
	"hp_below": {"label": "체력이 낮은가", "help": "남은 체력이 이 비율 아래", "params": [
		{"name": "percent", "label": "비율 (%)", "default": 30.0, "min": 1.0, "max": 99.0, "step": 1.0}]},
	"ally_called": {"label": "같은 종족이 불렀는가", "help": "근처의 같은 종족이 싸우면서 도움을 불렀음 (최근 몇 초 안)", "params": [
		{"name": "seconds", "label": "몇 초 안", "default": 4.0, "min": 0.5, "max": 30.0, "step": 0.5}]},
	"camper_near": {"label": "빈 캠핑카가 가까운가", "help": "위험한 곳(쉼터·마을 밖)에 주인공 없이 세워 둔 캠핑카가 7 m 안 (GDD 9.4)", "params": []},
	"is_night": {"label": "밤인가", "help": "게임 시각이 밤", "params": []},
	"random": {"label": "확률", "help": "이 확률로 '예'", "params": [
		{"name": "percent", "label": "확률 (%)", "default": 50.0, "min": 0.0, "max": 100.0, "step": 1.0}]},
}

## Actions (the end of a walk): label, help, params.
const ACTIONS := {
	"wander": {"label": "어슬렁거리기", "help": "처음 자리 근처를 깡충깡충 돌아다님", "params": [
		{"name": "radius", "label": "범위 (m)", "default": 3.5, "min": 0.5, "max": 20.0, "step": 0.5},
		{"name": "hop", "label": "한 번 뛰는 시간 (초)", "default": 1.1, "min": 0.3, "max": 3.0, "step": 0.1}]},
	"chase": {"label": "쫓아가기", "help": "주인공 쪽으로 뜀 (가까우면 제자리에서 기다림)", "params": [
		{"name": "step", "label": "한 번에 (m)", "default": 1.5, "min": 0.3, "max": 4.0, "step": 0.1},
		{"name": "hop", "label": "한 번 뛰는 시간 (초)", "default": 0.7, "min": 0.3, "max": 3.0, "step": 0.1}]},
	"attack": {"label": "덮치기 공격", "help": "주인공에게 몸을 날림 — 몸이 닿으면 명중 판정 (GDD 6.2)", "params": [
		{"name": "cooldown", "label": "다음 공격까지 (초)", "default": 1.3, "min": 0.2, "max": 10.0, "step": 0.1}]},
	"flee": {"label": "도망치기", "help": "주인공 반대쪽으로 뜀", "params": [
		{"name": "step", "label": "한 번에 (m)", "default": 1.6, "min": 0.3, "max": 4.0, "step": 0.1}]},
	"return_home": {"label": "자리로 돌아가기", "help": "싸움을 그만두고 처음 자리로 — 도착하면 체력 회복(선택)", "params": [
		{"name": "heal", "label": "도착하면 체력 회복 (1=예)", "default": 1.0, "min": 0.0, "max": 1.0, "step": 1.0}]},
	"idle": {"label": "가만히 있기", "help": "그 자리에서 잠깐 쉼", "params": [
		{"name": "seconds", "label": "시간 (초)", "default": 1.0, "min": 0.2, "max": 10.0, "step": 0.1}]},
	"attack_camper": {"label": "캠핑카 공격", "help": "빈 캠핑카에 다가가 긁음 — 내구도가 깎임 (GDD 9.4)", "params": [
		{"name": "cooldown", "label": "다음 공격까지 (초)", "default": 5.0, "min": 0.5, "max": 30.0, "step": 0.5}]},
}

## "engage" node params: call others of the same species for help.
const ENGAGE_PARAMS := [{"name": "call_allies", "label": "같은 종족 부르기 (1=예)", "default": 1.0, "min": 0.0, "max": 1.0, "step": 1.0}]

static var _cache := {}


static func path_for(ai_id: String) -> String:
	return DIR.path_join(ai_id + ".json")


static func ids() -> Array:
	var out := []
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(f.trim_suffix(".json"))
	out.sort()
	return out


static func load_graph(ai_id: String) -> Dictionary:
	if _cache.has(ai_id) and not Engine.is_editor_hint():
		return _cache[ai_id]
	var v: Variant = DialogueData.read_json(path_for(ai_id))
	var g: Dictionary = v if v is Dictionary else {}
	_cache[ai_id] = g
	return g


static func clear_cache() -> void:
	_cache.clear()


## Which graph a monster kind uses: its "ai", else by its 선공 flag.
static func ai_for(kind: String) -> String:
	var def := MonsterDB.info(kind)
	var id := str(def.get("ai", ""))
	if id != "":
		return id
	return "ai.slime.aggressive" if bool(def.get("aggressive", false)) else "ai.slime.passive"


static func node(g: Dictionary, id: String) -> Dictionary:
	for n: Dictionary in g.get("nodes", []):
		if n.get("id", "") == id:
			return n
	return {}


static func next_of(g: Dictionary, from: String, port: String) -> String:
	for c: Dictionary in g.get("connections", []):
		if c.get("from", "") == from and c.get("port", "") == port:
			return str(c.get("to", ""))
	return ""


static func ports_of(n: Dictionary) -> Array:
	match n.get("type", ""):
		"condition":
			return ["true", "false"]
		"action":
			return []
	return ["next"]


static func param(n: Dictionary, key: String) -> float:
	var spec: Array = []
	match n.get("type", ""):
		"condition":
			spec = CHECKS.get(n.get("check", ""), {}).get("params", [])
		"action":
			spec = ACTIONS.get(n.get("action", ""), {}).get("params", [])
		"engage":
			spec = ENGAGE_PARAMS
	var fallback := 0.0
	for p: Dictionary in spec:
		if p["name"] == key:
			fallback = float(p["default"])
	return float(n.get("params", {}).get(key, fallback))


## Walks the graph. ctx answers conditions (check(kind, node) -> bool) and does "engage"
## (engage(node)). Returns {"node": action node} or {"error": text}; "path" lists visited ids.
static func decide(g: Dictionary, ctx: Object) -> Dictionary:
	var id := str(g.get("start_node_id", "start"))
	var path := []
	for i in MAX_STEPS:
		var n := node(g, id)
		if n.is_empty():
			return {"error": "노드 '%s' 없음" % id, "path": path}
		path.append(id)
		match n.get("type", ""):
			"action":
				return {"node": n, "path": path}
			"condition":
				id = next_of(g, id, "true" if ctx.call("ai_check", str(n.get("check", "")), n) else "false")
			"engage":
				ctx.call("ai_engage", n)
				id = next_of(g, id, "next")
			_:
				id = next_of(g, id, "next")
		if id == "":
			return {"error": "'%s'에서 이어지는 노드가 없다" % path[-1], "path": path}
	return {"error": "고리(순환)가 있다", "path": path}


## Problems as [{severity, node, message}] — the editor shows them, the game warns once.
static func validate(g: Dictionary) -> Array:
	var out := []
	var err := func(sev: String, id: String, msg: String) -> void: out.append({"severity": sev, "node": id, "message": msg})
	var ids_seen := {}
	var starts := 0
	for n: Dictionary in g.get("nodes", []):
		var id := str(n.get("id", ""))
		if id == "" or ids_seen.has(id):
			err.call("error", id, "노드 ID가 비었거나 겹친다")
		ids_seen[id] = true
		match n.get("type", ""):
			"start":
				starts += 1
			"condition":
				if not CHECKS.has(n.get("check", "")):
					err.call("error", id, "알 수 없는 조건 '%s'" % n.get("check", ""))
			"action":
				if not ACTIONS.has(n.get("action", "")):
					err.call("error", id, "알 수 없는 행동 '%s'" % n.get("action", ""))
			"engage":
				pass
			_:
				err.call("error", id, "알 수 없는 노드 종류 '%s'" % n.get("type", ""))
		for port: String in ports_of(n):
			var to := next_of(g, id, port)
			if to == "":
				err.call("error", id, "연결 없는 출력: %s" % ({"true": "예", "false": "아니오", "next": "다음"}[port]))
			elif not ids_seen.has(to) and node(g, to).is_empty():
				err.call("error", id, "없는 노드 '%s'로 이어짐" % to)
	if starts != 1:
		err.call("error", "", "시작 노드가 정확히 하나 있어야 한다 (지금 %d개)" % starts)
	# reachability + cycles (graph walk)
	var start_id := str(g.get("start_node_id", "start"))
	var reach := {}
	var stack := [[start_id, []]]
	var cycle := false
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var id2: String = top[0]
		var trail: Array = top[1]
		if trail.has(id2):
			cycle = true
			continue
		reach[id2] = true
		var n2 := node(g, id2)
		for port2: String in ports_of(n2):
			var to2 := next_of(g, id2, port2)
			if to2 != "":
				stack.append([to2, trail + [id2]])
	if cycle:
		err.call("error", "", "고리(순환)가 있다 — 행동에 닿지 못하고 맴돈다")
	for n3: Dictionary in g.get("nodes", []):
		if not reach.has(str(n3.get("id", ""))):
			err.call("warning", str(n3.get("id", "")), "시작에서 닿지 않는 노드")
	return out


static func save_graph(g: Dictionary, ai_id: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(path_for(ai_id), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(g, "  ", false) + "\n")
	f.close()
	_cache.erase(ai_id)
	return OK


## Writes one monster's "ai" (and 선공 flag) into data/monsters.json as a small text edit inside
## that monster's block, so the rest of the file (numbers, order, comments) stays as written.
static func set_monster_ai(kind: String, ai_id: String, aggressive: Variant = null) -> Error:
	var text := FileAccess.get_file_as_string(MONSTERS_PATH)
	var at := text.find('"%s": {' % kind)
	if text == "" or at < 0:
		return ERR_DOES_NOT_EXIST
	var open := text.find("{", at)
	var depth := 0
	var close := -1
	for i in range(open, text.length()):
		var ch := text[i]
		if ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0:
				close = i
				break
	if close < 0:
		return ERR_PARSE_ERROR
	var block := text.substr(open, close - open + 1)
	var re_aggr := RegEx.create_from_string('"aggressive":\\s*(true|false)')
	var re_ai := RegEx.create_from_string(',?\\n[ \\t]*"ai":\\s*"[^"]*"')
	if aggressive != null:
		block = re_aggr.sub(block, '"aggressive": %s' % ("true" if aggressive else "false"))
	block = re_ai.sub(block, "")
	if ai_id != "":
		var m := re_aggr.search(block)
		var line_start := block.rfind("\n", m.get_start()) if m else block.find("\n")
		var indent := block.substr(line_start + 1, (m.get_start() if m else line_start + 1) - line_start - 1)
		var pos := m.get_end() if m else 1
		block = block.insert(pos, ',\n%s"ai": "%s"' % [indent, ai_id])
	var out := text.substr(0, open) + block + text.substr(close + 1)
	if not (JSON.parse_string(out) is Dictionary):
		return ERR_PARSE_ERROR
	var f := FileAccess.open(MONSTERS_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(out)
	f.close()
	MonsterDB.reload()
	return OK


static func node_text(n: Dictionary) -> String:
	match n.get("type", ""):
		"start":
			return "시작"
		"condition":
			var c: Dictionary = CHECKS.get(n.get("check", ""), {})
			return "%s?%s" % [c.get("label", n.get("check", "?")), _params_text(n, c.get("params", []))]
		"action":
			var a: Dictionary = ACTIONS.get(n.get("action", ""), {})
			return "%s%s" % [a.get("label", n.get("action", "?")), _params_text(n, a.get("params", []))]
		"engage":
			return "싸움 시작%s" % (" + 같은 종족 부르기" if param(n, "call_allies") > 0.5 else "")
	return "?"


static func _params_text(n: Dictionary, spec: Array) -> String:
	var parts := PackedStringArray()
	for p: Dictionary in spec:
		parts.append("%s %s" % [str(p["label"]).split(" (")[0], str(snappedf(param(n, p["name"]), 0.1))])
	return "" if parts.is_empty() else " (" + ", ".join(parts) + ")"
