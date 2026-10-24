class_name VisualLab
extends Node3D
## Outdoor region (P0 visual lab, extended for the P1 core loop and P3 regions). Which region is
## built comes from Game.region + data/regions/<id>.json: terrain layout, monster spawns, safe
## checkpoints, road exits to other regions. The starting meadow adds its hand-built set pieces
## (camp, trade post, ...) through region "features". Everything is generated procedurally on
## load; dead monsters, corpses and death bags persist per region in Game.field, the camper's
## parking spot (and region) in Game.camper.

## Occlusion aid (user request 2026-10-23: no more x-ray silhouette of a covered character):
## canopies / roofs that cover the hero go translucent, or nothing at all.
enum Occlusion { FADE, OFF }
const OCCLUSION_NAMES := ["수관 디더 투명화", "끔"]
const CAMPER_POS := Vector3(-6.2, 0.0, -2.8)
const CAMPER_YAW_DEG := -6.0
const CAMPER_LIGHT_RANGE := 7.5
const DEFAULT_SPAWN := Vector3(-4.3, 0.0, 1.1)
const CAMPFIRE_POS := Vector3(-2.6, 0.0, 1.9)
## Camp layout is designed around the original parking spot (the camper itself can drive away).
static var CAMP_XF := Transform3D(Basis(Vector3.UP, deg_to_rad(CAMPER_YAW_DEG)), CAMPER_POS)
## Monster spawns, checkpoints, exits: data/regions/*.json (meadow = the original layout).
const MONSTER_RESPAWN_MIN := 120.0  # game minutes [미정]
const CORPSE_LIFETIME_MIN := 60.0  # game minutes [미정]
const BOSS_CORPSE_MULT := 24.0  # bosses keep their corpse longer (GDD 8.2): a game day [미정]
## Seconds after arriving before road exits react (never bounce straight back).
const EXIT_GRACE := 1.5
const RAM_MIN_SPEED := 1.5      # m/s: slower bumps don't count
const RAM_CAMPER_DAMAGE := 15.0  # durability lost per monster hit (deliberately high, [미정])
const REFINERY_POS := Vector3(-29.6, 0.0, 2.2)  # NPC fuel refinery beside the smithy (GDD 9.3)
## Trade post west of the camp (P2-4): stalls with a merchant each, their houses behind.
## [stall position, shop id / look, house position]
const TRADE_STALLS := [
	[Vector3(-20.2, 0.0, 4.4), "rosa", Vector3(-20.6, 0.0, -0.8)],
	[Vector3(-25.6, 0.0, 4.2), "bron", Vector3(-26.4, 0.0, -1.2)],
]
const CAT_ENCOUNTER_POS := Vector3(7.5, 0.0, 3.0)
## P2-5: trade post notice board, and the overturned cart of the "lost parcels" field event
## (its trigger area lives in data/quests/quest.event.lost_parcels.json).
const BOARD_POS := Vector3(-22.9, 0.0, 3.3)
const CART_POS := Vector3(40.8, 0.0, -6.4)
const PARCELS := [["parcel_1", Vector3(38.7, 0.0, -4.2)], ["parcel_2", Vector3(42.1, 0.0, -3.9)], ["parcel_3", Vector3(39.3, 0.0, -7.6)]]
const PARCEL_QUEST := "quest.event.lost_parcels"
const CRATE_POS := Vector3(-4.6, 0.0, 2.9)
const WORKBENCH_POS := Vector3(-11.4, 0.0, 1.0)  # P3-5: camp workbench (complex crafting)  # inside the camper's turning circle: clear of its way out

var region_id := RegionDB.START
var region := {}
## Safe checkpoints of this region (GDD 2.4 [확정]: no monster fights inside); placement / radius [미정].
var checkpoints: Array[Dictionary] = []
var exits: Array[Dictionary] = []
var terrain: TerrainField
## Towns in this region (data "cities"): {"id", "name", "rect": Rect2 (x, z), "plaza": Vector3(x, z, r), "data"}
var cities: Array[Dictionary] = []
var player: PrototypePlayer
var camera: TopdownCamera
var camper: CamperExterior
var vehicle: CamperVehicle
var monsters: Array[SlimeMonster] = []
var cat: CatCompanion
var npcs: Array[Npc] = []
var sun: DirectionalLight3D
var day_night: DayNightController
var occlusion_mode: Occlusion = Occlusion.FADE
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
	region_id = Game.region
	region = RegionDB.info(region_id)
	region_id = str(region.get("region_id", RegionDB.START))
	terrain = TerrainField.new(region.get("terrain", {}))
	for cp: Dictionary in region.get("checkpoints", []):
		checkpoints.append({"id": cp["id"], "name": cp["name"], "pos": RegionDB.v3(cp["pos"]),
			"radius": float(cp["radius"]), "marker": bool(cp.get("marker", false))})
	for ex: Dictionary in region.get("exits", []):
		var e := ex.duplicate()
		e["pos"] = RegionDB.v3(ex["pos"])
		exits.append(e)
	for ct: Dictionary in region.get("cities", []):
		var cc := TerrainField._v2(ct["center"], Vector2.ZERO)
		var sz := TerrainField._v2(ct.get("size", null), Vector2(40, 36))
		var pl: Dictionary = ct.get("plaza", {})
		var pc := TerrainField._v2(pl.get("center", null), cc)
		cities.append({"id": ct["id"], "name": ct["name"], "rect": Rect2(cc - sz * 0.5, sz),
			"plaza": Vector3(pc.x, pc.y, float(pl.get("radius", 6.0))), "data": ct})
	_rng.seed = 2024 if region_id == RegionDB.START else hash(region_id)
	StylizedMaterials.clear_registry()
	var t0 := Time.get_ticks_msec()
	_build_environment()
	_build_ground()
	var t_ground := Time.get_ticks_msec()
	_build_camp()
	_build_landmarks()
	if is_dungeon():
		_build_dungeon()
		if region.has("_floor_exit"):
			_build_floor_exit(region["_floor_exit"])
	else:
		_scatter_nature()
		_build_ground_cover()
	var t_nature := Time.get_ticks_msec()
	_spawn_actors()
	_spawn_loot()
	print("[world] built %s in %d ms (terrain %d, props/nature %d, actors %d)" % [region_id, Time.get_ticks_msec() - t0,
		t_ground - t0, t_nature - t_ground, Time.get_ticks_msec() - t_nature])
	Game.discovered["region:" + region_id] = true
	Game.story_changed.connect(_on_story_changed)
	Game.camper_changed.connect(_on_camper_changed)


func is_dungeon() -> bool:
	return region.get("kind", "") in ["dungeon", "random_dungeon"]


func is_random_dungeon() -> bool:
	return region.get("kind", "") == "random_dungeon"


func has_feature(f: String) -> bool:
	return (region.get("features", []) as Array).has(f)


## The camper is in this region (and owned): only then is it built / drivable here.
func camper_here() -> bool:
	return Game.has_camper and str(Game.camper.get("region", RegionDB.START)) == region_id


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
	day_night.cave = is_dungeon()
	var amb: Array = region.get("ambient", [])
	if amb.size() >= 4:  # lit interiors (throne room) instead of the dark cave light
		day_night.cave_ambient = Color(float(amb[0]), float(amb[1]), float(amb[2]))
		day_night.cave_ambient_energy = float(amb[3])
	add_child(day_night)
	day_night.apply(Game.daylight(), Game.twilight())


func _build_ground() -> void:
	var tm := StylizedMaterials.terrain()
	_apply_ground_colors(tm, "")
	for mesh in terrain.build_chunks(tm):
		var mi := MeshInstance3D.new()
		mi.name = "Terrain"
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	for pd: Array in terrain.ponds:
		if float(pd[1]) > 0.0:
			_build_pond(pd[0], float(pd[1]))
	if not is_dungeon():
		_build_sea()


## Outdoor regions sit in a sea (the world map's continent): sandy banks down from the terrain
## edge and a ring of stylised sea water around the land rectangle, instead of an empty background.
func _build_sea() -> void:
	var skirt := MeshInstance3D.new()
	skirt.name = "Banks"
	skirt.mesh = terrain.build_skirt(TerrainField.WATER_LEVEL - 1.6)
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skirt)
	var lo := terrain.bounds_min
	var hi := terrain.bounds_max
	var land := Vector4(lo.x, lo.y, hi.x, hi.y)
	var mat := StylizedMaterials.water(true, land)
	var far := 260.0
	var inset := 0.6  # tucked under the banks so no gap shows
	var y := TerrainField.WATER_LEVEL
	# four strips around the rectangle (none inside it, so the sea never shows through a pond)
	for r: Rect2 in [Rect2(lo.x - far, lo.y - far, hi.x - lo.x + far * 2.0, far + inset),
			Rect2(lo.x - far, hi.y - inset, hi.x - lo.x + far * 2.0, far + inset),
			Rect2(lo.x - far, lo.y + inset, far + inset, hi.y - lo.y - inset * 2.0),
			Rect2(hi.x - inset, lo.y + inset, far + inset, hi.y - lo.y - inset * 2.0)]:
		var plane := PlaneMesh.new()
		plane.size = r.size
		var mi := MeshInstance3D.new()
		mi.name = "Sea"
		mi.mesh = plane
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(r.position.x + r.size.x * 0.5, y, r.position.y + r.size.y * 0.5)
		add_child(mi)


## Optional per-region ground palette (data/regions "ground"): terrain and grass tuft colours.
func _apply_ground_colors(mat: ShaderMaterial, prefix: String) -> void:
	var g: Dictionary = region.get("ground", {})
	for k: String in g:
		var a: Array = g[k]
		var c := Color(float(a[0]), float(a[1]), float(a[2]))
		if prefix == "" and not k.begins_with("tuft_"):
			mat.set_shader_parameter(k, c)
		elif prefix == "tuft":
			match k:
				"tuft_root": mat.set_shader_parameter("root_color", c)
				"tuft_tip": mat.set_shader_parameter("tip_color", c)
				"grass_dark", "grass_mid": mat.set_shader_parameter(k, c)


func _build_pond(center: Vector2, radius: float) -> void:
	# Pond / lake water: stylised water disc (depth colour, foam, reflections — water_stylized.gdshader).
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius + 0.2
	disc.bottom_radius = radius + 0.2
	disc.height = 0.02
	disc.radial_segments = clampi(roundi(radius * 4.0), 28, 96)
	disc.rings = 1
	water.mesh = disc
	water.material_override = StylizedMaterials.water()
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(center.x, TerrainField.WATER_LEVEL, center.y)
	add_child(water)
	ProtoMesh.static_cylinder_collider(self, radius - 1.0, 6.0, water.position)
	var pad := ProtoMesh.mat(Color(0.3, 0.56, 0.26))
	var flower := ProtoMesh.mat(Color(0.98, 0.82, 0.88))
	for i in roundi(9 * maxf(1.0, radius / 6.5)):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(1.5, radius - 1.2)
		var p := water.position + Vector3(cos(a) * r, 0.02, sin(a) * r)
		ProtoMesh.cylinder(self, _rng.randf_range(0.25, 0.45), 0.02, p, pad, Vector3.ZERO, 8)
		if i % 2 == 0:
			ProtoMesh.sphere(self, 0.09, p + Vector3(0.08, 0.06, 0), flower, Vector3.ONE, 6, 3)
	# Reeds around the shore
	var reed := StylizedMaterials.foliage(Color(0.42, 0.6, 0.28), Color(0.7, 0.78, 0.38), Color(0.22, 0.4, 0.2))
	for i in roundi(26 * maxf(1.0, radius / 6.5)):
		var a := _rng.randf() * TAU
		var r := radius + _rng.randf_range(-0.6, 0.6)
		var x := center.x + cos(a) * r
		var z := center.y + sin(a) * r
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
	_build_vehicle()
	if has_feature("camp"):
		_build_camp_props()


func _build_vehicle() -> void:
	vehicle = CamperVehicle.new()
	vehicle.name = "CamperVehicle"
	vehicle.base_yaw = deg_to_rad(CAMPER_YAW_DEG)
	vehicle.height_func = Callable(self, "ground_height")
	vehicle.walk_bounds = Rect2(terrain.bounds_min + Vector2(6, 6), terrain.bounds_max - terrain.bounds_min - Vector2(12, 12))
	var park: Dictionary = Game.camper
	var ppos: Vector3 = park.get("pos", CAMPER_POS)
	vehicle.position = Vector3(ppos.x, ground_height(ppos.x, ppos.z), ppos.z)
	vehicle.rotation.y = park.get("yaw", deg_to_rad(CAMPER_YAW_DEG))
	add_child(vehicle)
	camper = vehicle.camper
	InteractPoint.make(camper, CamperExterior.DOOR_LOCAL + Vector3(0, 0, 0.9), "E 캠핑카 실내로 들어가기",
			func(_p: Node) -> void: Game.request_world(Game.WORLD_INTERIOR), 1.4)
	InteractPoint.make(camper, Vector3(2.5, 0, 1.75), "E 운전석에 타기", func(_p: Node) -> void: enter_vehicle(), 1.4)
	_apply_camper_owned()


## Camp workbench (GDD 14.4: complex crafting needs one): sturdy table, vice, a few tools.
func _build_workbench(p: Vector3) -> void:
	var wood := ProtoMesh.mat(Color(0.55, 0.38, 0.22))
	var dark := ProtoMesh.mat(Color(0.34, 0.24, 0.15))
	var metal := ProtoMesh.mat(Color(0.5, 0.52, 0.56), 0.4)
	var root := _on_ground(Node3D.new(), p.x, p.z)
	root.rotation_degrees.y = 8.0
	ProtoMesh.box(root, Vector3(1.5, 0.1, 0.7), Vector3(0, 0.82, 0), wood)
	for x in [-0.65, 0.65]:
		for z in [-0.28, 0.28]:
			ProtoMesh.box(root, Vector3(0.09, 0.8, 0.09), Vector3(x, 0.4, z), dark)
	ProtoMesh.box(root, Vector3(1.3, 0.05, 0.55), Vector3(0, 0.25, 0), dark)
	ProtoMesh.box(root, Vector3(0.2, 0.14, 0.16), Vector3(-0.55, 0.94, 0.12), metal)
	ProtoMesh.box(root, Vector3(0.36, 0.04, 0.06), Vector3(0.25, 0.89, -0.1), metal, Vector3(0, 30, 0))
	ProtoMesh.cylinder(root, 0.03, 0.3, Vector3(0.5, 0.89, 0.1), dark, Vector3(0, 0, 90), 6)
	ProtoMesh.static_box_collider(self, Vector3(1.5, 2.0, 0.7), Vector3(p.x, 0.5, p.z), Vector3(0, 8, 0))
	_block(p.x, p.z, 1.4)
	InteractPoint.facility(self, p + Vector3(0, 0, 0.9), "workbench", "작업대")


func _build_camp_props() -> void:
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
	InteractPoint.facility(self, CAMPFIRE_POS + Vector3(-1.1, 0, 0.9), "cooking", "모닥불")
	_build_workbench(WORKBENCH_POS)
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
	for ct in cities:
		CityBuilder.build(self, ct["data"])
		if ct["data"].has("parking"):
			_build_parking_sign(ct["data"]["parking"]["pos"])
	for pr: Dictionary in region.get("props", []):
		_build_story_prop(pr)
	if has_feature("farm"):
		_build_farm()
	if has_feature("trade_post"):
		_build_trade_post()
		_build_refinery()
	if has_feature("lost_parcels") or has_feature("trade_post"):
		_build_quest_props()
	_build_map_drops()
	for cp: Dictionary in checkpoints:
		var cpos: Vector3 = cp["pos"]
		if cp["marker"]:
			_build_checkpoint_marker(cpos + Vector3(0.9, 0, -0.9))
		_block(cpos.x, cpos.z, 2.0)
	for ex: Dictionary in exits:
		_build_exit_marker(ex)
	_build_life_spots()
	if has_feature("camp"):
		_build_camp_framing()


func _build_farm() -> void:
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


func _build_camp_framing() -> void:
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


## Soft dark patch on the ground around a prop's base (pixel-art reference: things sit in their
## own contact shade). Transparent, no depth / shadow, roughness 1.0 so the outline pass skips it.
static var _shade_mats := {}


func _contact_shade(x: float, z: float, r: float, strength := 0.3) -> void:
	var key := snappedf(strength, 0.01)
	if not _shade_mats.has(key):
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.08, 0.1, 0.2, key)  # the alpha is the shade strength
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.roughness = 1.0
		sm.render_priority = -1
		_shade_mats[key] = sm
	var m := ProtoMesh.cylinder(self, r, 0.02, Vector3(x, ground_height(x, z) + 0.035, z), _shade_mats[key], Vector3.ZERO, 10)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _place_tree(kind: NatureProps.TreeKind, x: float, z: float, s: float) -> void:
	var t := _on_ground(NatureProps.tree(kind, s, _rng), x, z)
	_contact_shade(x, z, 1.1 * s, 0.16)
	var radius := (1.5 if kind != NatureProps.TreeKind.BIRCH else 1.0) * s
	_register_occluder(t, radius, 3.2 * s)
	ProtoMesh.static_cylinder_collider(self, 0.36 * s, 8.0, t.position)  # trunk (a little wider than drawn: no brushing through)
	_block(x, z, radius)


func _place_bush(x: float, z: float, kind: int, s: float) -> void:
	_on_ground(NatureProps.bush(kind, s, _rng), x, z)
	_contact_shade(x, z, 0.75 * s, 0.11)
	_block(x, z, 0.8 * s)


func _place_rock(x: float, z: float, big: bool, s: float) -> void:
	var r := _on_ground(NatureProps.rock(big, s, _rng), x, z)
	_contact_shade(x, z, (1.2 if big else 0.45) * s, 0.15 if big else 0.1)
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
	if x < terrain.bounds_min.x + 3.0 or x > terrain.bounds_max.x - 3.0 or z < terrain.bounds_min.y + 3.0 or z > terrain.bounds_max.y - 3.0:
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
	var sc: Dictionary = region.get("scatter", {})
	var pine_share := float(sc.get("forest_pine", 0.55))
	var broad_share := float(sc.get("forest_broadleaf", 0.3))
	# Forest patches: "forest_trees" is the total, shared by area
	var forest_area := 0.0
	for f: Array in terrain.forests:
		forest_area += float(f[1]) * float(f[1])
	var placed := 0
	var tries := 0
	for f: Array in terrain.forests:
		var want := roundi(int(sc.get("forest_trees", 46)) * float(f[1]) * float(f[1]) / maxf(forest_area, 1.0))
		placed = 0
		tries = 0
		while placed < want and tries < want * 40:
			tries += 1
			var p := _random_point(f[0], float(f[1]))
			var roll := _rng.randf()
			var kind := NatureProps.TreeKind.PINE if roll < pine_share else (NatureProps.TreeKind.BROADLEAF if roll < pine_share + broad_share else NatureProps.TreeKind.BIRCH)
			var s := _rng.randf_range(0.85, 1.3)
			if _is_free(p.x, p.y, 1.1 * s, 1.6):
				_place_tree(kind, p.x, p.y, s)
				placed += 1
	# Scattered meadow trees (kept away from the camp clearing)
	placed = 0
	tries = 0
	var area := Rect2(terrain.bounds_min, terrain.bounds_max - terrain.bounds_min)
	var mix: Array = sc.get("field_mix", [0.5, 0.25, 0.18, 0.07])
	var camp_c := terrain.camp_center if terrain.camp_center != Vector2.INF else Vector2(1e6, 1e6)
	while placed < int(sc.get("field_trees", 30)) and tries < 2000:
		tries += 1
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if p.distance_to(camp_c) < 11.0:
			continue
		var roll := _rng.randf()
		var m0 := float(mix[0])
		var m1 := m0 + float(mix[1])
		var m2 := m1 + float(mix[2])
		var kind := NatureProps.TreeKind.BROADLEAF if roll < m0 else (NatureProps.TreeKind.BIRCH if roll < m1 else (NatureProps.TreeKind.PINE if roll < m2 else NatureProps.TreeKind.BLOSSOM))
		var s := _rng.randf_range(0.85, 1.25)
		if _is_free(p.x, p.y, 2.0 * s, 2.5):
			_place_tree(kind, p.x, p.y, s)
			placed += 1
	# Bushes, rocks, small details (900 tries per the old meadow's 8 400 m²)
	for i in roundi(900.0 * area.get_area() / 8400.0):
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		var roll := _rng.randf()
		if p.distance_to(camp_c) < 6.5:
			continue
		var b0 := float(sc.get("bush", 0.07))
		var b1 := b0 + float(sc.get("big_rock", 0.03))
		var b2 := b1 + float(sc.get("small_rock", 0.06))
		if roll < b0:
			if _is_free(p.x, p.y, 0.8, 1.6):
				_place_bush(p.x, p.y, _rng.randi() % 3, _rng.randf_range(0.8, 1.2))
		elif roll < b1:
			if _is_free(p.x, p.y, 0.9, 1.8):
				_place_rock(p.x, p.y, true, _rng.randf_range(0.7, 1.3))
		elif roll < b2:
			if _is_free(p.x, p.y, 0.3, 1.3):
				_place_rock(p.x, p.y, false, _rng.randf_range(0.7, 1.4))
		elif roll < b2 + 0.02:
			if _is_free(p.x, p.y, 0.3, 1.5):
				_on_ground(NatureProps.mushrooms(_rng), p.x, p.y)
		elif roll < b2 + 0.03:
			if _is_free(p.x, p.y, 0.6, 1.8):
				_on_ground(NatureProps.stump(_rng), p.x, p.y)
				_block(p.x, p.y, 0.5)
	for m: Array in terrain.mounds:
		var c: Vector2 = m[0]
		if _is_free(c.x, c.y, 1.0, 1.5):
			_place_rock(c.x, c.y, true, 1.4)


func _grass_density(x: float, z: float) -> float:
	var pd := terrain.path_distance(x, z)
	if pd < 1.5:
		return 0.0
	if terrain.pond_distance(x, z) < 1.3:
		return 0.0
	for ct in cities:
		var pz: Vector3 = ct["plaza"]
		if Vector2(x - pz.x, z - pz.y).length() < pz.z + 0.5:
			return 0.0
		if (ct["rect"] as Rect2).grow(1.0).has_point(Vector2(x, z)):
			return 0.25 * smoothstep(1.5, 3.0, pd)  # trodden town ground
	var d := 1.0
	if not has_feature("camp"):
		return d * lerpf(0.35, 1.0, smoothstep(1.5, 3.0, pd))
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
	var area := Rect2(terrain.bounds_min + Vector2(3, 3), terrain.bounds_max - terrain.bounds_min - Vector2(6, 6))
	var forest := func(x: float, z: float) -> float: return terrain.forest_mask(x, z)
	# in tiles so the renderer can cull what is off screen (same density as before: 3000 / 7332 m²)
	var tile := 48.0
	var ty := area.position.y
	while ty < area.end.y:
		var tx := area.position.x
		while tx < area.end.x:
			var r := Rect2(tx, ty, minf(tile, area.end.x - tx), minf(tile, area.end.y - ty))
			GroundCover.build(self, r, roundi(3000 * r.get_area() / 7332.0), hf, Callable(self, "_grass_density"), _rng, forest)
			tx += tile
		ty += tile
	if has_feature("camp"):
		# A little denser around the camp so the hero shot feels lush (still patchy, not a carpet)
		GroundCover.build(self, Rect2(-18, -12, 26, 22), 700, hf, Callable(self, "_grass_density"), _rng, forest)
	var edge := func(x: float, z: float) -> float:
		var pd := terrain.path_distance(x, z)
		return 0.9 if pd > 0.9 and pd < 2.0 else 0.02
	GroundCover.pebbles(self, area, roundi(250 * area.get_area() / 7332.0), hf, edge, _rng)
	if region.has("ground"):
		for n in get_children():
			if not n.is_in_group("grass_tufts"):
				continue
			var gm: Variant = (n as GeometryInstance3D).material_override
			if gm is ShaderMaterial:
				_apply_ground_colors(gm, "tuft")


func _spawn_actors() -> void:
	var hf := Callable(self, "ground_height")
	player = PrototypePlayer.new()
	player.name = "Player"
	player.height_func = hf
	player.walk_bounds = Rect2(terrain.bounds_min + Vector2(4, 4), terrain.bounds_max - terrain.bounds_min - Vector2(8, 8))
	add_child(player)
	var ov := Game.take_spawn_override()
	var ds: Dictionary = region.get("default_spawn", {})
	var spawn := RegionDB.v3(ds["pos"]) if ds.has("pos") else DEFAULT_SPAWN
	var yaw := float(ds.get("yaw", PI * 0.75))
	if ov.has("pos"):
		spawn = ov["pos"]
		yaw = ov.get("yaw", 0.0)
	elif Game.previous_world == Game.WORLD_INTERIOR and camper_here():
		spawn = camper.door_world_position()
		yaw = PI
	player.global_position = Vector3(spawn.x, ground_height(spawn.x, spawn.z), spawn.z)
	player.face_direction(yaw)

	for spec: Dictionary in region.get("monsters", []):
		var dead_at: float = Game.field["dead"].get(spec["id"], -1.0)
		if dead_at < 0.0 and not _defeated(spec):
			_spawn_monster(spec)
	_spawn_cat(ov.get("kind", "") == "checkpoint" and Game.cat_joined)
	if has_feature("trade_post"):
		_spawn_npcs()
	if ov.get("kind", "") == "ceremony":
		_set_up_ceremony(ov)
	else:
		_spawn_region_npcs()
		if region_id == "capital" and Game.narrative.get_flag("story.wanted") and not Game.narrative.get_flag("story.escaped") \
				and camper_here():
			start_escape.call_deferred()  # loaded in the middle of the escape: run it again from the plaza

	camera = TopdownCamera.new()
	camera.name = "Camera"
	camera.target = player
	add_child(camera)
	_motes = AmbientParticles.motes(player)
	_motes.emitting = false
	_motes.visible = false
	add_child(AmbientParticles.leaves(player))
	if ov.get("kind", "") == "drive_in" and camper_here():
		enter_vehicle.call_deferred()


## Objects drawn as pre-rendered pixel sprites: [node, bake spec, name] (same name = same sheet).
## Actors that get a baked pixel sprite. The hero and the camper are NOT among them any more
## (user request 2026-10-24): they stay live 3D rigs so they move and turn smoothly — the pixel
## look comes from the low-res render, the toon materials and the outline pass, not from a sheet.
func sprite_targets() -> Array:
	var out := []
	for m in monsters:
		if is_instance_valid(m) and not m is DragonBoss:  # the dragon stays a 3D model
			var tg := m.sprite_target()
			out.append([m, tg[0], tg[1]])
	if cat:
		out.append([cat, CatCompanion.sprite_bake_spec(), "cat"])
	for n in npcs:
		out.append([n, Npc.sprite_bake_spec(n.look, n.armed), "npc_" + n.look + ("_armed" if n.armed else "")])
	return out


# ---------------------------------------------------------------- P3-4: gathering & fishing

var gather_nodes: Array[GatherNode] = []


func _build_life_spots() -> void:
	for g: Dictionary in region.get("gather", []):
		var n := GatherNode.new()
		n.node_id = str(g["id"])
		n.kind = str(g["kind"])
		var p := RegionDB.v3(g["pos"])
		n.position = Vector3(p.x, ground_height(p.x, p.z), p.z)
		add_child(n)
		gather_nodes.append(n)
		_block(p.x, p.z, 1.0)
	for fs: Dictionary in region.get("fishing_spots", []):
		_build_fishing_spot(fs)


## Small wooden pier into the water; E = automatic fishing, R = by hand (minigame).
func _build_fishing_spot(fs: Dictionary) -> void:
	var wood := ProtoMesh.mat(Color(0.56, 0.4, 0.26))
	var dark := ProtoMesh.mat(Color(0.36, 0.25, 0.16))
	var pp := RegionDB.v3(fs.get("pier", fs["pos"]))
	var stand := RegionDB.v3(fs["pos"])
	var root := Node3D.new()
	root.position = Vector3(pp.x, maxf(TerrainField.WATER_LEVEL + 0.25, ground_height(stand.x, stand.z) + 0.06), pp.z)
	add_child(root)
	var length := stand.distance_to(pp) * 2.0 + 1.0
	ProtoMesh.box(root, Vector3(1.4, 0.1, length), Vector3(0, 0, 0), wood)
	for i in 4:
		for x in [-0.6, 0.6]:
			ProtoMesh.cylinder(root, 0.07, 1.2, Vector3(x, -0.5, -length * 0.5 + 0.3 + i * (length - 0.6) / 3.0), dark, Vector3.ZERO, 6)
	_block(pp.x, pp.z, 1.6)
	var ip := InteractPoint.make(self, stand, "E 자동 낚시 · R 직접 낚시(미니게임) — 연못", Callable(), 1.3)
	ip.prompt_func = func() -> String:
		if Game.player_state.inventory.count("fishing_rod") <= 0:
			return "낚시 자리 — 낚싯대가 필요하다 (잡화점 / 캠핑카 창고)"
		return "E 자동 낚시 · R 직접 낚시(미니게임) — 낚시 Lv %d" % Game.player_state.mastery_level("fishing")
	ip.action = func(pl: Node) -> void:
		(pl as PrototypePlayer).face_direction(float(fs.get("yaw", 0.0)))
		Game.hud.start_fishing(false, ip)
	ip.alt_prompt = "R 직접 낚시"
	ip.alt_action = func(pl: Node) -> void:
		(pl as PrototypePlayer).face_direction(float(fs.get("yaw", 0.0)))
		Game.hud.start_fishing(true, ip)


# ---------------------------------------------------------------- P3-2: fixed dungeon

func _grid_world(col: int, row: int) -> Vector3:
	var w := RegionDB.grid_to_world(col, row, int(region["_cols"]), int(region["_rows"]), float(region.get("cell", 2.0)))
	return Vector3(w.x, 0.0, w.y)


## Walls (merged per row run, with a lighter cap), torches with real light, rubble and glowing
## mushrooms on the floor. Walls stay low (1.5 m) so the fixed top-down camera sees over them.
func _build_dungeon() -> void:
	var c := float(region.get("cell", 2.0))
	var h := float(region.get("wall_height", 1.5))
	var hall := str(region.get("style", "")) == "hall"
	var lair := str(region.get("style", "")) == "lair"
	# dark rock mass with a slightly lighter rim on top: the lit floor reads as the walkable space
	# (a hall: pale dressed stone with a darker coping; the dragon's lair: scorched red rock)
	var stone: Material = StylizedMaterials.stone_wall(Color(0.62, 0.6, 0.56), 0.25) if hall \
		else ProtoMesh.mat(Color(0.24, 0.13, 0.11) if lair else Color(0.22, 0.21, 0.25))
	var cap := ProtoMesh.mat(Color(0.42, 0.4, 0.38) if hall else (Color(0.36, 0.17, 0.12) if lair else Color(0.3, 0.29, 0.33)))
	var cols := int(region["_cols"])
	var rows := int(region["_rows"])
	var wall := {}
	for wc: Array in region["_walls"]:
		wall[Vector2i(int(wc[0]), int(wc[1]))] = true
	for r in rows:
		var col := 0
		while col < cols:
			if not wall.has(Vector2i(col, r)):
				col += 1
				continue
			var start := col
			while col < cols and wall.has(Vector2i(col, r)):
				col += 1
			var a := _grid_world(start, r)
			var b := _grid_world(col - 1, r)
			var center := (a + b) * 0.5
			var size := Vector3((col - start) * c, h, c)
			var y := ground_height(center.x, center.z)
			var mi := ProtoMesh.box(self, size, Vector3(center.x, y + h * 0.5, center.z), stone)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			ProtoMesh.box(self, Vector3(size.x, 0.08, size.z), Vector3(center.x, y + h + 0.04, center.z), cap)
			ProtoMesh.static_box_collider(self, Vector3(size.x, 3.0, size.z), Vector3(center.x, y + 0.5, center.z))
	var flame := ProtoMesh.mat(Color(1.0, 0.62, 0.25), 0.6, Color(1.0, 0.55, 0.2), 3.0)
	var wood := ProtoMesh.mat(Color(0.36, 0.25, 0.16))
	for t: Array in region.get("_torches", []):
		var p := Vector3(float(t[0]), 0.0, float(t[1]))
		var root := _on_ground(Node3D.new(), p.x, p.z)
		ProtoMesh.cylinder(root, 0.05, 1.3, Vector3(0, 0.65, 0), wood, Vector3.ZERO, 6)
		var f := ProtoMesh.sphere(root, 0.13, Vector3(0, 1.38, 0), flame, Vector3(1, 1.5, 1), 6, 4)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light := OmniLight3D.new()
		light.position = Vector3(0, 1.5, 0)
		light.light_color = Color(1.0, 0.68, 0.4)
		light.light_energy = 2.2
		light.omni_range = 8.0
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		root.add_child(light)
		AmbientParticles.embers(self, root.position + Vector3(0, 1.4, 0))
		_block(p.x, p.z, 1.0)
	if hall:
		_build_hall_props(c)
		return
	if lair:
		_build_lair_props(c)
		return
	# rubble + glowing mushrooms on free floor cells (fixed seed: the layout never changes)
	var glow := ProtoMesh.mat(Color(0.5, 0.95, 0.9), 0.4, Color(0.4, 0.95, 0.85), 1.6)
	var stem := ProtoMesh.mat(Color(0.75, 0.78, 0.7))
	for fc: Array in region.get("_floor", []):
		var p2 := _grid_world(int(fc[0]), int(fc[1]))
		var roll := _rng.randf()
		var jitter := Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6))
		var q := p2 + jitter
		if not _is_free(q.x, q.z, 0.4, 0.0):
			continue
		if roll < 0.08:
			_place_rock(q.x, q.z, false, _rng.randf_range(0.6, 1.1))
		elif roll < 0.14:
			var m := _on_ground(Node3D.new(), q.x, q.z)
			for i in 3:
				var o := Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2))
				ProtoMesh.cylinder(m, 0.025, 0.14, o + Vector3(0, 0.07, 0), stem, Vector3.ZERO, 5)
				var capm := ProtoMesh.sphere(m, 0.07, o + Vector3(0, 0.15, 0), glow, Vector3(1, 0.55, 1), 6, 3)
				capm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Set pieces from region data ("props"): the dragon road's burnt cart, scorch marks, bones and
## the nest mouth at the end of the pass.
func _build_story_prop(pr: Dictionary) -> void:
	var p := RegionDB.v3(pr["pos"])
	var char_mat := ProtoMesh.mat(Color(0.16, 0.13, 0.12))
	var bone := ProtoMesh.mat(Color(0.9, 0.86, 0.76))
	match str(pr.get("kind", "")):
		"scorch":
			# a few overlapping soot blotches, each on the ground under it (one flat disc cuts into slopes)
			var r := float(pr.get("radius", 2.5))
			var soot := ProtoMesh.mat(Color(0.14, 0.11, 0.1))
			for i in 6:
				var o := Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5)) * r
				var br := r * _rng.randf_range(0.35, 0.6)
				var x := p.x + o.x
				var z := p.z + o.y
				var d := ProtoMesh.cylinder(self, br, 0.03, Vector3(x, ground_height(x, z) + 0.05 + i * 0.004, z), soot, Vector3.ZERO, 9)
				d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var e := ProtoMesh.cylinder(self, r * 0.18, 0.03, Vector3(p.x, ground_height(p.x, p.z) + 0.09, p.z), ProtoMesh.mat(Color(0.35, 0.14, 0.07), 0.9, Color(0.8, 0.25, 0.08), 0.5), Vector3.ZERO, 8)
			e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"burnt_cart":
			var root := _on_ground(Node3D.new(), p.x, p.z)
			root.rotation.y = float(pr.get("yaw", 0.0))
			ProtoMesh.box(root, Vector3(2.4, 0.5, 1.4), Vector3(0, 0.6, 0), char_mat, Vector3(0, 0, 9))
			ProtoMesh.box(root, Vector3(0.12, 0.7, 1.4), Vector3(-1.1, 1.0, 0), char_mat, Vector3(0, 0, 20))
			for spec in [[-0.8, 0.75, 0.0], [0.8, 0.75, 0.0], [0.9, -0.75, 70.0]]:
				ProtoMesh.cylinder(root, 0.42, 0.12, Vector3(spec[0], 0.42 if spec[2] == 0.0 else 0.1, spec[1]), ProtoMesh.mat(Color(0.22, 0.17, 0.14)), Vector3(90 - spec[2], 0, 0), 10)
			ProtoMesh.static_box_collider(root, Vector3(2.4, 1.2, 1.4), Vector3(0, 0.6, 0))
			AmbientParticles.embers(self, root.position + Vector3(0, 0.8, 0))
			_block(p.x, p.z, 2.0)
		"bones":
			var root := _on_ground(Node3D.new(), p.x, p.z)
			for i in 4:
				ProtoMesh.capsule(root, 0.07, 0.7, Vector3(_rng.randf_range(-0.6, 0.6), 0.08, _rng.randf_range(-0.6, 0.6)), bone, Vector3(90, _rng.randf() * 180.0, 0))
			ProtoMesh.sphere(root, 0.22, Vector3(0.2, 0.18, 0.1), bone, Vector3(1.2, 0.9, 1.0), 8, 5)
		"nest_mouth":
			# the mouth of the nest seen from above: a black pit glowing red deep inside, ringed by
			# scorched boulders on its far side, embers drifting up out of it
			var root := _on_ground(Node3D.new(), p.x, p.z)
			for spec in [[-5.2, 0.6, 2.4], [5.2, 0.8, 2.6], [-3.6, -2.6, 2.8], [3.8, -2.4, 2.7], [0.0, -4.2, 3.2], [-6.4, -2.2, 2.0], [6.6, -1.8, 2.0]]:
				var rk := NatureProps.rock(true, spec[2], _rng)
				rk.position = Vector3(spec[0], 0, spec[1])
				root.add_child(rk)
				ProtoMesh.static_cylinder_collider(root, spec[2] * 0.7, 4.0, Vector3(spec[0], 1.5, spec[1]))
			var rim := ProtoMesh.cylinder(root, 3.4, 0.05, Vector3(0, 0.05, -0.4), ProtoMesh.mat(Color(0.12, 0.09, 0.08)), Vector3.ZERO, 14)
			rim.scale = Vector3(1.0, 1.0, 0.7)
			var pit := ProtoMesh.cylinder(root, 2.6, 0.05, Vector3(0, 0.08, -0.5), ProtoMesh.mat(Color(0.02, 0.015, 0.015)), Vector3.ZERO, 14)
			pit.scale = Vector3(1.0, 1.0, 0.65)
			var deep := ProtoMesh.cylinder(root, 1.2, 0.05, Vector3(0, 0.11, -0.7), ProtoMesh.mat(Color(0.25, 0.05, 0.02), 0.9, Color(0.85, 0.2, 0.05), 0.9), Vector3.ZERO, 12)
			deep.scale = Vector3(1.0, 1.0, 0.6)
			for m: MeshInstance3D in [rim, pit, deep]:
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var glow := OmniLight3D.new()
			glow.position = Vector3(0, 0.8, -0.6)
			glow.light_color = Color(1.0, 0.4, 0.18)
			glow.light_energy = 2.2
			glow.omni_range = 8.0
			root.add_child(glow)
			for x in [-1.0, 0.0, 1.0]:
				AmbientParticles.embers(self, root.position + Vector3(x, 0.4, -0.6))
			ProtoMesh.static_cylinder_collider(root, 2.4, 3.0, Vector3(0, 1.0, -0.6))
			_block(p.x, p.z, 7.0)
			var ip := InteractPoint.make(self, p + Vector3(0, 0, 1.6), "E 구덩이 아래로 내려간다 — 드래곤의 둥지", Callable(), 2.0)
			ip.action = func(_pl: Node) -> void:
				Game.boot.travel(str(pr.get("to_region", "dragon_nest")), str(pr.get("to_entry", "entrance")), false)


## Throne room furnishing from grid letters: 'c' red carpet, 'P' pillars, 'Q' the throne on a dais,
## 'B' banners on the wall behind it, 'L' standing braziers (extra light).
func _build_hall_props(c: float) -> void:
	var marks: Dictionary = region.get("_marks", {})
	var carpet := ProtoMesh.mat(Color(0.62, 0.14, 0.16))
	var trim := ProtoMesh.mat(Color(0.86, 0.68, 0.3), 0.4)
	for p: Array in marks.get("c", []):
		var m := ProtoMesh.box(self, Vector3(c, 0.04, c), Vector3(float(p[0]), ground_height(float(p[0]), float(p[1])) + 0.02, float(p[1])), carpet)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pillar := ProtoMesh.mat(Color(0.74, 0.72, 0.68))
	for p: Array in marks.get("P", []):
		var root := _on_ground(Node3D.new(), float(p[0]), float(p[1]))
		ProtoMesh.cylinder(root, 0.45, 3.2, Vector3(0, 1.6, 0), pillar, Vector3.ZERO, 10)
		ProtoMesh.box(root, Vector3(1.1, 0.25, 1.1), Vector3(0, 0.12, 0), trim)
		ProtoMesh.box(root, Vector3(1.1, 0.25, 1.1), Vector3(0, 3.25, 0), trim)
		ProtoMesh.static_cylinder_collider(root, 0.5, 3.0, Vector3(0, 1.5, 0))
		_block(float(p[0]), float(p[1]), 1.0)
	var gold := ProtoMesh.mat(Color(0.95, 0.76, 0.26), 0.35)
	var velvet := ProtoMesh.mat(Color(0.5, 0.12, 0.2))
	for p: Array in marks.get("Q", []):
		var root := _on_ground(Node3D.new(), float(p[0]), float(p[1]))
		ProtoMesh.box(root, Vector3(4.0, 0.3, 3.0), Vector3(0, 0.15, -0.3), ProtoMesh.mat(Color(0.7, 0.68, 0.64)))  # dais
		ProtoMesh.box(root, Vector3(1.3, 0.5, 1.0), Vector3(0, 0.55, -0.8), gold)                   # seat
		ProtoMesh.box(root, Vector3(1.3, 1.9, 0.25), Vector3(0, 1.4, -1.25), gold)                  # back
		ProtoMesh.box(root, Vector3(0.9, 1.4, 0.1), Vector3(0, 1.4, -1.1), velvet)
		ProtoMesh.sphere(root, 0.16, Vector3(0, 2.45, -1.25), gold, Vector3.ONE, 8, 5)
		_block(float(p[0]), float(p[1]), 2.0)
	var banner := ProtoMesh.mat(Color(0.7, 0.16, 0.2))
	for p: Array in marks.get("B", []):
		var root := _on_ground(Node3D.new(), float(p[0]), float(p[1]))
		ProtoMesh.box(root, Vector3(1.2, 2.6, 0.08), Vector3(0, 2.0, 0.6), banner)
		ProtoMesh.box(root, Vector3(0.5, 0.5, 0.1), Vector3(0, 2.4, 0.66), gold, Vector3(0, 0, 45))
	var flame := ProtoMesh.mat(Color(1.0, 0.7, 0.3), 0.6, Color(1.0, 0.6, 0.25), 3.0)
	for p: Array in marks.get("L", []):
		var root := _on_ground(Node3D.new(), float(p[0]), float(p[1]))
		ProtoMesh.cylinder(root, 0.08, 1.1, Vector3(0, 0.55, 0), gold, Vector3.ZERO, 6)
		ProtoMesh.cylinder(root, 0.35, 0.25, Vector3(0, 1.15, 0), gold, Vector3.ZERO, 8, 0.45)
		var f := ProtoMesh.sphere(root, 0.22, Vector3(0, 1.4, 0), flame, Vector3(1, 1.4, 1), 6, 4)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light := OmniLight3D.new()
		light.position = Vector3(0, 1.8, 0)
		light.light_color = Color(1.0, 0.78, 0.5)
		light.light_energy = 2.6
		light.omni_range = 11.0
		root.add_child(light)
		ProtoMesh.static_cylinder_collider(root, 0.4, 2.0, Vector3(0, 1, 0))
		_block(float(p[0]), float(p[1]), 0.8)


## Dragon's lair from grid letters: 'v' glowing lava cracks (blocked), 'g' heaps of gold around the
## hoard, 'P' rock pillars, 'b' bones; once the dragon is dead its body lies where it slept ('D').
func _build_lair_props(c: float) -> void:
	var marks: Dictionary = region.get("_marks", {})
	var crust := ProtoMesh.mat(Color(0.14, 0.08, 0.07))
	var lava := ProtoMesh.mat(Color(0.95, 0.38, 0.1), 0.6, Color(1.0, 0.36, 0.08), 1.1)
	var n := 0
	for p: Array in marks.get("v", []):
		var x := float(p[0])
		var z := float(p[1])
		var y := ground_height(x, z)
		var rim := ProtoMesh.box(self, Vector3(c * 1.05, 0.14, c * 1.05), Vector3(x, y + 0.05, z), crust)
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pool := ProtoMesh.box(self, Vector3(c * 0.8, 0.06, c * 0.8), Vector3(x, y + 0.12, z), lava)
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in 2:
			var cr := ProtoMesh.box(self, Vector3(_rng.randf_range(0.3, 0.7), 0.08, _rng.randf_range(0.2, 0.5)),
				Vector3(x + _rng.randf_range(-0.5, 0.5), y + 0.15, z + _rng.randf_range(-0.5, 0.5)), crust, Vector3(0, _rng.randf() * 180.0, 0))
			cr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if n % 2 == 0:
			var light := OmniLight3D.new()
			light.position = Vector3(x, y + 1.2, z)
			light.light_color = Color(1.0, 0.45, 0.18)
			light.light_energy = 2.4
			light.omni_range = 7.0
			add_child(light)
			AmbientParticles.embers(self, Vector3(x, y + 0.3, z))
		n += 1
		ProtoMesh.static_box_collider(self, Vector3(c, 2.0, c), Vector3(x, y + 1.0, z))
		_block(x, z, c * 0.7)
	var gold := ProtoMesh.mat(Color(0.96, 0.76, 0.26), 0.35, Color(0.6, 0.42, 0.1), 0.3)
	var gem := ProtoMesh.mat(Color(0.3, 0.8, 0.9), 0.3, Color(0.2, 0.7, 0.9), 0.8)
	for p: Array in marks.get("g", []):
		var root := _on_ground(Node3D.new(), float(p[0]), float(p[1]))
		ProtoMesh.sphere(root, 0.9, Vector3(0, 0.05, 0), gold, Vector3(1.1, 0.4, 1.0), 10, 5)
		for i in 5:
			ProtoMesh.cylinder(root, 0.12, 0.03, Vector3(_rng.randf_range(-0.9, 0.9), 0.04, _rng.randf_range(-0.9, 0.9)), gold, Vector3(_rng.randf_range(-30, 30), 0, 0), 8)
		if _rng.randf() < 0.5:
			ProtoMesh.box(root, Vector3(0.18, 0.18, 0.18), Vector3(_rng.randf_range(-0.4, 0.4), 0.38, _rng.randf_range(-0.3, 0.3)), gem, Vector3(45, 30, 0))
	for p: Array in marks.get("P", []):
		var rk := _on_ground(NatureProps.rock(true, 2.2, _rng), float(p[0]), float(p[1]))
		rk.scale = Vector3(1.6, 2.6, 1.6)
		ProtoMesh.static_cylinder_collider(self, 1.1, 4.0, rk.position + Vector3(0, 2, 0))
		_block(float(p[0]), float(p[1]), 1.6)
	var bone := ProtoMesh.mat(Color(0.9, 0.86, 0.76))
	for p: Array in marks.get("b", []):
		var root := _on_ground(Node3D.new(), float(p[0]), float(p[1]))
		for i in 4:
			ProtoMesh.capsule(root, 0.07, 0.7, Vector3(_rng.randf_range(-0.6, 0.6), 0.08, _rng.randf_range(-0.6, 0.6)), bone, Vector3(90, _rng.randf() * 180.0, 0))
		ProtoMesh.sphere(root, 0.22, Vector3(0.2, 0.18, 0.1), bone, Vector3(1.2, 0.9, 1.0), 8, 5)
	var rm: Dictionary = Game.field.get("remains", {})  # where the dragon fell (DragonBoss._die)
	if not rm.is_empty():
		var remains := DragonRig.new()
		remains.dead = 1.0
		_on_ground(remains, float(rm["pos"][0]), float(rm["pos"][1]))
		remains.rotation.y = float(rm.get("yaw", 0.0))
	if Game.narrative.get_flag("story.dragon_left"):
		_build_portal()


## Story NPCs from region data ("npcs": [{"look", "pos", "yaw", "speaker"}]): they stay put and
## open their speaker's talk dialogue (data/speakers.json) with E.
func _spawn_region_npcs() -> void:
	for spec: Dictionary in region.get("npcs", []):
		var n := Npc.new()
		n.name = "Npc_" + str(spec["look"])
		n.look = str(spec["look"])
		n.shop_id = ""
		n.counter_pos = RegionDB.v3(spec["pos"])
		n.counter_yaw = float(spec.get("yaw", 0.0))
		n.door_pos = n.counter_pos
		n.height_func = Callable(self, "ground_height")
		n.player = player
		n.armed = Game.npcs_hostile()
		add_child(n)
		npcs.append(n)
		if _arm_npc(n):
			continue  # no talking or trading with someone who is swinging a club at you
		var sp := str(spec.get("speaker", spec["look"]))
		var talk_at := n.counter_pos + Vector3(-sin(n.counter_yaw), 0, -cos(n.counter_yaw)) * float(spec.get("talk_distance", 1.6))
		var vendor := str(spec.get("upgrades", ""))
		if vendor != "":  # camper upgrade vendor (GDD 9.2: upgrades come from NPCs for gold / quests)
			var vip := InteractPoint.make(self, talk_at, "E 캠핑카 개조 — %s" % CamperUpgrades.vendor_name(vendor), Callable(), 1.8)
			vip.action = func(_pl: Node) -> void: Game.hud.open_upgrades(vendor, vip)
			continue
		var ip := InteractPoint.make(self, talk_at, "E 대화 — %s" % DialogueData.speaker_name(sp), Callable(), 1.8)
		ip.action = func(_pl: Node) -> void: Game.hud.start_dialogue(DialogueData.talk_dialogue(sp))


# ---------------------------------------------------------------- chapter 1 ending: wish ceremony + escape

var escape: EscapeSequence


## Chapter 1's hunt (Game.npcs_hostile): an NPC just added to the world takes up arms. True if so.
func _arm_npc(n: Npc) -> bool:
	if not Game.npcs_hostile():
		return false
	n.vehicle = vehicle
	n.set_hostile(true)
	return true


## Where the dragon slept, a portal stands once it has flown off (user story: the way to the other
## continent, chapter 2). It takes the hero in only after the flight from the capital.
func _build_portal() -> void:
	var at := Vector3(0, 0, -9)
	for spec: Dictionary in region.get("monsters", []):
		if str(spec.get("kind", "")) == "dragon":
			at = RegionDB.v3(spec["pos"])
	var open := Game.narrative.get_flag("story.escaped")
	var root := _on_ground(Node3D.new(), at.x, at.z)
	root.name = "Portal"
	var rim_col := Color(0.6, 0.4, 1.0) if open else Color(0.36, 0.3, 0.5)
	# soft glow: the lair's grading blooms hard, a strong emission turned the disc into a white blob
	var rim := ProtoMesh.mat(rim_col, 0.3, rim_col, 1.5 if open else 0.4)
	var core := ProtoMesh.mat(Color(0.7, 0.55, 0.95), 0.2, Color(0.55, 0.4, 0.9), 1.1 if open else 0.3)
	var stone := ProtoMesh.mat(Color(0.2, 0.12, 0.12))
	var disc := ProtoMesh.cylinder(root, 1.45, 0.08, Vector3(0, 1.75, 0), core, Vector3(90, 0, 0), 24)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := ProtoMesh.cylinder(root, 1.7, 0.06, Vector3(0, 1.75, 0.08), rim, Vector3(90, 0, 0), 24)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in [-1.0, 1.0]:  # scorched stone posts either side, where the dragon's claws rested
		ProtoMesh.box(root, Vector3(0.5, 2.6, 0.5), Vector3(2.1 * s, 1.3, 0.2), stone)
		ProtoMesh.static_box_collider(root, Vector3(0.5, 3.0, 0.5), Vector3(2.1 * s, 1.3, 0.2))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.8, -0.6)
	light.light_color = Color(0.7, 0.5, 1.0)
	light.light_energy = 3.0 if open else 0.8
	light.omni_range = 9.0
	root.add_child(light)
	AmbientParticles.embers(root, Vector3(0, 0.4, 0))
	var ip := InteractPoint.make(self, root.position + Vector3(0, 0, 1.9),
		"E 포탈로 들어가기 — 바다 건너 다른 대륙으로" if open else "드래곤이 떠난 자리의 포탈 — 아직 잠잠하다", Callable(), 2.2)
	ip.action = func(_pl: Node) -> void:
		if open:
			Game.boot.enter_portal()
		else:
			Game.boot.hud.toast("포탈은 아직 잠잠하다 — 아직 이 섬에서 할 일이 남았다")
	_block(at.x, at.z, 2.5)


## A story NPC that just stands there (wish ceremony cast, escape guards); not a shop, no dialogue.
func spawn_story_npc(look: String, pos: Vector3, yaw: float) -> Npc:
	var n := Npc.new()
	n.name = "Story_" + look
	n.look = look
	n.shop_id = ""
	n.counter_pos = Vector3(pos.x, ground_height(pos.x, pos.z), pos.z)
	n.counter_yaw = yaw
	n.door_pos = n.counter_pos
	n.height_func = Callable(self, "ground_height")
	n.player = player
	add_child(n)
	npcs.append(n)
	Game.sprites_dirty = true
	return n


## The plaza set for the wish (data/story.json "wish_ceremony"): king, court wizard, guards; the
## camper already belongs to the hero but stays hidden in the sky until cutscene step camper_drop.
func _set_up_ceremony(ov: Dictionary) -> void:
	for a: Dictionary in ov.get("actors", []):
		spawn_story_npc(str(a["look"]), RegionDB.v3(a["pos"]), float(a.get("yaw", 0.0)))
	if vehicle:
		vehicle.visible = false
		vehicle.collision_layer = 0


## Cutscene step camper_drop: the wished-for camper falls out of the sky onto `at` (crushing
## whoever stands there), with dust, a rolling crown and a shaking view.
func drop_camper(at: Vector3, seconds: float, crushed: Node3D = null) -> void:
	var ground := ground_height(at.x, at.z)
	var w: Dictionary = CutsceneData.story().get("camper_wish", {})
	vehicle.process_mode = Node.PROCESS_MODE_INHERIT
	vehicle.rotation.y = float(w.get("yaw", -PI * 0.5))
	vehicle.call("_sync_visual")
	vehicle.global_position = Vector3(at.x, ground + (26.0 if seconds > 0.0 else 0.0), at.z)
	vehicle.visible = true
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := clampf(t / seconds, 0.0, 1.0)
		vehicle.global_position.y = ground + 26.0 * (1.0 - k * k)
	vehicle.global_position = Vector3(at.x, ground, at.z)
	vehicle.collision_layer = 1
	if crushed and is_instance_valid(crushed):
		crushed.visible = false
		if crushed is Npc:
			npcs.erase(crushed)
			crushed.queue_free()
	camera.shake(0.7, 3.0)
	var dust := CPUParticles3D.new()
	dust.one_shot = true
	dust.amount = 46
	dust.lifetime = 1.4
	dust.explosiveness = 1.0
	dust.direction = Vector3(0, 0.25, 0)
	dust.spread = 180.0
	dust.flatness = 0.7
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 6.5
	dust.damping_min = 3.0
	dust.damping_max = 5.0
	dust.gravity = Vector3(0, 0.6, 0)
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 2.2
	var puff := SphereMesh.new()
	puff.radius = 0.28
	puff.height = 0.56
	puff.radial_segments = 6
	puff.rings = 3
	puff.material = ProtoMesh.mat(Color(0.82, 0.76, 0.66))
	dust.mesh = puff
	dust.position = Vector3(at.x, ground + 0.3, at.z)
	add_child(dust)
	dust.emitting = true
	get_tree().create_timer(2.0).timeout.connect(dust.queue_free)
	# the crown rolls out from under the camper
	var crown := Node3D.new()
	var gold := ProtoMesh.mat(Color(0.95, 0.76, 0.26), 0.4)
	ProtoMesh.cylinder(crown, 0.2, 0.1, Vector3(0, 0.05, 0), gold, Vector3.ZERO, 10)
	for i in 5:
		var a := TAU * i / 5.0
		ProtoMesh.cylinder(crown, 0.045, 0.1, Vector3(sin(a) * 0.17, 0.14, cos(a) * 0.17), gold, Vector3.ZERO, 4, 0.0)
	add_child(crown)
	var from := Vector3(at.x + 1.0, ground, at.z + 2.6)
	var to := Vector3(at.x + 2.4, ground_height(at.x + 2.4, at.z + 4.4), at.z + 4.4)
	crown.global_position = from
	crown.rotation.z = PI * 0.5
	var tw := create_tween().set_parallel()
	tw.tween_property(crown, "global_position", to, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(crown, "rotation:y", TAU * 1.5, 0.9)
	tw.chain().tween_property(crown, "rotation:z", 0.0, 0.25)


## The chase to the south gate (EscapeSequence). Once per world.
func start_escape() -> void:
	if escape or not camper_here():
		return
	escape = EscapeSequence.new()
	escape.name = "Escape"
	escape.world = self
	add_child(escape)
	escape.begin()


## Highland cave mouth: two big rocks around a dark opening, a lantern-less warning sign.
func _build_cave_mouth(c: Vector3) -> void:
	var dark := ProtoMesh.mat(Color(0.03, 0.03, 0.04))
	for spec in [[-2.3, 0.2, 1.5], [2.3, 0.0, 1.6], [0.0, -1.6, 1.9]]:
		var r := _on_ground(NatureProps.rock(true, spec[2], _rng), c.x + spec[0], c.z + spec[1])
		ProtoMesh.static_cylinder_collider(self, 0.8 * spec[2], 6.0, r.position)
	var hole := ProtoMesh.sphere(self, 1.25, Vector3(c.x, ground_height(c.x, c.z) + 0.15, c.z - 0.6), dark, Vector3(1.2, 0.85, 0.5), 10, 6)
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_on_ground(NatureProps.signpost(), c.x + 3.0, c.z + 2.6)
	_block(c.x, c.z, 4.0)


## Random dungeon gate (meadow): a ring of standing stones around a violet glow. E asks first
## (GDD 12.2: warn that the map keeps changing before entering).
func _build_rift_gate(ex: Dictionary) -> void:
	var c: Vector3 = ex["pos"]
	var stone := ProtoMesh.mat(Color(0.42, 0.4, 0.46))
	var glow := ProtoMesh.mat(Color(0.62, 0.45, 0.95), 0.4, Color(0.6, 0.4, 1.0), 1.5)
	var root := _on_ground(Node3D.new(), c.x, c.z)
	for i in 6:
		var a := TAU * i / 6.0
		ProtoMesh.box(root, Vector3(0.38, 1.4 + 0.25 * (i % 2), 0.3), Vector3(cos(a) * 1.5, 0.7, sin(a) * 1.5), stone, Vector3(0, -rad_to_deg(a), 0))
	var disc := ProtoMesh.cylinder(root, 1.0, 0.05, Vector3(0, 0.05, 0), glow, Vector3.ZERO, 16)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.0, 0)
	light.light_color = Color(0.7, 0.5, 1.0)
	light.light_energy = 1.4
	light.omni_range = 5.0
	root.add_child(light)
	ProtoMesh.static_cylinder_collider(self, 0.6, 2.0, root.position)
	_block(c.x, c.z, 2.6)
	var ip := InteractPoint.make(self, c + Vector3(0, 0, 1.9), "E %s — 들어가기 전에 안내" % ex.get("name", "미궁 입구"), Callable(), 1.6)
	ip.action = func(_pl: Node) -> void: Game.hud.open_rift_gate(ex, ip)


## Random dungeon floor exit: a stair hole with a cold light; E = escape or go deeper.
func _build_floor_exit(p: Array) -> void:
	var c := Vector3(float(p[0]), 0.0, float(p[1]))
	var ring := ProtoMesh.mat(Color(0.5, 0.48, 0.52))
	var hole := ProtoMesh.mat(Color(0.02, 0.02, 0.03))
	var root := _on_ground(Node3D.new(), c.x, c.z)
	ProtoMesh.cylinder(root, 0.95, 0.12, Vector3(0, 0.06, 0), ring, Vector3.ZERO, 14)
	ProtoMesh.cylinder(root, 0.72, 0.13, Vector3(0, 0.07, 0), hole, Vector3.ZERO, 14)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.8, 0)
	light.light_color = Color(0.65, 0.8, 1.0)
	light.light_energy = 1.3
	light.omni_range = 5.0
	root.add_child(light)
	var ip := InteractPoint.make(self, c, "E 출구 — 탈출하거나 아래층으로", Callable(), 1.6)
	ip.action = func(_pl: Node) -> void: Game.hud.open_floor_exit(ip)


## Way out of the dungeon: pale light falling on a stone slab.
func _build_dungeon_exit(c: Vector3) -> void:
	var slab := ProtoMesh.mat(Color(0.42, 0.43, 0.45), 0.8, Color(0.5, 0.6, 0.75), 0.25)
	ProtoMesh.box(self, Vector3(1.6, 0.08, 1.6), Vector3(c.x, ground_height(c.x, c.z) + 0.04, c.z), slab)
	var light := OmniLight3D.new()
	light.position = Vector3(c.x, ground_height(c.x, c.z) + 2.2, c.z)
	light.light_color = Color(0.75, 0.85, 1.0)
	light.light_energy = 1.1
	light.omni_range = 5.0
	add_child(light)


# ---------------------------------------------------------------- P1: monsters, loot, safety

func _spawn_monster(spec: Dictionary) -> SlimeMonster:
	var cls := str(MonsterDB.info(str(spec.get("kind", ""))).get("class", ""))
	var m: SlimeMonster = DragonBoss.new() if cls == "dragon" else (BeastMonster.new() if cls == "beast" else SlimeMonster.new())
	m.name = {"dragon": "Dragon_", "beast": "Beast_"}.get(cls, "Slime_") + str(spec["id"])
	m.monster_id = str(spec["id"])
	m.kind = str(spec.get("kind", "meadow_slime"))
	m.set_meta("once", bool(spec.get("once", false)))
	m.height_func = Callable(self, "ground_height")
	m.world = self
	var h := RegionDB.v3(spec["pos"])
	m.position = Vector3(h.x, ground_height(h.x, h.z), h.z)
	add_child(m)
	monsters.append(m)
	Game.sprites_dirty = true
	return m


## A monster in a fight calls the same species nearby (GDD 7.2); each one's AI graph decides
## whether it answers (선공 graphs do, 비선공 ones don't).
func alert_species(source: SlimeMonster) -> void:
	for m in monsters:
		if m != source and is_instance_valid(m) and m.state != SlimeMonster.State.DEAD and m.kind == source.kind \
				and m.global_position.distance_to(source.global_position) < source.join_radius:
			m.hear_call(source)


## GDD 7.4 [확정]: bosses / special monsters can appear only once.
func _defeated(spec: Dictionary) -> bool:
	return bool(spec.get("once", false)) and Game.field.get("defeated", {}).has(spec["id"])


func on_monster_killed(m: SlimeMonster) -> void:
	monsters.erase(m)
	if m.get_meta("once", false):
		var dfd: Dictionary = Game.field.get("defeated", {})
		dfd[m.monster_id] = Game.total_minutes()
		Game.field["defeated"] = dfd
		Game.boot.hud.toast("%s을(를) 쓰러뜨렸다 — 다시 나타나지 않는다" % m.display_name)
	Game.field["dead"][m.monster_id] = Game.total_minutes()
	var p := m.global_position
	var d := {"id": "corpse_%s_%d" % [m.monster_id, int(Game.total_minutes())], "kind": "corpse",
		"title": "%s 시체" % m.display_name, "pos": Vector3(p.x, ground_height(p.x, p.z), p.z),
		"inv": m.roll_loot(), "expires": Game.total_minutes() + CORPSE_LIFETIME_MIN * (BOSS_CORPSE_MULT if m.get_meta("once", false) else 1)}
	Game.field["loot"].append(d)
	LootContainer.create(self, d)


func _spawn_loot() -> void:
	var has_crate := false
	for d: Dictionary in Game.field["loot"]:
		if d["id"] == "camp_crate":
			has_crate = true
	if has_feature("camp") and not has_crate and not Game.field.get("crate_made", false):
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
	if is_dungeon() and not Game.field.get("chests_made", false):
		var defs: Array = region.get("chests", [])
		var spots: Array = region.get("_chests", [])
		for i in mini(defs.size(), spots.size()):
			var inv2 := Inventory.new()
			var items: Dictionary = defs[i].get("items", {})
			for id: String in items:
				inv2.add(id, int(items[id]))
			var sp: Array = spots[i]
			Game.field["loot"].append({"id": "chest_%d" % i, "kind": "chest", "title": defs[i].get("title", "상자"),
				"pos": Vector3(float(sp[0]), ground_height(float(sp[0]), float(sp[1])), float(sp[1])), "inv": inv2, "expires": -1.0})
		Game.field["chests_made"] = true  # one-time contents, never refilled
	for d: Dictionary in Game.field["loot"].duplicate():
		LootContainer.create(self, d)


func _respawn_check() -> void:
	if is_random_dungeon():
		return  # a floor only exists for this visit
	var now := Game.total_minutes()
	for spec: Dictionary in region.get("monsters", []):
		var dead_at: float = Game.field["dead"].get(spec["id"], -1.0)
		if dead_at >= 0.0 and now - dead_at >= MONSTER_RESPAWN_MIN and not _defeated(spec):
			Game.field["dead"].erase(spec["id"])
			_spawn_monster(spec)


func is_safe(pos: Vector3) -> bool:
	for cp: Dictionary in checkpoints:
		var c: Vector3 = cp["pos"]
		if Vector2(pos.x - c.x, pos.z - c.z).length() < cp["radius"]:
			return true
	return false


## Nearest checkpoint by straight-line distance [미정 selection rule].
func nearest_checkpoint(pos: Vector3) -> Dictionary:
	var best: Dictionary = checkpoints[0] if not checkpoints.is_empty() else {}
	var best_d := INF
	for cp: Dictionary in checkpoints:
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
	var kept := {}  # quest items stay in the bag (assumption: losing them could block a quest)
	for e in inv.items:
		if ItemDB.category(e["id"]) == "quest":
			kept[e["id"]] = e["count"]
			continue
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
	for id: String in kept:
		inv.add(id, kept[id])
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
		ip.alt_prompt = "R 대화"
		ip.alt_action = func(_pl: Node) -> void:
			var n := _npc_for(shop_id)
			if n and n.is_working() and not n.hostile:
				Game.hud.start_dialogue(DialogueData.talk_dialogue(n.look))
		ip.prompt_func = func() -> String:
			var n := _npc_for(shop_id)
			if n and n.hostile:
				return "%s — 주인이 무기를 들고 쫓아온다" % ShopDB.info(shop_id)["name"]
			if n and n.is_working():
				return "E 거래하기 · R 대화 — %s" % ShopDB.info(shop_id)["name"]
			return "%s — 영업 종료 (%s)" % [ShopDB.info(shop_id)["name"], ShopDB.hours_text(shop_id)]
		ip.action = func(_pl: Node) -> void:
			var n := _npc_for(shop_id)
			if n and n.hostile:
				Game.boot.hud.toast("거래는 끝났다 — 섬 전체가 수배범을 쫓는다")
			elif n and n.is_working():
				Game.hud.open_shop(shop_id, ip)
			else:
				Game.boot.hud.toast("%s은(는) 지금 문을 닫았다 — 영업시간 %s" % [ShopDB.info(shop_id)["name"], ShopDB.hours_text(shop_id)])
	_on_ground(NatureProps.signpost(), -22.8, 6.8)


## NPC fuel refinery beside the smithy (GDD 9.3 [확정]: monster materials refined into fuel at an
## NPC facility first; a refinery inside the camper comes later): still, barrels, a pipe.
func _build_refinery() -> void:
	var root := _on_ground(Node3D.new(), REFINERY_POS.x, REFINERY_POS.z)
	var metal := ProtoMesh.mat(Color(0.5, 0.52, 0.56), 0.5)
	var copper := ProtoMesh.mat(Color(0.78, 0.48, 0.3), 0.4)
	var barrel := ProtoMesh.mat(Color(0.32, 0.38, 0.3))
	ProtoMesh.cylinder(root, 0.55, 1.5, Vector3(0, 0.75, 0), copper, Vector3.ZERO, 10)
	ProtoMesh.cone(root, 0.55, 0.5, Vector3(0, 1.75, 0), copper, 10)
	ProtoMesh.cylinder(root, 0.06, 1.2, Vector3(0.5, 1.6, 0), metal, Vector3(0, 0, -60), 6)
	ProtoMesh.cylinder(root, 0.3, 0.6, Vector3(1.1, 0.3, 0.1), metal, Vector3.ZERO, 8)
	for spec in [[-0.9, 0.4], [-1.0, -0.4], [1.0, -0.6]]:
		ProtoMesh.cylinder(root, 0.28, 0.75, Vector3(spec[0], 0.38, spec[1]), barrel, Vector3.ZERO, 8)
	ProtoMesh.static_cylinder_collider(root, 0.8, 2.0, Vector3(0, 1, 0))
	_block(REFINERY_POS.x, REFINERY_POS.z, 1.6)
	InteractPoint.facility(self, REFINERY_POS + Vector3(0, 0, 1.0), "refinery", "정제 시설")


func _build_quest_props() -> void:
	var wood := ProtoMesh.mat(Color(0.56, 0.4, 0.25))
	var dark := ProtoMesh.mat(Color(0.36, 0.25, 0.16))
	var paper := ProtoMesh.mat(Color(0.95, 0.92, 0.82))
	# notice board between the two stalls
	var board := _on_ground(Node3D.new(), BOARD_POS.x, BOARD_POS.z)
	for x in [-0.7, 0.7]:
		ProtoMesh.box(board, Vector3(0.1, 1.9, 0.1), Vector3(x, 0.95, 0), dark)
	ProtoMesh.box(board, Vector3(1.7, 1.0, 0.08), Vector3(0, 1.35, 0.02), wood)
	ProtoMesh.box(board, Vector3(1.9, 0.08, 0.3), Vector3(0, 1.92, 0), dark)
	for spec in [[-0.45, 1.5, 0.4], [0.1, 1.42, 0.5], [0.5, 1.2, 0.35], [-0.3, 1.12, 0.3]]:
		ProtoMesh.box(board, Vector3(spec[2], spec[2] * 0.75, 0.02), Vector3(spec[0], spec[1], 0.08), paper)
	ProtoMesh.static_box_collider(self, Vector3(1.8, 2.0, 0.3), Vector3(BOARD_POS.x, 1.0, BOARD_POS.z))
	_block(BOARD_POS.x, BOARD_POS.z, 1.2)
	var bip := InteractPoint.make(self, BOARD_POS + Vector3(0, 0, 0.8), "E 게시판 보기 — 의뢰 수락·보고", Callable(), 1.4)
	bip.action = func(_pl: Node) -> void: Game.hud.open_board(bip)
	# overturned cart + scattered parcels (field event: starts by walking close, no acceptance)
	var cart := _on_ground(Node3D.new(), CART_POS.x, CART_POS.z)
	cart.rotation_degrees.y = 28.0
	var bed := ProtoMesh.box(cart, Vector3(1.8, 0.12, 1.1), Vector3(0, 0.45, 0), wood, Vector3(0, 0, 24))
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	ProtoMesh.box(cart, Vector3(1.8, 0.4, 0.06), Vector3(0, 0.62, 0.55), dark, Vector3(0, 0, 24))
	ProtoMesh.box(cart, Vector3(1.8, 0.4, 0.06), Vector3(0, 0.62, -0.55), dark, Vector3(0, 0, 24))
	ProtoMesh.cylinder(cart, 0.42, 0.1, Vector3(-0.2, 0.42, 0.68), dark, Vector3(90, 0, 0), 12)
	ProtoMesh.cylinder(cart, 0.42, 0.1, Vector3(0.9, 0.08, -0.2), dark, Vector3(0, 0, 0), 12)
	ProtoMesh.box(cart, Vector3(1.4, 0.06, 0.06), Vector3(-1.5, 0.05, 0.1), dark, Vector3(0, 15, 0))
	ProtoMesh.static_box_collider(self, Vector3(1.9, 1.0, 1.4), Vector3(CART_POS.x, 0.5, CART_POS.z))
	_block(CART_POS.x, CART_POS.z, 2.0)
	var taken: Dictionary = Game.field.get("parcels", {})
	for spec: Array in PARCELS:
		var pid: String = spec[0]
		var pp: Vector3 = spec[1]
		_block(pp.x, pp.z, 0.8)
		if taken.has(pid):
			continue
		var pr := _on_ground(Node3D.new(), pp.x, pp.z)
		pr.rotation_degrees.y = float(pid.hash() % 60)
		ProtoMesh.box(pr, Vector3(0.5, 0.36, 0.42), Vector3(0, 0.18, 0), ProtoMesh.mat(Color(0.7, 0.55, 0.36)))
		ProtoMesh.box(pr, Vector3(0.52, 0.05, 0.1), Vector3(0, 0.37, 0), ProtoMesh.mat(Color(0.5, 0.2, 0.16)))
		var ip := InteractPoint.make(self, pp, "E 흩어진 짐 꾸러미 줍기 (대장간 표식)", Callable(), 1.3)
		ip.enabled_func = func() -> bool: return Game.quests.is_open(PARCEL_QUEST)
		ip.action = func(_pl: Node) -> void:
			if not Game.player_state.can_carry(ItemDB.weight("lost_parcel")):
				Game.boot.hud.toast("너무 무겁다 — 짐을 줄이고 다시 줍자")
				return
			Game.player_state.inventory.add("lost_parcel", 1)
			Game.player_state.changed.emit()
			var t: Dictionary = Game.field.get("parcels", {})
			t[pid] = true
			Game.field["parcels"] = t
			Game.boot.hud.toast("흩어진 짐 꾸러미를 주웠다 (%d/3)" % Game.player_state.inventory.count("lost_parcel"))
			pr.queue_free()
			ip.queue_free()


## Region maps lying in the field (data/maps "sources" kind drop, placed in the editor's 지도 tab):
## a rolled-up map on the ground, E picks it up and it goes onto the map screen.
func _build_map_drops() -> void:
	for dr: Dictionary in MapDB.drops_in(Game.region):
		var dp: Vector3 = dr["pos"]
		var mr: String = dr["region"]
		var pr := _on_ground(Node3D.new(), dp.x, dp.z)
		pr.name = "MapDrop_" + mr
		pr.rotation_degrees.y = float(mr.hash() % 90)
		var paper := ProtoMesh.mat(Color(0.93, 0.86, 0.66))
		ProtoMesh.box(pr, Vector3(0.62, 0.12, 0.14), Vector3(0, 0.07, 0), paper)
		ProtoMesh.box(pr, Vector3(0.12, 0.13, 0.15), Vector3(-0.33, 0.07, 0), ProtoMesh.mat(Color(0.55, 0.32, 0.18)))
		ProtoMesh.box(pr, Vector3(0.12, 0.13, 0.15), Vector3(0.33, 0.07, 0), ProtoMesh.mat(Color(0.55, 0.32, 0.18)))
		ProtoMesh.box(pr, Vector3(0.05, 0.14, 0.16), Vector3(0, 0.08, 0), ProtoMesh.mat(Color(0.7, 0.18, 0.15)))
		var ip := InteractPoint.make(self, dp, "E 지도 줍기 — %s" % MapDB.title(mr), Callable(), 1.3)
		ip.add_to_group("map_drop")
		ip.set_meta("map_region", mr)
		ip.action = func(_pl: Node) -> void:
			MapDB.give(mr)
			pr.queue_free()
			ip.queue_free()


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
		n.armed = Game.npcs_hostile()
		add_child(n)
		npcs.append(n)
		_arm_npc(n)


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
	if not Game.cat_joined and (not has_feature("camp") or not cat_may_appear()):
		cat.free()  # the roadside encounter only happens in the starting region (after the king's quest)
		cat = null
		return
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


## GDD 2.3 [확정]: the cat shows up once the hero has set out to fight the dragon. In a real game
## (the new-game story was seen) that means after accepting the king's quest; test runs without
## the story keep the old roadside encounter.
func cat_may_appear() -> bool:
	return not Game.narrative.get_flag("story.new_game_seen") or Game.quests.state("quest.main.dragon") != "none"


func _apply_camper_owned() -> void:
	var owned := camper_here()
	vehicle.visible = owned
	vehicle.process_mode = Node.PROCESS_MODE_INHERIT if owned else Node.PROCESS_MODE_DISABLED
	vehicle.collision_layer = 1 if owned else 0
	for ip in camper.find_children("*", "InteractPoint", false, false):
		(ip as InteractPoint).visible = owned


## Paint / attachments changed at the mechanic: repaint the model and re-bake its sprite.
func _on_camper_changed() -> void:
	if camper:
		camper.apply_look()
		Game.sprites_dirty = true


func _on_story_changed() -> void:
	_apply_camper_owned()
	if Game.cat_joined and cat and cat.mode == CatCompanion.Mode.ENCOUNTER:
		return  # joined by walking up to the player: keep this cat
	_spawn_cat(false)


func enter_vehicle() -> void:
	if not camper_here() or vehicle.driving:
		return
	if Game.camper_broken():
		Game.boot.hud.toast("캠핑카가 고장났다 (내구도 0) — 대장간 브론에게 수리를 맡기거나 응급 수리 공구를 쓰자")
		return
	player.set_driving(true)
	vehicle.driving = true
	camera.target = vehicle
	if cat:
		cat.visible = false  # rides along inside
		cat.process_mode = Node.PROCESS_MODE_DISABLED
	_last_drive_pos = vehicle.global_position
	vehicle.power = Game.camper_power()
	Game.boot.hud.toast("연료가 없다 — 휘발유 통으로 주유해야 움직인다" if Game.camper_out_of_fuel() else
		"운전 중 — W 가속 · S 브레이크→멈추면 천천히 후진 · W+S 제자리 정지 · A/D 핸들(달리는 동안) · 멈춘 뒤 E 내리기")


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
	_check_parking_manners(vehicle.global_position)
	if cat:
		var c := p + Vector3(0.7, 0, 0.6)
		cat.global_position = Vector3(c.x, ground_height(c.x, c.z), c.z)
		cat.visible = true
		cat.process_mode = Node.PROCESS_MODE_INHERIT
		cat.mode = CatCompanion.Mode.FOLLOW


func _save_parking() -> void:
	if vehicle:
		# Local position: also valid while the world is leaving the tree (world root = origin).
		if camper_here() and not _leaving_with_camper:
			Game.camper = {"region": region_id, "pos": vehicle.position, "yaw": vehicle.rotation.y}


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
var _age := 0.0
var _last_drive_pos := Vector3.INF
var _ram_cd := {}  # monster instance id -> time the next hit may count
## Set by bootstrap.travel when the camper drives out: its new parking spot is already decided.
var _leaving_with_camper := false
var _no_vehicle_toast_at := 0.0


## Exit whose zone (plus margin) contains pos, or {}.
func _exit_near(pos: Vector3, margin: float) -> Dictionary:
	for ex in exits:
		var c: Vector3 = ex["pos"]
		if Vector2(pos.x - c.x, pos.z - c.z).length() < float(ex["radius"]) + margin:
			return ex
	return {}


## Visiting a checkpoint or road exit marks it on the world map (GDD 11.3).
func _discover(pos: Vector3) -> void:
	# story spots (data "story_triggers"): walking there sets a flag (quest objectives read it),
	# says what you found and, with "map_name", puts it on the map
	for tr: Dictionary in region.get("story_triggers", []):
		var tk := "trig:%s:%s" % [region_id, tr["id"]]
		if Game.discovered.has(tk):
			continue
		var tp := RegionDB.v3(tr["pos"])
		if Vector2(pos.x - tp.x, pos.z - tp.z).length() < float(tr.get("radius", 6.0)):
			Game.discovered[tk] = true
			if str(tr.get("flag", "")) != "":
				Game.narrative.set_flag(str(tr["flag"]))
			if str(tr.get("toast", "")) != "":
				Game.boot.hud.toast(str(tr["toast"]))
				Game.combat_log.add(str(tr["toast"]), "", "info")
	for ct in cities:
		var ck := "city:" + str(ct["id"])
		if not Game.discovered.has(ck) and (ct["rect"] as Rect2).grow(4.0).has_point(Vector2(pos.x, pos.z)):
			Game.discovered[ck] = true
			Game.boot.hud.toast("%s — 처음 방문. 이제 지도(M)에서 빠른 이동 목적지로 고를 수 있다" % ct["name"])
	for cp in checkpoints:
		var c: Vector3 = cp["pos"]
		var key := "%s:%s" % [region_id, cp["id"]]
		if not Game.discovered.has(key) and Vector2(pos.x - c.x, pos.z - c.z).length() < cp["radius"]:
			Game.discovered[key] = true
			Game.boot.hud.toast("지도에 표시: " + cp["name"])
	for ex in exits:
		var c2: Vector3 = ex["pos"]
		var key2 := "%s:%s" % [region_id, ex["id"]]
		if not Game.discovered.has(key2) and Vector2(pos.x - c2.x, pos.z - c2.z).length() < float(ex["radius"]) + 8.0:
			Game.discovered[key2] = true


## Road exit: two stone posts and a signpost naming where the road leads (cave mouth / dungeon
## way out have their own look).
func _build_exit_marker(ex: Dictionary) -> void:
	var c: Vector3 = ex["pos"]
	if is_dungeon():
		_build_dungeon_exit(c)
		return
	if ex.get("style", "") == "door":
		_block(c.x, c.z, float(ex["radius"]) + 1.0)
		return  # a building's own door (the castle gate): no road markers
	if ex.get("style", "") == "cave":
		_build_cave_mouth(c)
		return
	if ex.get("style", "") == "rift":
		_build_rift_gate(ex)
		return
	var stone := ProtoMesh.mat(Color(0.58, 0.57, 0.54))
	var cloth := ProtoMesh.mat(Color(0.86, 0.72, 0.36))
	# posts either side of the road, across the direction toward the region edge
	var b_min := terrain.bounds_min
	var b_max := terrain.bounds_max
	var horizontal := minf(c.x - b_min.x, b_max.x - c.x) < minf(c.z - b_min.y, b_max.y - c.z)
	var side := Vector3(0, 0, 2.6) if horizontal else Vector3(2.6, 0, 0)
	for sgn in [-1.0, 1.0]:
		var pp: Vector3 = c + side * sgn
		var post := _on_ground(Node3D.new(), pp.x, pp.z)
		ProtoMesh.cylinder(post, 0.32, 1.5, Vector3(0, 0.75, 0), stone, Vector3.ZERO, 7)
		ProtoMesh.sphere(post, 0.3, Vector3(0, 1.55, 0), stone, Vector3(1, 0.7, 1), 7, 4)
		var flag := WindSway.new()
		flag.mode = WindSway.Mode.FLAG
		flag.position = Vector3(0, 1.3, 0.3)
		post.add_child(flag)
		ProtoMesh.box(flag, Vector3(0.36, 0.22, 0.03), Vector3(0.2, -0.1, 0), cloth)
		ProtoMesh.static_cylinder_collider(post, 0.35, 2.0, Vector3(0, 0.5, 0))
		_block(pp.x, pp.z, 1.0)
	var sign_pos: Vector3 = c + side * 1.6 + (Vector3(-2.2, 0, 0) if c.x > 0 else Vector3(2.2, 0, 0))
	_on_ground(NatureProps.signpost(), sign_pos.x, sign_pos.z)
	_block(c.x, c.z, float(ex["radius"]) + 1.5)


## While driving: fuel per metre, engine power from fuel / durability, running into monsters.
func _drive_costs() -> void:
	var was := vehicle.power
	var p := vehicle.global_position
	# upgrades (GDD 9.2 주행): top speed, and off the roads it is slow without the off-road kit
	var rough := not CamperUpgrades.offroad() and not on_road(p)
	vehicle.power = Game.camper_power() * CamperUpgrades.speed_mult() * (CamperUpgrades.OFFROAD_SPEED if rough else 1.0)
	vehicle.turn_mult = CamperUpgrades.turn_mult()
	if _last_drive_pos != Vector3.INF:
		var moved := Vector2(p.x - _last_drive_pos.x, p.z - _last_drive_pos.z).length()
		if moved < 3.0:  # not a teleport / scene change
			var before := Game.camper_fuel
			Game.use_camper_fuel(moved * CamperUpgrades.fuel_per_m())
			var low := Game.camper_fuel_max() * 0.15
			if before > low and Game.camper_fuel <= low and Game.camper_fuel > 0.0:
				Game.boot.hud.toast("연료가 얼마 안 남았다 (%d L)" % roundi(Game.camper_fuel))
	_last_drive_pos = p
	if was > 0.0 and vehicle.power <= 0.0:
		Game.boot.hud.toast("캠핑카가 멈췄다 — " + ("고장 (내구도 0)" if Game.camper_broken() else "연료가 떨어졌다"))
	if absf(vehicle.speed) < RAM_MIN_SPEED:
		return
	var inv := vehicle.global_transform.affine_inverse()
	for m in monsters:
		if not is_instance_valid(m) or m.state == SlimeMonster.State.DEAD:
			continue
		var key := m.get_instance_id()
		if float(_ram_cd.get(key, 0.0)) > _age:
			continue
		var l := inv * m.global_position
		if absf(l.x) > CamperExterior.LENGTH * 0.5 + 0.5 or absf(l.z) > CamperExterior.WIDTH * 0.5 + 0.5:
			continue
		_ram_cd[key] = _age + 0.8
		var sp := absf(vehicle.speed)
		var cost := roundf((RAM_CAMPER_DAMAGE + sp + float(m.profile.get("armor", 0)) * 4.0) * CamperUpgrades.ram_mult())  # whole points
		m.receive_ram(roundi(4.0 + sp * 2.5), vehicle)
		Game.damage_camper(cost)
		vehicle.speed *= 0.45
		Game.hud.float_text(vehicle.global_position + Vector3(0, 3.4, 0), "내구도 -%d" % roundi(cost), Color(1.0, 0.55, 0.3), true)
		Game.combat_log.add("캠핑카 내구도 -%d (%d/%d)" % [roundi(cost), ceili(Game.camper_durability), roundi(Game.CAMPER_DURABILITY_MAX)],
			"몬스터를 들이받은 충격 — 캠핑카 내구도 -%d (속도 %.1f m/s, 상대 방어 %d)" % [roundi(cost), sp, int(m.profile.get("armor", 0))], "death")
		if Game.camper_broken():
			vehicle.power = 0.0
			Game.boot.hud.toast("캠핑카가 고장났다! 멈춘 뒤 E로 내리자 — 수리: 대장간 브론 / 응급 수리 공구")
		elif Game.camper_durability < Game.CAMPER_DURABILITY_MAX * Game.CAMPER_WEAK and Game.camper_durability + cost >= Game.CAMPER_DURABILITY_MAX * Game.CAMPER_WEAK:
			Game.boot.hud.toast("캠핑카가 많이 상했다 — 속도가 떨어진다")


# ---------------------------------------------------------------- parked camper and the world (GDD 9.4)

var _camper_hit_toast_at := 0.0


func camper_parked_safe() -> bool:
	return RegionDB.spot_safe(region_id, vehicle.global_position)


## Nearest point on the parked camper's body for a monster to attack, or INF (not here, being
## driven, parked somewhere safe, or too far from this monster / its home).
func camper_bait(m: SlimeMonster) -> Vector3:
	if not camper_here() or vehicle.driving or camper_parked_safe():
		return Vector3.INF
	var local := vehicle.global_transform.affine_inverse() * m.global_position
	local.x = clampf(local.x, -CamperExterior.LENGTH * 0.5 - 0.4, CamperExterior.LENGTH * 0.5 + 0.4)
	local.z = clampf(local.z, -CamperExterior.WIDTH * 0.5 - 0.4, CamperExterior.WIDTH * 0.5 + 0.4)
	local.y = 0.0
	var w := vehicle.global_transform * local
	if Vector2(w.x - m.global_position.x, w.z - m.global_position.z).length() > 7.0 \
			or Vector2(w.x - m.home.x, w.z - m.home.z).length() > m.leash:
		return Vector3.INF
	return w


func hit_camper(m: SlimeMonster) -> void:
	if Game.camper_broken():
		return
	var dmg := 2.0
	Game.damage_camper(dmg)
	Game.hud.float_text(vehicle.global_position + Vector3(0, 3.4, 0), "내구도 -%d" % roundi(dmg), Color(1.0, 0.55, 0.3))
	Game.combat_log.add("%s이(가) 캠핑카를 공격 (-%d)" % [m.display_name, roundi(dmg)], "세워 둔 캠핑카가 공격받았다 — 내구도 %d/%d" % [ceili(Game.camper_durability), roundi(Game.CAMPER_DURABILITY_MAX)], "hurt")
	if _age > _camper_hit_toast_at:
		_camper_hit_toast_at = _age + 6.0
		Game.boot.hud.toast("캠핑카가 공격받고 있다! (내구도 %d) — 쫓아내거나, 안전한 곳에 세우자" % ceili(Game.camper_durability))


## Parking inside a town anywhere but its parking spot: a resident complains (penalty [미정]).
func _check_parking_manners(p: Vector3) -> void:
	for ct in cities:
		if not (ct["rect"] as Rect2).grow(2.0).has_point(Vector2(p.x, p.z)):
			continue
		var pk: Dictionary = ct["data"].get("parking", {})
		if not pk.is_empty() and Vector2(p.x - float(pk["pos"][0]), p.z - float(pk["pos"][1])).length() < 7.0:
			return
		Game.camper_mods["complaints"] = int(Game.camper_mods.get("complaints", 0)) + 1
		Game.hud.float_text(p + Vector3(1.5, 2.6, 2.0), "주민: 여기 세우시면 곤란해요!", Color(1.0, 0.85, 0.6), true)
		Game.combat_log.add("%s 주민의 항의" % ct["name"], "마을 안 아무 데나 세운 캠핑카에 주민이 항의했다 — 마을 입구의 주차 자리(P 표지)에 세워 달라고 한다", "info")
		Game.boot.hud.toast("%s 주민이 항의했다 — 주차 자리(P 표지)에 세워 달라고 한다" % ct["name"])
		return


func _build_parking_sign(pos: Variant) -> void:
	var p := RegionDB.v3(pos)
	var root := _on_ground(Node3D.new(), p.x - 2.0, p.z + 3.2)
	var white := ProtoMesh.mat(Color(0.95, 0.95, 0.95))
	ProtoMesh.cylinder(root, 0.05, 2.0, Vector3(0, 1.0, 0), ProtoMesh.mat(Color(0.5, 0.52, 0.55), 0.4), Vector3.ZERO, 6)
	ProtoMesh.box(root, Vector3(0.7, 0.7, 0.05), Vector3(0, 2.1, 0.03), ProtoMesh.mat(Color(0.2, 0.4, 0.8)))
	ProtoMesh.box(root, Vector3(0.1, 0.5, 0.06), Vector3(-0.12, 2.1, 0.06), white)
	ProtoMesh.box(root, Vector3(0.28, 0.08, 0.06), Vector3(0.0, 2.31, 0.06), white)
	ProtoMesh.box(root, Vector3(0.28, 0.08, 0.06), Vector3(0.0, 2.1, 0.06), white)
	ProtoMesh.box(root, Vector3(0.08, 0.2, 0.06), Vector3(0.12, 2.2, 0.06), white)
	# painted bay on the ground
	var bay := ProtoMesh.box(self, Vector3(8.0, 0.02, 3.4), Vector3(p.x, ground_height(p.x, p.z) + 0.03, p.z), ProtoMesh.mat(Color(0.62, 0.62, 0.6)))
	bay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Roads, town streets and the camp clearing count as road; everything else is rough ground.
func on_road(p: Vector3) -> bool:
	if is_dungeon() or terrain.path_distance(p.x, p.z) < 3.5:
		return true
	for ct in cities:
		if (ct["rect"] as Rect2).has_point(Vector2(p.x, p.z)):
			return true
	return has_feature("camp") and Vector2(p.x - CAMPER_POS.x, p.z - CAMPER_POS.z).length() < 14.0


func _process(delta: float) -> void:
	if vehicle and vehicle.driving:
		_drive_costs()
	if player == null:
		return
	_update_occluder_fade(delta)
	if player.visible:
		Game.quests.check_triggers(player.global_position)
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = 1.0
		_respawn_check()
	if vehicle.driving and Input.is_action_just_pressed("interact"):
		exit_vehicle()
	_age += delta
	_discover(player.global_position if not vehicle.driving else vehicle.global_position)
	if _age > EXIT_GRACE and Game.boot and not Game.boot.is_busy():
		var at := vehicle.global_position if vehicle.driving else player.global_position
		var ex := _exit_near(at, 0.0)
		if not ex.is_empty() and not ex.get("interact", false) and (vehicle.driving or player.visible):
			if vehicle.driving and ex.get("no_vehicle", false):
				if _age > _no_vehicle_toast_at:
					_no_vehicle_toast_at = _age + 3.0
					Game.boot.hud.toast("캠핑카로는 들어갈 수 없다 — 내려서 걸어가자")
			else:
				Game.boot.travel(ex["to_region"], ex["to_entry"], vehicle.driving)


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
	occlusion_mode = ((occlusion_mode + 1) % 2) as Occlusion
	return occlusion_mode_name()


func occlusion_mode_name() -> String:
	return OCCLUSION_NAMES[occlusion_mode]


func player_near_camper() -> bool:
	if not camper_here():
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
	if not camper_here():
		return "캠핑카는 %s에 세워 두었다" % RegionDB.region_name(str(Game.camper.get("region", "")))
	if not player_near_camper():
		return "캠핑카 근처(%.0fm 이내)에서만 F 라이트를 켤 수 있습니다" % CAMPER_LIGHT_RANGE
	Game.camper_lights_on = not Game.camper_lights_on
	return "캠핑카 라이트 %s" % ("ON" if Game.camper_lights_on else "OFF")


func context_hint() -> String:
	if vehicle.driving:
		return "운전 중 — W 가속 · S 브레이크/후진 · W+S 정지 · A/D 핸들 · E 내리기(정지 시) · F 라이트"
	if is_random_dungeon() and Game.in_run():
		var n := 0
		var gained := Game.run_gained()
		for id: String in gained:
			n += int(gained[id])
		return "%s %d층 — 출구를 찾아라 · 이번 탐험에서 얻은 것 %d개 (쓰러지면 모두 잃음)" % [region.get("name", ""), int(Game.run.get("floor", 1)), n]
	var ex := _exit_near(player.global_position, 7.0)
	if not ex.is_empty():
		if ex.get("style", "") == "rift":
			return ""
		if is_dungeon():
			return "%s → %s" % [ex.get("name", "출구"), RegionDB.region_name(ex["to_region"])]
		if ex.get("style", "") == "cave":
			return "%s — 들어가면 → %s (위험도 %s, 캠핑카로는 못 들어감)" % [ex.get("name", "동굴"), RegionDB.region_name(ex["to_region"]), RegionDB.danger_text(ex["to_region"])]
		if Game.region_locked(str(ex["to_region"])) != "":
			return "%s 쪽 길 — %s" % [RegionDB.region_name(ex["to_region"]), Game.region_locked(str(ex["to_region"]))]
		return "이 길을 따라가면 → %s (위험도 %s)" % [RegionDB.region_name(ex["to_region"]), RegionDB.danger_text(ex["to_region"])]
	if player_near_camper():
		return "캠핑카 근처 — F: 외부 라이트"
	return ""


func world_title() -> String:
	return "%s (위험도 %s)" % [RegionDB.region_name(region_id), RegionDB.danger_text(region_id)]
