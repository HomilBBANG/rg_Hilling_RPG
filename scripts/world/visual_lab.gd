class_name VisualLab
extends Node3D
## Outdoor P0 visual lab: meadow, winding path, small forest, pond, mounds, fence/shed,
## modern camper, one slime and the player. Everything is generated procedurally on load.

enum Occlusion { SILHOUETTE, FADE, OFF }
const OCCLUSION_NAMES := ["실루엣", "수관 디더 투명화", "끔"]
const CAMPER_POS := Vector3(-6.2, 0.0, -2.8)
const CAMPER_YAW_DEG := -6.0
const CAMPER_LIGHT_RANGE := 7.5
const DEFAULT_SPAWN := Vector3(-4.3, 0.0, 1.1)
const CAMPFIRE_POS := Vector3(-2.6, 0.0, 1.9)

var terrain := TerrainField.new()
var player: PrototypePlayer
var camera: TopdownCamera
var camper: CamperExterior
var slime: SlimeVisual
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
	camper = CamperExterior.new()
	camper.name = "Camper"
	camper.position = CAMPER_POS
	camper.rotation_degrees.y = CAMPER_YAW_DEG
	add_child(camper)
	_block(CAMPER_POS.x, CAMPER_POS.z, 4.2)
	_block(CAMPER_POS.x - 2.0, CAMPER_POS.z, 2.0)
	_block(CAMPER_POS.x + 2.5, CAMPER_POS.z, 2.0)
	# Under the awning (door side faces the camera): rug, chairs, table, cooler, plants
	var door := camper.to_global(CamperExterior.DOOR_LOCAL)
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
	var rear := camper.to_global(Vector3(-4.4, 0, 0.6))
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
	var local := camper.to_local(Vector3(x, 0, z))
	if absf(local.x) < 4.0 and absf(local.z) < 1.5:
		return 0.0
	if Vector2(x, z).distance_to(Vector2(CAMPFIRE_POS.x, CAMPFIRE_POS.z)) < 1.4:
		return 0.0
	var door := camper.to_global(CamperExterior.DOOR_LOCAL)
	if absf(x - door.x - 1.6) < 1.4 and absf(z - door.z - 1.6) < 1.0:
		return 0.0
	d *= lerpf(0.35, 1.0, smoothstep(1.5, 3.0, pd))  # sparse at path edges
	return d


func _build_ground_cover() -> void:
	var hf := Callable(self, "ground_height")
	var area := Rect2(TerrainField.MIN + Vector2(3, 3), TerrainField.MAX - TerrainField.MIN - Vector2(6, 6))
	GroundCover.build(self, area, 3000, hf, Callable(self, "_grass_density"), _rng)
	# A little denser around the camp so the hero shot feels lush (still patchy, not a carpet)
	GroundCover.build(self, Rect2(-18, -12, 26, 22), 700, hf, Callable(self, "_grass_density"), _rng)
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
	var spawn := DEFAULT_SPAWN
	if Game.previous_world == Game.WORLD_INTERIOR:
		spawn = camper.door_world_position()
	player.global_position = Vector3(spawn.x, ground_height(spawn.x, spawn.z), spawn.z)
	player.face_direction(PI * 0.75 if Game.previous_world != Game.WORLD_INTERIOR else PI)

	slime = SlimeVisual.new()
	slime.name = "Slime"
	slime.height_func = hf
	slime.position = Vector3(7.0, 0.0, -0.5)
	add_child(slime)

	camera = TopdownCamera.new()
	camera.name = "Camera"
	camera.target = player
	add_child(camera)
	_motes = AmbientParticles.motes(player)
	_motes.emitting = false
	_motes.visible = false


## Objects drawn as pre-rendered pixel sprites: [node, bake spec, name].
func sprite_targets() -> Array:
	return [
		[player, PrototypePlayer.sprite_bake_spec(), "player"],
		[slime, SlimeVisual.sprite_bake_spec(), "slime"],
		[camper, CamperExterior.sprite_bake_spec(CAMPER_YAW_DEG), "camper"],
	]


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
