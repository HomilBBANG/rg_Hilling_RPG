class_name VisualLab
extends Node3D
## Outdoor P0 visual lab: meadow, winding path, small forest, pond, mounds, fence/shed,
## modern camper, one slime and the player. Everything is generated procedurally on load.

enum Occlusion { SILHOUETTE, FADE, OFF }
const OCCLUSION_NAMES := ["실루엣", "수관 투명화", "끔"]
const CAMPER_POS := Vector3(-7.0, 0.0, -1.5)
const CAMPER_LIGHT_RANGE := 7.5
const DEFAULT_SPAWN := Vector3(-1.5, 0.0, 3.2)

var terrain := TerrainField.new()
var player: PrototypePlayer
var camera: TopdownCamera
var camper: CamperExterior
var slime: SlimeVisual
var sun: DirectionalLight3D
var day_night: DayNightController
var occlusion_mode: Occlusion = Occlusion.SILHOUETTE

## [{node: Node3D, mats: Array[StandardMaterial3D], radius: float, height: float}]
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
	_build_environment()
	_build_ground()
	_build_landmarks()
	_scatter_nature()
	_spawn_actors()


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
	sun.directional_shadow_max_distance = 75.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 0.6
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
	mi.mesh = terrain.build_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Pond water: semi-transparent, slightly glossy disc.
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = TerrainField.POND_RADIUS + 0.2
	disc.bottom_radius = TerrainField.POND_RADIUS + 0.2
	disc.height = 0.02
	disc.radial_segments = 24
	disc.rings = 1
	water.mesh = disc
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.22, 0.48, 0.66, 0.78)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.08
	wm.metallic_specular = 0.8
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(TerrainField.POND_CENTER.x, TerrainField.WATER_LEVEL, TerrainField.POND_CENTER.y)
	add_child(water)
	ProtoMesh.static_cylinder_collider(self, TerrainField.POND_RADIUS - 1.0, 6.0, water.position)
	var pad := ProtoMesh.mat(Color(0.2, 0.45, 0.2))
	var flower := ProtoMesh.mat(Color(0.98, 0.85, 0.9))
	for i in 6:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(1.5, TerrainField.POND_RADIUS - 1.5)
		var p := water.position + Vector3(cos(a) * r, 0.02, sin(a) * r)
		ProtoMesh.cylinder(self, _rng.randf_range(0.3, 0.5), 0.02, p, pad, Vector3.ZERO, 7)
		if i % 2 == 0:
			ProtoMesh.sphere(self, 0.1, p + Vector3(0.1, 0.06, 0), flower, Vector3.ONE, 5, 3)


func _on_ground(node: Node3D, x: float, z: float) -> Node3D:
	node.position = Vector3(x, ground_height(x, z), z)
	add_child(node)
	return node


func _build_landmarks() -> void:
	camper = CamperExterior.new()
	camper.name = "Camper"
	camper.position = CAMPER_POS
	add_child(camper)
	_placed.append(Vector3(CAMPER_POS.x, CAMPER_POS.z, 5.0))

	var hf := Callable(self, "ground_height")
	var fence_root := Node3D.new()
	fence_root.name = "Fence"
	add_child(fence_root)
	NatureProps.fence(fence_root, Vector3(-17, 0, -10), Vector3(-17, 0, 0.5), hf)
	NatureProps.fence(fence_root, Vector3(-17, 0, -10), Vector3(-9, 0, -10), hf)
	_placed.append(Vector3(-17, -5, 2.0))
	_placed.append(Vector3(-13, -10, 2.0))

	var shed := _on_ground(NatureProps.shed(), -16.0, 9.6)
	_register_occluder(shed, 2.6, 3.4)
	_placed.append(Vector3(-16, 9.6, 3.0))

	_on_ground(NatureProps.signpost(), 12.5, 4.4)
	_on_ground(NatureProps.campfire_ring(_rng), -1.0, -4.0)
	_placed.append(Vector3(-1, -4, 2.5))

	# Deliberate occlusion test: big trees just south of the path near the forest edge.
	for spec in [[NatureProps.TreeKind.BROADLEAF, 22.0, -3.9, 1.25], [NatureProps.TreeKind.PINE, 26.0, -6.2, 1.2],
			[NatureProps.TreeKind.BROADLEAF, 33.0, -6.9, 1.1], [NatureProps.TreeKind.BIRCH, 18.4, 0.3, 1.1]]:
		_place_tree(spec[0], spec[1], spec[2], spec[3])


func _place_tree(kind: NatureProps.TreeKind, x: float, z: float, s: float) -> void:
	var t := _on_ground(NatureProps.tree(kind, s, _rng), x, z)
	var radius := (1.5 if kind != NatureProps.TreeKind.BIRCH else 1.0) * s
	_register_occluder(t, radius, 3.2 * s)
	ProtoMesh.static_cylinder_collider(self, 0.28 * s, 8.0, t.position)
	_placed.append(Vector3(x, z, radius))


func _register_occluder(node: Node3D, radius: float, h: float) -> void:
	if not node.has_meta("fade_mats"):
		return
	var mats: Array[StandardMaterial3D] = []
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
		var kind := NatureProps.TreeKind.PINE if roll < 0.6 else (NatureProps.TreeKind.BROADLEAF if roll < 0.85 else NatureProps.TreeKind.BIRCH)
		var s := _rng.randf_range(0.85, 1.3)
		if _is_free(p.x, p.y, 1.1 * s, 1.6):
			_place_tree(kind, p.x, p.y, s)
			placed += 1
	# Scattered meadow trees
	placed = 0
	tries = 0
	var area := Rect2(TerrainField.MIN, TerrainField.MAX - TerrainField.MIN)
	while placed < 26 and tries < 2000:
		tries += 1
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		var kind := NatureProps.TreeKind.BROADLEAF if _rng.randf() < 0.55 else (NatureProps.TreeKind.BIRCH if _rng.randf() < 0.6 else NatureProps.TreeKind.PINE)
		var s := _rng.randf_range(0.85, 1.25)
		if _is_free(p.x, p.y, 2.0 * s, 2.5):
			_place_tree(kind, p.x, p.y, s)
			placed += 1
	# Bushes, rocks, grass tufts
	for i in 600:
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		var roll := _rng.randf()
		if roll < 0.06:
			if _is_free(p.x, p.y, 0.8, 1.6):
				_on_ground(NatureProps.bush(_rng.randf() < 0.4, _rng.randf_range(0.8, 1.2), _rng), p.x, p.y)
				_placed.append(Vector3(p.x, p.y, 0.8))
		elif roll < 0.1:
			if _is_free(p.x, p.y, 0.9, 1.8):
				var s := _rng.randf_range(0.7, 1.3)
				var r := _on_ground(NatureProps.rock(_rng.randf() < 0.4, s, _rng), p.x, p.y)
				ProtoMesh.static_cylinder_collider(self, 0.7 * s, 6.0, r.position)
				_placed.append(Vector3(p.x, p.y, 0.9 * s))
		elif roll < 0.4:
			if _is_free(p.x, p.y, 0.1, 1.4):
				_on_ground(NatureProps.grass_tuft(_rng), p.x, p.y)
	# A few rocks on the mounds and around the pond for silhouette variety
	for m: Array in TerrainField.MOUNDS:
		var c: Vector2 = m[0]
		if _is_free(c.x, c.y, 1.0, 1.5):
			var r := _on_ground(NatureProps.rock(false, 1.4, _rng), c.x, c.y)
			ProtoMesh.static_cylinder_collider(self, 1.0, 6.0, r.position)


func _spawn_actors() -> void:
	var hf := Callable(self, "ground_height")
	player = PrototypePlayer.new()
	player.name = "Player"
	player.height_func = hf
	player.walk_bounds = Rect2(TerrainField.MIN + Vector2(4, 4), TerrainField.MAX - TerrainField.MIN - Vector2(8, 8))
	add_child(player)
	var spawn := DEFAULT_SPAWN
	if Game.previous_world == Game.WORLD_INTERIOR:
		spawn = camper.door_world_position()
	player.global_position = Vector3(spawn.x, ground_height(spawn.x, spawn.z), spawn.z)
	player.face_direction(0.0 if Game.previous_world != Game.WORLD_INTERIOR else PI)

	slime = SlimeVisual.new()
	slime.name = "Slime"
	slime.height_func = hf
	slime.position = Vector3(6.0, 0.0, -2.5)
	add_child(slime)

	camera = TopdownCamera.new()
	camera.name = "Camera"
	camera.target = player
	add_child(camera)


func _process(delta: float) -> void:
	if player == null:
		return
	_update_occluder_fade(delta)


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
			for m: StandardMaterial3D in o["mats"]:
				m.albedo_color.a = a
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if a < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED


func cycle_occlusion_mode() -> String:
	occlusion_mode = ((occlusion_mode + 1) % 3) as Occlusion
	var sil := occlusion_mode == Occlusion.SILHOUETTE
	player.set_silhouette(sil)
	slime.set_silhouette(sil)
	return occlusion_mode_name()


func occlusion_mode_name() -> String:
	return OCCLUSION_NAMES[occlusion_mode]


func player_near_camper() -> bool:
	var d := Vector2(player.global_position.x - CAMPER_POS.x, player.global_position.z - CAMPER_POS.z)
	return d.length() < CAMPER_LIGHT_RANGE


## F key. Returns a message for the HUD.
func try_toggle_camper_lights() -> String:
	if not player_near_camper():
		return "캠핑카 근처(%.0fm 이내)에서만 F 라이트를 켤 수 있습니다" % CAMPER_LIGHT_RANGE
	Game.camper_lights_on = not Game.camper_lights_on
	return "캠핑카 라이트 %s" % ("ON" if Game.camper_lights_on else "OFF")


func context_hint() -> String:
	if player_near_camper():
		return "캠핑카 근처 — F: 외부 라이트 · I: 실내로"
	return ""


func world_title() -> String:
	return "야외 랩 (visual_lab)"
