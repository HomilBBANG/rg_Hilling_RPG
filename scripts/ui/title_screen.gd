class_name TitleScreen
extends Control
## Title / slot select (SaveManager). One slot = one character: an empty slot starts a new game and
## claims the slot, a used slot continues that character (it keeps saving into the same slot).
## Deleting asks twice. The world behind stays frozen (tree paused) and dimmed.

var boot: Node
var _list: VBoxContainer
var _note: Label
var _confirm_delete := 0


func _ready() -> void:
	size = Vector2(1920, 1080)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.8)
	dim.size = size
	add_child(dim)
	var col := VBoxContainer.new()
	col.position = Vector2(470, 120)
	col.custom_minimum_size.x = 980
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	var title := Label.new()
	title.text = "DENIAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.58))
	col.add_child(title)
	var sub := Label.new()
	sub.text = "저장 슬롯을 고르세요 — 슬롯 하나에 캐릭터 하나"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	col.add_child(sub)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	col.add_child(_list)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 19)
	_note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	_note.text = "새 게임은 빈 슬롯에서 시작하고, 그 캐릭터는 계속 같은 슬롯에 저장됩니다.\n자동 저장: 수면 · 지역 이동 · 쓰러진 뒤 깨어날 때 · 5분마다 · 창을 닫을 때   수동 저장: ESC"
	col.add_child(_note)
	var quit := Button.new()
	quit.text = "게임 종료"
	quit.focus_mode = Control.FOCUS_NONE
	quit.add_theme_font_size_override("font_size", 22)
	quit.custom_minimum_size = Vector2(220, 0)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit.pressed.connect(func() -> void: get_tree().quit())
	col.add_child(quit)


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for slot in range(1, SaveManager.SLOTS + 1):
		_list.add_child(_card(slot))


func _card(slot: int) -> PanelContainer:
	var data := SaveManager.read(slot)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.075, 0.1, 0.94)
	sb.border_color = Color(0.62, 0.5, 0.32) if not data.is_empty() else Color(0.36, 0.34, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(980, 112)
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
		line.text = "새 캐릭터로 시작하면 이 슬롯에 저장됩니다"
		h.add_child(_button("새 게임", func() -> void: boot.start_slot(slot, true)))
	elif data.get("broken", false):
		head.text = "슬롯 %d — 읽을 수 없는 저장 파일" % slot
		line.text = "파일이 손상되었거나 다른 형식입니다"
		h.add_child(_delete_button(slot))
	else:
		var m: Dictionary = data.get("meta", {})
		head.text = "슬롯 %d — Lv %d · %s · %d일차 %s" % [slot, int(m.get("level", 1)), m.get("where", ""), int(m.get("day", 1)), m.get("clock", "")]
		line.text = "플레이 %s · %d 골드 · 마지막 저장 %s" % [play_time_text(float(m.get("play_seconds", 0.0))), int(m.get("gold", 0)), m.get("saved_at", "")]
		h.add_child(_button("이어하기", func() -> void: boot.start_slot(slot, false)))
		h.add_child(_delete_button(slot))
	return card


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
	refresh()


static func play_time_text(sec: float) -> String:
	var m := int(sec / 60.0)
	return "%d시간 %02d분" % [m / 60, m % 60]
