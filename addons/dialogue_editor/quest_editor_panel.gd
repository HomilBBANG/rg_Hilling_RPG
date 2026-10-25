@tool
class_name QuestEditorPanel
extends Control
## The dialogue editor's 퀘스트 tab: quest definitions (data/quests/<quest_id>.json, QuestDB).
## Left: every quest file. Right: title / description / source / giver / how it is accepted,
## the start trigger of a field event (placed with a click on the region picture), objectives
## (collect / kill / count / flag), rewards, optional outcome branches. Below: validation and
## "where used" (dialogue actions, conditions, cutscene steps — double-click opens that tab).
## The game reads the same files through QuestDB / QuestManager; nothing here is needed at runtime.

signal saved(path: String)
signal play_requested(quest_id: String)
signal open_ref(kind: String, id: String, node: String)

const UNDO_LIMIT := 200
const SOURCE_ORDER := ["story", "npc", "board", "event"]

var doc := {}
var quest_id := ""
var dirty := false
var issues: Array = []
var refs: Array = []
var can_play_in_game := false
var place := false  ## next click on the trigger picture sets the start position

var _undo: Array[String] = []
var _redo: Array[String] = []
var _snap := ""

var _list: ItemList
var _inspector: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _issue_list: ItemList
var _ref_list: ItemList
var _play_btn: Button
var _new_dialog: ConfirmationDialog
var _new_id: LineEdit
var _new_title: LineEdit
var _confirm: ConfirmationDialog
var _confirm_cb: Callable
var _canvas: Control
var _zoom := MapZoom.new()
var _drag := false


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()
	refresh_list()
	var ids := _sorted_ids()
	if not ids.is_empty():
		open_quest("quest.rosa.jelly" if ids.has("quest.rosa.jelly") else str(ids[0]))


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


func _text(parent: Control, value: String, cb: Callable) -> TextEdit:
	var t := TextEdit.new()
	t.text = value
	t.custom_minimum_size.y = 72
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.focus_exited.connect(func() -> void: cb.call(t.text))
	parent.add_child(t)
	return t


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


## options = [[value, label], ...]; a current value outside the list is shown as "(알 수 없음)".
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


func _item_options() -> Array:
	var out := []
	var keys := ItemDB.ITEMS.keys()
	keys.sort()
	for k: String in keys:
		out.append([k, "%s (%s)" % [ItemDB.item_name(k), k]])
	return out


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bar := HFlowContainer.new()
	root.add_child(bar)
	_btn(bar, "새 퀘스트", _ask_new, "새 퀘스트 파일 만들기 (data/quests)")
	_btn(bar, "저장", func() -> void: save(), "Ctrl+S — data/quests/<퀘스트 ID>.json")
	_btn(bar, "파일에서 다시 읽기", revert, "저장하지 않은 변경 버리기")
	_btn(bar, "↶", undo, "실행 취소 (Ctrl+Z)")
	_btn(bar, "↷", redo, "다시 실행 (Ctrl+Y / Ctrl+Shift+Z)")
	bar.add_child(VSeparator.new())
	_btn(bar, "검증", func() -> void: validate(true))
	_btn(bar, "이 퀘스트 지우기", _ask_delete, "파일을 지운다 (대화·컷씬에서 쓰고 있으면 거기 검증 오류가 남)")
	_play_btn = _btn(bar, "게임에서 실행", func() -> void: play_requested.emit(quest_id),
		"게임을 띄우고 이 퀘스트를 받은 상태로 시작 (저장하지 않은 변경은 먼저 저장)")
	_play_btn.visible = can_play_in_game
	bar.add_child(VSeparator.new())
	_btn(bar, "플래그 목록", func() -> void: EditorWidgets.show_flag_list(self), "모든 플래그와 켜는 곳·쓰는 곳")
	EditorWidgets.help_button(bar, "quest")
	EditorWidgets.quick_guide(root, "① 왼쪽에서 퀘스트 고르기 → ② 오른쪽에서 제목·종류·목표·보상 적기 (현장 사건은 지역 그림을 클릭해 시작 자리) → ③ 검증 → ④ 저장")
	_status = Label.new()
	_status.clip_text = true
	root.add_child(_status)
	var hs := HSplitContainer.new()
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(hs)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 260
	hs.add_child(left)
	_heading(left, "퀘스트 (data/quests)")
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: open_quest(str(_list.get_item_metadata(i))))
	left.add_child(_list)
	var vs := VSplitContainer.new()
	vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.add_child(vs)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vs.add_child(_scroll)
	var scroll := _scroll
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inspector)
	var bottom := HBoxContainer.new()
	bottom.custom_minimum_size.y = 150
	vs.add_child(bottom)
	var ib := VBoxContainer.new()
	ib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(ib)
	_heading(ib, "검증")
	_issue_list = ItemList.new()
	_issue_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ib.add_child(_issue_list)
	var rb := VBoxContainer.new()
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(rb)
	_heading(rb, "쓰이는 곳 (더블클릭 = 그 탭으로)")
	_ref_list = ItemList.new()
	_ref_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ref_list.item_activated.connect(func(i: int) -> void:
		var r: Dictionary = _ref_list.get_item_metadata(i)
		if not r.is_empty():
			open_ref.emit(str(r["kind"]), str(r["id"]), str(r["node"])))
	rb.add_child(_ref_list)
	# dialogs
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "새 퀘스트"
	var nv := VBoxContainer.new()
	_new_dialog.add_child(nv)
	_label(nv, "퀘스트 ID (파일 이름. 예: quest.npc.bron.ore — 'quest.'로 시작)")
	_new_id = LineEdit.new()
	nv.add_child(_new_id)
	_label(nv, "제목")
	_new_title = LineEdit.new()
	nv.add_child(_new_title)
	_new_dialog.confirmed.connect(func() -> void:
		if not create_quest(_new_id.text.strip_edges(), _new_title.text.strip_edges()):
			_new_dialog.call_deferred("popup_centered"))
	add_child(_new_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func() -> void:
		if _confirm_cb.is_valid():
			_confirm_cb.call())
	add_child(_confirm)


func _ask(text: String, cb: Callable) -> void:
	_confirm_cb = cb
	_confirm.dialog_text = text
	_confirm.popup_centered()


func _ask_new() -> void:
	_new_id.text = "quest.npc."
	_new_title.text = ""
	_new_dialog.popup_centered()
	_new_id.grab_focus()
	_new_id.caret_column = _new_id.text.length()


func _ask_delete() -> void:
	if quest_id == "":
		return
	var used := refs.size()
	_ask("'%s' 파일을 지울까요?%s" % [quest_id, "\n대화·컷씬 %d곳에서 쓰고 있습니다 — 거기에 검증 오류가 생깁니다." % used if used > 0 else ""],
		func() -> void: delete_quest(quest_id))


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is TextEdit or focus is LineEdit or focus is SpinBox
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

func _sorted_ids() -> Array:
	var ids := QuestDB.all().keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var sa := SOURCE_ORDER.find(str(QuestDB.info(a).get("source", "")))
		var sb := SOURCE_ORDER.find(str(QuestDB.info(b).get("source", "")))
		return sa < sb if sa != sb else a < b)
	return ids


func refresh_list() -> void:
	QuestDB.reload()
	_list.clear()
	for id: String in _sorted_ids():
		var q := QuestDB.info(id)
		var i := _list.add_item("%s%s\n  %s · %s%s" % ["● " if id == quest_id and dirty else "", q.get("title", id), id,
			QuestDB.SOURCE_NAMES.get(q.get("source", ""), "?"), "  [임시]" if q.get("test_only", false) else ""])
		_list.set_item_metadata(i, id)
		if id == quest_id:
			_list.select(i)


func open_quest(id: String) -> bool:
	if dirty and id != quest_id:
		_set_status("저장하지 않은 변경이 있습니다 — 저장하거나 '파일에서 다시 읽기' 후 다른 퀘스트를 여세요")
		refresh_list()
		return false
	QuestDB.reload()
	var d := QuestDB.info(id)
	if d.is_empty():
		return false
	doc = QuestDB.normalized(d)
	quest_id = id
	dirty = false
	place = false
	_undo.clear()
	_redo.clear()
	_snap = JSON.stringify(doc)
	refs = QuestDB.references(id)
	refresh_list()
	_show_inspector()
	validate(false)
	_update_status()
	return true


## New file, saved at once so it shows in every quest picker. False (with a status line) if the id
## is bad or taken.
func create_quest(id: String, title: String) -> bool:
	if not QuestDB.valid_id(id):
		_set_status("퀘스트 ID는 'quest.'로 시작하는 파일 이름이어야 합니다 (띄어쓰기·특수문자 없이): '%s'" % id)
		return false
	if FileAccess.file_exists(QuestDB.path_for(id)):
		_set_status("이미 있는 퀘스트 ID: %s" % id)
		return false
	if dirty:
		_set_status("저장하지 않은 변경이 있습니다 — 먼저 저장하거나 '파일에서 다시 읽기'")
		return false
	var err := QuestDB.save(QuestDB.new_doc(id, title))
	if err != OK:
		_set_status("만들기 실패: %s" % error_string(err))
		return false
	saved.emit(QuestDB.path_for(id))
	return open_quest(id)


func delete_quest(id: String) -> bool:
	var p := QuestDB.path_for(id)
	if not FileAccess.file_exists(p):
		return false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	QuestDB.reload()
	if id == quest_id:
		dirty = false
		quest_id = ""
		doc = {}
		refs = []
		var ids := _sorted_ids()
		if not ids.is_empty():
			open_quest(str(ids[0]))
		else:
			refresh_list()
			_show_inspector()
			validate(false)
			_update_status()
	saved.emit(p)
	return true


func save() -> bool:
	if quest_id == "":
		return false
	doc["quest_id"] = quest_id
	validate(false)
	var err := QuestDB.save(doc)
	if err != OK:
		_set_status("저장 실패: %s" % error_string(err))
		return false
	doc = QuestDB.normalized(doc)
	_snap = JSON.stringify(doc)
	dirty = false
	refresh_list()
	var bad := issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "error").size()
	_set_status("저장함: %s%s" % [QuestDB.path_for(quest_id), "  — ⚠ 오류 %d개" % bad if bad > 0 else ""])
	saved.emit(QuestDB.path_for(quest_id))
	return true


func revert() -> void:
	dirty = false
	var id := quest_id
	quest_id = ""
	open_quest(id)


# ---------------------------------------------------------------- editing

func _commit(rebuild := false) -> void:
	var now := JSON.stringify(doc)
	if now != _snap:
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
	if rebuild:
		_show_inspector()
	elif _canvas:
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
	doc = QuestDB.normalized(JSON.parse_string(snap))
	dirty = true
	refresh_list()
	_show_inspector()
	validate(false)
	_update_status()


func set_field(key: String, value: Variant, rebuild := false) -> void:
	if doc.get(key) == value:
		return
	doc[key] = value
	_commit(rebuild)


## accept "auto" needs a trigger; "direct" drops it (kept in undo).
func set_accept(mode: String) -> void:
	doc["accept"] = mode
	if mode == "auto" and not doc.has("trigger"):
		doc["trigger"] = {"type": "reach", "region": "meadow", "pos": [0, 0], "radius": 6}
	elif mode != "auto":
		doc.erase("trigger")
	_commit(true)


func set_trigger_field(key: String, value: Variant) -> void:
	if not doc.has("trigger"):
		return
	doc["trigger"][key] = value
	_commit(key == "region")


func set_trigger_pos(p: Vector2, rebuild := true) -> void:
	if not doc.has("trigger"):
		return
	doc["trigger"]["pos"] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]
	_commit(rebuild)


func objective(obj_id: String) -> Dictionary:
	for o: Dictionary in doc.get("objectives", []):
		if o.get("id", "") == obj_id:
			return o
	return {}


func _new_obj_id() -> String:
	var i := 1
	while not objective("obj_%d" % i).is_empty():
		i += 1
	return "obj_%d" % i


func add_objective(type: String) -> String:
	var o := {"id": _new_obj_id(), "type": type, "text": ""}
	match type:
		"collect":
			o["item"] = "herb"
			o["count"] = 1
		"kill":
			o["target"] = "meadow"
			o["count"] = 1
		"flag":
			o["flag"] = ""
		_:
			o["count"] = 1
	doc["objectives"].append(o)
	_commit(true)
	return o["id"]


func set_objective_field(index: int, key: String, value: Variant) -> void:
	var objs: Array = doc["objectives"]
	if index < 0 or index >= objs.size():
		return
	if objs[index].get(key) == value:
		return
	objs[index][key] = value
	_commit(false)


## Changing the type keeps id / text and swaps the type-specific fields.
func set_objective_type(index: int, type: String) -> void:
	var objs: Array = doc["objectives"]
	if index < 0 or index >= objs.size():
		return
	var o: Dictionary = objs[index]
	var n := {"id": o.get("id", ""), "type": type, "text": o.get("text", "")}
	match type:
		"collect":
			n["item"] = str(o.get("item", "herb"))
			n["count"] = int(o.get("count", 1))
		"kill":
			n["target"] = str(o.get("target", "meadow"))
			n["count"] = int(o.get("count", 1))
		"flag":
			n["flag"] = str(o.get("flag", ""))
		_:
			n["count"] = int(o.get("count", 1))
	objs[index] = n
	_commit(true)


func move_objective(index: int, delta: int) -> void:
	var objs: Array = doc["objectives"]
	var j := index + delta
	if index < 0 or index >= objs.size() or j < 0 or j >= objs.size():
		return
	var o: Variant = objs[index]
	objs.remove_at(index)
	objs.insert(j, o)
	_commit(true)


func remove_objective(index: int) -> void:
	if index < 0 or index >= doc["objectives"].size():
		return
	doc["objectives"].remove_at(index)
	_commit(true)


func rewards(outcome := "") -> Dictionary:
	if outcome == "":
		return doc["rewards"]
	return doc.get("outcomes", {}).get(outcome, {}).get("rewards", {})


func set_reward(outcome: String, key: String, value: int) -> void:
	var r := rewards(outcome)
	if r.is_empty() or int(r.get(key, 0)) == value:
		return
	r[key] = value
	_commit(false)


func set_reward_item(outcome: String, item: String, count: int, old_item := "") -> void:
	var r := rewards(outcome)
	if r.is_empty():
		return
	if old_item != "" and old_item != item:
		r["items"].erase(old_item)
	if count <= 0:
		r["items"].erase(item)
	else:
		r["items"][item] = count
	_commit(old_item != item)


## Adds the first item not yet in the list (the designer then picks the real one).
func add_reward_item(outcome: String) -> String:
	var r := rewards(outcome)
	if r.is_empty():
		return ""
	for opt in _item_options():
		if not r["items"].has(str(opt[0])):
			r["items"][str(opt[0])] = 1
			_commit(true)
			return str(opt[0])
	return ""


func set_reward_recipes(outcome: String, list: Array) -> void:
	var r := rewards(outcome)
	if r.is_empty():
		return
	if list.is_empty():
		r.erase("recipes")
	else:
		r["recipes"] = list
	_commit(true)


func add_outcome() -> String:
	if not doc.has("outcomes"):
		doc["outcomes"] = {}
	var i := 1
	while doc["outcomes"].has("outcome_%d" % i):
		i += 1
	var key := "outcome_%d" % i
	doc["outcomes"][key] = {"label": "새 결과", "rewards": QuestDB._rewards_normalized(doc["rewards"])}
	_commit(true)
	return key


func rename_outcome(old: String, new_key: String) -> void:
	var oc: Dictionary = doc.get("outcomes", {})
	new_key = new_key.strip_edges()
	if old == new_key or new_key == "" or not oc.has(old) or oc.has(new_key):
		return
	var rebuilt := {}
	for k in oc:
		rebuilt[new_key if k == old else k] = oc[k]
	doc["outcomes"] = rebuilt
	_commit(true)


func set_outcome_label(key: String, label: String) -> void:
	var oc: Dictionary = doc.get("outcomes", {})
	if not oc.has(key) or oc[key].get("label", "") == label:
		return
	oc[key]["label"] = label
	_commit(false)


func remove_outcome(key: String) -> void:
	var oc: Dictionary = doc.get("outcomes", {})
	if not oc.has(key):
		return
	oc.erase(key)
	if oc.is_empty():
		doc.erase("outcomes")
	_commit(true)


# ---------------------------------------------------------------- inspector

func _show_inspector() -> void:
	for c in _inspector.get_children():
		_inspector.remove_child(c)
		c.queue_free()
	_canvas = null
	if doc.is_empty():
		_label(_inspector, "왼쪽에서 퀘스트를 고르거나 '새 퀘스트'를 누르세요.", true)
		return
	_heading(_inspector, "퀘스트: %s" % quest_id)
	_label(_inspector, "제목 (퀘스트 기록·알림에 보임)")
	_line(_inspector, str(doc.get("title", "")), func(s: String) -> void: set_field("title", s))
	_label(_inspector, "설명 (퀘스트 기록의 본문)")
	_text(_inspector, str(doc.get("desc", "")), func(s: String) -> void: set_field("desc", s))
	var row := HBoxContainer.new()
	_inspector.add_child(row)
	_label(row, "종류")
	var sopts := []
	for k: String in QuestDB.SOURCE_NAMES:
		sopts.append([k, QuestDB.SOURCE_NAMES[k]])
	_opt(row, sopts, str(doc.get("source", "")), func(v: String) -> void: set_field("source", v, true))
	_label(row, "의뢰인")
	var gopts := [["", "(없음)"], ["board", "게시판"]]
	for k: String in DialogueData.speakers():
		if k not in ["narrator", "player"]:
			gopts.append([k, DialogueData.speaker_name(k)])
	_opt(row, gopts, str(doc.get("giver", "")), func(v: String) -> void: set_field("giver", v))
	var row2 := HBoxContainer.new()
	_inspector.add_child(row2)
	_label(row2, "받는 방식")
	var aopts := []
	for k: String in QuestDB.ACCEPT_NAMES:
		aopts.append([k, QuestDB.ACCEPT_NAMES[k]])
	_opt(row2, aopts, str(doc.get("accept", "")), set_accept)
	var row3 := HBoxContainer.new()
	_inspector.add_child(row3)
	_check(row3, "다시 받을 수 있음 (성공·실패 뒤)", bool(doc.get("repeatable", false)), func(v: bool) -> void: set_field("repeatable", v))
	_check(row3, "완료할 때 모은 아이템을 넘김", bool(doc.get("consume_items", true)), func(v: bool) -> void: set_field("consume_items", v))
	_check(row3, "임시 데이터", bool(doc.get("test_only", false)), func(v: bool) -> void:
		if v:
			doc["test_only"] = true
		else:
			doc.erase("test_only")
		_commit(false))
	var row4 := HBoxContainer.new()
	_inspector.add_child(row4)
	_label(row4, "제한 시간 (게임 시간, 0 = 없음)")
	_spin(row4, float(doc.get("time_limit_hours", 0)), 0, 999, 0.5, func(v: float) -> void: set_field("time_limit_hours", DialogueData.intified(v)))
	match str(doc.get("source", "")):
		"npc":
			_label(_inspector, "받는 길: 대화 탭에서 그 NPC의 대화에 액션 '퀘스트 수락'을 넣는다. 보고도 대화의 '퀘스트 완료(보상)' 액션으로.", true)
		"board":
			_label(_inspector, "받는 길: 교역소 게시판에 저절로 뜬다 (종류 = 게시판 의뢰). 보고도 게시판에서.", true)
		"event":
			_label(_inspector, "받는 길: 받는 방식을 '자동 시작'으로 두고 아래 시작 조건의 자리에 가면 시작된다. 보고는 의뢰인 대화의 '퀘스트 완료(보상)'.", true)
		"story":
			_label(_inspector, "메인 이야기: 컷씬의 '퀘스트 시작/완료' 단계나 대화 액션, 또는 게임 코드가 시작·완료한다.", true)
	_inspector.add_child(HSeparator.new())
	if str(doc.get("accept", "")) == "auto":
		_trigger_section()
		_inspector.add_child(HSeparator.new())
	_objectives_section()
	_inspector.add_child(HSeparator.new())
	_heading(_inspector, "보상")
	_rewards_editor(_inspector, "")
	_inspector.add_child(HSeparator.new())
	_outcomes_section()


func _trigger_section() -> void:
	_heading(_inspector, "시작 조건 — 이 자리에 닿으면 저절로 시작")
	var t: Dictionary = doc.get("trigger", {})
	var row := HBoxContainer.new()
	_inspector.add_child(row)
	_label(row, "지역")
	var ropts := []
	for rid: String in RegionDB.all():
		if not RegionDB.is_random_dungeon(rid):
			ropts.append([rid, RegionDB.region_name(rid)])
	_opt(row, ropts, str(t.get("region", "")), func(v: String) -> void: set_trigger_field("region", v))
	var row2 := HBoxContainer.new()
	_inspector.add_child(row2)
	var p: Vector2 = TerrainField._v2(t.get("pos", null), Vector2.ZERO)
	_label(row2, "x")
	_spin(row2, p.x, -1000, 1000, 0.1, func(v: float) -> void: set_trigger_pos(Vector2(v, TerrainField._v2(doc["trigger"]["pos"], Vector2.ZERO).y), false))
	_label(row2, "z")
	_spin(row2, p.y, -1000, 1000, 0.1, func(v: float) -> void: set_trigger_pos(Vector2(TerrainField._v2(doc["trigger"]["pos"], Vector2.ZERO).x, v), false))
	_label(row2, "반경 m")
	_spin(row2, float(t.get("radius", 5)), 0.5, 200, 0.5, func(v: float) -> void: set_trigger_field("radius", DialogueData.intified(v)))
	_btn(row2, "그림에서 자리 찍기", func() -> void:
		place = true
		_set_status("아래 지역 그림을 클릭해 시작 자리를 정하세요")
		if _canvas:
			_canvas.queue_redraw()
			_scroll.call_deferred("ensure_control_visible", _canvas), "클릭한 자리가 시작 위치가 됨 — 그림이 보이도록 아래로 내려감")
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(360, 420)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	var cv := _canvas
	_canvas.resized.connect(cv.queue_redraw)
	_zoom.toolbar(_inspector, _canvas)
	_inspector.add_child(_canvas)
	_label(_inspector, "그림을 클릭하면 빨간 동그라미(시작 자리)가 거기로 갑니다. 동그라미를 끌어서 옮길 수도 있어요. 흰 점 = 출구, 노란 원 = 마을, 하늘색 ▲ = 쉼터.", true)


func _fit() -> void:
	var r := MapDB.region_rect(str(doc["trigger"].get("region", "")))
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		r = Rect2(-100, -100, 200, 200)
	_zoom.pad = 16.0
	_zoom.fit(_canvas, r)


func to_canvas(p: Vector2) -> Vector2:
	return _zoom.to_canvas(p)


func to_region(c: Vector2) -> Vector2:
	return _zoom.to_region(c)


## ＋ / － buttons and the wheel (also used by the selftest).
func zoom_in(factor := 1.5) -> void:
	if _canvas:
		_zoom.zoom_by(factor, _canvas)


## A click on the trigger picture (also used by the selftest).
func canvas_click(c: Vector2) -> void:
	if not doc.has("trigger") or _canvas == null:
		return
	_fit()
	if place:
		place = false
		_set_status("")
		set_trigger_pos(to_region(c))


func _canvas_input(ev: InputEvent) -> void:
	if _zoom.handle(ev, _canvas):
		_canvas.accept_event()
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			if not place:
				place = true  # a click without pressing the button first also places
			canvas_click(ev.position)
			_drag = true
		else:
			if _drag:
				_commit(true)
			_drag = false
		_canvas.accept_event()
	elif ev is InputEventMouseMotion and _drag and doc.has("trigger"):
		var p := to_region(ev.position)
		doc["trigger"]["pos"] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]
		_canvas.queue_redraw()


func _draw_canvas() -> void:
	if not doc.has("trigger") or _canvas == null:
		return
	_fit()
	var f := get_theme_default_font()
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(0.12, 0.13, 0.15))
	var rid := str(doc["trigger"].get("region", ""))
	var r := MapDB.region_rect(rid)
	var area := Rect2(to_canvas(r.position), r.size * _zoom.scale)
	if MapDB.mappable(rid):
		_canvas.draw_texture_rect(MapDB.terrain_texture(rid), area, false)
	else:
		_canvas.draw_rect(area, Color(0.3, 0.3, 0.32))
	_canvas.draw_rect(area, Color(0.9, 0.8, 0.55), false, 2.0)
	var reg: Dictionary = RegionDB.all().get(rid, {})
	for ex: Dictionary in reg.get("exits", []):
		var c := to_canvas(TerrainField._v2(ex["pos"], Vector2.ZERO))
		_canvas.draw_circle(c, 3.0, Color(1, 1, 1, 0.5))
		_canvas.draw_string(f, c + Vector2(5, -3), str(ex.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))
	for ct: Dictionary in reg.get("cities", []):
		var cc := to_canvas(TerrainField._v2(ct["center"], Vector2.ZERO))
		_canvas.draw_arc(cc, 7.0, 0, TAU, 20, Color(0.95, 0.82, 0.45, 0.7), 2.0)
		_canvas.draw_string(f, cc + Vector2(9, 4), str(ct.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.82, 0.45, 0.8))
	for cp: Dictionary in reg.get("checkpoints", []):
		var c2 := to_canvas(TerrainField._v2(cp["pos"], Vector2.ZERO))
		_canvas.draw_colored_polygon(PackedVector2Array([c2 + Vector2(0, -5), c2 + Vector2(4, 3), c2 + Vector2(-4, 3)]), Color(0.45, 0.9, 0.85, 0.6))
		_canvas.draw_string(f, c2 + Vector2(6, 4), str(cp.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.9, 0.85, 0.75))
	var p := to_canvas(TerrainField._v2(doc["trigger"].get("pos", null), Vector2.ZERO))
	var rad := float(doc["trigger"].get("radius", 5)) * _zoom.scale
	_canvas.draw_circle(p, maxf(rad, 2.0), Color(1.0, 0.45, 0.3, 0.35))
	_canvas.draw_arc(p, maxf(rad, 2.0), 0, TAU, 32, Color(1.0, 0.45, 0.3), 2.0)
	_canvas.draw_line(p - Vector2(6, 0), p + Vector2(6, 0), Color(1, 1, 1), 1.5)
	_canvas.draw_line(p - Vector2(0, 6), p + Vector2(0, 6), Color(1, 1, 1), 1.5)
	_canvas.draw_string(f, Vector2(8, _canvas.size.y - 8), "%s — 클릭 = 시작 자리" % RegionDB.region_name(rid), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.82, 0.86))
	if place:
		_canvas.draw_string(f, Vector2(8, 18), "클릭해서 자리 정하기", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.9, 0.5))


func _objectives_section() -> void:
	_heading(_inspector, "목표 (모두 채우면 '목표 달성' — 보고하면 완료)")
	var objs: Array = doc.get("objectives", [])
	var monsters := MonsterDB.all().keys()
	monsters.sort()
	var flags := QuestDB.known_flags()
	for i in objs.size():
		var o: Dictionary = objs[i]
		var idx := i
		var box := PanelContainer.new()
		_inspector.add_child(box)
		var v := VBoxContainer.new()
		box.add_child(v)
		var head := HBoxContainer.new()
		v.add_child(head)
		_label(head, "%d. %s" % [i + 1, QuestDB.OBJECTIVE_TYPES.get(o.get("type", ""), o.get("type", "?"))])
		_btn(head, "↑", func() -> void: move_objective(idx, -1))
		_btn(head, "↓", func() -> void: move_objective(idx, 1))
		_btn(head, "×", func() -> void: remove_objective(idx), "이 목표 지우기")
		var r1 := HBoxContainer.new()
		v.add_child(r1)
		_label(r1, "ID (대화 액션 '퀘스트 목표 진행'이 가리킴)")
		_line(r1, str(o.get("id", "")), func(s: String) -> void: set_objective_field(idx, "id", s.strip_edges()))
		var r2 := HBoxContainer.new()
		v.add_child(r2)
		_label(r2, "종류")
		var topts := []
		for k: String in QuestDB.OBJECTIVE_TYPES:
			topts.append([k, QuestDB.OBJECTIVE_TYPES[k]])
		_opt(r2, topts, str(o.get("type", "")), func(t: String) -> void: set_objective_type(idx, t))
		match str(o.get("type", "")):
			"collect":
				var r3 := HBoxContainer.new()
				v.add_child(r3)
				_label(r3, "아이템")
				_opt(r3, _item_options(), str(o.get("item", "")), func(s: String) -> void: set_objective_field(idx, "item", s))
				_label(r3, "개수")
				_spin(r3, float(o.get("count", 1)), 1, 999, 1, func(n: float) -> void: set_objective_field(idx, "count", int(n)))
				_label(v, "가방에 든 개수를 그대로 센다. 위 '완료할 때 모은 아이템을 넘김'이 켜져 있으면 보고할 때 가져간다.", true)
			"kill":
				var r3 := HBoxContainer.new()
				v.add_child(r3)
				_label(r3, "몬스터 (ID 앞부분 — 'meadow'는 meadow_* 전부)")
				var te := _line(r3, str(o.get("target", "")), func(s: String) -> void: set_objective_field(idx, "target", s.strip_edges()))
				var mopts := [["", "고르기…"]]
				for m: String in monsters:
					mopts.append([m, "%s (%s)" % [MonsterDB.info(m).get("name", m), m]])
				_opt(r3, mopts, "", func(s: String) -> void:
					if s != "":
						te.text = s
						set_objective_field(idx, "target", s))
				_label(r3, "마리")
				_spin(r3, float(o.get("count", 1)), 1, 999, 1, func(n: float) -> void: set_objective_field(idx, "count", int(n)))
			"flag":
				var r3 := HBoxContainer.new()
				v.add_child(r3)
				_label(r3, "플래그 (이 이름표가 켜지면 달성)")
				r3.add_child(EditorWidgets.flag_picker(str(o.get("flag", "")), func(s: String) -> void: set_objective_field(idx, "flag", s), "flag"))
				_label(v, "켜는 곳: 컷씬 단계 '플래그 설정', 대화 액션 '플래그 설정', 지역의 이야기 장소(밟으면), 게임 코드. 위 '플래그 목록' 버튼에서 전부 볼 수 있음.", true)
			_:
				var r3 := HBoxContainer.new()
				v.add_child(r3)
				_label(r3, "횟수")
				_spin(r3, float(o.get("count", 1)), 1, 999, 1, func(n: float) -> void: set_objective_field(idx, "count", int(n)))
				_label(v, "대화 액션 '퀘스트 목표 진행'(이 목표 ID)이나 컷씬·코드가 올린다.", true)
		var r4 := HBoxContainer.new()
		v.add_child(r4)
		_label(r4, "표시 글자 (퀘스트 기록·추적)")
		_line(r4, str(o.get("text", "")), func(s: String) -> void: set_objective_field(idx, "text", s))
	var add := HBoxContainer.new()
	_inspector.add_child(add)
	var al := Label.new()
	al.text = "+ 목표:"
	add.add_child(al)
	for k: String in QuestDB.OBJECTIVE_TYPES:
		var kk := k
		_btn(add, QuestDB.OBJECTIVE_TYPES[k], func() -> void: add_objective(kk))


func _rewards_editor(parent: Control, outcome: String) -> void:
	var r := rewards(outcome)
	if r.is_empty():
		return
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, "일반 EXP")
	_spin(row, float(r.get("gen_exp", 0)), 0, 99999, 1, func(v: float) -> void: set_reward(outcome, "gen_exp", int(v)))
	_label(row, "생활 EXP")
	_spin(row, float(r.get("life_exp", 0)), 0, 99999, 1, func(v: float) -> void: set_reward(outcome, "life_exp", int(v)))
	_label(row, "골드")
	_spin(row, float(r.get("gold", 0)), 0, 999999, 1, func(v: float) -> void: set_reward(outcome, "gold", int(v)))
	var items: Dictionary = r.get("items", {})
	var iopts := _item_options()
	for k: String in items:
		var key := k
		var ir := HBoxContainer.new()
		parent.add_child(ir)
		_opt(ir, iopts, key, func(s: String) -> void: set_reward_item(outcome, s, int(rewards(outcome)["items"].get(key, 1)), key))
		_label(ir, "×")
		_spin(ir, float(items[k]), 1, 999, 1, func(v: float) -> void: set_reward_item(outcome, key, int(v)))
		_btn(ir, "×", func() -> void: set_reward_item(outcome, key, 0), "이 보상 아이템 지우기")
	var recipes: Array = r.get("recipes", [])
	var ropts := []
	for rid: String in RecipeDB.all():
		ropts.append([rid, "%s (%s)" % [RecipeDB.recipe_name(rid), rid]])
	for i in recipes.size():
		var ri := i
		var rr := HBoxContainer.new()
		parent.add_child(rr)
		_label(rr, "레시피")
		_opt(rr, ropts, str(recipes[i]), func(s: String) -> void:
			var l: Array = rewards(outcome).get("recipes", []).duplicate()
			l[ri] = s
			set_reward_recipes(outcome, l))
		_btn(rr, "×", func() -> void:
			var l: Array = rewards(outcome).get("recipes", []).duplicate()
			l.remove_at(ri)
			set_reward_recipes(outcome, l), "이 레시피 보상 지우기")
	var add := HBoxContainer.new()
	parent.add_child(add)
	_btn(add, "+ 아이템", func() -> void: add_reward_item(outcome))
	_btn(add, "+ 레시피", func() -> void:
		if ropts.is_empty():
			return
		var l: Array = rewards(outcome).get("recipes", []).duplicate()
		l.append(str(ropts[0][0]))
		set_reward_recipes(outcome, l))
	_label(parent, "주는 것: %s" % QuestDB.reward_text(r), true)


func _outcomes_section() -> void:
	_heading(_inspector, "결과 분기 (선택) — 대화 액션 '퀘스트 완료(보상)'의 '결과'로 고른 보상을 줌")
	var oc: Dictionary = doc.get("outcomes", {})
	for k: String in oc:
		var key := k
		var box := PanelContainer.new()
		_inspector.add_child(box)
		var v := VBoxContainer.new()
		box.add_child(v)
		var head := HBoxContainer.new()
		v.add_child(head)
		_label(head, "결과 키")
		_line(head, key, func(s: String) -> void: rename_outcome(key, s))
		_label(head, "이름 (기록에 보임)")
		_line(head, str(oc[k].get("label", "")), func(s: String) -> void: set_outcome_label(key, s))
		_btn(head, "×", func() -> void: remove_outcome(key), "이 결과 지우기")
		_rewards_editor(v, key)
	if oc.is_empty():
		_label(_inspector, "없음 — 결과를 비우면 위의 기본 보상을 준다. 예: 짐을 돌려주고 사례를 받거나 거절하는 두 갈래.", true)
	_btn(_inspector, "+ 결과", func() -> void: add_outcome())


# ---------------------------------------------------------------- validation / status

func validate(show := false) -> Array:
	issues = QuestDB.validate(doc, refs) if not doc.is_empty() else []
	_issue_list.clear()
	for it: Dictionary in issues:
		_issue_list.add_item("%s %s" % ["⛔" if it["severity"] == "error" else "⚠", it["message"]])
	if issues.is_empty():
		_issue_list.add_item("✔ 문제 없음")
	_ref_list.clear()
	for r: Dictionary in refs:
		var i := _ref_list.add_item("%s %s · %s — %s" % ["대화" if r["kind"] == "dialogue" else "컷씬", r["id"], r["node"], r["what"]])
		_ref_list.set_item_metadata(i, r)
	if refs.is_empty() and not doc.is_empty():
		_ref_list.add_item("(대화·컷씬에서 쓰는 곳 없음)")
	if show:
		_set_status("검증: 오류 %d, 경고 %d" % [issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "error").size(),
			issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "warning").size()])
	return issues


func scroll_to_end() -> void:
	_scroll.scroll_vertical = int(_inspector.size.y)


func _set_status(text: String) -> void:
	_status.text = text


func _update_status() -> void:
	if doc.is_empty():
		_set_status("퀘스트를 고르세요")
		return
	_set_status("%s%s — 목표 %d개 · 쓰이는 곳 %d · %s" % ["● " if dirty else "", str(doc.get("title", "")), doc["objectives"].size(),
		refs.size(), "저장하지 않은 변경 있음" if dirty else "저장됨"])
