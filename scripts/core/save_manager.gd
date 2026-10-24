class_name SaveManager
extends RefCounted
## Save slots. User decision: 3 slots, one character per slot - a new game claims an empty slot and
## that character keeps saving back into the same slot; another character needs another slot.
## When / how often the game saves is a GDD 17 [미정] item (see notes/IMPLEMENTATION_ASSUMPTIONS.md).
## Files: user://saves/slot<N>.save, Variant binary without objects (Inventory objects inside the
## field data are packed as {"__inv": items}).

const SLOTS := 3
const VERSION := 1

static var dir := "user://saves"
## Fresh-game state, captured once at startup (Game._ready): a new game applies it, and a save
## written by an older build is laid over it so newly added fields get their defaults.
static var defaults := {}


static func path(slot: int) -> String:
	return dir.path_join("slot%d.save" % slot)


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path(slot)) or FileAccess.file_exists(path(slot) + ".bak")


## {} = empty slot, {"broken": true} = unreadable file, else the whole save.
static func read(slot: int) -> Dictionary:
	for p: String in [path(slot), path(slot) + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		var v: Variant = f.get_var(false) if f else null
		if v is Dictionary and int((v as Dictionary).get("version", 0)) >= 1 and (v as Dictionary).has("state"):
			return v
		return {"broken": true}
	return {}


## Writes through a temporary file; the previous save is kept as .bak until the new one is in place.
static func write(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var p := path(slot)
	var f := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data, false)
	f.close()
	if FileAccess.file_exists(p):
		if FileAccess.file_exists(p + ".bak"):
			DirAccess.remove_absolute(p + ".bak")
		DirAccess.rename_absolute(p, p + ".bak")
	if DirAccess.rename_absolute(p + ".tmp", p) != OK:
		return false
	DirAccess.remove_absolute(p + ".bak")
	return true


static func delete(slot: int) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path(slot) + suffix):
			DirAccess.remove_absolute(path(slot) + suffix)


## Whole save: where the player stands plus every piece of play state.
static func capture(world_id: String, pos: Vector3, yaw: float) -> Dictionary:
	var st := Game.player_state
	var interior := world_id == String(Game.WORLD_INTERIOR)
	return {
		"version": VERSION,
		"meta": {"level": st.level, "where": "캠핑카 실내" if interior else RegionDB.region_name(Game.region),
			"day": Game.day, "clock": Game.clock_text(), "play_seconds": Game.play_seconds, "gold": st.gold,
			"saved_at": Time.get_datetime_string_from_system(false, true)},
		"world": world_id, "pos": pos, "yaw": yaw,
		"state": capture_state(),
	}


static func capture_state() -> Dictionary:
	var st := Game.player_state
	return {
		"minute": Game.minute_of_day, "day": Game.day, "play_seconds": Game.play_seconds,
		"lantern_on": Game.lantern_on, "camper_lights_on": Game.camper_lights_on,
		"has_camper": Game.has_camper, "cat_joined": Game.cat_joined, "cat_affection": Game.cat_affection,
		"camper_fuel": Game.camper_fuel, "camper_durability": Game.camper_durability, "camper_infinite_power": Game.camper_infinite_power,
		"camper_mods": Game.camper_mods.duplicate(true),
		"region": Game.region, "fields": _pack(Game.fields), "camper": Game.camper.duplicate(true),
		"discovered": Game.discovered.duplicate(true), "map_pins": Game.map_pins.duplicate(true), "maps_owned": Game.maps_owned.duplicate(), "shops": Game.shops.duplicate(true),
		"flags": Game.narrative.flags.duplicate(true), "quests": Game.quests.entries.duplicate(true),
		"storage": Game.storage.duplicate_items(), "hut_storage": Game.hut_storage.duplicate_items(),
		"item_instances": ItemDB.instances.duplicate(true), "item_next": ItemDB._next_instance,
		"log_level": Game.combat_log.level,
		"player": {
			"stats": st.stats.duplicate(), "hp": st.hp, "mp": st.mp, "sp": st.sp,
			"inventory": st.inventory.duplicate_items(), "equipment": st.equipment.duplicate(),
			"quick_items": Array(st.quick_items.duplicate()), "quick_skills": Array(st.quick_skills.duplicate()), "spells": Array(st.spells.duplicate()),
			"gold": st.gold, "level": st.level, "gen_exp": st.gen_exp, "life_exp": st.life_exp,
			"mastery": st.mastery.duplicate(), "life_skills": Array(st.life_skills.duplicate()), "recipes": Array(st.recipes.duplicate()),
			"stat_points": st.stat_points, "skills": st.skills.duplicate(),
		},
	}


## Puts a captured state back (laid over the fresh-game defaults). The world is reloaded afterwards.
static func apply_state(saved: Dictionary) -> void:
	var s: Dictionary = defaults.duplicate(true)
	var p: Dictionary = s["player"]
	for k: String in saved:
		if k != "player":
			s[k] = saved[k]
	var sp: Dictionary = saved.get("player", {})
	for k: String in sp:
		p[k] = sp[k]
	s = s.duplicate(true)
	p = s["player"]
	Game.minute_of_day = float(s["minute"])
	Game.day = int(s["day"])
	Game.play_seconds = float(s["play_seconds"])
	Game.lantern_on = bool(s["lantern_on"])
	Game.camper_lights_on = bool(s["camper_lights_on"])
	Game.has_camper = bool(s["has_camper"])
	Game.camper_mods = s.get("camper_mods", {}).duplicate(true)
	Game.camper_fuel = float(s.get("camper_fuel", Game.camper_fuel_max()))
	Game.camper_durability = float(s.get("camper_durability", Game.CAMPER_DURABILITY_MAX))
	Game.camper_infinite_power = bool(s.get("camper_infinite_power", false))
	Game.cat_joined = bool(s["cat_joined"])
	Game.cat_affection = int(s["cat_affection"])
	Game.region = str(s["region"])
	Game.fields = _unpack(s["fields"])
	Game.camper = s["camper"]
	Game.discovered = s["discovered"]
	Game.map_pins = s.get("map_pins", [])
	Game.maps_owned = s.get("maps_owned", []).duplicate()
	Game.shops = s["shops"]
	Game.narrative.flags = s["flags"]
	Game.quests.entries = s["quests"]
	Game.storage.items.assign(s["storage"])
	Game.hut_storage.items.assign(s.get("hut_storage", []))
	ItemDB.instances = s["item_instances"]
	ItemDB._next_instance = int(s["item_next"])
	Game.combat_log.entries.clear()
	Game.combat_log.level = int(s["log_level"])
	Game.run = {}
	Game.spawn_override = {}
	Game.previous_world = &""
	var st := Game.player_state
	st.stats = p["stats"]
	st.inventory.items.assign(p["inventory"])
	var eq: Dictionary = defaults["player"]["equipment"].duplicate()
	eq.merge(p["equipment"], true)
	st.equipment = eq
	st.quick_items.assign(p["quick_items"])
	st.quick_skills.assign(p["quick_skills"])
	st.spells.assign(p["spells"])
	st.cooldowns = {}
	st.gold = int(p["gold"])
	st.level = int(p["level"])
	st.gen_exp = int(p["gen_exp"])
	st.life_exp = int(p["life_exp"])
	var mastery: Dictionary = defaults["player"]["mastery"].duplicate()
	mastery.merge(p["mastery"], true)
	st.mastery = mastery
	st.life_skills.assign(p["life_skills"])
	st.recipes.assign(p["recipes"])
	st.stat_points = int(p["stat_points"])
	st.skills = p["skills"]
	st.hp = minf(float(p["hp"]), st.max_hp())
	st.mp = minf(float(p["mp"]), st.max_mp())
	st.sp = minf(float(p["sp"]), st.max_sp())
	st.changed.emit()
	Game.quests.changed.emit()
	Game.narrative.changed.emit()


## Inventory objects -> {"__inv": items}, recursively (field loot: corpses, bags, chests).
static func _pack(v: Variant) -> Variant:
	if v is Inventory:
		return {"__inv": (v as Inventory).duplicate_items()}
	if v is Dictionary:
		var d := {}
		for k: Variant in v:
			d[k] = _pack(v[k])
		return d
	if v is Array:
		var a := []
		for e: Variant in v:
			a.append(_pack(e))
		return a
	return v


static func _unpack(v: Variant) -> Variant:
	if v is Dictionary:
		if (v as Dictionary).has("__inv"):
			var inv := Inventory.new()
			inv.items.assign(v["__inv"])
			return inv
		var d := {}
		for k: Variant in v:
			d[k] = _unpack(v[k])
		return d
	if v is Array:
		var a := []
		for e: Variant in v:
			a.append(_unpack(e))
		return a
	return v
