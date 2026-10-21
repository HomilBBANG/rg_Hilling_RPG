@tool
class_name QuestDB
extends RefCounted
## Quest definitions as data (res://data/quests/<quest_id>.json), so new quests need no code.
##
## { "version": 1, "quest_id": "quest.rosa.jelly", "title": "", "desc": "",
##   "giver": "rosa",            speaker id (data/speakers.json)
##   "source": "npc" | "board" | "event",   GDD 13.1 acquisition routes
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
const SOURCE_NAMES := {"npc": "NPC 의뢰", "board": "게시판 의뢰", "event": "현장 사건"}

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
