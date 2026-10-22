@tool
class_name MonsterDB
extends RefCounted
## Monster definitions (res://data/monsters.json). GDD 7.5 [확정]: strength is fixed by the
## monster / region definition, never scaled to the player's level. Numbers are [미정].
##
## kind: {"name", "aggressive", "hp", "exp", "profile": {hit_bonus, crit_chance, phys, str_mult, ac, armor},
##        "colors": {"body", "light", "core"} | null (default blue), "scale",
##        "loot": [{"item", "chance", "dice"?} | {"equip_pool": [...], "chance", "option_chance"}]}

const PATH := "res://data/monsters.json"

static var _cache := {}


static func all() -> Dictionary:
	if _cache.is_empty():
		var d: Variant = DialogueData.read_json(PATH)
		_cache = d.get("monsters", {}) if d is Dictionary else {}
	return _cache


static func reload() -> void:
	_cache = {}


static func info(kind: String) -> Dictionary:
	return all().get(kind, all().get("meadow_slime", {}))


static func roll_loot(kind: String, rng: RandomNumberGenerator) -> Inventory:
	var inv := Inventory.new()
	for e: Dictionary in info(kind).get("loot", []):
		var chance := float(e.get("chance", 1.0))
		if chance < 1.0 and rng.randf() >= chance:  # sure drops roll nothing (same RNG use as before)
			continue
		if e.has("equip_pool"):
			var pool: Array = e["equip_pool"]
			inv.add(ItemDB.acquire(str(pool[rng.randi() % pool.size()]), rng, float(e.get("option_chance", 0.5))), 1)
		else:
			inv.add(str(e["item"]), Dice.roll(str(e["dice"]))["total"] if e.has("dice") else 1)
	return inv
