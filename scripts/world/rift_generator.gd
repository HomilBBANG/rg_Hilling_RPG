class_name RiftGenerator
extends RefCounted
## Random / roguelike dungeon floors (GDD 12.2 [확정]: a new structure every time you enter,
## several floors, find the exit on each floor). Builds a text grid in the fixed-dungeon legend
## (RegionDB._expand_dungeon) from a seed + floor number: rooms joined by corridors (plus a loop
## or two), start in the first room, the floor exit 'X' in the room farthest from it, monsters
## and chests in the other rooms. Deeper floors are bigger with more / stronger monsters.

## cfg (data/regions/<id>.json "generator"): {"width", "height", "rooms", "floors": [...], "chest_pool": [...]}
static func generate(seed_value: int, floor_n: int, cfg: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%d" % [seed_value, floor_n])
	var grow := mini(floor_n - 1, 4)
	var w := int(cfg.get("width", 30)) + grow * 2
	var h := int(cfg.get("height", 22)) + mini(floor_n - 1, 3) * 2
	var grid: Array[PackedStringArray] = []
	for y in h:
		var row := PackedStringArray()
		row.resize(w)
		row.fill("#")
		grid.append(row)
	var rooms: Array[Rect2i] = []
	var want := int(cfg.get("rooms", 5)) + mini(floor_n, 4)
	for t in 400:
		if rooms.size() >= want:
			break
		var rw := rng.randi_range(4, 7)
		var rh := rng.randi_range(3, 5)
		var r := Rect2i(rng.randi_range(1, w - rw - 2), rng.randi_range(1, h - rh - 2), rw, rh)
		var ok := true
		for o in rooms:
			if r.grow(1).intersects(o):
				ok = false
				break
		if ok:
			rooms.append(r)
			_carve_rect(grid, r)
	# chain the rooms in creation order, then a couple of extra links for loops
	for i in range(1, rooms.size()):
		_corridor(grid, _center(rooms[i - 1]), _center(rooms[i]), rng)
	for i in mini(2, rooms.size() / 3):
		var a := rng.randi_range(0, rooms.size() - 1)
		var b := rng.randi_range(0, rooms.size() - 1)
		if a != b:
			_corridor(grid, _center(rooms[a]), _center(rooms[b]), rng)
	var start := _center(rooms[0])
	var dist := _bfs(grid, start)
	var exit_room := 0
	var best := -1
	for i in rooms.size():
		var d := int(dist.get(_center(rooms[i]), -1))
		if d > best:
			best = d
			exit_room = i
	_put(grid, start, "S")
	_put(grid, _center(rooms[exit_room]), "X")
	# floor config (deeper floors reuse the last entry)
	var floors: Array = cfg.get("floors", [])
	var fc: Dictionary = floors[mini(floor_n, floors.size()) - 1] if not floors.is_empty() else {}
	var kinds: Dictionary = fc.get("kinds", {"cave_slime": 1})
	var letters := {}
	var spawn_kinds := {}
	var li := 0
	for k: String in kinds:
		var letter := "abcdefgh"[li]
		letters[k] = letter
		spawn_kinds[letter] = k
		li += 1
	var others: Array[int] = []
	for i in rooms.size():
		if i != 0:
			others.append(i)
	for i in rooms.size():
		_place_in(grid, rooms[i], "T", rng)
	var mrange: Array = fc.get("monsters", [3, 4])
	for i in rng.randi_range(int(mrange[0]), int(mrange[1])):
		var kind := _weighted(kinds, rng)
		_place_in(grid, rooms[others[rng.randi() % others.size()]], letters[kind], rng)
	var crange: Array = fc.get("chests", [1, 1])
	var chests := []
	for i in rng.randi_range(int(crange[0]), int(crange[1])):
		if _place_in(grid, rooms[others[rng.randi() % others.size()]], "C", rng):
			chests.append({"title": "미궁의 상자 (%d층)" % floor_n, "items": _chest_items(cfg.get("chest_pool", []), floor_n, rng)})
	var lines := PackedStringArray()
	for row in grid:
		lines.append("".join(row))
	return {"grid": Array(lines), "spawn_kinds": spawn_kinds, "chests": chests}


static func _center(r: Rect2i) -> Vector2i:
	return r.position + r.size / 2


static func _put(grid: Array[PackedStringArray], p: Vector2i, ch: String) -> void:
	grid[p.y][p.x] = ch


static func _carve_rect(grid: Array[PackedStringArray], r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			grid[y][x] = "."


static func _corridor(grid: Array[PackedStringArray], a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	var p := a
	var horizontal_first := rng.randf() < 0.5
	for leg in 2:
		var horiz := horizontal_first if leg == 0 else not horizontal_first
		while (p.x != b.x) if horiz else (p.y != b.y):
			if horiz:
				p.x += signi(b.x - p.x)
			else:
				p.y += signi(b.y - p.y)
			if grid[p.y][p.x] == "#":
				grid[p.y][p.x] = "."


static func _bfs(grid: Array[PackedStringArray], start: Vector2i) -> Dictionary:
	var dist := {start: 0}
	var q: Array[Vector2i] = [start]
	var i := 0
	while i < q.size():
		var c := q[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.y >= 0 and n.y < grid.size() and n.x >= 0 and n.x < grid[0].size() and grid[n.y][n.x] != "#" and not dist.has(n):
				dist[n] = int(dist[c]) + 1
				q.append(n)
	return dist


## A free floor cell inside the room (not next to the start / exit markers).
static func _place_in(grid: Array[PackedStringArray], r: Rect2i, ch: String, rng: RandomNumberGenerator) -> bool:
	for t in 30:
		var p := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))
		if grid[p.y][p.x] == ".":
			grid[p.y][p.x] = ch
			return true
	return false


static func _weighted(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	for k: String in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return weights.keys()[0]


## Deeper floors: more items per chest and rarer entries unlock (bigger reward for the risk).
static func _chest_items(pool: Array, floor_n: int, rng: RandomNumberGenerator) -> Dictionary:
	var allowed: Array = pool.filter(func(e: Dictionary) -> bool: return int(e.get("min_floor", 1)) <= floor_n)
	var weights := {}
	for i in allowed.size():
		weights[str(i)] = float(allowed[i].get("w", 1))
	var out := {}
	if allowed.is_empty():
		return out
	for n in 1 + floor_n:
		var e: Dictionary = allowed[int(_weighted(weights, rng))]
		var id: String
		if e.has("equip"):
			var opts: Array = e["equip"]
			id = ItemDB.acquire(str(opts[rng.randi() % opts.size()]), rng, minf(0.9, 0.5 + 0.1 * floor_n))
		else:
			id = str(e["item"])
		out[id] = int(out.get(id, 0)) + 1
	return out
