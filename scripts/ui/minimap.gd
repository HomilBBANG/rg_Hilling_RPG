class_name Minimap
extends Control
## Minimap in the HUD's top-right corner: the terrain around the hero (the same pictures as the
## world map, M), north up, with the hero as an arrow in the middle. Also the parked camper (blue),
## NPCs (yellow), towns, found checkpoints / story spots / cave entrances, region exits (white) and
## nearby monsters. The cat is not shown.
## Without the region's map (MapDB) there is no terrain — only the hero, NPCs, monsters and the camper.
## Mouse wheel = zoom, click = open the world map. Fixed dungeons show their floor plan; the
## random dungeon and the camper interior have no minimap.

const SIZE := 260.0
const ZOOM_MIN := 1.0
const ZOOM_MAX := 6.0

var font: Font
var hud: Control
var zoom := 2.6  ## screen pixels per map metre (default view ≈ 100 m across)
var _active := false
var _region_label: Label


func _ready() -> void:
	size = Vector2(SIZE, SIZE)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_region_label = Label.new()
	_region_label.position = Vector2(0, SIZE + 4)
	_region_label.size = Vector2(SIZE, 24)
	_region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region_label.add_theme_font_size_override("font_size", 17)
	_region_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	_region_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_region_label.add_theme_constant_override("outline_size", 5)
	_region_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_region_label)
	if hud and hud.has_method("tip"):
		hud.tip(self, "미니맵", "북쪽이 위. ➤ 나 · 파란 ■ 캠핑카 · 노란 • NPC · ● 도시 · ▲ 체크포인트 · ◆ 이야기 장소 · ◉ 동굴 · 흰 • 지역 출구 · 붉은 • 몬스터\n휠: 확대/축소 · 클릭: 큰 지도(M)")


func _world() -> Node:
	return Game.boot.world if Game.boot else null


## Where the hero (or the camper being driven) is, in world-map metres; INF when there is no map.
func player_map_pos() -> Vector2:
	var w := _world()
	if not (w is VisualLab) or w.player == null or RegionDB.is_random_dungeon(Game.region):
		return Vector2.INF
	var pp: Vector3 = w.vehicle.global_position if w.vehicle.driving else w.player.global_position
	return RegionDB.map_pos(Game.region, Vector2(pp.x, pp.z))


func _process(_delta: float) -> void:
	var on := player_map_pos().x != INF
	if on != _active:
		_active = on
		modulate.a = 1.0 if on else 0.0
		mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if _active:
		var reg := RegionDB.info(Game.region)
		_region_label.text = "%s  %s" % [reg.get("name", Game.region), "★".repeat(int(reg.get("danger", 1)))]
		queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if not _active or not ev is InputEventMouseButton or not ev.pressed:
		return
	match ev.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			zoom = minf(ZOOM_MAX, zoom * 1.25)
		MOUSE_BUTTON_WHEEL_DOWN:
			zoom = maxf(ZOOM_MIN, zoom / 1.25)
		MOUSE_BUTTON_LEFT:
			if hud and hud.has_method("toggle_map"):
				hud.toggle_map()
	accept_event()


func _to_screen(center: Vector2, p: Vector2) -> Vector2:
	return size * 0.5 + (p - center) * zoom


func _draw() -> void:
	if not _active:
		return
	var center := player_map_pos()
	var all := RegionDB.all()
	var view := Rect2(center - size * 0.5 / zoom, size / zoom)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.12, 0.92))
	# terrain of every mapped region in view (neighbours too, so crossing a border is seamless)
	for rid: String in all:
		var reg: Dictionary = all[rid]
		if not MapDB.owned(rid):
			continue  # no map of that region: no terrain (user design — maps are collected)
		if RegionDB.is_random_dungeon(rid):
			continue
		var r := RegionDB.map_rect(rid)
		if not r.intersects(view):
			continue
		var sr := Rect2(_to_screen(center, r.position), r.size * zoom)
		if reg.get("kind", "") == "dungeon":
			draw_rect(sr, Color(0.14, 0.13, 0.16))
			var cl := float(reg.get("cell", 2.0))
			for fc: Array in reg.get("_floor", []):
				var wpos := RegionDB.grid_to_world(int(fc[0]), int(fc[1]), int(reg["_cols"]), int(reg["_rows"]), cl)
				draw_rect(Rect2(_to_screen(center, RegionDB.map_pos(rid, wpos - Vector2(cl, cl) * 0.5)), Vector2(cl, cl) * zoom), Color(0.55, 0.52, 0.5))
		else:
			draw_texture_rect(MapDB.terrain_texture(rid), sr, false)
		# marks in this region
		for cp: Dictionary in reg.get("checkpoints", []):
			if Game.discovered.has("%s:%s" % [rid, cp["id"]]):
				var c := _to_screen(center, RegionDB.map_pos(rid, cp["pos"]))
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(5, 4), c + Vector2(-5, 4)]), Color(0.45, 0.9, 0.85))
		for tr: Dictionary in reg.get("story_triggers", []):
			if str(tr.get("map_name", "")) != "" and Game.discovered.has("trig:%s:%s" % [rid, tr["id"]]):
				var c2 := _to_screen(center, RegionDB.map_pos(rid, tr["pos"]))
				draw_colored_polygon(PackedVector2Array([c2 + Vector2(0, -6), c2 + Vector2(6, 0), c2 + Vector2(0, 6), c2 + Vector2(-6, 0)]), Color(0.95, 0.35, 0.2))
		for ex: Dictionary in reg.get("exits", []):
			if ex.get("hidden", false) and not Game.discovered.has("%s:%s" % [rid, ex["id"]]):
				continue
			var c3 := _to_screen(center, RegionDB.map_pos(rid, ex["pos"]))
			var st := str(ex.get("style", ""))
			if st == "cave" or st == "rift":
				draw_circle(c3, 5.0, Color(0.35, 0.25, 0.45) if st == "rift" else Color(0.3, 0.27, 0.24))
				draw_arc(c3, 5.0, 0, TAU, 12, Color(0.9, 0.85, 0.75), 1.5)
			elif rid == Game.region:
				draw_circle(c3, 4.0, Color(0.95, 0.95, 0.95))  # white: yellow is for NPCs
				draw_arc(c3, 4.0, 0, TAU, 10, Color(0, 0, 0, 0.7), 1.0)
	if not MapDB.owned(Game.region):
		var f0: Font = font if font else get_theme_default_font()
		draw_string(f0, Vector2(10, size.y - 12), "지도 없음", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.78, 0.82))
	# towns (only on owned maps)
	var cities := RegionDB.cities()
	for id: String in cities:
		var ct: Dictionary = cities[id]
		if not MapDB.owned(str(ct["region"])):
			continue
		var c4 := _to_screen(center, ct["map"])
		if Rect2(Vector2(-20, -20), size + Vector2(40, 40)).has_point(c4):
			draw_circle(c4, 7.0, Color(0, 0, 0, 0.6))
			draw_circle(c4, 5.0, Color(0.95, 0.82, 0.45) if Game.discovered.has("city:" + id) else Color(0.7, 0.66, 0.58))
	# monsters nearby (current region only)
	var w := _world()
	if w is VisualLab and "monsters" in w:
		for m in w.monsters:
			if is_instance_valid(m) and m is SlimeMonster and m.state != SlimeMonster.State.DEAD:
				var c5 := _to_screen(center, RegionDB.map_pos(Game.region, Vector2(m.global_position.x, m.global_position.z)))
				draw_circle(c5, 3.5 if not m.provoked else 4.5, Color(0.95, 0.3, 0.25) if m.provoked else Color(0.9, 0.55, 0.45))
	# NPCs (yellow); the ones at home are hidden and not drawn. The cat is never shown.
	if w is VisualLab and "npcs" in w:
		for n in w.npcs:
			if is_instance_valid(n) and n.visible:
				var c7 := _to_screen(center, RegionDB.map_pos(Game.region, Vector2(n.global_position.x, n.global_position.z)))
				draw_circle(c7, 5.0, Color(0.15, 0.12, 0.05, 0.85))
				draw_circle(c7, 3.8, Color(1.0, 0.86, 0.15))
	# the parked camper (blue)
	if Game.has_camper and not (w is VisualLab and w.vehicle.driving):
		var cpos: Variant = Game.camper.get("pos", null)
		var cv: Vector3 = cpos if cpos is Vector3 else VisualLab.CAMPER_POS
		var creg := str(Game.camper.get("region", ""))
		if all.has(creg):
			var c6 := _to_screen(center, RegionDB.map_pos(creg, Vector2(cv.x, cv.z)))
			draw_rect(Rect2(c6 - Vector2(7, 5), Vector2(14, 10)), Color(0.25, 0.5, 1.0))
			draw_rect(Rect2(c6 - Vector2(7, 5), Vector2(14, 10)), Color(0.9, 0.95, 1.0), false, 1.5)
	# me: arrow in the middle, pointing where the hero faces
	var mid := size * 0.5
	var yaw: float = w.player.facing_yaw() if w.player.has_method("facing_yaw") else 0.0
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	var arrow := PackedVector2Array([mid + fwd * 11.0, mid - fwd * 6.0 + side * 7.0, mid - fwd * 2.5, mid - fwd * 6.0 - side * 7.0])
	draw_colored_polygon(arrow, Color(1.0, 0.35, 0.3))
	arrow.append(arrow[0])
	draw_polyline(arrow, Color(1, 1, 1, 0.95), 1.5)
	# frame + north mark
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color(0.46, 0.46, 0.48), false, 2.0)
	var f: Font = font if font else get_theme_default_font()
	draw_string_outline(f, Vector2(size.x * 0.5 - 6, 20), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0, 0, 0, 0.85))
	draw_string(f, Vector2(size.x * 0.5 - 6, 20), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1.0, 0.92, 0.7))
