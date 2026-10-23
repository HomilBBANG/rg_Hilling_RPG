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

## The region's ground as a picture (1 px = 1 m, covering RegionDB.map_rect): grass shaded by
## height, forests, water, roads, towns; fixed dungeons as their floor plan.
static func terrain_texture(rid: String) -> Texture2D:
	if _tex.has(rid):
		return _tex[rid]
	var reg: Dictionary = RegionDB.all()[rid]
	var img: Image
	if reg.get("kind", "") == "dungeon":
		var cl := float(reg.get("cell", 2.0))
		var cols := int(reg.get("_cols", 1))
		var rows := int(reg.get("_rows", 1))
		img = Image.create(maxi(1, int(cols * cl)), maxi(1, int(rows * cl)), false, Image.FORMAT_RGB8)
		img.fill(Color(0.14, 0.13, 0.16))
		for fc: Array in reg.get("_floor", []):
			img.fill_rect(Rect2i(int(int(fc[0]) * cl), int(int(fc[1]) * cl), int(cl), int(cl)), Color(0.55, 0.52, 0.5))
	else:
		var tf := TerrainField.new(reg.get("terrain", {}))
		var w := int(tf.bounds_max.x - tf.bounds_min.x)
		var h := int(tf.bounds_max.y - tf.bounds_min.y)
		img = Image.create(w, h, false, Image.FORMAT_RGB8)
		var g: Dictionary = reg.get("ground", {})
		var gm: Array = g.get("grass_mid", [0.42, 0.62, 0.32])
		var grass := Color(float(gm[0]), float(gm[1]), float(gm[2]))
		var heights := PackedFloat32Array()
		heights.resize((w + 1) * (h + 1))
		for z in h + 1:
			for x in w + 1:
				heights[z * (w + 1) + x] = tf.height(tf.bounds_min.x + x, tf.bounds_min.y + z)
		var towns: Array[Rect2] = []
		for ct: Dictionary in reg.get("cities", []):
			var c := TerrainField._v2(ct["center"], Vector2.ZERO)
			var sz := TerrainField._v2(ct.get("size", null), Vector2(40, 36))
			towns.append(Rect2(c - sz * 0.5, sz))
		for z in h:
			for x in w:
				var wx := tf.bounds_min.x + x + 0.5
				var wz := tf.bounds_min.y + z + 0.5
				var hh := heights[z * (w + 1) + x]
				var slope := heights[z * (w + 1) + x] - heights[(z + 1) * (w + 1) + x + 1]  # light from the north-west
				var col := grass.lightened(clampf(hh * 0.05, -0.2, 0.25)) if hh >= 0.0 else grass.darkened(clampf(-hh * 0.08, 0.0, 0.2))
				col = col.lightened(clampf(slope * 0.35, 0.0, 0.25)) if slope > 0.0 else col.darkened(clampf(-slope * 0.35, 0.0, 0.25))
				col = col.lerp(Color(0.2, 0.38, 0.2), tf.forest_mask(wx, wz) * 0.75)
				for r in towns:
					if r.has_point(Vector2(wx, wz)):
						col = col.lerp(Color(0.8, 0.74, 0.6), 0.55)
				var wd := tf.pond_distance(wx, wz)
				if wd < 0.0:
					col = Color(0.3, 0.55, 0.78).darkened(clampf(-wd * 0.02, 0.0, 0.25))
				elif wd < 1.2:
					col = Color(0.84, 0.77, 0.56)
				elif tf.path_distance(wx, wz) < 1.4:
					col = Color(0.8, 0.66, 0.44)
				img.set_pixel(x, z, col)
	var tex := ImageTexture.create_from_image(img)
	_tex[rid] = tex
	return tex


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
