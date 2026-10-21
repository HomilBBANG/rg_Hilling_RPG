class_name TitleScreen
extends Control
## Title screen over the key art (assets/ui/title_background.webp): 새 게임 / 불러오기 / 설정 / 종료
## in the empty space under the painted title on the left. Save slots (SaveManager): one slot = one
## character — 새 게임 claims an empty slot and that character keeps saving into it, 불러오기
## continues (or deletes, asking twice) a used slot. The world behind stays frozen (tree paused).

const BACKGROUND := preload("res://assets/ui/title_background.webp")
const MENU_POS := Vector2(196, 600)  # under the painted "DENIAL" and its subtitle
const CREAM := Color(0.96, 0.92, 0.82)
const HOVER := Color(1.0, 0.7, 0.66)  # the desk lamp's pink

var boot: Node
var mode := ""  # "" main menu, "new", "load", "settings"
var _menu: VBoxContainer
var _panel: PanelContainer
var _head: Label
var _body: VBoxContainer
var _note: Label
var _confirm_delete := 0


func _ready() -> void:
	size = Vector2(1920, 1080)
	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.size = size
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(bg)
	_menu = VBoxContainer.new()
	_menu.position = MENU_POS
	_menu.add_theme_constant_override("separation", 6)
	add_child(_menu)
	_menu.add_child(_menu_button("새 게임", func() -> void: open_slots("new")))
	_menu.add_child(_menu_button("불러오기", func() -> void: open_slots("load")))
	_menu.add_child(_menu_button("설정", func() -> void: open_settings()))
	_menu.add_child(_menu_button("종료", func() -> void: get_tree().quit()))
	_build_panel()


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(300, 62)
	b.add_theme_font_size_override("font_size", 38)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.1, 0.8))
	for st in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(st, CREAM)
	for st in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(st, HOVER)
	var none := StyleBoxEmpty.new()
	none.content_margin_left = 18
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.04, 0.03, 0.09, 0.45)
	hover.border_color = HOVER
	hover.border_width_left = 4
	hover.set_corner_radius_all(4)
	hover.content_margin_left = 18
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, none)
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hover)
	b.pressed.connect(func() -> void:
		_confirm_delete = 0
		cb.call())
	return b


## Sub-screen for slots and settings, to the right of the menu over the dimmed art.
func _build_panel() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.93)
	sb.border_color = Color(0.62, 0.5, 0.32)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(640, 200)
	_panel.custom_minimum_size = Vector2(1040, 0)
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_head = Label.new()
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_theme_font_size_override("font_size", 32)
	_head.add_theme_color_override("font_color", Color(1.0, 0.86, 0.58))
	top.add_child(_head)
	top.add_child(_button("뒤로 (ESC)", close_panel))
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	v.add_child(_body)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 990
	_note.add_theme_font_size_override("font_size", 19)
	_note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	v.add_child(_note)


func _unhandled_input(ev: InputEvent) -> void:
	if visible and mode != "" and ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


## Rebuilds whatever sub-screen is open (bootstrap.show_title calls this when the title opens).
func refresh() -> void:
	if mode == "new" or mode == "load":
		open_slots(mode)
	elif mode == "settings":
		open_settings()
	else:
		close_panel()


func close_panel() -> void:
	mode = ""
	_confirm_delete = 0
	_panel.visible = false


func _open(m: String, head: String, note: String) -> void:
	mode = m
	_head.text = head
	_note.text = note
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_panel.visible = true


## "new": pick an empty slot for a new character. "load": continue or delete a used one.
func open_slots(m: String) -> void:
	var free := 0
	for slot in range(1, SaveManager.SLOTS + 1):
		if not SaveManager.exists(slot):
			free += 1
	var note := "새 캐릭터는 빈 슬롯에서 시작하고, 그 캐릭터는 계속 같은 슬롯에 저장됩니다." if free > 0 \
		else "빈 슬롯이 없습니다. 불러오기에서 캐릭터 하나를 지우면 새로 시작할 수 있습니다."
	if m == "load":
		note = "자동 저장: 수면 · 지역 이동 · 쓰러진 뒤 깨어날 때 · 5분마다 · 창을 닫을 때   수동 저장: ESC"
	_open(m, "새 게임 — 슬롯 고르기" if m == "new" else "불러오기", note)
	for slot in range(1, SaveManager.SLOTS + 1):
		_body.add_child(_card(slot))


func _card(slot: int) -> PanelContainer:
	var data := SaveManager.read(slot)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.085, 0.12, 0.96)
	sb.border_color = Color(0.62, 0.5, 0.32) if not data.is_empty() else Color(0.36, 0.34, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(990, 112)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var head := Label.new()
	head.clip_text = true
	head.add_theme_font_size_override("font_size", 28)
	info.add_child(head)
	var line := Label.new()
	line.clip_text = true
	line.add_theme_font_size_override("font_size", 20)
	line.add_theme_color_override("font_color", Color(0.8, 0.8, 0.76))
	info.add_child(line)
	if data.is_empty():
		head.text = "슬롯 %d — 비어 있음" % slot
		if mode == "new":
			line.text = "새 캐릭터로 시작하면 이 슬롯에 저장됩니다"
			h.add_child(_button("여기서 시작", func() -> void: boot.start_slot(slot, true)))
		else:
			line.text = "저장된 캐릭터가 없습니다"
	elif data.get("broken", false):
		head.text = "슬롯 %d — 읽을 수 없는 저장 파일" % slot
		line.text = "파일이 손상되었거나 다른 형식입니다"
		h.add_child(_delete_button(slot))
	else:
		var m: Dictionary = data.get("meta", {})
		head.text = "슬롯 %d — Lv %d · %s · %d일차 %s" % [slot, int(m.get("level", 1)), m.get("where", ""), int(m.get("day", 1)), m.get("clock", "")]
		line.text = "플레이 %s · %d 골드 · 마지막 저장 %s" % [play_time_text(float(m.get("play_seconds", 0.0))), int(m.get("gold", 0)), m.get("saved_at", "")]
		if mode == "new":
			var used := Label.new()
			used.text = "사용 중"
			used.add_theme_font_size_override("font_size", 20)
			used.add_theme_color_override("font_color", Color(0.6, 0.6, 0.58))
			h.add_child(used)
		else:
			h.add_child(_button("이어하기", func() -> void: boot.start_slot(slot, false)))
			h.add_child(_delete_button(slot))
	return card


func open_settings() -> void:
	_open("settings", "설정", "설정은 이 컴퓨터에 저장되고 모든 슬롯에 같이 적용됩니다.")
	var fs := CheckButton.new()
	fs.text = "전체 화면"
	fs.focus_mode = Control.FOCUS_NONE
	fs.add_theme_font_size_override("font_size", 24)
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply()
		Settings.save())
	_body.add_child(fs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_body.add_child(row)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 24)
	l.custom_minimum_size.x = 220
	row.add_child(l)
	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 100
	vol.step = 5
	vol.value = roundf(Settings.volume * 100.0)
	vol.custom_minimum_size = Vector2(520, 36)
	vol.focus_mode = Control.FOCUS_NONE
	l.text = "전체 음량 %d%%" % int(vol.value)
	vol.value_changed.connect(func(v: float) -> void:
		l.text = "전체 음량 %d%%" % int(v)
		Settings.volume = v / 100.0
		Settings.apply())
	vol.drag_ended.connect(func(_changed: bool) -> void: Settings.save())
	row.add_child(vol)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(150, 56)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		_confirm_delete = 0
		cb.call())
	return b


func _delete_button(slot: int) -> Button:
	var b := Button.new()
	b.text = "정말 삭제?" if _confirm_delete == slot else "삭제"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(130, 56)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void: press_delete(slot))
	return b


## First press asks, second press deletes the slot's character for good.
func press_delete(slot: int) -> void:
	if _confirm_delete == slot:
		SaveManager.delete(slot)
		_confirm_delete = 0
	else:
		_confirm_delete = slot
	open_slots("load")


static func play_time_text(sec: float) -> String:
	var m := int(sec / 60.0)
	return "%d시간 %02d분" % [m / 60, m % 60]
