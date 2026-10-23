class_name LootContainer
extends Node3D
## Something on the ground whose items the player inspects by hand (GDD 8.2 [확정]: no auto pickup,
## take only what you want): monster corpses, the death bag, a supply crate.
## The data lives in Game.field["loot"] so it survives the exterior scene being rebuilt.

var data: Dictionary  # {"id", "kind", "title", "pos", "inv": Inventory, "expires": float (-1 = never)}
var interact_range := 1.5

const CORPSE_FADE := 0.8  ## seconds an emptied corpse takes to fade away (user request)
var _fade_t := -1.0       ## < 0: not fading
var _fade_mats: Array[StandardMaterial3D] = []


static func create(parent: Node3D, d: Dictionary) -> LootContainer:
	var lc := LootContainer.new()
	lc.data = d
	lc.position = d["pos"]
	parent.add_child(lc)
	return lc


func _ready() -> void:
	add_to_group("interactable")
	match data["kind"]:
		"corpse":
			_build_corpse()
		"bag":
			_build_bag()
		"chest":
			_build_chest()
		_:
			_build_crate()
	if not data["kind"] in ["crate", "chest"]:
		# Flat, low objects: their shadow from the hip lantern a few cm above smeared over the ground.
		for mi in find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func inventory() -> Inventory:
	return data["inv"]


func can_interact() -> bool:
	return _fade_t < 0.0


func prompt_text() -> String:
	var inv := inventory()
	return "E 조사하기 — %s%s" % [data["title"], " (비어 있음)" if inv.is_empty() else ""]


func interact(_player: Node) -> void:
	if Game.hud:
		Game.hud.open_loot(self)


func _process(delta: float) -> void:
	if _fade_t >= 0.0:
		_fade_t += delta
		var a := 1.0 - clampf(_fade_t / CORPSE_FADE, 0.0, 1.0)
		for m in _fade_mats:
			m.albedo_color.a = a
		if _fade_t >= CORPSE_FADE:
			remove()
		return
	var exp_at: float = data.get("expires", -1.0)
	if exp_at >= 0.0 and Game.total_minutes() >= exp_at:
		remove()
	elif data["kind"] == "bag" and inventory().is_empty():
		remove()
	elif data["kind"] == "corpse" and inventory().is_empty():
		_start_fade()


## A corpse with nothing left on it melts away (0.8 s) instead of lying around until it expires.
func _start_fade() -> void:
	_fade_t = 0.0
	for m in _fade_mats:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if Game.hud and Game.hud._panel_source == self:
		Game.hud.close_panel()


func remove() -> void:
	Game.field["loot"].erase(data)
	queue_free()


func _build_corpse() -> void:
	# Collapsed slime: a flat translucent-looking puddle with the dull core in it.
	# Own (uncached) materials: they go transparent when the corpse fades out.
	var body := ProtoMesh.unique_mat(Color(0.2, 0.52, 0.66))
	var light := ProtoMesh.unique_mat(Color(0.42, 0.74, 0.84))
	var core := ProtoMesh.unique_mat(Color(0.12, 0.33, 0.45))
	_fade_mats = [body, light, core]
	ProtoMesh.sphere(self, 0.48, Vector3(0, 0.03, 0), body, Vector3(1.15, 0.12, 0.95), 12, 4)
	ProtoMesh.sphere(self, 0.2, Vector3(0.22, 0.05, 0.18), body, Vector3(1.0, 0.25, 1.0), 8, 3)
	ProtoMesh.sphere(self, 0.12, Vector3(-0.15, 0.07, -0.1), light, Vector3(1.0, 0.35, 1.0), 6, 3)
	ProtoMesh.sphere(self, 0.13, Vector3(0.05, 0.09, 0.02), core, Vector3(1.0, 0.7, 1.0), 6, 3)


func _build_bag() -> void:
	var cloth := ProtoMesh.mat(Color(0.62, 0.44, 0.26))
	var dark := ProtoMesh.mat(Color(0.4, 0.27, 0.16))
	ProtoMesh.sphere(self, 0.28, Vector3(0, 0.22, 0), cloth, Vector3(1.0, 0.85, 0.9), 10, 5)
	ProtoMesh.cylinder(self, 0.09, 0.12, Vector3(0, 0.48, 0), dark, Vector3.ZERO, 6)
	ProtoMesh.sphere(self, 0.11, Vector3(0, 0.58, 0), cloth, Vector3(1.2, 0.6, 1.2), 6, 3)


## Dungeon treasure chest (one-time contents).
func _build_chest() -> void:
	var wood := ProtoMesh.mat(Color(0.52, 0.32, 0.18))
	var trim := ProtoMesh.mat(Color(0.86, 0.68, 0.3), 0.35)
	ProtoMesh.box(self, Vector3(0.9, 0.48, 0.58), Vector3(0, 0.24, 0), wood)
	ProtoMesh.cylinder(self, 0.29, 0.9, Vector3(0, 0.48, 0), wood, Vector3(0, 0, 90), 10)
	for x in [-0.36, 0.36]:
		ProtoMesh.box(self, Vector3(0.07, 0.5, 0.6), Vector3(x, 0.25, 0), trim)
	ProtoMesh.box(self, Vector3(0.14, 0.14, 0.04), Vector3(0, 0.42, -0.3), trim)


func _build_crate() -> void:
	var wood := ProtoMesh.mat(Color(0.7, 0.52, 0.3))
	var dark := ProtoMesh.mat(Color(0.45, 0.31, 0.18))
	ProtoMesh.box(self, Vector3(0.9, 0.55, 0.6), Vector3(0, 0.275, 0), wood)
	ProtoMesh.box(self, Vector3(0.94, 0.06, 0.64), Vector3(0, 0.56, 0), dark)
	for x in [-0.4, 0.4]:
		ProtoMesh.box(self, Vector3(0.06, 0.55, 0.62), Vector3(x, 0.275, 0), dark)
	ProtoMesh.static_box_collider(self, Vector3(0.9, 1.5, 0.6), Vector3(0, 0.5, 0))
