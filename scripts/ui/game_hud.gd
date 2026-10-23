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
var overlay: CutsceneOverlay
var _talk_hidden: Array[CanvasItem] = []
var fishing: FishingPanel
var cutscene: CutsceneRunner
var _caption: Label
var _tracker: Label
var _tracker_t := 0.0
var minimap: Minimap
## Boss HP bar across the top (the dragon): the boss node it follows, or null when hidden.
var boss: Node
var _boss_box: Control
var _boss_fill: ColorRect
var _boss_name: Label
var _save_note: Label
var _save_note_t := 0.0
## Hover description box: stats, derived numbers, skills and every panel tooltip show here
## (a framed box beside the mouse) instead of inline text.
var _tip: PanelContainer
var _tip_title: Label
var _tip_body: Label
var _tip_owner: Control
## Character sheet: stat points planned but not yet confirmed (stat key -> amount).
var stat_plan := {}


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
	minimap = Minimap.new()
	minimap.font = font
	minimap.hud = self
	minimap.position = Vector2(1920 - 22 - Minimap.SIZE, 18)
	add_child(minimap)
	_tracker = _label("", 19, Vector2(1440, 18 + Minimap.SIZE + 34))  # under the minimap
	_tracker.size = Vector2(458, 0)
	_tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tracker.add_theme_color_override("font_color", Color(1.0, 0.93, 0.75))
	cutscene = CutsceneRunner.new()
	add_child(cutscene)
	overlay = CutsceneOverlay.new()
	add_child(overlay)
	dialogue = DialogueBox.new()
	dialogue.cutscenes = cutscene
	add_child(dialogue)
	add_child(overlay.fade_rect)  # a cutscene fade covers the dialogue window too
	cutscene.overlay = overlay
	cutscene.dialogue = dialogue
	fishing = FishingPanel.new()
	add_child(fishing)
	_caption = _label("", 28, Vector2(0, 760))
	_caption.size = Vector2(1920, 50)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	_build_boss_bar()
	_save_note = _label("", 20, Vector2(24, 912))
	_save_note.add_theme_color_override("font_color", Color(0.7, 1.0, 0.65))
	move_child(_fade, -1)
	move_child(_fade_label, -1)
	_build_tip()
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
	if _panel_kind == "character" and _plan_total() > 0:
		boot.hud.toast("확정하지 않은 능력치 투자는 취소했다")
	stat_plan.clear()
	_hide_tip()
	if _panel:
		_panel.queue_free()
	_panel = null
	_panel_source = null
	_panel_kind = ""
	_panel_refresh = Callable()


# ---------------------------------------------------------------- hover description box

func _build_tip() -> void:
	_tip = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.055, 0.075, 0.97)
	sb.border_color = Color(0.85, 0.7, 0.42)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	_tip.add_theme_stylebox_override("panel", sb)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(v)
	_tip_title = Label.new()
	_tip_title.add_theme_font_size_override("font_size", 21)
	_tip_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	v.add_child(_tip_title)
	_tip_body = Label.new()
	_tip_body.add_theme_font_size_override("font_size", 18)
	_tip_body.add_theme_color_override("font_color", Color(0.88, 0.9, 0.92))
	_tip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_body.custom_minimum_size.x = 360
	v.add_child(_tip_body)
	add_child(_tip)


## Gives a control a hover description (title + body) shown in the framed box beside the mouse.
func tip(c: Control, title: String, body := "") -> Control:
	if c is Label:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.set_meta("tip", [title, body])
	if not c.has_meta("tip_hooked"):
		c.set_meta("tip_hooked", true)
		c.mouse_entered.connect(func() -> void: show_tip(c))
		c.mouse_exited.connect(func() -> void:
			if _tip_owner == c:
				_hide_tip())
	return c


func show_tip(c: Control) -> void:
	var t: Array = c.get_meta("tip", ["", ""])
	_tip_owner = c
	_tip_title.text = str(t[0])
	_tip_title.visible = str(t[0]) != ""
	_tip_body.text = str(t[1])
	_tip_body.visible = str(t[1]) != ""
	var widest := 0.0  # short texts get a small box, long ones wrap at 360 px
	for line in str(t[1]).split("\n"):
		widest = maxf(widest, _tip_body.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x)
	_tip_body.custom_minimum_size.x = minf(360.0, widest + 4.0)
	_tip.size = Vector2.ZERO
	_tip.visible = true
	_tip.move_to_front()
	_tip.reset_size()
	_place_tip()


func _hide_tip() -> void:
	_tip_owner = null
	if _tip:
		_tip.visible = false


func tip_text() -> String:
	return "%s | %s" % [_tip_title.text, _tip_body.text] if _tip and _tip.visible else ""


func _place_tip() -> void:
	var screen := Vector2(1920, 1080)  # the HUD's layout space (panels are placed in it too)
	var m := get_global_mouse_position() + Vector2(20, 24)
	var sz := _tip.size
	if m.x + sz.x > screen.x - 8:
		m.x = get_global_mouse_position().x - sz.x - 12
	if m.y + sz.y > screen.y - 8:
		m.y = screen.y - 8 - sz.y
	m.y = maxf(8.0, m.y)
	_tip.position = m


## Panel buttons that had a plain tooltip use the same box (one look for every hover text).
func _adopt_tooltips(root: Node) -> void:
	for c in root.get_children():
		if c is Control and (c as Control).tooltip_text != "":
			tip(c, "", c.tooltip_text)
			c.tooltip_text = ""
		_adopt_tooltips(c)


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
		_adopt_tooltips(_panel)
		_panel.reset_size()
		_panel.position = Vector2(960 - _panel.size.x * 0.5, 470 - _panel.size.y * 0.5)
		if kind in ["inventory", "character", "skills"]:
			_panel.position.y = 40.0  # the two tabs of one window: same place, the tab bar doesn't jump
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
	return Game.storage.weight() + w <= Game.storage_capacity() + 0.0001


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
		bottom.add_child(_button("전부 가져가기 (Space)", loot_take_all))
		bottom.add_child(_button("닫기 (E)", close_panel))
		v.add_child(bottom))


## "전부 가져가기" (button or Space): takes everything the player can carry; the window closes
## by itself once the container is empty (user request). Too heavy → the rest stays, window stays.
func loot_take_all() -> void:
	if _panel_kind != "loot" or not is_instance_valid(_panel_source):
		return
	var inv: Inventory = (_panel_source as LootContainer).inventory()
	for e in inv.duplicate_items():
		var id: String = e["id"]
		var n: int = e["count"]
		var got := _move(inv, Game.player_state.inventory, id, n, _player_can_take)
		if got > 0:
			Game.combat_log.add("획득: %s ×%d" % [ItemDB.item_name(id), got], "", "info")
		if got < n and inv.count(id) > 0:
			_too_heavy_toast()
	if inv.is_empty():
		close_panel()
	else:
		_refresh_panel()


## Space in the loot window = 전부 가져가기 (buttons never take focus, so the key is free).
func _input(ev: InputEvent) -> void:
	if _panel_kind == "loot" and ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_SPACE:
		loot_take_all()
		get_viewport().set_input_as_handled()


## The character window: one panel with tabs on top — 소지품·장비 (Tab) and 능력치 (C).
func _window_tabs(v: VBoxContainer, active: String) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	for t: Array in [["inventory", "소지품 · 장비  (Tab)"], ["character", "능력치  (C)"], ["skills", "스킬  (K)"]]:
		var kind: String = t[0]
		var b := _button(t[1], func() -> void: _open_window_tab(kind), 230)
		b.toggle_mode = true
		b.button_pressed = kind == active
		if kind == active:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.5, 0.36, 0.16)
			sb.border_color = Color(0.95, 0.78, 0.45)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(4)
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			for st_name in ["normal", "pressed", "hover"]:
				b.add_theme_stylebox_override(st_name, sb)
		bar.add_child(b)
	v.add_child(bar)


func _open_window_tab(kind: String) -> void:
	if _panel_kind == kind:
		return
	if kind == "inventory":
		toggle_inventory()
	elif kind == "character":
		toggle_character()
	else:
		toggle_skills()


const INV_BORDER := Color(0.46, 0.46, 0.48)  ## frames, cell lines, weight bar (gray)
const INV_CELL := 84
const INV_COLS := 7
const INV_MIN_ROWS := 7
## Equipment layout (user mockup): 3 columns × 3 rows, then the two hands below.
const EQUIP_GRID := [["back", "head", "neck"], ["belt", "body", "ring1"], ["hands", "feet", "ring2"]]
const KIND_COLORS := {"equip": Color(0.45, 0.62, 0.9), "consumable": Color(0.5, 0.82, 0.5), "camper": Color(0.9, 0.62, 0.3),
	"decor": Color(0.82, 0.55, 0.82), "tool": Color(0.75, 0.7, 0.55)}
## Slot captions in the window (user mockup wording; ItemDB.SLOT_NAMES elsewhere).
const SLOT_CAPTIONS := {"main": "주무기", "off": "보조무기", "body": "몸"}
## Selected thing in the inventory window: {"bag": item id} or {"slot": slot key}.
var _inv_sel := {}


func _framed(child: Control, pad := 14) -> PanelContainer:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.11, 0.7)
	sb.border_color = INV_BORDER
	sb.set_border_width_all(2)
	sb.set_content_margin_all(pad)
	box.add_theme_stylebox_override("panel", sb)
	box.add_child(child)
	return box


## One square cell (equipment slot or bag stack): caption on top, name in the middle, count corner.
func _cell(caption: String, name: String, count: int, edge: Color, selected: bool, cb: Callable, dbl := Callable()) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(INV_CELL, INV_CELL)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.25, 0.25, 0.26), "hover": Color(0.34, 0.33, 0.3), "pressed": Color(0.4, 0.36, 0.28),
			"disabled": Color(0.2, 0.2, 0.2)}[state]
		if selected:
			sb.bg_color = Color(0.42, 0.34, 0.18)
		sb.border_color = Color(1.0, 0.85, 0.45) if selected else edge
		sb.set_border_width_all(3 if selected else 2)
		b.add_theme_stylebox_override(state, sb)
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.double_click and dbl.is_valid():
				dbl.call()
			else:
				cb.call())
	if caption != "":
		var c := Label.new()
		c.text = caption
		c.add_theme_font_size_override("font_size", 14)
		c.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78))
		c.position = Vector2(5, 2)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(c)
	var n := Label.new()
	n.text = name
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.add_theme_font_size_override("font_size", 15 if caption == "" else 14)
	n.position = Vector2(3, 16 if caption != "" else 4)
	n.size = Vector2(INV_CELL - 6, INV_CELL - (22 if caption != "" else 10))
	n.max_lines_visible = 3
	n.clip_text = true
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(n)
	if count > 1:
		var k := Label.new()
		k.text = "×%d" % count
		k.add_theme_font_size_override("font_size", 15)
		k.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
		k.position = Vector2(INV_CELL - 34, INV_CELL - 24)
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(k)
	return b


## Hover text for an item: weight, what it does, and how to use it here.
func _item_tip(id: String, count: int, where: String) -> String:
	var lines := PackedStringArray()
	var w := ItemDB.weight(id)
	lines.append("무게 %.1f kg%s" % [w, " × %d = %.1f kg" % [count, w * count] if count > 1 else ""])
	if ItemDB.is_equipment(id):
		lines.append(ItemDB.equip_summary(id))
	elif ItemDB.is_consumable(id):
		var ci := ItemDB.info(id)
		var ut: Dictionary = ItemDB.USE_TYPES[ci["use"]]
		lines.append("%s · %s %.1f초%s" % [ItemDB.effect_text(ci["effect"]), ut["name"].replace(" 중", ""), ut["time"],
			" (천천히 이동 가능)" if ut["move"] > 0.0 else " (멈춰서)"])
	var desc := str(ItemDB.info(id).get("desc", ""))
	if desc != "":
		lines.append(desc)
	if where == "slot":
		lines.append("클릭: 선택 · 더블클릭: 해제")
	elif ItemDB.is_equipment(id) or ItemDB.is_consumable(id):
		lines.append("클릭: 선택 · 더블클릭: %s" % ("장착" if ItemDB.is_equipment(id) else "사용"))
	else:
		lines.append("클릭: 선택")
	return "\n".join(lines)


func toggle_inventory() -> void:
	if _panel_kind == "inventory":
		close_panel()
		return
	_inv_sel = {}
	var st := Game.player_state
	_open("inventory", null, 0.0, func(v: VBoxContainer) -> void:
		_window_tabs(v, "inventory")
		var p := _player()
		var swapping: bool = p != null and p.is_swapping()
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 24)
		v.add_child(cols)
		# ---- left: equipment slots, weight, selected item
		var left := VBoxContainer.new()
		left.add_theme_constant_override("separation", 10)
		cols.add_child(left)
		var eq := VBoxContainer.new()
		eq.add_theme_constant_override("separation", 8)
		for row: Array in EQUIP_GRID + [["main", "", "off"]]:
			if row[0] == "main":
				var gap := Control.new()
				gap.custom_minimum_size.y = 44
				eq.add_child(gap)
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 92)
			for slot: String in row:
				if slot == "":
					var sp := Control.new()
					sp.custom_minimum_size = Vector2(INV_CELL, INV_CELL)
					h.add_child(sp)
					continue
				h.add_child(_slot_cell(slot, swapping))
			eq.add_child(h)
		left.add_child(_framed(eq, 22))
		left.add_child(_weight_bar())
		left.add_child(_row_label("방어 %d · 명중 +%d · 치명 %d%% · 무기 %s%s" % [st.total_armor(), st.total_hit_bonus(),
			st.total_crit_chance(), st.weapon()["name"], "   — 장비 교체 중…" if swapping else ""], 520, 18, Color(0.75, 0.88, 0.75)))
		left.add_child(_selected_box(swapping))
		# ---- right: bag grid + sort
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", 8)
		cols.add_child(right)
		var grid := GridContainer.new()
		grid.columns = INV_COLS
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		var items := st.inventory.items
		var cells := maxi(INV_COLS * INV_MIN_ROWS, ceili(items.size() / float(INV_COLS)) * INV_COLS)
		for i in cells:
			if i < items.size():
				var id: String = items[i]["id"]
				var count: int = items[i]["count"]
				var c := _cell("", ItemDB.item_name(id), count, KIND_COLORS.get(str(ItemDB.info(id).get("kind", "")), INV_BORDER),
					_inv_sel.get("bag", "") == id, func() -> void:
						_inv_sel = {"bag": id}
						_refresh_panel(),
					func() -> void: _inv_default_action(id, swapping))
				tip(c, ItemDB.item_name(id), _item_tip(id, count, "bag"))
				grid.add_child(c)
			else:
				var empty := Panel.new()
				empty.custom_minimum_size = Vector2(INV_CELL, INV_CELL)
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(0.25, 0.25, 0.26)
				sb.border_color = INV_BORDER
				sb.set_border_width_all(1)
				empty.add_theme_stylebox_override("panel", sb)
				grid.add_child(empty)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(INV_COLS * (INV_CELL + 4) + 8, INV_MIN_ROWS * (INV_CELL + 4))
		scroll.add_child(grid)
		right.add_child(_framed(scroll, 10))
		var bottom := HBoxContainer.new()
		var sort := _button("정렬", func() -> void:
			st.inventory.sort()
			_refresh_panel(), 90)
		sort.tooltip_text = "장비 → 소모품 → 재료 → 캠핑카 용품 → 소품 순, 같은 종류는 이름순"
		bottom.add_child(sort)
		bottom.add_child(_row_label("  %d종 · 칸 제한 없음 (중량만)" % items.size(), 360, 17, Color(0.7, 0.74, 0.78)))
		right.add_child(bottom), 1240)


func _slot_cell(slot: String, swapping: bool) -> Button:
	var st := Game.player_state
	var id: String = st.equipment.get(slot, "")
	var name := "" if id == "" else ItemDB.item_name(id)
	if slot == "off" and st.two_handed():
		name = "(양손 무기)"
	var c := _cell(SLOT_CAPTIONS.get(slot, ItemDB.SLOT_NAMES[slot]), name, 0, Color(0.1, 0.2, 0.25) if id == "" else Color(0.45, 0.62, 0.9),
		_inv_sel.get("slot", "") == slot, func() -> void:
			_inv_sel = {"slot": slot}
			_refresh_panel(),
		func() -> void:
			if id != "" and not swapping:
				_change_gear(func() -> void: st.unequip(slot), "%s 해제" % ItemDB.item_name(id)))
	if id != "":
		tip(c, "%s — %s" % [ItemDB.SLOT_NAMES[slot], ItemDB.item_name(id)], _item_tip(id, 1, "slot"))
	else:
		tip(c, ItemDB.SLOT_NAMES[slot], "비어 있다" + ("\n(망토·배낭 등을 걸 자리 — 아직 맞는 장비가 없다)" if slot == "back" else ""))
	return c


## Carried weight: bag + worn equipment, as a bar (the line marks where slowing starts).
func _weight_bar() -> Control:
	var st := Game.player_state
	var w := st.carried_weight()
	var cap := st.carry_capacity()
	var lim := st.carry_limit()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(520, 40)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.13)
	sb.border_color = INV_BORDER
	sb.set_border_width_all(2)
	bar.add_theme_stylebox_override("panel", sb)
	var fill := ColorRect.new()
	var frac := clampf(w / lim, 0.0, 1.0) if lim > 0.0 else 0.0
	fill.color = Color(0.32, 0.55, 0.3) if w <= cap else (Color(0.8, 0.6, 0.2) if w < lim - 0.001 else Color(0.8, 0.28, 0.22))
	fill.position = Vector2(2, 2)
	fill.size = Vector2((520 - 4) * frac, 36)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	var mark := ColorRect.new()
	mark.color = Color(1.0, 0.9, 0.6, 0.8)
	mark.position = Vector2(2 + (520 - 4) * cap / lim, 2)
	mark.size = Vector2(2, 36)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(mark)
	var lbl := Label.new()
	lbl.text = "소지 중량 · %s" % st.weight_state()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(520, 40)
	lbl.add_theme_font_size_override("font_size", 21)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(lbl)
	tip(bar, "소지 중량", "가방 %.1f kg + 착용 장비 %.1f kg = %.1f kg\n%.0f kg까지 보통 속도, 넘으면 느려짐(현재 ×%.2f), %.0f kg부터 더 주울 수 없음.\n힘(STR)·짐 꾸리기 요령·장비로 늘어난다." % [
		st.inventory.weight(), st.equipped_weight(), w, cap, st.speed_factor(), lim])
	box.add_child(bar)
	var num := _row_label("%.1f / %.0f kg  (한계 %.0f)" % [w, cap, lim], 520, 18, Color(0.85, 0.88, 0.9))
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(num)
	return box


## Details + actions for whatever is selected (bag item or equipment slot).
func _selected_box(swapping: bool) -> Control:
	var st := Game.player_state
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(520, 150)
	var id := ""
	var from_slot := str(_inv_sel.get("slot", ""))
	if from_slot != "":
		id = st.equipment.get(from_slot, "")
	elif _inv_sel.has("bag") and st.inventory.count(str(_inv_sel["bag"])) > 0:
		id = str(_inv_sel["bag"])
	if id == "":
		v.add_child(_row_label("칸을 클릭하면 여기서 사용·장착·해제할 수 있다 (더블클릭 = 바로)", 520, 17, Color(0.7, 0.74, 0.78)))
		return v
	v.add_child(_row_label(ItemDB.item_name(id), 520, 22, Color(1.0, 0.9, 0.6)))
	var info := Label.new()
	info.text = _item_tip(id, 1 if from_slot != "" else st.inventory.count(id), "slot" if from_slot != "" else "bag").get_slice("\n클릭", 0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 520
	info.add_theme_font_size_override("font_size", 17)
	info.add_theme_color_override("font_color", Color(0.78, 0.8, 0.84))
	v.add_child(info)
	var h := HFlowContainer.new()
	v.add_child(h)
	if from_slot != "":
		var ub := _button("해제", func() -> void: _change_gear(func() -> void: st.unequip(from_slot), "%s 해제" % ItemDB.item_name(id)))
		ub.disabled = swapping
		h.add_child(ub)
		return v
	var kind := str(ItemDB.info(id).get("kind", ""))
	if ItemDB.is_equipment(id):
		var slot := st.target_slot(id)
		var eb := _button("장착 (%s)" % ItemDB.SLOT_NAMES[slot], func() -> void:
			_change_gear(func() -> void: st.equip(id), "%s 장착" % ItemDB.item_name(id)))
		eb.disabled = swapping
		h.add_child(eb)
	if ItemDB.is_consumable(id):
		var reading: bool = ItemDB.info(id).get("use", "") == "read"
		var ub2 := _button("읽기" if reading else "사용", func() -> void: _inv_default_action(id, swapping))
		ub2.disabled = swapping
		h.add_child(ub2)
		if not reading:
			for qi in PlayerState.QUICK_ITEM_SLOTS:
				var on: bool = st.quick_items[qi] == id
				var qb := _button(("[%d]" if on else "%d") % (qi + 1), func() -> void:
					st.assign_quick_item(qi, "" if on else id)
					_refresh_panel())
				qb.tooltip_text = "소모품 퀵슬롯 %d에 %s" % [qi + 1, "등록됨 — 누르면 해제" if on else "등록"]
				h.add_child(qb)
	if kind == "decor":
		var db := _button("배치", func() -> void:
			close_panel()
			boot.world.begin_place(id))
		db.disabled = not (boot.world is CamperInteriorLab)
		db.tooltip_text = "캠핑카 안에서만 놓을 수 있다" if db.disabled else "E 놓기 · R 돌리기 · X 취소"
		h.add_child(db)
	if kind == "camper":
		var cb := _button("주유" if ItemDB.info(id).get("camper", "") == "fuel" else "응급 수리", func() -> void:
			boot.hud.toast(boot.use_camper_item(id))
			_refresh_panel())
		cb.tooltip_text = "캠핑카 곁에서 사용 — " + Game.camper_status_text()
		h.add_child(cb)
	return v


## Double-click on a bag item: equip it or use / read it.
func _inv_default_action(id: String, swapping: bool) -> void:
	if swapping:
		return
	var st := Game.player_state
	if ItemDB.is_equipment(id):
		_change_gear(func() -> void: st.equip(id), "%s 장착" % ItemDB.item_name(id))
	elif ItemDB.is_consumable(id):
		var pl := _player()
		if pl:
			pl.begin_use_item(id)
		_refresh_panel()


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
		for me: Array in MapDB.shop_maps(shop_id):
			var mid: String = me[0]
			var mprice: int = me[1]
			var have := MapDB.owned(MapDB.region_of(mid))
			var mrow := HBoxContainer.new()
			mrow.add_child(_row_label(ItemDB.item_name(mid), 190, 20, Color(0.85, 0.95, 1.0)))
			mrow.add_child(_row_label("%d g" % mprice, 70, 19, Color(1.0, 0.85, 0.4)))
			mrow.add_child(_row_label("가지고 있음" if have else "지도", 100, 18, Color(0.72, 0.76, 0.8)))
			var mb := _button("구매", func() -> void:
				var why := ShopDB.buy_map(mid, mprice)
				if why != "":
					boot.hud.toast(why)
				else:
					Game.combat_log.add("구매: %s (-%d 골드)" % [ItemDB.item_name(mid), mprice], "", "info")
				_refresh_panel())
			mb.disabled = have or st.gold < mprice
			mb.tooltip_text = str(MapDB.item_info(mid)["desc"]) + "\n사면 바로 지도(M)에 추가된다 — 가방에 들어가지 않음"
			mrow.add_child(mb)
			left.add_child(mrow)
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
		if shop.get("smith", false) and Game.has_camper:
			# GDD 9.5: the smith doubles as the mechanic (full repair for gold)
			var rq: Dictionary = boot.camper_repair_quote()
			var rrow := HBoxContainer.new()
			rrow.add_child(_row_label("캠핑카 정비 — %s" % Game.camper_status_text(), 760, 20, Color(1.0, 0.9, 0.6)))
			var rb := _button("완전 수리 (%d g)" % int(rq["gold"]) if rq["ok"] else str(rq["why"]), func() -> void:
				boot.hud.toast(boot.repair_camper())
				_refresh_panel())
			rb.disabled = not rq["ok"]
			rrow.add_child(rb)
			v.add_child(rrow)
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
		right.add_child(_row_label("창고 %.1f / %.0f kg" % [box.weight(), Game.storage_capacity()], 520, 20, Color(0.85, 0.88, 0.92)))
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


## Camper upgrade vendor (GDD 9.2 [확정]: NPC + gold, or a quest). One row per upgrade this
## vendor fits, grouped by field; paints / parts already owned can be switched here; the mechanic
## also repairs and names the camper, the mage gives the infinite-power quest.
func open_upgrades(vendor: String, source: Node3D) -> void:
	if _panel_kind == "upgrades":
		close_panel()
		return
	_open("upgrades", source, 3.0, func(v: VBoxContainer) -> void:
		var head := HBoxContainer.new()
		head.add_child(_row_label("%s — 캠핑카 개조" % CamperUpgrades.vendor_name(vendor), 520, 26, Color(1.0, 0.9, 0.6)))
		head.add_child(_row_label("%d 골드 · %s" % [Game.player_state.gold, CamperUpgrades.camper_name()], 420, 20, Color(0.85, 0.88, 0.92)))
		v.add_child(head)
		if not Game.has_camper:
			v.add_child(_row_label("캠핑카가 생기면 다시 오게. (아직 캠핑카가 없다)", 900, 20, Color(0.8, 0.8, 0.8)))
		v.add_child(_row_label(Game.camper_status_text(), 900, 18, Color(0.75, 0.8, 0.85)))
		var cat := ""
		for u: Dictionary in CamperUpgrades.for_vendor(vendor):
			if u["category"] != cat:
				cat = u["category"]
				v.add_child(_row_label("— %s" % CamperUpgrades.category_name(cat), 900, 19, Color(0.6, 0.85, 1.0)))
			v.add_child(_upgrade_row(u))
		if vendor == "carpenter":  # small furniture to place freely inside (GDD 9.1)
			v.add_child(_row_label("— 실내 소품 (가방에 넣고 캠핑카 안에서 '배치')", 900, 19, Color(0.6, 0.85, 1.0)))
			var prices: Dictionary = CamperUpgrades.data().get("decor_prices", {})
			var drow := HFlowContainer.new()
			drow.custom_minimum_size.x = 1060
			for item: String in prices:
				var b := _button("%s %dg" % [ItemDB.item_name(item), int(prices[item])], func() -> void:
					var st := Game.player_state
					if st.gold < int(prices[item]):
						boot.hud.toast("골드가 모자란다")
					elif not st.can_carry(ItemDB.weight(item)):
						boot.hud.toast("너무 무겁다 — 더 들 수 없다")
					else:
						st.gold -= int(prices[item])
						st.inventory.add(item, 1)
						boot.hud.toast("%s을(를) 샀다 — 캠핑카 안에서 가방의 '배치'" % ItemDB.item_name(item))
					_refresh_panel())
				b.tooltip_text = str(ItemDB.info(item).get("desc", ""))
				drow.add_child(b)
			v.add_child(drow)
		var bottom := HBoxContainer.new()
		if vendor == "mechanic":
			bottom.add_child(_button("이름 짓기", func() -> void: open_camper_name(source)))
			var q: Dictionary = boot.camper_repair_quote()
			var rb := _button("수리 (%d 골드)" % int(q.get("gold", 0)) if int(q.get("gold", 0)) > 0 else "수리", func() -> void:
				boot.hud.toast(boot.repair_camper())
				_refresh_panel())
			rb.disabled = not q["ok"]
			rb.tooltip_text = str(q.get("why", ""))
			bottom.add_child(rb)
		bottom.add_child(_button("닫기 (E)", close_panel))
		v.add_child(bottom), 1100)


func _upgrade_row(u: Dictionary) -> HBoxContainer:
	var id: String = u["id"]
	var row := HBoxContainer.new()
	var have := CamperUpgrades.owned(id)
	row.add_child(_row_label(("✔ " if have else "· ") + str(u["name"]), 270, 19, Color(0.75, 1.0, 0.7) if have else Color.WHITE))
	row.add_child(_row_label(str(u.get("desc", "")), 560, 16, Color(0.8, 0.82, 0.86)))
	var e: Dictionary = u.get("effects", {})
	var qid := str(u.get("quest", ""))
	if have and e.has("paint"):
		var on: bool = Game.camper_mods.get("paint", "") == e["paint"]
		var pb := _button("사용 중" if on else "이 색으로", func() -> void:
			Game.camper_mods["paint"] = str(e["paint"])
			Game.camper_changed.emit()
			_refresh_panel(), 170)
		pb.disabled = on
		row.add_child(pb)
	elif have and e.has("part"):
		var parts: Array = Game.camper_mods["parts"]
		var on2 := parts.has(e["part"])
		row.add_child(_button("떼기" if on2 else "달기", func() -> void:
			if parts.has(e["part"]):
				parts.erase(e["part"])
			else:
				parts.append(e["part"])
			Game.camper_changed.emit()
			_refresh_panel(), 170))
	elif have:
		row.add_child(_row_label("설치됨", 170, 18, Color(0.75, 1.0, 0.7)))
	elif qid != "" and Game.quests.state(qid) != "completed":
		var qs := Game.quests.state(qid)
		var qb: Button
		if qs == "ready":
			qb = _button("의뢰 보고", func() -> void:
				boot.hud.toast(Game.quests.complete(qid))  # pays the rewards; the upgrade can be fitted now
				_refresh_panel(), 170)
		elif qs == "active":
			qb = _button("의뢰 진행 중", func() -> void: pass, 170)
			qb.disabled = true
			qb.tooltip_text = " / ".join(Game.quests.objectives_text(qid))
		else:
			qb = _button("의뢰 받기", func() -> void:
				var why := Game.quests.accept(qid)
				if why != "":
					boot.hud.toast(why)
				_refresh_panel(), 170)
			qb.disabled = not Game.has_camper or not CamperUpgrades.owned(str(u.get("requires", "")))
		row.add_child(qb)
	else:
		var why := CamperUpgrades.block(id)
		var gold := int(u.get("gold", 0))
		var b := _button("개조 (%d 골드)" % gold if gold > 0 else "달기", func() -> void:
			var r := CamperUpgrades.buy(id)
			boot.hud.toast("%s — 달았다!" % u["name"] if r == "" else r)
			_refresh_panel(), 170)
		b.disabled = why != ""
		b.tooltip_text = why
		row.add_child(b)
	return row


## Magic room purpose (GDD 9.1: prebuilt room modules, the player decides what each room is for).
func open_room_purpose(index: int, source: Node3D) -> void:
	_open("room", source, 2.5, func(v: VBoxContainer) -> void:
		var rooms := CamperUpgrades.rooms()
		var cur := str(rooms[index].get("purpose", "")) if index < rooms.size() else ""
		v.add_child(_row_label("마법 방 %d — 용도 정하기" % (index + 1), 600, 26, Color(1.0, 0.9, 0.6)))
		v.add_child(_row_label("언제든 바꿀 수 있다 (가구는 마법으로 바뀐다)", 600, 17, Color(0.75, 0.8, 0.85)))
		var purposes: Dictionary = CamperUpgrades.data().get("room_purposes", {})
		for pid: String in purposes:
			var row := HBoxContainer.new()
			row.add_child(_row_label(("✔ " if pid == cur else "· ") + str(purposes[pid]["name"]), 160, 20))
			row.add_child(_row_label(str(purposes[pid].get("desc", "")), 470, 16, Color(0.8, 0.82, 0.86)))
			var b := _button("사용 중" if pid == cur else "이 방으로", func() -> void:
				rooms[index]["purpose"] = pid
				Game.camper_changed.emit()
				close_panel()
				boot.hud.toast("방 %d → %s" % [index + 1, purposes[pid]["name"]])
				if boot.world is CamperInteriorLab:
					Game.request_world(Game.WORLD_INTERIOR)  # rebuild the interior with the new furniture
				, 130)
			b.disabled = pid == cur
			row.add_child(b)
			v.add_child(row)
		v.add_child(_button("닫기", close_panel)), 820)


## Naming the camper (GDD 9.1 [확정]: the player names it). Up to 12 characters.
func open_camper_name(source: Node3D) -> void:
	_open("camper_name", source, 3.0, func(v: VBoxContainer) -> void:
		v.add_child(_row_label("캠핑카 이름 짓기", 400, 26, Color(1.0, 0.9, 0.6)))
		var edit := LineEdit.new()
		edit.text = str(Game.camper_mods.get("name", ""))
		edit.placeholder_text = "예: 굴러가는 집"
		edit.max_length = 12
		edit.custom_minimum_size.x = 360
		edit.add_theme_font_size_override("font_size", 22)
		v.add_child(edit)
		var save := func() -> void:
			Game.camper_mods["name"] = edit.text.strip_edges()
			Game.camper_changed.emit()
			Game.combat_log.add("캠핑카 이름: %s" % CamperUpgrades.camper_name(), "", "info")
			boot.hud.toast("이제부터 %s!" % CamperUpgrades.camper_name())
			close_panel()
		edit.text_submitted.connect(func(_t: String) -> void: save.call())
		var b := HBoxContainer.new()
		b.add_child(_button("정하기 (Enter)", save))
		b.add_child(_button("취소", close_panel))
		v.add_child(b)
		edit.grab_focus.call_deferred(), 520)


## Cot (GDD 9.6): choose hours, game time advances by that much, cot restores HP 10 % [임시].
func open_sleep(source: Node3D) -> void:
	if _panel_kind == "sleep":
		close_panel()
		return
	_open("sleep", source, 2.4, func(v: VBoxContainer) -> void:
		var bed := CamperUpgrades.bed_info()
		v.add_child(_row_label("%s — 수면" % bed.get("name", "간이침대"), 400, 28, Color(1.0, 0.9, 0.6)))
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
		v.add_child(_row_label("%s 회복: HP 최대치의 %d%% [임시] · SP/MP 회복 [미정→전부]" % [bed.get("name", ""), roundi(float(bed.get("hp", 0.1)) * 100.0)], 680, 19, Color(0.75, 0.8, 0.85)))
		var b := HBoxContainer.new()
		var bonus := float(CamperUpgrades.purpose_info("bedroom").get("sleep_bonus", 0.0)) if source and source.has_meta("bedroom") else 0.0
		b.add_child(_button("잠자기", func() -> void:
			var hours := _sleep_hours
			close_panel()
			boot.sleep(hours, bonus)))
		b.add_child(_button("취소", close_panel))
		v.add_child(b), 700)


# ---------------------------------------------------------------- per frame

## Character sheet (GDD 5.1-5.2): level-up with general EXP (+1 stat point) and the 7 stats with
## their derived numbers. Skills and life skills are in the skill window (K).
func toggle_character() -> void:
	if _panel_kind == "character":
		close_panel()
		return
	var st := Game.player_state
	_open("character", null, 0.0, func(v: VBoxContainer) -> void:
		_window_tabs(v, "character")
		var head := HBoxContainer.new()
		head.add_child(_row_label("주인공 — Lv %d" % st.level, 300, 28, Color(1.0, 0.9, 0.6)))
		head.add_child(tip(_row_label("일반 EXP %d / %d" % [st.gen_exp, st.exp_to_next()], 260, 22), "일반 EXP",
			"전투·퀘스트로 얻는다. 레벨업(능력치 포인트 +%d)이나 기본 스킬 습득(스킬 창, K)에 직접 쓴다 — 저절로 쓰이지 않는다." % PlayerState.STAT_POINTS_PER_LEVEL))
		var lv := _button("레벨업 (EXP %d 사용)" % st.exp_to_next(), func() -> void:
			if st.level_up():
				Game.combat_log.add("레벨 %d — 능력치 포인트 +%d" % [st.level, PlayerState.STAT_POINTS_PER_LEVEL], "", "info")
				boot.hud.toast("레벨 %d! 능력치 포인트를 투자하세요" % st.level)
			_refresh_panel())
		lv.disabled = not st.can_level_up()
		head.add_child(lv)
		v.add_child(head)
		v.add_child(HSeparator.new())
		_build_stat_block(v)
		v.add_child(_button("닫기 (C)", close_panel)), 1240)


## Skill window (K): two tabs — 스킬 (basic skills bought with general EXP, magic on quickslots)
## and 생활 스킬 (one section per life field: mastery + its life skills).
var skill_tab := "skill"


func toggle_skills(tab := "") -> void:
	if tab != "":
		skill_tab = tab
	elif _panel_kind == "skills":
		close_panel()
		return
	var st := Game.player_state
	_open("skills", null, 0.0, func(v: VBoxContainer) -> void:
		_window_tabs(v, "skills")
		var sub := HBoxContainer.new()
		sub.add_theme_constant_override("separation", 6)
		for t: Array in [["skill", "스킬"], ["life", "생활 스킬"]]:
			var key: String = t[0]
			var b := _button(t[1], func() -> void:
				skill_tab = key
				_refresh_panel(), 160)
			if key == skill_tab:
				b.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(0.3, 0.24, 0.14)
				sb.border_color = Color(0.85, 0.7, 0.42)
				sb.border_width_bottom = 3
				sb.content_margin_left = 12
				sb.content_margin_right = 12
				for st_name in ["normal", "hover", "pressed"]:
					b.add_theme_stylebox_override(st_name, sb)
			sub.add_child(b)
		v.add_child(sub)
		v.add_child(HSeparator.new())
		if skill_tab == "life":
			_build_life_skills(v)
		else:
			_build_combat_skills(v)
		v.add_child(_button("닫기 (K)", close_panel)), 1240)


func _section(v: VBoxContainer, title: String, help := "") -> void:
	var l := _row_label(title, 600, 23, Color(1.0, 0.9, 0.6))
	v.add_child(tip(l, title, help) if help != "" else l)


func _build_combat_skills(v: VBoxContainer) -> void:
	var st := Game.player_state
	v.add_child(tip(_row_label("일반 EXP %d" % st.gen_exp, 400, 21, Color(0.85, 0.9, 0.95)), "일반 EXP", "기본 스킬 습득과 레벨업(능력치 창)에 쓴다."))
	_section(v, "일반 스킬", "스승 없이 일반 EXP로 배우는 패시브 기술. 배우면 바로 적용되고 퀵슬롯이 필요 없다.")
	for id: String in PlayerState.SKILLS:
		var sk: Dictionary = PlayerState.SKILLS[id]
		var row := HBoxContainer.new()
		var rank := st.skill_rank(id)
		row.add_child(tip(_row_label("  %s" % sk["name"], 260, 21), sk["name"], "%s (단계마다)\n%d / %d단계" % [sk["desc"], rank, sk["max"]]))
		row.add_child(_row_label("%d / %d단계" % [rank, sk["max"]], 160, 20, Color(0.85, 0.88, 0.9)))
		var cost := st.skill_cost(id)
		var b := _button("최대" if cost < 0 else "배우기 (EXP %d)" % cost, func() -> void:
			if st.learn_skill(id):
				Game.combat_log.add("기본 스킬 습득: %s %d단계" % [sk["name"], st.skill_rank(id)], "", "info")
			_refresh_panel(), 200)
		b.disabled = cost < 0 or st.gen_exp < cost
		if cost >= 0 and st.gen_exp < cost:
			b.tooltip_text = "일반 EXP %d 필요 (지금 %d)" % [cost, st.gen_exp]
		row.add_child(b)
		v.add_child(row)
	v.add_child(HSeparator.new())
	_section(v, "마법", "마법서·NPC·퀘스트로 배운다. 퀵슬롯 5~8에 등록해야 쓸 수 있고, MP를 쓴다.")
	if st.spells.is_empty():
		v.add_child(_row_label("  아직 배운 마법이 없다 (보급 상자의 '마법서: 작은 치유'를 소지품에서 읽기)", 900, 18, Color(0.7, 0.74, 0.78)))
	for sid: String in st.spells:
		var spi: Dictionary = ItemDB.SPELLS[sid]
		var row2 := HBoxContainer.new()
		row2.add_child(tip(_row_label("  " + str(spi["name"]), 260, 21), spi["name"], "%s\nMP %d · %.1f초 시전 · 재사용 %.0f초" % [spi["desc"], spi["mp"], spi["time"], spi["cooldown"]]))
		row2.add_child(_row_label("MP %d" % spi["mp"], 160, 20, Color(0.6, 0.75, 1.0)))
		row2.add_child(_row_label("퀵슬롯", 80, 18, Color(0.72, 0.76, 0.8)))
		for qi in PlayerState.QUICK_SKILL_SLOTS:
			var on: bool = st.quick_skills[qi] == sid
			var qb := _button(("[%d]" if on else "%d") % (qi + 5), func() -> void:
				st.assign_quick_skill(qi, "" if on else sid)
				_refresh_panel())
			qb.tooltip_text = "퀵슬롯 %d에 %s" % [qi + 5, "등록됨 — 누르면 해제" if on else "등록"]
			row2.add_child(qb)
		v.add_child(row2)


func _build_life_skills(v: VBoxContainer) -> void:
	var st := Game.player_state
	v.add_child(tip(_row_label("생활 EXP %d" % st.life_exp, 400, 21, Color(0.75, 0.92, 0.75)), "생활 EXP",
		"채집·낚시·요리·제작과 퀘스트로 얻고, 생활 기술을 배우는 데 쓴다."))
	var by_field := {}
	for sid: String in LifeDB.data().get("skills", {}):
		for f: String in LifeDB.skill(sid).get("req", {}):
			by_field[f] = by_field.get(f, []) + [sid]
	var hint := {"gathering": "풀·버섯·나무·광석을 모을수록 오른다.", "fishing": "물고기를 낚을수록 오른다.",
		"cooking": "요리를 만들수록 오른다 (U 요리·제작).", "crafting": "물건을 만들수록 오른다 (U 요리·제작)."}
	for f: String in LifeDB.FIELDS:
		var pts := int(st.mastery.get(f, 0))
		var nxt := LifeDB.next_threshold(pts)
		var head := HBoxContainer.new()
		head.add_child(tip(_row_label(LifeDB.field_name(f), 160, 23, Color(1.0, 0.9, 0.6)), "%s 숙련도" % LifeDB.field_name(f),
			"%s\n숙련도는 그 활동을 반복하면 저절로 오른다 (EXP로 사지 않음)." % hint.get(f, "")))
		head.add_child(_row_label("숙련도 Lv %d" % st.mastery_level(f), 160, 20, Color(0.85, 0.9, 0.85)))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(260, 18)
		bar.show_percentage = false
		bar.max_value = maxf(1.0, float(nxt))
		bar.value = float(pts) if nxt > 0 else bar.max_value
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for part: Array in [["background", Color(0.13, 0.13, 0.14), Color(0.46, 0.46, 0.48)], ["fill", Color(0.4, 0.7, 0.38), Color(0.4, 0.7, 0.38)]]:
			var psb := StyleBoxFlat.new()
			psb.bg_color = part[1]
			psb.border_color = part[2]
			psb.set_border_width_all(1)
			bar.add_theme_stylebox_override(part[0], psb)
		head.add_child(bar)
		head.add_child(_row_label("  %s" % ("%d / %d" % [pts, nxt] if nxt > 0 else "최대"), 140, 18, Color(0.72, 0.76, 0.8)))
		v.add_child(head)
		var list: Array = by_field.get(f, [])
		if list.is_empty():
			v.add_child(_row_label("    배울 수 있는 생활 기술이 아직 없다", 600, 17, Color(0.6, 0.63, 0.67)))
		for sid: String in list:
			var sk := LifeDB.skill(sid)
			var row := HBoxContainer.new()
			row.add_child(tip(_row_label("    " + str(sk.get("name", sid)), 260, 20), str(sk.get("name", sid)), str(sk.get("desc", ""))))
			var block := st.life_skill_block(sid)
			var b := _button("배움" if st.has_life_skill(sid) else "배우기 (생활 EXP %d)" % int(sk.get("cost", 0)), func() -> void:
				if st.learn_life_skill(sid):
					boot.hud.toast("생활 기술 습득: " + str(sk.get("name", sid)))
				_refresh_panel(), 230)
			b.disabled = block != ""
			if block != "" and not st.has_life_skill(sid):
				b.tooltip_text = block
			row.add_child(b)
			v.add_child(row)


## Stats (left) and the numbers they make (right). + / − only plan points; "확정" spends them,
## and until then the right column shows "now → after" for whatever would change.
func _build_stat_block(v: VBoxContainer) -> void:
	var st := Game.player_state
	var left_pts := st.stat_points - _plan_total()
	var head := HBoxContainer.new()
	head.add_child(tip(_row_label("능력치 포인트 %d%s" % [st.stat_points, "  (남음 %d)" % left_pts if _plan_total() > 0 else ""], 420, 22,
		Color(0.6, 0.85, 1.0) if st.stat_points > 0 else Color(0.8, 0.82, 0.85)), "능력치 포인트",
		"레벨업마다 %d점. + / − 로 나눠 본 뒤 '확정'을 눌러야 적용된다. 확정하지 않고 창을 닫으면 취소된다." % PlayerState.STAT_POINTS_PER_LEVEL))
	head.add_child(_row_label("세부 능력치", 360, 22, Color(1.0, 0.9, 0.6)))
	v.add_child(head)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	v.add_child(cols)
	var lc := VBoxContainer.new()
	lc.custom_minimum_size.x = 420
	cols.add_child(lc)
	for key: String in PlayerState.STAT_KEYS:
		var row := HBoxContainer.new()
		var info: Array = PlayerState.STAT_INFO[key]
		var gb := st.gear_bonus(key)
		var planned := int(stat_plan.get(key, 0))
		row.add_child(tip(_row_label("%s %s" % [info[0], key], 130, 21), "%s (%s)" % [info[0], key],
			str(PlayerState.STAT_HELP[key]) + ("\n장비 보너스 +%d 포함." % gb if gb > 0 else "")))
		var val := "%d" % st.stats[key] if planned == 0 else "%d → %d" % [st.stats[key], st.stats[key] + planned]
		row.add_child(_row_label(val + (" (+%d)" % gb if gb > 0 else ""), 140, 21, Color(0.55, 1.0, 0.6) if planned > 0 else Color(1.0, 0.95, 0.8)))
		var minus := _button(" − ", func() -> void: plan_stat(key, -1), 46)
		minus.disabled = planned <= 0
		row.add_child(minus)
		var plus := _button(" + ", func() -> void: plan_stat(key, 1), 46)
		plus.disabled = left_pts <= 0
		row.add_child(plus)
		lc.add_child(row)
	var btns := HBoxContainer.new()
	var ok := _button("확정", confirm_stats, 120)
	ok.disabled = _plan_total() == 0
	ok.tooltip_text = "나눠 둔 포인트를 실제로 적용한다 (되돌릴 수 없음)"
	btns.add_child(ok)
	var undo := _button("되돌리기", func() -> void:
		stat_plan.clear()
		_refresh_panel(), 120)
	undo.disabled = _plan_total() == 0
	btns.add_child(undo)
	lc.add_child(btns)
	var rc := VBoxContainer.new()
	cols.add_child(rc)
	var now := st.derived()
	var after := st.derived_with(stat_plan)
	for d: Array in PlayerState.DERIVED:
		var key: String = d[0]
		var row2 := HBoxContainer.new()
		row2.add_child(tip(_row_label(d[1], 130, 20), d[1], d[3]))
		var a: Variant = now[key]
		var b: Variant = after[key]
		var changed := not is_equal_approx(float(a), float(b))
		var txt: String = d[2] % a
		if changed:
			txt += "  →  " + d[2] % b
		row2.add_child(_row_label(txt, 230, 20, Color(0.55, 1.0, 0.6) if changed else Color(0.85, 0.9, 0.85)))
		rc.add_child(row2)


func _plan_total() -> int:
	var n := 0
	for k: String in stat_plan:
		n += int(stat_plan[k])
	return n


## Plans one more (+1) or one fewer (−1) point for a stat; nothing is spent until confirm_stats().
func plan_stat(key: String, delta: int) -> void:
	var cur := int(stat_plan.get(key, 0))
	if delta > 0 and _plan_total() >= Game.player_state.stat_points:
		return
	cur = maxi(0, cur + delta)
	if cur == 0:
		stat_plan.erase(key)
	else:
		stat_plan[key] = cur
	_refresh_panel()


## Spends the planned points ("확정").
func confirm_stats() -> void:
	var st := Game.player_state
	var parts := PackedStringArray()
	for key: String in PlayerState.STAT_KEYS:
		var n := int(stat_plan.get(key, 0))
		var done := 0
		for i in n:
			if st.add_stat(key):
				done += 1
		if done > 0:
			parts.append("%s +%d" % [PlayerState.STAT_INFO[key][0], done])
	stat_plan.clear()
	if not parts.is_empty():
		Game.combat_log.add("능력치 확정: " + ", ".join(parts), "", "info")
		boot.hud.toast("능력치 확정 — " + ", ".join(parts))
	_refresh_panel()


# ---------------------------------------------------------------- dialogue / quests (P2-5)

## Dialogue or cutscene on screen: everything else in the HUD steps aside.
func story_mode() -> bool:
	return dialogue.active() or cutscene.playing


## While a dialogue or cutscene is on, the whole HUD steps aside so only the story is on screen.
## Runs after everything else in _process: widgets that re-show themselves every frame are hidden
## again before drawing, and everything hidden here comes back when the dialogue ends.
func _apply_talk_mode() -> void:
	if story_mode():
		for c in get_children():
			if c is CanvasItem and c.visible and not c in [dialogue, fishing, overlay, overlay.fade_rect, _fade, _fade_label, _caption]:
				c.visible = false
				if not c in _talk_hidden:
					_talk_hidden.append(c)
	elif not _talk_hidden.is_empty():
		for c in _talk_hidden:
			if is_instance_valid(c):
				c.visible = true
		_talk_hidden.clear()


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


func _build_boss_bar() -> void:
	_boss_box = Control.new()
	_boss_box.position = Vector2(560, 22)
	_boss_box.size = Vector2(800, 60)
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	add_child(_boss_box)
	_boss_name = Label.new()
	_boss_name.size = Vector2(800, 30)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_font_size_override("font_size", 24)
	_boss_name.add_theme_color_override("font_color", Color(1.0, 0.86, 0.7))
	_boss_box.add_child(_boss_name)
	var back := ColorRect.new()
	back.color = Color(0.08, 0.04, 0.04, 0.85)
	back.position = Vector2(0, 34)
	back.size = Vector2(800, 18)
	_boss_box.add_child(back)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color(0.82, 0.18, 0.12)
	_boss_fill.position = Vector2(2, 36)
	_boss_fill.size = Vector2(796, 14)
	_boss_box.add_child(_boss_fill)


## Shows the boss bar for a monster with hp / max_hp / display_name (null hides it).
func show_boss(node: Node) -> void:
	boss = node


func _update_boss_bar() -> void:
	var on := boss != null and is_instance_valid(boss) and int(boss.hp) > 0
	_boss_box.visible = on
	if on:
		var ratio := clampf(float(boss.hp) / float(boss.max_hp), 0.0, 1.0)
		_boss_fill.size.x = 796.0 * ratio
		_boss_name.text = "%s   %d / %d%s" % [boss.display_name, maxi(int(boss.hp), 0), int(boss.max_hp), "  · 격노" if boss.get("phase") == 2 else ""]


## Small "saved" note above the log button (doesn't take over the toast line).
func show_save_note(text: String) -> void:
	_save_note.text = "● " + text
	_save_note_t = 2.5


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
			row.add_child(_row_label("어디서나" if fac == "" else {"cooking": "모닥불·주방", "workbench": "작업대", "refinery": "정제 시설"}.get(fac, fac), 110, 17, Color(0.7, 0.78, 0.9)))
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
	# GDD 9.3: the improved refinery inside the camper makes a little more fuel
	var refine_extra := CamperUpgrades.refine_bonus() if facility == "refinery" and boot.world is CamperInteriorLab else 0
	for item: String in outs:
		var n := int(outs[item]) + (1 if bonus else 0) + refine_extra
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


## World map (GDD 11.3 / 11.4, scripts/ui/world_map.gd): terrain and major towns from the start,
## places once found, my pins with memos, fast travel between visited towns.
var map_view: WorldMap


func toggle_map() -> void:
	if _panel_kind == "map":
		close_panel()
		return
	_open("map", null, 0.0, func(v: VBoxContainer) -> void:
		var head := HBoxContainer.new()
		head.add_child(_row_label("지도", 300, 26, Color(1.0, 0.9, 0.6)))
		var cam_text := "캠핑카: %s" % RegionDB.region_name(str(Game.camper.get("region", ""))) if Game.has_camper else "캠핑카: 아직 없음"
		head.add_child(_row_label("%s · %s %s" % [RegionDB.region_name(Game.region), Game.clock_text(), cam_text], 1100, 18, Color(0.8, 0.82, 0.86)))
		v.add_child(head)
		map_view = WorldMap.new()
		map_view.font = font
		map_view.boot = boot
		map_view.custom_minimum_size = Vector2(1800, 820)
		v.add_child(map_view)
		v.add_child(_button("닫기 (M)", close_panel)), 1840)


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
	if _panel_kind in ["inventory", "loot", "storage", "character", "skills", "shop", "journal", "board", "craft"]:
		_refresh_panel()


func _process(delta: float) -> void:
	_update_boss_bar()
	if _tip and _tip.visible:
		if not is_instance_valid(_tip_owner) or not _tip_owner.is_visible_in_tree():
			_hide_tip()
		else:
			_place_tip()
	var st := Game.player_state
	_set_bar("hp", st.hp, st.max_hp())
	var hb: Array = _bars["hp"]
	(hb[0] as ColorRect).color = Color(0.45, 0.75, 0.25) if st.poison_left > 0.0 else Color(0.86, 0.26, 0.24)
	if st.poison_left > 0.0:
		(hb[1] as Label).text += "  · 중독 %d초" % ceili(st.poison_left)
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
	if Game.has_camper:
		lines.append(Game.camper_status_text())
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
	_save_note_t -= delta
	_save_note.modulate.a = clampf(_save_note_t, 0.0, 1.0)
	_apply_talk_mode()
	if _panel and _panel_source:
		var p2: Node3D = w.player if w else null
		if not is_instance_valid(_panel_source) or p2 == null \
				or Vector2(p2.global_position.x - _panel_source.global_position.x, p2.global_position.z - _panel_source.global_position.z).length() > _panel_range:
			close_panel()
