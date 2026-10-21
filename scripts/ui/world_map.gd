class_name WorldMap
extends Control
## World map drawing: every region from data/regions laid out by its "map.origin" (metres), its
## roads, safe checkpoints that were visited, road links between regions, the player and the
## camper. Basic terrain is shown from the start (GDD 11.3); visited places get their marker.

var font: Font


func _draw() -> void:
	var regions := RegionDB.all()
	if regions.is_empty():
		return
	# overall bounds in map space
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id: String in regions:
		var r := _rect(regions[id])
		lo = lo.min(r.position)
		hi = hi.max(r.end)
	var pad := 30.0
	var k := minf((size.x - pad * 2) / (hi.x - lo.x), (size.y - pad * 2) / (hi.y - lo.y))
	var off := Vector2(pad, pad) + ((size - Vector2(pad, pad) * 2) - (hi - lo) * k) * 0.5
	var to_screen := func(p: Vector2) -> Vector2: return off + (p - lo) * k
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.1, 0.9))
	# links first (under the regions)
	for id: String in regions:
		var reg: Dictionary = regions[id]
		for ex: Dictionary in reg.get("exits", []):
			var other: Dictionary = regions.get(ex["to_region"], {})
			var e: Dictionary = other.get("entries", {}).get(ex["to_entry"], {})
			if other.is_empty() or e.is_empty():
				continue
			var a: Vector2 = to_screen.call(_world_to_map(reg, ex["pos"]))
			var b: Vector2 = to_screen.call(_world_to_map(other, e["pos"]))
			draw_line(a, b, Color(0.95, 0.8, 0.45), 3.0)
	for id: String in regions:
		var reg: Dictionary = regions[id]
		var r := _rect(reg)
		var col_a: Array = reg.get("map", {}).get("color", [0.4, 0.55, 0.35])
		var col := Color(float(col_a[0]), float(col_a[1]), float(col_a[2]))
		var sr := Rect2(to_screen.call(r.position), r.size * k)
		draw_rect(sr, col.darkened(0.25))
		draw_rect(sr, col.lightened(0.3) if id == Game.region else col.darkened(0.5), false, 3.0 if id == Game.region else 1.5)
		var t: Dictionary = reg.get("terrain", {})
		var fo: Variant = t.get("forest", null)
		if fo is Dictionary:
			draw_circle(to_screen.call(_world_to_map(reg, fo["center"])), float(fo["radius"]) * k, col.darkened(0.45))
		var pd: Variant = t.get("pond", null)
		if pd is Dictionary:
			draw_circle(to_screen.call(_world_to_map(reg, pd["center"])), float(pd["radius"]) * k * 0.8, Color(0.3, 0.55, 0.75))
		for line: Array in t.get("paths", []):
			var pts := PackedVector2Array()
			for p: Array in line:
				pts.append(to_screen.call(_world_to_map(reg, p)))
			draw_polyline(pts, Color(0.78, 0.62, 0.4), 3.0)
		for cp: Dictionary in reg.get("checkpoints", []):
			if Game.discovered.has("%s:%s" % [id, cp["id"]]):
				var c: Vector2 = to_screen.call(_world_to_map(reg, cp["pos"]))
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 5), c + Vector2(-7, 5)]), Color(0.45, 0.9, 0.85))
				_text(c + Vector2(10, 5), str(cp["name"]), 15, Color(0.85, 0.95, 0.92))
		_text(sr.position + Vector2(8, 22), "%s  %s" % [reg.get("name", id), "★".repeat(int(reg.get("danger", 1)))], 20, Color(1, 0.95, 0.8))
	# camper and player
	if Game.has_camper and regions.has(str(Game.camper.get("region", ""))):
		var cpos: Variant = Game.camper.get("pos", null)
		var creg: Dictionary = regions[str(Game.camper["region"])]
		var cv: Vector3 = cpos if cpos is Vector3 else VisualLab.CAMPER_POS
		var c2: Vector2 = to_screen.call(_world_to_map(creg, [cv.x, cv.z]))
		draw_rect(Rect2(c2 - Vector2(7, 5), Vector2(14, 10)), Color(0.95, 0.95, 0.9))
		draw_rect(Rect2(c2 - Vector2(7, 5), Vector2(14, 10)), Color(0.2, 0.3, 0.6), false, 2.0)
	var w: Node = Game.boot.world if Game.boot else null
	if w is VisualLab and w.player:
		var pp: Vector3 = w.vehicle.global_position if w.vehicle.driving else w.player.global_position
		var c3: Vector2 = to_screen.call(_world_to_map(RegionDB.info(Game.region), [pp.x, pp.z]))
		draw_circle(c3, 7.0, Color(1.0, 0.35, 0.3))
		draw_arc(c3, 10.0, 0, TAU, 20, Color(1, 1, 1), 2.0)


func _text(pos: Vector2, s: String, fsize: int, col: Color) -> void:
	if font:
		draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, 0.8))
		draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


static func _rect(reg: Dictionary) -> Rect2:
	var t: Dictionary = reg.get("terrain", {})
	var mn := TerrainField._v2(t.get("min", null), TerrainField.MIN)
	var mx := TerrainField._v2(t.get("max", null), TerrainField.MAX)
	var o := TerrainField._v2(reg.get("map", {}).get("origin", null), Vector2.ZERO)
	return Rect2(o, mx - mn)


static func _world_to_map(reg: Dictionary, p: Variant) -> Vector2:
	var t: Dictionary = reg.get("terrain", {})
	var mn := TerrainField._v2(t.get("min", null), TerrainField.MIN)
	var o := TerrainField._v2(reg.get("map", {}).get("origin", null), Vector2.ZERO)
	return o + TerrainField._v2(p, Vector2.ZERO) - mn
