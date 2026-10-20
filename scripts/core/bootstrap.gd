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
var _zoom_index := 4  # 13 m view height (style D default)
## Camera comparison style (TopdownCamera.STYLES): 0 = A, 1 = B, 2 = C, 3 = D (default).
var style_index := 3
var _outline_user := true  # thin dark silhouette outlines (O toggles)
## Pre-rendered sprite pipeline for player / slime / camper (key Z).
var sprites_enabled := true
var baker: SpriteBaker
var last_sheets := {}
var _bake_signature := ""
var _baking := false
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

	baker = SpriteBaker.new()
	baker.name = "SpriteBaker"
	add_child(baker)
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
	cam.set_foliage_outline(style.get("foliage_outline", false))
	cam.snap_to_target()
	if render.grade_strength != (1.0 if style["grade"] else 0.0):
		render.grade_strength = 1.0 if style["grade"] else 0.0
		render.apply_settings()  # re-enters _configure_camera once via settings_changed
	StylizedMaterials.set_stylized(style["stylized"])
	StylizedMaterials.set_detail(style.get("detail", 1.0))
	if world.has_method("set_detail"):
		world.set_detail(style.get("detail", 1.0))
	var look: String = style.get("look", "soft")
	if render.grade_profile != look:
		render.set_grade_profile(look if render.GRADE_PROFILES.has(look) else "soft")
	if world.get("day_night"):
		world.day_night.set_style(style["ssao"], style["fog"], style["grade"], cam.ortho_distance)
		world.day_night.palette = look
	if world.has_method("set_fx"):
		world.set_fx(look == "deadcells")


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
	elif event.is_action("toggle_fullscreen"):
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event.is_action("toggle_sprites"):
		sprites_enabled = not sprites_enabled
		hud.toast("스프라이트 파이프라인(3D→픽셀 스프라이트): " + ("ON" if sprites_enabled else "OFF (실시간 3D)"))
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
	elif tour == "rawframes":
		_run_rawframes()
	elif tour == "walk_d":
		_run_walk_d()
	elif tour == "hd":
		_run_hd_tour()
	elif tour == "sprites":
		_run_sprite_tour()
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


## Camera style comparison (visual direction test): same spot, daylight, A / B / C / D.
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
		hud.set_capture_mode(true, "%s · PXL-MID 480×270" % style_name())
		await _shot("style_%s_PXL-MID.png" % id)
	# Dead Cells look (D) extra shots: night with lights, forest, other densities
	set_camera_style(3)
	Game.minute_of_day = Game.NIGHT_PRESET_MINUTE
	Game.camper_lights_on = true
	Game.lantern_on = true
	_place_player(Vector3(-4.3, 0, 1.1), PI * 0.8)
	hud.set_capture_mode(true, "%s · 밤 · 캠핑카 라이트 + 등불" % style_name())
	await _frames(30)
	await _shot("style_D_night_PXL-MID.png")
	Game.minute_of_day = 10.5 * 60.0
	Game.camper_lights_on = false
	Game.lantern_on = false
	_place_player(Vector3(22.2, 0, -5.7), PI * 0.6)
	hud.set_capture_mode(true, "%s · 숲길(나무 뒤)" % style_name())
	await _shot("style_D_forest_occlusion.png")
	_place_player(Vector3(-4.3, 0, 1.1), PI * 0.8)
	render.set_preset(0)
	hud.set_capture_mode(true, "%s · PXL-COARSE 320×180" % style_name())
	await _shot("style_D_PXL-COARSE.png")
	render.set_preset(1)
	set_camera_style(2)
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


# ---------------------------------------------------------------- sprite baking

func _process(_delta: float) -> void:
	if world == null or _baking:
		return
	var sig := _current_bake_signature()
	if sig != _bake_signature:
		_rebake(sig)


func _current_bake_signature() -> String:
	var cam: TopdownCamera = world.camera
	var on := sprites_enabled and cam.orthogonal and world.has_method("sprite_targets")
	return "%d|%s|%.2f|%d|%s|%d" % [world.get_instance_id(), on, cam.pitch_degrees, cam.zoom_index,
		render.render_size(), render.preset_index]


func _rebake(sig: String) -> void:
	_baking = true
	_bake_signature = sig
	var w := world
	var cam: TopdownCamera = w.camera
	var on := sprites_enabled and cam.orthogonal and w.has_method("sprite_targets")
	var targets: Array = w.sprite_targets() if w.has_method("sprite_targets") else []
	if not on:
		for t: Array in targets:
			t[0].use_sprite_sheet(null)
		_baking = false
		return
	var texel := cam.view_height() / float(render.render_texel_height())
	var pitch := cam.pitch_degrees
	var screen_px := render.render_size() + Vector2i(2, 2) * PixelRenderController.MARGIN_TEXELS
	var t0 := Time.get_ticks_msec()
	for t: Array in targets:
		var spec: Dictionary = t[1]
		spec["texel"] = texel
		spec["pitch"] = pitch
		spec["screen_px"] = screen_px
		var sheet := await baker.bake(spec)
		if w != world or not is_instance_valid(t[0]):
			break
		t[0].use_sprite_sheet(sheet)
		last_sheets[t[2]] = sheet
	print("[sprites] baked %d sheets in %d ms (texel %.3f m, pitch %.0f)" % [targets.size(), Time.get_ticks_msec() - t0, texel, pitch])
	_baking = false


func wait_for_sprites() -> void:
	await get_tree().process_frame
	while _baking or _bake_signature != _current_bake_signature():
		await get_tree().process_frame


## Pre-rendered sprite pipeline: export baked sheets + live 3D vs sprite comparison shots.
func _run_sprite_tour() -> void:
	_touring = true
	hud.show_help_panel(false)
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	render.set_preset(1)
	set_camera_style(3)
	await _frames(10)
	await wait_for_sprites()
	for k: String in last_sheets:
		SpriteBaker.export_sheet(last_sheets[k], _capture_dir.path_join("sheets"), k)
	var shots := [
		["day", 10.5 * 60.0, false, Vector3(-4.3, 0, 1.1), PI * 0.8, 2],
		["night", Game.NIGHT_PRESET_MINUTE, true, Vector3(-4.3, 0, 1.1), PI * 0.8, 2],
		["closeup", 10.5 * 60.0, false, Vector3(-4.0, 0, 1.0), PI * 0.75, 0],
		["slime", 10.5 * 60.0, false, Vector3(5.6, 0, 1.4), -PI * 0.4, 1],
	]
	for sdef: Array in shots:
		Game.minute_of_day = sdef[1]
		Game.camper_lights_on = sdef[2]
		Game.lantern_on = sdef[2]
		_zoom_index = sdef[5]
		_configure_camera()
		for mode in [true, false]:
			sprites_enabled = mode
			await wait_for_sprites()
			_place_player(sdef[3], sdef[4])
			hud.set_capture_mode(true, "%s · %s · %s" % [style_name(), sdef[0], "베이크 스프라이트" if mode else "실시간 3D"])
			await _frames(25)
			await _shot("sprite_%s_%s.png" % [sdef[0], "baked" if mode else "live3d"])
	# Interior (player sprite only)
	Game.minute_of_day = 12.0 * 60.0
	Game.lantern_on = false
	_zoom_index = 2
	Game.request_world(Game.WORLD_INTERIOR)
	for mode in [true, false]:
		sprites_enabled = mode
		await wait_for_sprites()
		_place_player(Vector3(-2.2, 0, -0.4), -PI * 0.3)
		hud.set_capture_mode(true, "%s · 실내 · %s" % [style_name(), "베이크 스프라이트" if mode else "실시간 3D"])
		await _frames(25)
		await _shot("sprite_interior_%s.png" % ("baked" if mode else "live3d"))
	sprites_enabled = true
	get_tree().quit()




## 1920x1080 output: current default (D, no outline) vs outline on, day and night.
func _run_hd_tour() -> void:
	_touring = true
	hud.show_help_panel(false)
	Game.clock_running = false
	render.set_preset(1)
	set_camera_style(3)
	var shots := [["day", 10.5 * 60.0, false], ["night", Game.NIGHT_PRESET_MINUTE, true]]
	for sdef: Array in shots:
		Game.minute_of_day = sdef[1]
		Game.camper_lights_on = sdef[2]
		Game.lantern_on = sdef[2]
		for outline in [false, true]:
			_outline_user = outline
			_configure_camera()
			await wait_for_sprites()
			_place_player(Vector3(-4.3, 0, 1.1), PI * 0.8)
			hud.set_capture_mode(true, "1920×1080 · %s · %s · 외곽선 %s" % [style_name(), sdef[0], "ON" if outline else "OFF"])
			await _frames(25)
			await _shot("hd_%s_outline_%s.png" % [sdef[0], "on" if outline else "off"])
	_outline_user = false
	get_tree().quit()


## Movement check for the default look (D + baked sprites): walk a loop around the camp.
func _run_walk_d() -> void:
	_touring = true
	hud.show_help_panel(false)
	hud.set_capture_mode(true, "")
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	var p: PrototypePlayer = world.player
	_place_player(Vector3(-3.0, 0, 3.5), 0.0)
	for goal in [Vector2(3.0, 3.0), Vector2(4.0, -1.5), Vector2(-1.0, -0.5), Vector2(-3.0, 3.5)]:
		await _walk_to(p, goal)
	p.scripted_move = Vector2.ZERO
	await _frames(20)
	get_tree().quit()


## Saves the raw low-res render (SubViewport) every frame: idle, then walking right, then diagonal.
func _run_rawframes() -> void:
	_touring = true
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	var p: PrototypePlayer = world.player
	_place_player(Vector3(0.0, 0, 2.5), 0.0)
	await _frames(10)
	var phases := [[Vector2.ZERO, 40, "idle"], [Vector2(1, 0), 40, "right"], [Vector2(0.8, -0.6), 40, "diag"]]
	for ph: Array in phases:
		p.scripted_move = ph[0]
		for i in ph[1]:
			await RenderingServer.frame_post_draw
			render.viewport.get_texture().get_image().save_png(_capture_dir.path_join("%s_%03d.png" % [ph[2], i]))
	get_tree().quit()
