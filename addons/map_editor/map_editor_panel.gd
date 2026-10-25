@tool
class_name MapEditorPanel
extends Control
## The dialogue editor's 지도 tab: region maps (data/maps/<region>.json, MapDB). The terrain is
## drawn automatically from the region data; the designer places marks on it (지명 / 아이콘 / 메모),
## sets the map's title, page order and description, and how the player gets it: sold in a shop,
## given by an NPC (dialogue action give_map), or lying in the field at a spot picked on the map.
## Region exits, checkpoints and towns are drawn faintly for reference.

signal saved(path: String)

const UNDO_LIMIT := 200
const PICK := 14.0

var doc := {}         ## the map file being edited
var region := ""      ## its region
var view_region := "" ## region drawn on the canvas (the map's own, or another one to place a drop)
var dirty := false
var selected := ""    ## selected mark id
var selected_drop := -1  ## selected source index (a drop)
var place := ""       ## "" | "label" | "icon" | "note" | "drop:<source index>" — next canvas click places it
var issues: Array = []

var _undo: Array[String] = []
var _redo: Array[String] = []
var _snap := ""
var _zoom := MapZoom.new()
var _scale := 1.0
var _origin := Vector2.ZERO
var _drag := false

var _list: ItemList
var _canvas: Control
var _inspector: VBoxContainer
var _status: Label
var _issue_list: ItemList
var _view_opt: OptionButton


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()
	refresh_list()
	var all := _regions()
	if not all.is_empty():
		open_map("meadow" if all.has("meadow") else str(all[0]))


# ---------------------------------------------------------------- UI

func _btn(parent: Control, text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))
	parent.add_child(l)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bar := HFlowContainer.new()
	root.add_child(bar)
	_btn(bar, "저장", func() -> void: save(), "Ctrl+S — data/maps/<지역>.json")
	_btn(bar, "파일에서 다시 읽기", revert, "저장하지 않은 변경 버리기")
	_btn(bar, "↶", undo, "실행 취소 (Ctrl+Z)")
	_btn(bar, "↷", redo, "다시 실행 (Ctrl+Y / Ctrl+Shift+Z)")
	bar.add_child(VSeparator.new())
	var l := Label.new()
	l.text = "표시 추가 (누른 뒤 지도를 클릭):"
	bar.add_child(l)
	for t: String in MapDB.MARK_TYPES:
		var tt := t
		_btn(bar, MapDB.TYPE_NAMES[t], func() -> void: start_place(tt), "지도 위 클릭한 자리에 %s 추가" % MapDB.TYPE_NAMES[t])
	_btn(bar, "선택 삭제", func() -> void: delete_selected(), "Delete 키로도 지움")
	bar.add_child(VSeparator.new())
	var vl := Label.new()
	vl.text = "보이는 지역:"
	bar.add_child(vl)
	_view_opt = OptionButton.new()
	_view_opt.tooltip_text = "다른 지역에 떨어뜨릴 지도 위치를 찍을 때 바꿈 (표시는 지도 자기 지역에서만)"
	_view_opt.item_selected.connect(func(i: int) -> void: set_view(_view_opt.get_item_metadata(i)))
	bar.add_child(_view_opt)
	_btn(bar, "검증", func() -> void: validate(true))
	EditorWidgets.help_button(bar, "map")
	EditorWidgets.quick_guide(root, "① 왼쪽에서 지역 고르기 → ② 위 버튼(지명·아이콘·메모)을 누르고 그림 클릭 → ③ 클릭해 고르고 끌어서 옮기기 → ④ 오른쪽에서 글자 고치기 → ⑤ 저장")
	_status = Label.new()
	_status.clip_text = true
	root.add_child(_status)
	var hs := HSplitContainer.new()
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(hs)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 230
	hs.add_child(left)
	_heading(left, "지역 지도 (data/maps)")
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: open_map(str(_list.get_item_metadata(i))))
	left.add_child(_list)
	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.add_child(right_split)
	var vs := VSplitContainer.new()
	vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(vs)
	var cbox := VBoxContainer.new()
	cbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vs.add_child(cbox)
	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(500, 400)
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.focus_mode = Control.FOCUS_CLICK
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	_canvas.resized.connect(_fit)
	_zoom.toolbar(cbox, _canvas)
	_zoom.changed.connect(func() -> void:
		_scale = _zoom.scale
		_origin = _zoom.origin)
	cbox.add_child(_canvas)
	_issue_list = ItemList.new()
	_issue_list.custom_minimum_size.y = 120
	vs.add_child(_issue_list)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 360
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_split.add_child(scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inspector)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is TextEdit or focus is LineEdit or focus is SpinBox
	if k.keycode == KEY_DELETE and not typing and focus == _canvas:
		delete_selected()
		get_viewport().set_input_as_handled()
		return
	if not k.is_command_or_control_pressed():
		return
	if k.keycode == KEY_S:
		save()
		get_viewport().set_input_as_handled()
	elif not typing and k.keycode == KEY_Z and not k.shift_pressed:
		undo()
		get_viewport().set_input_as_handled()
	elif not typing and (k.keycode == KEY_Y or (k.keycode == KEY_Z and k.shift_pressed)):
		redo()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- files

func _regions() -> Array:
	var out := []
	for rid: String in RegionDB.all():
		if MapDB.mappable(rid):
			out.append(rid)
	out.sort_custom(func(a: String, b: String) -> bool:
		var oa := int(MapDB.info(a).get("order", 99))
		var ob := int(MapDB.info(b).get("order", 99))
		return oa < ob if oa != ob else a < b)
	return out


func refresh_list() -> void:
	MapDB.reload()
	_list.clear()
	for rid: String in _regions():
		var has := not MapDB.info(rid).is_empty()
		var i := _list.add_item("%s%s\n  %s" % ["● " if rid == region and dirty else "", RegionDB.region_name(rid),
			MapDB.title(rid) if has else "(지도 없음 — 고르면 새로 만듦)"])
		_list.set_item_metadata(i, rid)
		if rid == region:
			_list.select(i)
	_view_opt.clear()
	for rid: String in _regions():
		_view_opt.add_item(RegionDB.region_name(rid))
		_view_opt.set_item_metadata(_view_opt.item_count - 1, rid)
		if rid == view_region:
			_view_opt.select(_view_opt.item_count - 1)


func open_map(rid: String) -> bool:
	if dirty and rid != region:
		_set_status("저장하지 않은 변경이 있습니다 — 저장하거나 '파일에서 다시 읽기' 후 다른 지도를 여세요")
		refresh_list()
		return false
	MapDB.reload()
	var d: Dictionary = MapDB.info(rid).duplicate(true)
	if d.is_empty():
		d = {"version": 1, "map_id": MapDB.map_id_for(rid), "region": rid, "title": RegionDB.region_name(rid) + " 지도",
			"order": 99, "desc": "", "marks": [], "sources": []}
	doc = d
	_normalize()
	region = rid
	view_region = rid
	dirty = MapDB.info(rid).is_empty()  # a new map is unsaved
	selected = ""
	selected_drop = -1
	place = ""
	_undo.clear()
	_redo.clear()
	_snap = JSON.stringify(doc)
	refresh_list()
	_fit()
	_show_inspector()
	validate(false)
	_update_status()
	return true


func _normalize() -> void:
	doc["version"] = 1
	for key in ["marks", "sources"]:
		if not doc.get(key) is Array:
			doc[key] = []


func save() -> bool:
	if region == "":
		return false
	doc["region"] = region
	doc["map_id"] = MapDB.map_id_for(region)
	validate(false)
	var err := MapDB.save(doc)
	if err != OK:
		_set_status("저장 실패: %s" % error_string(err))
		return false
	dirty = false
	refresh_list()
	var bad := issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "error").size()
	_set_status("저장함: %s%s" % [MapDB.path_for(region), "  — ⚠ 오류 %d개" % bad if bad > 0 else ""])
	saved.emit(MapDB.path_for(region))
	return true


func revert() -> void:
	dirty = false
	var rid := region
	region = ""
	open_map(rid)


# ---------------------------------------------------------------- editing

func _commit() -> void:
	var now := JSON.stringify(doc)
	if now == _snap:
		return
	_undo.append(_snap)
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()
	_snap = now
	if not dirty:
		dirty = true
		refresh_list()
	validate(false)
	_update_status()
	_canvas.queue_redraw()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_snap)
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_snap)
	_restore(_redo.pop_back())


func _restore(snap: String) -> void:
	_snap = snap
	doc = JSON.parse_string(snap)
	_normalize()
	if mark(selected).is_empty():
		selected = ""
	if selected_drop >= doc["sources"].size():
		selected_drop = -1
	dirty = true
	_show_inspector()
	validate(false)
	_update_status()
	_canvas.queue_redraw()


func mark(id: String) -> Dictionary:
	for m: Dictionary in doc.get("marks", []):
		if m.get("id", "") == id:
			return m
	return {}


func _new_mark_id() -> String:
	var i := 1
	while not mark("mark_%d" % i).is_empty():
		i += 1
	return "mark_%d" % i


## Adds a mark at a region position (x, z). Returns its id.
func add_mark(type: String, pos: Vector2) -> String:
	var m := {"id": _new_mark_id(), "type": type, "text": {"label": "새 지명", "icon": "새 장소", "note": "메모"}.get(type, ""),
		"pos": [snappedf(pos.x, 0.5), snappedf(pos.y, 0.5)]}
	if type == "icon":
		m["icon"] = "star"
	doc["marks"].append(m)
	selected = m["id"]
	selected_drop = -1
	_commit()
	_show_inspector()
	return m["id"]


func set_mark_field(id: String, key: String, value: Variant) -> void:
	var m := mark(id)
	if m.is_empty():
		return
	m[key] = value
	_commit()


func move_mark(id: String, pos: Vector2, commit := true) -> void:
	var m := mark(id)
	if m.is_empty():
		return
	m["pos"] = [snappedf(pos.x, 0.5), snappedf(pos.y, 0.5)]
	if commit:
		_commit()
		_show_inspector()
	else:
		_canvas.queue_redraw()


func delete_selected() -> void:
	if selected != "":
		doc["marks"].erase(mark(selected))
		selected = ""
		_commit()
		_show_inspector()
	elif selected_drop >= 0:
		remove_source(selected_drop)


func set_field(key: String, value: Variant) -> void:
	if doc.get(key) == value:
		return
	doc[key] = value
	_commit()


func add_source(kind: String) -> int:
	var s := {"kind": kind}
	match kind:
		"shop":
			s["shop"] = str(ShopDB.SHOPS.keys()[0])
			s["price"] = 20
		"npc":
			s["speaker"] = "king"
			s["note"] = ""
		"drop":
			s["region"] = view_region
			var c := MapDB.region_rect(view_region).get_center()
			s["pos"] = [snappedf(c.x, 0.5), snappedf(c.y, 0.5)]
	doc["sources"].append(s)
	_commit()
	_show_inspector()
	return doc["sources"].size() - 1


func set_source_field(i: int, key: String, value: Variant) -> void:
	if i < 0 or i >= doc["sources"].size():
		return
	doc["sources"][i][key] = value
	_commit()


func remove_source(i: int) -> void:
	if i < 0 or i >= doc["sources"].size():
		return
	doc["sources"].remove_at(i)
	if selected_drop == i:
		selected_drop = -1
	_commit()
	_show_inspector()


## Next click on the canvas places a mark of this type (or a drop spot: "drop:<index>").
func start_place(what: String) -> void:
	if what in MapDB.MARK_TYPES and view_region != region:
		set_view(region)
	place = what
	_set_status("지도를 클릭해 위치를 정하세요 (Esc 취소)" if what != "" else "")


func set_view(rid: String) -> void:
	view_region = rid
	refresh_list()
	_fit()


# ---------------------------------------------------------------- canvas

func _fit() -> void:
	if view_region == "" or _canvas == null or _canvas.size.x < 10.0:
		return
	var r := MapDB.region_rect(view_region)
	_zoom.pad = 24.0
	_zoom.fit(_canvas, r)
	_scale = _zoom.scale
	_origin = _zoom.origin
	_canvas.queue_redraw()


func to_canvas(p: Vector2) -> Vector2:
	return _origin + p * _scale


func to_region(c: Vector2) -> Vector2:
	return (c - _origin) / _scale


func _drops_on_view() -> Array:
	var out := []
	var srcs: Array = doc.get("sources", [])
	for i in srcs.size():
		if srcs[i].get("kind", "") == "drop" and str(srcs[i].get("region", "")) == view_region:
			out.append(i)
	return out


## A click on the canvas at local position c (also used by the selftest).
func canvas_click(c: Vector2) -> void:
	var p := to_region(c)
	if place in MapDB.MARK_TYPES:
		var t := place
		place = ""
		add_mark(t, p)
		_set_status("")
		return
	if place.begins_with("drop:"):
		var i := int(place.get_slice(":", 1))
		place = ""
		if i < doc["sources"].size():
			doc["sources"][i]["region"] = view_region
			doc["sources"][i]["pos"] = [snappedf(p.x, 0.5), snappedf(p.y, 0.5)]
			selected_drop = i
			selected = ""
			_commit()
			_show_inspector()
		_set_status("")
		return
	# select a mark or a drop under the mouse
	selected = ""
	selected_drop = -1
	if view_region == region:
		for m: Dictionary in doc["marks"]:
			if to_canvas(TerrainField._v2(m.get("pos", null), Vector2.ZERO)).distance_to(c) < PICK:
				selected = str(m["id"])
	if selected == "":
		for i: int in _drops_on_view():
			if to_canvas(TerrainField._v2(doc["sources"][i]["pos"], Vector2.ZERO)).distance_to(c) < PICK:
				selected_drop = i
	_show_inspector()
	_canvas.queue_redraw()


func _canvas_input(ev: InputEvent) -> void:
	if _zoom.handle(ev, _canvas):
		_canvas.accept_event()
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			canvas_click(ev.position)
			_drag = selected != "" or selected_drop >= 0
		else:
			if _drag:
				_commit()
				_show_inspector()
			_drag = false
		_canvas.accept_event()
	elif ev is InputEventMouseMotion and _drag:
		var p := to_region(ev.position)
		if selected != "":
			move_mark(selected, p, false)
		elif selected_drop >= 0:
			doc["sources"][selected_drop]["pos"] = [snappedf(p.x, 0.5), snappedf(p.y, 0.5)]
			_canvas.queue_redraw()
	elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE and place != "":
		start_place("")


func _draw_canvas() -> void:
	var f := get_theme_default_font()
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(0.12, 0.13, 0.15))
	if view_region == "":
		return
	var r := MapDB.region_rect(view_region)
	var area := Rect2(to_canvas(r.position), r.size * _scale)
	_canvas.draw_texture_rect(MapDB.terrain_texture(view_region), area, false)
	_canvas.draw_rect(area, Color(0.9, 0.8, 0.55), false, 2.0)
	var reg: Dictionary = RegionDB.all().get(view_region, {})
	# reference: exits, checkpoints, towns (faint)
	for ex: Dictionary in reg.get("exits", []):
		var c := to_canvas(TerrainField._v2(ex["pos"], Vector2.ZERO))
		_canvas.draw_circle(c, 4.0, Color(1, 1, 1, 0.5))
		_canvas.draw_string(f, c + Vector2(6, -4), "출구: %s" % RegionDB.region_name(str(ex.get("to_region", ""))), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))
	for cp: Dictionary in reg.get("checkpoints", []):
		var c2 := to_canvas(TerrainField._v2(cp["pos"], Vector2.ZERO))
		_canvas.draw_colored_polygon(PackedVector2Array([c2 + Vector2(0, -5), c2 + Vector2(4, 3), c2 + Vector2(-4, 3)]), Color(0.45, 0.9, 0.85, 0.55))
	for ct: Dictionary in reg.get("cities", []):
		var c3 := to_canvas(TerrainField._v2(ct["center"], Vector2.ZERO))
		_canvas.draw_arc(c3, 9.0, 0, TAU, 20, Color(0.95, 0.82, 0.45, 0.7), 2.0)
	# marks (only on the map's own region)
	if view_region == region:
		for m: Dictionary in doc.get("marks", []):
			MapDB.draw_mark(_canvas, m, to_canvas(TerrainField._v2(m.get("pos", null), Vector2.ZERO)), f, m.get("id", "") == selected)
	# field drops of this map lying in the region on view
	for i: int in _drops_on_view():
		var c4 := to_canvas(TerrainField._v2(doc["sources"][i]["pos"], Vector2.ZERO))
		_canvas.draw_rect(Rect2(c4 - Vector2(9, 4), Vector2(18, 8)), Color(0.93, 0.86, 0.66))
		_canvas.draw_rect(Rect2(c4 - Vector2(9, 4), Vector2(18, 8)), Color(0.55, 0.32, 0.18), false, 2.0)
		_canvas.draw_string(f, c4 + Vector2(12, 5), "지도 드롭", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.95, 0.8))
		if i == selected_drop:
			_canvas.draw_arc(c4, 14.0, 0, TAU, 24, Color(1.0, 0.3, 0.3), 2.5)
	if place != "":
		_canvas.draw_string(f, Vector2(10, 22), "클릭해서 놓기: %s" % (MapDB.TYPE_NAMES.get(place, "지도 드롭 위치")), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.5))
	_canvas.draw_string(f, Vector2(10, _canvas.size.y - 10), "%s — %d × %d m" % [RegionDB.region_name(view_region), int(r.size.x), int(r.size.y)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.82, 0.86))


# ---------------------------------------------------------------- inspector

func _label(parent: Control, text: String, dim := false) -> Label:
	var l := Label.new()
	l.text = text
	if parent is HBoxContainer:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # in a row: no wrapping (it would collapse)
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if dim:
		l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(l)
	return l


func _line(parent: Control, value: String, cb: Callable) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	e.text_submitted.connect(func(s: String) -> void: cb.call(s))
	e.focus_exited.connect(func() -> void: cb.call(e.text))
	parent.add_child(e)
	return e


func _spin(parent: Control, value: float, lo: float, hi: float, step: float, cb: Callable) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = value
	sb.value_changed.connect(func(v: float) -> void: cb.call(v))
	parent.add_child(sb)
	return sb


func _show_inspector() -> void:
	for c in _inspector.get_children():
		_inspector.remove_child(c)
		c.queue_free()
	if doc.is_empty():
		return
	_heading(_inspector, "지도: %s" % RegionDB.region_name(region))
	_label(_inspector, "이름 (지도 화면·상점에 보임)")
	_line(_inspector, str(doc.get("title", "")), func(s: String) -> void: set_field("title", s))
	var oh := HBoxContainer.new()
	_inspector.add_child(oh)
	_label(oh, "지도 화면 순서")
	_spin(oh, float(doc.get("order", 99)), 1, 99, 1, func(v: float) -> void: set_field("order", int(v)))
	_label(_inspector, "설명")
	_line(_inspector, str(doc.get("desc", "")), func(s: String) -> void: set_field("desc", s))
	_inspector.add_child(HSeparator.new())
	# selected mark
	var m := mark(selected)
	if not m.is_empty():
		var id := selected
		_heading(_inspector, "선택한 표시: %s" % id)
		var topt := OptionButton.new()
		for t: String in MapDB.MARK_TYPES:
			topt.add_item(MapDB.TYPE_NAMES[t])
			if t == m.get("type", ""):
				topt.select(topt.item_count - 1)
		topt.item_selected.connect(func(i: int) -> void:
			set_mark_field(id, "type", MapDB.MARK_TYPES[i])
			if MapDB.MARK_TYPES[i] == "icon" and not mark(id).has("icon"):
				set_mark_field(id, "icon", "star")
			_show_inspector())
		_inspector.add_child(topt)
		if m.get("type", "") == "icon":
			var iopt := OptionButton.new()
			var keys := MapDB.ICONS.keys()
			for k: String in keys:
				iopt.add_item(str(MapDB.ICONS[k]))
				if k == m.get("icon", ""):
					iopt.select(iopt.item_count - 1)
			iopt.item_selected.connect(func(i: int) -> void: set_mark_field(id, "icon", str(keys[i])))
			_inspector.add_child(iopt)
		_label(_inspector, "글자")
		_line(_inspector, str(m.get("text", "")), func(s: String) -> void: set_mark_field(id, "text", s))
		var ph := HBoxContainer.new()
		_inspector.add_child(ph)
		var p: Vector2 = TerrainField._v2(m.get("pos", null), Vector2.ZERO)
		_label(ph, "x")
		_spin(ph, p.x, -500, 500, 0.5, func(v: float) -> void: move_mark(id, Vector2(v, TerrainField._v2(mark(id).get("pos", null), Vector2.ZERO).y)))
		_label(ph, "z")
		_spin(ph, p.y, -500, 500, 0.5, func(v: float) -> void: move_mark(id, Vector2(TerrainField._v2(mark(id).get("pos", null), Vector2.ZERO).x, v)))
		_btn(_inspector, "이 표시 지우기", delete_selected)
		_inspector.add_child(HSeparator.new())
	else:
		_label(_inspector, "표시를 클릭해 고르고 끌어 옮기세요. 위 버튼으로 새 표시를 놓습니다.", true)
		_inspector.add_child(HSeparator.new())
	# sources
	_heading(_inspector, "얻는 방법")
	var srcs: Array = doc.get("sources", [])
	for i in srcs.size():
		var s: Dictionary = srcs[i]
		var idx := i
		var box := VBoxContainer.new()
		_inspector.add_child(box)
		var head := HBoxContainer.new()
		box.add_child(head)
		var hl := _label(head, "%d. %s" % [i + 1, MapDB.SOURCE_KINDS.get(s.get("kind", ""), s.get("kind", ""))])
		hl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5) if i == selected_drop else Color(0.9, 0.9, 0.9))
		_btn(head, "×", func() -> void: remove_source(idx), "이 방법 지우기")
		match str(s.get("kind", "")):
			"shop":
				var sh := HBoxContainer.new()
				box.add_child(sh)
				var so := OptionButton.new()
				var shops := ShopDB.SHOPS.keys()
				for k: String in shops:
					so.add_item(str(ShopDB.SHOPS[k]["name"]))
					if k == s.get("shop", ""):
						so.select(so.item_count - 1)
				so.item_selected.connect(func(j: int) -> void: set_source_field(idx, "shop", str(shops[j])))
				sh.add_child(so)
				_label(sh, "값")
				_spin(sh, float(s.get("price", 0)), 0, 9999, 1, func(v: float) -> void: set_source_field(idx, "price", int(v)))
			"npc":
				var nh := HBoxContainer.new()
				box.add_child(nh)
				var no := OptionButton.new()
				var sp := DialogueData.speakers().keys().filter(func(k: String) -> bool: return k not in ["narrator", "player"])
				for k: String in sp:
					no.add_item(DialogueData.speaker_name(k))
					if k == s.get("speaker", ""):
						no.select(no.item_count - 1)
				no.item_selected.connect(func(j: int) -> void: set_source_field(idx, "speaker", str(sp[j])))
				nh.add_child(no)
				_line(box, str(s.get("note", "")), func(t: String) -> void: set_source_field(idx, "note", t)).placeholder_text = "언제 주는지 (메모)"
				_label(box, "실제로 주려면: 대화 탭에서 그 NPC 대화에 액션 '지도 주기' (지역 ID '%s')를 넣으세요." % region, true)
			"drop":
				var dh := HBoxContainer.new()
				box.add_child(dh)
				var ro := OptionButton.new()
				var regs := _regions()
				for k: String in regs:
					ro.add_item(RegionDB.region_name(k))
					if k == s.get("region", ""):
						ro.select(ro.item_count - 1)
				ro.item_selected.connect(func(j: int) -> void:
					set_source_field(idx, "region", str(regs[j]))
					set_view(str(regs[j])))
				dh.add_child(ro)
				var dp: Vector2 = TerrainField._v2(s.get("pos", null), Vector2.ZERO)
				_label(dh, "(%.1f, %.1f)" % [dp.x, dp.y], true)
				_btn(box, "지도에서 위치 찍기", func() -> void:
					set_view(str(doc["sources"][idx].get("region", region)))
					start_place("drop:%d" % idx), "보이는 지역을 그 지역으로 바꾸고, 클릭한 자리에 지도가 떨어져 있게 함")
	var add := HFlowContainer.new()
	_inspector.add_child(add)
	for k: String in MapDB.SOURCE_KINDS:
		var kk := k
		_btn(add, "+ " + {"shop": "상점", "npc": "NPC", "drop": "필드 드롭"}[k], func() -> void: add_source(kk))


func validate(show := false) -> Array:
	issues = MapDB.validate(doc) if not doc.is_empty() else []
	_issue_list.clear()
	for it: Dictionary in issues:
		_issue_list.add_item("%s %s" % ["⛔" if it["severity"] == "error" else "⚠", it["message"]])
	if issues.is_empty():
		_issue_list.add_item("✔ 문제 없음")
	if show:
		_set_status("검증: 오류 %d, 경고 %d" % [issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "error").size(),
			issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "warning").size()])
	return issues


func _set_status(text: String) -> void:
	_status.text = text


func _update_status() -> void:
	if doc.is_empty():
		_set_status("지역을 고르세요")
		return
	_set_status("%s%s — 표시 %d개 · 얻는 방법 %d가지 · %s" % ["● " if dirty else "", MapDB.title(region) if not dirty else str(doc.get("title", "")),
		doc["marks"].size(), doc["sources"].size(), "저장하지 않은 변경 있음" if dirty else "저장됨"])
