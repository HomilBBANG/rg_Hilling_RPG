class_name CamperInteriorLab
extends Node3D
## Camper interior (separate scene, GDD 3.1/9.1 [확정]): door back out, folding cot for sleep
## (9.6), weight-limited storage (8.3) and the black cat who is always here once the camper is
## owned (2.5).
## Room is 9 x 4.4 m while the exterior body is 2.4 m wide: a first try at the
## "magically larger inside" feeling. Camera-side wall is cut down so the room stays readable.
## Upgrades (GDD 9.1 / 9.2, CamperUpgrades): the bed's tier, the workbench / fuel refinery,
## magic room modules east of the main room (each with a purpose the player picks) and small
## decor the player places freely (bought from the carpenter, placed from the bag: E place,
## R turn, X cancel; E on a placed piece picks it back up).

const ROOM_X := 4.5
const ROOM_Z := 2.2
const WALL_H := 2.5
const DOOR_X := -1.6
const COT_POS := Vector3(-3.3, 0, -1.55)
const STORAGE_POS := Vector3(3.2, 0, 1.4)
const CAT_SPOTS: Array[Vector3] = [Vector3(1.4, 0, 0.2), Vector3(-1.9, 0, 0.6), Vector3(2.2, 0, -0.6), Vector3(-2.5, 0, -0.75)]
const MODULE_W := 6.0          ## width of one magic room module (east of the main room)
const REFINERY_POS := Vector3(1.5, 0, 1.65)
const PLAQUE_POS := Vector3(-2.7, 0, 1.75)

var player: PrototypePlayer
var camera: TopdownCamera
var cat: CatCompanion
var day_night: DayNightController
var _fill_light: OmniLight3D
var _room_spots: Array[Vector3] = []   # extra cat spots from rooms / decor
var _placing := ""                     # decor item being placed ("" = not placing)
var _ghost: Node3D
var _ghost_yaw := 0.0
var _decor_root: Node3D


func _ready() -> void:
	if get_tree().current_scene == self:
		Game.start_world = Game.WORLD_INTERIOR
		get_tree().change_scene_to_file.call_deferred("res://scenes/bootstrap.tscn")
		return
	_build_environment()
	_build_shell()
	_build_furniture()
	_build_rooms()
	_decor_root = Node3D.new()
	add_child(_decor_root)
	_build_decor()
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
	# Planks at roughness 1.0 sit outside the pixel outline pass (its light bevel lines read as
	# white streaks on the floor); the seams are drawn as dark shade-coloured strips instead.
	var plank_a := ProtoMesh.mat(Color(0.62, 0.45, 0.3), 1.0)
	var plank_b := ProtoMesh.mat(Color(0.56, 0.4, 0.26), 1.0)
	var seam := ProtoMesh.mat(Color(0.33, 0.22, 0.14), 1.0)
	var wall := ProtoMesh.mat(Color(0.88, 0.84, 0.76))
	var wall_trim := ProtoMesh.mat(Color(0.45, 0.33, 0.24))
	# Floor planks
	var n := int(ROOM_Z * 2.0 / 0.4)
	for i in n:
		var z := -ROOM_Z + 0.2 + i * 0.4
		ProtoMesh.box(self, Vector3(ROOM_X * 2.0, 0.1, 0.39), Vector3(0, -0.05, z), plank_a if i % 2 == 0 else plank_b)
		if i > 0:
			ProtoMesh.box(self, Vector3(ROOM_X * 2.0, 0.104, 0.035), Vector3(0, -0.05, z - 0.2), seam)
	# Back (north) wall full height, end walls full height, front (camera-side) wall cut down.
	ProtoMesh.box(self, Vector3(ROOM_X * 2.0 + 0.3, WALL_H, 0.15), Vector3(0, WALL_H * 0.5, -ROOM_Z - 0.075), wall)
	ProtoMesh.box(self, Vector3(0.15, WALL_H, ROOM_Z * 2.0), Vector3(-ROOM_X - 0.075, WALL_H * 0.5, 0), wall)
	_end_wall(ROOM_X, wall, CamperUpgrades.rooms_max() > 0)
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
	ProtoMesh.static_box_collider(self, Vector3(ROOM_X * 2, 4, 0.3), Vector3(0, 1, ROOM_Z + 0.15))


## East wall of the main room / a module: solid, or with a 1.4 m archway into the next room.
func _end_wall(x: float, wall: Material, opening: bool) -> void:
	if not opening:
		ProtoMesh.box(self, Vector3(0.15, WALL_H, ROOM_Z * 2.0), Vector3(x + 0.075, WALL_H * 0.5, 0), wall)
		ProtoMesh.static_box_collider(self, Vector3(0.3, 4, ROOM_Z * 2), Vector3(x + 0.15, 1, 0))
		return
	var seg := ROOM_Z - 0.7
	for s in [-1.0, 1.0]:
		ProtoMesh.box(self, Vector3(0.15, WALL_H, seg), Vector3(x + 0.075, WALL_H * 0.5, s * (0.7 + seg * 0.5)), wall)
		ProtoMesh.static_box_collider(self, Vector3(0.3, 4, seg), Vector3(x + 0.15, 1, s * (0.7 + seg * 0.5)))
	ProtoMesh.box(self, Vector3(0.15, 0.5, 1.4), Vector3(x + 0.075, WALL_H - 0.25, 0), wall)
	# a faint violet shimmer on the arch: the room is bigger inside by magic
	var glow := ProtoMesh.mat(Color(0.7, 0.55, 1.0), 0.4, Color(0.6, 0.45, 1.0), 1.2)
	ProtoMesh.box(self, Vector3(0.18, 0.05, 1.45), Vector3(x + 0.075, WALL_H - 0.5, 0), glow)


func _total_east() -> float:
	return ROOM_X + MODULE_W * CamperUpgrades.rooms_max()


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

	# Bed along the back-left: folding cot (간이침대) → sofa bed → proper bed (GDD 9.6 upgrades)
	var cot := COT_POS
	match CamperUpgrades.bed():
		"sofa":
			var sofa := ProtoMesh.mat(Color(0.46, 0.36, 0.56))
			ProtoMesh.box(self, Vector3(2.0, 0.4, 0.8), cot + Vector3(0, 0.25, 0), sofa)
			ProtoMesh.box(self, Vector3(2.0, 0.55, 0.18), cot + Vector3(0, 0.55, -0.32), sofa)
			for sx in [-1.0, 1.0]:
				ProtoMesh.box(self, Vector3(0.16, 0.6, 0.8), cot + Vector3(sx * 1.0, 0.35, 0), sofa)
			ProtoMesh.box(self, Vector3(0.42, 0.14, 0.32), cot + Vector3(-0.6, 0.52, 0.0), pillow)
			ProtoMesh.box(self, Vector3(0.8, 0.06, 0.7), cot + Vector3(0.4, 0.48, 0.02), blanket)
		"bed":
			ProtoMesh.box(self, Vector3(2.05, 0.35, 0.85), cot + Vector3(0, 0.2, 0), wood_dark)
			ProtoMesh.box(self, Vector3(1.95, 0.2, 0.8), cot + Vector3(0, 0.47, 0), pillow)
			ProtoMesh.box(self, Vector3(0.12, 0.85, 0.85), cot + Vector3(-1.05, 0.45, 0), wood)
			ProtoMesh.box(self, Vector3(0.45, 0.14, 0.62), cot + Vector3(-0.68, 0.63, 0), pillow)
			ProtoMesh.box(self, Vector3(1.2, 0.08, 0.86), cot + Vector3(0.35, 0.6, 0), blanket)
		_:
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
	if CamperUpgrades.has_facility("refinery"):
		_build_refinery(REFINERY_POS)
	# name plaque by the door (GDD 9.1: the player names the camper)
	ProtoMesh.box(self, Vector3(0.6, 0.3, 0.05), PLAQUE_POS + Vector3(0, 0.45, 0.42), wood_dark)
	ProtoMesh.box(self, Vector3(0.5, 0.2, 0.06), PLAQUE_POS + Vector3(0, 0.45, 0.42), ProtoMesh.mat(Color(0.95, 0.85, 0.55)))


## Fuel refinery appliance: a squat tank with a coil, a gauge and a glowing sight glass.
func _build_refinery(p: Vector3) -> void:
	var metal := ProtoMesh.mat(Color(0.55, 0.58, 0.62), 0.4)
	var copper := ProtoMesh.mat(Color(0.78, 0.48, 0.28), 0.4)
	var glow := ProtoMesh.mat(Color(0.5, 0.85, 0.95), 0.3, Color(0.4, 0.8, 1.0), 1.4) if CamperUpgrades.fuel_kind() == "magic" else ProtoMesh.mat(Color(0.95, 0.7, 0.3), 0.3, Color(1.0, 0.6, 0.2), 1.2)
	ProtoMesh.cylinder(self, 0.32, 0.9, p + Vector3(-0.15, 0.45, 0), metal, Vector3.ZERO, 12)
	ProtoMesh.cylinder(self, 0.18, 0.05, p + Vector3(-0.15, 0.93, 0), copper, Vector3.ZERO, 10)
	for i in 3:
		ProtoMesh.cylinder(self, 0.14, 0.05, p + Vector3(0.3, 0.3 + i * 0.18, 0), copper, Vector3(0, 0, 90), 8)
	ProtoMesh.box(self, Vector3(0.14, 0.2, 0.05), p + Vector3(-0.15, 0.55, 0.32), glow)
	ProtoMesh.static_box_collider(self, Vector3(0.8, 2, 0.6), p + Vector3(0.05, 0.5, 0))


# ---------------------------------------------------------------- magic rooms (GDD 9.1 / 9.2-6)

func _build_rooms() -> void:
	var rooms := CamperUpgrades.rooms()
	var plank_a := ProtoMesh.mat(Color(0.6, 0.44, 0.32), 1.0)
	var plank_b := ProtoMesh.mat(Color(0.54, 0.38, 0.27), 1.0)
	var seam := ProtoMesh.mat(Color(0.33, 0.22, 0.14), 1.0)
	var wall := ProtoMesh.mat(Color(0.86, 0.82, 0.9))
	var trim := ProtoMesh.mat(Color(0.42, 0.34, 0.5))
	for i in rooms.size():
		var x0 := ROOM_X + MODULE_W * i
		var cx := x0 + MODULE_W * 0.5
		var n := int(ROOM_Z * 2.0 / 0.4)
		for j in n:
			ProtoMesh.box(self, Vector3(MODULE_W, 0.1, 0.39), Vector3(cx, -0.05, -ROOM_Z + 0.2 + j * 0.4), plank_a if j % 2 == 0 else plank_b)
			if j > 0:
				ProtoMesh.box(self, Vector3(MODULE_W, 0.104, 0.035), Vector3(cx, -0.05, -ROOM_Z + j * 0.4), seam)
		ProtoMesh.box(self, Vector3(MODULE_W, WALL_H, 0.15), Vector3(cx, WALL_H * 0.5, -ROOM_Z - 0.075), wall)
		ProtoMesh.box(self, Vector3(MODULE_W, 0.45, 0.15), Vector3(cx, 0.225, ROOM_Z + 0.075), wall)
		ProtoMesh.box(self, Vector3(MODULE_W, 0.08, 0.18), Vector3(cx, 0.45, ROOM_Z + 0.075), trim)
		ProtoMesh.static_box_collider(self, Vector3(MODULE_W, 4, 0.3), Vector3(cx, 1, -ROOM_Z - 0.15))
		ProtoMesh.static_box_collider(self, Vector3(MODULE_W, 4, 0.3), Vector3(cx, 1, ROOM_Z + 0.15))
		_end_wall(x0 + MODULE_W, wall, i < rooms.size() - 1)
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.35, 0.3, 0.55)
		wm.emission_enabled = true
		day_night.window_materials.append(wm)
		ProtoMesh.box(self, Vector3(1.2, 0.7, 0.04), Vector3(cx, 1.65, -ROOM_Z + 0.01), wm)
		var l := OmniLight3D.new()
		l.position = Vector3(cx, 2.3, -0.2)
		l.light_color = Color(1.0, 0.86, 0.7)
		l.light_energy = 1.3
		l.omni_range = 5.5
		add_child(l)
		_build_purpose(i, str(rooms[i].get("purpose", "")), Vector3(cx, 0, 0))
		var ip := InteractPoint.make(self, Vector3(cx, 0, ROOM_Z - 0.55), "", Callable(), 1.2)
		var pname := str(CamperUpgrades.purpose_info(str(rooms[i].get("purpose", ""))).get("name", ""))
		ip.prompt = "E 방 꾸미기 — %s" % (pname if pname != "" else "아직 빈 방 (용도 정하기)")
		var idx := i
		ip.action = func(_p: Node) -> void: Game.hud.open_room_purpose(idx, ip)


## Fixed furniture of a room's purpose, around the room centre c.
func _build_purpose(i: int, purpose: String, c: Vector3) -> void:
	var wood := ProtoMesh.mat(Color(0.58, 0.41, 0.24))
	var wood_dark := ProtoMesh.mat(Color(0.38, 0.26, 0.16))
	var fabric := ProtoMesh.mat(Color(0.36, 0.5, 0.62))
	var pillow := ProtoMesh.mat(Color(0.94, 0.92, 0.86))
	match purpose:
		"lounge":
			var sofa := ProtoMesh.mat(Color(0.62, 0.36, 0.3))
			ProtoMesh.box(self, Vector3(2.4, 0.42, 0.85), c + Vector3(0, 0.25, -1.55), sofa)
			ProtoMesh.box(self, Vector3(2.4, 0.6, 0.2), c + Vector3(0, 0.6, -1.9), sofa)
			ProtoMesh.box(self, Vector3(1.2, 0.4, 0.7), c + Vector3(0, 0.2, -0.3), wood)
			ProtoMesh.box(self, Vector3(2.6, 0.015, 1.8), c + Vector3(0, 0.008, -0.6), ProtoMesh.mat(Color(0.32, 0.46, 0.4)))
			ProtoMesh.static_box_collider(self, Vector3(2.4, 2, 1.0), c + Vector3(0, 0.5, -1.6))
			ProtoMesh.static_box_collider(self, Vector3(1.2, 2, 0.7), c + Vector3(0, 0.5, -0.3))
			_room_spots.append(c + Vector3(0.6, 0, -1.5))
		"bedroom":
			ProtoMesh.box(self, Vector3(2.2, 0.4, 1.6), c + Vector3(-1.2, 0.22, -1.25), wood_dark)
			ProtoMesh.box(self, Vector3(2.1, 0.22, 1.5), c + Vector3(-1.2, 0.5, -1.25), pillow)
			ProtoMesh.box(self, Vector3(1.3, 0.08, 1.52), c + Vector3(-0.85, 0.64, -1.25), ProtoMesh.mat(Color(0.52, 0.34, 0.62)))
			for z in [-1.6, -0.9]:
				ProtoMesh.box(self, Vector3(0.4, 0.14, 0.5), c + Vector3(-2.05, 0.67, z), pillow)
			ProtoMesh.box(self, Vector3(0.5, 0.5, 0.45), c + Vector3(0.25, 0.25, -1.75), wood)
			ProtoMesh.static_box_collider(self, Vector3(2.2, 2, 1.6), c + Vector3(-1.2, 0.5, -1.25))
			var bed_ip := InteractPoint.make(self, c + Vector3(-1.2, 0, -0.1), "E 침대에서 자기 (침실: 회복 +10%p)", Callable(), 1.3)
			bed_ip.set_meta("bedroom", true)
			bed_ip.action = func(_p: Node) -> void: Game.hud.open_sleep(bed_ip)
		"workshop":
			ProtoMesh.box(self, Vector3(1.8, 0.08, 0.8), c + Vector3(-1.3, 0.9, -1.6), wood)
			for lx in [-0.8, 0.8]:
				ProtoMesh.box(self, Vector3(0.08, 0.9, 0.7), c + Vector3(-1.3 + lx, 0.45, -1.6), wood_dark)
			ProtoMesh.static_box_collider(self, Vector3(1.9, 2, 0.85), c + Vector3(-1.3, 0.5, -1.6))
			InteractPoint.facility(self, c + Vector3(-1.3, 0, -0.85), "workbench", "작업실 작업대")
			_build_refinery(c + Vector3(1.4, 0, -1.7))
			InteractPoint.facility(self, c + Vector3(1.4, 0, -1.0), "refinery", "작업실 연료 정제기")
		"storage_room":
			for k in 3:
				var sx := -2.0 + k * 2.0
				ProtoMesh.box(self, Vector3(1.6, 1.8, 0.5), c + Vector3(sx, 0.9, -1.85), wood_dark)
				for h in [0.5, 1.1]:
					ProtoMesh.box(self, Vector3(0.45, 0.35, 0.35), c + Vector3(sx - 0.4 + h * 0.3, h + 0.2, -1.8), ProtoMesh.mat(Color(0.72, 0.56, 0.34)))
			ProtoMesh.static_box_collider(self, Vector3(5.6, 2, 0.6), c + Vector3(0, 0.5, -1.85))
			var box := InteractPoint.make(self, c + Vector3(0, 0, -1.1), "E 창고 열기 (창고방)", Callable(), 1.6)
			box.action = func(_p: Node) -> void: Game.hud.open_storage(box)
		"cat_room":
			_build_cat_tower(c + Vector3(-1.8, 0, -1.4))
			for cp in [Vector3(0.6, 0, -1.2), Vector3(1.8, 0, -0.4)]:
				ProtoMesh.cylinder(self, 0.4, 0.12, c + cp + Vector3(0, 0.06, 0), ProtoMesh.mat(Color(0.86, 0.5, 0.42)), Vector3.ZERO, 12)
				_room_spots.append(c + cp)
			_room_spots.append(c + Vector3(-1.8, 0, -1.4))
		_:
			# an empty module: bare floor and a sign that it can be furnished
			ProtoMesh.box(self, Vector3(0.6, 0.6, 0.05), c + Vector3(0, 0.9, -ROOM_Z + 0.08), ProtoMesh.mat(Color(0.95, 0.9, 0.7)))


func _build_cat_tower(p: Vector3) -> void:
	var post := ProtoMesh.mat(Color(0.82, 0.72, 0.52))
	var pad := ProtoMesh.mat(Color(0.5, 0.42, 0.62))
	ProtoMesh.box(self, Vector3(0.9, 0.08, 0.9), p + Vector3(0, 0.04, 0), pad)
	ProtoMesh.cylinder(self, 0.08, 1.4, p + Vector3(-0.2, 0.7, 0), post, Vector3.ZERO, 8)
	ProtoMesh.cylinder(self, 0.08, 0.9, p + Vector3(0.25, 0.45, 0.2), post, Vector3.ZERO, 8)
	ProtoMesh.cylinder(self, 0.36, 0.08, p + Vector3(-0.2, 1.42, 0), pad, Vector3.ZERO, 10)
	ProtoMesh.cylinder(self, 0.3, 0.08, p + Vector3(0.25, 0.92, 0.2), pad, Vector3.ZERO, 10)


# ---------------------------------------------------------------- free decor (GDD 9.1: 소형 가구 자유 배치)

func _decor_model(item: String) -> Node3D:
	var root := Node3D.new()
	match item:
		"decor_plant":
			ProtoMesh.cylinder(root, 0.2, 0.32, Vector3(0, 0.16, 0), ProtoMesh.mat(Color(0.72, 0.4, 0.28)), Vector3.ZERO, 10, 0.16)
			var leaf := ProtoMesh.mat(Color(0.3, 0.58, 0.32))
			for k in 5:
				var a := TAU * k / 5.0
				ProtoMesh.sphere(root, 0.18, Vector3(cos(a) * 0.12, 0.5 + (k % 2) * 0.12, sin(a) * 0.12), leaf, Vector3(1.0, 1.4, 1.0), 8, 5)
		"decor_lamp":
			var metal := ProtoMesh.mat(Color(0.3, 0.28, 0.26), 0.4)
			ProtoMesh.cylinder(root, 0.16, 0.04, Vector3(0, 0.02, 0), metal, Vector3.ZERO, 10)
			ProtoMesh.cylinder(root, 0.025, 1.3, Vector3(0, 0.67, 0), metal, Vector3.ZERO, 6)
			ProtoMesh.cylinder(root, 0.22, 0.26, Vector3(0, 1.4, 0), ProtoMesh.mat(Color(1.0, 0.9, 0.66), 0.4, Color(1.0, 0.82, 0.5), 1.0), Vector3.ZERO, 10, 0.12)
			var l := OmniLight3D.new()
			l.position = Vector3(0, 1.3, 0)
			l.light_color = Color(1.0, 0.8, 0.55)
			l.light_energy = 1.0
			l.omni_range = 3.5
			root.add_child(l)
		"decor_rug":
			var r := ProtoMesh.cylinder(root, 0.8, 0.015, Vector3(0, 0.01, 0), ProtoMesh.mat(Color(0.86, 0.6, 0.36)), Vector3.ZERO, 18)
			r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ProtoMesh.cylinder(root, 0.5, 0.017, Vector3(0, 0.012, 0), ProtoMesh.mat(Color(0.92, 0.84, 0.66)), Vector3.ZERO, 16)
		"decor_shelf":
			var w := ProtoMesh.mat(Color(0.5, 0.34, 0.2))
			ProtoMesh.box(root, Vector3(0.9, 1.2, 0.32), Vector3(0, 0.6, 0), w)
			var cols := [Color(0.7, 0.2, 0.2), Color(0.2, 0.4, 0.7), Color(0.3, 0.6, 0.35), Color(0.85, 0.7, 0.3)]
			for k in 6:
				ProtoMesh.box(root, Vector3(0.1, 0.3, 0.24), Vector3(-0.32 + k * 0.12, 0.85 if k < 4 else 0.4, 0.05), ProtoMesh.mat(cols[k % 4]))
		"decor_cat_tower":
			var post := ProtoMesh.mat(Color(0.82, 0.72, 0.52))
			var pad := ProtoMesh.mat(Color(0.5, 0.42, 0.62))
			ProtoMesh.box(root, Vector3(0.7, 0.06, 0.7), Vector3(0, 0.03, 0), pad)
			ProtoMesh.cylinder(root, 0.07, 1.1, Vector3(0, 0.55, 0), post, Vector3.ZERO, 8)
			ProtoMesh.cylinder(root, 0.3, 0.07, Vector3(0, 1.12, 0), pad, Vector3.ZERO, 10)
		"decor_painting":
			var w2 := ProtoMesh.mat(Color(0.45, 0.3, 0.18))
			ProtoMesh.box(root, Vector3(0.05, 1.1, 0.05), Vector3(0, 0.55, -0.1), w2, Vector3(-10, 0, 0))
			ProtoMesh.box(root, Vector3(0.7, 0.5, 0.04), Vector3(0, 0.95, 0.0), w2, Vector3(-10, 0, 0))
			ProtoMesh.box(root, Vector3(0.6, 0.4, 0.045), Vector3(0, 0.95, 0.005), ProtoMesh.mat(Color(0.5, 0.72, 0.85)), Vector3(-10, 0, 0))
			ProtoMesh.box(root, Vector3(0.6, 0.15, 0.05), Vector3(0, 0.82, 0.01), ProtoMesh.mat(Color(0.4, 0.62, 0.36)), Vector3(-10, 0, 0))
	return root


func _build_decor() -> void:
	for c in _decor_root.get_children():
		c.queue_free()
	for k in range(_room_spots.size() - 1, -1, -1):  # decor cat spots are rebuilt below
		if _room_spots[k].y > 0.5:
			_room_spots.remove_at(k)
	var list: Array = Game.camper_mods.get("decor", [])
	for i in list.size():
		var d: Dictionary = list[i]
		var m := _decor_model(str(d["item"]))
		m.position = Vector3(float(d["pos"][0]), 0, float(d["pos"][1]))
		m.rotation.y = float(d.get("yaw", 0.0))
		_decor_root.add_child(m)
		if d["item"] == "decor_cat_tower":
			_room_spots.append(m.position + Vector3(0, 1.0, 0))  # y marks a decor spot (cat uses x/z)
		var ip := InteractPoint.make(_decor_root, m.position + Vector3(0, 0, 0.5), "E 집어 들기 — %s" % ItemDB.item_name(str(d["item"])), Callable(), 0.9)
		var idx := i
		ip.action = func(_p: Node) -> void: pick_up_decor(idx)
	if cat:
		cat.home_spots = _cat_spots()


func placing() -> bool:
	return _placing != ""


## Start placing a decor item from the bag: a ghost follows in front of the player.
func begin_place(item: String) -> void:
	if Game.player_state.inventory.count(item) <= 0:
		return
	cancel_place()
	_placing = item
	_ghost = _decor_model(item)
	for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).transparency = 0.45
	add_child(_ghost)
	_ghost_yaw = 0.0
	Game.hud.show_caption("%s 배치 — 움직여서 자리 잡기 · E 놓기 · R 돌리기 · X 취소" % ItemDB.item_name(item))


func cancel_place() -> void:
	if _ghost:
		_ghost.queue_free()
	_ghost = null
	_placing = ""
	if Game.hud:
		Game.hud.show_caption("")


func _ghost_pos() -> Vector3:
	var f := Vector3(-sin(player._yaw), 0, -cos(player._yaw))
	var p := player.global_position + f * 1.1
	p.x = clampf(snappedf(p.x, 0.25), -ROOM_X + 0.4, _total_east() - 0.4)
	p.z = clampf(snappedf(p.z, 0.25), -ROOM_Z + 0.4, ROOM_Z - 0.4)
	return Vector3(p.x, 0, p.z)


## Keys while placing (bootstrap routes them here). Returns true when used.
func handle_place_key(ev: InputEvent) -> bool:
	if not placing() or not (ev is InputEventKey):
		return false
	match (ev as InputEventKey).physical_keycode:
		KEY_E:
			place_here()
		KEY_R:
			_ghost_yaw = fposmod(_ghost_yaw + PI * 0.25, TAU)
		KEY_X:
			cancel_place()
		_:
			return false
	return true


func place_here() -> void:
	if not placing():
		return
	var p := _ghost_pos()
	if Game.player_state.inventory.remove(_placing, 1) <= 0:
		cancel_place()
		return
	var list: Array = Game.camper_mods["decor"]
	list.append({"item": _placing, "pos": [p.x, p.z], "yaw": _ghost_yaw})
	Game.boot.hud.toast("%s을(를) 놓았다" % ItemDB.item_name(_placing))
	cancel_place()
	_build_decor()


func pick_up_decor(i: int) -> void:
	var list: Array = Game.camper_mods["decor"]
	if i < 0 or i >= list.size():
		return
	var d: Dictionary = list[i]
	Game.player_state.inventory.add(str(d["item"]), 1)
	list.remove_at(i)
	Game.boot.hud.toast("%s을(를) 가방에 넣었다" % ItemDB.item_name(str(d["item"])))
	_build_decor.call_deferred()


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
	player.walk_bounds = Rect2(-ROOM_X + 0.35, -ROOM_Z + 0.35, ROOM_X + _total_east() - 0.7, ROOM_Z * 2.0 - 0.7)
	add_child(player)
	var ov := Game.take_spawn_override()
	var rescued: bool = ov.get("kind", "") == "rescued"
	if rescued:
		# Woken on the cot after the cat brought the player home (GDD 2.4 [확정]).
		player.global_position = COT_POS + Vector3(0.2, 0, 0.75)
		player.face_direction(PI)
	elif ov.has("pos"):  # loaded save
		var lp: Vector3 = ov["pos"]
		player.global_position = Vector3(lp.x, 0.0, lp.z)
		player.face_direction(float(ov.get("yaw", 0.0)))
	else:
		player.global_position = Vector3(DOOR_X, 0.0, ROOM_Z - 0.6)
		player.face_direction(0.0)
	if Game.has_camper:
		cat = CatCompanion.new()
		cat.name = "BlackCat"
		cat.mode = CatCompanion.Mode.HOME
		cat.player = player
		cat.home_spots = _cat_spots()
		cat.height_func = Callable(self, "ground_height")
		cat.position = player.global_position + Vector3(0.75, 0, 0.1) if rescued else CAT_SPOTS[0]
		add_child(cat)
		cat.face(player.global_position)
	camera = TopdownCamera.new()
	camera.name = "Camera"
	camera.target = player
	add_child(camera)


func _cat_spots() -> Array[Vector3]:
	var out: Array[Vector3] = CAT_SPOTS.duplicate()
	for s in _room_spots:
		out.append(Vector3(s.x, 0, s.z))
	return out


func _process(_delta: float) -> void:
	if _ghost:
		_ghost.position = _ghost_pos()
		_ghost.rotation.y = _ghost_yaw
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
	var cot := InteractPoint.make(self, COT_POS + Vector3(0, 0, 0.6), "E %s에서 자기 (수면 시간 선택)" % CamperUpgrades.bed_info().get("name", "간이침대"), Callable(), 1.3)
	cot.action = func(_p: Node) -> void: Game.hud.open_sleep(cot)
	var box := InteractPoint.make(self, STORAGE_POS + Vector3(0, 0, -0.55), "E 캠핑카 창고 열기", Callable(), 1.4)
	box.action = func(_p: Node) -> void: Game.hud.open_storage(box)
	InteractPoint.facility(self, Vector3(0.4, 0, -1.1), "cooking", "주방 (2구 버너)")
	if CamperUpgrades.has_facility("workbench"):
		InteractPoint.facility(self, Vector3(3.4, 0, -0.85), "workbench", "실내 작업대")
	if CamperUpgrades.has_facility("refinery"):
		InteractPoint.facility(self, REFINERY_POS + Vector3(0, 0, -0.75), "refinery", "실내 연료 정제기")
	var plaque := InteractPoint.make(self, PLAQUE_POS, "E 이름표 — %s 이름 짓기" % CamperUpgrades.camper_name(), Callable(), 1.0)
	plaque.action = func(_p: Node) -> void: Game.hud.open_camper_name(plaque)


func cycle_occlusion_mode() -> String:
	return occlusion_mode_name()


func occlusion_mode_name() -> String:
	return "끔 (실내)"


func try_toggle_camper_lights() -> String:
	return "실내에서는 외부 라이트를 조작하지 않습니다"


func context_hint() -> String:
	return ""


func world_title() -> String:
	return "캠핑카 실내 랩 (camper_interior_lab)"
