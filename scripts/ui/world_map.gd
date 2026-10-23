class_name WorldMap
extends Control
## The map screen (M). User design: the player starts without maps and collects one per region
## (MapDB: from merchants, NPCs, or lying in the field). Each owned map is shown on its own sheet,
## every sheet the same size whatever the region's real size: the region's terrain (from the region
## data), the designer's marks (data/maps, editor 지도 tab), towns (click = card with fast travel,
## GDD 11.4), found checkpoints, the parked camper, the player and the player's own pins.
##
## Left: the list of maps (owned ones open, others "지도 없음"). ◀ ▶ / list = turn the page.
## 세계 지도: every surface region at its real place — terrain shape and name only (no marks,
## towns, pins or player); clicking a region whose map is owned opens that map. 현재 지도 = back.
## Right click on the sheet = new pin, click a pin = edit, click a town = its card.
## Fast travel itself is bootstrap.fast_travel_quote() / fast_travel().

const PIN_LIMIT := 40
const CITY_PICK := 16.0
const PIN_PICK := 11.0
const SHEET := Vector2(780, 780)  ## every region's map sheet has this size
const SHEET_POS := Vector2(300, 20)
const MARGIN := 46.0

var font: Font
var boot: Node
var page := ""  ## region id of the sheet on screen ("" = no maps yet)
## World map view (button 세계 지도): every surface region by its real place, shape and name only.
var world_view := false
var _w_zoom := 1.0
var _w_off := Vector2.ZERO
var _scale := 1.0      # sheet pixels per region metre
var _origin := Vector2.ZERO  # screen position of region (0, 0)
var _card: PanelContainer
var _card_box: VBoxContainer
var _list: VBoxContainer
var _title_bar: HBoxContainer
var selected_city := ""
var selected_pin := -1


## A region's map is known once the player owns it (MapDB).
static func known(id: String, _reg: Dictionary = {}) -> bool:
	return MapDB.owned(id)


static func terrain_texture(rid: String) -> Texture2D:
	return MapDB.terrain_texture(rid)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_list = VBoxContainer.new()
	_list.position = Vector2(10, 20)
	_list.custom_minimum_size.x = 270
	_list.add_theme_constant_override("separation", 6)
	add_child(_list)
	_title_bar = HBoxContainer.new()
	add_child(_title_bar)
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
	set_page(Game.region)  # M opens the map of where the hero is (an empty sheet if not owned yet)


# ---------------------------------------------------------------- pages

## Regions that have a map, in the maps' "order" (set in the editor's 지도 tab).
func _map_regions() -> Array:
	return MapDB.ordered()


## Owned maps, in map order.
func _known_regions() -> Array:
	return _map_regions().filter(func(r: String) -> bool: return MapDB.owned(r))


func set_page(rid: String) -> void:
	world_view = false
	page = rid if MapDB.owned(rid) else ""
	close_card()
	fit_all()
	_rebuild_side()


func turn(step: int) -> void:
	var owned := _known_regions()
	if owned.is_empty():
		return
	var i := owned.find(page)
	set_page(str(owned[posmod(i + step, owned.size())]))


## Lays the page's region into the sheet (same sheet size for every region).
func fit_all() -> void:
	if page == "":
		queue_redraw()
		return
	var r := MapDB.region_rect(page)
	var inner := Rect2(SHEET_POS + Vector2(MARGIN, MARGIN + 18), SHEET - Vector2(MARGIN * 2, MARGIN * 2 + 18))
	_scale = minf(inner.size.x / r.size.x, inner.size.y / r.size.y)
	var drawn := r.size * _scale
	_origin = inner.position + (inner.size - drawn) * 0.5 - r.position * _scale
	queue_redraw()


## Shows the map of the region the player is in (when owned).
func center_on_player() -> void:
	if MapDB.owned(Game.region) and page != Game.region:
		set_page(Game.region)


func _rebuild_side() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var head := _label("가진 지도 %d / %d" % [_known_regions().size(), _map_regions().size()], 20, Color(1.0, 0.88, 0.55))
	head.custom_minimum_size.x = 270
	_list.add_child(head)
	for rid: String in _map_regions():
		var have := MapDB.owned(rid)
		var b := _button((MapDB.title(rid) if have else "???  (지도 없음)"), func() -> void: set_page(rid))
		b.custom_minimum_size.x = 270
		b.disabled = not have
		b.toggle_mode = true
		b.button_pressed = rid == page
		b.tooltip_text = "" if have else "%s — 상인·NPC에게서 얻거나 필드에서 주울 수 있다" % RegionDB.region_name(rid)
		_list.add_child(b)
	var hint := _label("지도는 상인·NPC에게서 얻거나\n필드에 떨어진 것을 주워 모은다.\n오른쪽 클릭 = 내 핀", 15, Color(0.7, 0.72, 0.76))
	hint.custom_minimum_size.x = 270
	_list.add_child(hint)
	for c in _title_bar.get_children():
		_title_bar.remove_child(c)
		c.queue_free()
	_title_bar.position = SHEET_POS + Vector2(SHEET.x + 14, 0)
	if world_view:
		_title_bar.position = Vector2(size.x - 200, 20)
		_title_bar.add_child(_button("현재 지도", func() -> void:
			set_page(Game.region if MapDB.owned(Game.region) else page)))
		return
	if _known_regions().size() > 1:
		_title_bar.add_child(_button("◀", func() -> void: turn(-1)))
		_title_bar.add_child(_button("▶", func() -> void: turn(1)))
	if MapDB.owned(Game.region) and page != Game.region:
		_title_bar.add_child(_button("현재 위치", center_on_player))
	_title_bar.add_child(_button("세계 지도", func() -> void: show_world(true)))


# ---------------------------------------------------------------- world map view

## Surface regions on the world map: the outdoor fields (not dungeons, interiors or the random
## dungeon), whether or not their map is owned — the world map only shows shapes and names.
func world_regions() -> Array:
	var out := []
	var all := RegionDB.all()
	for rid: String in all:
		var reg: Dictionary = all[rid]
		if reg.get("kind", "") in ["dungeon", "random_dungeon"] or reg.get("no_map", false):
			continue
		if reg.get("hidden", false) and not Game.discovered.has("region:" + rid):
			continue
		out.append(rid)
	return out


func show_world(on: bool) -> void:
	world_view = on
	close_card()
	if on:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for rid: String in world_regions():
			var r := RegionDB.map_rect(rid)
			lo = lo.min(r.position)
			hi = hi.max(r.end)
		var area := _world_area()
		if lo.x != INF:
			_w_zoom = minf((area.size.x - 60.0) / (hi.x - lo.x), (area.size.y - 60.0) / (hi.y - lo.y))
			_w_off = area.position + (area.size - (hi - lo) * _w_zoom) * 0.5 - lo * _w_zoom
	_rebuild_side()
	queue_redraw()


func _world_area() -> Rect2:
	return Rect2(SHEET_POS, Vector2(maxf(SHEET.x, size.x - SHEET_POS.x - 220.0), SHEET.y))


func world_to_screen(map_p: Vector2) -> Vector2:
	return _w_off + map_p * _w_zoom


## Region under a screen point on the world map ("" = none).
func world_region_at(screen: Vector2) -> String:
	for rid: String in world_regions():
		var r := RegionDB.map_rect(rid)
		if Rect2(world_to_screen(r.position), r.size * _w_zoom).has_point(screen):
			return rid
	return ""


# ---------------------------------------------------------------- coordinates

func to_screen_local(p: Vector2) -> Vector2:
	return _origin + p * _scale


func to_local_pos(s: Vector2) -> Vector2:
	return (s - _origin) / _scale


## World-map metres (pins, cities) -> sheet pixels, for the page's region.
func to_screen(map_p: Vector2) -> Vector2:
	return to_screen_local(map_p - RegionDB.map_pos(page, Vector2.ZERO))


func to_map(s: Vector2) -> Vector2:
	return RegionDB.map_pos(page, to_local_pos(s))


func _sheet_rect() -> Rect2:
	return Rect2(SHEET_POS, SHEET)


func player_map_pos() -> Vector2:
	var w: Node = Game.boot.world if Game.boot else null
	if not (w is VisualLab) or w.player == null or RegionDB.is_random_dungeon(Game.region):
		return Vector2.INF
	var pp: Vector3 = w.vehicle.global_position if w.vehicle.driving else w.player.global_position
	return RegionDB.map_pos(Game.region, Vector2(pp.x, pp.z))


# ---------------------------------------------------------------- input

func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	if world_view:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			var rid := world_region_at(ev.position)
			if rid != "" and MapDB.owned(rid):
				set_page(rid)  # a region with its map: open that map
			accept_event()
		return
	if page == "" or not _sheet_rect().has_point(ev.position):
		return
	match ev.button_index:
		MOUSE_BUTTON_LEFT:
			click(ev.position)
		MOUSE_BUTTON_RIGHT:
			add_pin(to_map(ev.position))
	accept_event()


## A click on the sheet: a town opens its card, a pin opens its memo, elsewhere closes the card.
func click(screen: Vector2) -> void:
	var cities := RegionDB.cities()
	for id: String in cities:
		if cities[id]["region"] == page and to_screen(cities[id]["map"]).distance_to(screen) < CITY_PICK:
			open_city(id)
			return
	for i in Game.map_pins.size():
		if _pin_on_page(i) and to_screen(_pin_pos(i)).distance_to(screen) < PIN_PICK:
			open_pin(i)
			return
	close_card()


func _pin_pos(i: int) -> Vector2:
	var p: Array = Game.map_pins[i]["pos"]
	return Vector2(float(p[0]), float(p[1]))


func _pin_on_page(i: int) -> bool:
	return page != "" and _sheet_rect().has_point(to_screen(_pin_pos(i)))


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
	_card.position = Vector2(size.x - _card.size.x - 14, 70)
	queue_redraw()


func close_card() -> void:
	if _card:
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


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.12, 0.15))
	if world_view:
		_draw_world()
		return
	var sheet := _sheet_rect()
	draw_rect(sheet.grow(6), Color(0.35, 0.25, 0.15))
	draw_rect(sheet, Color(0.88, 0.82, 0.67))
	if page == "":
		var here := RegionDB.region_name(Game.region)
		_text_centered(sheet.get_center() - Vector2(0, 20), "%s의 지도가 아직 없다" % here if MapDB.mappable(Game.region) else "아직 가진 지도가 없다", 28, Color(0.3, 0.22, 0.14))
		_text_centered(sheet.get_center() + Vector2(0, 22), "상인이나 NPC에게서 지도를 얻거나, 필드에 떨어진 지도를 주워 보자 (세계 지도는 위 버튼)", 18, Color(0.35, 0.28, 0.2))
		return
	var reg: Dictionary = RegionDB.all()[page]
	var r := MapDB.region_rect(page)
	var area := Rect2(to_screen_local(r.position), r.size * _scale)
	draw_texture_rect(MapDB.terrain_texture(page), area, false)
	draw_rect(area, Color(0.3, 0.22, 0.14), false, 2.0)
	_text_centered(SHEET_POS + Vector2(SHEET.x * 0.5, 40), "%s  %s" % [MapDB.title(page), "★".repeat(int(reg.get("danger", 1)))], 24, Color(0.25, 0.17, 0.1), false)
	# found checkpoints
	for cp: Dictionary in reg.get("checkpoints", []):
		if Game.discovered.has("%s:%s" % [page, cp["id"]]):
			var c := to_screen_local(TerrainField._v2(cp["pos"], Vector2.ZERO))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 5), c + Vector2(-7, 5)]), Color(0.45, 0.9, 0.85))
			draw_polyline(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 5), c + Vector2(-7, 5), c + Vector2(0, -8)]), Color(0, 0, 0, 0.7), 1.5)
	# designer marks (data/maps)
	for m: Dictionary in MapDB.info(page).get("marks", []):
		MapDB.draw_mark(self, m, to_screen_local(TerrainField._v2(m.get("pos", null), Vector2.ZERO)), font if font else get_theme_default_font())
	# towns (click = card)
	var cities := RegionDB.cities()
	for id: String in cities:
		var ct: Dictionary = cities[id]
		if ct["region"] != page:
			continue
		var c3 := to_screen(ct["map"])
		var big: bool = ct["kind"] == "capital"
		var rad := 11.0 if big else 8.0
		draw_circle(c3, rad + 3.0, Color(0, 0, 0, 0.6))
		draw_circle(c3, rad, Color(0.95, 0.82, 0.45) if Game.discovered.has("city:" + id) else Color(0.7, 0.66, 0.58))
		if id == selected_city:
			draw_arc(c3, rad + 6.0, 0, TAU, 24, Color(1, 1, 1), 2.5)
		_text(c3 + Vector2(rad + 6, 6), ct["name"], 20 if big else 17, Color(1.0, 0.95, 0.82))
	# my pins
	for i in Game.map_pins.size():
		if not _pin_on_page(i):
			continue
		var pp := to_screen(_pin_pos(i))
		draw_line(pp, pp + Vector2(0, -16), Color(0.15, 0.1, 0.1), 2.0)
		draw_circle(pp + Vector2(0, -18), 6.0, Color(0.95, 0.35, 0.4) if i != selected_pin else Color(1.0, 0.8, 0.3))
		draw_circle(pp, 2.5, Color(0.15, 0.1, 0.1))
		var memo := str(Game.map_pins[i].get("text", ""))
		if memo != "":
			_text(pp + Vector2(9, -14), memo, 15, Color(1.0, 0.9, 0.9))
	# camper and player
	if Game.has_camper and str(Game.camper.get("region", "")) == page:
		var cpos: Variant = Game.camper.get("pos", null)
		var cv: Vector3 = cpos if cpos is Vector3 else VisualLab.CAMPER_POS
		var c4 := to_screen_local(Vector2(cv.x, cv.z))
		draw_rect(Rect2(c4 - Vector2(8, 6), Vector2(16, 12)), Color(0.25, 0.5, 1.0))
		draw_rect(Rect2(c4 - Vector2(8, 6), Vector2(16, 12)), Color(0.9, 0.95, 1.0), false, 1.5)
	var pm := player_map_pos()
	if pm.x != INF and Game.region == page:
		var c5 := to_screen(pm)
		var w: Node = Game.boot.world
		var yaw: float = w.player.facing_yaw() if w.player.has_method("facing_yaw") else 0.0
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		draw_colored_polygon(PackedVector2Array([c5 + fwd * 12.0, c5 - fwd * 7.0 + side * 7.0, c5 - fwd * 3.0, c5 - fwd * 7.0 - side * 7.0]), Color(1.0, 0.35, 0.3))
		draw_arc(c5, 13.0, 0, TAU, 20, Color(1, 1, 1, 0.9), 2.0)
	# legend under the sheet
	var lg := "● 도시(노랑 = 가 본 곳, 클릭 = 빠른 이동)   ▲ 체크포인트   파란 ■ 캠핑카   ➤ 나   ♦ 내 핀 (오른쪽 클릭)"
	_text(Vector2(SHEET_POS.x, SHEET_POS.y + SHEET.y + 18), lg, 15, Color(0.85, 0.87, 0.9))


## World map: each surface region's terrain picture at its real place, with its name — nothing else.
func _draw_world() -> void:
	var area := _world_area()
	draw_rect(area.grow(6), Color(0.35, 0.25, 0.15))
	draw_rect(area, Color(0.88, 0.82, 0.67))
	_text_centered(area.position + Vector2(area.size.x * 0.5, 34), "세계 지도", 26, Color(0.25, 0.17, 0.1), false)
	var f: Font = font if font else get_theme_default_font()
	for rid: String in world_regions():
		var r := RegionDB.map_rect(rid)
		var sr := Rect2(world_to_screen(r.position), r.size * _w_zoom)
		draw_texture_rect(MapDB.terrain_texture(rid), sr, false)
		draw_rect(sr, Color(0.3, 0.22, 0.14), false, 2.0)
		var name := RegionDB.region_name(rid)
		var w := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		MapDB.text_on(self, f, sr.get_center() - Vector2(w * 0.5, -8), name, 22,
			Color(1.0, 0.86, 0.45) if rid == Game.region else Color(1.0, 0.97, 0.9))
	_text(Vector2(area.position.x, area.end.y + 18), "지역의 생김새와 이름만 — 자세한 지도는 지역 지도를 모아서 본다 (가진 지역 클릭 = 그 지역 지도)", 15, Color(0.85, 0.87, 0.9))


func _text(pos: Vector2, s: String, fsize: int, col: Color) -> void:
	MapDB.text_on(self, font if font else get_theme_default_font(), pos, s, fsize, col)


func _text_centered(pos: Vector2, s: String, fsize: int, col: Color, outline := false) -> void:
	var f: Font = font if font else get_theme_default_font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	if outline:
		MapDB.text_on(self, f, pos - Vector2(w * 0.5, 0), s, fsize, col)
	else:
		draw_string(f, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
