class_name LifeDB
extends RefCounted
## Life activities as data (res://data/life.json): gathering node kinds, the fish table, mastery
## level thresholds and life skills. GDD 5.4 [확정]: mastery grows by doing the activity and makes
## it better; life EXP is spent to learn life skills (some need a minimum mastery). Numbers [미정].

const PATH := "res://data/life.json"
const FIELDS := ["gathering", "fishing", "cooking", "crafting"]

static var _cache := {}


static func data() -> Dictionary:
	if _cache.is_empty():
		var d: Variant = DialogueData.read_json(PATH)
		_cache = d if d is Dictionary else {}
	return _cache


static func gather_kind(kind: String) -> Dictionary:
	return data().get("gather_kinds", {}).get(kind, {})


static func fishing() -> Dictionary:
	return data().get("fishing", {})


static func skill(id: String) -> Dictionary:
	return data().get("skills", {}).get(id, {})


static func field_name(field: String) -> String:
	return str(data().get("mastery_names", {}).get(field, field))


## Level 1.. from accumulated mastery points.
static func level_for(points: int) -> int:
	var lv := 0
	for t in data().get("mastery_levels", [0]):
		if points >= int(t):
			lv += 1
	return maxi(lv, 1)


## Points needed for the next level, or -1 at the top.
static func next_threshold(points: int) -> int:
	for t in data().get("mastery_levels", [0]):
		if points < int(t):
			return int(t)
	return -1
