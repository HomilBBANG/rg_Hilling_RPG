@tool
class_name EditorWidgets
extends RefCounted
## Small controls shared by the editor tabs: the flag / event picker (a list of every known flag
## with where it comes from, plus a box for a new name and an explanation underneath), the
## "플래그 목록" dialog, and the ❓ 도움말 button.


## A flag field: pick from the list or type a new name; the line underneath says what the flag
## means, who turns it on and who reads it. kind = "flag" | "event" (event ids without "event.").
## on_change(value: String) is called with the new text.
static func flag_picker(current: String, on_change: Callable, kind := "flag") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	box.add_child(row)
	var le := LineEdit.new()
	le.text = current
	le.placeholder_text = "새 이름 (예: story.met_rosa)" if kind == "flag" else "새 이벤트 이름 (예: story.cat_meeting)"
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.72, 0.78, 0.7))
	var refresh := func(v: String) -> void:
		info.text = FlagCatalog.describe(("event." + v) if kind == "event" and v != "" else v)
	var ob := OptionButton.new()
	ob.fit_to_longest_item = false
	ob.clip_text = true
	ob.custom_minimum_size.x = 150
	ob.add_item("목록에서 고르기…")
	ob.set_item_metadata(0, "")
	var ids := FlagCatalog.event_ids() if kind == "event" else FlagCatalog.names()
	for f: String in ids:
		var full := ("event." + f) if kind == "event" else f
		var e: Dictionary = FlagCatalog.all().get(full, {})
		var d := str(e.get("desc", "")) if not e.is_empty() else ""
		ob.add_item("%s — %s" % [f, d] if d != "" and d != "이벤트" else f)
		ob.set_item_metadata(ob.item_count - 1, f)
		ob.set_item_tooltip(ob.item_count - 1, FlagCatalog.describe(full))
	ob.item_selected.connect(func(i: int) -> void:
		var v := str(ob.get_item_metadata(i))
		if v != "":
			le.text = v
			refresh.call(v)
			on_change.call(v)
		ob.select(0))
	row.add_child(ob)
	row.add_child(le)
	le.text_changed.connect(func(v: String) -> void:
		refresh.call(v.strip_edges())
		on_change.call(v.strip_edges()))
	box.add_child(info)
	refresh.call(current)
	return box


## A window listing every flag with where it is set and read.
static func show_flag_list(parent: Node) -> AcceptDialog:
	var dlg := AcceptDialog.new()
	dlg.title = "플래그 목록 — 어디서 켜지고 어디서 쓰이나"
	dlg.ok_button_text = "닫기"
	var v := VBoxContainer.new()
	dlg.add_child(v)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = ("플래그는 '이야기가 여기까지 왔다'를 기억하는 이름표입니다 (켜짐/꺼짐, 저장됨).\n"
		+ "켜는 곳: 게임 코드 · 대화 액션 '플래그 설정' · 컷씬 단계 '플래그 설정' · 지역의 이야기 장소(밟으면).\n"
		+ "쓰는 곳: 대화 조건 '플래그가 켜져 있다' · 선택지 조건 · 퀘스트 목표 '플래그'.\n"
		+ "이벤트(event.…)는 한 번만 기록되는 플래그: 대화 종료 노드의 '완료 기록할 이벤트'나 액션 '이벤트 완료 기록'이 켜고, 조건 '이벤트 완료됨'이 읽습니다.\n"
		+ "⚠ '켜는 곳 없음'인 플래그는 절대 켜지지 않으니 어딘가에서 켜 줘야 합니다.")
	v.add_child(intro)
	var search := LineEdit.new()
	search.placeholder_text = "찾기"
	search.clear_button_enabled = true
	v.add_child(search)
	var tree := Tree.new()
	tree.columns = 4
	tree.set_column_titles_visible(true)
	tree.set_column_title(0, "플래그")
	tree.set_column_title(1, "뜻 / 종류")
	tree.set_column_title(2, "켜는 곳")
	tree.set_column_title(3, "쓰는 곳")
	tree.set_column_expand(0, false)
	tree.set_column_custom_minimum_width(0, 220)
	tree.set_column_custom_minimum_width(1, 180)
	tree.custom_minimum_size = Vector2(1100, 520)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tree)
	var fill := func(filter: String) -> void:
		tree.clear()
		var root := tree.create_item()
		var cat := FlagCatalog.all()
		var keys := cat.keys()
		keys.sort()
		for f: String in keys:
			var e: Dictionary = cat[f]
			var set_s := ", ".join(e["set_by"]) if not (e["set_by"] as PackedStringArray).is_empty() else "⚠ 없음"
			var used_s := ", ".join(e["used_by"]) if not (e["used_by"] as PackedStringArray).is_empty() else "—"
			var hay := (f + " " + str(e["desc"]) + " " + set_s + " " + used_s).to_lower()
			if filter != "" and not hay.contains(filter.to_lower()):
				continue
			var it := tree.create_item(root)
			it.set_text(0, f)
			it.set_text(1, "%s [%s]" % [e["desc"], e["origin"]] if str(e["desc"]) != "" else "[%s]" % e["origin"])
			it.set_text(2, set_s)
			it.set_text(3, used_s)
			it.set_tooltip_text(2, set_s)
			it.set_tooltip_text(3, used_s)
			if (e["set_by"] as PackedStringArray).is_empty():
				it.set_custom_color(2, Color(1.0, 0.55, 0.5))
	search.text_changed.connect(func(t: String) -> void: fill.call(t))
	fill.call("")
	parent.add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	return dlg


## ❓ 도움말 button that opens EditorHelp for a topic.
static func help_button(parent: Control, topic: String) -> Button:
	var b := Button.new()
	b.text = "❓ 도움말"
	b.tooltip_text = "이 탭 쓰는 법 (쉬운 설명)"
	b.pressed.connect(func() -> void: EditorHelp.show(parent, topic))
	parent.add_child(b)
	return b


## A one-line "how this tab works" strip under the toolbar.
static func quick_guide(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
	l.add_theme_font_size_override("font_size", 12)
	parent.add_child(l)
	return l
