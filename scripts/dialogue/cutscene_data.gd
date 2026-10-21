@tool
class_name CutsceneData
extends RefCounted
## Cutscene file format (UTF-8 JSON in res://data/cutscenes/<cutscene_id>.json), shared by the
## game (CutsceneRunner) and the dialogue editor's 컷씬 tab. Step types and their fields are data
## (STEPS): the editor builds its inspector from them, the validator checks against them and the
## runner plays them, so a new step type is added in one place.
##
## { "version": 1, "cutscene_id": "cutscene.intro", "title": "", "notes": "", "skippable": true,
##   "steps": [ {"type": "fade", "to": "clear", "seconds": 1.0},
##              {"type": "image", "path": "res://assets/cutscenes/intro_01.png", "seconds": 0.6},
##              {"type": "narration", "text": "...", "seconds": 0},
##              {"type": "line", "speaker_id": "player", "expression": "", "text": "..."}, ... ] }
##
## data/story.json lists the cutscenes a new game plays, in order: {"new_game": ["...", "..."]}.
## The camera stays the fixed top-down camera (GDD 3.1); cutscenes never move it.

const VERSION := 1
const DIR := "res://data/cutscenes"
const STORY_PATH := "res://data/story.json"
const ILLUSTRATION_DIR := "res://assets/cutscenes"

## Field types: text (multi-line), line (one line), float, bool, enum (options), speaker,
## expression (of the step's speaker), actor, target (actor id or a [x, z] point), vec2, image.
const STEPS := {
	"fade": {"label": "화면 페이드", "fields": [
		{"name": "to", "type": "enum", "label": "방향", "default": "black",
			"options": [["black", "어둡게 (암전)"], ["clear", "밝게 (화면 보이기)"]]},
		{"name": "seconds", "type": "float", "label": "시간 (초)", "default": 1.0}]},
	"image": {"label": "삽화 (전체 화면)", "fields": [
		{"name": "path", "type": "image", "label": "그림 파일 (비우면 삽화를 내림)", "default": ""},
		{"name": "seconds", "type": "float", "label": "바뀌는 시간 (초)", "default": 0.6}]},
	"narration": {"label": "내레이션", "fields": [
		{"name": "text", "type": "text", "label": "문장 (줄바꿈 가능)", "default": ""},
		{"name": "seconds", "type": "float", "label": "자동 넘김 (초, 0 = 키를 누를 때까지)", "default": 0.0}]},
	"line": {"label": "대사 (초상화 대화창)", "fields": [
		{"name": "speaker_id", "type": "speaker", "label": "화자", "default": "player"},
		{"name": "expression", "type": "expression", "label": "표정", "default": ""},
		{"name": "text", "type": "text", "label": "대사", "default": ""}]},
	"caption": {"label": "자막 (화면 아래)", "fields": [
		{"name": "text", "type": "line", "label": "자막", "default": ""},
		{"name": "seconds", "type": "float", "label": "표시 시간 (초)", "default": 2.0}]},
	"wait": {"label": "대기", "fields": [
		{"name": "seconds", "type": "float", "label": "시간 (초)", "default": 0.5}]},
	"letterbox": {"label": "영화 띠 (위아래 검은 띠)", "fields": [
		{"name": "on", "type": "bool", "label": "켜기", "default": true}]},
	"actor_move": {"label": "인물 이동", "fields": [
		{"name": "actor", "type": "actor", "label": "누가", "default": "player"},
		{"name": "to", "type": "target", "label": "어디로", "default": "player"},
		{"name": "offset", "type": "vec2", "label": "그곳에서 떨어진 거리 (x, z m)", "default": [0, 0]},
		{"name": "speed", "type": "float", "label": "속도 (m/초, 4 이상이면 달리기)", "default": 2.0}]},
	"actor_face": {"label": "인물 바라보기", "fields": [
		{"name": "actor", "type": "actor", "label": "누가", "default": "cat"},
		{"name": "target", "type": "actor", "label": "누구를", "default": "player"}]},
	"set_flag": {"label": "플래그 설정", "fields": [
		{"name": "key", "type": "line", "label": "플래그 키", "default": ""},
		{"name": "value", "type": "bool", "label": "값 (켜기)", "default": true}]},
}
const ORDER := ["fade", "image", "narration", "line", "caption", "wait", "letterbox", "actor_move", "actor_face", "set_flag"]
const ACTOR_NAMES := {"player": "주인공", "cat": "검은 고양이", "rosa": "로사", "bron": "브론"}


static func path_for(cutscene_id: String) -> String:
	return DIR.path_join(cutscene_id + ".json")


static func all() -> Dictionary:
	return DialogueData.cutscenes()


static func load_cutscene(cutscene_id: String) -> Dictionary:
	var d: Variant = DialogueData.read_json(path_for(cutscene_id))
	return normalized(d) if d is Dictionary else {}


static func new_doc(cutscene_id: String, title := "") -> Dictionary:
	return normalized({"cutscene_id": cutscene_id, "title": title, "skippable": true,
		"steps": [new_step("fade").merged({"to": "clear"}, true), new_step("narration")]})


static func new_step(t: String) -> Dictionary:
	var s := {"type": t}
	for f: Dictionary in STEPS.get(t, {}).get("fields", []):
		var v: Variant = f.get("default", "")
		s[f["name"]] = v.duplicate() if v is Array else v
	return s


## Stable key order (file header, then each step's type and fields in STEPS order) so diffs stay small.
static func normalized(d: Dictionary) -> Dictionary:
	var doc: Dictionary = DialogueData.intified(d)
	var out := {"version": int(doc.get("version", VERSION)), "cutscene_id": str(doc.get("cutscene_id", "")),
		"title": str(doc.get("title", "")), "notes": str(doc.get("notes", "")), "skippable": bool(doc.get("skippable", true))}
	if doc.get("test_only", false):
		out["test_only"] = true
	var steps: Array = []
	for s: Variant in doc.get("steps", []):
		if not s is Dictionary:
			continue
		var t := str(s.get("type", ""))
		var o := {"type": t}
		for f: Dictionary in STEPS.get(t, {}).get("fields", []):
			if s.has(f["name"]):
				o[f["name"]] = s[f["name"]]
		for k in s:
			if not o.has(k):
				o[k] = s[k]
		steps.append(o)
	out["steps"] = steps
	return out


static func to_json(doc: Dictionary) -> String:
	return JSON.stringify(normalized(doc), "  ", false) + "\n"


static func save_cutscene(doc: Dictionary, path := "") -> Error:
	if path == "":
		path = path_for(doc["cutscene_id"])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json(doc))
	f.close()
	return OK


static func valid_cutscene_id(id: String) -> bool:
	if id == "" or id.begins_with(".") or id.ends_with("."):
		return false
	for ch in id:
		if not (DialogueData.ID_CHARS + ".").contains(ch):
			return false
	return true


# ---------------------------------------------------------------- story (new game sequence)

static func story() -> Dictionary:
	var d: Variant = DialogueData.read_json(STORY_PATH)
	return d if d is Dictionary else {}


static func new_game_cutscenes() -> Array:
	return story().get("new_game", [])


static func set_new_game_cutscenes(ids: Array) -> Error:
	var d := story()
	d["new_game"] = ids
	var f := FileAccess.open(STORY_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "  ", false) + "\n")
	f.close()
	return OK


# ---------------------------------------------------------------- readable text / checks

static func actor_name(id: String) -> String:
	return str(ACTOR_NAMES.get(id, DialogueData.speaker_name(id)))


static func actor_ids() -> Array:
	var out := ["player", "cat"]
	for look: String in NpcRig.LOOKS:
		out.append(look)
	return out


static func step_text(s: Dictionary) -> String:
	var t := str(s.get("type", ""))
	match t:
		"fade":
			return "페이드 %s %.1f초" % ["암전" if s.get("to", "black") == "black" else "밝게", float(s.get("seconds", 1.0))]
		"image":
			var p := str(s.get("path", ""))
			return "삽화 %s" % (p.get_file() if p != "" else "내림")
		"narration":
			return "내레이션 \"%s\"" % _short(str(s.get("text", "")))
		"line":
			var ex := str(s.get("expression", ""))
			return "%s%s: \"%s\"" % [DialogueData.speaker_name(str(s.get("speaker_id", ""))), " (%s)" % ex if ex != "" else "", _short(str(s.get("text", "")))]
		"caption":
			return "자막 \"%s\"" % _short(str(s.get("text", "")))
		"wait":
			return "대기 %.1f초" % float(s.get("seconds", 0.5))
		"letterbox":
			return "영화 띠 %s" % ("켬" if s.get("on", true) else "끔")
		"actor_move":
			var to: Variant = s.get("to", "player")
			return "%s → %s 이동" % [actor_name(str(s.get("actor", "?"))), actor_name(str(to)) + " 옆" if to is String else "(%.1f, %.1f)" % [float(to[0]), float(to[1])]]
		"actor_face":
			return "%s → %s 바라보기" % [actor_name(str(s.get("actor", "?"))), actor_name(str(s.get("target", "player")))]
		"set_flag":
			return "플래그 %s = %s" % [s.get("key", ""), bool(s.get("value", true))]
	return "알 수 없는 단계 '%s'" % t


static func _short(text: String) -> String:
	var line := text.split("\n")[0]
	return line.substr(0, 28) + ("…" if line.length() > 28 or text.contains("\n") else "")


## Errors and warnings like DialogueData.validate: [{severity, step (index or -1), message}].
static func validate(doc: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var speakers := DialogueData.speakers()
	var actors := actor_ids()
	var add := func(sev: String, i: int, msg: String) -> void:
		out.append({"severity": sev, "step": i, "message": msg})
	if not valid_cutscene_id(str(doc.get("cutscene_id", ""))):
		add.call("error", -1, "cutscene_id가 올바르지 않다 (영문·숫자·._)")
	var steps: Array = doc.get("steps", [])
	if steps.is_empty():
		add.call("warning", -1, "단계가 하나도 없다")
	for i in steps.size():
		var s: Dictionary = steps[i]
		var t := str(s.get("type", ""))
		if not STEPS.has(t):
			add.call("error", i, "알 수 없는 단계 종류 '%s'" % t)
			continue
		if t in ["narration", "line", "caption"] and str(s.get("text", "")).strip_edges() == "":
			add.call("error", i, "문장이 비어 있다")
		if t == "line":
			var sp := str(s.get("speaker_id", ""))
			if not speakers.has(sp):
				add.call("error", i, "등록되지 않은 화자 '%s' (data/speakers.json)" % sp)
			var ex := str(s.get("expression", ""))
			if ex != "" and speakers.has(sp) and not (speakers[sp].get("expressions", {}) as Dictionary).has(ex):
				add.call("warning", i, "화자 '%s'에 없는 표정 '%s' — 기본 초상화로 표시" % [sp, ex])
		if t == "image":
			var p := str(s.get("path", ""))
			if p != "" and not ResourceLoader.exists(p) and not FileAccess.file_exists(p):
				add.call("warning", i, "그림 파일이 아직 없다: %s — 게임에서는 자리표시로 나옴" % p)
		if t in ["actor_move", "actor_face"]:
			if not str(s.get("actor", "")) in actors:
				add.call("error", i, "알 수 없는 인물 '%s'" % s.get("actor", ""))
			var target: Variant = s.get("to", "player") if t == "actor_move" else s.get("target", "player")
			if target is String and not target in actors:
				add.call("error", i, "알 수 없는 대상 '%s'" % target)
		if t == "set_flag" and str(s.get("key", "")).strip_edges() == "":
			add.call("error", i, "플래그 키가 비어 있다")
		if s.has("seconds") and float(s.get("seconds", 0.0)) < 0.0:
			add.call("error", i, "시간이 음수")
	return out
