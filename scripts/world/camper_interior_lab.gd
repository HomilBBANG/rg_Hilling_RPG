class_name CamperInteriorLab
extends Node3D
## Camper interior (separate scene, GDD 3.1/9.1 [확정]): door back out, folding cot for sleep
## (9.6), weight-limited storage (8.3) and the black cat who is always here once the camper is
## owned (2.5).
## Room is 9 x 4.4 m while the exterior body is 2.4 m wide: a first try at the
## "magically larger inside" feeling. Camera-side wall is cut down so the room stays readable.

const ROOM_X := 4.5
const ROOM_Z := 2.2
const WALL_H := 2.5
const DOOR_X := -1.6
const COT_POS := Vector3(-3.3, 0, -1.55)
const STORAGE_POS := Vector3(3.2, 0, 1.4)
const CAT_SPOTS: Array[Vector3] = [Vector3(1.4, 0, 0.2), Vector3(-1.9, 0, 0.6), Vector3(2.2, 0, -0.6), Vector3(-2.5, 0, -0.75)]

var player: PrototypePlayer
var camera: TopdownCamera
var cat: CatCompanion
var day_night: DayNightController
var _fill_light: OmniLight3D


func _ready() -> void:
	if get_tree().current_scene == self:
		Game.start_world = Game.WORLD_INTERIOR
		get_tree().change_scene_to_file.call_deferred("res://scenes/bootstrap.tscn")
		return
	_build_environment()
	_build_shell()
	_build_furniture()
	_build_lights()
	_spawn_actors()
	_build_interactions()


func ground_height(_x: float, _z: float) -> float:
	return 0.0


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.environment = DayNightController.make_environment()
	add_child(we)
	day_night = DayNightController.new()
	day_night.interior = true
	day_night.environment = we.environment
	add_child(day_night)


func _build_shell() -> void:
	var plank_a := ProtoMesh.mat(Color(0.62, 0.45, 0.3))
	var plank_b := ProtoMesh.mat(Color(0.56, 0.4, 0.26))
	var wall := ProtoMesh.mat(Color(0.88, 0.84, 0.76))
	var wall_trim := ProtoMesh.mat(Color(0.45, 0.33, 0.24))
	# Floor planks
	var n := int(ROOM_Z * 2.0 / 0.4)
	for i in n:
		var z := -ROOM_Z + 0.2 + i * 0.4
		ProtoMesh.box(self, Vector3(ROOM_X * 2.0, 0.1, 0.39), Vector3(0, -0.05, z), plank_a if i % 2 == 0 else plank_b)
	# Back (north) wall full height, end walls full height, front (camera-side) wall cut down.
	ProtoMesh.box(self, Vector3(ROOM_X * 2.0 + 0.3, WALL_H, 0.15), Vector3(0, WALL_H * 0.5, -ROOM_Z - 0.075), wall)
	ProtoMesh.box(self, Vector3(0.15, WALL_H, ROOM_Z * 2.0), Vector3(-ROOM_X - 0.075, WALL_H * 0.5, 0), wall)
	ProtoMesh.box(self, Vector3(0.15, WALL_H, ROOM_Z * 2.0), Vector3(ROOM_X + 0.075, WALL_H * 0.5, 0), wall)
	var front_h := 0.45
	var left_len := DOOR_X - 0.5 + ROOM_X
	var right_len := ROOM_X - (DOOR_X + 0.5)
	ProtoMesh.box(self, Vector3(left_len, front_h, 0.15), Vector3(-ROOM_X + left_len * 0.5, front_h * 0.5, ROOM_Z + 0.075), wall)
	ProtoMesh.box(self, Vector3(right_len, front_h, 0.15), Vector3(DOOR_X + 0.5 + right_len * 0.5, front_h * 0.5, ROOM_Z + 0.075), wall)
	ProtoMesh.box(self, Vector3(ROOM_X * 2.0 + 0.3, 0.08, 0.18), Vector3(0, front_h, ROOM_Z + 0.075), wall_trim)
	ProtoMesh.box(self, Vector3(ROOM_X * 2.0, 0.12, 0.05), Vector3(0, 0.06, -ROOM_Z + 0.02), wall_trim)
	# Door mat
	ProtoMesh.box(self, Vector3(1.0, 0.02, 0.6), Vector3(DOOR_X, 0.01, ROOM_Z - 0.35), ProtoMesh.mat(Color(0.55, 0.22, 0.18)))
	# Windows on the back wall (daylight emission driven by the clock)
	for wx in [-3.0, 0.9, 3.2]:
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.3, 0.4, 0.55)
		wm.emission_enabled = true
		wm.roughness = 0.2
		day_night.window_materials.append(wm)
		ProtoMesh.box(self, Vector3(1.0, 0.6, 0.04), Vector3(wx, 1.65, -ROOM_Z + 0.01), wm)
		ProtoMesh.box(self, Vector3(1.12, 0.06, 0.08), Vector3(wx, 1.32, -ROOM_Z + 0.03), wall_trim)
	# Colliders
	ProtoMesh.static_box_collider(self, Vector3(ROOM_X * 2, 4, 0.3), Vector3(0, 1, -ROOM_Z - 0.15))
	ProtoMesh.static_box_collider(self, Vector3(0.3, 4, ROOM_Z * 2), Vector3(-ROOM_X - 0.15, 1, 0))
	ProtoMesh.static_box_collider(self, Vector3(0.3, 4, ROOM_Z * 2), Vector3(ROOM_X + 0.15, 1, 0))
	ProtoMesh.static_box_collider(self, Vector3(ROOM_X * 2, 4, 0.3), Vector3(0, 1, ROOM_Z + 0.15))


func _build_furniture() -> void:
	var metal := ProtoMesh.mat(Color(0.6, 0.62, 0.65), 0.4)
	var fabric := ProtoMesh.mat(Color(0.32, 0.42, 0.58))
	var pillow := ProtoMesh.mat(Color(0.92, 0.9, 0.85))
	var blanket := ProtoMesh.mat(Color(0.75, 0.38, 0.28))
	var counter := ProtoMesh.mat(Color(0.9, 0.88, 0.82))
	var cabinet := ProtoMesh.mat(Color(0.5, 0.62, 0.55))
	var dark := ProtoMesh.mat(Color(0.12, 0.12, 0.13))
	var wood := ProtoMesh.mat(Color(0.58, 0.41, 0.24))
	var wood_dark := ProtoMesh.mat(Color(0.38, 0.26, 0.16))
	var crate := ProtoMesh.mat(Color(0.7, 0.55, 0.32))
	var red := ProtoMesh.mat(Color(0.7, 0.2, 0.18))

	# Folding cot (간이침대) along the back-left
	var cot := Vector3(-3.3, 0, -1.55)
	ProtoMesh.box(self, Vector3(1.95, 0.08, 0.75), cot + Vector3(0, 0.45, 0), fabric)
	ProtoMesh.box(self, Vector3(0.45, 0.12, 0.6), cot + Vector3(-0.7, 0.55, 0), pillow)
	ProtoMesh.box(self, Vector3(0.7, 0.1, 0.78), cot + Vector3(0.45, 0.53, 0), blanket)
	for lx in [-0.85, 0.85]:
		ProtoMesh.box(self, Vector3(0.04, 0.6, 0.04), cot + Vector3(lx, 0.22, 0), metal, Vector3(0, 0, 25))
		ProtoMesh.box(self, Vector3(0.04, 0.6, 0.04), cot + Vector3(lx, 0.22, 0), metal, Vector3(0, 0, -25))
		ProtoMesh.box(self, Vector3(0.04, 0.04, 0.78), cot + Vector3(lx, 0.02, 0), metal)
	ProtoMesh.static_box_collider(self, Vector3(2.0, 2, 0.8), cot + Vector3(0, 0.5, 0))
	# Storage chest at the foot of the cot
	ProtoMesh.box(self, Vector3(0.8, 0.5, 0.5), Vector3(-3.9, 0.25, -0.4), wood)
	ProtoMesh.box(self, Vector3(0.82, 0.06, 0.52), Vector3(-3.9, 0.52, -0.4), wood_dark)
	ProtoMesh.static_box_collider(self, Vector3(0.8, 2, 0.5), Vector3(-3.9, 0.5, -0.4))

	# Kitchen along the back wall: counter, sink, 2-burner stove, upper cabinets, fridge
	var k := Vector3(-0.2, 0, -1.85)
	ProtoMesh.box(self, Vector3(2.6, 0.86, 0.6), k + Vector3(0, 0.43, 0), cabinet)
	ProtoMesh.box(self, Vector3(2.66, 0.06, 0.66), k + Vector3(0, 0.89, 0.02), counter)
	for i in 4:
		ProtoMesh.box(self, Vector3(0.02, 0.7, 0.02), k + Vector3(-1.3 + (i + 1) * 0.52, 0.43, 0.305), dark)
	ProtoMesh.box(self, Vector3(0.55, 0.04, 0.4), k + Vector3(-0.6, 0.91, 0.02), metal)
	ProtoMesh.box(self, Vector3(0.04, 0.25, 0.04), k + Vector3(-0.6, 1.04, -0.2), metal)
	for bx in [0.45, 0.85]:
		ProtoMesh.cylinder(self, 0.14, 0.03, k + Vector3(bx, 0.935, 0.02), dark, Vector3.ZERO, 8)
	ProtoMesh.cylinder(self, 0.12, 0.14, k + Vector3(0.45, 1.02, 0.02), red, Vector3.ZERO, 8)  # pot
	ProtoMesh.box(self, Vector3(2.6, 0.5, 0.35), k + Vector3(0, 2.0, -0.12), cabinet)
	ProtoMesh.box(self, Vector3(0.65, 1.75, 0.62), Vector3(1.55, 0.875, -1.85), counter)
	ProtoMesh.box(self, Vector3(0.04, 0.4, 0.04), Vector3(1.32, 1.2, -1.53), metal)
	ProtoMesh.static_box_collider(self, Vector3(3.3, 2, 0.65), Vector3(0.1, 0.5, -1.85))

	# Dinette: small table + two benches (center-left, near camera side)
	var t := Vector3(-0.6, 0, 0.9)
	ProtoMesh.box(self, Vector3(1.0, 0.06, 0.7), t + Vector3(0, 0.72, 0), wood)
	ProtoMesh.box(self, Vector3(0.1, 0.7, 0.1), t + Vector3(0, 0.36, 0), metal)
	for s in [-1.0, 1.0]:
		ProtoMesh.box(self, Vector3(0.45, 0.42, 0.7), t + Vector3(s * 0.85, 0.21, 0), fabric)
	ProtoMesh.cylinder(self, 0.06, 0.12, t + Vector3(0.2, 0.81, 0.1), pillow, Vector3.ZERO, 6)
	ProtoMesh.static_box_collider(self, Vector3(2.2, 2, 0.75), t + Vector3(0, 0.5, 0))

	# Workbench at the right end with vise, tools, pegboard
	var w := Vector3(3.55, 0, -1.6)
	ProtoMesh.box(self, Vector3(1.6, 0.08, 0.8), w + Vector3(0, 0.9, 0), wood)
	for lx in [-0.72, 0.72]:
		for lz in [-0.32, 0.32]:
			ProtoMesh.box(self, Vector3(0.08, 0.9, 0.08), w + Vector3(lx, 0.45, lz), wood_dark)
	ProtoMesh.box(self, Vector3(1.5, 0.05, 0.7), w + Vector3(0, 0.3, 0), wood_dark)
	ProtoMesh.box(self, Vector3(0.25, 0.18, 0.2), w + Vector3(0.55, 1.03, 0.25), metal)
	ProtoMesh.box(self, Vector3(0.35, 0.04, 0.05), w + Vector3(-0.3, 0.96, 0.15), wood_dark, Vector3(0, 30, 0))
	ProtoMesh.box(self, Vector3(0.08, 0.07, 0.14), w + Vector3(-0.15, 0.97, 0.06), metal, Vector3(0, 30, 0))
	ProtoMesh.box(self, Vector3(1.4, 0.9, 0.04), w + Vector3(0, 1.75, -0.58), wood_dark)
	for i in 4:
		ProtoMesh.box(self, Vector3(0.05, 0.35, 0.04), w + Vector3(-0.5 + i * 0.32, 1.75, -0.54), metal)
	ProtoMesh.static_box_collider(self, Vector3(1.7, 2, 0.85), w + Vector3(0, 0.5, 0))

	# Storage: crates and a low shelf near the camera-side right corner
	var st := Vector3(3.2, 0, 1.4)
	ProtoMesh.box(self, Vector3(1.8, 0.06, 0.6), st + Vector3(0, 0.6, 0), wood_dark)
	ProtoMesh.box(self, Vector3(1.8, 0.06, 0.6), st + Vector3(0, 0.03, 0), wood_dark)
	for sx in [-0.88, 0.88]:
		ProtoMesh.box(self, Vector3(0.05, 0.62, 0.6), st + Vector3(sx, 0.31, 0), wood_dark)
	ProtoMesh.box(self, Vector3(0.5, 0.45, 0.45), st + Vector3(-0.5, 0.28, 0), crate)
	ProtoMesh.box(self, Vector3(0.45, 0.4, 0.45), st + Vector3(0.3, 0.26, 0), crate)
	ProtoMesh.box(self, Vector3(0.4, 0.3, 0.4), st + Vector3(-0.4, 0.78, 0), crate, Vector3(0, 12, 0))
	ProtoMesh.cylinder(self, 0.16, 0.42, st + Vector3(0.45, 0.84, 0.05), red, Vector3.ZERO, 8)  # jerrycan-ish
	ProtoMesh.static_box_collider(self, Vector3(1.9, 2, 0.65), st + Vector3(0, 0.5, 0))

	# Rug
	ProtoMesh.box(self, Vector3(1.8, 0.015, 1.1), Vector3(1.4, 0.008, 0.2), ProtoMesh.mat(Color(0.45, 0.32, 0.5)))


func _build_lights() -> void:
	var lamp_mat := ProtoMesh.mat(Color(1, 0.95, 0.8), 0.3, Color(1.0, 0.85, 0.6), 2.5)
	for lx in [-2.4, 1.6]:
		var l := OmniLight3D.new()
		l.position = Vector3(lx, 2.35, -0.3)
		l.light_color = Color(1.0, 0.84, 0.62)
		l.light_energy = 1.4
		l.omni_range = 5.5
		l.shadow_enabled = true
		l.shadow_bias = 0.06
		add_child(l)
		# No visible ceiling fixture: with the ceiling cut away it would float over the room.
	# Under-cabinet LED strip
	ProtoMesh.box(self, Vector3(2.4, 0.03, 0.05), Vector3(-0.2, 1.73, -1.85), lamp_mat)
	# Cool daylight fill through the windows (energy follows the clock)
	_fill_light = OmniLight3D.new()
	_fill_light.position = Vector3(0.5, 1.8, -1.2)
	_fill_light.light_color = Color(0.8, 0.88, 1.0)
	_fill_light.omni_range = 7.0
	add_child(_fill_light)


func _spawn_actors() -> void:
	player = PrototypePlayer.new()
	player.name = "Player"
	player.height_func = Callable(self, "ground_height")
	player.walk_bounds = Rect2(-ROOM_X + 0.35, -ROOM_Z + 0.35, ROOM_X * 2.0 - 0.7, ROOM_Z * 2.0 - 0.7)
	add_child(player)
	var ov := Game.take_spawn_override()
	var rescued: bool = ov.get("kind", "") == "rescued"
	if rescued:
		# Woken on the cot after the cat brought the player home (GDD 2.4 [확정]).
		player.global_position = COT_POS + Vector3(0.2, 0, 0.75)
		player.face_direction(PI)
	else:
		player.global_position = Vector3(DOOR_X, 0.0, ROOM_Z - 0.6)
		player.face_direction(0.0)
	if Game.has_camper:
		cat = CatCompanion.new()
		cat.name = "BlackCat"
		cat.mode = CatCompanion.Mode.HOME
		cat.player = player
		cat.home_spots = CAT_SPOTS
		cat.height_func = Callable(self, "ground_height")
		cat.position = player.global_position + Vector3(0.75, 0, 0.1) if rescued else CAT_SPOTS[0]
		add_child(cat)
		cat.face(player.global_position)
	camera = TopdownCamera.new()
	camera.name = "Camera"
	camera.target = player
	add_child(camera)


func _process(_delta: float) -> void:
	if _fill_light:
		_fill_light.light_energy = lerpf(0.0, 0.8, Game.daylight())


func sprite_targets() -> Array:
	var g := Game.player_state.visual_gear()
	var out := [[player, PrototypePlayer.sprite_bake_spec(g), "player|" + PlayerState.gear_key(g)]]
	if cat:
		out.append([cat, CatCompanion.sprite_bake_spec(), "cat"])
	return out


func _build_interactions() -> void:
	InteractPoint.make(self, Vector3(DOOR_X, 0, ROOM_Z - 0.35), "E 밖으로 나가기",
			func(_p: Node) -> void: Game.request_world(Game.WORLD_EXTERIOR), 1.1)
	var cot := InteractPoint.make(self, COT_POS + Vector3(0, 0, 0.6), "E 간이침대에서 자기 (수면 시간 선택)", Callable(), 1.3)
	cot.action = func(_p: Node) -> void: Game.hud.open_sleep(cot)
	var box := InteractPoint.make(self, STORAGE_POS + Vector3(0, 0, -0.55), "E 캠핑카 창고 열기", Callable(), 1.4)
	box.action = func(_p: Node) -> void: Game.hud.open_storage(box)
	InteractPoint.facility(self, Vector3(0.4, 0, -1.1), "cooking", "주방 (2구 버너)")


func cycle_occlusion_mode() -> String:
	player.set_silhouette(not player.silhouette_enabled)
	return occlusion_mode_name()


func occlusion_mode_name() -> String:
	return "실루엣" if player.silhouette_enabled else "끔"


func try_toggle_camper_lights() -> String:
	return "실내에서는 외부 라이트를 조작하지 않습니다"


func context_hint() -> String:
	return ""


func world_title() -> String:
	return "캠핑카 실내 랩 (camper_interior_lab)"
