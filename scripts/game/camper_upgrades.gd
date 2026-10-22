class_name CamperUpgrades
extends RefCounted
## Camper upgrades (GDD 9.2 [확정]): six fields — engine / fuel / power, driving, interior
## facilities, storage, exterior, magic interior rooms — plus the mechanic's advanced repair
## skill (9.5). Only bought from an NPC for gold or earned by finishing a quest; never with EXP.
## Data: res://data/camper_upgrades.json. Owned ids and the camper's own choices (name, paint,
## parts on/off, room purposes, placed decor) live in Game.camper_mods and are saved.
## Every effect value is a [미정] placeholder (notes/IMPLEMENTATION_ASSUMPTIONS.md).

const PATH := "res://data/camper_upgrades.json"
const BASE_FUEL_MAX := 60.0
const BASE_FUEL_PER_M := 0.04
const BASE_STORAGE := 100.0
const OFFROAD_SPEED := 0.65  ## speed share off the roads without the off-road kit

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = DialogueData.read_json(PATH)
		_data = d if d is Dictionary else {"upgrades": []}
	return _data


static func info(id: String) -> Dictionary:
	for u: Dictionary in data().get("upgrades", []):
		if u["id"] == id:
			return u
	return {}


static func vendor_name(vendor: String) -> String:
	return str(data().get("vendors", {}).get(vendor, {}).get("name", vendor))


static func category_name(cat: String) -> String:
	for c: Array in data().get("categories", []):
		if c[0] == cat:
			return str(c[1])
	return cat


static func for_vendor(vendor: String) -> Array:
	var out := []
	for u: Dictionary in data().get("upgrades", []):
		if u["vendor"] == vendor:
			out.append(u)
	return out


static func owned(id: String) -> bool:
	return (Game.camper_mods.get("owned", []) as Array).has(id)


## Merged value of one effect over everything owned: numbers take the best one (lowest for fuel
## use, highest otherwise), other values the last installed.
static func effect(key: String, fallback: Variant = null) -> Variant:
	var best: Variant = fallback
	for id: String in Game.camper_mods.get("owned", []):
		var e: Dictionary = info(id).get("effects", {})
		if not e.has(key):
			continue
		var v: Variant = e[key]
		if (v is float or v is int) and (best is float or best is int):
			best = minf(float(best), float(v)) if key == "fuel_per_m" else maxf(float(best), float(v))
		else:
			best = v
	return best


## "" when it can be bought now, otherwise why not.
static func block(id: String) -> String:
	var u := info(id)
	if u.is_empty():
		return "없는 개조"
	if owned(id):
		return "이미 달려 있다"
	if not Game.has_camper:
		return "아직 캠핑카가 없다"
	var req := str(u.get("requires", ""))
	if req != "" and not owned(req):
		return "먼저: " + str(info(req).get("name", req))
	var qid := str(u.get("quest", ""))
	if qid != "" and Game.quests.state(qid) != "completed":
		return "의뢰를 먼저 끝내야 한다"
	if Game.player_state.gold < int(u.get("gold", 0)):
		return "골드가 모자란다"
	return ""


## Buys / installs one upgrade. Returns "" on success or the reason.
static func buy(id: String) -> String:
	var why := block(id)
	if why != "":
		return why
	var u := info(id)
	Game.player_state.gold -= int(u.get("gold", 0))
	var list: Array = Game.camper_mods["owned"]
	list.append(id)
	apply_install(id)
	Game.combat_log.add("캠핑카 개조: %s" % u["name"], "%s — %s (%s)" % [vendor_name(str(u["vendor"])), u.get("desc", ""),
		"-%d 골드" % int(u["gold"]) if int(u.get("gold", 0)) > 0 else "의뢰 보상"], "info")
	Game.camper_changed.emit()
	return ""


## One-time results of installing (the tank switching to mana, paint / parts switching on...).
static func apply_install(id: String) -> void:
	var e: Dictionary = info(id).get("effects", {})
	if e.get("fuel_kind", "") == "magic":
		Game.camper_fuel = fuel_max()
	if e.get("infinite", false):
		Game.camper_infinite_power = true
	if e.has("paint"):
		Game.camper_mods["paint"] = str(e["paint"])
	if e.has("part"):
		var parts: Array = Game.camper_mods["parts"]
		if not parts.has(e["part"]):
			parts.append(e["part"])


# ---------------------------------------------------------------- derived camper numbers

static func fuel_kind() -> String:
	return str(effect("fuel_kind", "gasoline"))


static func fuel_name() -> String:
	return "마력" if fuel_kind() == "magic" else "연료"


static func fuel_max() -> float:
	return float(effect("fuel_max", BASE_FUEL_MAX))


static func fuel_per_m() -> float:
	return float(effect("fuel_per_m", BASE_FUEL_PER_M))


static func storage_capacity() -> float:
	var extra := 0.0
	for r: Dictionary in rooms():
		extra += float(purpose_info(str(r.get("purpose", ""))).get("storage_bonus", 0.0))
	return float(effect("storage", BASE_STORAGE)) + extra


static func speed_mult() -> float:
	return float(effect("speed_mult", 1.0))


static func turn_mult() -> float:
	return float(effect("turn_mult", 1.0))


static func offroad() -> bool:
	return bool(effect("offroad", false))


static func ram_mult() -> float:
	var parts: Array = Game.camper_mods.get("parts", [])
	return 0.6 if owned("part_bullbar") and parts.has("bullbar") else 1.0


static func has_facility(f: String) -> bool:
	for id: String in Game.camper_mods.get("owned", []):
		if info(id).get("effects", {}).get("facility", "") == f:
			return true
	return false


static func refine_bonus() -> int:
	return int(effect("refine_bonus", 0))


static func bed() -> String:
	return "bed" if owned("bed_full") else ("sofa" if owned("bed_sofa") else "cot")


static func bed_info() -> Dictionary:
	return data().get("beds", {}).get(bed(), {"name": "간이침대", "hp": 0.1})


static func rooms_max() -> int:
	return int(effect("rooms", 0))


## Magic room modules (9.1: prebuilt modules, the player picks each one's purpose), one entry per
## room the upgrades allow: {"purpose": "" | data room_purposes id}.
static func rooms() -> Array:
	var list: Array = Game.camper_mods.get("rooms", [])
	while list.size() < rooms_max():
		list.append({"purpose": ""})
	return list.slice(0, rooms_max())


static func purpose_info(id: String) -> Dictionary:
	return data().get("room_purposes", {}).get(id, {})


static func full_field_repair() -> bool:
	return str(effect("field_repair", "")) == "full"


static func paint_colors() -> Dictionary:
	return data().get("paints", {}).get(str(Game.camper_mods.get("paint", "classic")), {})


## Name for messages: the player's name for it, or plain "캠핑카".
static func camper_name() -> String:
	var n := str(Game.camper_mods.get("name", "")).strip_edges()
	return "캠핑카" if n == "" else "캠핑카 '%s'" % n


## Look key for the baked sprite: paint + parts that are switched on.
static func look_key() -> String:
	var parts: Array = (Game.camper_mods.get("parts", []) as Array).duplicate()
	parts.sort()
	return "%s|%s" % [Game.camper_mods.get("paint", "classic"), ",".join(parts)]
