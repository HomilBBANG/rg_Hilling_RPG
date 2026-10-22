@tool
class_name CutsceneEditorPanel
extends Control
## The dialogue editor's 컷씬 tab: write cutscenes (data/cutscenes/*.json) as a list of steps —
## illustration, narration, lines with portraits, fades, letterbox, actor moves, flags — without
## touching JSON. The step types and their fields come from CutsceneData.STEPS, the same list the
## game's CutsceneRunner plays. Also edits the new-game story order (data/story.json).
## Preview plays the screen-side steps (illustration / narration / lines / fades / letterbox /
## captions) in the editor; actor moves are listed there and seen for real with "게임에서 실행".

signal play_requested(cutscene_id: String)
signal saved(path: String)

const TYPE_COLORS := {"quest": Color(0.95, 0.8, 0.4), "fade": Color(0.55, 0.55, 0.6), "image": Color(0.75, 0.55, 0.3), "narration": Color(0.85, 0.8, 0.6),
	"line": Color(0.45, 0.62, 0.9), "caption": Color(0.7, 0.75, 0.8), "wait": Color(0.5, 0.5, 0.5),
	"letterbox": Color(0.6, 0.6, 0.65), "actor_move": Color(0.45, 0.78, 0.5), "actor_face": Color(0.45, 0.7, 0.6),
	"set_flag": Color(0.8, 0.5, 0.45)}
const BACKUP_DIR := "user://dialogue_backups"
const BACKUPS_KEPT := 20
const UNDO_LIMIT := 200
const PREVIEW_SIZE := Vector2(640, 360)
const TYPE_CPS := 30.0  # narration typing speed, same as the game's CutsceneOverlay

var doc := {}
var path := ""
var dirty := false
var can_play_in_game := false
var issues: Array[Dictionary] = []
var selected := -1

var _mtime := 0
var _undo: Array[String] = []
var _redo: Array[String] = []
var _snap := ""
var _commit_key := ""
var _commit_ms := 0
var _ids: Array = []

var _list: ItemList
var _search: LineEdit
var _story_list: ItemList
var _steps: ItemList
var _inspector: VBoxContainer
var _status: Label
var _tabs: TabContainer
var _issue_list: ItemList
var _add_menu: PopupMenu
var _confirm: ConfirmationDialog
var _confirm_cb: Callable
var _new_dialog: ConfirmationDialog
var _new_id: LineEdit
var _new_title: LineEdit
var _file_dialog: ConfirmationDialog  # EditorFileDialog in the editor, FileDialog elsewhere
var _file_target := -1
var _play_button: Button

# preview
var _pv: Control
var _pv_image: TextureRect
var _pv_placeholder: Label
var _pv_world: Label
var _pv_narr: Label
var _pv_caption: Label
var _pv_note: Label
var _pv_box: PanelContainer
var _pv_line: Label
var _pv_portraits: Array[TextureRect] = []
var _pv_names: Array[Label] = []
var _pv_bars: Array[ColorRect] = []
var _pv_fade: ColorRect
var _pv_state: Label
var previewing := false
var preview_step := -1
var _pv_advance := false
var _pv_stop := false


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()
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
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bar := HFlowContainer.new()
	root.add_child(bar)
	_btn(bar, "새 컷씬", _ask_new, "새 컷씬 파일 만들기 (data/cutscenes)")
	_btn(bar, "복제", _duplicate_cutscene, "지금 컷씬을 다른 ID로 복사")
	_btn(bar, "저장", func() -> void: save(), "Ctrl+S")
	_btn(bar, "↶", undo, "실행 취소 (Ctrl+Z)")
	_btn(bar, "↷", redo, "다시 실행 (Ctrl+Y)")
	bar.add_child(VSeparator.new())
	var add := MenuButton.new()
	add.text = "단계 추가 ▾"
	add.flat = false
	add.tooltip_text = "선택한 단계 다음에 넣음"
	_add_menu = add.get_popup()
	for i in CutsceneData.ORDER.size():
		_add_menu.add_item(CutsceneData.STEPS[CutsceneData.ORDER[i]]["label"], i)
	_add_menu.id_pressed.connect(func(i: int) -> void: add_step(CutsceneData.ORDER[i]))
	bar.add_child(add)
	_btn(bar, "▲", func() -> void: move_step(selected, -1), "선택 단계를 위로")
	_btn(bar, "▼", func() -> void: move_step(selected, 1), "선택 단계를 아래로")
	_btn(bar, "단계 복제", func() -> void: duplicate_step(selected))
	_btn(bar, "단계 삭제", func() -> void: delete_step(selected), "Delete")
	bar.add_child(VSeparator.new())
	_btn(bar, "검증", func() -> void: validate(true))
	_btn(bar, "▶ 미리보기", func() -> void: preview_start(0), "에디터 안에서 화면 쪽 단계를 재생 (E/Space/클릭 = 다음)")
	_btn(bar, "▶ 선택 단계부터", func() -> void: preview_start(maxi(selected, 0)))
	_btn(bar, "■ 정지", preview_stop)
	_play_button = _btn(bar, "▶ 게임에서 실행", _play_in_game, "저장한 뒤 실제 게임을 켜서 이 컷씬을 재생")
	_btn(bar, "▶ 새 게임 순서 실행", func() -> void: play_requested.emit("story.new_game"), "새 게임 때 나오는 컷씬들을 순서대로 게임에서 재생")
	_status = Label.new()
	_status.clip_text = true
	_status.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	root.add_child(_status)

	var hs := HSplitContainer.new()
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(hs)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	hs.add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = "검색: ID·제목·문장"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _fill_list())
	left.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: _on_pick(str(_list.get_item_metadata(i))))
	left.add_child(_list)
	var sl := Label.new()
	sl.text = "새 게임 때 재생 (순서대로)"
	left.add_child(sl)
	_story_list = ItemList.new()
	_story_list.custom_minimum_size.y = 110
	left.add_child(_story_list)
	var sh := HBoxContainer.new()
	left.add_child(sh)
	_btn(sh, "+ 지금 컷씬", func() -> void: story_add(str(doc.get("cutscene_id", ""))), "지금 편집 중인 컷씬을 새 게임 순서 끝에 추가")
	_btn(sh, "▲", func() -> void: story_move(-1))
	_btn(sh, "▼", func() -> void: story_move(1))
	_btn(sh, "빼기", story_remove)

	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.add_child(right_split)
	var vs := VSplitContainer.new()
	vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(vs)
	_steps = ItemList.new()
	_steps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_steps.custom_minimum_size = Vector2(380, 200)
	_steps.item_selected.connect(func(i: int) -> void: select_step(i, false))
	_steps.item_activated.connect(func(i: int) -> void: preview_start(i))
	vs.add_child(_steps)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.y = PREVIEW_SIZE.y + 70
	vs.add_child(_tabs)
	_build_preview()
	_issue_list = ItemList.new()
	_issue_list.name = "검증"
	_issue_list.item_selected.connect(func(i: int) -> void:
		var st := int(_issue_list.get_item_metadata(i))
		if st >= 0:
			select_step(st))
	_tabs.add_child(_issue_list)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 380
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_split.add_child(scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inspector)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func() -> void:
		if _confirm_cb.is_valid():
			_confirm_cb.call())
	add_child(_confirm)
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "새 컷씬"
	var nv := VBoxContainer.new()
	_new_dialog.add_child(nv)
	var l1 := Label.new()
	l1.text = "cutscene_id (영문·숫자·._ — 예: cutscene.story.dragon_offer)"
	nv.add_child(l1)
	_new_id = LineEdit.new()
	_new_id.custom_minimum_size.x = 420
	nv.add_child(_new_id)
	var l2 := Label.new()
	l2.text = "제목 (목록에 표시)"
	nv.add_child(l2)
	_new_title = LineEdit.new()
	nv.add_child(_new_title)
	_new_dialog.confirmed.connect(func() -> void: create_cutscene(_new_id.text.strip_edges(), _new_title.text.strip_edges()))
	add_child(_new_dialog)
	_file_dialog = EditorFileDialog.new() if Engine.is_editor_hint() and ClassDB.class_exists("EditorFileDialog") else FileDialog.new()
	_file_dialog.set("file_mode", 0)  # open one file (same value in both dialog classes)
	_file_dialog.set("access", 0)     # res://
	_file_dialog.set("filters", PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; 그림"]))
	_file_dialog.set("current_dir", CutsceneData.ILLUSTRATION_DIR)
	_file_dialog.connect("file_selected", func(p: String) -> void:
		if _file_target >= 0 and _file_target < _step_count():
			doc["steps"][_file_target]["path"] = p
			_edited("path", true))
	add_child(_file_dialog)
	_update_status()
	_show_inspector()


func _build_preview() -> void:
	var page := VBoxContainer.new()
	page.name = "미리보기"
	_tabs.add_child(page)
	var row := HBoxContainer.new()
	page.add_child(row)
	_pv = Control.new()
	_pv.custom_minimum_size = PREVIEW_SIZE
	_pv.clip_contents = true
	_pv.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			preview_next())
	row.add_child(_pv)
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.32, 0.22)
	bg.size = PREVIEW_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv.add_child(bg)
	_pv_world = _pv_label(16, Color(0.8, 0.9, 0.8, 0.7))
	_pv_world.text = "게임 화면 (고정 탑다운)"
	_pv_world.position = Vector2(12, 8)
	_pv_image = TextureRect.new()
	_pv_image.size = PREVIEW_SIZE
	_pv_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pv_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_image.visible = false
	_pv.add_child(_pv_image)
	_pv_placeholder = _pv_label(18, Color(0.9, 0.86, 0.76))
	_pv_placeholder.size = PREVIEW_SIZE
	_pv_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pv_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_pv_placeholder.add_theme_stylebox_override("normal", _flat(Color(0.12, 0.12, 0.16), Color(0.62, 0.5, 0.32), 2))
	_pv_placeholder.visible = false
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.size = Vector2(PREVIEW_SIZE.x, PREVIEW_SIZE.y / 9.0)
		b.position = Vector2(0, 0 if top else PREVIEW_SIZE.y - b.size.y)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.visible = false
		_pv.add_child(b)
		_pv_bars.append(b)
	_pv_narr = _pv_label(15, Color(0.96, 0.92, 0.82))
	_pv_narr.size = Vector2(PREVIEW_SIZE.x, 100)
	_pv_narr.position = Vector2(0, 130)
	_pv_narr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pv_narr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pv_narr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pv_narr.add_theme_stylebox_override("normal", _flat(Color(0, 0, 0, 0.55)))
	_pv_narr.visible = false
	for side in [0, 1]:
		var tr := TextureRect.new()
		tr.size = Vector2(140, 160)
		tr.position = Vector2(30 if side == 0 else PREVIEW_SIZE.x - 170, PREVIEW_SIZE.y - 160)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.visible = false
		_pv.add_child(tr)
		_pv_portraits.append(tr)
		var nl := _pv_label(13, Color(0.2, 0.14, 0.08))
		nl.add_theme_stylebox_override("normal", _flat(Color(0.96, 0.87, 0.56)))
		nl.visible = false
		_pv_names.append(nl)
	_pv_box = PanelContainer.new()
	_pv_box.add_theme_stylebox_override("panel", _flat(Color(0.06, 0.065, 0.09, 0.94), Color(0.72, 0.58, 0.36), 2))
	_pv_box.position = Vector2(150, PREVIEW_SIZE.y - 80)
	_pv_box.size = Vector2(PREVIEW_SIZE.x - 300, 70)
	_pv_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_box.visible = false
	_pv.add_child(_pv_box)
	_pv_line = Label.new()
	_pv_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pv_line.add_theme_font_size_override("font_size", 14)
	_pv_box.add_child(_pv_line)
	for nl in _pv_names:
		_pv.move_child(nl, -1)
	_pv_caption = _pv_label(14, Color(0.95, 0.93, 0.86))
	_pv_caption.size = Vector2(PREVIEW_SIZE.x, 24)
	_pv_caption.position = Vector2(0, PREVIEW_SIZE.y * 0.7)
	_pv_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pv_note = _pv_label(14, Color(0.7, 1.0, 0.7))
	_pv_note.position = Vector2(12, 34)
	_pv_fade = ColorRect.new()
	_pv_fade.color = Color.BLACK
	_pv_fade.size = PREVIEW_SIZE
	_pv_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_fade.modulate.a = 0.0
	_pv.add_child(_pv_fade)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(side)
	_pv_state = Label.new()
	_pv_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pv_state.text = "▶ 미리보기를 누르면 여기서 재생합니다.\n화면을 클릭하거나 E/Space = 다음.\n인물 이동·바라보기·플래그는 글로만 표시 — 실제 움직임은 '게임에서 실행'."
	side.add_child(_pv_state)
	_btn(side, "다음 (E / Space)", preview_next)


func _pv_label(fs: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv.add_child(l)
	return l


func _flat(bg: Color, border := Color.TRANSPARENT, w := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	return sb


# ---------------------------------------------------------------- list / files

func refresh_list() -> void:
	_fill_list()
	_fill_story()


func _fill_list() -> void:
	_list.clear()
	var all := CutsceneData.all()
	_ids = all.keys()
	_ids.sort()
	var story := CutsceneData.new_game_cutscenes()
	var q := _search.text.strip_edges().to_lower()
	for id: String in _ids:
		var d: Dictionary = all[id]
		var hay := "%s %s %s" % [id, d.get("title", ""), JSON.stringify(d.get("steps", []))]
		if q != "" and not hay.to_lower().contains(q):
			continue
		var mark := "★ " if id in story else ""
		_list.add_item("%s%s\n  %s" % [mark, id, d.get("title", "")])
		_list.set_item_metadata(_list.item_count - 1, id)
		if id == str(doc.get("cutscene_id", "")):
			_list.select(_list.item_count - 1)


func _fill_story() -> void:
	_story_list.clear()
	var all := CutsceneData.all()
	var i := 1
	for id: String in CutsceneData.new_game_cutscenes():
		_story_list.add_item("%d. %s%s" % [i, id, "" if all.has(id) else "  ⚠ 파일 없음"])
		i += 1


func _on_pick(id: String) -> void:
	if id == str(doc.get("cutscene_id", "")):
		return
	if dirty:
		_ask("'%s'의 저장하지 않은 변경을 버리고 열까요?" % doc.get("cutscene_id", ""), func() -> void: open_cutscene(id, true))
		_fill_list()
		return
	open_cutscene(id)


func open_cutscene(id: String, force := false) -> bool:
	if dirty and not force:
		return false
	var d := CutsceneData.load_cutscene(id)
	if d.is_empty():
		_set_status("컷씬 파일을 찾을 수 없음: " + id)
		return false
	preview_stop()
	doc = d
	path = CutsceneData.path_for(id)
	_mtime = FileAccess.get_modified_time(path)
	selected = -1
	_reset_history()
	_rebuild_steps()
	_show_inspector()
	validate(false)
	_fill_list()
	_set_status("열림: " + path)
	return true


func create_cutscene(id: String, title: String) -> bool:
	if not CutsceneData.valid_cutscene_id(id):
		_ask_info("cutscene_id는 영문·숫자·._ 만 쓸 수 있습니다.")
		return false
	if FileAccess.file_exists(CutsceneData.path_for(id)):
		_ask_info("이미 있는 ID입니다: " + id)
		return false
	preview_stop()
	doc = CutsceneData.new_doc(id, title)
	path = ""
	selected = -1
	_reset_history()
	dirty = true
	_rebuild_steps()
	_show_inspector()
	validate(false)
	_update_status()
	return true


func _ask_new() -> void:
	_new_id.text = "cutscene."
	_new_title.text = ""
	_new_dialog.popup_centered()
	_new_id.grab_focus()
	_new_id.caret_column = _new_id.text.length()


func _duplicate_cutscene() -> void:
	if doc.is_empty():
		return
	var base := str(doc["cutscene_id"]) + "_copy"
	var id := base
	var n := 2
	while FileAccess.file_exists(CutsceneData.path_for(id)):
		id = "%s%d" % [base, n]
		n += 1
	var copy: Dictionary = doc.duplicate(true)
	copy["cutscene_id"] = id
	copy["title"] = str(copy.get("title", "")) + " (복사)"
	doc = copy
	path = ""
	_reset_history()
	dirty = true
	_rebuild_steps()
	_show_inspector()
	_update_status()
	_set_status("복제됨 — 저장하면 %s 로 만들어집니다" % id)


func save(skip_errors := false, skip_conflict := false) -> bool:
	if doc.is_empty():
		return false
	var id := str(doc["cutscene_id"])
	if not CutsceneData.valid_cutscene_id(id):
		_ask_info("cutscene_id가 올바르지 않습니다.")
		return false
	var target := CutsceneData.path_for(id)
	var errors := validate(false)
	if errors > 0 and not skip_errors:
		_ask("오류 %d개가 있습니다 (검증 탭). 그래도 저장할까요?" % errors, func() -> void: save(true, skip_conflict))
		_tabs.current_tab = 1
		return false
	if not skip_conflict and path == target and FileAccess.file_exists(target) and FileAccess.get_modified_time(target) != _mtime:
		_ask("'%s' 파일이 에디터 밖에서 바뀌었습니다. 덮어쓸까요? (이전 내용은 백업됨)" % target.get_file(), func() -> void: save(true, true))
		return false
	if path != target and path == "" and FileAccess.file_exists(target):
		_ask_info("이미 있는 ID입니다: " + id)
		return false
	if FileAccess.file_exists(target):
		_backup(id, FileAccess.get_file_as_string(target))
	var err := CutsceneData.save_cutscene(doc, target)
	if err != OK:
		_ask_info("저장 실패 (%s): %s" % [error_string(err), target])
		return false
	if path != "" and path != target and FileAccess.file_exists(path):
		var old := path.get_file().get_basename()
		_backup(old, FileAccess.get_file_as_string(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))  # cutscene_id was renamed
		var story := CutsceneData.new_game_cutscenes()
		if old in story:
			story[story.find(old)] = id
			CutsceneData.set_new_game_cutscenes(story)
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
	play_requested.emit(str(doc["cutscene_id"]))


# ---------------------------------------------------------------- new-game story order

func story_add(id: String) -> void:
	if id == "":
		return
	if dirty and path == "":
		_ask_info("먼저 저장하세요 (아직 파일이 없는 컷씬).")
		return
	var s := CutsceneData.new_game_cutscenes()
	if id in s:
		_set_status("이미 새 게임 순서에 있음: " + id)
		return
	s.append(id)
	CutsceneData.set_new_game_cutscenes(s)
	refresh_list()
	saved.emit(CutsceneData.STORY_PATH)


func story_move(d: int) -> void:
	var sel := _story_list.get_selected_items()
	if sel.is_empty():
		return
	var i := sel[0]
	var s := CutsceneData.new_game_cutscenes()
	var j := i + d
	if j < 0 or j >= s.size():
		return
	var t: Variant = s[i]
	s[i] = s[j]
	s[j] = t
	CutsceneData.set_new_game_cutscenes(s)
	_fill_story()
	_story_list.select(j)
	saved.emit(CutsceneData.STORY_PATH)


func story_remove() -> void:
	var sel := _story_list.get_selected_items()
	if sel.is_empty():
		return
	var s := CutsceneData.new_game_cutscenes()
	s.remove_at(sel[0])
	CutsceneData.set_new_game_cutscenes(s)
	refresh_list()
	saved.emit(CutsceneData.STORY_PATH)


# ---------------------------------------------------------------- steps

func _step_count() -> int:
	return (doc.get("steps", []) as Array).size()


func _rebuild_steps() -> void:
	_steps.clear()
	var bad := {}
	for it: Dictionary in issues:
		if int(it["step"]) >= 0:
			bad[int(it["step"])] = it["severity"]
	for i in _step_count():
		var s: Dictionary = doc["steps"][i]
		var t := str(s.get("type", ""))
		var mark := ("⛔ " if bad[i] == "error" else "⚠ ") if bad.has(i) else ""
		_steps.add_item("%2d. %s%s" % [i + 1, mark, CutsceneData.step_text(s)])
		_steps.set_item_custom_fg_color(i, (TYPE_COLORS.get(t, Color.WHITE) as Color).lightened(0.2))
		if i == preview_step and previewing:
			_steps.set_item_custom_bg_color(i, Color(0.25, 0.32, 0.18))
	if selected >= 0 and selected < _step_count():
		_steps.select(selected)
		_steps.ensure_current_is_visible()


func select_step(i: int, sync_list := true) -> void:
	selected = i if i >= 0 and i < _step_count() else -1
	if sync_list:
		if selected >= 0:
			_steps.select(selected)
			_steps.ensure_current_is_visible()
		else:
			_steps.deselect_all()
	_show_inspector()


func add_step(t: String) -> int:
	if doc.is_empty():
		return -1
	var at := selected + 1 if selected >= 0 else _step_count()
	var s := CutsceneData.new_step(t)
	if t == "line":
		for j in range(at - 1, -1, -1):  # same speaker as the line before
			if doc["steps"][j].get("type", "") == "line":
				s["speaker_id"] = doc["steps"][j].get("speaker_id", "player")
				break
	if t == "image":
		s["path"] = CutsceneData.ILLUSTRATION_DIR.path_join("")
	(doc["steps"] as Array).insert(at, s)
	selected = at
	_commit("add")
	_rebuild_steps()
	_show_inspector()
	return at


func delete_step(i: int) -> void:
	if i < 0 or i >= _step_count():
		return
	(doc["steps"] as Array).remove_at(i)
	selected = mini(i, _step_count() - 1)
	_commit("delete")
	_rebuild_steps()
	_show_inspector()


func duplicate_step(i: int) -> void:
	if i < 0 or i >= _step_count():
		return
	(doc["steps"] as Array).insert(i + 1, (doc["steps"][i] as Dictionary).duplicate(true))
	selected = i + 1
	_commit("duplicate")
	_rebuild_steps()
	_show_inspector()


func move_step(i: int, d: int) -> void:
	var j := i + d
	if i < 0 or j < 0 or j >= _step_count():
		return
	var arr: Array = doc["steps"]
	var t: Variant = arr[i]
	arr[i] = arr[j]
	arr[j] = t
	selected = j
	_commit("move")
	_rebuild_steps()
	_show_inspector()


## After a field edit: record undo, refresh the list row (and the inspector if fields depend on it).
func _edited(field: String, reinspect := false) -> void:
	_commit("edit:%d:%s" % [selected, field])
	_rebuild_steps()
	if reinspect:
		_show_inspector.call_deferred()


# ---------------------------------------------------------------- history

func _reset_history() -> void:
	_undo.clear()
	_redo.clear()
	_snap = var_to_str(doc)
	_commit_key = ""
	dirty = false
	_update_status()


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
	if selected >= _step_count():
		selected = _step_count() - 1
	validate(false)
	_rebuild_steps()
	_show_inspector()
	_update_status()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is TextEdit or focus is LineEdit or focus is SpinBox
	if previewing and not typing and k.keycode in [KEY_E, KEY_SPACE, KEY_ENTER]:
		preview_next()
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_DELETE and focus == _steps:
		delete_step(selected)
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


# ---------------------------------------------------------------- inspector

func _clear_inspector() -> void:
	for c in _inspector.get_children():
		_inspector.remove_child(c)
		c.queue_free()


func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_inspector.add_child(l)


func _field_label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.86))
	_inspector.add_child(l)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.62, 0.66, 0.7))
	_inspector.add_child(l)


func _show_inspector() -> void:
	_clear_inspector()
	if doc.is_empty():
		_note("왼쪽 목록에서 컷씬을 고르거나 '새 컷씬'을 누르세요.\n대화의 '컷씬 호출' 노드, 새 게임 순서, '게임에서 실행'이 이 파일들을 재생합니다.")
		return
	_heading("컷씬 정보")
	_field_label("cutscene_id (저장하면 파일 이름이 됨)")
	var idl := LineEdit.new()
	idl.text = str(doc["cutscene_id"])
	idl.text_changed.connect(func(v: String) -> void:
		doc["cutscene_id"] = v.strip_edges()
		_commit("id")
		_update_status())
	_inspector.add_child(idl)
	_field_label("제목")
	var tl := LineEdit.new()
	tl.text = str(doc.get("title", ""))
	tl.text_changed.connect(func(v: String) -> void:
		doc["title"] = v
		_commit("title"))
	_inspector.add_child(tl)
	var sk := CheckBox.new()
	sk.text = "ESC로 건너뛸 수 있음"
	sk.button_pressed = bool(doc.get("skippable", true))
	sk.toggled.connect(func(on: bool) -> void:
		doc["skippable"] = on
		_commit("skippable"))
	_inspector.add_child(sk)
	_field_label("메모 (게임에 안 나옴)")
	var nt := TextEdit.new()
	nt.text = str(doc.get("notes", ""))
	nt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	nt.custom_minimum_size.y = 60
	nt.text_changed.connect(func() -> void:
		doc["notes"] = nt.text
		_commit("notes"))
	_inspector.add_child(nt)
	_inspector.add_child(HSeparator.new())
	if selected < 0 or selected >= _step_count():
		_note("단계를 고르면 여기서 편집합니다. '단계 추가'는 선택한 단계 다음에 넣습니다.\n두 번 클릭하면 그 단계부터 미리보기.")
		return
	var s: Dictionary = doc["steps"][selected]
	var t := str(s.get("type", ""))
	_heading("%d. %s" % [selected + 1, CutsceneData.STEPS.get(t, {}).get("label", t)])
	for f: Dictionary in CutsceneData.STEPS.get(t, {}).get("fields", []):
		_field_label(f["label"])
		_inspector.add_child(_field_widget(f, s))
	match t:
		"narration":
			_note("화면 가운데 띠 위에 글자가 한 자씩 나옵니다. 키를 누르면 바로 다 나오고, 한 번 더 누르면 다음.")
		"line":
			_note("초상화 대화창: 주인공은 왼쪽, 상대는 오른쪽. 그림은 assets/portraits/<화자>.png, 표정은 <화자>_<표정>.png.")
		"image":
			_note("전체 화면 삽화 (16:9, 넘치면 잘림). 파일이 없으면 게임에서 '삽화 자리' 카드가 나옵니다.")
			_inspector.add_child(_thumb(str(s.get("path", ""))))
		"fade":
			_note("컷씬이 검은 화면으로 끝나면 자동으로 밝아집니다 (새 게임 순서 중간은 다음 컷씬이 밝힘).")
		"actor_move":
			_note("목적지가 인물이면 그 인물 위치 + 거리. 자기 자신을 고르면 지금 자리에서 그만큼 걸어감. 카메라는 그대로.")
	for it: Dictionary in issues:
		if int(it["step"]) == selected:
			_note(("⛔ " if it["severity"] == "error" else "⚠ ") + it["message"])


func _thumb(p: String) -> Control:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(320, 180)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = load(p) as Texture2D if p != "" and ResourceLoader.exists(p) else null
	return tr


func _options(opts: Array, current: String, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.clip_text = true
	var found := -1
	for i in opts.size():
		ob.add_item(str(opts[i][1]))
		ob.set_item_metadata(i, opts[i][0])
		if str(opts[i][0]) == current:
			found = i
	if found < 0:
		ob.add_item("⚠ %s (없음)" % current if current != "" else "(선택하세요)")
		ob.set_item_metadata(ob.item_count - 1, current)
		found = ob.item_count - 1
	ob.selected = found
	ob.item_selected.connect(func(i: int) -> void: on_pick.call(ob.get_item_metadata(i)))
	return ob


func _spin(v: float, lo: float, hi: float, stp: float, on_change: Callable) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = lo
	sp.max_value = hi
	sp.step = stp
	sp.allow_greater = true
	sp.allow_lesser = lo < 0.0
	sp.value = v
	sp.value_changed.connect(on_change)
	return sp


## Widget for one field of a step (CutsceneData.STEPS); writes straight into the step.
func _field_widget(f: Dictionary, s: Dictionary) -> Control:
	var key: String = f["name"]
	var val: Variant = s.get(key, f.get("default", ""))
	match f["type"]:
		"text":
			var te := TextEdit.new()
			te.text = str(val)
			te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			te.custom_minimum_size.y = 110
			te.text_changed.connect(func() -> void:
				s[key] = te.text
				_edited(key))
			return te
		"line":
			var le := LineEdit.new()
			le.text = str(val)
			le.text_changed.connect(func(v: String) -> void:
				s[key] = v
				_edited(key))
			return le
		"float":
			return _spin(float(val), 0.0, 60.0, 0.1, func(v: float) -> void:
				s[key] = snappedf(v, 0.01)
				_edited(key))
		"bool":
			var cb := CheckBox.new()
			cb.text = "예"
			cb.button_pressed = bool(val)
			cb.toggled.connect(func(on: bool) -> void:
				s[key] = on
				_edited(key))
			return cb
		"enum":
			return _options(f["options"], str(val), func(v: Variant) -> void:
				s[key] = str(v)
				_edited(key))
		"speaker":
			var opts := []
			var sp: Dictionary = DialogueData.speakers()
			for id: String in sp:
				opts.append([id, "%s (%s)" % [sp[id].get("name", ""), id] if str(sp[id].get("name", "")) != "" else "(이름 없음) (%s)" % id])
			return _options(opts, str(val), func(v: Variant) -> void:
				s[key] = str(v)
				if not DialogueData.speaker_expressions(str(v)).has(str(s.get("expression", ""))):
					s["expression"] = ""  # that speaker has no such face
				_edited(key, true))
		"expression":
			var opts := [["", "기본"]]
			var exs := DialogueData.speaker_expressions(str(s.get("speaker_id", "")))
			for ex: String in exs:
				opts.append([ex, "%s (%s)" % [exs[ex], ex]])
			return _options(opts, str(val), func(v: Variant) -> void:
				s[key] = str(v)
				_edited(key))
		"quest":
			var qopts := []
			var qs: Dictionary = QuestDB.all()
			for qid: String in qs:
				qopts.append([qid, "%s (%s)" % [qs[qid].get("title", qid), qid]])
			return _options(qopts, str(val), func(v: Variant) -> void:
				s[key] = str(v)
				_edited(key))
		"actor":
			return _options(_actor_opts(), str(val), func(v: Variant) -> void:
				s[key] = str(v)
				_edited(key))
		"target":
			var box := VBoxContainer.new()
			var opts := _actor_opts()
			opts.append(["@point", "좌표 지정 (x, z)"])
			box.add_child(_options(opts, "@point" if val is Array else str(val), func(v: Variant) -> void:
				s[key] = [0, 0] if str(v) == "@point" else str(v)
				_edited(key, true)))
			if val is Array:
				box.add_child(_vec2_row(s, key))
			return box
		"vec2":
			return _vec2_row(s, key)
		"image":
			var row := HBoxContainer.new()
			var le := LineEdit.new()
			le.text = str(val)
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_changed.connect(func(v: String) -> void:
				s[key] = v.strip_edges()
				_edited(key))
			le.text_submitted.connect(func(_v: String) -> void: _show_inspector())
			row.add_child(le)
			var b := Button.new()
			b.text = "찾기…"
			b.pressed.connect(func() -> void:
				_file_target = selected
				_file_dialog.popup_centered_ratio(0.6))
			row.add_child(b)
			return row
	var l := Label.new()
	l.text = "(편집 불가 필드 %s)" % f["type"]
	return l


func _vec2_row(s: Dictionary, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var v: Array = s.get(key, [0, 0]) if s.get(key) is Array else [0, 0]
	for axis in 2:
		var ax := axis
		var l := Label.new()
		l.text = "x" if axis == 0 else "z"
		row.add_child(l)
		row.add_child(_spin(float(v[axis]), -200.0, 200.0, 0.1, func(nv: float) -> void:
			var arr: Array = s.get(key, [0, 0]) if s.get(key) is Array else [0, 0]
			arr[ax] = snappedf(nv, 0.01)
			s[key] = arr
			_edited(key)))
	return row


func _actor_opts() -> Array:
	var out := []
	for id: String in CutsceneData.actor_ids():
		out.append([id, "%s (%s)" % [CutsceneData.actor_name(id), id]])
	return out


# ---------------------------------------------------------------- validation

func validate(show := false) -> int:
	issues = CutsceneData.validate(doc) if not doc.is_empty() else []
	_issue_list.clear()
	var errors := 0
	for it: Dictionary in issues:
		var err: bool = it["severity"] == "error"
		errors += 1 if err else 0
		var where := "단계 %d" % (int(it["step"]) + 1) if int(it["step"]) >= 0 else "컷씬"
		_issue_list.add_item("%s %s: %s" % ["⛔" if err else "⚠", where, it["message"]])
		_issue_list.set_item_metadata(_issue_list.item_count - 1, int(it["step"]))
	if issues.is_empty():
		_issue_list.add_item("문제 없음")
		_issue_list.set_item_metadata(0, -1)
	if show:
		_tabs.current_tab = 1
	_rebuild_steps()
	_update_status()
	return errors


# ---------------------------------------------------------------- preview

func preview_start(from := 0) -> void:
	if doc.is_empty():
		return
	preview_stop()
	await get_tree().process_frame
	_tabs.current_tab = 0
	_pv_reset()
	previewing = true
	_pv_stop = false
	var steps: Array = doc["steps"]
	# the screen as it would be at `from`: apply earlier screen-state steps instantly
	for i in range(0, mini(from, steps.size())):
		_pv_apply_state(steps[i])
	for i in range(from, steps.size()):
		if _pv_stop:
			break
		preview_step = i
		_rebuild_steps()
		_pv_state.text = "미리보기 %d / %d — %s\n클릭 / E / Space = 다음" % [i + 1, steps.size(), CutsceneData.step_text(steps[i])]
		_pv_advance = false
		await _pv_play(steps[i])
	previewing = false
	preview_step = -1
	if not _pv_stop:
		_pv_state.text = "미리보기 끝 (%d단계)" % steps.size()
	_rebuild_steps()


func preview_stop() -> void:
	_pv_stop = true
	_pv_advance = true
	previewing = false
	preview_step = -1


func preview_next() -> void:
	_pv_advance = true


func _pv_reset() -> void:
	_pv_image.visible = false
	_pv_placeholder.visible = false
	_pv_narr.visible = false
	_pv_box.visible = false
	for p in _pv_portraits:
		p.visible = false
	for n in _pv_names:
		n.visible = false
	for b in _pv_bars:
		b.visible = false
	_pv_fade.modulate.a = 0.0
	_pv_caption.text = ""
	_pv_note.text = ""


func _pv_apply_state(s: Dictionary) -> void:
	match s.get("type", ""):
		"fade":
			_pv_fade.modulate.a = 1.0 if s.get("to", "black") == "black" else 0.0
		"image":
			_pv_show_image(str(s.get("path", "")))
		"letterbox":
			for b in _pv_bars:
				b.visible = bool(s.get("on", true))


func _pv_show_image(p: String) -> void:
	var tex: Texture2D = load(p) as Texture2D if p != "" and ResourceLoader.exists(p) else null
	_pv_image.texture = tex
	_pv_image.visible = tex != null
	_pv_placeholder.visible = p != "" and tex == null
	_pv_placeholder.text = "\n삽화 자리 — " + p.get_file()


func _pv_wait(t: float) -> void:
	var left := t
	while left > 0.0 and not _pv_advance and not _pv_stop:
		await get_tree().process_frame
		left -= get_process_delta_time()


func _pv_wait_key() -> void:
	while not _pv_advance and not _pv_stop:
		await get_tree().process_frame


func _pv_play(s: Dictionary) -> void:
	_pv_note.text = ""
	match s.get("type", ""):
		"fade":
			var tw := create_tween()
			tw.tween_property(_pv_fade, "modulate:a", 1.0 if s.get("to", "black") == "black" else 0.0, maxf(float(s.get("seconds", 1.0)), 0.01))
			while tw.is_running() and not _pv_stop:
				if _pv_advance:
					tw.custom_step(100.0)
					break
				await get_tree().process_frame
		"image":
			_pv_show_image(str(s.get("path", "")))
			await _pv_wait(float(s.get("seconds", 0.6)))
		"narration":
			_pv_narr.text = str(s.get("text", ""))
			_pv_narr.visible = true
			_pv_narr.visible_ratio = 0.0
			var n := maxf(float(_pv_narr.text.length()), 1.0)
			while _pv_narr.visible_ratio < 1.0 and not _pv_advance and not _pv_stop:
				await get_tree().process_frame
				_pv_narr.visible_ratio = minf(1.0, _pv_narr.visible_ratio + get_process_delta_time() * TYPE_CPS / n)
			_pv_narr.visible_ratio = 1.0
			_pv_advance = false
			var secs := float(s.get("seconds", 0.0))
			if secs > 0.0:
				await _pv_wait(secs)
			else:
				await _pv_wait_key()
			_pv_narr.visible = false
		"line":
			var sp := str(s.get("speaker_id", ""))
			var right := sp not in ["", "player", "narrator"]
			_pv_portrait(0, "player", str(s.get("expression", "")) if sp == "player" else "", sp == "player")
			if right:
				_pv_portrait(1, sp, str(s.get("expression", "")), true)
			else:
				_pv_portraits[1].visible = false
				_pv_names[1].visible = false
			_pv_line.text = str(s.get("text", ""))
			_pv_box.visible = true
			await _pv_wait_key()
			_pv_box.visible = false
			for i in 2:
				_pv_portraits[i].visible = false
				_pv_names[i].visible = false
		"caption":
			_pv_caption.text = str(s.get("text", ""))
			await _pv_wait(float(s.get("seconds", 2.0)))
			_pv_caption.text = ""
		"wait":
			await _pv_wait(float(s.get("seconds", 0.5)))
		"letterbox":
			for b in _pv_bars:
				b.visible = bool(s.get("on", true))
			await _pv_wait(0.3)
		"actor_move", "actor_face", "set_flag":
			_pv_note.text = "(게임에서) " + CutsceneData.step_text(s)
			await _pv_wait(0.9)


func _pv_portrait(i: int, sp: String, expr: String, lit: bool) -> void:
	var base := _portrait_base(sp)
	var p := base
	if expr != "":
		var alt := "%s_%s.%s" % [base.get_basename(), expr, base.get_extension()]
		if ResourceLoader.exists(alt):
			p = alt
	var tex: Texture2D = load(p) as Texture2D if ResourceLoader.exists(p) else null
	var tr := _pv_portraits[i]
	tr.texture = tex
	tr.visible = true
	tr.modulate.a = 1.0 if lit else 0.5
	if tex == null:  # no portrait yet: a plain block like the game's placeholder
		var g := Gradient.new()
		g.set_color(0, Color(0.45, 0.5, 0.75))
		g.set_color(1, Color(0.35, 0.4, 0.65))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 140
		gt.height = 160
		tr.texture = gt
	var nl := _pv_names[i]
	nl.text = DialogueData.speaker_name(sp)
	nl.visible = nl.text != ""
	nl.position = Vector2(tr.position.x + 30, PREVIEW_SIZE.y - 24)
	nl.modulate.a = 1.0 if lit else 0.5


static func _portrait_base(sp: String) -> String:
	return str(DialogueData.speakers().get(sp, {}).get("portrait", "res://assets/portraits/%s.png" % sp))


# ---------------------------------------------------------------- status / dialogs

func _update_status() -> void:
	if not is_instance_valid(_status):
		return
	if doc.is_empty():
		_status.text = "컷씬을 열거나 새로 만드세요."
		return
	var errs := 0
	var warns := 0
	for it: Dictionary in issues:
		if it["severity"] == "error":
			errs += 1
		else:
			warns += 1
	_status.text = "%s%s — %s · 단계 %d · 오류 %d · 경고 %d%s" % [doc.get("cutscene_id", ""), " *" if dirty else "",
		doc.get("title", ""), _step_count(), errs, warns, " · ★ 새 게임 순서" if str(doc.get("cutscene_id", "")) in CutsceneData.new_game_cutscenes() else ""]
	if _play_button:
		_play_button.disabled = not can_play_in_game


func _set_status(text: String) -> void:
	_update_status()
	_status.text += "   |   " + text


func _ask(text: String, cb: Callable) -> void:
	_confirm.dialog_text = text
	_confirm_cb = cb
	_confirm.popup_centered()


func _ask_info(text: String) -> void:
	_ask(text, Callable())
