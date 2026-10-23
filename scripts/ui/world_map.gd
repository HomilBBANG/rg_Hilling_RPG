class_name WorldMap
extends Control
## The map screen (M), drawn as one continuous flat map (user design, like an open-world RPG map):
## every outdoor region joined to its neighbours at the roads, the land around them filled in to a
## ragged coastline, sea beyond (MapDB.world_picture). Flat parchment style — no hill shading.
##
## M opens the zoomed map centred on the hero: regions whose map the player owns show their terrain,
## the designer's marks (data/maps, editor 지도 tab), towns (click = card with fast travel, GDD
## 11.4), found checkpoints, the parked camper, the player and the player's own pins; regions
## without the map are under clouds. Wheel = zoom, drag = move, right click = new pin.
## 세계 지도: the whole continent — terrain shape and region names only; regions never visited hide
## under grey clouds; clicking a region whose map is owned zooms to it. 현재 지도 = back to the hero.
## Left: owned maps (click = look at that region). Fast travel: bootstrap.fast_travel_quote() / fast_travel().

const PIN_LIMIT := 40
const CITY_PICK := 16.0
const PIN_PICK := 11.0
const VIEW_POS := Vector2(300, 20)
const VIEW_H := 750.0
const LOCAL_ZOOM := 2.4  ## default zoom of the map around the hero (screen px per metre)
const ZOOM_MIN := 1.1
const ZOOM_MAX := 7.0

var font: Font
var boot: Node
var page := ""  ## region the zoomed map is looking at ("" = none)
## World map view (button 세계 지도): the whole continent, shape and names only.
var world_view := false
var _zoom := LOCAL_ZOOM
var _off := Vector2.ZERO  # screen position of world-map (0, 0)
var _drag_from := Vector2.INF
var _drag_moved := false
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
	resized.connect(func() -> void:
		if world_view:
			show_world(true))
	center_on_player.call_deferred()


# ---------------------------------------------------------------- views

func view_rect() -> Rect2:
	return Rect2(VIEW_POS, Vector2(maxf(600.0, size.x - VIEW_POS.x - 20.0), VIEW_H))


## Regions that have a map, in the maps' "order" (set in the editor's 지도 tab).
func _map_regions() -> Array:
	return MapDB.ordered()


## Owned maps, in map order.
func _known_regions() -> Array:
	return _map_regions().filter(func(r: String) -> bool: return MapDB.owned(r))


## Surface regions on the world map (outdoor fields; hidden ones once found).
func world_regions() -> Array:
	return MapDB.world_regions().filter(func(r: String) -> bool:
		return not RegionDB.all()[r].get("hidden", false) or Game.discovered.has("region:" + r))


## A fixed dungeon is not part of the continent: its map is its own floor plan.
func _is_dungeon(rid: String) -> bool:
	return str(RegionDB.all().get(rid, {}).get("kind", "")) == "dungeon"


## Zoomed map looking at a region (its centre, or the hero when the hero is there).
func set_page(rid: String) -> void:
	if not MapDB.world_regions().has(rid) and not (_is_dungeon(rid) and MapDB.mappable(rid)):
		show_world(true)  # an interior / the random dungeon: no zoomed map, show the world
		return
	world_view = false
	page = rid
	_zoom = LOCAL_ZOOM
	if _is_dungeon(rid):
		close_card()
		_rebuild_side()
		queue_redraw()
		return
	var c := player_map_pos() if rid == Game.region and player_map_pos().x != INF else RegionDB.map_rect(rid).get_center()
	_look_at(c)
	close_card()
	_rebuild_side()


func turn(step: int) -> void:
	var owned := _known_regions()
	if owned.is_empty():
		return
	var i := owned.find(page)
	set_page(str(owned[posmod(i + step, owned.size())]))


func _look_at(map_p: Vector2) -> void:
	_off = view_rect().get_center() - map_p * _zoom
	queue_redraw()


## Back to the zoomed map around the hero (M opens here).
func center_on_player() -> void:
	set_page(Game.region)


func fit_all() -> void:
	show_world(true)


func show_world(on: bool) -> void:
	if not on:
		center_on_player()
		return
	world_view = true
	close_card()
	var wr: Rect2 = MapDB.world_picture()["rect"]
	var v := view_rect()
	_zoom = minf((v.size.x - 20.0) / wr.size.x, (v.size.y - 20.0) / wr.size.y)
	_off = v.get_center() - wr.get_center() * _zoom
	_rebuild_side()
	queue_redraw()


func zoom_at(screen: Vector2, factor: float) -> void:
	var before := to_map(screen)
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_off = screen - before * _zoom
	queue_redraw()


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
		b.button_pressed = rid == page and not world_view
		b.tooltip_text = "" if have else "%s — 상인·NPC에게서 얻거나 필드에서 주울 수 있다" % RegionDB.region_name(rid)
		_list.add_child(b)
	var hint := _label("지도는 상인·NPC에게서 얻거나\n필드에 떨어진 것을 주워 모은다.\n휠 = 확대 · 끌기 = 이동\n오른쪽 클릭 = 내 핀", 15, Color(0.7, 0.72, 0.76))
	hint.custom_minimum_size.x = 270
	_list.add_child(hint)
	for c in _title_bar.get_children():
		_title_bar.remove_child(c)
		c.queue_free()
	var v := view_rect()
	_title_bar.position = Vector2(v.end.x - 330, v.position.y + 10)
	if world_view:
		_title_bar.add_child(_button("현재 지도", center_on_player))
	else:
		_title_bar.add_child(_button("현재 위치", center_on_player))
		_title_bar.add_child(_button("세계 지도", func() -> void: show_world(true)))


# ---------------------------------------------------------------- coordinates

## World-map metres -> screen.
func to_screen(map_p: Vector2) -> Vector2:
	return _off + map_p * _zoom


func to_map(s: Vector2) -> Vector2:
	return (s - _off) / _zoom


func world_to_screen(map_p: Vector2) -> Vector2:
	return to_screen(map_p)


## Region under a screen point ("" = none).
func world_region_at(screen: Vector2) -> String:
	var p := to_map(screen)
	for rid: String in world_regions():
		if RegionDB.map_rect(rid).has_point(p):
			return rid
	return ""


func player_map_pos() -> Vector2:
	var w: Node = Game.boot.world if Game.boot else null
	if not (w is VisualLab) or w.player == null or RegionDB.is_random_dungeon(Game.region):
		return Vector2.INF
	var pp: Vector3 = w.vehicle.global_position if w.vehicle.driving else w.player.global_position
	return RegionDB.map_pos(Game.region, Vector2(pp.x, pp.z))


# ---------------------------------------------------------------- input

func _gui_input(ev: InputEvent) -> void:
	var v := view_rect()
	if ev is InputEventMouseButton and ev.pressed:
		if not v.has_point(ev.position):
			return
		match ev.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if not world_view:
					zoom_at(ev.position, 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if not world_view:
					zoom_at(ev.position, 1.0 / 1.15)
			MOUSE_BUTTON_LEFT:
				if world_view:
					var rid := world_region_at(ev.position)
					if rid != "" and MapDB.owned(rid):
						set_page(rid)  # a region with its map: zoom to it
				else:
					_drag_from = ev.position
					_drag_moved = false
			MOUSE_BUTTON_RIGHT:
				if not world_view and MapDB.owned(world_region_at(ev.position)):
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
			_off += ev.relative
			queue_redraw()
		accept_event()


## A click on the zoomed map: a town opens its card, a pin opens its memo, elsewhere closes the card.
func click(screen: Vector2) -> void:
	var cities := RegionDB.cities()
	for id: String in cities:
		if MapDB.owned(str(cities[id]["region"])) and to_screen(cities[id]["map"]).distance_to(screen) < CITY_PICK:
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
	var v := view_rect()
	draw_rect(v.grow(6), Color(0.35, 0.25, 0.15))
	var wp: Dictionary = MapDB.world_picture()
	var wr: Rect2 = wp["rect"]
	draw_rect(v, MapDB.SEA)
	if world_view or not _is_dungeon(page):
		draw_texture_rect(wp["tex"], Rect2(to_screen(wr.position), wr.size * _zoom), false)
	if world_view:
		_draw_world_layer()
	elif _is_dungeon(page):
		_draw_dungeon_sheet()
	else:
		_draw_local_layer()
	# mask everything that spilled outside the map frame, then the frame
	var bg := Color(0.1, 0.12, 0.15)
	draw_rect(Rect2(0, 0, v.position.x - 6, size.y), bg)
	draw_rect(Rect2(v.end.x + 6, 0, size.x - v.end.x, size.y), bg)
	draw_rect(Rect2(0, 0, size.x, v.position.y - 6), bg)
	draw_rect(Rect2(0, v.end.y + 6, size.x, size.y - v.end.y), bg)
	draw_rect(v.grow(3), Color(0.35, 0.25, 0.15), false, 6.0)
	if world_view:
		_text(Vector2(v.position.x, v.end.y + 24), "세계 지도 — 지역의 생김새와 이름만 · 안 가 본 곳은 구름 (지도를 가진 지역 클릭 = 그 지역 확대)", 15, Color(0.85, 0.87, 0.9))
	else:
		_text(Vector2(v.position.x, v.end.y + 24), "● 도시(노랑 = 가 본 곳, 클릭 = 빠른 이동)   ▲ 체크포인트   파란 ■ 캠핑카   ➤ 나   ♦ 내 핀 (오른쪽 클릭)   지도 없는 지역 = 구름", 15, Color(0.85, 0.87, 0.9))


## The zoomed map: details on owned maps, clouds over the rest.
func _draw_local_layer() -> void:
	var v := view_rect()
	var f: Font = font if font else get_theme_default_font()
	for rid: String in world_regions():
		var r := RegionDB.map_rect(rid)
		var sr := Rect2(to_screen(r.position), r.size * _zoom)
		if not sr.intersects(v.grow(60)):
			continue
		if not MapDB.owned(rid):
			_draw_clouds(sr, rid, false)
			continue
		var reg: Dictionary = RegionDB.all()[rid]
		for cp: Dictionary in reg.get("checkpoints", []):
			if Game.discovered.has("%s:%s" % [rid, cp["id"]]):
				var c := to_screen(RegionDB.map_pos(rid, cp["pos"]))
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 5), c + Vector2(-7, 5)]), Color(0.45, 0.9, 0.85))
				draw_polyline(PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 5), c + Vector2(-7, 5), c + Vector2(0, -8)]), Color(0, 0, 0, 0.7), 1.5)
		for m: Dictionary in MapDB.info(rid).get("marks", []):
			MapDB.draw_mark(self, m, to_screen(RegionDB.map_pos(rid, m.get("pos", [0, 0]))), f)
	# towns on owned maps
	var cities := RegionDB.cities()
	for id: String in cities:
		var ct: Dictionary = cities[id]
		if not MapDB.owned(str(ct["region"])):
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
		var pp := to_screen(_pin_pos(i))
		draw_line(pp, pp + Vector2(0, -16), Color(0.15, 0.1, 0.1), 2.0)
		draw_circle(pp + Vector2(0, -18), 6.0, Color(0.95, 0.35, 0.4) if i != selected_pin else Color(1.0, 0.8, 0.3))
		draw_circle(pp, 2.5, Color(0.15, 0.1, 0.1))
		var memo := str(Game.map_pins[i].get("text", ""))
		if memo != "":
			_text(pp + Vector2(9, -14), memo, 15, Color(1.0, 0.9, 0.9))
	# camper and player
	if Game.has_camper and RegionDB.all().has(str(Game.camper.get("region", ""))):
		var cpos: Variant = Game.camper.get("pos", null)
		var cv: Vector3 = cpos if cpos is Vector3 else VisualLab.CAMPER_POS
		var c4 := to_screen(RegionDB.map_pos(str(Game.camper["region"]), Vector2(cv.x, cv.z)))
		draw_rect(Rect2(c4 - Vector2(8, 6), Vector2(16, 12)), Color(0.25, 0.5, 1.0))
		draw_rect(Rect2(c4 - Vector2(8, 6), Vector2(16, 12)), Color(0.9, 0.95, 1.0), false, 1.5)
	var pm := player_map_pos()
	if pm.x != INF:
		var c5 := to_screen(pm)
		var w: Node = Game.boot.world
		var yaw: float = w.player.facing_yaw() if w.player.has_method("facing_yaw") else 0.0
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		draw_colored_polygon(PackedVector2Array([c5 + fwd * 12.0, c5 - fwd * 7.0 + side * 7.0, c5 - fwd * 3.0, c5 - fwd * 7.0 - side * 7.0]), Color(1.0, 0.35, 0.3))
		draw_arc(c5, 13.0, 0, TAU, 20, Color(1, 1, 1, 0.9), 2.0)
	# the region in view, like a map title
	if page != "":
		var title := MapDB.title(page) if MapDB.owned(page) else RegionDB.region_name(page)
		MapDB.text_on(self, f, v.position + Vector2(18, 40), title, 30, Color(1.0, 0.95, 0.82))


## A fixed dungeon's map: its floor plan filling the view (under clouds without the map).
func _draw_dungeon_sheet() -> void:
	var v := view_rect()
	draw_rect(v, Color(0.2, 0.18, 0.16))
	var r := MapDB.region_rect(page)
	var k := minf((v.size.x - 80.0) / r.size.x, (v.size.y - 80.0) / r.size.y)
	var origin := v.get_center() - r.get_center() * k
	var sr := Rect2(origin + r.position * k, r.size * k)
	if not MapDB.owned(page):
		_draw_clouds(sr, page, false)
		return
	draw_texture_rect(MapDB.terrain_texture(page), sr, false)
	var f: Font = font if font else get_theme_default_font()
	for m: Dictionary in MapDB.info(page).get("marks", []):
		MapDB.draw_mark(self, m, origin + TerrainField._v2(m.get("pos", null), Vector2.ZERO) * k, f)
	var w: Node = Game.boot.world if Game.boot else null
	if page == Game.region and w is VisualLab and w.player:
		var pp: Vector3 = w.player.global_position
		draw_circle(origin + Vector2(pp.x, pp.z) * k, 8.0, Color(1.0, 0.35, 0.3))
	MapDB.text_on(self, f, v.position + Vector2(18, 40), MapDB.title(page), 30, Color(1.0, 0.95, 0.82))


## The world map: names on visited regions, clouds over the others and over the open sea.
func _draw_world_layer() -> void:
	var f: Font = font if font else get_theme_default_font()
	var wr: Rect2 = MapDB.world_picture()["rect"]
	# decorative clouds drifting over the sea corners
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 7:
		var cpos := wr.position + Vector2(rng.randf_range(0.0, wr.size.x), rng.randf_range(0.0, wr.size.y))
		var over_land := false
		for rid: String in world_regions():
			if RegionDB.map_rect(rid).grow(40).has_point(cpos):
				over_land = true
		if not over_land:
			var cs := Vector2(rng.randf_range(50, 90), rng.randf_range(22, 34))
			_draw_clouds(Rect2(to_screen(cpos - cs * 0.5), cs * _zoom), "sea%d" % i, true)
	for rid: String in world_regions():
		var r := RegionDB.map_rect(rid)
		var sr := Rect2(to_screen(r.position), r.size * _zoom)
		if not visited(rid):
			_draw_clouds(sr, rid, false)  # never been there: hidden under grey clouds
			continue
		var name := RegionDB.region_name(rid)
		var w := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var plate := Rect2(sr.get_center() - Vector2(w * 0.5 + 12, 16), Vector2(w + 24, 30))
		draw_rect(plate, Color(0.9, 0.85, 0.7, 0.92))
		draw_rect(plate, MapDB.INK, false, 1.5)
		draw_string(f, plate.position + Vector2(12, 22), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			Color(0.55, 0.18, 0.1) if rid == Game.region else MapDB.INK)


static func visited(rid: String) -> bool:
	return rid == Game.region or Game.discovered.has("region:" + rid)


## Cloud cover: grey over places not visited / without a map, parchment over the open sea.
func _draw_clouds(sr: Rect2, key: String, light: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var base := Color(0.88, 0.84, 0.72) if light else Color(0.62, 0.63, 0.66)
	var shadow := Color(0.55, 0.5, 0.4, 0.4) if light else Color(0.45, 0.46, 0.5, 0.5)
	if not light:
		draw_rect(sr.grow(-minf(sr.size.x, sr.size.y) * 0.04), base)
	var step := clampf(minf(sr.size.x, sr.size.y) * 0.16, 12.0, 46.0)
	var pts: Array[Vector2] = []
	var x := sr.position.x
	while x <= sr.end.x:
		pts.append(Vector2(x, sr.position.y + rng.randf_range(-4, 8)))
		pts.append(Vector2(x, sr.end.y + rng.randf_range(-8, 4)))
		x += step * 0.8
	var y := sr.position.y
	while y <= sr.end.y:
		pts.append(Vector2(sr.position.x + rng.randf_range(-4, 8), y))
		pts.append(Vector2(sr.end.x + rng.randf_range(-8, 4), y))
		y += step * 0.8
	for i in int(sr.size.x * sr.size.y / (step * step * 1.5)):
		pts.append(Vector2(rng.randf_range(sr.position.x, sr.end.x), rng.randf_range(sr.position.y, sr.end.y)))
	for p in pts:
		draw_circle(p + Vector2(2, 3), step * 0.62, shadow)
	for p in pts:
		var shade := rng.randf_range(-0.05, 0.06)
		draw_circle(p, step * rng.randf_range(0.5, 0.7), Color(base.r + shade, base.g + shade, base.b + shade))
	if not light:
		for i in 6:
			draw_circle(Vector2(rng.randf_range(sr.position.x, sr.end.x), rng.randf_range(sr.position.y, sr.end.y)), step * 0.35, Color(0.78, 0.79, 0.82, 0.8))
		if sr.size.x > 60.0:
			_text_centered(sr.get_center() + Vector2(0, 8), "???", 22, Color(0.4, 0.41, 0.45))


func _text(pos: Vector2, s: String, fsize: int, col: Color) -> void:
	MapDB.text_on(self, font if font else get_theme_default_font(), pos, s, fsize, col)


func _text_centered(pos: Vector2, s: String, fsize: int, col: Color, outline := false) -> void:
	var f: Font = font if font else get_theme_default_font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	if outline:
		MapDB.text_on(self, f, pos - Vector2(w * 0.5, 0), s, fsize, col)
	else:
		draw_string(f, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
