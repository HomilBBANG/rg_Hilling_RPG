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
	_fade_label = _label("", 40, Vector2(0, 500))
	_fade_label.size = Vector2(1920, 60)
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_label.modulate.a = 0.0
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
		using_id = p._use["id"]
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
		v.add_child(_row_label("생활 EXP %d (생활 활동·퀘스트로 획득 — 아직 획득처 없음) · 자동 레벨업 없음" % st.life_exp, 760, 18, Color(0.7, 0.75, 0.8)))
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


func _on_player_changed() -> void:
	if _panel_kind in ["inventory", "loot", "storage", "character"]:
		_refresh_panel()


func _process(delta: float) -> void:
	var st := Game.player_state
	_set_bar("hp", st.hp, st.max_hp())
	_set_bar("sp", st.sp, st.max_sp())
	_set_bar("mp", st.mp, st.max_mp())
	var lines := PackedStringArray()
	lines.append("Lv %d · EXP %d / %d%s" % [st.level, st.gen_exp, st.exp_to_next(),
		"  ▲ 레벨업 가능 (C)" if st.can_level_up() else ("  ● 능력치 포인트 %d (C)" % st.stat_points if st.stat_points > 0 else "")])
	lines.append("%s %s · %d일차" % [Game.clock_text(), "밤" if Game.is_night() else "낮", Game.day])
	var wl := "중량 %.1f / %.0f kg (한계 %.0f)" % [st.carried_weight(), st.carry_capacity(), st.carry_limit()]
	if st.speed_factor() < 0.999:
		wl += " — %s, 이동 ×%.2f" % [st.weight_state(), st.speed_factor()]
	lines.append(wl)
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
	_prompt.text = text
	_update_quickbar()
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
