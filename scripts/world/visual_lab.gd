class_name VisualLab
extends Node3D
## Outdoor field (P0 visual lab, extended for the P1 core loop): meadow, winding path, forest,
## pond, camp with the drivable camper, slime groups, safe checkpoints, the black cat.
## Everything is generated procedurally on load; dead monsters, corpses, the death bag and the
## camper's parking spot persist in Game.field across scene reloads.

enum Occlusion { SILHOUETTE, FADE, OFF }
const OCCLUSION_NAMES := ["실루엣", "수관 디더 투명화", "끔"]
const CAMPER_POS := Vector3(-6.2, 0.0, -2.8)
const CAMPER_YAW_DEG := -6.0
const CAMPER_LIGHT_RANGE := 7.5
const DEFAULT_SPAWN := Vector3(-4.3, 0.0, 1.1)
const CAMPFIRE_POS := Vector3(-2.6, 0.0, 1.9)
## Camp layout is designed around the original parking spot (the camper itself can drive away).
static var CAMP_XF := Transform3D(Basis(Vector3.UP, deg_to_rad(CAMPER_YAW_DEG)), CAMPER_POS)
## [id, home (x, z), 선공 aggressive]. Groups: passive meadow slimes, aggressive forest slimes.
const MONSTER_SPAWNS := [
	["meadow_1", Vector2(14.5, 6.5), false], ["meadow_2", Vector2(16.2, 8.2), false],
	["meadow_3", Vector2(12.8, 8.8), false],
	["forest_1", Vector2(25.5, -14.0), true], ["forest_2", Vector2(27.8, -15.6), true],
	["forest_3", Vector2(24.2, -16.4), true],
]
const MONSTER_RESPAWN_MIN := 120.0  # game minutes [미정]
const CORPSE_LIFETIME_MIN := 60.0  # game minutes [미정]
## Safe checkpoints: no monster may fight inside (GDD 2.4 [확정]); placement / radius [미정].
const CHECKPOINTS := [
	{"id": "camp", "name": "캠프 모닥불", "pos": Vector3(-1.0, 0.0, 4.8), "radius": 6.5, "marker": false},
	{"id": "crossroad", "name": "갈림길 돌무지", "pos": Vector3(44.6, 0.0, 2.0), "radius": 5.0, "marker": true},
	{"id": "lake", "name": "호숫가 쉼터", "pos": Vector3(24.5, 0.0, 25.8), "radius": 5.0, "marker": true},
	{"id": "trade", "name": "길가 교역소", "pos": Vector3(-22.8, 0.0, 6.0), "radius": 7.0, "marker": false},
]
## Trade post west of the camp (P2-4): stalls with a merchant each, their houses behind.
## [stall position, shop id / look, house position]
const TRADE_STALLS := [
	[Vector3(-20.2, 0.0, 4.4), "rosa", Vector3(-20.6, 0.0, -0.8)],
	[Vector3(-25.6, 0.0, 4.2), "bron", Vector3(-26.4, 0.0, -1.2)],
]
const CAT_ENCOUNTER_POS := Vector3(7.5, 0.0, 3.0)
const CRATE_POS := Vector3(-4.6, 0.0, 2.9)  # inside the camper's turning circle: clear of its way out

var terrain := TerrainField.new()
var player: PrototypePlayer
var camera: TopdownCamera
var camper: CamperExterior
var vehicle: CamperVehicle
var monsters: Array[SlimeMonster] = []
var cat: CatCompanion
var npcs: Array[Npc] = []
var sun: DirectionalLight3D
var day_night: DayNightController
var occlusion_mode: Occlusion = Occlusion.SILHOUETTE
var _motes: GPUParticles3D

## [{node: Node3D, mats: Array[Material], radius: float, height: float, alpha: float}]
var _occluders: Array[Dictionary] = []
var _placed: Array[Vector3] = []  # x, z, radius
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if get_tree().current_scene == self:
		# Run directly with F6: hand over to bootstrap so the pixel pipeline + HUD exist.
		Game.start_world = Game.WORLD_EXTERIOR
		get_tree().change_scene_to_file.call_deferred("res://scenes/bootstrap.tscn")
		return
	_rng.seed = 2024
	StylizedMaterials.clear_registry()
	_build_environment()
	_build_ground()
	_build_camp()
	_build_landmarks()
	_scatter_nature()
	_build_ground_cover()
	_spawn_actors()
	_spawn_loot()
	Game.story_changed.connect(_on_story_changed)


func ground_height(x: float, z: float) -> float:
	return terrain.height(x, z)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.environment = DayNightController.make_environment()
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "SunMoon"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 50.0
	# Larger biases: with hard (unfiltered) shadows the bumpy foliage blobs showed acne stipple.
	sun.shadow_bias = 0.2
	sun.shadow_normal_bias = 3.5
	# Hard-edged shadows: soft penumbrae turn into dithered speckle once pixelated.
	sun.shadow_blur = 0.0
	sun.light_angular_distance = 0.0
	add_child(sun)
	day_night = DayNightController.new()
	day_night.name = "DayNight"
	day_night.sun = sun
	day_night.environment = we.environment
	add_child(day_night)
	day_night.apply(Game.daylight(), Game.twilight())


func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = terrain.build_mesh(StylizedMaterials.terrain())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Pond water: semi-transparent, slightly glossy disc with a light rim.
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = TerrainField.POND_RADIUS + 0.2
	disc.bottom_radius = TerrainField.POND_RADIUS + 0.2
	disc.height = 0.02
	disc.radial_segments = 28
	disc.rings = 1
	water.mesh = disc
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.28, 0.6, 0.72, 0.8)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.08
	wm.metallic_specular = 0.8
	wm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	wm.specular_mode = BaseMaterial3D.SPECULAR_TOON
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(TerrainField.POND_CENTER.x, TerrainField.WATER_LEVEL, TerrainField.POND_CENTER.y)
	add_child(water)
	ProtoMesh.static_cylinder_collider(self, TerrainField.POND_RADIUS - 1.0, 6.0, water.position)
	var pad := ProtoMesh.mat(Color(0.3, 0.56, 0.26))
	var flower := ProtoMesh.mat(Color(0.98, 0.82, 0.88))
	for i in 9:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(1.5, TerrainField.POND_RADIUS - 1.2)
		var p := water.position + Vector3(cos(a) * r, 0.02, sin(a) * r)
		ProtoMesh.cylinder(self, _rng.randf_range(0.25, 0.45), 0.02, p, pad, Vector3.ZERO, 8)
		if i % 2 == 0:
			ProtoMesh.sphere(self, 0.09, p + Vector3(0.08, 0.06, 0), flower, Vector3.ONE, 6, 3)
	# Reeds around the shore
	var reed := StylizedMaterials.foliage(Color(0.42, 0.6, 0.28), Color(0.7, 0.78, 0.38), Color(0.22, 0.4, 0.2))
	for i in 26:
		var a := _rng.randf() * TAU
		var r := TerrainField.POND_RADIUS + _rng.randf_range(-0.6, 0.6)
		var x := TerrainField.POND_CENTER.x + cos(a) * r
		var z := TerrainField.POND_CENTER.y + sin(a) * r
		var c := ProtoMesh.cylinder(self, 0.03, _rng.randf_range(0.6, 1.0), Vector3(x, ground_height(x, z) + 0.35, z), reed, Vector3(_rng.randf_range(-10, 10), 0, _rng.randf_range(-10, 10)), 4, 0.01)
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i % 3 == 0:
			ProtoMesh.capsule(self, 0.04, 0.2, Vector3(x, ground_height(x, z) + 0.8, z), ProtoMesh.mat(Color(0.5, 0.32, 0.2)))


func _on_ground(node: Node3D, x: float, z: float) -> Node3D:
	node.position = Vector3(x, ground_height(x, z), z)
	add_child(node)
	return node


func _block(x: float, z: float, r: float) -> void:
	_placed.append(Vector3(x, z, r))


func _build_camp() -> void:
	vehicle = CamperVehicle.new()
	vehicle.name = "CamperVehicle"
	vehicle.base_yaw = deg_to_rad(CAMPER_YAW_DEG)
	vehicle.height_func = Callable(self, "ground_height")
	vehicle.walk_bounds = Rect2(TerrainField.MIN + Vector2(6, 6), TerrainField.MAX - TerrainField.MIN - Vector2(12, 12))
	var park: Dictionary = Game.field["camper"]
	var ppos: Vector3 = park.get("pos", CAMPER_POS)
	vehicle.position = Vector3(ppos.x, ground_height(ppos.x, ppos.z), ppos.z)
	vehicle.rotation.y = park.get("yaw", deg_to_rad(CAMPER_YAW_DEG))
	add_child(vehicle)
	camper = vehicle.camper
	InteractPoint.make(camper, CamperExterior.DOOR_LOCAL + Vector3(0, 0, 0.9), "E 캠핑카 실내로 들어가기",
			func(_p: Node) -> void: Game.request_world(Game.WORLD_INTERIOR), 1.4)
	InteractPoint.make(camper, Vector3(2.5, 0, 1.75), "E 운전석에 타기", func(_p: Node) -> void: enter_vehicle(), 1.4)
	_apply_camper_owned()
	_block(CAMPER_POS.x, CAMPER_POS.z, 4.2)
	_block(CAMPER_POS.x - 2.0, CAMPER_POS.z, 2.0)
	_block(CAMPER_POS.x + 2.5, CAMPER_POS.z, 2.0)
	# In front of the door (door side faces the camera): rug, chairs, table, cooler, plants
	var door := CAMP_XF * CamperExterior.DOOR_LOCAL
	var rug := _on_ground(CampProps.picnic_rug(Vector2(2.2, 1.5)), door.x + 1.6, door.z + 1.6)
	rug.rotation_degrees.y = CAMPER_YAW_DEG
	var c1 := _on_ground(CampProps.chair(Color(0.95, 0.72, 0.3)), door.x + 0.9, door.z + 1.9)
	c1.rotation_degrees.y = 200.0
	var c2 := _on_ground(CampProps.chair(Color(0.35, 0.62, 0.66)), door.x + 2.6, door.z + 1.7)
	c2.rotation_degrees.y = 150.0
	var table := _on_ground(CampProps.folding_table(), door.x + 1.75, door.z + 1.3)
	table.rotation_degrees.y = CAMPER_YAW_DEG
	ProtoMesh.static_box_collider(self, Vector3(2.6, 4, 1.0), Vector3(door.x + 1.75, 0, door.z + 1.6))
	_on_ground(CampProps.cooler(), door.x - 1.1, door.z + 0.9).rotation_degrees.y = 20.0
	_on_ground(CampProps.potted_plant(_rng, true), door.x - 0.6, door.z + 0.35)
	_on_ground(CampProps.potted_plant(_rng, false), door.x + 0.6, door.z + 0.3)
	_on_ground(CampProps.potted_plant(_rng, true), door.x - 1.6, door.z + 0.4)
	# Campfire with log seats
	var fire := _on_ground(CampProps.campfire(_rng), CAMPFIRE_POS.x, CAMPFIRE_POS.z)
	_block(fire.position.x, fire.position.z, 2.0)
	ProtoMesh.static_cylinder_collider(self, 0.7, 4.0, fire.position)
	AmbientParticles.embers(self, fire.position + Vector3(0, 0.4, 0))
	var seat1 := _on_ground(NatureProps.log_prop(1.5, 0.2), CAMPFIRE_POS.x + 1.6, CAMPFIRE_POS.z + 0.5)
	seat1.rotation_degrees.y = 70.0
	var seat2 := _on_ground(NatureProps.log_prop(1.4, 0.19), CAMPFIRE_POS.x + 0.2, CAMPFIRE_POS.z + 1.6)
	seat2.rotation_degrees.y = 8.0
	# Firewood, crates, clothesline behind/at the rear of the camper
	var rear := CAMP_XF * Vector3(-4.4, 0, 0.6)
	_on_ground(CampProps.firewood_pile(_rng), rear.x, rear.z)
	_on_ground(CampProps.crate_stack(), rear.x - 0.2, rear.z + 1.6)
	_block(rear.x, rear.z, 1.8)
	add_child(CampProps.clothesline(Vector3(-13.0, ground_height(-13, -5.2), -5.2), Vector3(-9.6, ground_height(-9.6, -6.4), -6.4)))
	# Lantern post + signpost by the path
	_on_ground(CampProps.lantern_post(), 0.6, 4.6)
	_on_ground(NatureProps.signpost(), 3.2, 4.2)
	_block(0.6, 4.6, 0.8)


func _build_landmarks() -> void:
	var hf := Callable(self, "ground_height")
	var fence_root := Node3D.new()
	fence_root.name = "Fence"
	add_child(fence_root)
	NatureProps.fence(fence_root, Vector3(-15, 0, -8), Vector3(-15, 0, 2.5), hf, _rng)
	NatureProps.fence(fence_root, Vector3(-15, 0, -8), Vector3(-6, 0, -8.6), hf, _rng)
	_block(-15, -3, 1.2)
	_block(-10.5, -8.3, 1.2)
	var shed := _on_ground(NatureProps.shed(), -19.0, 13.0)
	_register_occluder(shed, 2.6, 3.4)
	_block(-19, 13, 3.0)
	_build_trade_post()
	for cp: Dictionary in CHECKPOINTS:
		var cpos: Vector3 = cp["pos"]
		if cp["marker"]:
			_build_checkpoint_marker(cpos + Vector3(0.9, 0, -0.9))
		_block(cpos.x, cpos.z, 2.0)

	# Diorama framing: a big shade tree, a blossom tree, a pine backdrop behind the camper
	_place_tree(NatureProps.TreeKind.BROADLEAF, -12.2, 4.2, 1.45)
	_place_tree(NatureProps.TreeKind.BLOSSOM, 2.2, -3.6, 1.15)
	_place_tree(NatureProps.TreeKind.BLOSSOM, -16.5, -10.5, 1.0)
	for spec in [[-9.5, -10.0, 1.2], [-6.0, -10.8, 1.35], [-2.4, -9.6, 1.1], [-12.5, -11.5, 1.0], [0.8, -11.2, 1.25]]:
		_place_tree(NatureProps.TreeKind.PINE, spec[0], spec[1], spec[2])
	_place_tree(NatureProps.TreeKind.BIRCH, -0.8, -7.2, 1.05)
	_place_tree(NatureProps.TreeKind.BIRCH, 5.5, -6.0, 0.95)
	# Occlusion test trees just south of the path near the forest edge
	for spec in [[NatureProps.TreeKind.BROADLEAF, 22.0, -3.9, 1.25], [NatureProps.TreeKind.PINE, 26.0, -6.2, 1.2],
			[NatureProps.TreeKind.BROADLEAF, 33.0, -6.9, 1.1], [NatureProps.TreeKind.BIRCH, 18.4, 0.3, 1.1]]:
		_place_tree(spec[0], spec[1], spec[2], spec[3])
	# Bushes / rocks / small details hugging the camp edges (rich but tidy)
	for spec in [[-14.2, -6.5, 2], [-14.0, 1.2, 1], [-9.0, -8.0, 0], [-3.5, -7.8, 1], [1.2, -1.2, 2], [-13.4, 6.2, 0], [4.5, 1.0, 1]]:
		_place_bush(spec[0], spec[1], spec[2], 1.0)
	for spec in [[-1.0, -5.6, true, 1.0], [3.8, -2.0, false, 1.0], [-13.0, -1.5, true, 0.8], [-0.4, 3.0, false, 1.0]]:
		_place_rock(spec[0], spec[1], spec[2], spec[3])
	_on_ground(NatureProps.mushrooms(_rng), -11.4, 3.2)
	_on_ground(NatureProps.mushrooms(_rng), 1.6, -2.6)
	_on_ground(NatureProps.stump(_rng), 4.0, -4.6)
	var lg := _on_ground(NatureProps.log_prop(1.8, 0.22), -10.8, 6.8)
	lg.rotation_degrees.y = 25.0


func _place_tree(kind: NatureProps.TreeKind, x: float, z: float, s: float) -> void:
	var t := _on_ground(NatureProps.tree(kind, s, _rng), x, z)
	var radius := (1.5 if kind != NatureProps.TreeKind.BIRCH else 1.0) * s
	_register_occluder(t, radius, 3.2 * s)
	ProtoMesh.static_cylinder_collider(self, 0.28 * s, 8.0, t.position)
	_block(x, z, radius)


func _place_bush(x: float, z: float, kind: int, s: float) -> void:
	_on_ground(NatureProps.bush(kind, s, _rng), x, z)
	_block(x, z, 0.8 * s)


func _place_rock(x: float, z: float, big: bool, s: float) -> void:
	var r := _on_ground(NatureProps.rock(big, s, _rng), x, z)
	if big:
		ProtoMesh.static_cylinder_collider(self, 0.8 * s, 6.0, r.position)
	_block(x, z, (1.0 if big else 0.35) * s)


func _register_occluder(node: Node3D, radius: float, h: float) -> void:
	if not node.has_meta("fade_mats"):
		return
	var mats: Array[Material] = []
	mats.assign(node.get_meta("fade_mats"))
	_occluders.append({"node": node, "mats": mats, "radius": radius, "height": h, "alpha": 1.0})


func _is_free(x: float, z: float, r: float, path_clear: float) -> bool:
	if terrain.path_distance(x, z) < path_clear + r:
		return false
	if terrain.pond_distance(x, z) < 1.5 + r:
		return false
	if x < TerrainField.MIN.x + 3.0 or x > TerrainField.MAX.x - 3.0 or z < TerrainField.MIN.y + 3.0 or z > TerrainField.MAX.y - 3.0:
		return false
	for p in _placed:
		if Vector2(x, z).distance_to(Vector2(p.x, p.y)) < p.z + r:
			return false
	return true


func _random_point(center: Vector2, radius: float) -> Vector2:
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * radius
	return center + Vector2(cos(a), sin(a)) * r


func _scatter_nature() -> void:
	# Forest patch
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 2000:
		tries += 1
		var p := _random_point(TerrainField.FOREST_CENTER, TerrainField.FOREST_RADIUS)
		var roll := _rng.randf()
		var kind := NatureProps.TreeKind.PINE if roll < 0.55 else (NatureProps.TreeKind.BROADLEAF if roll < 0.85 else NatureProps.TreeKind.BIRCH)
		var s := _rng.randf_range(0.85, 1.3)
		if _is_free(p.x, p.y, 1.1 * s, 1.6):
			_place_tree(kind, p.x, p.y, s)
			placed += 1
	# Scattered meadow trees (kept away from the camp clearing)
	placed = 0
	tries = 0
	var area := Rect2(TerrainField.MIN, TerrainField.MAX - TerrainField.MIN)
	while placed < 30 and tries < 2000:
		tries += 1
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if p.distance_to(TerrainField.CAMP_CENTER) < 11.0:
			continue
		var roll := _rng.randf()
		var kind := NatureProps.TreeKind.BROADLEAF if roll < 0.5 else (NatureProps.TreeKind.BIRCH if roll < 0.75 else (NatureProps.TreeKind.PINE if roll < 0.93 else NatureProps.TreeKind.BLOSSOM))
		var s := _rng.randf_range(0.85, 1.25)
		if _is_free(p.x, p.y, 2.0 * s, 2.5):
			_place_tree(kind, p.x, p.y, s)
			placed += 1
	# Bushes, rocks, small details
	for i in 900:
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		var roll := _rng.randf()
		if p.distance_to(TerrainField.CAMP_CENTER) < 6.5:
			continue
		if roll < 0.07:
			if _is_free(p.x, p.y, 0.8, 1.6):
				_place_bush(p.x, p.y, _rng.randi() % 3, _rng.randf_range(0.8, 1.2))
		elif roll < 0.1:
			if _is_free(p.x, p.y, 0.9, 1.8):
				_place_rock(p.x, p.y, true, _rng.randf_range(0.7, 1.3))
		elif roll < 0.16:
			if _is_free(p.x, p.y, 0.3, 1.3):
				_place_rock(p.x, p.y, false, _rng.randf_range(0.7, 1.4))
		elif roll < 0.18:
			if _is_free(p.x, p.y, 0.3, 1.5):
				_on_ground(NatureProps.mushrooms(_rng), p.x, p.y)
		elif roll < 0.19:
			if _is_free(p.x, p.y, 0.6, 1.8):
				_on_ground(NatureProps.stump(_rng), p.x, p.y)
				_block(p.x, p.y, 0.5)
	for m: Array in TerrainField.MOUNDS:
		var c: Vector2 = m[0]
		if _is_free(c.x, c.y, 1.0, 1.5):
			_place_rock(c.x, c.y, true, 1.4)


func _grass_density(x: float, z: float) -> float:
	var pd := terrain.path_distance(x, z)
	if pd < 1.5:
		return 0.0
	if terrain.pond_distance(x, z) < 1.3:
		return 0.0
	var d := 1.0
	var local := CAMP_XF.affine_inverse() * Vector3(x, 0, z)
	if absf(local.x) < 4.0 and absf(local.z) < 1.5:
		return 0.0
	if Vector2(x, z).distance_to(Vector2(CAMPFIRE_POS.x, CAMPFIRE_POS.z)) < 1.4:
		return 0.0
	var door := CAMP_XF * CamperExterior.DOOR_LOCAL
	if absf(x - door.x - 1.6) < 1.4 and absf(z - door.z - 1.6) < 1.0:
		return 0.0
	d *= lerpf(0.35, 1.0, smoothstep(1.5, 3.0, pd))  # sparse at path edges
	return d


func _build_ground_cover() -> void:
	var hf := Callable(self, "ground_height")
	var area := Rect2(TerrainField.MIN + Vector2(3, 3), TerrainField.MAX - TerrainField.MIN - Vector2(6, 6))
	var forest := func(x: float, z: float) -> float: return terrain.masks(x, z).b
	GroundCover.build(self, area, 3000, hf, Callable(self, "_grass_density"), _rng, forest)
	# A little denser around the camp so the hero shot feels lush (still patchy, not a carpet)
	GroundCover.build(self, Rect2(-18, -12, 26, 22), 700, hf, Callable(self, "_grass_density"), _rng, forest)
	var edge := func(x: float, z: float) -> float:
		var pd := terrain.path_distance(x, z)
		return 0.9 if pd > 0.9 and pd < 2.0 else 0.02
	GroundCover.pebbles(self, area, 250, hf, edge, _rng)


func _spawn_actors() -> void:
	var hf := Callable(self, "ground_height")
	player = PrototypePlayer.new()
	player.name = "Player"
	player.height_func = hf
	player.walk_bounds = Rect2(TerrainField.MIN + Vector2(4, 4), TerrainField.MAX - TerrainField.MIN - Vector2(8, 8))
	add_child(player)
	var ov := Game.take_spawn_override()
	var spawn := DEFAULT_SPAWN
	var yaw := PI * 0.75
	if ov.has("pos"):
		spawn = ov["pos"]
		yaw = ov.get("yaw", 0.0)
	elif Game.previous_world == Game.WORLD_INTERIOR and Game.has_camper:
		spawn = camper.door_world_position()
		yaw = PI
	player.global_position = Vector3(spawn.x, ground_height(spawn.x, spawn.z), spawn.z)
	player.face_direction(yaw)

	for spec: Array in MONSTER_SPAWNS:
		var dead_at: float = Game.field["dead"].get(spec[0], -1.0)
		if dead_at < 0.0:
			_spawn_monster(spec)
	_spawn_cat(ov.get("kind", "") == "checkpoint" and Game.cat_joined)
	_spawn_npcs()

	camera = TopdownCamera.new()
	camera.name = "Camera"
	camera.target = player
	add_child(camera)
	_motes = AmbientParticles.motes(player)
	_motes.emitting = false
	_motes.visible = false
	add_child(AmbientParticles.leaves(player))


## Objects drawn as pre-rendered pixel sprites: [node, bake spec, name] (same name = same sheet).
func sprite_targets() -> Array:
	var g := Game.player_state.visual_gear()
	var out := [[player, PrototypePlayer.sprite_bake_spec(g), "player|" + PlayerState.gear_key(g)]]
	for m in monsters:
		if is_instance_valid(m):
			out.append([m, SlimeMonster.sprite_bake_spec(), "slime"])
	if Game.has_camper:
		out.append([camper, CamperExterior.sprite_bake_spec(CAMPER_YAW_DEG), "camper"])
	if cat:
		out.append([cat, CatCompanion.sprite_bake_spec(), "cat"])
	for n in npcs:
		out.append([n, Npc.sprite_bake_spec(n.look), "npc_" + n.look])
	return out


# ---------------------------------------------------------------- P1: monsters, loot, safety

func _spawn_monster(spec: Array) -> SlimeMonster:
	var m := SlimeMonster.new()
	m.name = "Slime_" + spec[0]
	m.monster_id = spec[0]
	m.aggressive = spec[2]
	m.height_func = Callable(self, "ground_height")
	m.world = self
	var h: Vector2 = spec[1]
	m.position = Vector3(h.x, ground_height(h.x, h.y), h.y)
	add_child(m)
	m.set_silhouette(occlusion_mode == Occlusion.SILHOUETTE)
	monsters.append(m)
	Game.sprites_dirty = true
	return m


func alert_species(source: SlimeMonster) -> void:
	for m in monsters:
		if m != source and is_instance_valid(m) and m.state != SlimeMonster.State.DEAD \
				and m.global_position.distance_to(source.global_position) < source.join_radius:
			m.engage()


func on_monster_killed(m: SlimeMonster) -> void:
	monsters.erase(m)
	Game.field["dead"][m.monster_id] = Game.total_minutes()
	var p := m.global_position
	var d := {"id": "corpse_%s_%d" % [m.monster_id, int(Game.total_minutes())], "kind": "corpse",
		"title": "%s 시체" % m.display_name, "pos": Vector3(p.x, ground_height(p.x, p.z), p.z),
		"inv": m.roll_loot(), "expires": Game.total_minutes() + CORPSE_LIFETIME_MIN}
	Game.field["loot"].append(d)
	LootContainer.create(self, d)


func _spawn_loot() -> void:
	var has_crate := false
	for d: Dictionary in Game.field["loot"]:
		if d["id"] == "camp_crate":
			has_crate = true
	if not has_crate and not Game.field.get("crate_made", false):
		var inv := Inventory.new()
		inv.add("iron_ore", 6)
		inv.add("cat_snack", 3)
		inv.add("firewood", 2)
		inv.add("flame_longsword", 1)
		inv.add("strength_ring", 1)
		inv.add("luck_necklace", 1)
		inv.add("heal_potion", 2)
		inv.add("mana_potion", 1)
		inv.add("stamina_potion", 1)
		inv.add("spellbook_minor_heal", 1)
		Game.field["loot"].append({"id": "camp_crate", "kind": "crate", "title": "보급 상자",
			"pos": Vector3(CRATE_POS.x, ground_height(CRATE_POS.x, CRATE_POS.z), CRATE_POS.z), "inv": inv, "expires": -1.0})
		Game.field["crate_made"] = true
	for d: Dictionary in Game.field["loot"].duplicate():
		LootContainer.create(self, d)


func _respawn_check() -> void:
	var now := Game.total_minutes()
	for spec: Array in MONSTER_SPAWNS:
		var dead_at: float = Game.field["dead"].get(spec[0], -1.0)
		if dead_at >= 0.0 and now - dead_at >= MONSTER_RESPAWN_MIN:
			Game.field["dead"].erase(spec[0])
			_spawn_monster(spec)


func is_safe(pos: Vector3) -> bool:
	for cp: Dictionary in CHECKPOINTS:
		var c: Vector3 = cp["pos"]
		if Vector2(pos.x - c.x, pos.z - c.z).length() < cp["radius"]:
			return true
	return false


## Nearest checkpoint by straight-line distance [미정 selection rule].
func nearest_checkpoint(pos: Vector3) -> Dictionary:
	var best: Dictionary = CHECKPOINTS[0]
	var best_d := INF
	for cp: Dictionary in CHECKPOINTS:
		var c: Vector3 = cp["pos"]
		var dd := Vector2(pos.x - c.x, pos.z - c.z).length()
		if dd < best_d:
			best_d = dd
			best = cp
	return best


## Death in the field (GDD 12.3 [확정]): goblins take part of the bag, the rest stays at the spot.
## Share taken (30 % of item units, at least 1) is a [미정] prototype value. Returns a summary.
func drop_death_loot(pos: Vector3) -> Dictionary:
	var inv := Game.player_state.inventory
	var units: Array[String] = []
	for e in inv.items:
		for i in e["count"]:
			units.append(e["id"])
	if units.is_empty():
		return {"taken": {}, "left": 0}
	units.shuffle()
	var take_n := maxi(1, ceili(units.size() * 0.3))
	var taken := {}
	for i in take_n:
		taken[units[i]] = taken.get(units[i], 0) + 1
	var bag := Inventory.new()
	for i in range(take_n, units.size()):
		bag.add(units[i], 1)
	inv.clear()
	if not bag.is_empty():
		var d := {"id": "bag_%d" % int(Game.total_minutes()), "kind": "bag", "title": "쓰러진 자리의 짐 꾸러미",
			"pos": Vector3(pos.x, ground_height(pos.x, pos.z), pos.z), "inv": bag, "expires": -1.0}
		Game.field["loot"].append(d)
	return {"taken": taken, "left": bag.unit_count()}


func _build_trade_post() -> void:
	var wood := ProtoMesh.mat(Color(0.6, 0.42, 0.26))
	var dark := ProtoMesh.mat(Color(0.38, 0.26, 0.16))
	var cloths := {"rosa": [Color(0.36, 0.62, 0.46), Color(0.95, 0.9, 0.78)], "bron": [Color(0.72, 0.28, 0.22), Color(0.5, 0.5, 0.54)]}
	for spec: Array in TRADE_STALLS:
		var p: Vector3 = spec[0]
		var shop_id: String = spec[1]
		var root := _on_ground(Node3D.new(), p.x, p.z)
		# counter + striped canopy on four posts
		ProtoMesh.box(root, Vector3(2.2, 0.9, 0.7), Vector3(0, 0.45, 0), wood)
		ProtoMesh.box(root, Vector3(2.3, 0.06, 0.8), Vector3(0, 0.92, 0), dark)
		# canopy set high and back over the keeper so the camera still sees their face beneath it
		for x in [-1.1, 1.1]:
			for z in [-1.4, 0.05]:
				ProtoMesh.box(root, Vector3(0.08, 2.85, 0.08), Vector3(x, 1.425, z), dark)
		var cols: Array = cloths[shop_id]
		for i in 6:
			ProtoMesh.box(root, Vector3(0.4, 0.04, 1.7), Vector3(-1.0 + i * 0.4, 2.87, -0.65), ProtoMesh.mat(cols[i % 2]), Vector3(-8, 0, 0))
		if shop_id == "rosa":  # goods on the counter: bottles, bread, a crate
			for i in 4:
				ProtoMesh.cylinder(root, 0.05, 0.16, Vector3(-0.8 + i * 0.18, 1.03, -0.05), ProtoMesh.mat([Color(0.85, 0.25, 0.25), Color(0.3, 0.7, 0.4), Color(0.3, 0.5, 0.9)][i % 3], 0.3), Vector3.ZERO, 6)
			ProtoMesh.sphere(root, 0.1, Vector3(0.4, 1.0, 0.0), ProtoMesh.mat(Color(0.8, 0.56, 0.28)), Vector3(1.3, 0.7, 1), 8, 4)
			ProtoMesh.box(root, Vector3(0.5, 0.4, 0.5), Vector3(1.6, 0.2, -0.3), wood)
		else:  # forge: anvil, glowing hearth, a rack of blades
			ProtoMesh.box(root, Vector3(0.5, 0.18, 0.22), Vector3(1.75, 0.62, -0.2), ProtoMesh.mat(Color(0.3, 0.31, 0.35), 0.4))
			ProtoMesh.box(root, Vector3(0.22, 0.5, 0.2), Vector3(1.75, 0.27, -0.2), dark)
			ProtoMesh.box(root, Vector3(0.9, 0.7, 0.8), Vector3(-1.7, 0.35, -0.6), ProtoMesh.mat(Color(0.45, 0.42, 0.4)))
			var glow := ProtoMesh.box(root, Vector3(0.5, 0.12, 0.5), Vector3(-1.7, 0.72, -0.6), ProtoMesh.mat(Color(1.0, 0.5, 0.2), 0.8, Color(1.0, 0.45, 0.15), 2.5))
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for i in 3:
				ProtoMesh.box(root, Vector3(0.05, 0.6, 0.02), Vector3(-0.5 + i * 0.25, 1.25, -0.02), ProtoMesh.mat(Color(0.8, 0.83, 0.87), 0.3), Vector3(0, 0, 8))
		ProtoMesh.static_box_collider(self, Vector3(2.3, 2.0, 0.8), Vector3(p.x, 0.5, p.z))
		_block(p.x, p.z, 2.4)
		# house behind the stall
		var h: Vector3 = spec[2]
		_on_ground(NatureProps.shed(), h.x, h.z)
		ProtoMesh.static_box_collider(self, Vector3(3.3, 4.0, 2.7), Vector3(h.x, 1.0, h.z))
		_block(h.x, h.z, 3.0)
		# the counter interaction for the customer side (south, toward the path)
		var ip := InteractPoint.make(self, Vector3(p.x, 0.0, p.z + 0.9), "", Callable(), 1.4)
		ip.prompt_func = func() -> String:
			var n := _npc_for(shop_id)
			if n and n.is_working():
				return "E 거래하기 — %s" % ShopDB.info(shop_id)["name"]
			return "%s — 영업 종료 (%s)" % [ShopDB.info(shop_id)["name"], ShopDB.hours_text(shop_id)]
		ip.action = func(_pl: Node) -> void:
			var n := _npc_for(shop_id)
			if n and n.is_working():
				Game.hud.open_shop(shop_id, ip)
			else:
				Game.boot.hud.toast("%s은(는) 지금 문을 닫았다 — 영업시간 %s" % [ShopDB.info(shop_id)["name"], ShopDB.hours_text(shop_id)])
	_on_ground(NatureProps.signpost(), -22.8, 6.8)


func _spawn_npcs() -> void:
	for spec: Array in TRADE_STALLS:
		var n := Npc.new()
		var p: Vector3 = spec[0]
		var h: Vector3 = spec[2]
		n.name = "Npc_" + spec[1]
		n.look = spec[1]
		n.shop_id = spec[1]
		n.counter_pos = p + Vector3(0.0, 0.0, -0.75)
		n.counter_yaw = PI  # faces the customers on the path side
		n.door_pos = h + Vector3(0.5, 0.0, 1.6)
		n.height_func = Callable(self, "ground_height")
		n.player = player
		add_child(n)
		npcs.append(n)


func _npc_for(shop_id: String) -> Npc:
	for n in npcs:
		if n.shop_id == shop_id:
			return n
	return null


func _build_checkpoint_marker(p: Vector3) -> void:
	var stone := ProtoMesh.mat(Color(0.6, 0.6, 0.58))
	var stone_d := ProtoMesh.mat(Color(0.48, 0.48, 0.5))
	var wood := ProtoMesh.mat(Color(0.5, 0.35, 0.22))
	var cloth := ProtoMesh.mat(Color(0.3, 0.7, 0.66))
	var root := _on_ground(Node3D.new(), p.x, p.z)
	ProtoMesh.sphere(root, 0.42, Vector3(0, 0.15, 0), stone_d, Vector3(1.0, 0.45, 0.9), 8, 4)
	ProtoMesh.sphere(root, 0.3, Vector3(0.03, 0.42, 0), stone, Vector3(1.0, 0.5, 0.9), 8, 4)
	ProtoMesh.sphere(root, 0.18, Vector3(-0.02, 0.62, 0.02), stone_d, Vector3(1.0, 0.6, 1.0), 6, 3)
	ProtoMesh.cylinder(root, 0.05, 1.5, Vector3(0.5, 0.75, 0.1), wood, Vector3.ZERO, 6)
	var flag := WindSway.new()
	flag.mode = WindSway.Mode.FLAG
	flag.position = Vector3(0.5, 1.42, 0.1)
	root.add_child(flag)
	ProtoMesh.box(flag, Vector3(0.42, 0.26, 0.03), Vector3(0.23, -0.12, 0), cloth)
	ProtoMesh.static_cylinder_collider(root, 0.45, 2.0, Vector3(0, 0.5, 0))


# ---------------------------------------------------------------- P1: cat & camper

func _spawn_cat(rescue: bool) -> void:
	if cat:
		cat.queue_free()
		cat = null
	cat = CatCompanion.new()
	cat.name = "BlackCat"
	cat.player = player
	cat.height_func = Callable(self, "ground_height")
	var p: Vector3
	if not Game.cat_joined:
		cat.mode = CatCompanion.Mode.ENCOUNTER
		p = CAT_ENCOUNTER_POS
	else:
		cat.mode = CatCompanion.Mode.FOLLOW
		p = player.global_position + Vector3(0.9, 0, 0.7)
	cat.position = Vector3(p.x, ground_height(p.x, p.z), p.z)
	add_child(cat)
	cat.face(player.global_position)
	if rescue:
		cat.start_rescue()
	Game.sprites_dirty = true


func _apply_camper_owned() -> void:
	var owned := Game.has_camper
	vehicle.visible = owned
	vehicle.process_mode = Node.PROCESS_MODE_INHERIT if owned else Node.PROCESS_MODE_DISABLED
	vehicle.collision_layer = 1 if owned else 0
	for ip in camper.find_children("*", "InteractPoint", false, false):
		(ip as InteractPoint).visible = owned


func _on_story_changed() -> void:
	_apply_camper_owned()
	if Game.cat_joined and cat and cat.mode == CatCompanion.Mode.ENCOUNTER:
		return  # joined by walking up to the player: keep this cat
	_spawn_cat(false)


func enter_vehicle() -> void:
	if not Game.has_camper or vehicle.driving:
		return
	player.set_driving(true)
	vehicle.driving = true
	camera.target = vehicle
	if cat:
		cat.visible = false  # rides along inside
		cat.process_mode = Node.PROCESS_MODE_DISABLED
	Game.boot.hud.toast("운전 중 — W 전진 · S 후진 · A/D 머리 좌/우 · 키를 놓으면 정지 · 멈춘 뒤 E 내리기")


func exit_vehicle() -> void:
	if not vehicle.driving:
		return
	if not vehicle.can_exit():
		Game.boot.hud.toast("먼저 차를 멈추세요 (방향키를 놓으면 섭니다)")
		return
	vehicle.driving = false
	vehicle.speed = 0.0
	var p := vehicle.exit_position()
	player.global_position = Vector3(p.x, ground_height(p.x, p.z), p.z)
	player.set_driving(false)
	camera.target = player
	camera.snap_to_target()
	_save_parking()
	if cat:
		var c := p + Vector3(0.7, 0, 0.6)
		cat.global_position = Vector3(c.x, ground_height(c.x, c.z), c.z)
		cat.visible = true
		cat.process_mode = Node.PROCESS_MODE_INHERIT
		cat.mode = CatCompanion.Mode.FOLLOW


func _save_parking() -> void:
	if vehicle:
		# Local position: also valid while the world is leaving the tree (world root = origin).
		Game.field["camper"] = {"pos": vehicle.position, "yaw": vehicle.rotation.y}


func _exit_tree() -> void:
	if vehicle and vehicle.driving:
		vehicle.driving = false
	_save_parking()


## Flat cel mode hides flowers, swaying grass tufts and pebbles: once pixelated they are
## single bright/dark texels that change every frame (wind) and read as ground sparkle.
func set_detail(v: float) -> void:
	for group in ["flowers", "ground_detail"]:
		for f in get_tree().get_nodes_in_group(group):
			if is_ancestor_of(f):
				(f as Node3D).visible = v > 0.5


## Extra atmosphere for the Dead Cells-like look (floating glowing motes).
func set_fx(_on: bool) -> void:
	# Floating motes were removed from the look (read as sparkle); campfire embers stay.
	if _motes:
		_motes.visible = false
		_motes.emitting = false


var _respawn_timer := 0.0


func _process(delta: float) -> void:
	if player == null:
		return
	_update_occluder_fade(delta)
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = 1.0
		_respawn_check()
	if vehicle.driving and Input.is_action_just_pressed("interact"):
		exit_vehicle()


func _update_occluder_fade(delta: float) -> void:
	var pp := player.global_position
	for o in _occluders:
		var n: Node3D = o["node"]
		var target := 1.0
		if occlusion_mode == Occlusion.FADE:
			# Camera looks north (-Z) and down: things south of the player (+Z) can cover it.
			var dz := n.position.z - pp.z
			var dx := absf(n.position.x - pp.x)
			if dz > -0.5 and dz < o["height"] * 0.9 + 1.0 and dx < o["radius"] + 0.4:
				target = 0.3
		var a: float = move_toward(o["alpha"], target, delta * 4.0)
		if not is_equal_approx(a, o["alpha"]):
			o["alpha"] = a
			for m: Material in o["mats"]:
				if m is ShaderMaterial:
					(m as ShaderMaterial).set_shader_parameter("fade", a)
				elif m is StandardMaterial3D:
					var sm := m as StandardMaterial3D
					sm.albedo_color.a = a
					sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if a < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED


func cycle_occlusion_mode() -> String:
	occlusion_mode = ((occlusion_mode + 1) % 3) as Occlusion
	var sil := occlusion_mode == Occlusion.SILHOUETTE
	player.set_silhouette(sil)
	for m in monsters:
		if is_instance_valid(m):
			m.set_silhouette(sil)
	return occlusion_mode_name()


func occlusion_mode_name() -> String:
	return OCCLUSION_NAMES[occlusion_mode]


func player_near_camper() -> bool:
	if not Game.has_camper:
		return false
	if vehicle.driving:
		return true
	var c := vehicle.global_position
	var d := Vector2(player.global_position.x - c.x, player.global_position.z - c.z)
	return d.length() < CAMPER_LIGHT_RANGE


## F key. Returns a message for the HUD.
func try_toggle_camper_lights() -> String:
	if not Game.has_camper:
		return "아직 캠핑카가 없습니다 (F9: 진행 단계 전환)"
	if not player_near_camper():
		return "캠핑카 근처(%.0fm 이내)에서만 F 라이트를 켤 수 있습니다" % CAMPER_LIGHT_RANGE
	Game.camper_lights_on = not Game.camper_lights_on
	return "캠핑카 라이트 %s" % ("ON" if Game.camper_lights_on else "OFF")


func context_hint() -> String:
	if vehicle.driving:
		return "운전 중 — W 전진 · S 후진 · A/D 머리 좌/우 · E 내리기(정지 시) · F 라이트"
	if player_near_camper():
		return "캠핑카 근처 — F: 외부 라이트"
	return ""


func world_title() -> String:
	return "야외 필드 (visual_lab)"
