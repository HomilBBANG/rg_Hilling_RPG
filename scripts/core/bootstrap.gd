extends Node
## Entry scene: owns the pixel render pipeline, the sharp HUD layer, debug input and
## world (exterior/interior) switching. Optional automated capture tour via user args:
##   godot --path . -- --tour=shots --capture-dir=/abs/path
##   godot --path . --write-movie out.avi --fixed-fps 30 -- --tour=walk

const FONT := preload("res://assets/fonts/NanumGothic.ttf")

var render: PixelRenderController
var world: Node3D
var hud: VisualHud

var _snap := true
var _orthogonal := true
var _zoom_index := 2
## Camera comparison style (TopdownCamera.STYLES): 0 = A, 1 = B, 2 = C.
var style_index := 2
var _outline_user := true
var _capture_dir := ""
var _touring := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	render = PixelRenderController.new()
	render.name = "PixelRender"
	render.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(render)
	Game.view = render

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = VisualHud.new()
	hud.font = FONT
	hud.boot = self
	layer.add_child(hud)

	Game.world_change_requested.connect(_load_world)
	render.settings_changed.connect(_on_render_settings_changed)
	_load_world(Game.start_world)
	_parse_args()


func _load_world(world_id: StringName) -> void:
	var prev := &""
	if world:
		prev = Game.WORLD_INTERIOR if world is CamperInteriorLab else Game.WORLD_EXTERIOR
		world.queue_free()
		render.world_root.remove_child(world)
	Game.previous_world = prev
	world = load(Game.WORLD_SCENES[world_id]).instantiate()
	render.world_root.add_child(world)
	_configure_camera()


func _configure_camera() -> void:
	var cam: TopdownCamera = world.camera
	var style: Dictionary = TopdownCamera.STYLES[style_index]
	cam.render = render
	cam.apply_style(style)
	cam.snap_enabled = _snap
	cam.orthogonal = _orthogonal
	cam.zoom_index = _zoom_index
	cam.set_outline(style["outline"] and _outline_user)
	cam.snap_to_target()
	if render.grade_strength != (1.0 if style["grade"] else 0.0):
		render.grade_strength = 1.0 if style["grade"] else 0.0
		render.apply_settings()  # re-enters _configure_camera once via settings_changed
	StylizedMaterials.set_stylized(style["stylized"])
	if world.get("day_night"):
		world.day_night.set_style(style["ssao"], style["fog"], style["grade"], cam.ortho_distance)


func set_camera_style(index: int) -> void:
	style_index = posmod(index, TopdownCamera.STYLES.size())
	_zoom_index = TopdownCamera.STYLES[style_index]["zoom"]
	_configure_camera()


func style_name() -> String:
	return TopdownCamera.STYLES[style_index]["name"]


func _on_render_settings_changed() -> void:
	if world:
		_configure_camera()


func current_world_id() -> StringName:
	return Game.WORLD_INTERIOR if world is CamperInteriorLab else Game.WORLD_EXTERIOR


func _unhandled_input(event: InputEvent) -> void:
	if _touring or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("pause"):
		get_tree().paused = not get_tree().paused
	elif event.is_action("preset_coarse"):
		render.set_preset(0)
	elif event.is_action("preset_mid"):
		render.set_preset(1)
	elif event.is_action("preset_soft"):
		render.set_preset(2)
	elif event.is_action("preset_native"):
		render.set_preset(3)
	elif event.is_action("cycle_camera_style"):
		set_camera_style(style_index + 1)
		hud.toast("카메라 스타일: " + style_name())
	elif event.is_action("toggle_outline"):
		_outline_user = not _outline_user
		_configure_camera()
		hud.toast("픽셀 외곽선: " + ("ON" if _outline_user else "OFF"))
	elif event.is_action("toggle_pipeline"):
		render.toggle_pipeline()
		hud.toast("파이프라인: " + render.pipeline_name())
	elif event.is_action("toggle_post"):
		render.set_post_enabled(not render.post_enabled)
		hud.toast("팔레트/디더(모드3): " + ("ON" if render.post_enabled else "OFF"))
	elif event.is_action("toggle_day_night"):
		Game.toggle_day_night()
		hud.toast("시각 → " + Game.clock_text())
	elif event.is_action("toggle_clock"):
		Game.clock_running = not Game.clock_running
		hud.toast("시계 " + ("진행" if Game.clock_running else "정지"))
	elif event.is_action("toggle_lantern"):
		Game.lantern_on = not Game.lantern_on
		hud.toast("개인 등불 " + ("ON" if Game.lantern_on else "OFF"))
	elif event.is_action("camper_lights"):
		hud.toast(world.try_toggle_camper_lights())
	elif event.is_action("toggle_interior"):
		Game.request_world(Game.WORLD_EXTERIOR if current_world_id() == Game.WORLD_INTERIOR else Game.WORLD_INTERIOR)
	elif event.is_action("toggle_help"):
		hud.toggle_help()
	elif event.is_action("toggle_snap"):
		_snap = not _snap
		_configure_camera()
		hud.toast("픽셀 스냅 카메라 " + ("ON" if _snap else "OFF"))
	elif event.is_action("toggle_projection"):
		_orthogonal = not _orthogonal
		_configure_camera()
		hud.toast("투영: " + ("직교" if _orthogonal else "원근"))
	elif event.is_action("toggle_occlusion"):
		hud.toast("가림 보조: " + world.cycle_occlusion_mode())
	elif event.is_action("zoom_in"):
		_zoom_index = maxi(0, _zoom_index - 1)
		_configure_camera()
	elif event.is_action("zoom_out"):
		_zoom_index = mini(TopdownCamera.ZOOM_STEPS.size() - 1, _zoom_index + 1)
		_configure_camera()
	elif event.is_action("screenshot"):
		var path := save_screenshot("")
		hud.toast("캡처 저장: " + ProjectSettings.globalize_path(path))


func save_screenshot(name: String) -> String:
	var dir := _capture_dir if _capture_dir != "" else "user://captures"
	DirAccess.make_dir_recursive_absolute(dir)
	if name == "":
		name = "denial_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	var path := dir.path_join(name)
	get_viewport().get_texture().get_image().save_png(path)
	return path


# ---------------------------------------------------------------- capture tour

func _parse_args() -> void:
	var tour := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-dir="):
			_capture_dir = a.trim_prefix("--capture-dir=")
		elif a.begins_with("--tour="):
			tour = a.trim_prefix("--tour=")
	if tour == "shots":
		_run_shot_tour()
	elif tour == "styles":
		_run_style_tour()
	elif tour == "night_outline":
		_run_night_outline_check()
	elif tour == "walk":
		_run_walk_tour()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _place_player(pos: Vector3, yaw: float) -> void:
	var p: PrototypePlayer = world.player
	p.global_position = Vector3(pos.x, world.ground_height(pos.x, pos.z), pos.z)
	p.face_direction(yaw)
	world.camera.snap_to_target()


func _shot(name: String) -> void:
	await _frames(12)
	var path := save_screenshot(name)
	print("[tour] saved ", path)


func _run_shot_tour() -> void:
	_touring = true
	hud.show_help_panel(false)
	Game.clock_running = false
	await _frames(20)
	# 1. Day forest path walk pose
	Game.minute_of_day = Game.DAY_PRESET_MINUTE
	render.set_preset(0)
	_place_player(Vector3(28.5, 0, -9.9), PI * 0.55)
	world.player.scripted_move = Vector2(1, -0.2)
	await _frames(15)
	world.player.scripted_move = Vector2.ZERO
	await _shot("01_day_forest_path_PXL-COARSE.png")
	# 2. Behind trees / shadows (silhouette on)
	_place_player(Vector3(22.2, 0, -5.7), PI * 0.6)
	await _shot("02_day_behind_tree_silhouette_PXL-COARSE.png")
	world.cycle_occlusion_mode()  # -> fade
	await _frames(40)
	await _shot("02b_day_behind_tree_fade_PXL-COARSE.png")
	world.cycle_occlusion_mode()  # -> off
	await _frames(40)
	await _shot("02c_day_behind_tree_off_PXL-COARSE.png")
	world.cycle_occlusion_mode()  # -> silhouette
	# 3. Camper front / ratio, then pixel comparison at the same spot
	_place_player(Vector3(-2.0, 0, 1.6), -PI * 0.25)
	await _shot("03_day_camper_PXL-COARSE.png")
	render.set_preset(2)
	await _shot("06a_compare_PXL-SOFT.png")
	render.set_preset(3)
	await _shot("06b_compare_3D-NATIVE.png")
	render.set_preset(0)
	render.toggle_pipeline()
	await _shot("06c_compare_M2_scaling3d_nearest_320.png")
	render.toggle_pipeline()
	render.set_post_enabled(true)
	await _shot("06d_compare_M3_palette_dither_PXL-COARSE.png")
	render.set_post_enabled(false)
	# 4. Night + lantern walk near the slime
	Game.minute_of_day = Game.NIGHT_PRESET_MINUTE
	Game.lantern_on = true
	_place_player(Vector3(4.0, 0, -0.5), -PI * 0.4)
	await _shot("04_night_lantern_slime_PXL-COARSE.png")
	Game.lantern_on = false
	await _shot("04b_night_no_light_PXL-COARSE.png")
	# 5. Night camper lights off/on
	_place_player(Vector3(-1.0, 0, 1.0), PI * 0.5)
	Game.camper_lights_on = false
	Game.lantern_on = true
	await _shot("05a_night_camper_lights_OFF_PXL-COARSE.png")
	Game.camper_lights_on = true
	await _shot("05b_night_camper_lights_ON_PXL-COARSE.png")
	render.set_preset(2)
	await _shot("05c_night_camper_lights_ON_PXL-SOFT.png")
	render.set_preset(0)
	# 6. Interior day & night
	Game.request_world(Game.WORLD_INTERIOR)
	await _frames(5)
	_place_player(Vector3(-2.2, 0, -0.4), -PI * 0.3)
	await _shot("07a_interior_night_PXL-COARSE.png")
	Game.minute_of_day = Game.DAY_PRESET_MINUTE
	Game.lantern_on = false
	await _shot("07b_interior_day_PXL-COARSE.png")
	render.set_preset(2)
	await _shot("07c_interior_day_PXL-SOFT.png")
	hud.show_help_panel(true)
	await _shot("08_help_overlay.png")
	get_tree().quit()


func _run_walk_tour() -> void:
	_touring = true
	hud.show_help_panel(false)
	Game.clock_running = false
	Game.minute_of_day = Game.DAY_PRESET_MINUTE
	render.set_preset(0)
	await _frames(5)
	_place_player(Vector3(12.0, 0, 1.8), 0.0)
	var p: PrototypePlayer = world.player
	var route: Array[Vector2] = [Vector2(17, -2), Vector2(23, -6.8), Vector2(30, -9.8), Vector2(37, -8)]
	for i in route.size():
		if i == 2:
			render.set_preset(2)
			hud.toast("PXL-SOFT")
		await _walk_to(p, route[i])
	render.set_preset(3)
	hud.toast("3D-NATIVE")
	await _walk_to(p, Vector2(42, -2))
	# Night section with lantern back toward the camper (coarse)
	Game.minute_of_day = Game.NIGHT_PRESET_MINUTE
	Game.lantern_on = true
	render.set_preset(0)
	hud.toast("밤 · 등불 · PXL-COARSE")
	_place_player(Vector3(9.0, 0, 2.2), 0.0)
	await _walk_to(p, Vector2(1.0, 3.8))
	Game.camper_lights_on = true
	hud.toast("캠핑카 라이트 ON")
	await _walk_to(p, Vector2(-2.5, 1.5))
	p.scripted_move = Vector2.ZERO
	await _frames(45)
	get_tree().quit()


func _walk_to(p: PrototypePlayer, goal: Vector2) -> void:
	for i in 900:
		var d := goal - Vector2(p.global_position.x, p.global_position.z)
		if d.length() < 0.4:
			return
		p.scripted_move = d.normalized()
		await get_tree().physics_frame


## Camera style comparison (visual direction test): same spot, daylight, A / B / C.
func _run_style_tour() -> void:
	_touring = true
	hud.show_help_panel(false)
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	render.set_preset(1)
	await _frames(30)
	for i in TopdownCamera.STYLES.size():
		set_camera_style(i)
		_place_player(Vector3(-4.3, 0, 1.1), PI * 0.8)
		await _frames(30)
		var id: String = TopdownCamera.STYLES[i]["id"]
		hud.set_capture_mode(true, "%s · PXL-MID 427×240" % style_name())
		await _shot("style_%s_PXL-MID.png" % id)
	# C at other densities for reference
	render.set_preset(0)
	hud.set_capture_mode(true, "%s · PXL-COARSE 320×180" % style_name())
	await _shot("style_C_PXL-COARSE.png")
	render.set_preset(2)
	hud.set_capture_mode(true, "%s · PXL-SOFT 640×360" % style_name())
	await _shot("style_C_PXL-SOFT.png")
	render.set_preset(1)
	set_camera_style(1)
	_place_player(Vector3(22.2, 0, -5.7), PI * 0.6)
	hud.set_capture_mode(true, "%s · 숲길(나무 뒤)" % style_name())
	await _shot("style_B_forest_occlusion.png")
	set_camera_style(2)
	hud.set_capture_mode(true, "%s · 숲길(나무 뒤)" % style_name())
	await _shot("style_C_forest_occlusion.png")
	_place_player(Vector3(6.0, 0, 4.2), -PI * 0.5)
	hud.set_capture_mode(true, "%s · 흙길과 슬라임" % style_name())
	await _shot("style_C_path_slime.png")
	get_tree().quit()


## Night view with outline pass on/off (diagnostic for the outline/highlight pass).
func _run_night_outline_check() -> void:
	_touring = true
	hud.show_help_panel(false)
	Game.clock_running = false
	Game.minute_of_day = Game.NIGHT_PRESET_MINUTE
	Game.lantern_on = true
	render.set_preset(1)
	await _frames(20)
	_place_player(Vector3(4.0, 0, -0.5), -PI * 0.4)
	hud.set_capture_mode(true, "%s · 밤 · 외곽선 ON" % style_name())
	await _shot("night_outline_on.png")
	_outline_user = false
	_configure_camera()
	hud.set_capture_mode(true, "%s · 밤 · 외곽선 OFF" % style_name())
	await _shot("night_outline_off.png")
	get_tree().quit()
