class_name GatherNode
extends Node3D
## Gathering spot (GDD 14.3 [확정]: plants / ores are gathered by interacting, with a short motion;
## some rare resources need a condition - the moonflower only opens at night). Gathering gives
## life EXP and gathering mastery (5.4). Picked spots regrow after a while [미정 respawn], kept per
## region in Game.field["gather"].

var node_id := ""
var kind := "herb"
var def := {}
var interact_range := 1.4
var _parts: Array[Node3D] = []  # what disappears when picked
var _bud: Node3D               # moonflower by day
var _tick := 0.0


func _ready() -> void:
	def = LifeDB.gather_kind(kind)
	add_to_group("interactable")
	_build()
	_refresh()


func _build() -> void:
	var leaf := ProtoMesh.mat(Color(0.3, 0.55, 0.26))
	match def.get("model", "herb"):
		"herb":
			for i in 5:
				var a := TAU * i / 5.0
				ProtoMesh.sphere(self, 0.16, Vector3(cos(a) * 0.18, 0.14, sin(a) * 0.18), leaf, Vector3(1, 1.4, 1), 6, 4)
			var flowers := Node3D.new()
			add_child(flowers)
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				ProtoMesh.sphere(flowers, 0.06, Vector3(cos(a) * 0.15, 0.34, sin(a) * 0.15), ProtoMesh.mat(Color(0.96, 0.96, 0.9)), Vector3.ONE, 5, 3)
			_parts.append(flowers)
		"berry":
			ProtoMesh.sphere(self, 0.38, Vector3(0, 0.3, 0), ProtoMesh.mat(Color(0.26, 0.48, 0.24)), Vector3(1.2, 0.85, 1.1), 8, 5)
			var berries := Node3D.new()
			add_child(berries)
			for i in 9:
				var a := TAU * i / 9.0
				ProtoMesh.sphere(berries, 0.055, Vector3(cos(a) * 0.36, 0.28 + 0.12 * (i % 3) - 0.06, sin(a) * 0.32), ProtoMesh.mat(Color(0.86, 0.16, 0.2), 0.4), Vector3.ONE, 5, 3)
			_parts.append(berries)
		"mushroom":
			var caps := Node3D.new()
			add_child(caps)
			for spec in [[0.0, 0.0, 1.0], [0.18, 0.1, 0.75], [-0.14, 0.12, 0.6]]:
				ProtoMesh.cylinder(caps, 0.035, 0.16 * spec[2], Vector3(spec[0], 0.08 * spec[2], spec[1]), ProtoMesh.mat(Color(0.9, 0.86, 0.76)), Vector3.ZERO, 6)
				ProtoMesh.sphere(caps, 0.11 * spec[2], Vector3(spec[0], 0.17 * spec[2], spec[1]), ProtoMesh.mat(Color(0.62, 0.42, 0.26)), Vector3(1, 0.55, 1), 7, 4)
			_parts.append(caps)
		"ore":
			ProtoMesh.sphere(self, 0.55, Vector3(0, 0.25, 0), ProtoMesh.mat(Color(0.45, 0.43, 0.42)), Vector3(1.2, 0.7, 1.0), 8, 5)
			var veins := Node3D.new()
			add_child(veins)
			for i in 6:
				var a := TAU * i / 6.0
				ProtoMesh.sphere(veins, 0.08, Vector3(cos(a) * 0.45, 0.32 + 0.08 * (i % 2), sin(a) * 0.36), ProtoMesh.mat(Color(0.82, 0.5, 0.32), 0.4), Vector3.ONE, 5, 3)
			_parts.append(veins)
		"moonflower":
			ProtoMesh.cylinder(self, 0.025, 0.4, Vector3(0, 0.2, 0), leaf, Vector3.ZERO, 5)
			_bud = Node3D.new()
			add_child(_bud)
			ProtoMesh.sphere(_bud, 0.07, Vector3(0, 0.42, 0), ProtoMesh.mat(Color(0.7, 0.76, 0.62)), Vector3(1, 1.4, 1), 6, 4)
			var bloom := Node3D.new()
			add_child(bloom)
			var petal := ProtoMesh.mat(Color(0.85, 0.92, 1.0), 0.4, Color(0.6, 0.8, 1.0), 2.2)
			for i in 5:
				var a := TAU * i / 5.0
				var p := ProtoMesh.sphere(bloom, 0.09, Vector3(cos(a) * 0.1, 0.44, sin(a) * 0.1), petal, Vector3(1, 0.4, 1), 6, 3)
				p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var glow := OmniLight3D.new()
			glow.position = Vector3(0, 0.6, 0)
			glow.light_color = Color(0.6, 0.8, 1.0)
			glow.light_energy = 0.8
			glow.omni_range = 2.5
			bloom.add_child(glow)
			_parts.append(bloom)


func depleted() -> bool:
	var t: float = Game.field.get("gather", {}).get(node_id, -1.0)
	return t >= 0.0 and Game.total_minutes() - t < float(def.get("respawn_hours", 12)) * 60.0


func _refresh() -> void:
	var gone := depleted()
	var closed: bool = def.get("night_only", false) and not Game.is_night()
	for p in _parts:
		p.visible = not gone and not closed
	if _bud:
		_bud.visible = not gone and closed


func _process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		_refresh()


func can_interact() -> bool:
	return visible and not depleted()


func prompt_text() -> String:
	if def.get("night_only", false) and not Game.is_night():
		return "%s — 꽃봉오리가 닫혀 있다 (밤에만 핀다)" % def.get("name", "")
	return "E 채집 — %s (채집 Lv %d)" % [def.get("name", ""), Game.player_state.mastery_level("gathering")]


func interact(player: Node) -> void:
	if def.get("night_only", false) and not Game.is_night():
		Game.boot.hud.toast("%s은(는) 밤에만 핀다" % def.get("name", ""))
		return
	var st := Game.player_state
	var lv := st.mastery_level("gathering")
	var time := float(def.get("time", 1.2)) * maxf(0.5, 1.0 - 0.04 * (lv - 1)) * (0.7 if st.has_life_skill("gather_knack") else 1.0)
	(player as PrototypePlayer).begin_task("%s 채집" % def.get("name", ""), time, 0.0, "cast", _gathered)


func _gathered() -> void:
	var st := Game.player_state
	if depleted():
		return
	var item: String = def.get("item", "herb")
	var c: Array = def.get("count", [1, 1])
	var n := randi_range(int(c[0]), int(c[1]))
	var extra_chance := 0.05 * (st.mastery_level("gathering") - 1) + (0.15 if st.has_life_skill("gather_knack") else 0.0)
	var bonus := randf() < extra_chance
	if bonus:
		n += 1
	if not st.can_carry(ItemDB.weight(item) * n):
		Game.boot.hud.toast("너무 무겁다 — 짐을 줄이고 다시 채집하자")
		return
	st.inventory.add(item, n)
	var g: Dictionary = Game.field.get("gather", {})
	g[node_id] = Game.total_minutes()
	Game.field["gather"] = g
	var lexp := int(def.get("life_exp", 2))
	st.life_exp += lexp
	var up := st.add_mastery("gathering", int(def.get("mastery", 3)))
	var text := "%s ×%d%s · 생활 EXP +%d" % [ItemDB.item_name(item), n, " (추가 수확!)" if bonus else "", lexp]
	Game.combat_log.add("채집: " + text, "%s 채집 — 채집 숙련도 %d" % [def.get("name", ""), st.mastery["gathering"]], "info")
	if Game.hud:
		Game.hud.float_text(global_position + Vector3(0, 1.2, 0), "+%d %s" % [n, ItemDB.item_name(item)], Color(0.7, 1.0, 0.6))
	Game.boot.hud.toast(text + ("  ▲ 채집 숙련도 Lv %d" % up if up > 0 else ""))
	st.changed.emit()
	_refresh()
