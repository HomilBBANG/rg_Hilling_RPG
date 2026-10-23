@tool
class_name MapDB
extends RefCounted
## Region maps (user design, replacing GDD 11.3's "terrain and towns known from the start"): the
## player starts with no maps and gets one per region from a merchant, an NPC or a map lying in
## the field. A map shows its region's terrain (drawn from the region data) plus the marks the
## designer placed in the editor's 지도 tab. Owned maps: Game.maps_owned (saved).
##
## File res://data/maps/<region>.json:
##   {"version": 1, "map_id": "map.<region>", "region", "title", "order" (page order), "desc",
##    "marks": [{"id", "type": "label"|"icon"|"note", "icon": ICONS key, "text", "pos": [x, z]}],
##    "sources": [{"kind": "shop", "shop": shop id, "price"}
##                | {"kind": "npc", "speaker": speaker id, "note"}        (give with dialogue action give_map)
##                | {"kind": "drop", "region": region id, "pos": [x, z]}]}  (a map lying in the field)
## Mark / drop positions are region metres (x, z), like everything else in the region files.

const DIR := "res://data/maps"
const MARK_TYPES := ["label", "icon", "note"]
const TYPE_NAMES := {"label": "지명", "icon": "아이콘", "note": "메모"}
const ICONS := {"town": "마을", "camp": "야영지", "cave": "동굴", "shop": "상점", "danger": "위험", "quest": "의뢰",
	"road": "길 안내", "star": "볼거리", "water": "물가", "boss": "강한 적"}
const ICON_COLORS := {"town": Color(0.95, 0.8, 0.4), "camp": Color(0.95, 0.55, 0.25), "cave": Color(0.45, 0.38, 0.32),
	"shop": Color(0.45, 0.7, 0.95), "danger": Color(0.9, 0.3, 0.25), "quest": Color(1.0, 0.85, 0.2), "road": Color(0.95, 0.95, 0.9),
	"star": Color(1.0, 0.92, 0.5), "water": Color(0.35, 0.6, 0.9), "boss": Color(0.75, 0.15, 0.12)}
const SOURCE_KINDS := {"shop": "상점에서 판매", "npc": "NPC가 줌 (대화 액션 give_map)", "drop": "필드에 떨어져 있음"}

static var _cache := {}
static var _tex := {}  # region id -> ImageTexture (built once per session)


static func path_for(region: String) -> String:
	return DIR.path_join(region + ".json")


static func map_id_for(region: String) -> String:
	return "map." + region


static func region_of(map_id: String) -> String:
	return map_id.trim_prefix("map.")


static func is_map(id: String) -> bool:
	return id.begins_with("map.") and not info(region_of(id)).is_empty()


## Regions that can have a map: outdoor fields and fixed dungeons (not the random one, not interiors).
static func mappable(region: String) -> bool:
	var reg: Dictionary = RegionDB.all().get(region, {})
	return not reg.is_empty() and reg.get("kind", "") != "random_dungeon" and not reg.get("no_map", false)


static func all() -> Dictionary:
	if _cache.is_empty() or Engine.is_editor_hint():
		_cache = {}
		for p in DialogueData.list_files(DIR):
			var d: Variant = DialogueData.read_json(p)
			if d is Dictionary and d.has("region"):
				_cache[str(d["region"])] = d
	return _cache


## Map regions in page order ("order", then name).
static func ordered() -> Array:
	var out: Array = all().keys().filter(func(r: String) -> bool: return mappable(r))
	out.sort_custom(func(a: String, b: String) -> bool:
		var oa := int(info(a).get("order", 99))
		var ob := int(info(b).get("order", 99))
		return oa < ob if oa != ob else a < b)
	return out


static func info(region: String) -> Dictionary:
	return all().get(region, {})


static func reload() -> void:
	_cache = {}


static func title(region: String) -> String:
	return str(info(region).get("title", RegionDB.region_name(region) + " 지도"))


static func owned(region: String) -> bool:
	return not Engine.is_editor_hint() and Game.maps_owned.has(region)  # the editor has no game state


## Gives the region's map. Returns true the first time.
static func give(region: String) -> bool:
	if owned(region) or info(region).is_empty():
		return false
	Game.maps_owned.append(region)
	Game.combat_log.add("지도를 얻었다: %s" % title(region), "M으로 열어 볼 수 있다", "info")
	if Game.hud:
		Game.hud.toast_quest("지도 획득 — %s (M)" % title(region))
	return true


## Item-like info so shops and the bag can show a map: {name, weight, kind "map", value, desc}.
static func item_info(map_id: String) -> Dictionary:
	var r := region_of(map_id)
	var price := 0
	for s: Dictionary in info(r).get("sources", []):
		if s.get("kind", "") == "shop":
			price = int(s.get("price", 0))
	return {"name": title(r), "weight": 0.0, "kind": "map", "value": price, "desc": str(info(r).get("desc", "%s의 지형이 그려진 지도." % RegionDB.region_name(r)))}


## Map entries a shop sells: [[map id, price], ...] (only maps not owned yet).
static func shop_maps(shop_id: String) -> Array:
	var out := []
	for r: String in all():
		for s: Dictionary in info(r).get("sources", []):
			if s.get("kind", "") == "shop" and str(s.get("shop", "")) == shop_id:
				out.append([map_id_for(r), int(s.get("price", 0))])
	return out


## Field drops in a region still lying there: [{"region": map region, "index": i, "pos": Vector3}].
static func drops_in(region: String) -> Array:
	var out := []
	for r: String in all():
		var srcs: Array = info(r).get("sources", [])
		for i in srcs.size():
			var s: Dictionary = srcs[i]
			if s.get("kind", "") == "drop" and str(s.get("region", "")) == region and not owned(r):
				var p: Array = s.get("pos", [0, 0])
				out.append({"region": r, "index": i, "pos": Vector3(float(p[0]), 0.0, float(p[1]))})
	return out


## Short "how to get it" lines for the map screen / editor.
static func sources_text(region: String) -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in info(region).get("sources", []):
		match str(s.get("kind", "")):
			"shop":
				out.append("%s에서 %d 골드" % [ShopDB.info(str(s["shop"])).get("name", s["shop"]) if ShopDB.SHOPS.has(str(s.get("shop", ""))) else s.get("shop", "?"), int(s.get("price", 0))])
			"npc":
				out.append("%s%s" % [DialogueData.speakers().get(str(s.get("speaker", "")), {}).get("name", s.get("speaker", "?")), " — " + str(s["note"]) if str(s.get("note", "")) != "" else ""])
			"drop":
				out.append("%s 어딘가에 떨어져 있음" % RegionDB.region_name(str(s.get("region", ""))))
	return out


## Problems in a map file (editor + tours): [{severity, message}].
static func validate(d: Dictionary) -> Array:
	var out := []
	var r := str(d.get("region", ""))
	if not mappable(r):
		out.append({"severity": "error", "message": "지도를 둘 수 없는 지역 '%s'" % r})
	var ids := {}
	for m: Dictionary in d.get("marks", []):
		var id := str(m.get("id", ""))
		if id == "" or ids.has(id):
			out.append({"severity": "error", "message": "표시 ID가 비었거나 겹친다 (%s)" % id})
		ids[id] = true
		if not MARK_TYPES.has(m.get("type", "")):
			out.append({"severity": "error", "message": "알 수 없는 표시 종류 '%s'" % m.get("type", "")})
		if m.get("type", "") == "icon" and not ICONS.has(m.get("icon", "")):
			out.append({"severity": "error", "message": "알 수 없는 아이콘 '%s' (%s)" % [m.get("icon", ""), id]})
		if m.get("type", "") != "icon" and str(m.get("text", "")).strip_edges() == "":
			out.append({"severity": "warning", "message": "글자가 빈 표시 (%s)" % id})
	for s: Dictionary in d.get("sources", []):
		match str(s.get("kind", "")):
			"shop":
				if not ShopDB.SHOPS.has(str(s.get("shop", ""))):
					out.append({"severity": "error", "message": "없는 상점 '%s'" % s.get("shop", "")})
			"npc":
				pass
			"drop":
				if not mappable(str(s.get("region", ""))):
					out.append({"severity": "error", "message": "떨어뜨릴 수 없는 지역 '%s'" % s.get("region", "")})
			_:
				out.append({"severity": "error", "message": "알 수 없는 획득 방법 '%s'" % s.get("kind", "")})
	if d.get("sources", []).is_empty():
		out.append({"severity": "warning", "message": "얻을 방법이 없다 (상점·NPC·필드 드롭 중 하나 이상)"})
	return out


static func save(d: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(path_for(str(d["region"])), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "  ", false) + "\n")
	f.close()
	_cache = {}
	return OK


# ---------------------------------------------------------------- drawing

## Draws one designer mark at c (the map screen and the editor's 지도 tab look the same).
static func draw_mark(ci: CanvasItem, m: Dictionary, c: Vector2, f: Font, selected := false) -> void:
	var text := str(m.get("text", ""))
	match str(m.get("type", "label")):
		"icon":
			var col: Color = ICON_COLORS.get(str(m.get("icon", "")), Color.WHITE)
			if str(m.get("icon", "")) == "road":
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -6), c + Vector2(8, 0), c + Vector2(-7, 6), c + Vector2(-3, 0)]), col)
				ci.draw_polyline(PackedVector2Array([c + Vector2(-7, -6), c + Vector2(8, 0), c + Vector2(-7, 6), c + Vector2(-3, 0), c + Vector2(-7, -6)]), Color(0.15, 0.1, 0.05), 1.5)
			else:
				ci.draw_circle(c, 9.0, Color(0.15, 0.1, 0.05, 0.85))
				ci.draw_circle(c, 7.0, col)
			if text != "":
				text_on(ci, f, c + Vector2(12, 6), text, 16, Color(1.0, 0.97, 0.88))
		"note":
			var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 14.0
			var box := Rect2(c + Vector2(-4, -26), Vector2(maxf(w, 40.0), 24))
			ci.draw_rect(box, Color(1.0, 0.93, 0.55, 0.95))
			ci.draw_rect(box, Color(0.45, 0.35, 0.15), false, 1.5)
			ci.draw_colored_polygon(PackedVector2Array([c, c + Vector2(0, -3), c + Vector2(8, -3)]), Color(1.0, 0.93, 0.55, 0.95))
			ci.draw_string(f, box.position + Vector2(7, 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.25, 0.18, 0.08))
		_:
			text_on(ci, f, c - Vector2(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x * 0.5, -6), text, 18, Color(1.0, 0.96, 0.86))
	if selected:
		ci.draw_arc(c, 14.0, 0, TAU, 24, Color(1.0, 0.3, 0.3), 2.5)


static func text_on(ci: CanvasItem, f: Font, pos: Vector2, s: String, fsize: int, col: Color) -> void:
	ci.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, 0.85))
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)



# ---------------------------------------------------------------- terrain picture

## Flat map colours (parchment cartography — no hill shading, user request "평면").
const PARCHMENT := Color(0.86, 0.8, 0.64)
const SEA := Color(0.5, 0.58, 0.6)
const INK := Color(0.32, 0.25, 0.17)


## A region's land colour on the map: its grass toned down toward parchment.
static func land_color(reg: Dictionary) -> Color:
	var g: Dictionary = reg.get("ground", {})
	var gm: Array = g.get("grass_mid", [0.42, 0.62, 0.32])
	return Color(float(gm[0]), float(gm[1]), float(gm[2])).lerp(PARCHMENT, 0.42)


## The region's ground as a flat map picture (1 px = 1 m, covering region_rect): land colour,
## forests darker with little tree dots, water with an ink shoreline, roads as pale lines with ink
## edges, towns as light ground with an ink border. Fixed dungeons: their floor plan.
static func terrain_texture(rid: String) -> Texture2D:
	if _tex.has(rid):
		return _tex[rid]
	var img := terrain_image(rid)
	var tex := ImageTexture.create_from_image(img)
	_tex[rid] = tex
	return tex


static var _img := {}


static func terrain_image(rid: String) -> Image:
	if _img.has(rid):
		return _img[rid]
	var reg: Dictionary = RegionDB.all()[rid]
	var img: Image
	if reg.get("kind", "") == "dungeon":
		var cl := float(reg.get("cell", 2.0))
		var cols := int(reg.get("_cols", 1))
		var rows := int(reg.get("_rows", 1))
		img = Image.create(maxi(1, int(cols * cl)), maxi(1, int(rows * cl)), false, Image.FORMAT_RGB8)
		img.fill(Color(0.3, 0.27, 0.24))
		for fc: Array in reg.get("_floor", []):
			img.fill_rect(Rect2i(int(int(fc[0]) * cl), int(int(fc[1]) * cl), int(cl), int(cl)), PARCHMENT)
	else:
		var tf := TerrainField.new(reg.get("terrain", {}))
		var w := int(tf.bounds_max.x - tf.bounds_min.x)
		var h := int(tf.bounds_max.y - tf.bounds_min.y)
		img = Image.create(w, h, false, Image.FORMAT_RGB8)
		var land := land_color(reg)
		var forest := land.darkened(0.22).lerp(Color(0.3, 0.42, 0.28), 0.25)
		var water := Color(0.48, 0.62, 0.7)
		var road := Color(0.93, 0.88, 0.74)
		var towns: Array[Rect2] = []
		for ct: Dictionary in reg.get("cities", []):
			var c := TerrainField._v2(ct["center"], Vector2.ZERO)
			var sz := TerrainField._v2(ct.get("size", null), Vector2(40, 36))
			towns.append(Rect2(c - sz * 0.5, sz))
		for z in h:
			for x in w:
				var wx := tf.bounds_min.x + x + 0.5
				var wz := tf.bounds_min.y + z + 0.5
				var col := land
				var fm := tf.forest_mask(wx, wz)
				if fm > 0.45:
					col = forest
					if (x % 5 == 2 and z % 5 == 2) or (x % 5 == 0 and z % 5 == 4):
						col = forest.darkened(0.3)  # tree dots
				var in_town := false
				for r in towns:
					if r.has_point(Vector2(wx, wz)):
						in_town = true
						var edge := minf(minf(wx - r.position.x, r.end.x - wx), minf(wz - r.position.y, r.end.y - wz))
						col = INK if edge < 1.0 else land.lerp(PARCHMENT, 0.65)
				var wd := tf.pond_distance(wx, wz)
				var pd := tf.path_distance(wx, wz)
				if wd < -0.8:
					col = water
				elif wd < 0.4:
					col = INK.lerp(water, 0.35)  # shoreline
				elif pd < 1.2:
					col = road
				elif pd < 1.9 and not in_town:
					col = col.lerp(INK, 0.55)  # road edge
				img.set_pixel(x, z, col)
	_img[rid] = img
	return img


## The whole surface world as one continuous flat picture (world-map metres, 1 px = 1 m): every
## outdoor region at its map place, the land between and around them filled in with a ragged
## coastline, sea beyond. {"tex": ImageTexture, "rect": Rect2 in map metres}.
static var _world := {}


static func world_regions() -> Array:
	var out := []
	var all := RegionDB.all()
	for rid: String in all:
		var reg: Dictionary = all[rid]
		if reg.get("kind", "") in ["dungeon", "random_dungeon"] or reg.get("no_map", false):
			continue
		out.append(rid)
	return out


static func world_picture() -> Dictionary:
	if not _world.is_empty():
		return _world
	var regs := world_regions()
	var rects := {}
	var lands := {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for rid: String in regs:
		var r := RegionDB.map_rect(rid)
		rects[rid] = r
		var lc0 := land_color(RegionDB.all()[rid])
		lands[rid] = Color(roundf(lc0.r * 255.0) / 255.0, roundf(lc0.g * 255.0) / 255.0, roundf(lc0.b * 255.0) / 255.0)  # as stored (RGB8)
		lo = lo.min(r.position)
		hi = hi.max(r.end)
	var pad := 90.0
	var area := Rect2(lo - Vector2(pad, pad), hi - lo + Vector2(pad, pad) * 2.0).abs()
	var w := int(area.size.x)
	var h := int(area.size.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.018
	var noise2 := FastNoiseLite.new()
	noise2.seed = 21
	noise2.frequency = 0.07
	for z in h:
		for x in w:
			var p := area.position + Vector2(x + 0.5, z + 0.5)
			var col := Color.BLACK
			var inside := ""
			# land colour blended between regions (no hard seams), and the distance to the nearest one
			var best := INF
			var acc := Color(0, 0, 0, 0)
			var wsum := 0.0
			for rid: String in regs:
				var r: Rect2 = rects[rid]
				var d := Vector2(maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0), maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)).length()
				if d <= 0.0 and inside == "":
					inside = rid
				best = minf(best, d)
				var wgt := 1.0 / pow(d + 14.0, 3.0)
				var lc: Color = lands[rid]
				acc += Color(lc.r * wgt, lc.g * wgt, lc.b * wgt, 0.0)
				wsum += wgt
			var blend := Color(acc.r / wsum, acc.g / wsum, acc.b / wsum)
			if inside != "":
				var rr: Rect2 = rects[inside]
				var rimg := terrain_image(inside)
				col = rimg.get_pixel(clampi(int(p.x - rr.position.x), 0, rimg.get_width() - 1), clampi(int(p.y - rr.position.y), 0, rimg.get_height() - 1))
				var lq: Color = lands[inside]
				if absf(col.r - lq.r) + absf(col.g - lq.g) + absf(col.b - lq.b) < 0.01:
					col = blend  # plain ground: the blended colour; forests / water / roads stay
			else:
				var coast := 26.0 + noise.get_noise_2dv(p) * 22.0 + noise2.get_noise_2dv(p) * 5.0
				if best < coast - 4.0:
					col = blend  # wild land between / around regions
				elif best < coast - 1.5:
					col = Color(0.9, 0.84, 0.66)  # beach
				elif best < coast:
					col = INK.lerp(SEA, 0.3)  # coastline ink
				else:
					var wave := noise2.get_noise_2d(p.x * 0.6, p.y * 2.4)
					col = SEA.lightened(0.06) if absf(wave) < 0.04 else SEA  # faint wave lines
			img.set_pixel(x, z, col)
	_world = {"tex": ImageTexture.create_from_image(img), "rect": area}
	return _world


## The area a region's picture covers, in region metres (fixed dungeons: their grid).
static func region_rect(rid: String) -> Rect2:
	var reg: Dictionary = RegionDB.all().get(rid, {})
	if reg.get("kind", "") == "dungeon":
		var cl := float(reg.get("cell", 2.0))
		var sz := Vector2(int(reg.get("_cols", 1)), int(reg.get("_rows", 1))) * cl
		return Rect2(-sz * 0.5, sz)
	var t: Dictionary = reg.get("terrain", {})
	var mn := TerrainField._v2(t.get("min", null), TerrainField.MIN)
	var mx := TerrainField._v2(t.get("max", null), TerrainField.MAX)
	return Rect2(mn, mx - mn)
