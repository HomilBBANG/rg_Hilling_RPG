@tool
class_name MonsterAIEditorPanel
extends Control
## The dialogue editor's 몬스터 AI tab: edit monster decision graphs (data/ai/*.json, MonsterAI)
## as nodes — 시작 → 조건 (예 / 아니오) → 싸움 시작 → 행동 — and pick which graph (and 선공 flag)
## each monster in data/monsters.json uses. The node kinds and their settings come from
## MonsterAI.CHECKS / ACTIONS, the same lists the game's SlimeMonster runs.
## 시뮬레이션: answer each condition 예 / 아니오 and see which path is taken and what the monster does.

signal saved(path: String)

const TYPE_COLORS := {"start": Color(0.45, 0.7, 0.45), "condition": Color(0.85, 0.65, 0.3),
	"engage": Color(0.85, 0.4, 0.4), "action": Color(0.4, 0.58, 0.88)}
const UNDO_LIMIT := 200
const COL_W := 290.0
const ROW_H := 165.0
const ORIGIN := Vector2(30, 70)  ## arrange() leaves room for GraphEdit's own toolbar

var doc := {}
var ai_id := ""
var dirty := false
var issues: Array = []
var selected := ""
var sim_answers := {}  ## condition kind -> bool (시뮬레이션)
var sim_result := {}

var _undo: Array[String] = []
var _redo: Array[String] = []
var _snap := ""
var _views := {}  # node id -> GraphNode

var _list: ItemList
var _monsters: ItemList
var _mon_ai: OptionButton
var _mon_aggr: CheckBox
var _mon_info: Label
var _graph: GraphEdit
var _inspector: VBoxContainer
var _status: Label
var _issue_list: ItemList
var _sim_box: GridContainer
var _sim_label: Label
var _new_dialog: ConfirmationDialog
var _new_id: LineEdit
var _new_from: OptionButton


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()
	refresh_list()
	refresh_monsters()
	var all := MonsterAI.ids()
	if not all.is_empty():
		open_ai("ai.slime.passive" if all.has("ai.slime.passive") else str(all[0]))


# ---------------------------------------------------------------- UI construction

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
	_btn(bar, "새 AI", _ask_new, "새 AI 그래프 만들기 (data/ai) — 기존 것을 복사해서 시작할 수 있음")
	_btn(bar, "저장", func() -> void: save(), "Ctrl+S")
	_btn(bar, "파일에서 다시 읽기", revert, "저장하지 않은 변경 버리기")
	_btn(bar, "↶", undo, "실행 취소 (Ctrl+Z)")
	_btn(bar, "↷", redo, "다시 실행 (Ctrl+Y / Ctrl+Shift+Z)")
	bar.add_child(VSeparator.new())
	var add_label := Label.new()
	add_label.text = "노드 추가:"
	bar.add_child(add_label)
	for t: String in ["condition", "engage", "action"]:
		var tt := t
		var b := _btn(bar, MonsterAI.TYPE_NAMES[t], func() -> void: add_node(tt), "선택한 노드의 빈 출력에 이어 붙임")
		b.add_theme_color_override("font_color", (TYPE_COLORS[t] as Color).lightened(0.45))
	_btn(bar, "선택 삭제", func() -> void: delete_nodes(_selected_ids()), "Delete 키로도 지움 (시작 노드는 못 지움)")
	bar.add_child(VSeparator.new())
	_btn(bar, "정렬", arrange, "시작에서부터 단계별로 자동 배치")
	_btn(bar, "검증", func() -> void: validate(true), "연결 없는 출력·고리·닿지 않는 노드 검사")
	_status = Label.new()
	_status.clip_text = true
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_status)

	var hs := HSplitContainer.new()
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(hs)
	# left: graphs + monsters
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	hs.add_child(left)
	_heading(left, "AI 그래프 (data/ai)")
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: open_ai(str(_list.get_item_metadata(i))))
	left.add_child(_list)
	_heading(left, "몬스터별 AI (data/monsters.json)")
	_monsters = ItemList.new()
	_monsters.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_monsters.item_selected.connect(func(_i: int) -> void: _show_monster())
	left.add_child(_monsters)
	_mon_info = Label.new()
	_mon_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_mon_info)
	_mon_ai = OptionButton.new()
	_mon_ai.tooltip_text = "이 몬스터가 쓸 AI 그래프"
	left.add_child(_mon_ai)
	_mon_aggr = CheckBox.new()
	_mon_aggr.text = "선공 (먼저 덤빔)"
	_mon_aggr.tooltip_text = "AI를 '선공 여부로 기본'에 두면 이 값으로 ai.slime.aggressive / ai.slime.passive 중 하나를 씀"
	left.add_child(_mon_aggr)
	_btn(left, "이 몬스터에 적용", _apply_monster, "data/monsters.json의 이 몬스터 항목만 고침")

	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.add_child(right_split)
	var vs := VSplitContainer.new()
	vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(vs)
	_graph = GraphEdit.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.custom_minimum_size = Vector2(400, 300)
	_graph.right_disconnects = true
	_graph.connection_request.connect(_on_connection_request)
	_graph.disconnection_request.connect(_on_disconnection_request)
	_graph.delete_nodes_request.connect(func(names: Array) -> void: delete_nodes(PackedStringArray(names.map(func(n: StringName) -> String: return String(n)))))
	_graph.node_selected.connect(func(_n: Node) -> void: _update_selection.call_deferred())
	_graph.node_deselected.connect(func(_n: Node) -> void: _update_selection.call_deferred())
	_graph.end_node_move.connect(_on_end_move)
	vs.add_child(_graph)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.y = 220
	vs.add_child(tabs)
	var sim := VBoxContainer.new()
	sim.name = "시뮬레이션"
	tabs.add_child(sim)
	var sim_help := Label.new()
	sim_help.text = "조건마다 예/아니오를 골라 보면, 그래프가 지나가는 길(노드가 밝아짐)과 고르는 행동이 바로 보입니다."
	sim_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sim.add_child(sim_help)
	_sim_box = GridContainer.new()
	_sim_box.columns = 3
	sim.add_child(_sim_box)
	for kind: String in MonsterAI.CHECKS:
		var k := kind
		var cb := CheckBox.new()
		cb.name = "sim_" + kind
		cb.text = str(MonsterAI.CHECKS[kind]["label"])
		cb.tooltip_text = str(MonsterAI.CHECKS[kind]["help"])
		cb.toggled.connect(func(on: bool) -> void: set_sim(k, on))
		_sim_box.add_child(cb)
	_sim_label = Label.new()
	_sim_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sim_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75))
	sim.add_child(_sim_label)
	_issue_list = ItemList.new()
	_issue_list.name = "검증"
	_issue_list.item_selected.connect(func(i: int) -> void:
		var id := str(_issue_list.get_item_metadata(i))
		if id != "":
			select_node(id))
	tabs.add_child(_issue_list)
	# right: inspector
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 330
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_split.add_child(scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inspector)

	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "새 AI 그래프"
	var nb := VBoxContainer.new()
	_new_dialog.add_child(nb)
	var l1 := Label.new()
	l1.text = "ID (파일 이름, 예: ai.goblin.coward)"
	nb.add_child(l1)
	_new_id = LineEdit.new()
	_new_id.custom_minimum_size.x = 320
	nb.add_child(_new_id)
	var l2 := Label.new()
	l2.text = "복사해서 시작할 그래프"
	nb.add_child(l2)
	_new_from = OptionButton.new()
	nb.add_child(_new_from)
	_new_dialog.confirmed.connect(func() -> void:
		var from := "" if _new_from.selected <= 0 else _new_from.get_item_text(_new_from.selected)
		create_ai(_new_id.text.strip_edges(), from))
	add_child(_new_dialog)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if not k.is_command_or_control_pressed():
		return
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is TextEdit or focus is LineEdit or focus is SpinBox
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
	_list.clear()
	for id: String in MonsterAI.ids():
		var g := MonsterAI.load_graph(id)
		var i := _list.add_item("%s%s\n  %s" % ["● " if id == ai_id and dirty else "", id, g.get("title", "")])
		_list.set_item_metadata(i, id)
		if id == ai_id:
			_list.select(i)


func open_ai(id: String) -> bool:
	if dirty and id != ai_id:
		_set_status("저장하지 않은 변경이 있습니다 — 저장하거나 '파일에서 다시 읽기' 후 다른 그래프를 여세요")
		refresh_list()
		return false
	MonsterAI.clear_cache()
	var g := MonsterAI.load_graph(id)
	if g.is_empty():
		_set_status("'%s'를 읽지 못했습니다" % id)
		return false
	doc = g.duplicate(true)
	_normalize()
	ai_id = id
	dirty = false
	selected = ""
	_undo.clear()
	_redo.clear()
	if doc["editor_positions"].is_empty():
		arrange(false)
	_snap = JSON.stringify(doc)
	_rebuild_graph()
	refresh_list()
	_show_inspector()
	validate(false)
	_update_status()
	return true


func _normalize() -> void:
	doc["version"] = 1
	doc["ai_id"] = str(doc.get("ai_id", ai_id))
	doc["start_node_id"] = str(doc.get("start_node_id", "start"))
	for key in ["nodes", "connections"]:
		if not doc.get(key) is Array:
			doc[key] = []
	if not doc.get("editor_positions") is Dictionary:
		doc["editor_positions"] = {}


func save() -> bool:
	if ai_id == "" or doc.is_empty():
		return false
	validate(false)
	doc["ai_id"] = ai_id
	var err := MonsterAI.save_graph(doc, ai_id)
	if err != OK:
		_set_status("저장 실패: %s" % error_string(err))
		return false
	dirty = false
	refresh_list()
	var bad := issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "error").size()
	_set_status("저장함: %s%s" % [MonsterAI.path_for(ai_id), "  — ⚠ 오류 %d개: 게임은 이 그래프 대신 기본 규칙으로 움직입니다" % bad if bad > 0 else ""])
	saved.emit(MonsterAI.path_for(ai_id))
	return true


func revert() -> void:
	dirty = false
	var id := ai_id
	ai_id = ""
	open_ai(id)


func _ask_new() -> void:
	_new_from.clear()
	_new_from.add_item("(빈 그래프)")
	for id: String in MonsterAI.ids():
		_new_from.add_item(id)
		if id == ai_id:
			_new_from.select(_new_from.item_count - 1)
	_new_id.text = "ai.new_monster"
	_new_dialog.popup_centered()


## New graph file, empty (start → wander) or copied from from_id. Returns false when the id is taken.
func create_ai(id: String, from_id := "") -> bool:
	if id == "" or not id.is_valid_filename() or MonsterAI.ids().has(id):
		_set_status("쓸 수 없는 ID이거나 이미 있습니다: '%s'" % id)
		return false
	if dirty:
		_set_status("저장하지 않은 변경이 있습니다 — 먼저 저장하세요")
		return false
	var g := {}
	if from_id != "":
		g = MonsterAI.load_graph(from_id).duplicate(true)
		g["title"] = "%s (복사)" % g.get("title", from_id)
	else:
		g = {"version": 1, "title": "새 몬스터 AI", "notes": "", "start_node_id": "start",
			"nodes": [{"id": "start", "type": "start"}, {"id": "a_wander", "type": "action", "action": "wander", "params": {}}],
			"connections": [{"from": "start", "port": "next", "to": "a_wander"}], "editor_positions": {}}
	g["ai_id"] = id
	if MonsterAI.save_graph(g, id) != OK:
		return false
	open_ai(id)
	_set_status("새 AI '%s'를 만들었습니다%s" % [id, " ('%s' 복사)" % from_id if from_id != "" else ""])
	refresh_monsters()
	return true


# ---------------------------------------------------------------- monsters

func refresh_monsters() -> void:
	MonsterDB.reload()
	var keep := _monster_kind()
	_monsters.clear()
	var all := MonsterDB.all()
	for kind: String in all:
		var def: Dictionary = all[kind]
		var custom := str(def.get("ai", ""))
		var i := _monsters.add_item("%s  %s · %s" % [def.get("name", kind), "선공" if def.get("aggressive", false) else "비선공",
			"보스 전용 스크립트" if kind == "dragon" else (custom if custom != "" else "기본(%s)" % MonsterAI.ai_for(kind))])
		_monsters.set_item_metadata(i, kind)
		if kind == keep:
			_monsters.select(i)
	_show_monster()


func _monster_kind() -> String:
	var sel := _monsters.get_selected_items() if _monsters else PackedInt32Array()
	return str(_monsters.get_item_metadata(sel[0])) if sel.size() > 0 else ""


func select_monster(kind: String) -> void:
	for i in _monsters.item_count:
		if str(_monsters.get_item_metadata(i)) == kind:
			_monsters.select(i)
	_show_monster()


func _show_monster() -> void:
	var kind := _monster_kind()
	_mon_ai.clear()
	_mon_ai.add_item("(선공 여부로 기본)")
	for id: String in MonsterAI.ids():
		_mon_ai.add_item(id)
	_mon_ai.disabled = kind == ""
	_mon_aggr.disabled = kind == ""
	if kind == "":
		_mon_info.text = "몬스터를 고르면 쓸 AI와 선공 여부를 바꿀 수 있습니다."
		return
	var def := MonsterDB.info(kind)
	var custom := str(def.get("ai", ""))
	for i in _mon_ai.item_count:
		if _mon_ai.get_item_text(i) == custom:
			_mon_ai.select(i)
	if custom == "":
		_mon_ai.select(0)
	_mon_aggr.button_pressed = bool(def.get("aggressive", false))
	_mon_info.text = "%s (%s) — 지금 쓰는 AI: %s" % [def.get("name", kind), kind, MonsterAI.ai_for(kind)]
	if kind == "dragon":
		_mon_info.text += "\n※ 드래곤은 보스 전용 스크립트로 움직여 이 설정을 쓰지 않습니다."


func _apply_monster() -> void:
	var kind := _monster_kind()
	if kind == "":
		return
	assign_monster(kind, "" if _mon_ai.selected <= 0 else _mon_ai.get_item_text(_mon_ai.selected), _mon_aggr.button_pressed)


## Writes the monster's "ai" ("" = by 선공 flag) and 선공 flag into data/monsters.json.
func assign_monster(kind: String, id: String, aggressive: bool) -> bool:
	var err := MonsterAI.set_monster_ai(kind, id, aggressive)
	if err != OK:
		_set_status("monsters.json에 쓰지 못했습니다 (%s)" % error_string(err))
		return false
	refresh_monsters()
	select_monster(kind)
	_set_status("%s: AI %s, %s — data/monsters.json에 저장" % [MonsterDB.info(kind).get("name", kind), MonsterAI.ai_for(kind), "선공" if aggressive else "비선공"])
	return true


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
	_changed()


func _changed() -> void:
	if not dirty:
		dirty = true
		refresh_list()
	validate(false)
	_update_status()


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
	if MonsterAI.node(doc, selected).is_empty():
		selected = ""
	_rebuild_graph()
	_show_inspector()
	_changed()


func _new_id_for(prefix: String) -> String:
	var i := 1
	while not MonsterAI.node(doc, "%s_%d" % [prefix, i]).is_empty():
		i += 1
	return "%s_%d" % [prefix, i]


## Adds a node; with one node selected it hangs it on that node's first free output.
func add_node(type: String, kind := "") -> String:
	if doc.is_empty():
		return ""
	var n := {"type": type, "params": {}}
	match type:
		"condition":
			n["check"] = kind if kind != "" else "player_near"
			n["id"] = _new_id_for("c")
		"action":
			n["action"] = kind if kind != "" else "wander"
			n["id"] = _new_id_for("a")
		"engage":
			n["id"] = _new_id_for("e")
		_:
			return ""
	var pos := (_graph.scroll_offset + _graph.size * 0.4) / _graph.zoom
	var from := MonsterAI.node(doc, selected)
	if not from.is_empty():
		var p: Variant = doc["editor_positions"].get(selected, [0, 0])
		pos = Vector2(float(p[0]) + COL_W, float(p[1]))
		for port: String in MonsterAI.ports_of(from):
			if MonsterAI.next_of(doc, selected, port) == "":
				doc["connections"].append({"from": selected, "port": port, "to": n["id"]})
				pos.y += 0.0 if port != "false" else ROW_H
				break
	doc["nodes"].append(n)
	doc["editor_positions"][n["id"]] = [roundi(pos.x), roundi(pos.y)]
	_commit()
	_rebuild_graph()
	select_node(n["id"])
	return n["id"]


func delete_nodes(ids: PackedStringArray) -> void:
	var gone := PackedStringArray()
	for id in ids:
		var n := MonsterAI.node(doc, id)
		if n.is_empty() or n.get("type", "") == "start":
			continue
		doc["nodes"].erase(n)
		doc["editor_positions"].erase(id)
		gone.append(id)
	if gone.is_empty():
		return
	var conns: Array = doc["connections"]
	for i in range(conns.size() - 1, -1, -1):
		if gone.has(str(conns[i]["from"])) or gone.has(str(conns[i]["to"])):
			conns.remove_at(i)
	if gone.has(selected):
		selected = ""
	_commit()
	_rebuild_graph()
	_show_inspector()


func connect_nodes(from: String, port: String, to: String) -> void:
	if from == to or MonsterAI.node(doc, to).get("type", "") == "start":
		return
	var conns: Array = doc["connections"]
	for i in range(conns.size() - 1, -1, -1):
		if conns[i]["from"] == from and conns[i]["port"] == port:
			conns.remove_at(i)  # one target per output
	conns.append({"from": from, "port": port, "to": to})
	_commit()
	_rebuild_graph()


func disconnect_port(from: String, port: String) -> void:
	var conns: Array = doc["connections"]
	for i in range(conns.size() - 1, -1, -1):
		if conns[i]["from"] == from and conns[i]["port"] == port:
			conns.remove_at(i)
	_commit()
	_rebuild_graph()


## Changes a node's condition / action kind (keeps settings with the same name).
func set_kind(id: String, kind: String) -> void:
	var n := MonsterAI.node(doc, id)
	var key := "check" if n.get("type", "") == "condition" else "action"
	if n.is_empty() or n.get("type", "") not in ["condition", "action"] or n.get(key, "") == kind:
		return
	n[key] = kind
	var spec: Array = (MonsterAI.CHECKS if key == "check" else MonsterAI.ACTIONS).get(kind, {}).get("params", [])
	var keep := {}
	for p: Dictionary in spec:
		if n["params"].has(p["name"]):
			keep[p["name"]] = n["params"][p["name"]]
	n["params"] = keep
	_commit()
	_refresh_view(id)
	_show_inspector()


func set_param(id: String, key: String, value: float) -> void:
	var n := MonsterAI.node(doc, id)
	if n.is_empty():
		return
	if not n.get("params") is Dictionary:
		n["params"] = {}
	n["params"][key] = value
	_commit()
	_refresh_view(id)


func rename_node(id: String, new_id: String) -> bool:
	new_id = new_id.strip_edges()
	var n := MonsterAI.node(doc, id)
	if n.is_empty() or new_id == "" or new_id == id or not MonsterAI.node(doc, new_id).is_empty():
		return false
	n["id"] = new_id
	for c: Dictionary in doc["connections"]:
		if c["from"] == id:
			c["from"] = new_id
		if c["to"] == id:
			c["to"] = new_id
	if doc["start_node_id"] == id:
		doc["start_node_id"] = new_id
	doc["editor_positions"][new_id] = doc["editor_positions"].get(id, [0, 0])
	doc["editor_positions"].erase(id)
	selected = new_id
	_commit()
	_rebuild_graph()
	_show_inspector()
	return true


## Layered layout from the start node (each step one column, branches stacked).
func arrange(commit := true) -> void:
	var depth := {}
	var order: Array[String] = []
	var queue: Array = [[str(doc.get("start_node_id", "start")), 0]]
	while not queue.is_empty():
		var it: Array = queue.pop_front()
		var id: String = it[0]
		if depth.has(id) or MonsterAI.node(doc, id).is_empty():
			continue
		depth[id] = it[1]
		order.append(id)
		for port: String in MonsterAI.ports_of(MonsterAI.node(doc, id)):
			var to := MonsterAI.next_of(doc, id, port)
			if to != "":
				queue.append([to, int(it[1]) + 1])
	var rows := {}
	var max_d := 0
	for id in order:
		var d: int = depth[id]
		max_d = maxi(max_d, d)
		var r: int = rows.get(d, 0)
		rows[d] = r + 1
		doc["editor_positions"][id] = [roundi(ORIGIN.x + d * COL_W), roundi(ORIGIN.y + r * ROW_H)]
	var extra := 0
	for n: Dictionary in doc["nodes"]:
		if not depth.has(n["id"]):  # unreachable ones in a column of their own
			doc["editor_positions"][n["id"]] = [roundi(ORIGIN.x + (max_d + 1) * COL_W), roundi(ORIGIN.y + extra * ROW_H)]
			extra += 1
	if commit:
		_commit()
		_rebuild_graph()


func set_title(text: String) -> void:
	doc["title"] = text
	_commit()


func set_notes(text: String) -> void:
	doc["notes"] = text
	_commit()


# ---------------------------------------------------------------- graph view

func _rebuild_graph() -> void:
	_graph.clear_connections()
	for c in _graph.get_children():
		if c is GraphNode:
			_graph.remove_child(c)
			c.queue_free()
	_views.clear()
	if doc.is_empty():
		return
	for n: Dictionary in doc["nodes"]:
		var g := _make_gnode(n)
		_graph.add_child(g)
		g.selected = str(n["id"]) == selected
	for c: Dictionary in doc["connections"]:
		var from := MonsterAI.node(doc, str(c["from"]))
		var idx := MonsterAI.ports_of(from).find(str(c["port"]))
		if idx >= 0 and _views.has(str(c["to"])):
			_graph.connect_node(StringName(c["from"]), idx, StringName(c["to"]), 0)
	run_sim()


func _make_gnode(n: Dictionary) -> GraphNode:
	var id := str(n["id"])
	var t := str(n.get("type", ""))
	var g := GraphNode.new()
	g.name = id
	g.position_offset = Vector2(40, 40)
	var p: Variant = doc["editor_positions"].get(id, null)
	if p is Array and (p as Array).size() >= 2:
		g.position_offset = Vector2(float(p[0]), float(p[1]))
	g.custom_minimum_size = Vector2(230, 0)
	var col: Color = TYPE_COLORS.get(t, Color.GRAY)
	for key in ["titlebar", "titlebar_selected"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col if key == "titlebar" else col.lightened(0.18)
		sb.set_corner_radius_all(4)
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.set_content_margin_all(6)
		g.add_theme_stylebox_override(key, sb)
	var summary := Label.new()
	summary.name = "summary"
	summary.custom_minimum_size.x = 230
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = MonsterAI.node_text(n)
	g.add_child(summary)
	var port_col := col.lightened(0.35)
	match t:
		"condition":
			g.set_slot(0, true, 0, Color(0.85, 0.85, 0.85), false, 0, port_col)
			for s in ["예 ▸", "아니오 ▸"]:
				var l := Label.new()
				l.text = s
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				g.add_child(l)
				g.set_slot(g.get_child_count() - 1, false, 0, Color.WHITE, true, 0, Color(0.5, 0.9, 0.5) if s.begins_with("예") else Color(0.95, 0.5, 0.45))
		"action":
			g.set_slot(0, true, 0, Color(0.85, 0.85, 0.85), false, 0, port_col)
		_:
			g.set_slot(0, t != "start", 0, Color(0.85, 0.85, 0.85), true, 0, port_col)
	_views[id] = g
	return g


func _refresh_view(id: String) -> void:
	if _views.has(id):
		var l := (_views[id] as GraphNode).get_node_or_null("summary") as Label
		if l:
			l.text = MonsterAI.node_text(MonsterAI.node(doc, id))
	run_sim()


func _apply_marks() -> void:
	var by_node := {}
	for it: Dictionary in issues:
		if it["node"] != "":
			by_node[it["node"]] = by_node.get(it["node"], PackedStringArray()) + PackedStringArray([it["message"]])
	var path: Array = sim_result.get("path", [])
	for id: String in _views:
		var g: GraphNode = _views[id]
		var t := str(MonsterAI.node(doc, id).get("type", ""))
		var bad: bool = by_node.has(id)
		g.title = "%s%s · %s" % ["⚠ " if bad else "", MonsterAI.TYPE_NAMES.get(t, t), id]
		g.tooltip_text = "\n".join(by_node[id]) if bad else ""
		var on_path := path.has(id)
		g.self_modulate = Color(1.35, 1.3, 0.6) if on_path else (Color(1.15, 0.8, 0.8) if bad else (Color(0.65, 0.65, 0.65) if not path.is_empty() else Color.WHITE))


func _selected_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for c in _graph.get_children():
		if c is GraphNode and c.selected:
			out.append(String(c.name))
	return out


func select_node(id: String) -> void:
	for c in _graph.get_children():
		if c is GraphNode:
			c.selected = String(c.name) == id
	selected = id
	_show_inspector()


func _update_selection() -> void:
	var ids := _selected_ids()
	var s := ids[0] if ids.size() == 1 else ""
	if s != selected:
		selected = s
		_show_inspector()


func _on_end_move() -> void:
	for c in _graph.get_children():
		if c is GraphNode and c.selected:
			doc["editor_positions"][String(c.name)] = [roundi(c.position_offset.x), roundi(c.position_offset.y)]
	_commit()


func _on_connection_request(from: StringName, from_port: int, to: StringName, _to_port: int) -> void:
	var ports := MonsterAI.ports_of(MonsterAI.node(doc, String(from)))
	if from_port < ports.size():
		connect_nodes(String(from), ports[from_port], String(to))


func _on_disconnection_request(from: StringName, from_port: int, _to: StringName, _to_port: int) -> void:
	var ports := MonsterAI.ports_of(MonsterAI.node(doc, String(from)))
	if from_port < ports.size():
		disconnect_port(String(from), ports[from_port])


# ---------------------------------------------------------------- inspector

func _show_inspector() -> void:
	for c in _inspector.get_children():
		_inspector.remove_child(c)
		c.queue_free()
	if doc.is_empty():
		return
	var n := MonsterAI.node(doc, selected)
	if n.is_empty():
		_heading(_inspector, "그래프: %s" % ai_id)
		var lt := Label.new()
		lt.text = "이름"
		_inspector.add_child(lt)
		var title := LineEdit.new()
		title.text = str(doc.get("title", ""))
		title.text_submitted.connect(func(s: String) -> void: set_title(s))
		title.focus_exited.connect(func() -> void: set_title(title.text))
		_inspector.add_child(title)
		var ln := Label.new()
		ln.text = "설명"
		_inspector.add_child(ln)
		var notes := TextEdit.new()
		notes.custom_minimum_size.y = 120
		notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		notes.text = str(doc.get("notes", ""))
		notes.focus_exited.connect(func() -> void: set_notes(notes.text))
		_inspector.add_child(notes)
		var users := PackedStringArray()
		var all := MonsterDB.all()
		for kind: String in all:
			if MonsterAI.ai_for(kind) == ai_id and kind != "dragon":
				users.append(str(all[kind].get("name", kind)))
		var lu := Label.new()
		lu.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lu.text = "이 AI를 쓰는 몬스터: %s" % (", ".join(users) if not users.is_empty() else "없음")
		_inspector.add_child(lu)
		var hint := Label.new()
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		hint.text = "몬스터는 한 번 뛸 때마다 '시작'부터 길을 따라가 처음 닿는 '행동'을 합니다. 노드를 골라 설정을 바꾸고, 출력 점을 끌어 다른 노드에 이으세요 (오른쪽 클릭으로 끊기)."
		_inspector.add_child(hint)
		return
	var t := str(n.get("type", ""))
	var id := str(n["id"])
	_heading(_inspector, "%s 노드" % MonsterAI.TYPE_NAMES.get(t, t))
	var lid := Label.new()
	lid.text = "ID"
	_inspector.add_child(lid)
	var id_edit := LineEdit.new()
	id_edit.text = id
	id_edit.editable = t != "start"
	id_edit.text_submitted.connect(func(s: String) -> void: rename_node(id, s))
	_inspector.add_child(id_edit)
	var spec: Array = []
	match t:
		"condition", "action":
			var table: Dictionary = MonsterAI.CHECKS if t == "condition" else MonsterAI.ACTIONS
			var key := "check" if t == "condition" else "action"
			var opt := OptionButton.new()
			opt.name = "kind"
			var kinds := table.keys()
			for k: String in kinds:
				opt.add_item(str(table[k]["label"]))
				if k == n.get(key, ""):
					opt.select(opt.item_count - 1)
			opt.item_selected.connect(func(i: int) -> void: set_kind(id, str(kinds[i])))
			_inspector.add_child(opt)
			var info: Dictionary = table.get(n.get(key, ""), {})
			var help := Label.new()
			help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			help.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
			help.text = str(info.get("help", ""))
			_inspector.add_child(help)
			spec = info.get("params", [])
		"engage":
			var help2 := Label.new()
			help2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			help2.text = "여기를 지나면 싸우는 중이 됩니다 (조건 '싸우는 중인가' = 예). 처음 싸움을 시작할 때 근처 같은 종족을 부를 수 있습니다 — 부름을 받은 쪽도 자기 AI의 '같은 종족이 불렀는가'로 끼어들지 정합니다."
			_inspector.add_child(help2)
			spec = MonsterAI.ENGAGE_PARAMS
		"start":
			var help3 := Label.new()
			help3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			help3.text = "매번 여기서부터 결정을 시작합니다."
			_inspector.add_child(help3)
	for p: Dictionary in spec:
		var pname := str(p["name"])
		var lp := Label.new()
		lp.text = str(p["label"])
		_inspector.add_child(lp)
		var sb := SpinBox.new()
		sb.name = "param_" + pname
		sb.min_value = float(p["min"])
		sb.max_value = float(p["max"])
		sb.step = float(p["step"])
		sb.value = MonsterAI.param(n, pname)
		sb.value_changed.connect(func(v: float) -> void: set_param(id, pname, v))
		_inspector.add_child(sb)
	var outs := MonsterAI.ports_of(n)
	if not outs.is_empty():
		var lo := Label.new()
		lo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var parts := PackedStringArray()
		for port: String in outs:
			var to := MonsterAI.next_of(doc, id, port)
			parts.append("%s → %s" % [{"true": "예", "false": "아니오", "next": "다음"}[port], to if to != "" else "(연결 없음)"])
		lo.text = "\n".join(parts)
		_inspector.add_child(lo)
	if t != "start":
		_btn(_inspector, "이 노드 지우기", func() -> void: delete_nodes(PackedStringArray([id])))


# ---------------------------------------------------------------- validation + simulation

func validate(show := false) -> Array:
	issues = MonsterAI.validate(doc) if not doc.is_empty() else []
	_issue_list.clear()
	for it: Dictionary in issues:
		var i := _issue_list.add_item("%s %s%s" % ["⛔" if it["severity"] == "error" else "⚠", "[%s] " % it["node"] if it["node"] != "" else "", it["message"]])
		_issue_list.set_item_metadata(i, it["node"])
	if issues.is_empty():
		_issue_list.add_item("✔ 문제 없음")
	_apply_marks()
	if show:
		var tabs := _issue_list.get_parent() as TabContainer
		tabs.current_tab = _issue_list.get_index()
		_set_status("검증: 오류 %d, 경고 %d" % [issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "error").size(),
			issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "warning").size()])
	return issues


func set_sim(kind: String, on: bool) -> void:
	sim_answers[kind] = on
	var cb := _sim_box.get_node_or_null("sim_" + kind) as CheckBox
	if cb and cb.button_pressed != on:
		cb.set_pressed_no_signal(on)
	run_sim()


## Walks the graph with the 시뮬레이션 answers; returns MonsterAI.decide's result.
func run_sim() -> Dictionary:
	if doc.is_empty():
		return {}
	var ctx := SimContext.new()
	ctx.answers = sim_answers.duplicate()
	sim_result = MonsterAI.decide(doc, ctx)
	if sim_result.has("error"):
		_sim_label.text = "⛔ %s" % sim_result["error"]
	else:
		var n: Dictionary = sim_result["node"]
		_sim_label.text = "→ %s%s   (지나간 길: %s)" % [MonsterAI.node_text(n), "  · 싸우는 중이 됨%s" % (" + 같은 종족을 부름" if ctx.called else "") if ctx.engaged else "",
			" → ".join(sim_result["path"])]
	_apply_marks()
	return sim_result


func _set_status(text: String) -> void:
	_status.text = text


func _update_status() -> void:
	if doc.is_empty():
		_set_status("AI 그래프를 고르세요")
		return
	_set_status("%s%s — 노드 %d개 · %s" % ["● " if dirty else "", ai_id, doc["nodes"].size(),
		"저장하지 않은 변경 있음" if dirty else "저장됨"])


## Stand-in monster for the 시뮬레이션 tab: conditions answer from the checkboxes.
class SimContext:
	extends RefCounted
	var answers := {}
	var engaged := false
	var called := false

	func ai_check(kind: String, _n: Dictionary) -> bool:
		if kind == "provoked" and engaged:
			return true
		return bool(answers.get(kind, false))

	func ai_engage(n: Dictionary) -> void:
		called = called or (not engaged and not answers.get("provoked", false) and MonsterAI.param(n, "call_allies") > 0.5)
		engaged = true
