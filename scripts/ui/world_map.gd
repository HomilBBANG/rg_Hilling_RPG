class_name WorldMap
extends Control
## The world map (M), GDD 11.3 / 11.4. Regions are drawn side by side by their "map.origin" as
## a small terrain picture (grass shaded by height, forests, water, roads, towns) - the basic
## terrain and the major towns are known from the start; checkpoints, hidden places (dungeons)
## and their roads appear once found. The player, the parked camper and the player's own pins
## with a memo are drawn on top.
##
## Mouse: wheel = zoom, drag = move, click a town = its card (fast travel), click a pin = edit,
## right click = new pin. Buttons: whole map / where am I.
## Fast travel itself is bootstrap.fast_travel_quote() / fast_travel().

const PIN_LIMIT := 40
const CITY_PICK := 16.0
const PIN_PICK := 11.0

static var _terrain_tex := {}  # region id -> ImageTexture (built once per session)

var font: Font
var boot: Node
var _zoom := 1.0       # screen pixels per map metre
var _offset := Vector2.ZERO  # screen position of map (0, 0)
var _fit_zoom := 1.0
var _drag_from := Vector2.INF
var _drag_moved := false
var _card: PanelContainer
var _card_box: VBoxContainer
var selected_city := ""
var selected_pin := -1


## Hidden places (dungeons) appear only once found (GDD 11.3).
static func known(id: String, reg: Dictionary) -> bool:
	if reg.get("kind", "") == "random_dungeon" or reg.get("no_map", false):
		return false  # changes every visit / an interior (throne room): nothing to map
	return not reg.get("hidden", false) or Game.discovered.has("region:" + id)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.065, 0.09, 0.95)
	sb.border_color = Color(0.72, 0.58, 0.36)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	_card.add_theme_stylebox_override("panel", sb)
	_card.custom_minimum_size.x = 360
	_card.visible = false
	add_child(_card)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 8)
	_card.add_child(_card_box)
	var bar := HBoxContainer.new()
	bar.position = Vector2(10, 10)
	add_child(bar)
	for spec in [["전체 지도", fit_all], ["현재 위치", center_on_player], ["＋", func() -> void: zoom_at(size * 0.5, 1.4)], ["－", func() -> void: zoom_at(size * 0.5, 1.0 / 1.4)]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(spec[1])
		bar.add_child(b)
	resized.connect(fit_all)
	fit_all.call_deferred()


# ---------------------------------------------------------------- view

func _known_regions() -> Array:
	var out := []
	var all := RegionDB.all()
	for rid: String in all:
		if known(rid, all[rid]):
			out.append(rid)
	return out


func fit_all() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for rid: String in _known_regions():
		var r := RegionDB.map_rect(rid)
		lo = lo.min(r.position)
		hi = hi.max(r.end)
	if lo.x == INF or size.x < 10.0:
		return
	var pad := 40.0
	_fit_zoom = minf((size.x - pad * 2) / (hi.x - lo.x), (size.y - pad * 2) / (hi.y - lo.y))
	_zoom = _fit_zoom
	_offset = (size - (hi - lo) * _zoom) * 0.5 - lo * _zoom
	queue_redraw()


func center_on_player() -> void:
	var p := player_map_pos()
	if p.x == INF:
		return
	_zoom = maxf(_zoom, _fit_zoom * 2.5)
	_offset = size * 0.5 - p * _zoom
	queue_redraw()


func zoom_at(screen: Vector2, factor: float) -> void:
	var before := to_map(screen)
	_zoom = clampf(_zoom * factor, _fit_zoom * 0.7, _fit_zoom * 8.0)
	_offset = screen - before * _zoom
	queue_redraw()


func to_screen(p: Vector2) -> Vector2:
	return _offset + p * _zoom


func to_map(s: Vector2) -> Vector2:
	return (s - _offset) / _zoom


func player_map_pos() -> Vector2:
	var w: Node = Game.boot.world if Game.boot else null
	if not (w is VisualLab) or w.player == null or RegionDB.is_random_dungeon(Game.region):
		return Vector2.INF
	var pp: Vector3 = w.vehicle.global_position if w.vehicle.driving else w.player.global_position
	return RegionDB.map_pos(Game.region, Vector2(pp.x, pp.z))


# ---------------------------------------------------------------- input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		match ev.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_at(ev.position, 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_at(ev.position, 1.0 / 1.15)
			MOUSE_BUTTON_LEFT:
				_drag_from = ev.position
				_drag_moved = false
			MOUSE_BUTTON_RIGHT:
				add_pin(to_map(ev.position))
		accept_event()
	elif ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if not _drag_moved and _drag_from != Vector2.INF:
			click(ev.position)
		_drag_from = Vector2.INF
		accept_event()
	elif ev is InputEventMouseMotion and _drag_from != Vector2.INF:
		if (ev.position - _drag_from).length() > 4.0 or _drag_moved:
			_drag_moved = true
			_offset += ev.relative
			queue_redraw()
		accept_event()


## A click on the map: a town opens its card, a pin opens its memo, elsewhere closes the card.
func click(screen: Vector2) -> void:
	var cities := RegionDB.cities()
	for id: String in cities:
		if to_screen(cities[id]["map"]).distance_to(screen) < CITY_PICK:
			open_city(id)
			return
	for i in Game.map_pins.size():
		if to_screen(_pin_pos(i)).distance_to(screen) < PIN_PICK:
			open_pin(i)
			return
	close_card()


func _pin_pos(i: int) -> Vector2:
	var p: Array = Game.map_pins[i]["pos"]
	return Vector2(float(p[0]), float(p[1]))


# ---------------------------------------------------------------- pins (GDD 11.3 [미정]: placeholder pin + memo)

func add_pin(at: Vector2) -> int:
	if Game.map_pins.size() >= PIN_LIMIT:
		_show_card([_label("핀은 %d개까지 꽂을 수 있다" % PIN_LIMIT, 18)])
		return -1
	Game.map_pins.append({"pos": [snappedf(at.x, 0.1), snappedf(at.y, 0.1)], "text": ""})
	open_pin(Game.map_pins.size() - 1)
	queue_redraw()
	return Game.map_pins.size() - 1


func open_pin(i: int) -> void:
	selected_pin = i
	selected_city = ""
	var memo := LineEdit.new()
	memo.placeholder_text = "메모 (예: 달빛 꽃 자리)"
	memo.text = str(Game.map_pins[i].get("text", ""))
	memo.max_length = 40
	memo.custom_minimum_size.x = 320
	memo.text_changed.connect(func(t: String) -> void:
		if i < Game.map_pins.size():
			Game.map_pins[i]["text"] = t
			queue_redraw())
	var del := _button("핀 지우기", func() -> void: remove_pin(i))
	_show_card([_label("내 핀", 22, Color(1.0, 0.86, 0.5)), memo, del, _label("지도를 오른쪽 클릭하면 새 핀", 15, Color(0.7, 0.72, 0.76))])
	memo.grab_focus.call_deferred()


func remove_pin(i: int) -> void:
	if i >= 0 and i < Game.map_pins.size():
		Game.map_pins.remove_at(i)
	close_card()
	queue_redraw()


# ---------------------------------------------------------------- town card + fast travel (GDD 11.4)

func open_city(id: String) -> void:
	selected_city = id
	selected_pin = -1
	var c: Dictionary = RegionDB.cities()[id]
	var visited := Game.discovered.has("city:" + id)
	var rows: Array[Control] = [_label(c["name"], 24, Color(1.0, 0.86, 0.5)),
		_label("%s · %s" % ["주요 도시 (왕도)" if c["kind"] == "capital" else "주요 도시 (마을)", RegionDB.region_name(c["region"])], 17, Color(0.75, 0.78, 0.82)),
		_label("방문함 — 빠른 이동 목적지" if visited else "아직 가 보지 않음 — 한 번 가 봐야 빠른 이동 목적지가 된다", 17,
			Color(0.6, 1.0, 0.6) if visited else Color(1.0, 0.75, 0.55))]
	if boot and visited:
		var q: Dictionary = boot.fast_travel_quote(id)
		if q.get("ok", false):
			rows.append(_label("출발: %s → 거리 %d m" % [q["from_name"], int(q["distance"])], 17))
			rows.append(_label("걸리는 시간: %s" % _hours(float(q["minutes"])), 17))
			rows.append(_label("캠핑카와 함께 (요금 없음, 연료 %.0f L)" % float(q["fuel"]) if q["with_camper"] else "마차 삯: %d 골드 (캠핑카 없이)" % int(q["gold"]), 17,
				Color(0.85, 0.95, 1.0)))
			if str(q.get("camper_note", "")) != "":
				rows.append(_label(q["camper_note"], 16, Color(1.0, 0.75, 0.55)))
			rows.append(_button("빠른 이동", func() -> void: boot.fast_travel(id)))
		else:
			rows.append(_label(str(q.get("why", "")), 17, Color(1.0, 0.7, 0.6)))
	_show_card(rows)


static func _hours(minutes: float) -> String:
	var m := roundi(minutes)
	return "%d시간 %02d분" % [m / 60, m % 60] if m >= 60 else "%d분" % m


func _show_card(rows: Array) -> void:
	for ch in _card_box.get_children():
		_card_box.remove_child(ch)
		ch.queue_free()
	for r: Control in rows:
		_card_box.add_child(r)
	_card.visible = true
	_card.reset_size()
	_card.position = Vector2(size.x - _card.size.x - 14, 14)
	queue_redraw()


func close_card() -> void:
	_card.visible = false
	selected_city = ""
	selected_pin = -1
	queue_redraw()


func _label(text: String, fs: int, col := Color(0.92, 0.92, 0.9)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 330
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


# ---------------------------------------------------------------- terrain pictures

## One pixel per metre: grass shaded by height and slope, forests, water and sand, roads, town
## ground. Built once per region per session.
static func terrain_texture(rid: String) -> Texture2D:
	if _terrain_tex.has(rid):
		return _terrain_tex[rid]
	var reg: Dictionary = RegionDB.all()[rid]
	var tf := TerrainField.new(reg.get("terrain", {}))
	var w := int(tf.bounds_max.x - tf.bounds_min.x)
	var h := int(tf.bounds_max.y - tf.bounds_min.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
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
	_terrain_tex[rid] = tex
	return tex


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.12, 0.15))
	var regions := _known_regions()
	var all := RegionDB.all()
	# road links between regions (under the pictures); hidden ones once found
	for rid: String in regions:
		var reg: Dictionary = all[rid]
		for ex: Dictionary in reg.get("exits", []):
			if ex.get("hidden", false) and not Game.discovered.has("%s:%s" % [rid, ex["id"]]):
				continue
			if not regions.has(ex["to_region"]):
				continue
			var e := RegionDB.entry(ex["to_region"], ex["to_entry"])
			if e.is_empty():
				continue
			draw_line(to_screen(RegionDB.map_pos(rid, ex["pos"])), to_screen(RegionDB.map_pos(ex["to_region"], e["pos"])), Color(0.8, 0.66, 0.44), maxf(2.0, 1.6 * _zoom))
	for rid: String in regions:
		var reg: Dictionary = all[rid]
		var r := RegionDB.map_rect(rid)
		var sr := Rect2(to_screen(r.position), r.size * _zoom)
		if reg.get("kind", "") == "dungeon":
			draw_rect(sr, Color(0.14, 0.13, 0.16))
			var cl := float(reg.get("cell", 2.0))
			for fc: Array in reg.get("_floor", []):
				var wpos := RegionDB.grid_to_world(int(fc[0]), int(fc[1]), int(reg["_cols"]), int(reg["_rows"]), cl)
				draw_rect(Rect2(to_screen(RegionDB.map_pos(rid, wpos - Vector2(cl, cl) * 0.5)), Vector2(cl, cl) * _zoom), Color(0.55, 0.52, 0.5))
		else:
			draw_texture_rect(terrain_texture(rid), sr, false)
		draw_rect(sr, Color(1.0, 0.92, 0.6) if rid == Game.region else Color(0, 0, 0, 0.6), false, 3.0 if rid == Game.region else 2.0)
		_text(sr.position + Vector2(10, 26), "%s  %s" % [reg.get("name", rid), "★".repeat(int(reg.get("danger", 1)))], 20, Color(1, 0.95, 0.8))
		# checkpoints that were visited, hidden entrances that were found
		for cp: Dictionary in reg.get("checkpoints", []):
			if Game.discovered.has("%s:%s" % [rid, cp["id"]]):
				var c := to_screen(RegionDB.map_pos(rid, cp["pos"]))
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 5), c + Vector2(-7, 5)]), Color(0.45, 0.9, 0.85))
				draw_polyline(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 5), c + Vector2(-7, 5), c + Vector2(0, -8)]), Color(0, 0, 0, 0.7), 1.5)
				if _zoom > _fit_zoom * 1.6:
					_text(c + Vector2(10, 5), str(cp["name"]), 15, Color(0.85, 0.95, 0.92))
		for tr: Dictionary in reg.get("story_triggers", []):  # found story spots (the nest...)
			if str(tr.get("map_name", "")) != "" and Game.discovered.has("trig:%s:%s" % [rid, tr["id"]]):
				var c6 := to_screen(RegionDB.map_pos(rid, tr["pos"]))
				draw_colored_polygon(PackedVector2Array([c6 + Vector2(0, -8), c6 + Vector2(8, 0), c6 + Vector2(0, 8), c6 + Vector2(-8, 0)]), Color(0.95, 0.35, 0.2))
				draw_polyline(PackedVector2Array([c6 + Vector2(0, -8), c6 + Vector2(8, 0), c6 + Vector2(0, 8), c6 + Vector2(-8, 0), c6 + Vector2(0, -8)]), Color(0, 0, 0, 0.8), 1.5)
				_text(c6 + Vector2(11, 5), str(tr["map_name"]), 15, Color(1.0, 0.85, 0.75))
		for ex: Dictionary in reg.get("exits", []):
			var st := str(ex.get("style", ""))
			if (st == "cave" or st == "rift") and Game.discovered.has("%s:%s" % [rid, ex["id"]]):
				var c2 := to_screen(RegionDB.map_pos(rid, ex["pos"]))
				draw_circle(c2, 7.0, Color(0.35, 0.25, 0.45) if st == "rift" else Color(0.3, 0.27, 0.24))
				draw_arc(c2, 7.0, 0, TAU, 16, Color(0.9, 0.85, 0.75), 2.0)
				_text(c2 + Vector2(10, 5), str(ex["name"]), 15, Color(0.92, 0.88, 0.8))
	# major towns: always shown (GDD 11.3)
	var cities := RegionDB.cities()
	for id: String in cities:  # town walls
		var ct0: Dictionary = cities[id]
		var tr: Rect2 = ct0["rect"]
		draw_rect(Rect2(to_screen(RegionDB.map_pos(ct0["region"], tr.position)), tr.size * _zoom), Color(0.42, 0.3, 0.2, 0.9), false, maxf(1.5, 0.8 * _zoom))
	for id: String in cities:
		var ct: Dictionary = cities[id]
		var c3 := to_screen(ct["map"])
		var big: bool = ct["kind"] == "capital"
		var rad := 11.0 if big else 8.0
		draw_circle(c3, rad + 3.0, Color(0, 0, 0, 0.6))
		draw_circle(c3, rad, Color(0.95, 0.82, 0.45) if Game.discovered.has("city:" + id) else Color(0.7, 0.66, 0.58))
		if big:
			draw_colored_polygon(PackedVector2Array([c3 + Vector2(-6, 3), c3 + Vector2(-6, -3), c3 + Vector2(-3, 0), c3 + Vector2(0, -5),
				c3 + Vector2(3, 0), c3 + Vector2(6, -3), c3 + Vector2(6, 3)]), Color(0.4, 0.25, 0.1))
		else:
			draw_rect(Rect2(c3 - Vector2(3, 2), Vector2(6, 5)), Color(0.4, 0.25, 0.1))
		if id == selected_city:
			draw_arc(c3, rad + 6.0, 0, TAU, 24, Color(1, 1, 1), 2.5)
		_text(c3 + Vector2(rad + 6, 6), ct["name"], 20 if big else 17, Color(1.0, 0.95, 0.82))
	# my pins
	for i in Game.map_pins.size():
		var pp := to_screen(_pin_pos(i))
		draw_line(pp, pp + Vector2(0, -16), Color(0.15, 0.1, 0.1), 2.0)
		draw_circle(pp + Vector2(0, -18), 6.0, Color(0.95, 0.35, 0.4) if i != selected_pin else Color(1.0, 0.8, 0.3))
		draw_circle(pp, 2.5, Color(0.15, 0.1, 0.1))
		var memo := str(Game.map_pins[i].get("text", ""))
		if memo != "":
			_text(pp + Vector2(9, -14), memo, 15, Color(1.0, 0.9, 0.9))
	# camper and player
	if Game.has_camper and regions.has(str(Game.camper.get("region", ""))):
		var cpos: Variant = Game.camper.get("pos", null)
		var cv: Vector3 = cpos if cpos is Vector3 else VisualLab.CAMPER_POS
		var c4 := to_screen(RegionDB.map_pos(str(Game.camper["region"]), Vector2(cv.x, cv.z)))
		draw_rect(Rect2(c4 - Vector2(8, 6), Vector2(16, 12)), Color(0.95, 0.95, 0.9))
		draw_rect(Rect2(c4 - Vector2(8, 6), Vector2(16, 12)), Color(0.2, 0.3, 0.6), false, 2.0)
	var pm := player_map_pos()
	if pm.x != INF:
		var c5 := to_screen(pm)
		var w: Node = Game.boot.world
		var yaw: float = w.player.facing_yaw() if w.player.has_method("facing_yaw") else 0.0
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		draw_colored_polygon(PackedVector2Array([c5 + fwd * 12.0, c5 - fwd * 7.0 + side * 7.0, c5 - fwd * 3.0, c5 - fwd * 7.0 - side * 7.0]), Color(1.0, 0.35, 0.3))
		draw_arc(c5, 13.0, 0, TAU, 20, Color(1, 1, 1, 0.9), 2.0)
	# legend
	var lg := "● 도시(노랑 = 가 본 곳)   ▲ 체크포인트   ◉ 던전 입구   ■ 캠핑카   ➤ 나   ♦ 내 핀 (오른쪽 클릭)   휠 확대 · 드래그 이동"
	_text(Vector2(14, size.y - 14), lg, 16, Color(0.85, 0.87, 0.9))


func _text(pos: Vector2, s: String, fsize: int, col: Color) -> void:
	var f: Font = font if font else get_theme_default_font()
	draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, 0.85))
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
