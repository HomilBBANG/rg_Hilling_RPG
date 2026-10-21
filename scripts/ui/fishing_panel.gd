class_name FishingPanel
extends PanelContainer
## Fishing (GDD 14.2 [확정]): cast and fish automatically, or play the minigame by hand - doing it
## by hand is better (higher success and a better chance at rare fish). Gives life EXP and fishing
## mastery. Minigame: stop the moving marker inside the green zone, `manual_hits` times in a row.
## Exact rules, fish list and numbers are [미정] (data/life.json "fishing").

signal finished(result: String)

var active := false
var manual := false
var spot: Node3D

var _phase := ""   # "wait" | "game" | "result"
var _t := 0.0
var _hits := 0
var _zone := Vector2(0.4, 0.6)
var _speed := 2.4
var _clock := 0.0
var _label: Label
var _bar: Control
var _zone_rect: ColorRect
var _marker: ColorRect
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	visible = false
	_rng.randomize()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.92)
	sb.border_color = Color(0.4, 0.62, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 23)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.custom_minimum_size.x = 640
	v.add_child(_label)
	_bar = ColorRect.new()
	(_bar as ColorRect).color = Color(0.16, 0.2, 0.26)
	_bar.custom_minimum_size = Vector2(640, 30)
	v.add_child(_bar)
	_zone_rect = ColorRect.new()
	_zone_rect.color = Color(0.35, 0.8, 0.45)
	_bar.add_child(_zone_rect)
	_marker = ColorRect.new()
	_marker.color = Color(1, 1, 0.9)
	_marker.size = Vector2(8, 38)
	_bar.add_child(_marker)


func _player() -> PrototypePlayer:
	var w: Node = Game.boot.world if Game.boot else null
	return w.get("player") if w else null


func start(is_manual: bool, at: Node3D) -> bool:
	var p := _player()
	if active or p == null:
		return false
	if Game.player_state.inventory.count("fishing_rod") <= 0:
		Game.boot.hud.toast("낚싯대가 없다 — 잡화점에서 사거나 캠핑카 창고에서 꺼내 오자")
		return false
	if not p.begin_task("낚시 중", 9999.0, 0.0, "cast", func() -> void: pass, _on_cancel):
		return false
	manual = is_manual
	spot = at
	active = true
	var f := LifeDB.fishing()
	var st := Game.player_state
	var w: Array = f.get("wait", [3.0, 7.0])
	_t = _rng.randf_range(float(w[0]), float(w[1])) * maxf(0.5, 1.0 - 0.05 * (st.mastery_level("fishing") - 1)) * (0.8 if st.has_life_skill("angler_sense") else 1.0)
	_phase = "wait"
	_bar.visible = false
	_label.text = "찌를 던졌다… 입질을 기다리는 중 (%s)\nE — 낚싯대 거두기" % ("직접 낚시" if manual else "자동 낚시")
	visible = true
	_place()
	return true


func _place() -> void:
	reset_size()
	position = Vector2(960 - size.x * 0.5, 700 - size.y)


func _process(delta: float) -> void:
	if not active:
		return
	_clock += delta
	match _phase:
		"wait":
			_t -= delta
			if _t <= 0.0:
				if manual:
					_begin_game()
				else:
					var st := Game.player_state
					var p := float(LifeDB.fishing().get("auto_success", 0.55)) + 0.03 * (st.mastery_level("fishing") - 1) + (0.1 if st.has_life_skill("angler_sense") else 0.0)
					_resolve(_rng.randf() < p)
		"game":
			var x := (sin(_clock * _speed) + 1.0) * 0.5
			_marker.position = Vector2(x * (_bar.size.x - _marker.size.x), -4)
		"result":
			_t -= delta
			if _t <= 0.0:
				visible = false
				active = false
				_phase = ""


func _begin_game() -> void:
	_phase = "game"
	_hits = 0
	_new_zone()
	_bar.visible = true
	_label.text = "입질! 하얀 표시가 초록 구간에 올 때 E (0/%d)" % int(LifeDB.fishing().get("manual_hits", 2))
	_place()


func _new_zone() -> void:
	var st := Game.player_state
	var width := float(LifeDB.fishing().get("manual_zone", 0.2)) + 0.015 * (st.mastery_level("fishing") - 1) + (0.05 if st.has_life_skill("angler_sense") else 0.0)
	var start := _rng.randf_range(0.05, 0.95 - width)
	_zone = Vector2(start, start + width)
	_zone_rect.position = Vector2(_zone.x * _bar.custom_minimum_size.x, 0)
	_zone_rect.size = Vector2(width * _bar.custom_minimum_size.x, 30)
	_speed = _rng.randf_range(2.2, 3.4)


## E / Space while the panel is up.
func press() -> void:
	match _phase:
		"wait":
			_finish("낚싯대를 거뒀다", "cancel")
		"game":
			var x := _marker.position.x / maxf(1.0, _bar.size.x - _marker.size.x)
			if x >= _zone.x and x <= _zone.y:
				_hits += 1
				var need := int(LifeDB.fishing().get("manual_hits", 2))
				if _hits >= need:
					_resolve(true)
				else:
					_label.text = "좋아! 한 번 더 (%d/%d)" % [_hits, need]
					_new_zone()
			else:
				_resolve(false)


func handle_key(ev: InputEvent) -> bool:
	if ev.is_action("interact") or (ev is InputEventKey and ev.physical_keycode == KEY_SPACE):
		press()
		return true
	return false


func _on_cancel(reason: String) -> void:
	if active and _phase != "result":
		_phase = "result"
		_t = 1.2
		_bar.visible = false
		_label.text = "낚시 중단 (%s)" % reason
		finished.emit("cancel")


func _resolve(success: bool) -> void:
	var f := LifeDB.fishing()
	var st := Game.player_state
	if not success:
		st.add_mastery("fishing", int(f.get("mastery_miss", 1)))
		_finish("놓쳤다…", "miss")
		return
	var table: Array = f.get("fish", [])
	var total := 0.0
	for e: Dictionary in table:
		total += float(e["w"]) * (float(f.get("manual_rare_mult", 3.0)) if manual and e.get("rare", false) else 1.0)
	var roll := _rng.randf() * total
	var item := "small_fish"
	for e: Dictionary in table:
		roll -= float(e["w"]) * (float(f.get("manual_rare_mult", 3.0)) if manual and e.get("rare", false) else 1.0)
		if roll <= 0.0:
			item = e["item"]
			break
	if not st.can_carry(ItemDB.weight(item)):
		_finish("%s을(를) 낚았지만 너무 무거워 놓아줬다" % ItemDB.item_name(item), "heavy")
		return
	st.inventory.add(item, 1)
	var ex: Array = f.get("life_exp", [3, 6])
	var lexp := roundi(_rng.randi_range(int(ex[0]), int(ex[1])) * (float(f.get("manual_exp_mult", 1.5)) if manual else 1.0))
	st.life_exp += lexp
	var up := st.add_mastery("fishing", int(f.get("mastery", 4)))
	var text := "%s을(를) 낚았다! 생활 EXP +%d%s" % [ItemDB.item_name(item), lexp, "  ▲ 낚시 숙련도 Lv %d" % up if up > 0 else ""]
	Game.combat_log.add("낚시: " + text, "%s 낚시 성공 — 낚시 숙련도 %d" % ["직접" if manual else "자동", st.mastery["fishing"]], "info")
	st.changed.emit()
	_finish(text, item)


func _finish(text: String, result: String) -> void:
	var p := _player()
	if p:
		p.end_task()
	_phase = "result"
	_t = 1.6
	_bar.visible = false
	_label.text = text
	_place()
	finished.emit(result)
