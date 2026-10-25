@tool
class_name DialogueEditorPanel
extends Control
## Dialogue Editor main screen (see DIALOGUE_EDITOR_HANDOFF v10.5). Left: dialogue list + search;
## centre: node graph (GraphEdit); right: properties of the selected node (full text is edited
## here, the graph shows a short preview); bottom: preview (same DialogueRunner as the game, with a
## sandbox state) and validation results. Works inside the Godot editor (plugin.gd) and, for
## automated checks, inside the running game - it only depends on the runtime data classes.

signal play_requested(dialogue_id: String)
signal saved(path: String)

const TYPE_COLORS := {"start": Color(0.25, 0.55, 0.32), "line": Color(0.27, 0.42, 0.66), "choice": Color(0.62, 0.45, 0.2),
	"condition": Color(0.5, 0.32, 0.6), "action": Color(0.62, 0.3, 0.28), "cutscene": Color(0.22, 0.52, 0.55),
	"end": Color(0.4, 0.4, 0.42)}
const ADD_TYPES := ["line", "choice", "condition", "action", "cutscene", "end"]
const BACKUP_DIR := "user://dialogue_backups"
const BACKUPS_KEPT := 20
const UNDO_LIMIT := 200

var doc := {}
var path := ""
var dirty := false
var can_play_in_game := false
var issues: Array[Dictionary] = []

var _mtime := 0
var _catalog := {}
var _entries: Array[Dictionary] = []
var _undo: Array[String] = []
var _redo: Array[String] = []
var _snap := ""
var _commit_key := ""
var _commit_ms := 0
var _clipboard := {}
var _selected := ""
var _views := {}  # node id -> {"node": GraphNode, "summary": Label, "options": Array[Label]}
var _pending_conn := {}
var _pending_pos := Vector2.ZERO
var _last_speaker := "narrator"

# preview
var _prev_runner: DialogueRunner
var _prev_ctx: DialogueContext
var _prev_event := {}
var _current_node := ""

# ui
var _list: ItemList
var _search: LineEdit
var _count_label: Label
var _graph: GraphEdit
var _inspector: VBoxContainer
var _status: Label
var _tabs: TabContainer
var _issue_list: ItemList
var _prev_name: Label
var _prev_text: Label
var _prev_choices: VBoxContainer
var _prev_next: Button
var _prev_state: Label
var _prev_log: ItemList
var _sb_flags: TextEdit
var _sb_items: LineEdit
var _sb_gold: SpinBox
var _sb_quests: GridContainer
var _add_menu: PopupMenu
var _confirm: ConfirmationDialog
var _confirm_cb: Callable
var _new_dialog: ConfirmationDialog
var _new_id: LineEdit
var _new_title: LineEdit
var _play_button: Button
var _mode_tabs: TabContainer
var _page: Control
## The 컷씬 tab (cutscene files, new-game story order).
var cutscene_panel: CutsceneEditorPanel
## The 몬스터 AI tab (data/ai decision graphs, which graph each monster uses).
var monster_ai_panel: MonsterAIEditorPanel
## The 지도 tab (data/maps region maps: marks and how each map is obtained).
## 퀘스트 tab (QuestEditorPanel): quest files, validation, where-used
var quest_panel: QuestEditorPanel


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()
	refresh_catalog()
	refresh_list()


# ---------------------------------------------------------------- UI construction

func _btn(parent: Control, text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_ui() -> void:
	# tabs: 대화 (this graph editor), 컷씬 (CutsceneEditorPanel), 몬스터 AI (MonsterAIEditorPanel), 퀘스트 (QuestEditorPanel)
	# (지도 moved to the Map editor: addons/map_editor)
	_mode_tabs = TabContainer.new()
	_mode_tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_mode_tabs)
	var root := VBoxContainer.new()
	root.name = "대화"
	_mode_tabs.add_child(root)
	_page = root
	cutscene_panel = CutsceneEditorPanel.new()
	cutscene_panel.name = "컷씬"
	_mode_tabs.add_child(cutscene_panel)
	cutscene_panel.saved.connect(func(_p: String) -> void: refresh_catalog())
	monster_ai_panel = MonsterAIEditorPanel.new()
	monster_ai_panel.name = "몬스터 AI"
	_mode_tabs.add_child(monster_ai_panel)
	quest_panel = QuestEditorPanel.new()
	quest_panel.name = "퀘스트"
	_mode_tabs.add_child(quest_panel)
	quest_panel.saved.connect(func(_p: String) -> void: refresh_catalog())
	quest_panel.open_ref.connect(_open_quest_ref)
	# toolbar (wraps on narrow screens) + status line
	var bar := HFlowContainer.new()
	root.add_child(bar)
	_btn(bar, "새 대화", _ask_new, "새 대화 파일 만들기 (data/dialogues)")
	_btn(bar, "저장", func() -> void: save(), "Ctrl+S")
	_btn(bar, "↶", undo, "실행 취소 (Ctrl+Z)")
	_btn(bar, "↷", redo, "다시 실행 (Ctrl+Y / Ctrl+Shift+Z)")
	bar.add_child(VSeparator.new())
	var add_label := Label.new()
	add_label.text = "노드 추가:"
	bar.add_child(add_label)
	for t: String in ADD_TYPES:
		var tt := t
		var b := _btn(bar, DialogueData.TYPE_NAMES[t], func() -> void: add_node(tt), "선택한 노드 다음에 이어 붙임 (오른쪽 클릭·빈 곳으로 선 끌기로도 추가)")
		b.add_theme_color_override("font_color", (TYPE_COLORS[t] as Color).lightened(0.45))
	bar.add_child(VSeparator.new())
	_btn(bar, "정렬", arrange, "시작 노드부터 단계별로 자동 배치")
	_btn(bar, "검증", func() -> void: validate(true), "누락 연결·잘못된 ID·도달 불가 노드 검사")
	_btn(bar, "▶ 미리보기", func() -> void: preview_start(), "에디터 안에서 실제 실행기로 진행 (테스트 상태만 사용)")
	_btn(bar, "▶ 선택 노드부터", func() -> void: preview_start(_selected), "선택한 노드에서 미리보기 시작")
	_play_button = _btn(bar, "▶ 게임에서 실행", _play_in_game, "저장한 뒤 실제 게임을 켜서 이 대화를 재생")
	bar.add_child(VSeparator.new())
	_btn(bar, "플래그 목록", func() -> void: EditorWidgets.show_flag_list(self), "모든 플래그와 켜는 곳·쓰는 곳")
	EditorWidgets.help_button(bar, "dialogue")
	EditorWidgets.quick_guide(root, "① 왼쪽에서 대화 고르기 → ② 가운데서 상자를 선으로 잇기 (클릭하면 오른쪽에서 고침) → ③ ▶ 미리보기 → ④ 검증 → ⑤ 저장")
	_status = Label.new()
	_status.clip_text = true
	_status.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	root.add_child(_status)

	var hs := HSplitContainer.new()
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(hs)
	# left: list
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	hs.add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = "검색: ID·제목·태그·화자·대사"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _fill_list())
	left.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_on_list_pick)
	_list.item_selected.connect(_on_list_pick)
	left.add_child(_list)
	_count_label = Label.new()
	_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_count_label.add_theme_font_size_override("font_size", 13)
	left.add_child(_count_label)
	_btn(left, "목록·ID 새로고침", func() -> void:
		refresh_catalog()
		refresh_list(), "퀘스트·컷씬·화자 데이터를 다시 읽음")

	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.add_child(right_split)
	var vs := VSplitContainer.new()
	vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(vs)
	# centre: graph
	_graph = GraphEdit.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.custom_minimum_size = Vector2(400, 300)
	_graph.right_disconnects = true
	_graph.connection_request.connect(_on_connection_request)
	_graph.disconnection_request.connect(_on_disconnection_request)
	_graph.connection_to_empty.connect(_on_connection_to_empty)
	_graph.popup_request.connect(_on_popup_request)
	_graph.delete_nodes_request.connect(_on_delete_nodes)
	_graph.copy_nodes_request.connect(copy_selection)
	_graph.paste_nodes_request.connect(paste)
	_graph.duplicate_nodes_request.connect(func() -> void:
		copy_selection()
		paste())
	_graph.node_selected.connect(func(_n: Node) -> void: _on_selection_changed())
	_graph.node_deselected.connect(func(_n: Node) -> void: _on_selection_changed())
	_graph.end_node_move.connect(_on_end_move)
	vs.add_child(_graph)
	# bottom: preview / validation
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.y = 250
	vs.add_child(_tabs)
	_build_preview_tab()
	_issue_list = ItemList.new()
	_issue_list.name = "검증"
	_issue_list.item_selected.connect(_on_issue_pick)
	_tabs.add_child(_issue_list)
	# right: inspector
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 360
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_split.add_child(scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inspector)

	_add_menu = PopupMenu.new()
	for i in ADD_TYPES.size():
		_add_menu.add_item(DialogueData.TYPE_NAMES[ADD_TYPES[i]] + " 추가", i)
	_add_menu.id_pressed.connect(func(i: int) -> void:
		var pos := (_pending_pos + _graph.scroll_offset) / _graph.zoom
		add_node(ADD_TYPES[i], pos, _pending_conn)
		_pending_conn = {})
	add_child(_add_menu)
	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func() -> void:
		if _confirm_cb.is_valid():
			_confirm_cb.call())
	add_child(_confirm)
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "새 대화"
	var nv := VBoxContainer.new()
	_new_dialog.add_child(nv)
	var l1 := Label.new()
	l1.text = "dialogue_id (영문·숫자·._ — 예: dialogue.npc.rosa.rain)"
	nv.add_child(l1)
	_new_id = LineEdit.new()
	_new_id.custom_minimum_size.x = 420
	nv.add_child(_new_id)
	var l2 := Label.new()
	l2.text = "제목 (목록에 표시)"
	nv.add_child(l2)
	_new_title = LineEdit.new()
	nv.add_child(_new_title)
	_new_dialog.confirmed.connect(func() -> void: create_dialogue(_new_id.text.strip_edges(), _new_title.text.strip_edges()))
	add_child(_new_dialog)
	_update_status()
	_show_inspector()


func _build_preview_tab() -> void:
	var hs := HSplitContainer.new()
	hs.name = "미리보기"
	_tabs.add_child(hs)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.add_child(left)
	var bar := HBoxContainer.new()
	left.add_child(bar)
	_btn(bar, "▶ 처음부터", func() -> void: preview_start())
	_prev_next = _btn(bar, "다음 ▶", preview_next)
	_btn(bar, "■ 정지", preview_stop)
	_prev_state = Label.new()
	_prev_state.clip_text = true  # long paths must not widen the layout
	_prev_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prev_state.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	bar.add_child(_prev_state)
	_prev_name = Label.new()
	_prev_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	left.add_child(_prev_name)
	_prev_text = Label.new()
	_prev_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prev_text.custom_minimum_size = Vector2(160, 40)
	left.add_child(_prev_text)
	_prev_choices = VBoxContainer.new()
	left.add_child(_prev_choices)
	# sandbox
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 320
	hs.add_child(right)
	var t := Label.new()
	t.text = "테스트 상태 (미리보기 전용 · 실게임/세이브에 영향 없음)"
	t.add_theme_color_override("font_color", Color(0.75, 0.9, 0.75))
	right.add_child(t)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(tabs)
	var qs := ScrollContainer.new()
	qs.name = "퀘스트"
	tabs.add_child(qs)
	_sb_quests = GridContainer.new()
	_sb_quests.columns = 2
	qs.add_child(_sb_quests)
	var other := VBoxContainer.new()
	other.name = "플래그·소지품"
	tabs.add_child(other)
	var fl := Label.new()
	fl.text = "켜진 플래그 (한 줄에 하나, 이벤트는 event.<id>)"
	other.add_child(fl)
	_sb_flags = TextEdit.new()
	_sb_flags.custom_minimum_size.y = 60
	_sb_flags.size_flags_vertical = Control.SIZE_EXPAND_FILL
	other.add_child(_sb_flags)
	var row := HBoxContainer.new()
	other.add_child(row)
	var gl := Label.new()
	gl.text = "골드"
	row.add_child(gl)
	_sb_gold = SpinBox.new()
	_sb_gold.max_value = 999999
	_sb_gold.value = 50
	row.add_child(_sb_gold)
	_sb_items = LineEdit.new()
	_sb_items.placeholder_text = "소지품: slime_jelly=5, iron_ore=2"
	_sb_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_sb_items)
	_prev_log = ItemList.new()
	_prev_log.name = "액션 기록"
	tabs.add_child(_prev_log)


func _fill_sandbox_quests() -> void:
	var keep := {}
	for c in _sb_quests.get_children():
		if c is OptionButton:
			keep[c.get_meta("quest")] = DialogueData.QUEST_STATES[c.selected]
		_sb_quests.remove_child(c)
		c.queue_free()
	var ids: Array = (_catalog.get("quests", {}) as Dictionary).keys()
	ids.sort()
	for qid: String in ids:
		var l := Label.new()
		l.text = qid
		l.clip_text = true
		l.custom_minimum_size.x = 170
		l.tooltip_text = qid
		_sb_quests.add_child(l)
		var ob := OptionButton.new()
		for s: String in DialogueData.QUEST_STATES:
			ob.add_item(DialogueData.QUEST_STATE_NAMES[s])
		ob.set_meta("quest", qid)
		ob.selected = DialogueData.QUEST_STATES.find(str(keep.get(qid, "none")))
		_sb_quests.add_child(ob)


## Reads the sandbox widgets into a fresh preview context.
func sandbox() -> DialogueContext:
	var c := DialogueContext.new()
	for line in _sb_flags.text.split("\n", false):
		if line.strip_edges() != "":
			c.flags[line.strip_edges()] = true
	c.gold_amount = int(_sb_gold.value)
	for part in _sb_items.text.split(",", false):
		var kv := part.split("=")
		if kv.size() == 2:
			c.items[kv[0].strip_edges()] = int(kv[1])
	for ob in _sb_quests.get_children():
		if ob is OptionButton:
			c.quest_states[ob.get_meta("quest")] = DialogueData.QUEST_STATES[ob.selected]
	return c


func set_sandbox_quest(quest_id: String, state: String) -> void:
	for ob in _sb_quests.get_children():
		if ob is OptionButton and ob.get_meta("quest") == quest_id:
			ob.selected = DialogueData.QUEST_STATES.find(state)


# ---------------------------------------------------------------- list / files

func refresh_catalog() -> void:
	_catalog = DialogueData.catalog()
	_fill_sandbox_quests()


func refresh_list() -> void:
	_entries = DialogueData.list_all()
	_fill_list()


func _fill_list() -> void:
	_list.clear()
	var q := _search.text.strip_edges().to_lower()
	var per_speaker := {}
	var shown := 0
	for e in _entries:
		var sp: PackedStringArray = e["speakers"]
		for s in sp:
			per_speaker[s] = int(per_speaker.get(s, 0)) + 1
		var names := PackedStringArray()
		for s in sp:
			names.append(DialogueData.speaker_name(s))
		var tags := ", ".join(PackedStringArray(e["tags"]))
		var hay := ("%s %s %s %s %s %s" % [e["id"], e["title"], tags, " ".join(sp), " ".join(names), e["text"]]).to_lower()
		if q != "" and not hay.contains(q):
			continue
		var idx := _list.add_item("%s  ·  %s" % [e["title"], e["id"]] if e["title"] != "" else str(e["id"]))
		_list.set_item_metadata(idx, e["id"])
		_list.set_item_tooltip(idx, "화자: %s\n태그: %s\n%s" % [", ".join(names), tags, e["path"]])
		if e["id"] == doc.get("dialogue_id", ""):
			_list.select(idx)
		shown += 1
	var parts := PackedStringArray()
	for s: String in per_speaker:
		parts.append("%s %d" % [DialogueData.speaker_name(s) if DialogueData.speaker_name(s) != "" else s, per_speaker[s]])
	_count_label.text = "대화 %d개 (표시 %d) · 화자별: %s" % [_entries.size(), shown, ", ".join(parts)]


func _on_list_pick(idx: int) -> void:
	var id: String = _list.get_item_metadata(idx)
	if id == doc.get("dialogue_id", ""):
		return
	if dirty:
		_ask("저장하지 않은 변경이 있습니다. 버리고 '%s'를 열까요?" % id, func() -> void: open_dialogue(id))
		_fill_list()
	else:
		open_dialogue(id)


func open_dialogue(id: String) -> bool:
	var p := DialogueData.path_for(id)
	var d: Variant = DialogueData.read_json(p)
	if not d is Dictionary:
		_set_status("열 수 없음: " + p)
		return false
	doc = DialogueData.normalized(d)
	path = p
	_mtime = FileAccess.get_modified_time(p)
	_reset_history()
	_selected = ""
	preview_stop()
	_rebuild_graph()
	_show_inspector()
	validate(false)
	_fill_list()
	_graph.zoom = 0.85
	_focus_start.call_deferred()
	return true


## Scrolls so the Start node sits near the top-left of the graph view.
func _focus_start() -> void:
	var p := _node_pos(str(doc.get("start_node_id", "start"))) if not doc.is_empty() else Vector2.ZERO
	var top := 0.0
	for id: String in doc.get("editor_positions", {}):
		top = minf(top, float(doc["editor_positions"][id][1]))
	_graph.scroll_offset = Vector2(p.x, top) * _graph.zoom - Vector2(50, 40)


func create_dialogue(id: String, title: String) -> bool:
	if not id.begins_with("dialogue.") or not DialogueData.valid_id(id.replace(".", "_")):
		_ask_info("dialogue_id는 'dialogue.'로 시작하고 영문·숫자·._ 만 쓸 수 있습니다: " + id)
		return false
	if FileAccess.file_exists(DialogueData.path_for(id)):
		_ask_info("이미 있는 대화입니다: " + id)
		return false
	doc = DialogueData.new_doc(id, title)
	path = ""
	_reset_history()
	_selected = ""
	preview_stop()
	_rebuild_graph()
	_show_inspector()
	save(true, true)
	return true


func _ask_new() -> void:
	_new_id.text = "dialogue.npc."
	_new_title.text = ""
	_new_dialog.popup_centered()
	_new_id.grab_focus()
	_new_id.caret_column = _new_id.text.length()


## Saves to data/dialogues/<dialogue_id>.json. Errors and outside changes ask first; the old
## file content is backed up to user://dialogue_backups/<id>/ before it is overwritten.
func save(skip_errors := false, skip_conflict := false) -> bool:
	if doc.is_empty():
		return false
	var id := str(doc["dialogue_id"])
	var target := DialogueData.path_for(id)
	var errors := validate(false)
	if errors > 0 and not skip_errors:
		_ask("오류 %d개가 있습니다 (검증 탭). 그래도 저장할까요?\n게임에서는 끊긴 곳에서 대화가 안전하게 끝납니다." % errors,
			func() -> void: save(true, skip_conflict))
		_tabs.current_tab = 1
		return false
	if not skip_conflict and path == target and FileAccess.file_exists(target) and FileAccess.get_modified_time(target) != _mtime:
		_ask("'%s' 파일이 에디터 밖에서 바뀌었습니다. 덮어쓸까요? (이전 내용은 백업됨)" % target.get_file(),
			func() -> void: save(true, true))
		return false
	if FileAccess.file_exists(target):
		_backup(id, FileAccess.get_file_as_string(target))
	var err := DialogueData.save_dialogue(doc, target)
	if err != OK:
		_ask_info("저장 실패 (%s): %s" % [error_string(err), target])
		return false
	if path != "" and path != target and FileAccess.file_exists(path):
		_backup(id, FileAccess.get_file_as_string(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))  # dialogue_id was renamed
	path = target
	_mtime = FileAccess.get_modified_time(target)
	dirty = false
	refresh_list()
	_update_status()
	_set_status("저장됨: " + target)
	saved.emit(target)
	return true


func _backup(id: String, content: String) -> void:
	var dir := BACKUP_DIR.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("%s.json" % Time.get_datetime_string_from_system().replace(":", "-")), FileAccess.WRITE)
	if f:
		f.store_string(content)
		f.close()
	var files := DialogueData.list_files(dir)
	while files.size() > BACKUPS_KEPT:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(files[0]))
		files.remove_at(0)


func _play_in_game() -> void:
	if doc.is_empty():
		return
	if dirty and not save():
		return
	play_requested.emit(str(doc["dialogue_id"]))


# ---------------------------------------------------------------- history

func _reset_history() -> void:
	_undo.clear()
	_redo.clear()
	_snap = var_to_str(doc)
	_commit_key = ""
	dirty = false
	_update_status()


## Records an edit. Edits with the same key within 1.5 s merge into one undo step (typing).
func _commit(key := "") -> void:
	var cur := var_to_str(doc)
	if cur == _snap:
		return
	var now := Time.get_ticks_msec()
	if not (key != "" and key == _commit_key and now - _commit_ms < 1500 and not _undo.is_empty()):
		_undo.push_back(_snap)
		if _undo.size() > UNDO_LIMIT:
			_undo.pop_front()
	_snap = cur
	_redo.clear()
	_commit_key = key
	_commit_ms = now
	dirty = true
	validate(false)
	_update_status()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.push_back(_snap)
	_snap = _undo.pop_back()
	_restore_snap()


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.push_back(_snap)
	_snap = _redo.pop_back()
	_restore_snap()


func _restore_snap() -> void:
	doc = str_to_var(_snap)
	_commit_key = ""
	dirty = true
	if DialogueData.node_by_id(doc, _selected).is_empty():
		_selected = ""
	_rebuild_graph()
	_show_inspector()
	validate(false)
	_update_status()


## Opens a cutscene in the 컷씬 tab (from a CutsceneCall node).
func edit_cutscene(id: String) -> void:
	_mode_tabs.current_tab = 1
	if id != "" and str(cutscene_panel.doc.get("cutscene_id", "")) != id:
		if not cutscene_panel.open_cutscene(id):
			cutscene_panel._set_status("저장하지 않은 변경이 있어 '%s'를 열지 않았습니다 — 저장하거나 목록에서 다시 고르세요" % id)


## "쓰이는 곳" double-click in the 퀘스트 tab: jump to that dialogue node or cutscene.
func _open_quest_ref(kind: String, id: String, node: String) -> void:
	if kind == "cutscene":
		edit_cutscene(id)
		return
	if str(doc.get("dialogue_id", "")) != id and not open_dialogue(id):
		return
	_mode_tabs.current_tab = 0
	if node != "" and not DialogueData.node_by_id(doc, node).is_empty():
		select_node(node)


func _input(event: InputEvent) -> void:
	if not _page.is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if not k.is_command_or_control_pressed():
		return
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is TextEdit or focus is LineEdit
	if k.keycode == KEY_S:
		save()
		get_viewport().set_input_as_handled()
	elif not typing and k.keycode == KEY_Z and not k.shift_pressed:
		undo()
		get_viewport().set_input_as_handled()
	elif not typing and (k.keycode == KEY_Y or (k.keycode == KEY_Z and k.shift_pressed)):
		redo()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- graph view

func _node_pos(id: String) -> Vector2:
	var p: Variant = doc["editor_positions"].get(id, null)
	if p is Array and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2(40 * doc["nodes"].size(), 40 * doc["nodes"].size())


func _rebuild_graph() -> void:
	var keep := _selected_ids()
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
		if keep.has(n["id"]):
			g.selected = true
	for c: Dictionary in doc["connections"]:
		var from := DialogueData.node_by_id(doc, str(c["from"]))
		var idx := DialogueData.out_ports(from).find(str(c["port"]))
		if idx >= 0 and _views.has(str(c["to"])):
			_graph.connect_node(StringName(c["from"]), idx, StringName(c["to"]), 0)
	_apply_marks()


func _make_gnode(n: Dictionary) -> GraphNode:
	var id := str(n["id"])
	var t := str(n.get("type", ""))
	var g := GraphNode.new()
	g.name = id
	g.title = "%s · %s" % [DialogueData.TYPE_NAMES.get(t, t), id]
	g.position_offset = _node_pos(id)
	g.custom_minimum_size = Vector2(240, 0)
	var col: Color = TYPE_COLORS.get(t, Color.GRAY)
	for key in ["titlebar", "titlebar_selected"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col if key == "titlebar" else col.lightened(0.18)
		sb.set_corner_radius_all(4)
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.set_content_margin_all(6)
		g.add_theme_stylebox_override(key, sb)
	var view := {"node": g, "options": []}
	var summary := Label.new()
	summary.custom_minimum_size.x = 240
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.max_lines_visible = 2
	summary.text = DialogueData.node_summary(n)
	g.add_child(summary)
	view["summary"] = summary
	var port_col := col.lightened(0.35)
	var single_out := t in ["start", "line", "action", "cutscene"]
	g.set_slot(0, DialogueData.has_input(n), 0, Color(0.85, 0.85, 0.85), single_out, 0, port_col)
	var labels: Array[Label] = []
	if t == "choice":
		for o: Dictionary in n.get("options", []):
			var l := Label.new()
			l.text = "▸ " + _option_label(o)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.clip_text = true
			g.add_child(l)
			labels.append(l)
			g.set_slot(g.get_child_count() - 1, false, 0, Color.WHITE, true, 0, port_col)
	elif t == "condition":
		for s in ["참 ▸", "거짓 ▸"]:
			var l := Label.new()
			l.text = s
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			g.add_child(l)
			g.set_slot(g.get_child_count() - 1, false, 0, Color.WHITE, true, 0, Color(0.5, 0.9, 0.5) if s.begins_with("참") else Color(0.95, 0.5, 0.45))
	view["options"] = labels
	_views[id] = view
	return g


func _option_label(o: Dictionary) -> String:
	var t := str(o.get("text", ""))
	if t.length() > 26:
		t = t.substr(0, 25) + "…"
	var cond: Dictionary = o.get("condition", {})
	return t + ("  [조건]" if not cond.is_empty() else "")


func _refresh_view(id: String) -> void:
	if not _views.has(id):
		return
	var n := DialogueData.node_by_id(doc, id)
	var v: Dictionary = _views[id]
	(v["summary"] as Label).text = DialogueData.node_summary(n)
	var labels: Array = v["options"]
	var opts: Array = n.get("options", [])
	for i in mini(labels.size(), opts.size()):
		(labels[i] as Label).text = "▸ " + _option_label(opts[i])


## Error markers on node titles + preview highlight of the current node.
func _apply_marks() -> void:
	var by_node := {}
	for it in issues:
		if it["severity"] == "error" and it["node"] != "":
			by_node[it["node"]] = by_node.get(it["node"], PackedStringArray()) + PackedStringArray([it["message"]])
	for id: String in _views:
		var g: GraphNode = _views[id]["node"]
		var n := DialogueData.node_by_id(doc, id)
		var t := str(n.get("type", ""))
		var bad: bool = by_node.has(id)
		g.title = "%s%s · %s" % ["⚠ " if bad else "", DialogueData.TYPE_NAMES.get(t, t), id]
		g.tooltip_text = "\n".join(by_node[id]) if bad else ""
		g.self_modulate = Color(1.35, 1.2, 0.55) if id == _current_node else (Color(1.15, 0.8, 0.8) if bad else Color.WHITE)


func _selected_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for c in _graph.get_children():
		if c is GraphNode and c.selected:
			out.append(String(c.name))
	return out


func select_node(id: String, center := true) -> void:
	for c in _graph.get_children():
		if c is GraphNode:
			c.selected = String(c.name) == id
	_selected = id
	_show_inspector()
	if center and _views.has(id):
		var g: GraphNode = _views[id]["node"]
		_graph.scroll_offset = g.position_offset * _graph.zoom - _graph.size * 0.5 + g.size * _graph.zoom * 0.5


func _on_selection_changed() -> void:
	# deferred: node_deselected + node_selected arrive as a pair when clicking another node
	_update_selection.call_deferred()


func _update_selection() -> void:
	var ids := _selected_ids()
	var s := ids[0] if ids.size() == 1 else ""
	if s != _selected:
		_selected = s
		_show_inspector()


func _on_end_move() -> void:
	for c in _graph.get_children():
		if c is GraphNode and c.selected:
			doc["editor_positions"][String(c.name)] = [roundi(c.position_offset.x), roundi(c.position_offset.y)]
	_commit("move")


func _on_connection_request(from: StringName, from_port: int, to: StringName, _to_port: int) -> void:
	if from == to:
		return
	var ports := DialogueData.out_ports(DialogueData.node_by_id(doc, String(from)))
	if from_port >= ports.size():
		return
	connect_nodes(String(from), ports[from_port], String(to))


func connect_nodes(from: String, port: String, to: String) -> void:
	var conns: Array = doc["connections"]
	for i in range(conns.size() - 1, -1, -1):
		if conns[i]["from"] == from and conns[i]["port"] == port:
			conns.remove_at(i)  # one target per output
	conns.append({"from": from, "port": port, "to": to})
	_commit()
	_rebuild_graph()


func _on_disconnection_request(from: StringName, from_port: int, to: StringName, _to_port: int) -> void:
	var ports := DialogueData.out_ports(DialogueData.node_by_id(doc, String(from)))
	if from_port >= ports.size():
		return
	var conns: Array = doc["connections"]
	for i in range(conns.size() - 1, -1, -1):
		if conns[i]["from"] == String(from) and conns[i]["port"] == ports[from_port] and conns[i]["to"] == String(to):
			conns.remove_at(i)
	_commit()
	_rebuild_graph()


func _on_connection_to_empty(from: StringName, from_port: int, release_position: Vector2) -> void:
	var ports := DialogueData.out_ports(DialogueData.node_by_id(doc, String(from)))
	if from_port >= ports.size():
		return
	_pending_conn = {"from": String(from), "port": ports[from_port]}
	_pending_pos = release_position
	_add_menu.position = Vector2i(_graph.get_screen_position() + release_position)
	_add_menu.popup()


func _on_popup_request(at_position: Vector2) -> void:
	_pending_conn = {}
	_pending_pos = at_position
	_add_menu.position = Vector2i(_graph.get_screen_position() + at_position)
	_add_menu.popup()


func _on_delete_nodes(names: Array) -> void:
	var ids := PackedStringArray()
	for nm in names:
		ids.append(String(nm))
	delete_nodes(ids)


func delete_nodes(ids: PackedStringArray) -> void:
	var nodes: Array = doc["nodes"]
	var removed := false
	for i in range(nodes.size() - 1, -1, -1):
		var id := str(nodes[i]["id"])
		if ids.has(id):
			if nodes[i]["type"] == "start":
				_set_status("시작 노드는 지울 수 없습니다")
				continue
			nodes.remove_at(i)
			doc["editor_positions"].erase(id)
			removed = true
	if not removed:
		return
	var conns: Array = doc["connections"]
	for i in range(conns.size() - 1, -1, -1):
		if DialogueData.node_by_id(doc, str(conns[i]["from"])).is_empty() or DialogueData.node_by_id(doc, str(conns[i]["to"])).is_empty():
			conns.remove_at(i)
	if ids.has(_selected):
		_selected = ""
	_commit()
	_rebuild_graph()
	_show_inspector()


func _default_node(t: String, id: String) -> Dictionary:
	match t:
		"line":
			return {"id": id, "type": "line", "speaker_id": _last_speaker, "text": ""}
		"choice":
			return {"id": id, "type": "choice", "options": [{"port": "opt_1", "text": "선택지 1"}, {"port": "opt_2", "text": "선택지 2"}]}
		"condition":
			return {"id": id, "type": "condition", "check": {"kind": "flag", "key": ""}}
		"action":
			return {"id": id, "type": "action", "action": "set_flag", "args": {"key": "", "value": true}}
		"cutscene":
			var ids: Array = (_catalog.get("cutscenes", {}) as Dictionary).keys()
			return {"id": id, "type": "cutscene", "cutscene_id": str(ids[0]) if not ids.is_empty() else ""}
		"end":
			return {"id": id, "type": "end", "complete_event": ""}
	return {"id": id, "type": t}


## Adds a node. Without an explicit position it goes right of the selected node and is linked
## from that node's first free output, so a linear script can be typed out quickly.
func add_node(t: String, pos := Vector2.INF, from_conn := {}) -> String:
	if doc.is_empty():
		_set_status("먼저 대화를 열거나 새로 만드세요")
		return ""
	var prefix := {"condition": "cond", "action": "act", "cutscene": "cut"}.get(t, t) as String
	var id := DialogueData.unique_id(doc, prefix)
	if t == "end" and DialogueData.node_by_id(doc, "end").is_empty():
		id = "end"
	var n := _default_node(t, id)
	var src := ""
	var src_port := ""
	if not from_conn.is_empty():
		src = from_conn["from"]
		src_port = from_conn["port"]
	elif _selected != "":
		var sel := DialogueData.node_by_id(doc, _selected)
		for p in DialogueData.out_ports(sel):
			if DialogueData.target(doc, _selected, p) == "":
				src = _selected
				src_port = p
				break
	if pos == Vector2.INF:
		if src != "":
			var base := _node_pos(src)
			pos = base + Vector2(320, 0)
		else:
			pos = (_graph.scroll_offset + _graph.size * 0.5) / _graph.zoom
	doc["nodes"].append(n)
	doc["editor_positions"][id] = [roundi(pos.x), roundi(pos.y)]
	if src != "":
		var conns: Array = doc["connections"]
		for i in range(conns.size() - 1, -1, -1):
			if conns[i]["from"] == src and conns[i]["port"] == src_port:
				conns.remove_at(i)
		conns.append({"from": src, "port": src_port, "to": id})
	_commit()
	_rebuild_graph()
	select_node(id, false)
	return id


func copy_selection() -> void:
	var ids := _selected_ids()
	var nodes := []
	var conns := []
	var pos := {}
	for n: Dictionary in doc["nodes"]:
		if ids.has(n["id"]) and n["type"] != "start":
			nodes.append(n.duplicate(true))
			pos[n["id"]] = _node_pos(n["id"])
	for c: Dictionary in doc["connections"]:
		if ids.has(c["from"]) and ids.has(c["to"]):
			conns.append(c.duplicate())
	_clipboard = {"nodes": nodes, "connections": conns, "pos": pos}
	_set_status("노드 %d개 복사" % nodes.size())


func paste() -> PackedStringArray:
	var made := PackedStringArray()
	if _clipboard.is_empty() or (_clipboard["nodes"] as Array).is_empty() or doc.is_empty():
		return made
	var remap := {}
	for n: Dictionary in _clipboard["nodes"]:
		var prefix := {"condition": "cond", "action": "act", "cutscene": "cut"}.get(n["type"], n["type"]) as String
		var nid := DialogueData.unique_id(doc, prefix)
		remap[n["id"]] = nid
		var copy := n.duplicate(true)
		copy["id"] = nid
		doc["nodes"].append(copy)
		var p: Vector2 = _clipboard["pos"][n["id"]] + Vector2(60, 60)
		doc["editor_positions"][nid] = [roundi(p.x), roundi(p.y)]
		made.append(nid)
	for c: Dictionary in _clipboard["connections"]:
		doc["connections"].append({"from": remap[c["from"]], "port": c["port"], "to": remap[c["to"]]})
	_commit()
	_rebuild_graph()
	for c in _graph.get_children():
		if c is GraphNode:
			c.selected = made.has(String(c.name))
	_set_status("노드 %d개 붙여넣기" % made.size())
	return made


## Simple layered layout: columns by distance from Start, unreachable nodes in a last column.
func arrange() -> void:
	if doc.is_empty():
		return
	var depth := {}
	var order: Array[String] = []
	var start := str(doc["start_node_id"])
	if not DialogueData.node_by_id(doc, start).is_empty():
		depth[start] = 0
		order.append(start)
		var i := 0
		while i < order.size():
			var cur := order[i]
			i += 1
			var n := DialogueData.node_by_id(doc, cur)
			for p in DialogueData.out_ports(n):
				var t := DialogueData.target(doc, cur, p)
				if t != "" and not depth.has(t) and not DialogueData.node_by_id(doc, t).is_empty():
					depth[t] = int(depth[cur]) + 1
					order.append(t)
	var max_d := 0
	for id: String in depth:
		max_d = maxi(max_d, int(depth[id]))
	for n: Dictionary in doc["nodes"]:
		if not depth.has(n["id"]):
			depth[n["id"]] = max_d + 1
			order.append(str(n["id"]))
	var rows := {}
	for id in order:
		var d := int(depth[id])
		var r := int(rows.get(d, 0))
		rows[d] = r + 1
		doc["editor_positions"][id] = [d * 320, r * 170]
	_commit()
	_rebuild_graph()
	_focus_start.call_deferred()


# ---------------------------------------------------------------- inspector

func _clear_inspector() -> void:
	for c in _inspector.get_children():
		_inspector.remove_child(c)
		c.queue_free()


func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	_inspector.add_child(l)


func _field_label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	_inspector.add_child(l)


func _show_inspector() -> void:
	if _inspector == null:
		return
	_clear_inspector()
	if doc.is_empty():
		_heading("대화 에디터")
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "왼쪽 목록에서 대화를 열거나 '새 대화'를 누르세요.\n\n· 노드 추가: 위 버튼 / 그래프 오른쪽 클릭 / 출력에서 빈 곳으로 선 끌기\n· 연결 끊기: 입력 쪽 선을 오른쪽 클릭으로 끌기\n· Delete 삭제, Ctrl+C/V 복사·붙여넣기, Ctrl+D 복제\n· Ctrl+S 저장, Ctrl+Z / Ctrl+Y 실행 취소·다시"
		_inspector.add_child(l)
		return
	if _selected == "":
		_show_meta()
		return
	var n := DialogueData.node_by_id(doc, _selected)
	if n.is_empty():
		_selected = ""
		_show_meta()
		return
	var t := str(n["type"])
	_heading("%s 노드" % DialogueData.TYPE_NAMES.get(t, t))
	_field_label("노드 ID (연결은 ID로 유지됨)")
	var idl := LineEdit.new()
	idl.text = n["id"]
	idl.editable = t != "start"
	idl.text_submitted.connect(func(v: String) -> void: rename_node(_selected, v.strip_edges()))
	idl.focus_exited.connect(func() -> void:
		if is_instance_valid(idl) and idl.text.strip_edges() != _selected:
			rename_node(_selected, idl.text.strip_edges()))
	_inspector.add_child(idl)
	match t:
		"start":
			_note("대화의 진입점. 그래프마다 하나.")
		"line":
			_field_label("화자")
			_inspector.add_child(_options_widget(_speaker_options(), str(n.get("speaker_id", "")), func(v: String) -> void:
				n["speaker_id"] = v
				_last_speaker = v
				_node_edited("speaker", false, true)))
			_field_label("표정 (초상화 그림)")
			var ex_opts := [["", "기본"]]
			var exs: Dictionary = (_catalog.get("speakers", {}) as Dictionary).get(str(n.get("speaker_id", "")), {}).get("expressions", {})
			for ex: String in exs:
				ex_opts.append([ex, "%s (%s)" % [exs[ex], ex]])
			_inspector.add_child(_options_widget(ex_opts, str(n.get("expression", "")), func(v: String) -> void:
				if v == "":
					n.erase("expression")
				else:
					n["expression"] = v
				_node_edited("expression")))
			_field_label("대사 (줄바꿈 가능, 긴 대사는 게임에서 자동 줄바꿈)")
			var te := TextEdit.new()
			te.text = str(n.get("text", ""))
			te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			te.custom_minimum_size.y = 190
			te.text_changed.connect(func() -> void:
				n["text"] = te.text
				_node_edited("text"))
			_inspector.add_child(te)
		"choice":
			_show_choice(n)
		"condition":
			if not n.has("check"):
				n["check"] = {"kind": "flag", "key": ""}
			_check_editor(n["check"], "조건이 참이면 '참', 아니면 '거짓' 출력으로 진행")
		"action":
			_show_action(n)
		"cutscene":
			_field_label("컷씬 (data/cutscenes)")
			var ids: Array = (_catalog.get("cutscenes", {}) as Dictionary).keys()
			ids.sort()
			var opts := []
			for cid: String in ids:
				opts.append([cid, "%s — %s" % [cid, _catalog["cutscenes"][cid].get("title", "")]])
			_inspector.add_child(_options_widget(opts, str(n.get("cutscene_id", "")), func(v: String) -> void:
				n["cutscene_id"] = v
				_node_edited("cutscene", true)))
			_note("단계: " + DialogueData.cutscene_steps_text(str(n.get("cutscene_id", ""))) + "\n카메라는 고정 탑다운 그대로. 컷씬이 끝나면 '다음'으로 진행.")
			var cid := str(n.get("cutscene_id", ""))
			var eb := Button.new()
			eb.text = "컷씬 탭에서 편집"
			eb.pressed.connect(func() -> void: edit_cutscene(cid))
			_inspector.add_child(eb)
		"end":
			_field_label("완료 기록할 이벤트 (선택 — 여기까지 오면 '이 일은 끝났다'를 한 번만 기록. 비워도 됨)")
			_inspector.add_child(EditorWidgets.flag_picker(str(n.get("complete_event", "")), func(v: String) -> void:
				n["complete_event"] = v
				_node_edited("event"), "event"))
	var mine := PackedStringArray()
	for it in issues:
		if it["node"] == _selected:
			mine.append(("오류: " if it["severity"] == "error" else "경고: ") + it["message"])
	if not mine.is_empty():
		var w := Label.new()
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.text = "\n".join(mine)
		w.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
		_inspector.add_child(w)


func _note(text: String) -> void:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	l.add_theme_color_override("font_color", Color(0.62, 0.66, 0.7))
	_inspector.add_child(l)


func _show_meta() -> void:
	_heading("대화 정보")
	_field_label("dialogue_id (바꾸면 저장 시 파일 이름도 바뀜)")
	var idl := LineEdit.new()
	idl.text = doc["dialogue_id"]
	idl.text_submitted.connect(func(v: String) -> void:
		doc["dialogue_id"] = v.strip_edges()
		_commit()
		_update_status())
	_inspector.add_child(idl)
	_field_label("제목")
	var tl := LineEdit.new()
	tl.text = doc["metadata"]["title"]
	tl.text_changed.connect(func(v: String) -> void:
		doc["metadata"]["title"] = v
		_commit("title"))
	_inspector.add_child(tl)
	_field_label("태그 — 왼쪽 목록에서 찾기 쉽게 붙이는 꼬리표, 게임에는 영향 없음 (쉼표로 구분: npc, quest, 지역 이름 등)")
	var tg := LineEdit.new()
	tg.text = ", ".join(PackedStringArray(doc["metadata"]["tags"]))
	tg.text_changed.connect(func(v: String) -> void:
		var tags := []
		for x in v.split(",", false):
			if x.strip_edges() != "":
				tags.append(x.strip_edges())
		doc["metadata"]["tags"] = tags
		_commit("tags"))
	_inspector.add_child(tg)
	_field_label("메모")
	var nt := TextEdit.new()
	nt.text = doc["metadata"]["notes"]
	nt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	nt.custom_minimum_size.y = 110
	nt.text_changed.connect(func() -> void:
		doc["metadata"]["notes"] = nt.text
		_commit("notes"))
	_inspector.add_child(nt)
	var lines := 0
	var speakers := {}
	for n: Dictionary in doc["nodes"]:
		if n["type"] == "line":
			lines += 1
			speakers[DialogueData.speaker_name(str(n.get("speaker_id", "")))] = true
	_note("노드 %d개 · 대사 %d줄 · 화자: %s\n게임 호출: GameHud.start_dialogue(\"%s\") 또는 data/speakers.json의 talk" % [
		doc["nodes"].size(), lines, ", ".join(PackedStringArray(speakers.keys())), doc["dialogue_id"]])


func _show_choice(n: Dictionary) -> void:
	var opts: Array = n.get("options", [])
	n["options"] = opts
	for i in opts.size():
		var o: Dictionary = opts[i]
		var idx := i
		var box := VBoxContainer.new()
		var head := HBoxContainer.new()
		box.add_child(head)
		var pl := Label.new()
		pl.text = "%d." % (i + 1)
		head.add_child(pl)
		var port := LineEdit.new()
		port.text = str(o.get("port", ""))
		port.tooltip_text = "출력 포트 이름 (영문·숫자·_)"
		port.custom_minimum_size.x = 90
		port.text_submitted.connect(func(v: String) -> void: rename_port(_selected, idx, v.strip_edges()))
		port.focus_exited.connect(func() -> void:
			if is_instance_valid(port) and port.text.strip_edges() != str(o.get("port", "")):
				rename_port(_selected, idx, port.text.strip_edges()))
		head.add_child(port)
		var up := Button.new()
		up.text = "▲"
		up.disabled = i == 0
		up.pressed.connect(func() -> void: _move_option(n, idx, -1))
		head.add_child(up)
		var dn := Button.new()
		dn.text = "▼"
		dn.disabled = i == opts.size() - 1
		dn.pressed.connect(func() -> void: _move_option(n, idx, 1))
		head.add_child(dn)
		var del := Button.new()
		del.text = "✕"
		del.pressed.connect(func() -> void:
			opts.remove_at(idx)
			_drop_dangling_connections(str(n["id"]))
			_node_edited("options", true, true))
		head.add_child(del)
		var tx := LineEdit.new()
		tx.text = str(o.get("text", ""))
		tx.placeholder_text = "선택지 문구"
		tx.text_changed.connect(func(v: String) -> void:
			o["text"] = v
			_node_edited("opt%d" % idx))
		box.add_child(tx)
		var cond: Dictionary = o.get("condition", {})
		var cb := CheckBox.new()
		cb.text = "조건이 맞을 때만 보이기"
		cb.button_pressed = not cond.is_empty()
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				o["condition"] = {"kind": "flag", "key": ""}
			else:
				o.erase("condition")
			_node_edited("optcond", false, true))
		box.add_child(cb)
		_inspector.add_child(box)
		if not cond.is_empty():
			_check_editor(cond, "")
		_inspector.add_child(HSeparator.new())
	var add := Button.new()
	add.text = "+ 선택지 추가"
	add.pressed.connect(func() -> void:
		var k := opts.size() + 1
		var ports := DialogueData.out_ports(n)
		while ports.has("opt_%d" % k):
			k += 1
		opts.append({"port": "opt_%d" % k, "text": "선택지 %d" % (opts.size() + 1)})
		_node_edited("options", true, true))
	_inspector.add_child(add)


func _move_option(n: Dictionary, i: int, d: int) -> void:
	var opts: Array = n["options"]
	var j := i + d
	if j < 0 or j >= opts.size():
		return
	var tmp: Variant = opts[i]
	opts[i] = opts[j]
	opts[j] = tmp
	_node_edited("options", true, true)


func _drop_dangling_connections(id: String) -> void:
	var ports := DialogueData.out_ports(DialogueData.node_by_id(doc, id))
	var conns: Array = doc["connections"]
	for i in range(conns.size() - 1, -1, -1):
		if conns[i]["from"] == id and not ports.has(str(conns[i]["port"])):
			conns.remove_at(i)


func rename_port(id: String, idx: int, new_port: String) -> void:
	var n := DialogueData.node_by_id(doc, id)
	var opts: Array = n.get("options", [])
	if idx >= opts.size():
		return
	var old := str(opts[idx].get("port", ""))
	if new_port == old:
		return
	if not DialogueData.valid_id(new_port) or DialogueData.out_ports(n).has(new_port):
		_set_status("포트 이름이 올바르지 않거나 중복: " + new_port)
		_show_inspector()
		return
	opts[idx]["port"] = new_port
	for c: Dictionary in doc["connections"]:
		if c["from"] == id and c["port"] == old:
			c["port"] = new_port
	_node_edited("port", true, true)


func rename_node(old: String, new_id: String) -> void:
	if old == new_id or old == "":
		return
	if not DialogueData.valid_id(new_id) or not DialogueData.node_by_id(doc, new_id).is_empty():
		_set_status("노드 ID가 올바르지 않거나 이미 있음: " + new_id)
		_show_inspector()
		return
	var n := DialogueData.node_by_id(doc, old)
	n["id"] = new_id
	for c: Dictionary in doc["connections"]:
		if c["from"] == old:
			c["from"] = new_id
		if c["to"] == old:
			c["to"] = new_id
	if doc["editor_positions"].has(old):
		doc["editor_positions"][new_id] = doc["editor_positions"][old]
		doc["editor_positions"].erase(old)
	if doc["start_node_id"] == old:
		doc["start_node_id"] = new_id
	_selected = new_id
	_commit()
	_rebuild_graph()
	select_node(new_id, false)


func _show_action(n: Dictionary) -> void:
	_field_label("명령 (허용된 목록만 — 임의 코드 실행 없음)")
	var opts := []
	for a: String in DialogueData.ACTIONS:
		opts.append([a, "%s (%s)" % [DialogueData.ACTIONS[a]["label"], a]])
	_inspector.add_child(_options_widget(opts, str(n.get("action", "")), func(v: String) -> void:
		n["action"] = v
		var args := {}
		for spec: Dictionary in DialogueData.ACTIONS[v]["args"]:
			args[spec["name"]] = spec.get("default", "")
		n["args"] = args
		_node_edited("action", false, true)))
	var spec_d: Dictionary = DialogueData.ACTIONS.get(str(n.get("action", "")), {})
	if not n.has("args"):
		n["args"] = {}
	var args: Dictionary = n["args"]
	for spec: Dictionary in spec_d.get("args", []):
		_field_label(spec["label"])
		_inspector.add_child(_value_widget(spec, args, str(args.get("quest_id", ""))))
	if spec_d.has("args") and str(n.get("action", "")).begins_with("quest_complete"):
		_note("보상은 퀘스트 데이터(data/quests)에서 정함. 완료 조건 미달이면 아무 일도 없음. 결과(분기)를 비우면 기본 보상.")


## Condition editor shared by Condition nodes and choice-option conditions.
func _check_editor(check: Dictionary, hint: String) -> void:
	if hint != "":
		_note(hint)
	var opts := []
	for k: String in DialogueData.CONDITIONS:
		opts.append([k, DialogueData.CONDITIONS[k]["label"]])
	_inspector.add_child(_options_widget(opts, str(check.get("kind", "")), func(v: String) -> void:
		check.clear()
		check["kind"] = v
		for f: Dictionary in DialogueData.CONDITIONS[v]["fields"]:
			check[f["name"]] = f.get("default", "")
		_node_edited("kind", false, true)))
	for f: Dictionary in DialogueData.CONDITIONS.get(str(check.get("kind", "")), {}).get("fields", []):
		_field_label("  " + f["label"])
		_inspector.add_child(_value_widget(f, check, str(check.get("quest_id", ""))))


func _speaker_options() -> Array:
	var out := []
	var sp: Dictionary = _catalog.get("speakers", {})
	for id: String in sp:
		out.append([id, "%s (%s)" % [sp[id].get("name", ""), id] if str(sp[id].get("name", "")) != "" else "(이름 없음 — 지문) (%s)" % id])
	return out


## Widget for one typed field; writes into target[spec.name].
func _value_widget(spec: Dictionary, target: Dictionary, quest_id: String) -> Control:
	var key: String = spec["name"]
	var val: Variant = target.get(key, spec.get("default", ""))
	match spec["type"]:
		"bool":
			var cb := CheckBox.new()
			cb.text = "켜기"
			cb.button_pressed = bool(val) if val is bool else true
			target[key] = cb.button_pressed
			cb.toggled.connect(func(on: bool) -> void:
				target[key] = on
				_node_edited(key))
			return cb
		"int":
			var sbx := SpinBox.new()
			sbx.min_value = 0
			sbx.max_value = 999999
			sbx.value = int(val) if str(val) != "" else 0
			target[key] = int(sbx.value)
			sbx.value_changed.connect(func(v: float) -> void:
				target[key] = int(v)
				_node_edited(key))
			return sbx
		"quest":
			var opts := []
			var ids: Array = (_catalog.get("quests", {}) as Dictionary).keys()
			ids.sort()
			for qid: String in ids:
				opts.append([qid, "%s — %s" % [qid, _catalog["quests"][qid].get("title", "")]])
			return _options_widget(opts, str(val), func(v: String) -> void:
				target[key] = v
				_node_edited(key, false, true))
		"objective":
			var opts2 := []
			for o: Dictionary in _catalog.get("quests", {}).get(quest_id, {}).get("objectives", []):
				opts2.append([o["id"], "%s — %s" % [o["id"], o.get("text", "")]])
			return _options_widget(opts2, str(val), func(v: String) -> void:
				target[key] = v
				_node_edited(key))
		"outcome":
			var opts3 := [["", "(기본 보상)"]]
			var oc: Dictionary = _catalog.get("quests", {}).get(quest_id, {}).get("outcomes", {})
			for k: String in oc:
				opts3.append([k, "%s — %s" % [k, oc[k].get("label", "")]])
			return _options_widget(opts3, str(val), func(v: String) -> void:
				target[key] = v
				_node_edited(key))
		"quest_state":
			var opts4 := []
			for s: String in DialogueData.QUEST_STATES:
				opts4.append([s, DialogueData.QUEST_STATE_NAMES[s]])
			return _options_widget(opts4, str(val), func(v: String) -> void:
				target[key] = v
				_node_edited(key))
		"recipe":
			var opts6 := []
			var rids: Array = (_catalog.get("recipes", {}) as Dictionary).keys()
			rids.sort()
			for rid: String in rids:
				opts6.append([rid, "%s (%s)" % [_catalog["recipes"][rid].get("name", rid), rid]])
			return _options_widget(opts6, str(val), func(v: String) -> void:
				target[key] = v
				_node_edited(key))
		"flag":
			return EditorWidgets.flag_picker(str(val), func(v: String) -> void:
				target[key] = v
				_node_edited(key), "flag")
		"event":
			return EditorWidgets.flag_picker(str(val), func(v: String) -> void:
				target[key] = v
				_node_edited(key), "event")
		"item":
			var opts5 := []
			var items: Array = ItemDB.ITEMS.keys()
			items.sort()
			for it: String in items:
				opts5.append([it, "%s (%s)" % [ItemDB.ITEMS[it]["name"], it]])
			return _options_widget(opts5, str(val), func(v: String) -> void:
				target[key] = v
				_node_edited(key))
	var le := LineEdit.new()
	le.text = str(val)
	le.text_changed.connect(func(v: String) -> void:
		target[key] = v.strip_edges()
		_node_edited(key))
	return le


## OptionButton over [value, label] pairs; an unknown current value (typo / deleted id) stays
## visible as a warning entry so nothing is silently replaced.
func _options_widget(opts: Array, current: String, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.fit_to_longest_item = false
	ob.clip_text = true
	var found := -1
	for i in opts.size():
		ob.add_item(str(opts[i][1]))
		ob.set_item_metadata(i, str(opts[i][0]))
		if str(opts[i][0]) == current:
			found = i
	if found < 0:
		ob.add_item("⚠ %s (없음)" % current if current != "" else "(선택하세요)")
		ob.set_item_metadata(ob.item_count - 1, current)
		found = ob.item_count - 1
	ob.selected = found
	ob.item_selected.connect(func(i: int) -> void: on_pick.call(str(ob.get_item_metadata(i))))
	return ob


## After a property edit: refresh the node view (or rebuild when ports changed) and record undo.
func _node_edited(field: String, structural := false, reinspect := false) -> void:
	_commit("edit:%s:%s" % [_selected, field])
	if structural:
		_rebuild_graph()
	else:
		_refresh_view(_selected)
		_apply_marks()
	if reinspect:
		_show_inspector.call_deferred()


# ---------------------------------------------------------------- validation

## Runs the shared validator; returns the error count. show = switch to the results tab.
func validate(show := false) -> int:
	if doc.is_empty():
		return 0
	issues = DialogueData.validate(doc, _catalog)
	_issue_list.clear()
	var errors := 0
	for it in issues:
		var is_err: bool = it["severity"] == "error"
		errors += 1 if is_err else 0
		var idx := _issue_list.add_item("%s %s%s" % ["⛔" if is_err else "⚠", "[%s] " % it["node"] if it["node"] != "" else "", it["message"]])
		_issue_list.set_item_metadata(idx, it["node"])
		_issue_list.set_item_custom_fg_color(idx, Color(1.0, 0.55, 0.5) if is_err else Color(1.0, 0.85, 0.45))
	if issues.is_empty():
		_issue_list.add_item("문제 없음 ✔")
	_tabs.set_tab_title(1, "검증 (오류 %d · 경고 %d)" % [errors, issues.size() - errors])
	if show:
		_tabs.current_tab = 1
		_show_inspector()  # refresh the selected node's error lines (not while typing)
	_apply_marks()
	_update_status()
	return errors


func _on_issue_pick(idx: int) -> void:
	var id: Variant = _issue_list.get_item_metadata(idx)
	if id is String and id != "":
		select_node(id)


# ---------------------------------------------------------------- preview (same runner as the game)

func preview_start(from := "") -> void:
	if doc.is_empty():
		return
	_prev_ctx = sandbox()
	_prev_runner = DialogueRunner.new(doc.duplicate(true), _prev_ctx)
	_tabs.current_tab = 0
	_prev_show(_prev_runner.start(from))


func preview_stop() -> void:
	_prev_runner = null
	_prev_event = {}
	_current_node = ""
	if _prev_text:
		_prev_name.text = ""
		_prev_text.text = "▶ 미리보기를 누르면 실제 대화 실행기로 진행합니다."
		_prev_state.text = ""
		for c in _prev_choices.get_children():
			c.queue_free()
		_prev_next.disabled = true
	if not _views.is_empty():
		_apply_marks()


func preview_next() -> void:
	if _prev_runner and _prev_event.get("type", "") in ["line", "cutscene"]:
		_prev_show(_prev_runner.next())


func preview_choose(port: String) -> void:
	if _prev_runner and _prev_event.get("type", "") == "choice":
		_prev_show(_prev_runner.choose(port))


func preview_event() -> Dictionary:
	return _prev_event


func _prev_show(ev: Dictionary) -> void:
	_prev_event = ev
	_current_node = str(ev.get("node", ""))
	for c in _prev_choices.get_children():
		_prev_choices.remove_child(c)
		c.queue_free()
	_prev_next.disabled = true
	_prev_name.text = ""
	match ev.get("type", ""):
		"line":
			_prev_name.text = ev["name"] if ev["name"] != "" else "(지문)"
			_prev_text.text = ev["text"]
			_prev_next.disabled = false
		"choice":
			_prev_text.text = "선택:"
			var i := 1
			for o: Dictionary in ev["options"]:
				var b := Button.new()
				b.text = "%d. %s" % [i, o["text"]]
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.clip_text = true
				b.tooltip_text = o["text"]
				var port: String = o["port"]
				b.pressed.connect(func() -> void: preview_choose(port))
				_prev_choices.add_child(b)
				i += 1
		"cutscene":
			_prev_name.text = "컷씬 호출"
			_prev_text.text = "▶ %s\n%s\n(에디터에서는 단계만 표시 — '다음'으로 컷씬이 끝난 뒤를 진행. 실제 재생은 '게임에서 실행')" % [
				ev["cutscene_id"], DialogueData.cutscene_steps_text(ev["cutscene_id"])]
			_prev_next.disabled = false
		"end":
			_prev_text.text = "— 대화 종료 —" if ev.get("error", "") == "" else "⛔ 중단: " + str(ev["error"])
			_explain_end(ev)
	_prev_state.text = "경로: " + " → ".join(PackedStringArray(_prev_runner.trace)) if _prev_runner else ""
	_prev_log.clear()
	if _prev_ctx:
		for l in _prev_ctx.log:
			_prev_log.add_item(l)
	_apply_marks()
	if _views.has(_current_node):
		var g: GraphNode = _views[_current_node]["node"]
		_graph.scroll_offset = g.position_offset * _graph.zoom - _graph.size * 0.5 + g.size * _graph.zoom * 0.5


## Why the preview ended here, in plain words: unlinked outputs, and every condition it passed
## with its answer — with a button that flips the test state so that branch opens next time.
func _explain_end(ev: Dictionary) -> void:
	if _prev_runner == null:
		return
	var lines_seen := 0
	var conds := []
	for id in _prev_runner.trace:
		var n := DialogueData.node_by_id(doc, str(id))
		if n.get("type", "") == "line":
			lines_seen += 1
		elif n.get("type", "") == "condition":
			conds.append(n)
	var err := str(ev.get("error", ""))
	var msg := ""
	if err.begins_with("연결 없는 출력"):
		msg = "노드 '%s'의 출력 점이 아무 데도 이어지지 않았어요. 그림판에서 그 점을 다음 상자로 끌어 이으세요." % ev.get("node", "")
	elif err.begins_with("보이는 선택지가 없다"):
		msg = "선택지 '%s'의 보기가 모두 조건에 가려졌어요. 아래 조건을 맞추거나 조건 없는 보기를 하나 두세요." % ev.get("node", "")
	elif err != "":
		msg = err
	elif lines_seen == 0:
		msg = "대사가 하나도 나오지 않고 끝났어요. 아래 조건들의 답 때문이에요 — 버튼으로 테스트 상태를 바꿔 다시 볼 수 있어요."
	if msg != "":
		var l := Label.new()
		l.text = "왜? " + msg
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		_prev_choices.add_child(l)
	for n: Dictionary in conds:
		var check: Dictionary = n.get("check", {})
		var ok := DialogueData.eval_condition(check, _prev_ctx)
		var row := HBoxContainer.new()
		_prev_choices.add_child(row)
		var cl := Label.new()
		cl.text = "조건 '%s' (%s): %s" % [n.get("id", ""), _check_text(check), "예" if ok else "아니오"]
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cl.clip_text = true
		cl.tooltip_text = cl.text
		cl.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6) if ok else Color(1.0, 0.6, 0.55))
		row.add_child(cl)
		var b := Button.new()
		b.text = "'예'로 바꿔 다시 보기" if not ok else "'아니오'로 바꿔 다시 보기"
		b.tooltip_text = "오른쪽 테스트 상태를 이 조건에 맞게 고치고 처음부터 다시 미리보기"
		var c := check
		var want := not ok
		b.pressed.connect(func() -> void:
			_force_condition(c, want)
			preview_start())
		row.add_child(b)


func _check_text(check: Dictionary) -> String:
	match str(check.get("kind", "")):
		"flag":
			return "플래그 %s 켜짐" % check.get("key", "")
		"quest":
			return "퀘스트 %s = %s" % [check.get("quest_id", ""), DialogueData.QUEST_STATE_NAMES.get(str(check.get("state", "")), check.get("state", ""))]
		"item":
			return "%s %d개 이상" % [ItemDB.ITEMS.get(str(check.get("item", "")), {}).get("name", check.get("item", "")), int(check.get("count", 1))]
		"gold":
			return "골드 %d 이상" % int(check.get("amount", 0))
		"event":
			return "이벤트 %s 완료" % check.get("event_id", "")
	return str(check.get("kind", ""))


## Edit the sandbox widgets so a condition answers `want`.
func _force_condition(check: Dictionary, want: bool) -> void:
	match str(check.get("kind", "")):
		"flag", "event":
			var key := str(check.get("key", "")) if check.get("kind", "") == "flag" else "event." + str(check.get("event_id", ""))
			var lines := []
			for l in _sb_flags.text.split("\n", false):
				if l.strip_edges() != "" and l.strip_edges() != key:
					lines.append(l.strip_edges())
			if want:
				lines.append(key)
			_sb_flags.text = "\n".join(PackedStringArray(lines))
		"quest":
			set_sandbox_quest(str(check.get("quest_id", "")), str(check.get("state", "active")) if want else "none")
		"item":
			var item := str(check.get("item", ""))
			var parts := []
			for part in _sb_items.text.split(",", false):
				if part.split("=")[0].strip_edges() != item and part.strip_edges() != "":
					parts.append(part.strip_edges())
			if want:
				parts.append("%s=%d" % [item, int(check.get("count", 1))])
			_sb_items.text = ", ".join(PackedStringArray(parts))
		"gold":
			_sb_gold.value = int(check.get("amount", 0)) if want else maxi(int(check.get("amount", 0)) - 1, 0)


# ---------------------------------------------------------------- status / dialogs

func _update_status() -> void:
	if _status == null:
		return
	if doc.is_empty():
		_status.text = "대화를 여세요"
		return
	var errors := 0
	for it in issues:
		errors += 1 if it["severity"] == "error" else 0
	_status.text = "%s%s · %s · 노드 %d · 오류 %d" % [doc["dialogue_id"], " *" if dirty else "", path if path != "" else "(저장 안 됨)", doc["nodes"].size(), errors]


func _set_status(text: String) -> void:
	_update_status()
	if _status:
		_status.text = text + "   |   " + _status.text
	print("[dialogue editor] ", text)


func _ask(text: String, cb: Callable) -> void:
	_confirm_cb = cb
	_confirm.dialog_text = text
	_confirm.get_cancel_button().visible = true
	_confirm.popup_centered()


func _ask_info(text: String) -> void:
	_confirm_cb = Callable()
	_confirm.dialog_text = text
	_confirm.get_cancel_button().visible = false
	_confirm.popup_centered()
