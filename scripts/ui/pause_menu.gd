class_name PauseMenu
extends Control
## ESC menu: continue, save now into this character's slot, back to the title, quit. Leaving saves
## first; where saving is not allowed (in the rift, while driving, ...) leaving asks twice because
## progress since the last save would be lost.

var boot: Node
var _status: Label
var _result: Label
var _save_btn: Button
var _title_btn: Button
var _quit_btn: Button
var _confirm := ""


func _ready() -> void:
	size = Vector2(1920, 1080)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = size
	add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.075, 0.1, 0.96)
	sb.border_color = Color(0.62, 0.5, 0.32)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size.x = 620
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := Label.new()
	head.text = "일시정지"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 34)
	head.add_theme_color_override("font_color", Color(1.0, 0.86, 0.58))
	v.add_child(head)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 576
	_status.add_theme_font_size_override("font_size", 19)
	_status.add_theme_color_override("font_color", Color(0.82, 0.82, 0.78))
	v.add_child(_status)
	v.add_child(_button("계속 (ESC)", func() -> void: boot.set_paused(false)))
	_save_btn = _button("지금 저장", _on_save)
	v.add_child(_save_btn)
	_title_btn = _button("타이틀로", func() -> void: _leave("title"))
	v.add_child(_title_btn)
	_quit_btn = _button("게임 종료", func() -> void: _leave("quit"))
	v.add_child(_quit_btn)
	_result = Label.new()
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_font_size_override("font_size", 19)
	_result.add_theme_color_override("font_color", Color(0.7, 1.0, 0.65))
	v.add_child(_result)
	panel.reset_size()
	panel.position = Vector2(960 - panel.size.x * 0.5, 300)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size.y = 50
	b.pressed.connect(cb)
	return b


func open() -> void:
	_confirm = ""
	_result.text = ""
	refresh()


func refresh() -> void:
	var why: String = boot.save_block()
	var lines := PackedStringArray()
	if Game.slot > 0:
		var m: Dictionary = SaveManager.read(Game.slot).get("meta", {})
		lines.append("슬롯 %d · 플레이 %s · 마지막 저장 %s" % [Game.slot, TitleScreen.play_time_text(Game.play_seconds), m.get("saved_at", "없음")])
	lines.append("저장할 수 없음: " + why if why != "" else "자동 저장: 수면 · 지역 이동 · 깨어날 때 · 5분마다 · 창을 닫을 때")
	_status.text = "\n".join(lines)
	_save_btn.disabled = why != ""
	var lose := why != "" and Game.slot > 0
	_title_btn.text = "정말 타이틀로? 마지막 저장 이후 진행은 사라짐" if _confirm == "title" else ("타이틀로 (저장 안 됨)" if lose else "저장하고 타이틀로")
	_quit_btn.text = "정말 종료? 마지막 저장 이후 진행은 사라짐" if _confirm == "quit" else ("게임 종료 (저장 안 됨)" if lose else "저장하고 게임 종료")


func _on_save() -> void:
	var why: String = boot.save_game("manual")
	_result.text = "저장했다 — 슬롯 %d" % Game.slot if why == "" else why
	refresh()


func _leave(where: String) -> void:
	var why: String = boot.save_block()
	if why != "" and Game.slot > 0 and _confirm != where:
		_confirm = where
		refresh()
		return
	if why == "":
		boot.save_game("manual")
	if where == "title":
		boot.to_title()
	else:
		get_tree().quit()
