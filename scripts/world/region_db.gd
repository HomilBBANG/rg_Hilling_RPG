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
				_cache[d["region_id"]] = _expand_dungeon(d) if d.get("kind", "") == "dungeon" else d  # random: per run
	return _cache


static func is_dungeon(region_id: String) -> bool:
	return all().get(region_id, {}).get("kind", "") in ["dungeon", "random_dungeon"]


## Fixed dungeon (GDD 12.1 [확정]: a hand-designed layout that never changes) drawn as a text
## grid; this turns it into the ordinary region fields (terrain bounds, spawns, checkpoint,
## exits, entries) so the world, death / loot rules, travel and map treat it like any region.
## Grid: '#' wall, '.' floor, '+' doorway, 'S' arrival, 'E' exit, 'K' safe checkpoint, 'T' torch,
## 'C' chest, other letters = monsters through "spawn_kinds".
static func _expand_dungeon(src: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	var grid: Array = d["grid"]
	var c := float(d.get("cell", 2.0))
	var rows := grid.size()
	var cols := str(grid[0]).length()
	var half := Vector2(cols, rows) * c * 0.5
	d["terrain"] = {"min": [-half.x - 8.0, -half.y - 8.0], "max": [half.x + 8.0, half.y + 8.0], "seed": 31,
		"hill_noise": 0.04, "pond": null, "camp_center": null, "paths": [], "mounds": [],
		"forest": {"center": [9999, 9999], "radius": 1}}
	var kinds: Dictionary = d.get("spawn_kinds", {})
	var once: Array = d.get("once", [])
	var monsters := []
	var checkpoints := []
	var exits := []
	var entries := {}
	var walls := []
	var torches := []
	var chests := []
	var floor := []
	var counts := {}
	for r in rows:
		var line := str(grid[r])
		for col in cols:
			var ch := line[col] if col < line.length() else "#"
			var w := grid_to_world(col, r, cols, rows, c)
			if ch == "#" or ch == " ":
				walls.append([col, r])
				continue
			floor.append([col, r])
			match ch:
				"T":
					torches.append([w.x, w.y])
				"C":
					chests.append([w.x, w.y])
				"X":
					d["_floor_exit"] = [w.x, w.y]
				"K":
					var sr: Dictionary = d.get("safe_room", {})
					checkpoints.append({"id": "safe_room", "name": sr.get("name", "쉼터"), "pos": [w.x, w.y],
						"radius": float(sr.get("radius", 6.0)), "marker": true})
				_:
					if kinds.has(ch):
						counts[ch] = int(counts.get(ch, 0)) + 1
						monsters.append({"id": "%s_%s%d" % [d["region_id"], ch, counts[ch]], "kind": kinds[ch], "pos": [w.x, w.y],
							"once": once.has(ch)})
			if d.get("exit_tiles", {}).has(ch):
				var e: Dictionary = d["exit_tiles"][ch].duplicate()
				e["pos"] = [w.x, w.y]
				e["radius"] = c * 0.7
				exits.append(e)
			for entry_id: String in d.get("entry_tiles", {}):
				var et: Dictionary = d["entry_tiles"][entry_id]
				if et.get("tile", "") == ch:
					entries[entry_id] = {"pos": [w.x, w.y], "yaw": float(et.get("yaw", 0.0))}
	d["monsters"] = monsters
	d["checkpoints"] = checkpoints
	d["exits"] = exits
	d["entries"] = entries
	if not entries.is_empty():
		d["default_spawn"] = entries.values()[0]
	d["_walls"] = walls
	d["_floor"] = floor
	d["_torches"] = torches
	d["_chests"] = chests
	d["_cols"] = cols
	d["_rows"] = rows
	return d


static func grid_to_world(col: int, row: int, cols: int, rows: int, cell: float) -> Vector2:
	return Vector2((col - cols * 0.5 + 0.5) * cell, (row - rows * 0.5 + 0.5) * cell)


static func info(region_id: String) -> Dictionary:
	var d: Dictionary = all().get(region_id, all().get(START, {}))
	if d.get("kind", "") == "random_dungeon":
		return _random_floor(d)
	return d


static var _floor_cache := {}


## Random dungeon (GDD 12.2): the current run's seed + floor decide the layout; outside a run a
## placeholder floor 1 is returned (never shown).
static func _random_floor(base: Dictionary) -> Dictionary:
	var run: Dictionary = Game.run if Game.run.get("dungeon", "") == base["region_id"] else {}
	var seed_value := int(run.get("seed", 0))
	var floor_n := int(run.get("floor", 1))
	var key := "%s|%d|%d" % [base["region_id"], seed_value, floor_n]
	if not _floor_cache.has(key):
		_floor_cache.clear()
		var d := base.duplicate(true)
		var gen := RiftGenerator.generate(seed_value, floor_n, d.get("generator", {}))
		d["grid"] = gen["grid"]
		d["spawn_kinds"] = gen["spawn_kinds"]
		d["chests"] = gen["chests"]
		d["entry_tiles"] = {"start": {"tile": "S", "yaw": PI}}
		d["floor"] = floor_n
		_floor_cache[key] = _expand_dungeon(d)
	return _floor_cache[key]


static func is_random_dungeon(region_id: String) -> bool:
	return all().get(region_id, {}).get("kind", "") == "random_dungeon"


static func region_name(region_id: String) -> String:
	return str(info(region_id).get("name", region_id))


static func danger_text(region_id: String) -> String:
	return "★".repeat(int(info(region_id).get("danger", 1)))


static func v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), 0.0, float(a[1])) if a is Array and (a as Array).size() >= 2 else Vector3.ZERO


static func entry(region_id: String, entry_id: String) -> Dictionary:
	return info(region_id).get("entries", {}).get(entry_id, {})
