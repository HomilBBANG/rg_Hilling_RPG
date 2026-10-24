@tool
class_name RegionEditorPanel
extends Control
## 지역 배치 tab of the Map editor: a region file (data/regions/<id>.json, RegionDB) laid out on its
## own terrain picture. The designer drags things on the picture and edits their fields on the
## right: the new-character start (default_spawn), terrain shapes (forests, ponds, clearings,
## mounds), roads (paths, point by point), towns, exits / arrival points, checkpoints, story spots,
## monsters, NPCs, gathering spots and fishing spots. Fixed dungeons: their text grid. Save writes
## the same JSON the game loads; "게임에서 실행" starts the game in that region at the start spot.

signal saved(path: String)
signal play_requested(region_id: String)

const UNDO_LIMIT := 200
const PICK := 12.0

## Lists of placed things: key -> label, draw colour, template for "+ 추가".
const LISTS := {
	"monsters": {"label": "몬스터", "color": Color(0.95, 0.32, 0.3), "new": {"id": "", "kind": "meadow_slime", "pos": [0, 0]}},
	"npcs": {"label": "NPC", "color": Color(1.0, 0.72, 0.3), "new": {"look": "rosa", "speaker": "rosa", "pos": [0, 0], "yaw": 0.0, "talk_distance": 1.6}},
	"checkpoints": {"label": "체크포인트", "color": Color(0.45, 0.9, 0.85), "new": {"id": "", "name": "새 쉼터", "pos": [0, 0], "radius": 5.0, "marker": true}},
	"story_triggers": {"label": "이야기 장소", "color": Color(1.0, 0.9, 0.4), "new": {"id": "", "pos": [0, 0], "radius": 6.0, "flag": "", "toast": ""}},
	"exits": {"label": "출구", "color": Color(1, 1, 1), "new": {"id": "", "name": "새 길", "pos": [0, 0], "radius": 2.3, "to_region": "meadow", "to_entry": "east_road"}},
	"gather": {"label": "채집", "color": Color(0.5, 0.85, 0.4), "new": {"id": "", "kind": "herb", "pos": [0, 0]}},
	"fishing_spots": {"label": "낚시터", "color": Color(0.4, 0.6, 1.0), "new": {"id": "", "pos": [0, 0], "yaw": 0.0, "pier": [0, 0]}},
	"cities": {"label": "도시", "color": Color(0.95, 0.82, 0.45), "new": {"id": "", "name": "새 마을", "kind": "village", "center": [0, 0], "size": [34, 30], "gate": "south", "houses": 8, "seed": 1,
		"plaza": {"center": [0, 0], "radius": 5}, "arrival": {"pos": [0, 20], "yaw": 3.1416}, "parking": {"pos": [6, 20], "yaw": 1.571}}},
}
## Terrain shapes inside "terrain": key -> label, colour, template.
const SHAPES := {
	"forests": {"label": "숲", "color": Color(0.25, 0.5, 0.25), "new": {"center": [0, 0], "radius": 15}},
	"ponds": {"label": "연못", "color": Color(0.35, 0.55, 0.85), "new": {"center": [0, 0], "radius": 8}},
	"clearings": {"label": "평지", "color": Color(0.85, 0.8, 0.5), "new": {"center": [0, 0], "radius": 10}},
}
const GATHER_KINDS := ["herb", "berry", "mushroom", "ore", "wood"]

var doc := {}
var region_id := ""
var dirty := false
var issues: Array = []
var can_play_in_game := false
## Selection: {"list": name, "index": i} | {"list": "entries", "key": id} | {"list": "spawn"}
## | {"list": "shape", "kind": forests|ponds|clearings|mounds, "index": i}
## | {"list": "path", "index": i, "point": j}
var sel := {}
var place := ""  ## next canvas click places: a LISTS key, a SHAPES key, "mounds", "path", "point", "spawn", "entry:<id>"

var _undo: Array[String] = []
var _redo: Array[String] = []
var _snap := ""
var _scale := 1.0
var _origin := Vector2.ZERO
var _zoom := 1.0
var _pan := Vector2.ZERO
var _drag := false
var _panning := false
var _tex: ImageTexture
var _tex_dirty := true
var _tex_t := 0.0

var _list: ItemList
var _canvas: Control
var _inspector: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _issue_list: ItemList
var _play_btn: Button
var _new_dialog: ConfirmationDialog
var _new_id: LineEdit
var _new_name: LineEdit


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()
	refresh_list()
	if not RegionDB.all().is_empty():
		open_region(RegionDB.START if RegionDB.all().has(RegionDB.START) else str(RegionDB.all().keys()[0]))


# ---------------------------------------------------------------- UI helpers

func _btn(parent: Control, text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _heading(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))
	parent.add_child(l)
	return l


func _label(parent: Control, text: String, dim := false) -> Label:
	var l := Label.new()
	l.text = text
	if parent is HBoxContainer:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if dim:
		l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(l)
	return l


func _line(parent: Control, value: String, cb: Callable, placeholder := "") -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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


func _check(parent: Control, text: String, value: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.toggled.connect(func(v: bool) -> void: cb.call(v))
	parent.add_child(c)
	return c


## options = [[value, label], ...]; a value outside the list shows as "(알 수 없음)".
func _opt(parent: Control, options: Array, current: String, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	var found := false
	for i in options.size():
		o.add_item(str(options[i][1]))
		o.set_item_metadata(i, str(options[i][0]))
		if str(options[i][0]) == current:
			o.select(i)
			found = true
	if not found:
		o.add_item("(알 수 없음: %s)" % current)
		o.set_item_metadata(o.item_count - 1, current)
		o.select(o.item_count - 1)
	o.item_selected.connect(func(i: int) -> void: cb.call(str(o.get_item_metadata(i))))
	parent.add_child(o)
	return o


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bar := HFlowContainer.new()
	root.add_child(bar)
	_btn(bar, "새 지역 (복제)", _ask_new, "지금 연 지역을 복제해 새 지역 파일을 만든다 (data/regions)")
	_btn(bar, "저장", func() -> void: save(), "Ctrl+S — data/regions/<지역 ID>.json")
	_btn(bar, "파일에서 다시 읽기", revert, "저장하지 않은 변경 버리기")
	_btn(bar, "↶", undo, "실행 취소 (Ctrl+Z)")
	_btn(bar, "↷", redo, "다시 실행 (Ctrl+Y / Ctrl+Shift+Z)")
	bar.add_child(VSeparator.new())
	_btn(bar, "검증", func() -> void: validate(true))
	_play_btn = _btn(bar, "게임에서 실행", func() -> void: play_requested.emit(region_id), "게임을 띄워 이 지역의 시작 위치에서 시작 (먼저 저장)")
	_play_btn.visible = can_play_in_game
	var bar2 := HFlowContainer.new()
	root.add_child(bar2)
	var pl := Label.new()
	pl.text = "놓기 (누른 뒤 그림을 클릭):"
	bar2.add_child(pl)
	_btn(bar2, "시작 위치", func() -> void: start_place("spawn"), "새 캐릭터가 깨어나는 자리 (default_spawn)")
	for k: String in LISTS:
		var kk := k
		_btn(bar2, "+ " + LISTS[k]["label"], func() -> void: start_place(kk))
	for k: String in SHAPES:
		var kk2 := k
		_btn(bar2, "+ " + SHAPES[k]["label"], func() -> void: start_place(kk2))
	_btn(bar2, "+ 언덕", func() -> void: start_place("mounds"))
	_btn(bar2, "+ 길", func() -> void: start_place("path"), "새 길: 첫 점을 찍고, 이어서 '+ 길 점'으로 늘린다")
	_btn(bar2, "+ 길 점", func() -> void: start_place("point"), "선택한 길의 끝(또는 선택한 점 다음)에 점 추가")
	_btn(bar2, "선택 삭제", delete_selected, "Delete")
	_status = Label.new()
	_status.clip_text = true
	root.add_child(_status)
	var hs := HSplitContainer.new()
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(hs)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 210
	hs.add_child(left)
	_heading(left, "지역 (data/regions)")
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: open_region(str(_list.get_item_metadata(i))))
	left.add_child(_list)
	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.add_child(right_split)
	var vs := VSplitContainer.new()
	vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(vs)
	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(520, 420)
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.focus_mode = Control.FOCUS_CLICK
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	_canvas.resized.connect(_fit)
	vs.add_child(_canvas)
	_issue_list = ItemList.new()
	_issue_list.custom_minimum_size.y = 110
	vs.add_child(_issue_list)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size.x = 380
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_split.add_child(_scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_inspector)
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "새 지역 (지금 연 지역 복제)"
	var nv := VBoxContainer.new()
	_new_dialog.add_child(nv)
	_label(nv, "지역 ID (파일 이름, 영문 소문자·숫자·_)")
	_new_id = LineEdit.new()
	nv.add_child(_new_id)
	_label(nv, "이름")
	_new_name = LineEdit.new()
	nv.add_child(_new_name)
	_new_dialog.confirmed.connect(func() -> void:
		if not create_region(_new_id.text.strip_edges(), _new_name.text.strip_edges()):
			_new_dialog.call_deferred("popup_centered"))
	add_child(_new_dialog)
	set_process(true)


func _process(delta: float) -> void:
	if _tex_dirty and _canvas:
		_tex_t += delta
		if _tex_t > 0.35:
			_rebuild_texture()


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
	if k.keycode == KEY_ESCAPE and place != "":
		start_place("")
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

func refresh_list() -> void:
	RegionDB.reload()
	_list.clear()
	var ids := RegionDB.all().keys()
	ids.sort()
	for rid: String in ids:
		var r: Dictionary = RegionDB.all()[rid]
		var kind := str(r.get("kind", ""))
		var i := _list.add_item("%s%s\n  %s%s" % ["● " if rid == region_id and dirty else "", r.get("name", rid), rid,
			"  [고정 던전]" if kind == "dungeon" else ("  [랜덤 던전]" if kind == "random_dungeon" else "")])
		_list.set_item_metadata(i, rid)
		if rid == region_id:
			_list.select(i)


func open_region(rid: String) -> bool:
	if dirty and rid != region_id:
		_set_status("저장하지 않은 변경이 있습니다 — 저장하거나 '파일에서 다시 읽기' 후 다른 지역을 여세요")
		refresh_list()
		return false
	var d: Variant = DialogueData.read_json(RegionDB.path_for(rid))
	if not d is Dictionary:
		return false
	doc = d
	region_id = rid
	dirty = false
	sel = {}
	place = ""
	_undo.clear()
	_redo.clear()
	_snap = JSON.stringify(doc)
	_zoom = 1.0
	_pan = Vector2.ZERO
	_tex = null
	_tex_dirty = true
	_tex_t = 1.0
	refresh_list()
	_fit()
	_show_inspector()
	validate(false)
	_update_status()
	return true


## A copy of the open region as a new file (new id / name), saved at once.
func create_region(rid: String, name: String) -> bool:
	if rid == "" or not rid.is_valid_filename() or rid != rid.to_lower() or rid.contains(" ") or rid.contains("."):
		_set_status("지역 ID는 영문 소문자·숫자·_ 로 된 파일 이름이어야 합니다: '%s'" % rid)
		return false
	if RegionDB.all().has(rid) or FileAccess.file_exists(RegionDB.path_for(rid)):
		_set_status("이미 있는 지역 ID: %s" % rid)
		return false
	if doc.is_empty() or dirty:
		_set_status("먼저 복제할 지역을 열고 저장하세요")
		return false
	var d: Dictionary = doc.duplicate(true)
	d["region_id"] = rid
	d["name"] = name if name != "" else rid
	if d.has("map") and d["map"] is Dictionary:
		d["map"]["origin"] = [0, 0]
	var err := RegionDB.save(d)
	if err != OK:
		_set_status("만들기 실패: %s" % error_string(err))
		return false
	saved.emit(RegionDB.path_for(rid))
	return open_region(rid)


func save() -> bool:
	if region_id == "":
		return false
	validate(false)
	var err := RegionDB.save(doc)
	if err != OK:
		_set_status("저장 실패: %s" % error_string(err))
		return false
	_snap = JSON.stringify(doc)
	dirty = false
	refresh_list()
	var bad := issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "error").size()
	_set_status("저장함: %s%s" % [RegionDB.path_for(region_id), "  — ⚠ 오류 %d개" % bad if bad > 0 else ""])
	saved.emit(RegionDB.path_for(region_id))
	return true


func revert() -> void:
	dirty = false
	var rid := region_id
	region_id = ""
	open_region(rid)


func _ask_new() -> void:
	_new_id.text = region_id + "_2"
	_new_name.text = str(doc.get("name", "")) + " 2"
	_new_dialog.popup_centered()


# ---------------------------------------------------------------- editing core

func _commit(rebuild := false, terrain_changed := false) -> void:
	var now := JSON.stringify(doc)
	if now != _snap:
		_undo.append(_snap)
		if _undo.size() > UNDO_LIMIT:
			_undo.pop_front()
		_redo.clear()
		_snap = now
		dirty = true
		refresh_list()
		validate(false)
		_update_status()
	if terrain_changed:
		_tex_dirty = true
		_tex_t = 0.0
	if rebuild:
		_show_inspector()
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
	dirty = true
	sel = {}
	_tex_dirty = true
	_tex_t = 1.0
	refresh_list()
	_show_inspector()
	validate(false)
	_update_status()
	_canvas.queue_redraw()


func is_dungeon() -> bool:
	return str(doc.get("kind", "")) in ["dungeon", "random_dungeon"]


func _terrain() -> Dictionary:
	if not doc.get("terrain") is Dictionary:
		doc["terrain"] = {}
	return doc["terrain"]


func _list_of(key: String) -> Array:
	if not doc.get(key) is Array:
		doc[key] = []
	return doc[key]


func _v2(a: Variant) -> Vector2:
	return TerrainField._v2(a, Vector2.ZERO)


func _arr(v: Vector2) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1)]


## Position of a selection in region metres (Vector2.INF when it has none).
func sel_pos(s: Dictionary) -> Vector2:
	match str(s.get("list", "")):
		"spawn":
			return _v2(doc.get("default_spawn", {}).get("pos", null))
		"entries":
			return _v2(doc.get("entries", {}).get(s["key"], {}).get("pos", null))
		"shape":
			var kind := str(s["kind"])
			if kind == "mounds":
				var m: Array = _terrain().get("mounds", [])
				return _v2(m[s["index"]][0]) if s["index"] < m.size() else Vector2.INF
			var arr: Array = _terrain().get(kind, [])
			return _v2(arr[s["index"]].get("center", null)) if s["index"] < arr.size() else Vector2.INF
		"path":
			var paths: Array = _terrain().get("paths", [])
			if s["index"] < paths.size() and s["point"] < (paths[s["index"]] as Array).size():
				return _v2(paths[s["index"]][s["point"]])
			return Vector2.INF
		"":
			return Vector2.INF
	var lst: Array = doc.get(s["list"], [])
	if s["index"] >= lst.size():
		return Vector2.INF
	var o: Dictionary = lst[s["index"]]
	return _v2(o.get("center", o.get("pos", null)))


func set_sel_pos(s: Dictionary, p: Vector2, commit := true) -> void:
	var a := _arr(p)
	var terrain_changed := false
	match str(s.get("list", "")):
		"spawn":
			if not doc.get("default_spawn") is Dictionary:
				doc["default_spawn"] = {"pos": a, "yaw": 0.0}
			doc["default_spawn"]["pos"] = a
		"entries":
			doc["entries"][s["key"]]["pos"] = a
		"shape":
			terrain_changed = true
			if s["kind"] == "mounds":
				_terrain()["mounds"][s["index"]][0] = a
			else:
				_terrain()[s["kind"]][s["index"]]["center"] = a
		"path":
			terrain_changed = true
			_terrain()["paths"][s["index"]][s["point"]] = a
		"":
			return
		_:
			var o: Dictionary = doc[s["list"]][s["index"]]
			o["center" if o.has("center") else "pos"] = a
			terrain_changed = s["list"] == "cities"
	if commit:
		_commit(true, terrain_changed)
	else:
		_canvas.queue_redraw()


func delete_selected() -> void:
	if sel.is_empty():
		return
	match str(sel["list"]):
		"spawn":
			doc.erase("default_spawn")
		"entries":
			doc["entries"].erase(sel["key"])
		"shape":
			(_terrain()[sel["kind"]] as Array).remove_at(sel["index"])
		"path":
			var pts: Array = _terrain()["paths"][sel["index"]]
			pts.remove_at(sel["point"])
			if pts.size() < 2:
				(_terrain()["paths"] as Array).remove_at(sel["index"])
		_:
			(doc[sel["list"]] as Array).remove_at(sel["index"])
	var tc: bool = sel["list"] in ["shape", "path"] or sel["list"] == "cities"
	sel = {}
	_commit(true, tc)


func start_place(what: String) -> void:
	place = what
	_set_status("그림을 클릭해 자리를 정하세요 (Esc 취소)" if what != "" else "")
	_canvas.queue_redraw()


func _unique_id(list: Array, prefix: String) -> String:
	var i := 1
	while true:
		var cand := "%s_%d" % [prefix, i]
		var taken := false
		for o in list:
			if o is Dictionary and str(o.get("id", "")) == cand:
				taken = true
		if not taken:
			return cand
		i += 1
	return prefix


## Adds something at a region position (buttons + canvas click; also used by the selftest).
## Returns the new selection.
func add_at(what: String, p: Vector2) -> Dictionary:
	var a := _arr(p)
	var s := {}
	if what == "spawn":
		doc["default_spawn"] = {"pos": a, "yaw": float(doc.get("default_spawn", {}).get("yaw", 0.0))}
		s = {"list": "spawn"}
	elif what.begins_with("entry:"):
		var key := what.get_slice(":", 1)
		if not doc.get("entries") is Dictionary:
			doc["entries"] = {}
		if not doc["entries"].has(key):
			doc["entries"][key] = {"pos": a, "yaw": 0.0}
		else:
			doc["entries"][key]["pos"] = a
		s = {"list": "entries", "key": key}
	elif LISTS.has(what):
		var lst := _list_of(what)
		var o: Dictionary = (LISTS[what]["new"] as Dictionary).duplicate(true)
		if o.has("id"):
			o["id"] = _unique_id(lst, what.trim_suffix("s") if what != "gather" else "gather")
		if o.has("center"):
			o["center"] = a
			if o.has("plaza"):
				o["plaza"]["center"] = a
				o["arrival"]["pos"] = [a[0], a[1] + 20.0]
				o["parking"]["pos"] = [a[0] + 6.0, a[1] + 20.0]
		else:
			o["pos"] = a
		if o.has("pier"):
			o["pier"] = [a[0], a[1] - 1.0]
		if what == "exits":
			var others := RegionDB.all().keys().filter(func(r: String) -> bool: return r != region_id)
			if not others.is_empty():
				o["to_region"] = str(others[0])
				var ents: Dictionary = RegionDB.all()[o["to_region"]].get("entries", {})
				o["to_entry"] = str(ents.keys()[0]) if not ents.is_empty() else ""
		lst.append(o)
		s = {"list": what, "index": lst.size() - 1}
	elif SHAPES.has(what):
		var t := _terrain()
		if not t.get(what) is Array:
			t[what] = []
		var sh: Dictionary = (SHAPES[what]["new"] as Dictionary).duplicate(true)
		sh["center"] = a
		t[what].append(sh)
		s = {"list": "shape", "kind": what, "index": t[what].size() - 1}
	elif what == "mounds":
		var t2 := _terrain()
		if not t2.get("mounds") is Array:
			t2["mounds"] = []
		t2["mounds"].append([a, 1.5, 6.0])
		s = {"list": "shape", "kind": "mounds", "index": t2["mounds"].size() - 1}
	elif what == "path":
		var t3 := _terrain()
		if not t3.get("paths") is Array:
			t3["paths"] = []
		t3["paths"].append([a])
		s = {"list": "path", "index": t3["paths"].size() - 1, "point": 0}
	elif what == "point":
		var paths: Array = _terrain().get("paths", [])
		if sel.get("list", "") == "path" and sel["index"] < paths.size():
			var pts: Array = paths[sel["index"]]
			var at: int = mini(int(sel["point"]) + 1, pts.size())
			pts.insert(at, a)
			s = {"list": "path", "index": sel["index"], "point": at}
		elif not paths.is_empty():
			var last: Array = paths[paths.size() - 1]
			last.append(a)
			s = {"list": "path", "index": paths.size() - 1, "point": last.size() - 1}
		else:
			return add_at("path", p)
	else:
		return {}
	sel = s
	_commit(true, what in SHAPES or what in ["mounds", "path", "point", "cities"])
	return s


# ---------------------------------------------------------------- canvas

func _bounds() -> Rect2:
	var r := MapDB.region_rect_of(RegionDB.expanded(doc)) if not doc.is_empty() else Rect2(-100, -100, 200, 200)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		r = Rect2(-100, -100, 200, 200)
	return r


func _fit() -> void:
	if _canvas == null or _canvas.size.x < 10.0 or doc.is_empty():
		return
	var r := _bounds()
	var pad := 20.0
	_scale = minf((_canvas.size.x - pad * 2) / r.size.x, (_canvas.size.y - pad * 2) / r.size.y) * _zoom
	_origin = (_canvas.size - r.size * _scale) * 0.5 - r.position * _scale + _pan
	_canvas.queue_redraw()


func to_canvas(p: Vector2) -> Vector2:
	return _origin + p * _scale


func to_region(c: Vector2) -> Vector2:
	return (c - _origin) / _scale


func _rebuild_texture() -> void:
	_tex_dirty = false
	if doc.is_empty():
		return
	var img := MapDB.terrain_image_of(RegionDB.expanded(doc))
	_tex = ImageTexture.create_from_image(img)
	_canvas.queue_redraw()


## Everything that can be picked: [{sel, pos}]
func _pickables() -> Array:
	var out := []
	if doc.get("default_spawn") is Dictionary:
		out.append({"sel": {"list": "spawn"}, "pos": sel_pos({"list": "spawn"})})
	for key: String in doc.get("entries", {}):
		out.append({"sel": {"list": "entries", "key": key}, "pos": _v2(doc["entries"][key].get("pos", null))})
	for k: String in LISTS:
		var lst: Array = doc.get(k, []) if doc.get(k) is Array else []
		for i in lst.size():
			var o: Dictionary = lst[i]
			out.append({"sel": {"list": k, "index": i}, "pos": _v2(o.get("center", o.get("pos", null)))})
	var t: Dictionary = doc.get("terrain", {}) if doc.get("terrain") is Dictionary else {}
	for kind: String in SHAPES:
		var arr: Array = t.get(kind, []) if t.get(kind) is Array else []
		for i in arr.size():
			out.append({"sel": {"list": "shape", "kind": kind, "index": i}, "pos": _v2(arr[i].get("center", null))})
	var mounds: Array = t.get("mounds", []) if t.get("mounds") is Array else []
	for i in mounds.size():
		out.append({"sel": {"list": "shape", "kind": "mounds", "index": i}, "pos": _v2(mounds[i][0])})
	var paths: Array = t.get("paths", []) if t.get("paths") is Array else []
	for i in paths.size():
		for j in (paths[i] as Array).size():
			out.append({"sel": {"list": "path", "index": i, "point": j}, "pos": _v2(paths[i][j])})
	return out


## A click on the canvas at local position c (also used by the selftest).
func canvas_click(c: Vector2) -> void:
	var p := to_region(c)
	if place != "":
		var what := place
		place = ""
		add_at(what, p)
		_set_status("")
		return
	var best := {}
	var best_d := PICK
	for it: Dictionary in _pickables():
		var d := to_canvas(it["pos"]).distance_to(c)
		if d < best_d:
			best_d = d
			best = it["sel"]
	sel = best
	_show_inspector()
	_canvas.queue_redraw()


func _canvas_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				canvas_click(mb.position)
				_drag = not sel.is_empty()
			else:
				if _drag:
					_commit(true, sel.get("list", "") in ["shape", "path", "cities"])
				_drag = false
			_canvas.accept_event()
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_panning = mb.pressed
			_canvas.accept_event()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before := to_region(mb.position)
			_zoom = clampf(_zoom * (1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 0.5, 12.0)
			_fit()
			_pan += (to_canvas(before) - mb.position) * -1.0
			_fit()
			_canvas.accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _drag and not sel.is_empty():
			set_sel_pos(sel, to_region(mm.position), false)
		elif _panning:
			_pan += mm.relative
			_fit()


func _draw_canvas() -> void:
	var f := get_theme_default_font()
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(0.12, 0.13, 0.15))
	if doc.is_empty():
		return
	var r := _bounds()
	var area := Rect2(to_canvas(r.position), r.size * _scale)
	if _tex:
		_canvas.draw_texture_rect(_tex, area, false)
	_canvas.draw_rect(area, Color(0.9, 0.8, 0.55), false, 2.0)
	var t: Dictionary = doc.get("terrain", {}) if doc.get("terrain") is Dictionary else {}
	# terrain shapes (outlines), mounds, roads with their points
	for kind: String in SHAPES:
		var col: Color = SHAPES[kind]["color"]
		var arr: Array = t.get(kind, []) if t.get(kind) is Array else []
		for i in arr.size():
			var c := to_canvas(_v2(arr[i].get("center", null)))
			var selected: bool = sel.get("list", "") == "shape" and sel.get("kind", "") == kind and sel.get("index", -1) == i
			_canvas.draw_arc(c, float(arr[i].get("radius", 5)) * _scale, 0, TAU, 40, col if not selected else Color(1, 0.4, 0.3), 2.5 if selected else 1.5)
			_canvas.draw_circle(c, 3.5, col)
	var mounds: Array = t.get("mounds", []) if t.get("mounds") is Array else []
	for i in mounds.size():
		var m: Array = mounds[i]
		var c2 := to_canvas(_v2(m[0]))
		var selected2: bool = sel.get("list", "") == "shape" and sel.get("kind", "") == "mounds" and sel.get("index", -1) == i
		_canvas.draw_arc(c2, float(m[2]) * _scale, 0, TAU, 24, Color(0.7, 0.6, 0.4, 0.8) if not selected2 else Color(1, 0.4, 0.3), 1.0 if not selected2 else 2.5)
		_canvas.draw_string(f, c2 + Vector2(4, -4), "언덕 %.1f" % float(m[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.75, 0.55))
	var paths: Array = t.get("paths", []) if t.get("paths") is Array else []
	for i in paths.size():
		var pts: Array = paths[i]
		for j in pts.size():
			var c3 := to_canvas(_v2(pts[j]))
			if j > 0:
				_canvas.draw_line(to_canvas(_v2(pts[j - 1])), c3, Color(0.55, 0.42, 0.25), 2.0)
			var selp: bool = sel.get("list", "") == "path" and sel.get("index", -1) == i and sel.get("point", -1) == j
			_canvas.draw_circle(c3, 4.0 if selp else 2.5, Color(1, 0.4, 0.3) if selp else Color(0.95, 0.85, 0.6))
	# placed lists
	for k: String in LISTS:
		var col2: Color = LISTS[k]["color"]
		var lst: Array = doc.get(k, []) if doc.get(k) is Array else []
		for i in lst.size():
			var o: Dictionary = lst[i]
			var c4 := to_canvas(_v2(o.get("center", o.get("pos", null))))
			var selected3: bool = sel.get("list", "") == k and sel.get("index", -1) == i
			if k == "cities":
				var sz := _v2(o.get("size", null)) * _scale
				_canvas.draw_rect(Rect2(c4 - sz * 0.5, sz), col2, false, 2.0)
			if o.has("radius"):
				_canvas.draw_arc(c4, float(o["radius"]) * _scale, 0, TAU, 24, Color(col2, 0.6), 1.0)
			if k == "exits":
				_canvas.draw_circle(c4, 5.0, col2)
			elif k == "checkpoints":
				_canvas.draw_colored_polygon(PackedVector2Array([c4 + Vector2(0, -6), c4 + Vector2(5, 4), c4 + Vector2(-5, 4)]), col2)
			else:
				_canvas.draw_circle(c4, 4.5, col2)
			if o.has("pier"):
				_canvas.draw_line(c4, to_canvas(_v2(o["pier"])), col2, 2.0)
			var name := str(o.get("name", o.get("id", o.get("look", o.get("kind", k)))))
			_canvas.draw_string(f, c4 + Vector2(7, 4), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col2, 0.9))
			if selected3:
				_canvas.draw_arc(c4, 11.0, 0, TAU, 24, Color(1, 0.4, 0.3), 2.5)
	# arrival points
	for key: String in doc.get("entries", {}) if doc.get("entries") is Dictionary else {}:
		var e: Dictionary = doc["entries"][key]
		var c5 := to_canvas(_v2(e.get("pos", null)))
		var yaw := float(e.get("yaw", 0.0))
		var dir := Vector2(-sin(yaw), -cos(yaw)) * 10.0
		_canvas.draw_line(c5, c5 + dir, Color(0.5, 1.0, 0.5), 2.0)
		_canvas.draw_circle(c5, 3.5, Color(0.5, 1.0, 0.5))
		_canvas.draw_string(f, c5 + Vector2(6, -6), "도착 " + key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 1.0, 0.6))
		if sel.get("list", "") == "entries" and sel.get("key", "") == key:
			_canvas.draw_arc(c5, 11.0, 0, TAU, 24, Color(1, 0.4, 0.3), 2.5)
	# the new-character start
	if doc.get("default_spawn") is Dictionary:
		var sp: Dictionary = doc["default_spawn"]
		var c6 := to_canvas(_v2(sp.get("pos", null)))
		var yaw2 := float(sp.get("yaw", 0.0))
		var d2 := Vector2(-sin(yaw2), -cos(yaw2))
		var side := Vector2(-d2.y, d2.x)
		_canvas.draw_colored_polygon(PackedVector2Array([c6 + d2 * 12.0, c6 - d2 * 6.0 + side * 7.0, c6 - d2 * 6.0 - side * 7.0]), Color(1.0, 0.35, 0.35))
		_canvas.draw_string(f, c6 + Vector2(10, 6), "시작 위치 (새 캐릭터)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.7, 0.7))
		if sel.get("list", "") == "spawn":
			_canvas.draw_arc(c6, 15.0, 0, TAU, 24, Color(1, 0.4, 0.3), 2.5)
	if place != "":
		_canvas.draw_string(f, Vector2(10, 22), "클릭해서 놓기: %s" % _place_label(place), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.5))
	_canvas.draw_string(f, Vector2(10, _canvas.size.y - 10), "%s — %d × %d m · 휠 확대 · 오른쪽 끌기 이동" % [doc.get("name", region_id), int(r.size.x), int(r.size.y)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.82, 0.86))


func _place_label(what: String) -> String:
	if LISTS.has(what):
		return LISTS[what]["label"]
	if SHAPES.has(what):
		return SHAPES[what]["label"]
	return {"spawn": "시작 위치", "mounds": "언덕", "path": "새 길", "point": "길 점"}.get(what, what)


# ---------------------------------------------------------------- inspector

func _show_inspector() -> void:
	for c in _inspector.get_children():
		_inspector.remove_child(c)
		c.queue_free()
	if doc.is_empty():
		_label(_inspector, "왼쪽에서 지역을 고르세요.", true)
		return
	_heading(_inspector, "지역: %s" % region_id)
	_label(_inspector, "이름")
	_line(_inspector, str(doc.get("name", "")), func(s: String) -> void: _set_field(doc, "name", s))
	var r1 := HBoxContainer.new()
	_inspector.add_child(r1)
	_label(r1, "위험도 (별 수)")
	_spin(r1, float(doc.get("danger", 1)), 0, 5, 1, func(v: float) -> void: _set_field(doc, "danger", int(v)))
	_label(_inspector, "설명")
	_line(_inspector, str(doc.get("desc", "")), func(s: String) -> void: _set_field(doc, "desc", s))
	if doc.get("map") is Dictionary:
		var r2 := HBoxContainer.new()
		_inspector.add_child(r2)
		var mo := _v2(doc["map"].get("origin", null))
		_label(r2, "세계 지도 위 자리 x")
		_spin(r2, mo.x, -2000, 2000, 1, func(v: float) -> void:
			doc["map"]["origin"] = [v, _v2(doc["map"].get("origin", null)).y]
			_commit())
		_label(r2, "z")
		_spin(r2, mo.y, -2000, 2000, 1, func(v: float) -> void:
			doc["map"]["origin"] = [_v2(doc["map"].get("origin", null)).x, v]
			_commit())
	if not is_dungeon():
		var t := _terrain()
		var r3 := HBoxContainer.new()
		_inspector.add_child(r3)
		var mn := TerrainField._v2(t.get("min", null), TerrainField.MIN)
		var mx := TerrainField._v2(t.get("max", null), TerrainField.MAX)
		_label(r3, "크기 (m)  가로")
		_spin(r3, mx.x - mn.x, 40, 1000, 10, func(v: float) -> void:
			t["min"] = [-v * 0.5, mn.y]
			t["max"] = [v * 0.5, mx.y]
			_commit(true, true)
			_fit())
		_label(r3, "세로")
		_spin(r3, mx.y - mn.y, 40, 1000, 10, func(v: float) -> void:
			t["min"] = [mn.x, -v * 0.5]
			t["max"] = [mx.x, v * 0.5]
			_commit(true, true)
			_fit())
		var r4 := HBoxContainer.new()
		_inspector.add_child(r4)
		_label(r4, "지형 씨앗")
		_spin(r4, float(t.get("seed", 1)), 0, 9999, 1, func(v: float) -> void:
			t["seed"] = int(v)
			_commit(false, true))
		_label(r4, "언덕 굴곡")
		_spin(r4, float(t.get("hill_noise", 0.5)), 0, 2, 0.05, func(v: float) -> void:
			t["hill_noise"] = v
			_commit(false, true))
	else:
		_grid_editor()
	_inspector.add_child(HSeparator.new())
	# the new-character start
	_heading(_inspector, "시작 위치 (새 캐릭터가 깨어나는 자리)")
	if doc.get("default_spawn") is Dictionary:
		var sp: Dictionary = doc["default_spawn"]
		var r5 := HBoxContainer.new()
		_inspector.add_child(r5)
		var p := _v2(sp.get("pos", null))
		_label(r5, "x")
		_spin(r5, p.x, -1000, 1000, 0.1, func(v: float) -> void: set_sel_pos({"list": "spawn"}, Vector2(v, _v2(doc["default_spawn"]["pos"]).y), true))
		_label(r5, "z")
		_spin(r5, p.y, -1000, 1000, 0.1, func(v: float) -> void: set_sel_pos({"list": "spawn"}, Vector2(_v2(doc["default_spawn"]["pos"]).x, v), true))
		_label(r5, "바라보는 방향 °")
		_spin(r5, rad_to_deg(float(sp.get("yaw", 0.0))), -180, 180, 5, func(v: float) -> void:
			doc["default_spawn"]["yaw"] = snappedf(deg_to_rad(v), 0.0001)
			_commit())
		_label(_inspector, "0° = 북쪽(화면 위), 180° = 남쪽(화면 아래). 그림의 빨간 화살표를 끌어도 됨.", true)
	else:
		_btn(_inspector, "시작 위치 놓기 (그림 클릭)", func() -> void: start_place("spawn"))
	_inspector.add_child(HSeparator.new())
	# selection
	match str(sel.get("list", "")):
		"":
			_label(_inspector, "그림에서 무언가를 클릭해 고르고 끌어 옮기세요. 위 버튼으로 새로 놓습니다.", true)
		"spawn":
			_label(_inspector, "선택: 시작 위치 (위에서 편집)", true)
		"entries":
			_entry_inspector(str(sel["key"]))
		"shape":
			_shape_inspector(str(sel["kind"]), int(sel["index"]))
		"path":
			_path_inspector(int(sel["index"]), int(sel["point"]))
		_:
			_object_inspector(str(sel["list"]), int(sel["index"]))
	_inspector.add_child(HSeparator.new())
	# arrival points (entries) — one per exit of a neighbour that leads here
	_heading(_inspector, "도착 지점 (다른 지역에서 올 때 서는 자리)")
	var ents: Dictionary = doc.get("entries", {}) if doc.get("entries") is Dictionary else {}
	for key: String in ents:
		var kk := key
		var row := HBoxContainer.new()
		_inspector.add_child(row)
		_btn(row, key, func() -> void:
			sel = {"list": "entries", "key": kk}
			_show_inspector()
			_canvas.queue_redraw())
		_btn(row, "자리 찍기", func() -> void: start_place("entry:" + kk))
	var add := HBoxContainer.new()
	_inspector.add_child(add)
	var ne := _line(add, "", func(_s: String) -> void: pass, "새 도착 지점 ID")
	_btn(add, "+ 추가 (그림 클릭)", func() -> void:
		if ne.text.strip_edges() != "":
			start_place("entry:" + ne.text.strip_edges()))


func _set_field(d: Dictionary, key: String, value: Variant, rebuild := false, terrain := false) -> void:
	if d.get(key) == value:
		return
	d[key] = value
	_commit(rebuild, terrain)


func _entry_inspector(key: String) -> void:
	_heading(_inspector, "선택: 도착 지점 '%s'" % key)
	var e: Dictionary = doc["entries"][key]
	_generic_fields(e, {"yaw_deg": true})
	_btn(_inspector, "이 도착 지점 지우기", delete_selected)


func _shape_inspector(kind: String, index: int) -> void:
	var t := _terrain()
	if kind == "mounds":
		var m: Array = t["mounds"][index]
		_heading(_inspector, "선택: 언덕 %d" % (index + 1))
		var row := HBoxContainer.new()
		_inspector.add_child(row)
		_label(row, "높이 m")
		_spin(row, float(m[1]), 0, 20, 0.1, func(v: float) -> void:
			m[1] = v
			_commit(false, true))
		_label(row, "너비 m")
		_spin(row, float(m[2]), 1, 60, 0.5, func(v: float) -> void:
			m[2] = v
			_commit(false, true))
	else:
		var sh: Dictionary = t[kind][index]
		_heading(_inspector, "선택: %s %d" % [SHAPES[kind]["label"], index + 1])
		var row2 := HBoxContainer.new()
		_inspector.add_child(row2)
		_label(row2, "반지름 m")
		_spin(row2, float(sh.get("radius", 5)), 1, 200, 0.5, func(v: float) -> void:
			sh["radius"] = v
			_commit(false, true))
	_btn(_inspector, "지우기", delete_selected)


func _path_inspector(index: int, point: int) -> void:
	var pts: Array = _terrain()["paths"][index]
	_heading(_inspector, "선택: 길 %d, 점 %d / %d" % [index + 1, point + 1, pts.size()])
	_label(_inspector, "'+ 길 점'을 누르고 그림을 클릭하면 이 점 다음에 점이 들어간다. Delete = 이 점 지우기(점이 하나만 남으면 길도 지워짐).", true)
	_btn(_inspector, "이 점 지우기", delete_selected)
	_btn(_inspector, "이 길 전체 지우기", func() -> void:
		(_terrain()["paths"] as Array).remove_at(index)
		sel = {}
		_commit(true, true))


func _object_inspector(list: String, index: int) -> void:
	var o: Dictionary = doc[list][index]
	_heading(_inspector, "선택: %s %d — %s" % [LISTS[list]["label"], index + 1, o.get("name", o.get("id", o.get("look", "")))])
	_generic_fields(o, {"yaw_deg": true, "list": list})
	_btn(_inspector, "지우기", delete_selected)


## Every field of a placed thing: numbers, switches, text, [x, z] pairs; known fields get a list
## to pick from (monster kinds, NPC looks, speakers, regions and their arrival points, flags).
func _generic_fields(o: Dictionary, opts: Dictionary) -> void:
	var list := str(opts.get("list", ""))
	for key_v in o.keys():
		var key := str(key_v)
		var val: Variant = o[key]
		var row := HBoxContainer.new()
		_inspector.add_child(row)
		_label(row, key)
		if key == "kind" and list == "monsters":
			var mopts := []
			for m: String in MonsterDB.all():
				mopts.append([m, "%s (%s)" % [MonsterDB.all()[m].get("name", m), m]])
			_opt(row, mopts, str(val), func(s: String) -> void: _set_field(o, key, s))
		elif key == "kind" and list == "gather":
			var gopts := []
			for g: String in GATHER_KINDS:
				gopts.append([g, g])
			_opt(row, gopts, str(val), func(s: String) -> void: _set_field(o, key, s))
		elif key == "look":
			var lopts := []
			for l: String in NpcRig.LOOKS:
				lopts.append([l, l])
			_opt(row, lopts, str(val), func(s: String) -> void: _set_field(o, key, s, true))
		elif key == "speaker":
			var sopts := []
			for sp: String in DialogueData.speakers():
				sopts.append([sp, DialogueData.speaker_name(sp)])
			_opt(row, sopts, str(val), func(s: String) -> void: _set_field(o, key, s))
		elif key == "to_region":
			var ropts := []
			for rid: String in RegionDB.all():
				ropts.append([rid, RegionDB.region_name(rid)])
			_opt(row, ropts, str(val), func(s: String) -> void:
				o[key] = s
				var ents: Dictionary = RegionDB.all().get(s, {}).get("entries", {})
				o["to_entry"] = str(ents.keys()[0]) if not ents.is_empty() else ""
				_commit(true))
		elif key == "to_entry":
			var eopts := []
			for en: String in RegionDB.all().get(str(o.get("to_region", "")), {}).get("entries", {}):
				eopts.append([en, en])
			_opt(row, eopts, str(val), func(s: String) -> void: _set_field(o, key, s))
		elif key == "flag":
			var fl := _line(row, str(val), func(s: String) -> void: _set_field(o, key, s.strip_edges()))
			var fopts := [["", "아는 플래그…"]]
			for f: String in QuestDB.known_flags():
				fopts.append([f, f])
			_opt(row, fopts, "", func(s: String) -> void:
				if s != "":
					fl.text = s
					_set_field(o, key, s))
		elif key == "yaw" and opts.get("yaw_deg", false):
			_label(row, "(도, 0 = 북쪽)")
			_spin(row, rad_to_deg(float(val)), -180, 180, 5, func(v: float) -> void: _set_field(o, key, snappedf(deg_to_rad(v), 0.0001)))
		elif val is bool:
			_check(row, "", bool(val), func(v: bool) -> void: _set_field(o, key, v))
		elif val is float or val is int:
			_spin(row, float(val), -100000, 100000, 0.1 if val is float else 1, func(v: float) -> void:
				_set_field(o, key, v if val is float else int(v), false, list == "cities"))
		elif val is Array and (val as Array).size() == 2 and (val[0] is float or val[0] is int) and (val[1] is float or val[1] is int):
			_label(row, "x")
			_spin(row, float(val[0]), -100000, 100000, 0.1, func(v: float) -> void:
				o[key] = [v, float(o[key][1])]
				_commit(false, list == "cities"))
			_label(row, "z")
			_spin(row, float(val[1]), -100000, 100000, 0.1, func(v: float) -> void:
				o[key] = [float(o[key][0]), v]
				_commit(false, list == "cities"))
		elif val is String:
			_line(row, str(val), func(s: String) -> void: _set_field(o, key, s))
		else:
			_line(row, JSON.stringify(val), func(s: String) -> void:
				var parsed: Variant = JSON.parse_string(s)
				if parsed != null:
					_set_field(o, key, parsed, true, list == "cities"), "JSON")


## Fixed dungeons are drawn as a text grid: edit the rows here (see the legend) and apply.
func _grid_editor() -> void:
	_heading(_inspector, "던전 칸 그림 (한 줄 = 한 행)")
	_label(_inspector, str(doc.get("_legend", "# 벽 · . 바닥 · S 도착 · E 나가는 길 · K 쉼터 · T 횃불 · C 상자 · 글자 = 몬스터(spawn_kinds)")), true)
	var te := TextEdit.new()
	te.text = "\n".join(PackedStringArray(doc.get("grid", [])))
	te.custom_minimum_size.y = 260
	te.add_theme_font_override("font", ThemeDB.fallback_font)
	_inspector.add_child(te)
	var row := HBoxContainer.new()
	_inspector.add_child(row)
	_label(row, "칸 크기 m")
	_spin(row, float(doc.get("cell", 2.0)), 0.5, 6, 0.5, func(v: float) -> void: _set_field(doc, "cell", v, false, true))
	_btn(row, "칸 그림 적용", func() -> void:
		var rows := []
		for l in te.text.split("\n"):
			if l.strip_edges() != "":
				rows.append(l)
		doc["grid"] = rows
		_commit(true, true))


# ---------------------------------------------------------------- validation / status

func validate(show := false) -> Array:
	issues = RegionEditorPanel.check(doc) if not doc.is_empty() else []
	_issue_list.clear()
	for it: Dictionary in issues:
		_issue_list.add_item("%s %s" % ["⛔" if it["severity"] == "error" else "⚠", it["message"]])
	if issues.is_empty():
		_issue_list.add_item("✔ 문제 없음")
	if show:
		_set_status("검증: 오류 %d, 경고 %d" % [issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "error").size(),
			issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "warning").size()])
	return issues


## [{"severity", "message"}]: ids, exits and their targets, monster kinds, NPC looks, the start
## and arrival points inside the bounds, story flags.
static func check(d: Dictionary) -> Array:
	var out := []
	var rid := str(d.get("region_id", ""))
	if rid == "":
		out.append({"severity": "error", "message": "region_id가 비었다"})
	if str(d.get("name", "")).strip_edges() == "":
		out.append({"severity": "error", "message": "이름이 비었다"})
	var exp := RegionDB.expanded(d)
	var rect := MapDB.region_rect_of(exp)
	var inside := func(p: Variant) -> bool:
		var v := TerrainField._v2(p, Vector2.INF)
		return v != Vector2.INF and rect.grow(1.0).has_point(v)
	if d.get("default_spawn") is Dictionary:
		if not inside.call(d["default_spawn"].get("pos", null)):
			out.append({"severity": "error", "message": "시작 위치가 지역 밖이다"})
	elif d.get("kind", "") == "":
		out.append({"severity": "warning", "message": "시작 위치(default_spawn)가 없다 — 새 캐릭터·투어는 기본 자리에서 시작"})
	for key: String in ["monsters", "checkpoints", "exits", "story_triggers", "gather", "fishing_spots", "cities"]:
		var ids := {}
		for o in d.get(key, []) if d.get(key) is Array else []:
			if not o is Dictionary:
				continue
			var oid := str(o.get("id", ""))
			if o.has("id"):
				if oid == "" or ids.has(oid):
					out.append({"severity": "error", "message": "%s ID가 비었거나 겹친다 ('%s')" % [LISTS[key]["label"], oid]})
				ids[oid] = true
			if not inside.call(o.get("center", o.get("pos", null))):
				out.append({"severity": "warning", "message": "%s '%s'가 지역 밖이다" % [LISTS[key]["label"], oid]})
	for m in d.get("monsters", []) if d.get("monsters") is Array else []:
		if m is Dictionary and not MonsterDB.all().has(str(m.get("kind", ""))):
			out.append({"severity": "error", "message": "몬스터 '%s': 없는 종류 '%s' (data/monsters.json)" % [m.get("id", ""), m.get("kind", "")]})
	for n in d.get("npcs", []) if d.get("npcs") is Array else []:
		if n is Dictionary:
			if not NpcRig.LOOKS.has(str(n.get("look", ""))):
				out.append({"severity": "error", "message": "NPC: 없는 외형 '%s' (npc_rig.gd LOOKS)" % n.get("look", "")})
			var sp := str(n.get("speaker", n.get("look", "")))
			if str(n.get("upgrades", "")) == "" and not DialogueData.speakers().has(sp):
				out.append({"severity": "warning", "message": "NPC '%s': 화자 '%s'가 data/speakers.json에 없다 (대화가 안 열림)" % [n.get("look", ""), sp]})
	for e in d.get("exits", []) if d.get("exits") is Array else []:
		if not e is Dictionary:
			continue
		var to := str(e.get("to_region", ""))
		if not RegionDB.all().has(to):
			out.append({"severity": "error", "message": "출구 '%s': 없는 지역 '%s'" % [e.get("id", ""), to]})
		elif RegionDB.all()[to].get("kind", "") != "random_dungeon" and not RegionDB.all()[to].get("entries", {}).has(str(e.get("to_entry", ""))):  # random dungeons make their 'start' per floor
			out.append({"severity": "error", "message": "출구 '%s': %s에 도착 지점 '%s'가 없다" % [e.get("id", ""), to, e.get("to_entry", "")]})
	for key: String in d.get("entries", {}) if d.get("entries") is Dictionary else {}:
		if not inside.call(d["entries"][key].get("pos", null)):
			out.append({"severity": "warning", "message": "도착 지점 '%s'가 지역 밖이다" % key})
	for tr in d.get("story_triggers", []) if d.get("story_triggers") is Array else []:
		if tr is Dictionary and str(tr.get("flag", "")) == "" and str(tr.get("toast", "")) == "":
			out.append({"severity": "warning", "message": "이야기 장소 '%s': 플래그도 안내문도 없다" % tr.get("id", "")})
	if d.get("kind", "") == "dungeon":
		var grid: Array = d.get("grid", [])
		var w := -1
		var has_s := false
		for row in grid:
			if w >= 0 and str(row).length() != w:
				out.append({"severity": "error", "message": "던전 칸 그림의 줄 길이가 다르다"})
				break
			w = str(row).length()
			has_s = has_s or str(row).contains("S")
		if not has_s:
			out.append({"severity": "error", "message": "던전 칸 그림에 도착 칸 'S'가 없다"})
	return out


func _set_status(text: String) -> void:
	_status.text = text


func _update_status() -> void:
	if doc.is_empty():
		_set_status("지역을 고르세요")
		return
	var counts := PackedStringArray()
	for k: String in LISTS:
		var n: int = (doc.get(k, []) as Array).size() if doc.get(k) is Array else 0
		if n > 0:
			counts.append("%s %d" % [LISTS[k]["label"], n])
	_set_status("%s%s — %s · %s" % ["● " if dirty else "", doc.get("name", region_id), " · ".join(counts), "저장하지 않은 변경 있음" if dirty else "저장됨"])
