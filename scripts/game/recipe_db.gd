@tool  # item descriptions (ItemDB, used by the dialogue editor) name recipes
class_name RecipeDB
extends RefCounted
## Recipes as data (res://data/recipes.json). GDD 14.4 [확정]: choose a learned recipe, its
## ingredients are used up and the result is made - no free combination. Simple crafting works
## anywhere; cooking and complex crafting need a facility. Basic recipes are learned with life EXP,
## special ones come from NPCs, books, quests or exploration. Numbers are [미정].
##
## recipe: {"name", "field": "cooking"|"crafting" (mastery), "facility": ""|"cooking"|"workbench",
##          "inputs": {item: n}, "outputs": {item: n}, "time", "life_exp", "mastery",
##          "learn": "known"|"basic"|"special", "cost" (life EXP, basic), "req": {field: level}, "source"}

const PATH := "res://data/recipes.json"

static var _cache := {}


static func data() -> Dictionary:
	if _cache.is_empty():
		var d: Variant = DialogueData.read_json(PATH)
		_cache = d if d is Dictionary else {}
	return _cache


static func all() -> Dictionary:
	return data().get("recipes", {})


static func info(id: String) -> Dictionary:
	return all().get(id, {})


static func recipe_name(id: String) -> String:
	return str(info(id).get("name", id))


static func facility_name(f: String) -> String:
	return str(data().get("facilities", {}).get(f, "어디서나"))


static func inputs_text(id: String) -> String:
	var parts := PackedStringArray()
	var inputs: Dictionary = info(id).get("inputs", {})
	for item: String in inputs:
		parts.append("%s ×%d" % [ItemDB.item_name(item), int(inputs[item])])
	return " + ".join(parts)


static func outputs_text(id: String) -> String:
	var parts := PackedStringArray()
	var outs: Dictionary = info(id).get("outputs", {})
	for item: String in outs:
		parts.append("%s ×%d" % [ItemDB.item_name(item), int(outs[item])])
	return ", ".join(parts)
