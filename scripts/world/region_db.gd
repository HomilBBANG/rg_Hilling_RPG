class_name RegionDB
extends RefCounted
## Outdoor regions as data (res://data/regions/<region_id>.json, GDD 11.1 [확정]: several wide
## region scenes joined by roads, a loading screen between them). A region file holds the terrain
## layout, monster spawns, safe checkpoints, exits / arrival points, map placement and loading
## tips; hand-built set pieces (camp, trade post, ...) are switched on by "features".
##
## Exit: {"id", "name", "pos": [x, z], "radius", "to_region", "to_entry"} - walking or driving into
## it travels; the camper comes along only when driven through. Entry: {"pos", "yaw", "camper_pos",
## "camper_yaw"} - where you arrive (a few metres inside, so you never bounce straight back).

const DIR := "res://data/regions"
const START := "meadow"

static var _cache := {}


static func all() -> Dictionary:
	if _cache.is_empty():
		for p in DialogueData.list_files(DIR):
			var d: Variant = DialogueData.read_json(p)
			if d is Dictionary and d.has("region_id"):
				_cache[d["region_id"]] = d
	return _cache


static func info(region_id: String) -> Dictionary:
	return all().get(region_id, all().get(START, {}))


static func region_name(region_id: String) -> String:
	return str(info(region_id).get("name", region_id))


static func danger_text(region_id: String) -> String:
	return "★".repeat(int(info(region_id).get("danger", 1)))


static func v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), 0.0, float(a[1])) if a is Array and (a as Array).size() >= 2 else Vector3.ZERO


static func entry(region_id: String, entry_id: String) -> Dictionary:
	return info(region_id).get("entries", {}).get(entry_id, {})
