class_name GameHud
extends Control
## P1 gameplay HUD, drawn at full resolution outside the pixelated world (text stays sharp).
## HP/SP/MP bars, weight / clock / story line, interaction prompt, 3-level combat log
## (GDD 6.3 [확정]), floating damage numbers, fade for death / sleep, and the item panels:
## loot inspection, inventory (Tab), camper storage, cot sleep. Panels never pause the game
## (GDD 4.1 [확정]); layout and look are [미정] HUD placeholders (GDD 17).

const PANEL_FONT := 22
const BAR_SIZE := Vector2(330, 24)

var font: Font
var boot: Node

var _bars := {}  # key -> [fill ColorRect, Label, color]
var _info: Label
var _prompt: Label
var _log_box: PanelContainer
var _log_button: Button
var _log_line: Label
var _log_detail: RichTextLabel
var _floats: Array[Dictionary] = []
var _float_layer: Control
var _quick_slots: Array[Dictionary] = []  # {"panel": PanelContainer, "label": Label, "style": StyleBoxFlat}
var _fade: ColorRect
var _fade_label: Label
var _panel: PanelContainer
var _panel_source: Node3D
var _panel_range := 2.5
var _panel_refresh: Callable
var _panel_kind := ""
var _sleep_hours := 8
var dialogue: DialogueBox
var fishing: FishingPanel
var cutscene: CutsceneRunner
var _caption: Label
var _tracker: Label
var _tracker_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = PANEL_FONT
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 6)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.22, 0.19, 0.15), "hover": Color(0.36, 0.3, 0.2),
			"pressed": Color(0.5, 0.4, 0.24), "disabled": Color(0.15, 0.15, 0.15)}[state]
		sb.border_color = Color(0.62, 0.5, 0.32)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		t.set_stylebox(state, "Button", sb)
	theme = t
	var y := 18.0
	for spec in [["hp", "HP", Color(0.86, 0.26, 0.24)], ["sp", "SP", Color(0.86, 0.76, 0.26)], ["mp", "MP", Color(0.3, 0.52, 0.92)]]:
		_make_bar(spec[0], spec[1], spec[2], Vector2(22, y))
		y += BAR_SIZE.y + 8
	_info = _label("", 20, Vector2(22, y + 2))
	_prompt = _label("", 26, Vector2(0, 880))  # above the quickslot bar
	_prompt.size = Vector2(1920, 40)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_build_log()
	_build_quickbar()
	_float_layer = Control.new()
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.size = Vector2(1920, 1080)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	add_child(_fade)
	_fade_label = _label("", 36, Vector2(0, 360))
	_fade_label.size = Vector2(1920, 360)
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fade_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fade_label.modulate.a = 0.0
	_tracker = _label("", 19, Vector2(1440, 18))
	_tracker.size = Vector2(458, 0)
	_tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tracker.add_theme_color_override("font_color", Color(1.0, 0.93, 0.75))
	cutscene = CutsceneRunner.new()
	add_child(cutscene)
	dialogue = DialogueBox.new()
	dialogue.cutscenes = cutscene
	add_child(dialogue)
	fishing = FishingPanel.new()
	add_child(fishing)
	_caption = _label("", 28, Vector2(0, 760))
	_caption.size = Vector2(1920, 50)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	move_child(_fade, -1)
	move_child(_fade_label, -1)
	Game.quests.changed.connect(func() -> void:
		_tracker_t = 0.0
		if _panel_kind in ["journal", "board"]:
			_refresh_panel())
	Game.combat_log.added.connect(func(_e: Dictionary) -> void: _refresh_log())
	Game.player_state.changed.connect(_on_player_changed)
	_refresh_log()


func _label(text: String, fsize: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", fsize)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _make_bar(key: String, title: String, color: Color, pos: Vector2) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08, 0.8)
	bg.position = pos
	bg.size = BAR_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2(2, 2)
	fill.size = BAR_SIZE - Vector2(4, 4)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	var l := Label.new()
	l.position = Vector2(8, -2)
	l.add_theme_font_size_override("font_size", 19)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(l)
	_bars[key] = [fill, l, title]


func _set_bar(key: String, v: float, vmax: float) -> void:
	var b: Array = _bars[key]
	(b[0] as ColorRect).size.x = (BAR_SIZE.x - 4) * clampf(v / maxf(vmax, 0.001), 0.0, 1.0)
	(b[1] as Label).text = "%s %d / %d" % [b[2], ceili(v) if key == "hp" else floori(v), int(vmax)]


func set_capture_mode(on: bool) -> void:
	visible = not on


# ---------------------------------------------------------------- combat log (GDD 6.3)

func _build_log() -> void:
	_log_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.72)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	_log_box.add_theme_stylebox_override("panel", sb)
	add_child(_log_box)
	var v := VBoxContainer.new()
	_log_box.add_child(v)
	_log_detail = RichTextLabel.new()
	_log_detail.bbcode_enabled = true
	_log_detail.fit_content = true
	_log_detail.scroll_active = false
	_log_detail.custom_minimum_size = Vector2(980, 0)
	_log_detail.add_theme_font_size_override("normal_font_size", 18)
	_log_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_log_detail)
	var h := HBoxContainer.new()
	v.add_child(h)
	_log_button = _button("◆ 로그", func() -> void:
		Game.combat_log.cycle_level()
		_refresh_log())
	h.add_child(_log_button)
	_log_line = Label.new()
	_log_line.add_theme_font_size_override("font_size", 20)
	_log_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_log_line)


func cycle_log_level() -> void:
	Game.combat_log.cycle_level()
	_refresh_log()


const LOG_COLORS := {"hit": "#f4efe0", "crit": "#ffa040", "miss": "#a8b0b8", "hurt": "#ff6a60",
	"death": "#ffd860", "info": "#9fd0ff"}


func _refresh_log() -> void:
	var lv := Game.combat_log.level
	var entries := Game.combat_log.entries
	_log_button.text = "◆ 로그 %d" % lv
	_log_line.visible = lv >= 2
	_log_detail.visible = lv == 3
	if entries.is_empty():
		_log_line.text = "  (기록 없음)"
	else:
		var last: Dictionary = entries[-1]
		_log_line.text = "  " + last["short"]
		_log_line.add_theme_color_override("font_color", Color(LOG_COLORS.get(last["kind"], "#ffffff")))
	if lv == 3:
		var lines := PackedStringArray()
		for e in entries.slice(maxi(0, entries.size() - 9)):
			lines.append("[color=#808890]%s[/color] [color=%s]%s[/color]" % [e["time"], LOG_COLORS.get(e["kind"], "#ffffff"), e["detail"]])
		_log_detail.text = "\n".join(lines) if not lines.is_empty() else "[color=#808890]전투 기록이 없습니다[/color]"
	_log_box.reset_size()


# ---------------------------------------------------------------- quickslot bar (GDD 5.3 / 6.4)

func _build_quickbar() -> void:
	var total := PlayerState.QUICK_ITEM_SLOTS + PlayerState.QUICK_SKILL_SLOTS
	var w := 96.0
	var x0 := 1900.0 - total * (w + 6.0) - 14.0
	for i in total:
		var pc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.09, 0.78)
		sb.border_color = Color(0.45, 0.4, 0.3) if i < PlayerState.QUICK_ITEM_SLOTS else Color(0.3, 0.42, 0.6)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(5)
		sb.set_content_margin_all(4)
		pc.add_theme_stylebox_override("panel", sb)
		pc.position = Vector2(x0 + i * (w + 6.0) + (14.0 if i >= PlayerState.QUICK_ITEM_SLOTS else 0.0), 932)
		pc.custom_minimum_size = Vector2(w, 66)
		pc.size = Vector2(w, 66)
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_constant_override("outline_size", 4)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.custom_minimum_size = Vector2(w - 8, 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(l)
		add_child(pc)
		_quick_slots.append({"panel": pc, "label": l, "style": sb})


func _update_quickbar() -> void:
	var st := Game.player_state
	var p := _player()
	var using_id := ""
	if p and p.is_using():
		using_id = p._use.get("id", "")  # tasks (gathering / fishing) have no item id
	for i in _quick_slots.size():
		var q: Dictionary = _quick_slots[i]
		var l: Label = q["label"]
		var sb: StyleBoxFlat = q["style"]
		var text := ""
		var dim := false
		if i < PlayerState.QUICK_ITEM_SLOTS:
			var id: String = st.quick_items[i]
			if id == "":
				text = "%d\n—" % (i + 1)
				dim = true
			else:
				var n := st.inventory.count(id)
				text = "%d  ×%d\n%s" % [i + 1, n, ItemDB.item_name(id)]
				dim = n <= 0
		else:
			var k := i - PlayerState.QUICK_ITEM_SLOTS
			var id: String = st.quick_skills[k]
			if id == "":
				text = "%d\n—" % (k + 5)
				dim = true
			else:
				var sp_info: Dictionary = ItemDB.SPELLS[id]
				var cd: float = st.cooldowns.get(id, 0.0)
				text = "%d  MP%d\n%s%s" % [k + 5, sp_info["mp"], sp_info["name"], "\n%.1fs" % cd if cd > 0.05 else ""]
				dim = cd > 0.0 or st.mp < sp_info["mp"]
			if id != "" and id == using_id:
				dim = false
		l.text = text
		l.modulate = Color(1, 1, 1, 0.45) if dim else Color.WHITE
		sb.border_color = Color(0.95, 0.85, 0.45) if (using_id != "" and ((i < PlayerState.QUICK_ITEM_SLOTS and st.quick_items[i] == using_id) or (i >= PlayerState.QUICK_ITEM_SLOTS and st.quick_skills[i - PlayerState.QUICK_ITEM_SLOTS] == using_id))) \
			else (Color(0.45, 0.4, 0.3) if i < PlayerState.QUICK_ITEM_SLOTS else Color(0.3, 0.42, 0.6))


# ---------------------------------------------------------------- floating text

func float_text(world_pos: Vector3, text: String, color: Color, big := false) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 40 if big else 30)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_layer.add_child(l)
	_floats.append({"label": l, "pos": world_pos, "t": 0.0, "dx": randf_range(-14, 14)})


func _update_floats(delta: float) -> void:
	for f in _floats.duplicate():
		f["t"] += delta
		var l: Label = f["label"]
		var sp: Variant = Game.view.world_to_screen(f["pos"]) if Game.view else null
		if f["t"] > 1.4 or sp == null:
			l.queue_free()
			_floats.erase(f)
			continue
		l.reset_size()
		l.position = (sp as Vector2) + Vector2(f["dx"] - l.size.x * 0.5, -l.size.y - f["t"] * 50.0)
		l.modulate.a = 1.0 - smoothstep(0.9, 1.4, f["t"])


# ---------------------------------------------------------------- fade

func fade_to(alpha: float, time: float, text := "") -> void:
	if alpha > 0.5:
		_fade_label.text = text
	var tw := create_tween().set_parallel()
	tw.tween_property(_fade, "modulate:a", alpha, time)
	tw.tween_property(_fade_label, "modulate:a", alpha, time)
	await tw.finished


# ---------------------------------------------------------------- panels

func blocks_mouse() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null and is_ancestor_of(c)


func panel_open() -> bool:
	return _panel != null


func close_panel() -> void:
	if _panel:
		_panel.queue_free()
	_panel = null
	_panel_source = null
	_panel_kind = ""
	_panel_refresh = Callable()


func _style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.075, 0.1, 0.94)
	sb.border_color = Color(0.62, 0.5, 0.32)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	return sb


func _button(text: String, cb: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(cb)
	return b


func _row_label(text: String, w: int, fsize := PANEL_FONT, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = w
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.clip_text = true
	return l


## Opens a centred panel; build(v: VBoxContainer) fills it and is re-run on every refresh.
func _open(kind: String, source: Node3D, range_m: float, build: Callable, width := 760) -> void:
	close_panel()
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _style())
	_panel.custom_minimum_size.x = width
	add_child(_panel)
	move_child(_panel, _fade.get_index())
	_panel_kind = kind
	_panel_source = source
	_panel_range = range_m
	_panel_refresh = func() -> void:
		if _panel == null:
			return
		for c in _panel.get_children():
			c.queue_free()
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		_panel.add_child(v)
		build.call(v)
		_panel.reset_size()
		_panel.position = Vector2(960 - _panel.size.x * 0.5, 470 - _panel.size.y * 0.5)
	_panel_refresh.call()


func _refresh_panel() -> void:
	if _panel_refresh.is_valid():
		_panel_refresh.call_deferred()


func _weight_line() -> String:
	var st := Game.player_state
	var line := "소지 중량 %.1f / %.0f kg (한계 %.0f kg) · %s" % [st.carried_weight(), st.carry_capacity(), st.carry_limit(), st.weight_state()]
	if st.speed_factor() < 0.999:
		line += " — 이동 속도 ×%.2f" % st.speed_factor()
	return line


func _items_list(v: VBoxContainer, inv: Inventory, buttons: Callable, empty_text := "비어 있다") -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	scroll.custom_minimum_size.y = clampi(inv.items.size(), 1, 9) * 44
	v.add_child(scroll)
	if inv.is_empty():
		rows.add_child(_row_label(empty_text, 300, PANEL_FONT, Color(0.65, 0.68, 0.72)))
	for e in inv.items:
		var h := HBoxContainer.new()
		var id: String = e["id"]
		h.add_child(_row_label("%s ×%d" % [ItemDB.item_name(id), e["count"]], 260))
		h.add_child(_row_label("%.1f kg" % (ItemDB.weight(id) * e["count"]), 100, 19, Color(0.75, 0.78, 0.8)))
		if buttons.is_valid():
			buttons.call(h, id, e["count"])
		rows.add_child(h)


## Moves up to n units, one by one, as long as the target can take them. Returns moved count.
func _move(src: Inventory, dst: Inventory, id: String, n: int, can_take: Callable) -> int:
	var moved := 0
	for i in n:
		if src.count(id) <= 0 or not can_take.call(ItemDB.weight(id)):
			break
		src.remove(id, 1)
		dst.add(id, 1)
		moved += 1
	return moved


func _player_can_take(w: float) -> bool:
	return Game.player_state.can_carry(w)


func _storage_can_take(w: float) -> bool:
	return Game.storage.weight() + w <= Game.STORAGE_CAPACITY + 0.0001


func _too_heavy_toast() -> void:
	boot.hud.toast("너무 무겁다 — 한계 중량 %.0f kg을 넘어 더 들 수 없다" % Game.player_state.carry_limit())


## Corpse / bag / crate inspection: take single items, a stack, or everything (no auto pickup).
func open_loot(source: LootContainer) -> void:
	if _panel_kind == "loot" and _panel_source == source:
		close_panel()
		return
	var inv := source.inventory()
	var take := func(id: String, n: int) -> void:
		var got := _move(inv, Game.player_state.inventory, id, n, _player_can_take)
		if got > 0:
			Game.combat_log.add("획득: %s ×%d" % [ItemDB.item_name(id), got], "", "info")
		if got < n and inv.count(id) > 0:
			_too_heavy_toast()
		_refresh_panel()
	_open("loot", source, source.interact_range + 1.0, func(v: VBoxContainer) -> void:
		v.add_child(_row_label(source.data["title"], 400, 28, Color(1.0, 0.9, 0.6)))
		v.add_child(_row_label(_weight_line(), 720, 19, Color(0.8, 0.84, 0.88)))
		_items_list(v, inv, func(h: HBoxContainer, id: String, count: int) -> void:
			h.add_child(_button("가져가기", func() -> void: take.call(id, 1)))
			if count > 1:
				h.add_child(_button("모두", func() -> void: take.call(id, count))))
		var bottom := HBoxContainer.new()
		bottom.add_child(_button("전부 가져가기", func() -> void:
			for e in inv.duplicate_items():
				take.call(e["id"], e["count"])))
		bottom.add_child(_button("닫기 (E)", close_panel))
		v.add_child(bottom))


func toggle_inventory() -> void:
	if _panel_kind == "inventory":
		close_panel()
		return
	var st := Game.player_state
	_open("inventory", null, 0.0, func(v: VBoxContainer) -> void:
		v.add_child(_row_label("소지품 · 장비 — 슬롯 제한 없음 · 열어도 게임은 계속 진행", 900, 26, Color(1.0, 0.9, 0.6)))
		v.add_child(_row_label(_weight_line() + " · 장착 장비 중량 제외", 1100, 19, Color(0.8, 0.84, 0.88)))
		var p := _player()
		var swapping: bool = p != null and p.is_swapping()
		v.add_child(_row_label("방어 %d · 명중 +%d · 치명 %d%% · 무기 %s%s" % [st.total_armor(), st.total_hit_bonus(),
			st.total_crit_chance(), st.weapon()["name"], "   — 장비 교체 중…" if swapping else ""], 1100, 19, Color(0.75, 0.88, 0.75)))
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 24)
		v.add_child(cols)
		var left := VBoxContainer.new()
		var right := VBoxContainer.new()
		cols.add_child(left)
		cols.add_child(right)
		left.add_child(_row_label("장착 슬롯", 300, 22, Color(1.0, 0.9, 0.6)))
		for slot: String in ItemDB.SLOT_ORDER:
			var row := HBoxContainer.new()
			var id: String = st.equipment[slot]
			row.add_child(_row_label(ItemDB.SLOT_NAMES[slot], 100, 19, Color(0.72, 0.76, 0.8)))
			var txt := "—" if id == "" else ItemDB.item_name(id)
			if slot == "off" and st.two_handed():
				txt = "(양손 무기 사용 중)"
			row.add_child(_row_label(txt, 330, 19))
			if id != "":
				var b := _button("해제", func() -> void: _change_gear(func() -> void: st.unequip(slot), "%s 해제" % ItemDB.item_name(id)))
				b.disabled = swapping
				b.tooltip_text = ItemDB.equip_summary(id)
				row.add_child(b)
			left.add_child(row)
		right.add_child(_row_label("가방", 300, 22, Color(1.0, 0.9, 0.6)))
		_items_list(right, st.inventory, func(h: HBoxContainer, id: String, _count: int) -> void:
			if ItemDB.is_consumable(id):
				var reading: bool = ItemDB.info(id).get("use", "") == "read"
				var ub := _button("읽기" if reading else "사용", func() -> void:
					var pl := _player()
					if pl:
						pl.begin_use_item(id)
					_refresh_panel())
				ub.disabled = swapping
				h.add_child(ub)
				if not reading:
					for qi in PlayerState.QUICK_ITEM_SLOTS:
						var on: bool = st.quick_items[qi] == id
						var qb := _button(("[%d]" if on else "%d") % (qi + 1), func() -> void:
							st.assign_quick_item(qi, "" if on else id)
							_refresh_panel())
						qb.tooltip_text = "소모품 퀵슬롯 %d에 등록" % (qi + 1)
						h.add_child(qb)
			if ItemDB.is_equipment(id):
				var slot := st.target_slot(id)
				var eb := _button("장착 (%s)" % ItemDB.SLOT_NAMES[slot], func() -> void:
					_change_gear(func() -> void: st.equip(id), "%s 장착" % ItemDB.item_name(id)))
				eb.disabled = swapping
				eb.tooltip_text = ItemDB.equip_summary(id)
				h.add_child(eb), "가방이 비어 있다")
		var hint := PackedStringArray()
		for e in st.inventory.items:
			if ItemDB.is_equipment(e["id"]):
				hint.append("%s: %s" % [ItemDB.item_name(e["id"]), ItemDB.equip_summary(e["id"])])
			elif ItemDB.is_consumable(e["id"]):
				var ci := ItemDB.info(e["id"])
				var ut: Dictionary = ItemDB.USE_TYPES[ci["use"]]
				hint.append("%s: %s · %s %.1f초%s" % [ci["name"], ItemDB.effect_text(ci["effect"]), ut["name"].replace(" 중", ""),
					ut["time"], " (천천히 이동 가능)" if ut["move"] > 0.0 else " (멈춰서)"])
		if not hint.is_empty():
			right.add_child(_row_label("\n".join(hint), 620, 16, Color(0.7, 0.74, 0.78)))
		v.add_child(_button("닫기 (Tab)", close_panel)), 1180)


## Merchant (GDD 16): buy limited stock at the shop's price, sell bag items at this merchant's
## rate (0 = doesn't buy: rare goods only to specialists). The blacksmith also upgrades the
## equipped weapon / armour for gold (GDD 15.3: always succeeds).
func open_shop(shop_id: String, source: Node3D) -> void:
	if _panel_kind == "shop":
		close_panel()
		return
	ShopDB.restock(shop_id)
	var shop := ShopDB.info(shop_id)
	var st := Game.player_state
	_open("shop", source, 2.6, func(v: VBoxContainer) -> void:
		v.add_child(_row_label("%s — 주인 %s · 영업 %s · 보유 %d 골드" % [shop["name"], shop["keeper"], ShopDB.hours_text(shop_id), st.gold], 1100, 26, Color(1.0, 0.9, 0.6)))
		v.add_child(_row_label(_weight_line(), 1100, 18, Color(0.8, 0.84, 0.88)))
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 26)
		v.add_child(cols)
		var left := VBoxContainer.new()
		var right := VBoxContainer.new()
		cols.add_child(left)
		cols.add_child(right)
		left.add_child(_row_label("판매 물품", 300, 22, Color(1.0, 0.9, 0.6)))
		for e: Array in shop["stock"]:
			var id: String = e[0]
			var price: int = e[1]
			var left_n := ShopDB.stock_left(shop_id, id)
			var row := HBoxContainer.new()
			row.add_child(_row_label(ItemDB.item_name(id), 190, 20))
			row.add_child(_row_label("%d g" % price, 70, 19, Color(1.0, 0.85, 0.4)))
			row.add_child(_row_label("재고 %d/%d" % [left_n, e[2]], 100, 18, Color(0.72, 0.76, 0.8)))
			var b := _button("구매", func() -> void:
				var why := ShopDB.buy(shop_id, id, price)
				if why != "":
					boot.hud.toast(why)
				else:
					Game.combat_log.add("구매: %s (-%d 골드)" % [ItemDB.item_name(id), price], "", "info")
				_refresh_panel())
			b.disabled = left_n <= 0 or st.gold < price
			b.tooltip_text = ItemDB.equip_summary(id) if ItemDB.is_equipment(id) else ItemDB.info(id).get("desc", "")
			row.add_child(b)
			left.add_child(row)
		var groups := PackedStringArray()
		for g: String in ShopDB.state(shop_id)["last"]:
			var left_min: float = ShopDB.RESTOCK_DAYS[g] * 1440.0 - (Game.total_minutes() - ShopDB.state(shop_id)["last"][g])
			groups.append("재입고 · %s %d일 주기 (다음 %d시간 후)" % [{"consumable": "생필품·소모품", "material": "일반 재료", "rare": "희귀 재료", "equip": "특수 장비"}[g],
				ShopDB.RESTOCK_DAYS[g], ceili(left_min / 60.0)])
		for g_text in groups:
			left.add_child(_row_label(g_text, 520, 16, Color(0.66, 0.7, 0.74)))
		right.add_child(_row_label("내 물건 팔기", 300, 22, Color(1.0, 0.9, 0.6)))
		_items_list(right, st.inventory, func(h: HBoxContainer, id: String, count: int) -> void:
			var price := ShopDB.sell_price(shop_id, id)
			if price <= 0:
				h.add_child(_row_label("안 삼", 80, 17, Color(0.6, 0.62, 0.66)))
				return
			h.add_child(_row_label("%d g" % price, 60, 19, Color(1.0, 0.85, 0.4)))
			h.add_child(_button("팔기", func() -> void:
				var got := ShopDB.sell(shop_id, id)
				if got > 0:
					Game.combat_log.add("판매: %s (+%d 골드)" % [ItemDB.item_name(id), got], "", "info")
				_refresh_panel()))
			if count > 1:
				h.add_child(_button("모두", func() -> void:
					var total := 0
					for i in count:
						total += ShopDB.sell(shop_id, id)
					Game.combat_log.add("판매: %s ×%d (+%d 골드)" % [ItemDB.item_name(id), count, total], "", "info")
					_refresh_panel())), "팔 물건이 없다")
		if shop.get("smith", false):
			v.add_child(_row_label("장비 강화 — 착용 중인 무기·방어구, 100%% 성공 (실패·하락·파괴 없음) · 최대 +%d" % ItemDB.MAX_ENHANCE, 1100, 22, Color(1.0, 0.9, 0.6)))
			var any := false
			for slot: String in ItemDB.SLOT_ORDER:
				var eid: String = st.equipment[slot]
				if eid == "" or not (ItemDB.info(eid).has("phys") or ItemDB.info(eid).has("armor")):
					continue
				any = true
				var row2 := HBoxContainer.new()
				row2.add_child(_row_label(ItemDB.SLOT_NAMES[slot], 100, 19, Color(0.72, 0.76, 0.8)))
				row2.add_child(_row_label(ItemDB.item_name(eid), 300, 20))
				row2.add_child(_row_label(ItemDB.equip_summary(eid), 330, 17, Color(0.72, 0.76, 0.8)))
				if ItemDB.can_enhance(eid):
					var cost := ItemDB.enhance_cost(eid)
					var kind := "물리 피해 +1" if ItemDB.info(eid).has("phys") else "방어 +1"
					var eb := _button("강화 (%d g, %s)" % [cost, kind], func() -> void:
						if st.enhance_equipped(slot):
							Game.combat_log.add("강화 성공: %s (-%d 골드)" % [ItemDB.item_name(st.equipment[slot]), cost], "", "info")
							boot.hud.toast("강화 성공 — %s" % ItemDB.item_name(st.equipment[slot]))
						else:
							boot.hud.toast("골드가 부족하다")
						_refresh_panel())
					eb.disabled = st.gold < cost
					row2.add_child(eb)
				else:
					row2.add_child(_row_label("최대 강화", 120, 18, Color(0.6, 0.62, 0.66)))
				v.add_child(row2)
			if not any:
				v.add_child(_row_label("  강화할 장비를 착용하고 오세요", 600, 18, Color(0.7, 0.74, 0.78)))
		v.add_child(_button("닫기 (E)", close_panel)), 1220)


func _player() -> PrototypePlayer:
	var w: Node = boot.world if boot else null
	return w.player if w and is_instance_valid(w) and w.get("player") else null


## Equip / unequip through the player's swap motion (GDD 6.5); applied when it ends.
func _change_gear(action: Callable, done_text: String) -> void:
	var p := _player()
	if p == null or not p.begin_gear_change(func() -> void:
		action.call()
		_refresh_panel(), done_text):
		boot.hud.toast("지금은 장비를 바꿀 수 없다")
	_refresh_panel()


## Camper storage (GDD 8.3 [확정]): separate weight-limited box, move items one by one or
## "move everything carried". No automatic storing on arrival.
func open_storage(source: Node3D) -> void:
	if _panel_kind == "storage":
		close_panel()
		return
	var bag := Game.player_state.inventory
	var box := Game.storage
	_open("storage", source, 2.6, func(v: VBoxContainer) -> void:
		v.add_child(_row_label("캠핑카 창고", 400, 28, Color(1.0, 0.9, 0.6)))
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 26)
		v.add_child(cols)
		var left := VBoxContainer.new()
		var right := VBoxContainer.new()
		cols.add_child(left)
		cols.add_child(right)
		left.add_child(_row_label("소지품 %.1f / %.0f kg (한계 %.0f)" % [bag.weight(), Game.player_state.carry_capacity(), Game.player_state.carry_limit()], 520, 20, Color(0.85, 0.88, 0.92)))
		_items_list(left, bag, func(h: HBoxContainer, id: String, count: int) -> void:
			h.add_child(_button("1 →", func() -> void:
				if _move(bag, box, id, 1, _storage_can_take) == 0:
					boot.hud.toast("창고 용량이 부족하다")
				_refresh_panel()))
			if count > 1:
				h.add_child(_button("모두 →", func() -> void:
					if _move(bag, box, id, count, _storage_can_take) < count:
						boot.hud.toast("창고 용량이 부족해 일부만 옮겼다")
					_refresh_panel())), "가방이 비어 있다")
		right.add_child(_row_label("창고 %.1f / %.0f kg" % [box.weight(), Game.STORAGE_CAPACITY], 520, 20, Color(0.85, 0.88, 0.92)))
		_items_list(right, box, func(h: HBoxContainer, id: String, count: int) -> void:
			h.add_child(_button("← 1", func() -> void:
				if _move(box, bag, id, 1, _player_can_take) == 0:
					_too_heavy_toast()
				_refresh_panel()))
			if count > 1:
				h.add_child(_button("← 모두", func() -> void:
					if _move(box, bag, id, count, _player_can_take) < count:
						_too_heavy_toast()
					_refresh_panel())), "창고가 비어 있다")
		var bottom := HBoxContainer.new()
		bottom.add_child(_button("소지품 전체 옮기기 →", func() -> void:
			var left_over := 0
			for e in bag.duplicate_items():
				left_over += e["count"] - _move(bag, box, e["id"], e["count"], _storage_can_take)
			if left_over > 0:
				boot.hud.toast("창고 용량이 부족해 %d개는 소지품에 남았다" % left_over)
			else:
				boot.hud.toast("소지품을 모두 창고로 옮겼다")
			_refresh_panel()))
		bottom.add_child(_button("닫기 (E)", close_panel))
		v.add_child(bottom), 1180)


## Cot (GDD 9.6): choose hours, game time advances by that much, cot restores HP 10 % [임시].
func open_sleep(source: Node3D) -> void:
	if _panel_kind == "sleep":
		close_panel()
		return
	_open("sleep", source, 2.4, func(v: VBoxContainer) -> void:
		v.add_child(_row_label("간이침대 — 수면", 400, 28, Color(1.0, 0.9, 0.6)))
		var h := HBoxContainer.new()
		h.add_child(_row_label("수면 시간", 140))
		h.add_child(_button(" − ", func() -> void:
			_sleep_hours = maxi(1, _sleep_hours - 1)
			_refresh_panel()))
		h.add_child(_row_label("  %d시간  " % _sleep_hours, 110, 26))
		h.add_child(_button(" + ", func() -> void:
			_sleep_hours = mini(12, _sleep_hours + 1)
			_refresh_panel()))
		v.add_child(h)
		var wake := fposmod(Game.minute_of_day + _sleep_hours * 60.0, 1440.0)
		v.add_child(_row_label("지금 %s → 기상 %02d:%02d" % [Game.clock_text(), int(wake) / 60, int(wake) % 60], 520, 20, Color(0.85, 0.88, 0.92)))
		v.add_child(_row_label("간이침대 회복: HP 최대치의 10%% [임시] · SP/MP 회복 [미정→전부]", 680, 19, Color(0.75, 0.8, 0.85)))
		var b := HBoxContainer.new()
		b.add_child(_button("잠자기", func() -> void:
			var hours := _sleep_hours
			close_panel()
			boot.sleep(hours)))
		b.add_child(_button("취소", close_panel))
		v.add_child(b), 700)


# ---------------------------------------------------------------- per frame

## Character sheet (GDD 5.1-5.3): spend general EXP on a level-up (+1 stat point) or on basic
## skills; put stat points into the 7 stats. Nothing happens automatically.
func toggle_character() -> void:
	if _panel_kind == "character":
		close_panel()
		return
	var st := Game.player_state
	_open("character", null, 0.0, func(v: VBoxContainer) -> void:
		v.add_child(_row_label("주인공 — Lv %d" % st.level, 400, 28, Color(1.0, 0.9, 0.6)))
		var h := HBoxContainer.new()
		h.add_child(_row_label("일반 EXP %d / 레벨업 %d" % [st.gen_exp, st.exp_to_next()], 330, 22))
		var lv := _button("레벨업 (EXP %d 사용)" % st.exp_to_next(), func() -> void:
			if st.level_up():
				Game.combat_log.add("레벨 %d — 능력치 포인트 +%d" % [st.level, PlayerState.STAT_POINTS_PER_LEVEL], "", "info")
				boot.hud.toast("레벨 %d! 능력치 포인트를 투자하세요" % st.level)
			_refresh_panel())
		lv.disabled = not st.can_level_up()
		h.add_child(lv)
		v.add_child(h)
		# life side (GDD 5.2 / 5.4): life EXP is spent on life skills; mastery grows by doing
		var mparts := PackedStringArray()
		for f: String in LifeDB.FIELDS:
			var pts := int(st.mastery.get(f, 0))
			var nxt := LifeDB.next_threshold(pts)
			mparts.append("%s Lv %d (%s)" % [LifeDB.field_name(f), st.mastery_level(f), "%d/%d" % [pts, nxt] if nxt > 0 else "최대"])
		v.add_child(_row_label("생활 EXP %d · 숙련도: %s" % [st.life_exp, ", ".join(mparts)], 760, 18, Color(0.75, 0.9, 0.75)))
		for sid: String in LifeDB.data().get("skills", {}):
			var sk := LifeDB.skill(sid)
			var srow := HBoxContainer.new()
			srow.add_child(_row_label("  %s — %s" % [sk.get("name", sid), sk.get("desc", "")], 560, 17))
			var block := st.life_skill_block(sid)
			var sb := _button("배움" if st.has_life_skill(sid) else ("배우기 (생활 EXP %d)" % int(sk.get("cost", 0))), func() -> void:
				if st.learn_life_skill(sid):
					boot.hud.toast("생활 기술 습득: " + str(sk.get("name", sid)))
				_refresh_panel(), 190)
			sb.disabled = block != ""
			sb.tooltip_text = block
			srow.add_child(sb)
			v.add_child(srow)
		v.add_child(_row_label("능력치 포인트 %d" % st.stat_points, 400, 22, Color(0.6, 0.85, 1.0) if st.stat_points > 0 else Color(0.8, 0.82, 0.85)))
		for key: String in PlayerState.STAT_KEYS:
			var row := HBoxContainer.new()
			var info: Array = PlayerState.STAT_INFO[key]
			row.add_child(_row_label("%s %s" % [key, info[0]], 130, 21))
			var gb := st.gear_bonus(key)
			row.add_child(_row_label("%d%s" % [st.stats[key], " (+%d)" % gb if gb > 0 else ""], 80, 21, Color(1.0, 0.95, 0.8)))
			var plus := _button(" + ", func() -> void:
				st.add_stat(key)
				_refresh_panel())
			plus.disabled = st.stat_points <= 0
			row.add_child(plus)
			row.add_child(_row_label("  " + info[1], 520, 18, Color(0.72, 0.76, 0.8)))
			v.add_child(row)
		v.add_child(_row_label("최대 HP %d · SP %d · MP %d · 소지 %.0f/%.0f kg · 물리 배율 ×%.1f · 명중 +%d · 치명 %d%% · 방어 %d (괄호 = 장비 보너스)" % [
			st.max_hp(), st.max_sp(), st.max_mp(), st.carry_capacity(), st.carry_limit(), st.str_multiplier(),
			st.total_hit_bonus(), st.total_crit_chance(), st.total_armor()], 840, 18, Color(0.75, 0.88, 0.75)))
		v.add_child(_row_label("마법·특수 스킬 — 퀵슬롯(5~8)에 등록해야 사용 · 마법서/NPC/퀘스트로 습득", 840, 22, Color(1.0, 0.9, 0.6)))
		if st.spells.is_empty():
			v.add_child(_row_label("  아직 배운 마법이 없다 (보급 상자의 '마법서: 작은 치유'를 Tab에서 읽기)", 840, 18, Color(0.7, 0.74, 0.78)))
		for sid: String in st.spells:
			var spi: Dictionary = ItemDB.SPELLS[sid]
			var srow := HBoxContainer.new()
			srow.add_child(_row_label(spi["name"], 160, 21))
			srow.add_child(_row_label("%s · MP %d · %.1f초 시전 · 재사용 %.0f초" % [spi["desc"], spi["mp"], spi["time"], spi["cooldown"]], 420, 18, Color(0.72, 0.76, 0.8)))
			for qi in PlayerState.QUICK_SKILL_SLOTS:
				var on: bool = st.quick_skills[qi] == sid
				srow.add_child(_button(("[%d]" if on else "%d") % (qi + 5), func() -> void:
					st.assign_quick_skill(qi, "" if on else sid)
					_refresh_panel()))
			v.add_child(srow)
		v.add_child(_row_label("기본 스킬 — 일반 EXP로 스승 없이 습득 (패시브, 퀵슬롯 불필요)", 700, 22, Color(1.0, 0.9, 0.6)))
		for id: String in PlayerState.SKILLS:
			var sk: Dictionary = PlayerState.SKILLS[id]
			var row2 := HBoxContainer.new()
			var rank := st.skill_rank(id)
			row2.add_child(_row_label("%s %d/%d" % [sk["name"], rank, sk["max"]], 210, 21))
			row2.add_child(_row_label(sk["desc"], 230, 18, Color(0.72, 0.76, 0.8)))
			var cost := st.skill_cost(id)
			var b := _button("최대" if cost < 0 else "습득 (EXP %d)" % cost, func() -> void:
				if st.learn_skill(id):
					Game.combat_log.add("기본 스킬 습득: %s %d단계" % [sk["name"], st.skill_rank(id)], "", "info")
				_refresh_panel())
			b.disabled = cost < 0 or st.gen_exp < cost
			row2.add_child(b)
			v.add_child(row2)
		v.add_child(_button("닫기 (C)", close_panel)), 880)


# ---------------------------------------------------------------- dialogue / quests (P2-5)

## Opens a dialogue by id (data/dialogues). Returns false when the file is missing.
func start_dialogue(dialogue_id: String) -> bool:
	if dialogue_id == "" or dialogue.active():
		return false
	close_panel()
	return dialogue.play(dialogue_id)


func start_fishing(manual: bool, spot: Node3D) -> bool:
	close_panel()
	return fishing.start(manual, spot)


func dialogue_active() -> bool:
	return dialogue.active()


func show_caption(text: String) -> void:
	_caption.text = text


func toast_quest(text: String) -> void:
	if boot and boot.hud:
		boot.hud.toast(text)


func _quest_time_text(id: String) -> String:
	var left := Game.quests.time_left(id)
	if left < 0.0:
		return ""
	return "남은 시간 %d시간 %02d분" % [int(left) / 60, int(left) % 60]


func _tracker_text() -> String:
	var lines := PackedStringArray()
	for id: String in Game.quests.entries:
		if not Game.quests.is_open(id):
			continue
		var head := "◆ " + QuestDB.title(id)
		if Game.quests.state(id) == "ready":
			head += " — 보고하기"
		lines.append(head)
		for o in Game.quests.objectives_text(id):
			lines.append(o)
		var t := _quest_time_text(id)
		if t != "":
			lines.append(t)
		if lines.size() > 12:
			break
	if lines.is_empty():
		return ""
	return "퀘스트 (J)\n" + "\n".join(lines)


func toggle_journal() -> void:
	if _panel_kind == "journal":
		close_panel()
		return
	_open("journal", null, 0.0, func(v: VBoxContainer) -> void:
		v.add_child(_row_label("퀘스트 기록", 400, 26, Color(1.0, 0.9, 0.6)))
		var groups := {"open": [], "completed": [], "failed": []}
		for id: String in Game.quests.entries:
			var s := Game.quests.state(id)
			groups["open" if s in ["active", "ready"] else s].append(id)
		for g in [["open", "진행 중"], ["completed", "완료"], ["failed", "실패"]]:
			v.add_child(_row_label("%s (%d)" % [g[1], groups[g[0]].size()], 400, 22, Color(0.8, 0.86, 1.0)))
			if groups[g[0]].is_empty():
				v.add_child(_row_label("  없음", 400, 18, Color(0.6, 0.62, 0.66)))
			for id: String in groups[g[0]]:
				var q := QuestDB.info(id)
				var e: Dictionary = Game.quests.entries[id]
				var head := "  %s  [%s]" % [q.get("title", id), QuestDB.SOURCE_NAMES.get(q.get("source", ""), "")]
				if Game.quests.state(id) == "ready":
					head += " — 목표 달성, 보고하기"
				v.add_child(_row_label(head, 860, 20))
				var desc := _row_label("    " + str(q.get("desc", "")), 860, 17, Color(0.75, 0.77, 0.8))
				desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				desc.clip_text = false
				v.add_child(desc)
				if g[0] == "open":
					for o in Game.quests.objectives_text(id):
						v.add_child(_row_label("    " + o, 860, 18, Color(0.95, 0.9, 0.7)))
					var t := _quest_time_text(id)
					if t != "":
						v.add_child(_row_label("    " + t, 860, 18, Color(1.0, 0.6, 0.5)))
					v.add_child(_row_label("    보상: " + QuestDB.reward_text(QuestDB.rewards_for(id)), 860, 17, Color(0.7, 0.85, 0.7)))
				elif g[0] == "completed":
					var oc: String = e.get("outcome", "")
					var label := str(q.get("outcomes", {}).get(oc, {}).get("label", ""))
					v.add_child(_row_label("    %s완료 %d회 · 보상 %s" % ["결과: %s · " % label if label != "" else "", e.get("completions", 1),
						QuestDB.reward_text(QuestDB.rewards_for(id, oc))], 860, 17, Color(0.7, 0.85, 0.7)))
				elif q.get("repeatable", false):
					v.add_child(_row_label("    반복 의뢰 — 다시 받을 수 있다", 860, 17, Color(0.7, 0.8, 0.9)))
		v.add_child(_button("닫기 (J)", close_panel)), 920)


## Random dungeon gate: the GDD 12.2 warning before entering, then enter / leave it.
func open_rift_gate(ex: Dictionary, source: Node3D) -> void:
	var info: Dictionary = RegionDB.all().get(str(ex["to_region"]), {})
	_open("rift_gate", source, 3.0, func(v: VBoxContainer) -> void:
		v.add_child(_row_label("%s  (위험도 %s)" % [info.get("name", ""), RegionDB.danger_text(str(ex["to_region"]))], 700, 26, Color(0.85, 0.7, 1.0)))
		var warn := _row_label("⚠ " + str(info.get("warning", "")), 700, 20, Color(1.0, 0.85, 0.6))
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.clip_text = false
		v.add_child(warn)
		var row := HBoxContainer.new()
		row.add_child(_button("들어간다", func() -> void:
			close_panel()
			Game.start_run(str(ex["to_region"]))
			boot.travel(str(ex["to_region"]), str(ex["to_entry"]), false), 220))
		row.add_child(_button("그만둔다", close_panel, 220))
		v.add_child(row), 760)


## Random dungeon floor exit (GDD 12.2): leave safely with everything found so far, or go down.
func open_floor_exit(source: Node3D) -> void:
	if not Game.in_run():
		return
	_open("floor_exit", source, 3.0, func(v: VBoxContainer) -> void:
		var did: String = Game.run["dungeon"]
		var f := int(Game.run["floor"])
		v.add_child(_row_label("%s %d층 출구" % [RegionDB.region_name(did), f], 700, 26, Color(0.85, 0.7, 1.0)))
		var gained := Game.run_gained()
		var names := PackedStringArray()
		for id: String in gained:
			names.append("%s ×%d" % [ItemDB.item_name(id), gained[id]])
		var got := _row_label("이번 탐험에서 얻은 것: " + (", ".join(names) if not names.is_empty() else "아직 없음"), 700, 19)
		got.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		got.clip_text = false
		v.add_child(got)
		v.add_child(_row_label("아래층은 상자가 더 풍성하고 몬스터가 더 강하다. 쓰러지면 위의 것을 모두 잃는다.", 700, 17, Color(0.75, 0.77, 0.8)))
		var row := HBoxContainer.new()
		row.add_child(_button("탈출 — 가지고 밖으로", func() -> void:
			close_panel()
			var ent: Dictionary = RegionDB.all()[did].get("entrance", {})
			Game.end_run(true)
			Game.combat_log.add("%s에서 탈출 (%d층)" % [RegionDB.region_name(did), f], "가지고 나온 것: %s" % (", ".join(names) if not names.is_empty() else "없음"), "info")
			boot.travel(str(ent.get("region", RegionDB.START)), str(ent.get("entry", "")), false), 280))
		row.add_child(_button("아래층으로 (%d층)" % (f + 1), func() -> void:
			close_panel()
			Game.next_floor()
			boot.travel(did, "start", false), 240))
		v.add_child(row), 760)


# ---------------------------------------------------------------- cooking & crafting (P3-5)

## Facility type within reach of the player ("" = none: simple crafting only).
func nearby_facility() -> String:
	var p := _player()
	if p == null:
		return ""
	for ip in get_tree().get_nodes_in_group("facility"):
		if is_instance_valid(ip) and (ip as Node3D).is_visible_in_tree() and (ip as Node3D).global_position.distance_to(p.global_position) < 2.6:
			return str(ip.get_meta("facility", ""))
	return ""


func toggle_crafting() -> void:
	if _panel_kind == "craft":
		close_panel()
		return
	open_crafting(nearby_facility(), null)


func _recipe_block(rid: String, facility: String) -> String:
	var r := RecipeDB.info(rid)
	var f: String = r.get("facility", "")
	if f != "" and f != facility:
		return "%s 필요" % RecipeDB.facility_name(f)
	var inputs: Dictionary = r.get("inputs", {})
	for item: String in inputs:
		if Game.player_state.inventory.count(item) < int(inputs[item]):
			return "재료 부족: %s" % ItemDB.item_name(item)
	return ""


## Recipe panel (GDD 14.4): learned recipes only, ingredients are used up, the result is made.
func open_crafting(facility: String, source: Node3D) -> void:
	_open("craft", source, 3.0, func(v: VBoxContainer) -> void:
		var st := Game.player_state
		var where := RecipeDB.facility_name(facility) if facility != "" else "시설 없음 — 간단한 제작만"
		v.add_child(_row_label("요리·제작 — %s" % where, 900, 26, Color(1.0, 0.9, 0.6)))
		v.add_child(_row_label("생활 EXP %d · 요리 Lv %d · 제작 Lv %d" % [st.life_exp, st.mastery_level("cooking"), st.mastery_level("crafting")], 900, 18, Color(0.75, 0.9, 0.75)))
		v.add_child(_row_label("배운 레시피", 400, 21, Color(0.8, 0.86, 1.0)))
		var specials := []
		var learnable := []
		for rid: String in RecipeDB.all():
			var r := RecipeDB.info(rid)
			if not st.knows_recipe(rid):
				(specials if r.get("learn", "") == "special" else learnable).append(rid)
				continue
			var row := HBoxContainer.new()
			row.add_child(_row_label("  " + str(r.get("name", rid)), 170, 19))
			var parts := PackedStringArray()
			var inputs: Dictionary = r.get("inputs", {})
			for item: String in inputs:
				parts.append("%s %d/%d" % [ItemDB.item_name(item), st.inventory.count(item), int(inputs[item])])
			row.add_child(_row_label(" + ".join(parts), 400, 17, Color(0.85, 0.85, 0.8)))
			var fac: String = r.get("facility", "")
			row.add_child(_row_label("어디서나" if fac == "" else ("모닥불·주방" if fac == "cooking" else "작업대"), 110, 17, Color(0.7, 0.78, 0.9)))
			var block := _recipe_block(rid, facility)
			var b := _button("만들기", func() -> void: craft(rid, facility), 120)
			b.disabled = block != ""
			b.tooltip_text = block if block != "" else "→ " + RecipeDB.outputs_text(rid)
			row.add_child(b)
			v.add_child(row)
		v.add_child(_row_label("기본 레시피 배우기 (생활 EXP)", 400, 21, Color(0.8, 0.86, 1.0)))
		if learnable.is_empty():
			v.add_child(_row_label("  모두 배웠다", 400, 17, Color(0.6, 0.62, 0.66)))
		for rid: String in learnable:
			var r2 := RecipeDB.info(rid)
			var row2 := HBoxContainer.new()
			row2.add_child(_row_label("  %s — %s → %s" % [r2.get("name", rid), RecipeDB.inputs_text(rid), RecipeDB.outputs_text(rid)], 640, 17))
			var blk := st.recipe_learn_block(rid)
			var lb := _button("배우기 (생활 EXP %d)" % int(r2.get("cost", 0)), func() -> void:
				if st.buy_recipe(rid):
					boot.hud.toast("레시피 습득: " + RecipeDB.recipe_name(rid))
				_refresh_panel(), 200)
			lb.disabled = blk != ""
			lb.tooltip_text = blk
			row2.add_child(lb)
			v.add_child(row2)
		if not specials.is_empty():
			v.add_child(_row_label("특수 레시피 (아직 모름)", 400, 21, Color(0.8, 0.86, 1.0)))
			for rid: String in specials:
				v.add_child(_row_label("  ??? — 얻는 곳: %s" % RecipeDB.info(rid).get("source", "NPC·책·퀘스트·탐험"), 900, 17, Color(0.65, 0.66, 0.72)))
		v.add_child(_button("닫기 (U)", close_panel)), 960)


## Crafting motion (same rules as using an item: a hit stops it and nothing is used up).
func craft(rid: String, facility: String) -> bool:
	var p := _player()
	if p == null or _recipe_block(rid, facility) != "" or not Game.player_state.knows_recipe(rid):
		return false
	var r := RecipeDB.info(rid)
	var field: String = r.get("field", "cooking")
	var lv := Game.player_state.mastery_level(field)
	var time := float(r.get("time", 2.0)) * maxf(0.5, 1.0 - 0.04 * (lv - 1))
	return p.begin_task("%s 만드는 중" % r.get("name", rid), time, 0.0, "cast", func() -> void: _crafted(rid, facility))


func _crafted(rid: String, facility: String) -> void:
	var st := Game.player_state
	if _recipe_block(rid, facility) != "":
		return
	var r := RecipeDB.info(rid)
	var inputs: Dictionary = r.get("inputs", {})
	for item: String in inputs:
		st.inventory.remove(item, int(inputs[item]))
	var field: String = r.get("field", "cooking")
	var bonus := randf() < 0.06 * (st.mastery_level(field) - 1)  # mastery: a little extra now and then
	var outs: Dictionary = r.get("outputs", {})
	var made := PackedStringArray()
	for item: String in outs:
		var n := int(outs[item]) + (1 if bonus else 0)
		st.inventory.add(item, n)
		made.append("%s ×%d" % [ItemDB.item_name(item), n])
	var lexp := int(r.get("life_exp", 2))
	st.life_exp += lexp
	var up := st.add_mastery(field, int(r.get("mastery", 3)))
	var text := "%s 완성 — %s%s · 생활 EXP +%d" % [r.get("name", rid), ", ".join(made), " (숙련 보너스!)" if bonus else "", lexp]
	Game.combat_log.add(text, "%s — %s 숙련도 %d" % [RecipeDB.inputs_text(rid), LifeDB.field_name(field), st.mastery[field]], "info")
	boot.hud.toast(text + ("  ▲ %s 숙련도 Lv %d" % [LifeDB.field_name(field), up] if up > 0 else ""))
	st.changed.emit()
	_refresh_panel()


## World map (GDD 11.3 [확정]): regions and roads are known from the start; checkpoints and
## other places appear once visited. Pin UI / fog / notes are [미정] - this is a plain overview.
func toggle_map() -> void:
	if _panel_kind == "map":
		close_panel()
		return
	_open("map", null, 0.0, func(v: VBoxContainer) -> void:
		v.add_child(_row_label("월드맵", 400, 26, Color(1.0, 0.9, 0.6)))
		var m := WorldMap.new()
		m.font = font
		m.custom_minimum_size = Vector2(1100, 560)
		v.add_child(m)
		var cam_text := "캠핑카: %s" % RegionDB.region_name(str(Game.camper.get("region", ""))) if Game.has_camper else "캠핑카: 아직 없음"
		v.add_child(_row_label("● 현재 위치   ▲ 체크포인트(방문한 곳)   ■ %s   — 길   ⇄ 지역 연결 도로" % cam_text, 1100, 18, Color(0.8, 0.82, 0.86)))
		v.add_child(_button("닫기 (M)", close_panel)), 1160)


## Trade post notice board (GDD 13.1: board requests must be accepted directly).
func open_board(source: Node3D) -> void:
	_open("board", source, 3.0, func(v: VBoxContainer) -> void:
		v.add_child(_row_label("교역소 게시판", 400, 26, Color(1.0, 0.9, 0.6)))
		for id: String in QuestDB.all():
			var q: Dictionary = QuestDB.all()[id]
			if q.get("source", "") != "board":
				continue
			var s := Game.quests.state(id)
			var row := HBoxContainer.new()
			var head := q.get("title", id) as String
			if q.get("repeatable", false):
				head += "  (반복)"
			if float(q.get("time_limit_hours", 0)) > 0.0:
				head += "  (제한 %d시간)" % int(q["time_limit_hours"])
			row.add_child(_row_label(head, 640, 21))
			var b: Button
			match s:
				"ready":
					b = _button("보고하기", func() -> void: Game.quests.complete(id), 150)
				"active":
					b = _button("진행 중", func() -> void: pass, 150)
					b.disabled = true
				_:
					var again: bool = s in ["completed", "failed"]
					b = _button("다시 수락" if again else "수락", func() -> void: Game.quests.accept(id), 150)
					b.disabled = not Game.quests.can_accept(id)
					if b.disabled:
						b.text = "완료"
			row.add_child(b)
			v.add_child(row)
			var desc := _row_label("  " + str(q.get("desc", "")), 800, 17, Color(0.75, 0.77, 0.8))
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.clip_text = false
			v.add_child(desc)
			var info := "  보상: %s" % QuestDB.reward_text(QuestDB.rewards_for(id))
			if s in ["active", "ready"]:
				info += "  —  " + "  ".join(Game.quests.objectives_text(id))
				var t := _quest_time_text(id)
				if t != "":
					info += "  ·  " + t
			elif s == "failed":
				info += "  ·  지난번엔 실패 — 다시 받을 수 있다"
			v.add_child(_row_label(info, 800, 17, Color(0.7, 0.85, 0.7)))
		v.add_child(_button("닫기 (E)", close_panel)), 860)


func _on_player_changed() -> void:
	if _panel_kind in ["inventory", "loot", "storage", "character", "shop", "journal", "board", "craft"]:
		_refresh_panel()


func _process(delta: float) -> void:
	var st := Game.player_state
	_set_bar("hp", st.hp, st.max_hp())
	_set_bar("sp", st.sp, st.max_sp())
	_set_bar("mp", st.mp, st.max_mp())
	var lines := PackedStringArray()
	lines.append("Lv %d · EXP %d / %d%s" % [st.level, st.gen_exp, st.exp_to_next(),
		"  ▲ 레벨업 가능 (C)" if st.can_level_up() else ("  ● 능력치 포인트 %d (C)" % st.stat_points if st.stat_points > 0 else "")])
	lines.append("%s %s · %d일차 · %d 골드" % [Game.clock_text(), "밤" if Game.is_night() else "낮", Game.day, st.gold])
	var wl := "중량 %.1f / %.0f kg (한계 %.0f)" % [st.carried_weight(), st.carry_capacity(), st.carry_limit()]
	if st.speed_factor() < 0.999:
		wl += " — %s, 이동 ×%.2f" % [st.weight_state(), st.speed_factor()]
	lines.append(wl)
	if Game.in_run():
		var gained := Game.run_gained()
		var n := 0
		for id: String in gained:
			n += int(gained[id])
		lines.append("%s %d층 · 이번 탐험 획득 %d개 (쓰러지면 모두 잃음)" % [RegionDB.region_name(str(Game.run["dungeon"])), int(Game.run["floor"]), n])
	else:
		lines.append("지역 %s · 위험도 %s (M 지도)" % [RegionDB.region_name(Game.region), RegionDB.danger_text(Game.region)] if boot and boot.world is VisualLab else "캠핑카 실내")
	lines.append("진행 %s (F9)" % Game.STAGE_NAMES[Game.story_stage()])
	if Game.cat_joined:
		lines.append("고양이 호감도 %d / %d" % [Game.cat_affection, Game.CAT_AFFECTION_MAX])
	_info.text = "\n".join(lines)
	_info.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5) if st.speed_factor() < 0.999 else Color(1, 1, 1))
	var w: Node = boot.world if boot else null
	var text := ""
	if w and is_instance_valid(w) and w.get("player") and not _panel:
		var p: PrototypePlayer = w.player
		if p.focus and is_instance_valid(p.focus) and p.controls_enabled and not p.dead:
			text = p.focus.prompt_text()
		if text == "" and w.has_method("context_hint"):
			text = w.context_hint()
	var pl := _player()
	if pl and pl.is_using():
		var n := int(pl.use_progress() * 10.0)
		text = "%s  %s%s  (맞으면 중단)" % [pl.use_label(), "▮".repeat(n), "▯".repeat(10 - n)]
	if dialogue.active() or cutscene.playing or fishing.active:
		text = ""
	_prompt.text = text
	_update_quickbar()
	_tracker_t -= delta
	if _tracker_t <= 0.0:
		_tracker_t = 0.25
		_tracker.text = _tracker_text()
	# The detailed log would show through an open panel: collapse it to one line meanwhile.
	var want_detail := Game.combat_log.level == 3 and _panel == null
	if _log_detail.visible != want_detail:
		_log_detail.visible = want_detail
		_log_box.reset_size()
	_log_box.position = Vector2(22, 1004 - _log_box.size.y)
	_update_floats(delta)
	if _panel and _panel_source:
		var p2: Node3D = w.player if w else null
		if not is_instance_valid(_panel_source) or p2 == null \
				or Vector2(p2.global_position.x - _panel_source.global_position.x, p2.global_position.z - _panel_source.global_position.z).length() > _panel_range:
			close_panel()
