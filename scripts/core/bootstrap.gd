extends Node
## Entry scene: owns the pixel render pipeline, the sharp HUD layer, debug input and
## world (exterior/interior) switching. Optional automated capture tour via user args:
##   godot --path . -- --tour=shots --capture-dir=/abs/path
##   godot --path . --write-movie out.avi --fixed-fps 30 -- --tour=walk

const FONT := preload("res://assets/fonts/NanumGothic.ttf")

var render: PixelRenderController
var world: Node3D
var hud: VisualHud
var game_hud: GameHud

var _snap := true
var _orthogonal := true
var _zoom_index := 3  # 11 m view height (style D default)
## Camera comparison style (TopdownCamera.STYLES): 0 = A, 1 = B, 2 = C, 3 = D (default).
var style_index := 3
var _outline_user := true  # thin dark silhouette outlines (O toggles)
## Pre-rendered sprite pipeline for player / slime / camper (key Z).
var sprites_enabled := true
var baker: SpriteBaker
var last_sheets := {}
## Baked sheets by "name|render signature": shared by all slimes, reused across world reloads.
var _sheet_cache := {}
var _bake_signature := ""
var _baking := false
var _capture_dir := ""
var _touring := false
var _busy := false  # death / sleep sequence running


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
	game_hud = GameHud.new()
	game_hud.font = FONT
	game_hud.boot = self
	layer.add_child(game_hud)
	Game.hud = game_hud
	Game.boot = self
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
	if world_id == Game.WORLD_INTERIOR and not Game.has_camper:
		hud.toast("아직 캠핑카가 없습니다 (F9: 진행 단계 전환)")
		return
	if game_hud:
		game_hud.close_panel()
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
	if _busy and not event.is_action("pause"):
		return
	if event.is_action("pause"):
		get_tree().paused = not get_tree().paused
	elif event.is_action("inventory"):
		game_hud.toggle_inventory()
	elif event.is_action("character"):
		game_hud.toggle_character()
	elif event.is_action("combat_log"):
		game_hud.cycle_log_level()
	elif event.is_action("debug_status"):
		hud.toggle_debug()
	elif event.is_action("debug_heal"):
		Game.player_state.restore_all()
		hud.toast("디버그: HP/SP/MP 전체 회복")
	elif event.is_action("debug_stage"):
		_cycle_story_stage()
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
	elif event.is_action("toggle_wind"):
		StylizedMaterials.set_wind(0.0 if StylizedMaterials.wind > 0.5 else 1.0)
		hud.toast("바람(풀·수풀·나무 흔들림): " + ("ON" if StylizedMaterials.wind > 0.5 else "OFF"))
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
		if not Game.player_state.has_lantern():
			hud.toast("등불을 걸 허리띠가 없다 (등불 허리띠를 장착하세요)")
			return
		Game.lantern_on = not Game.lantern_on
		hud.toast("개인 등불 " + ("ON" if Game.lantern_on else "OFF"))
	elif event.is_action("camper_lights"):
		hud.toast(world.try_toggle_camper_lights())
	elif event.is_action("toggle_interior"):
		if world is VisualLab and world.vehicle.driving:
			return
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
	elif tour == "p1":
		_run_p1_tour()
	elif tour == "p2":
		_run_p2_tour()
	elif tour == "gear":
		_run_gear_tour()
	elif tour == "items":
		_run_items_tour()
	elif tour == "shop":
		_run_shop_tour()
	elif tour == "drive":
		_run_drive_compare()
	elif tour == "wind":
		_run_wind_check()
	elif tour == "catfollow":
		_run_cat_follow_check()
	elif tour == "p1input":
		_run_p1_input_tour()


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
	if sig != _bake_signature or Game.sprites_dirty:
		_rebake(sig)


func _render_signature() -> String:
	var cam: TopdownCamera = world.camera
	return "%.2f|%d|%s|%d" % [cam.pitch_degrees, cam.zoom_index, render.render_size(), render.preset_index]


func _current_bake_signature() -> String:
	var cam: TopdownCamera = world.camera
	var on := sprites_enabled and cam.orthogonal and world.has_method("sprite_targets")
	return "%d|%s|%.2f|%d|%s|%d" % [world.get_instance_id(), on, cam.pitch_degrees, cam.zoom_index,
		render.render_size(), render.preset_index]


func _rebake(sig: String) -> void:
	_baking = true
	_bake_signature = sig
	Game.sprites_dirty = false
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
	var rsig := _render_signature()
	for k: String in _sheet_cache.keys():
		if not k.ends_with("|" + rsig):
			_sheet_cache.erase(k)
	var baked := 0
	for t: Array in targets:
		var key: String = t[2] + "|" + rsig
		var sheet: SpriteSheet = _sheet_cache.get(key)
		if sheet == null:
			var spec: Dictionary = t[1]
			spec["texel"] = texel
			spec["pitch"] = pitch
			spec["screen_px"] = screen_px
			sheet = await baker.bake(spec)
			_sheet_cache[key] = sheet
			baked += 1
		if w != world:
			break
		if not is_instance_valid(t[0]):
			continue
		t[0].use_sprite_sheet(sheet)
		last_sheets[t[2]] = sheet
	if baked > 0:
		print("[sprites] baked %d new sheets (%d targets) in %d ms (texel %.3f m, pitch %.0f)" % [baked, targets.size(), Time.get_ticks_msec() - t0, texel, pitch])
	_baking = false


func wait_for_sprites() -> void:
	await get_tree().process_frame
	while _baking or _bake_signature != _current_bake_signature() or Game.sprites_dirty:
		await get_tree().process_frame


# ---------------------------------------------------------------- P1 flows

func _cycle_story_stage() -> void:
	if world is VisualLab and world.vehicle.driving:
		world.vehicle.speed = 0.0
		world.exit_vehicle()
	Game.set_story_stage(Game.story_stage() + 1)
	hud.toast("진행 단계 → " + Game.STAGE_NAMES[Game.story_stage()])
	if not Game.has_camper and world is CamperInteriorLab:
		Game.request_world(Game.WORLD_EXTERIOR)


## Player HP reached 0 (GDD 2.4 / 12.3 [확정]): field loot is split (goblins take part, the rest
## stays at the spot), then wake inside the camper if owned, else at the nearest safe checkpoint
## (with the cat beside the player once it has joined). Unconscious time / wake HP are [미정].
func on_player_died(death_pos: Vector3) -> void:
	if _busy:
		return
	_busy = true
	game_hud.close_panel()
	Game.combat_log.add("주인공이 쓰러졌다", "주인공 HP 0 — 쓰러졌다", "death")
	await game_hud.fade_to(1.0, 1.4, "쓰러졌다…")
	var loss := {"taken": {}, "left": 0}
	var cp := {}
	if world is VisualLab:
		loss = world.drop_death_loot(death_pos)
		cp = world.nearest_checkpoint(death_pos)
	Game.advance_minutes(60.0)
	var st := Game.player_state
	st.hp = ceilf(st.max_hp() * 0.5)
	st.sp = st.max_sp()
	st.changed.emit()
	var where := ""
	if Game.has_camper:
		Game.spawn_override = {"kind": "rescued"}
		where = "캠핑카 안에서 눈을 떴다"
		Game.request_world(Game.WORLD_INTERIOR)
	else:
		var p: Vector3 = cp.get("pos", VisualLab.DEFAULT_SPAWN)
		Game.spawn_override = {"kind": "checkpoint", "pos": p, "yaw": PI * 0.8, "name": cp.get("name", "")}
		where = "%s에서 정신을 차렸다" % cp.get("name", "체크포인트")
		Game.request_world(Game.WORLD_EXTERIOR)
	await _frames(3)
	await wait_for_sprites()
	await _frames(10)
	var taken: Dictionary = loss["taken"]
	var detail := "가져갈 짐이 없었다"
	if not taken.is_empty():
		var names := PackedStringArray()
		for id: String in taken:
			names.append("%s ×%d" % [ItemDB.item_name(id), taken[id]])
		detail = "고블린이 %s을(를) 가져갔다 · 나머지 %d개는 쓰러진 곳에 남아 있다" % [", ".join(names), loss["left"]]
	Game.combat_log.add(where, "%s — %s" % [where, detail], "info")
	await game_hud.fade_to(0.0, 1.2)
	hud.toast(where)
	await _frames(150)
	hud.toast(detail)
	_busy = false


## Cot sleep (GDD 9.6 / 10.1 [확정]): chosen hours pass, cot restores HP 10 % of max [임시].
func sleep(hours: int) -> void:
	if _busy:
		return
	_busy = true
	await game_hud.fade_to(1.0, 0.9, "zzz…")
	Game.advance_minutes(hours * 60.0)
	var st := Game.player_state
	var before := st.hp
	st.heal(st.max_hp() * 0.10)
	st.sp = st.max_sp()
	st.mp = st.max_mp()
	st.changed.emit()
	await _frames(20)
	await game_hud.fade_to(0.0, 0.9)
	var msg := "%d시간 잤다 — %s · HP +%d" % [hours, Game.clock_text(), roundi(st.hp - before)]
	hud.toast(msg)
	Game.combat_log.add(msg, "", "info")
	_busy = false


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
	render.set_preset(2)
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


# ---------------------------------------------------------------- P1 verification tour

func _seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _focus_interact(alt := false) -> void:
	await _frames(3)
	var p: PrototypePlayer = world.player
	if p.focus == null:
		print("[p1] no focus near ", p.global_position)
		return
	print("[p1] interact: ", p.focus.prompt_text())
	if alt:
		p.focus.interact_alt(p)
	else:
		p.focus.interact(p)


func _nearest_monster(from: Vector3) -> SlimeMonster:
	var best: SlimeMonster = null
	for m in world.monsters:
		if is_instance_valid(m) and (best == null or m.global_position.distance_to(from) < best.global_position.distance_to(from)):
			best = m
	return best


func _p1_shot(name: String, caption: String, quick := false) -> void:
	hud.set_capture_mode(false)
	hud.show_help_panel(false)
	print("[p1] ", caption)
	if quick:
		await _frames(3)
		print("[tour] saved ", save_screenshot("p1_" + name + ".png"))
	else:
		await _shot("p1_" + name + ".png")


func _wait_fade_clear() -> void:
	await _frames(2)
	while game_hud._fade.modulate.a > 0.02:
		await _frames(1)


## Exercises the P1 loop and saves screenshots: crate loot, weight, combat, corpse loot, death ->
## camper wake, storage, cat pet/snack, sleep, death bag, driving, stage A cat encounter and
## checkpoint wake with the cat.
func _run_p1_tour() -> void:
	_touring = true
	Dice.rng.seed = 4
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	Game.combat_log.level = 2
	await wait_for_sprites()
	var p: PrototypePlayer = world.player
	# 1. Camp, HUD
	_place_player(VisualLab.CRATE_POS + Vector3(0.3, 0, 1.2), 0.0)
	await _p1_shot("01_camp_hud", "camp + HUD")
	# 2. Supply crate inspection
	await _focus_interact()
	await _p1_shot("02_crate_loot", "crate loot panel")
	game_hud.close_panel()
	var crate: LootContainer = p.focus
	for e in crate.inventory().duplicate_items():
		game_hud._move(crate.inventory(), Game.player_state.inventory, e["id"], e["count"], game_hud._player_can_take)
	Game.player_state.inventory.add("iron_ore", 3)
	game_hud.toggle_inventory()
	await _p1_shot("03_inventory_overweight", "inventory overweight %.1f kg x%.2f" % [Game.player_state.carried_weight(), Game.player_state.speed_factor()])
	var before := Game.player_state.inventory.count("iron_ore")
	Game.player_state.inventory.add("iron_ore", 0)
	var tmp := Inventory.new()
	tmp.add("iron_ore", 3)
	var got := game_hud._move(tmp, Game.player_state.inventory, "iron_ore", 3, game_hud._player_can_take)
	print("[p1] pickup over the limit: moved %d of 3 (ore %d -> %d, weight %.1f / limit %.1f)" % [got, before, Game.player_state.inventory.count("iron_ore"), Game.player_state.carried_weight(), Game.player_state.carry_limit()])
	game_hud.close_panel()
	# keep a few things for the death test, drop the ore
	Game.player_state.inventory.remove("iron_ore", 99)
	# 3. Fight the passive meadow slimes
	_place_player(Vector3(12.0, 0, 5.0), -PI * 0.5)
	await _frames(10)
	Game.combat_log.level = 3
	game_hud._refresh_log()
	var target := _nearest_monster(p.global_position)
	var swings := 0
	var shot_taken := false
	while is_instance_valid(target) and swings < 40:
		var d := target.global_position - p.global_position
		d.y = 0
		if d.length() > 1.2:
			p.scripted_move = Vector2(d.x, d.z).normalized()
			await get_tree().physics_frame
			continue
		p.scripted_move = Vector2.ZERO
		p.start_attack(target.global_position)
		swings += 1
		await _seconds(0.45)
		if swings == 2 and not shot_taken:
			shot_taken = true
			await _p1_shot("04_combat_log3", "fight, log level 3")
		Game.player_state.sp = Game.player_state.max_sp()
	p.scripted_move = Vector2.ZERO
	print("[p1] slime fight: %d swings, killed=%s, HP %d" % [swings, not is_instance_valid(target), Game.player_state.hp])
	await _frames(20)
	# 4. Corpse inspection
	var corpse: LootContainer = null
	for n in world.get_children():
		if n is LootContainer and n.data["kind"] == "corpse":
			corpse = n
	if corpse:
		_place_player(corpse.global_position + Vector3(0, 0, 1.0), 0.0)
		await _focus_interact()
		await _p1_shot("05_corpse_loot", "corpse loot")
		for e in corpse.inventory().duplicate_items():
			game_hud._move(corpse.inventory(), Game.player_state.inventory, e["id"], e["count"], game_hud._player_can_take)
		game_hud.close_panel()
	Game.combat_log.level = 2
	game_hud._refresh_log()
	# 5. Death with the camper owned -> wake inside the camper
	var death_pos := p.global_position
	Game.player_state.take_damage(999)
	while not _busy:
		await _frames(1)
	await _seconds(1.0)
	await _wait_fade_clear()
	await _p1_shot("06_wake_in_camper", "death -> camper interior wake (cat beside)", true)
	while _busy:
		await _frames(1)
	# 6. Storage: take snacks out, move everything in
	p = world.player
	_place_player(CamperInteriorLab.STORAGE_POS + Vector3(0, 0, -0.9), 0.0)
	await _focus_interact()
	game_hud._move(Game.storage, Game.player_state.inventory, "cat_snack", 3, game_hud._player_can_take)
	game_hud._refresh_panel()
	await _p1_shot("07_storage", "storage panel")
	game_hud.close_panel()
	# 7. Cat: pet + snack
	var cat: CatCompanion = world.cat
	cat.global_position = Vector3(1.4, 0, 0.2)
	cat.mode = CatCompanion.Mode.HOME
	_place_player(Vector3(0.4, 0, 0.35), -PI * 0.5)
	await _frames(5)
	await _focus_interact()
	await _p1_shot("08_cat_pet", "pet the cat", true)
	await _seconds(1.9)
	await _focus_interact(true)
	await _p1_shot("09_cat_snack", "snack: affection %d" % Game.cat_affection, true)
	# 8. Sleep 10 h on the cot -> night
	_place_player(CamperInteriorLab.COT_POS + Vector3(0, 0, 1.2), 0.0)
	await _focus_interact()
	game_hud._sleep_hours = 10
	game_hud._refresh_panel()
	await _p1_shot("10_sleep_panel", "sleep panel")
	game_hud.close_panel()
	sleep(10)
	await _frames(2)
	while _busy:
		await _frames(1)
	await _p1_shot("11_after_sleep", "after sleep %s" % Game.clock_text())
	# 9. Out at night: lights, death bag
	Game.request_world(Game.WORLD_EXTERIOR)
	await wait_for_sprites()
	Game.lantern_on = true
	Game.camper_lights_on = true
	await _frames(10)
	await _p1_shot("12_night_exit", "night outside the camper")
	_place_player(death_pos + Vector3(0, 0, 1.0), 0.0)
	await _focus_interact()
	await _p1_shot("13_death_bag", "death bag at the death spot")
	game_hud.close_panel()
	# 10. Drive
	Game.minute_of_day = 10.5 * 60.0
	_place_player(world.camper.to_global(Vector3(2.5, 0, 2.6)), 0.0)
	await _focus_interact()
	await _frames(5)
	var v: CamperVehicle = world.vehicle
	# Out of the camp: W ahead past the blossom tree, then D (nose right, south-east) along the path.
	v.scripted = {"throttle": 1.0, "steer": 0.0}
	await _seconds(1.0)
	print("[p1] drive 1: pos %s yaw %.0f speed %.1f" % [v.global_position, rad_to_deg(v.rotation.y), v.speed])
	v.scripted = {"throttle": 1.0, "steer": -1.0}
	await _seconds(0.5)
	v.scripted = {"throttle": 1.0, "steer": 0.0}
	await _seconds(1.5)
	print("[p1] drive 2: pos %s yaw %.0f speed %.1f" % [v.global_position, rad_to_deg(v.rotation.y), v.speed])
	await _p1_shot("14_driving", "driving yaw %.0f dir %d" % [rad_to_deg(v.rotation.y), v.sprite_direction()], true)
	v.scripted = {"throttle": 1.0, "steer": 0.0}
	await _seconds(1.5)
	v.scripted = {"throttle": 0.0, "steer": 0.0}  # let go = stop
	while v.speed > 0.2:
		await get_tree().physics_frame
	v.scripted = {}
	await _seconds(0.3)
	world.exit_vehicle()
	await _frames(10)
	await _p1_shot("15_parked", "parked elsewhere, player out")
	# 11. Stage A: no camper, cat waits on the path and joins
	Game.set_story_stage(0)
	_place_player(Vector3(1.0, 0, 5.4), -PI * 0.5)
	await wait_for_sprites()
	await _frames(5)
	await _p1_shot("16_stage_a_cat_waiting", "stage A: cat waiting")
	p = world.player
	for i in 240:
		if Game.cat_joined:
			break
		p.scripted_move = Vector2(1, -0.2)
		await get_tree().physics_frame
	p.scripted_move = Vector2.ZERO
	await _seconds(1.0)
	await _p1_shot("17_cat_joined", "cat joined: %s" % Game.cat_joined)
	# 12. Stage B death in the field -> nearest checkpoint with the cat's rescue behaviour
	_place_player(Vector3(16.0, 0, 3.0), 0.0)
	await _frames(5)
	Game.player_state.take_damage(999)
	while not _busy:
		await _frames(1)
	await _seconds(1.0)
	await _wait_fade_clear()
	await _p1_shot("18_checkpoint_wake_cat", "checkpoint wake with the cat", true)
	while _busy:
		await _frames(1)
	await _seconds(1.0)
	await _p1_shot("19_checkpoint_after", "after wake")
	print("[p1] done: stage %d, hp %d, affection %d, field loot %d" % [Game.story_stage(), Game.player_state.hp, Game.cat_affection, Game.field["loot"].size()])
	get_tree().quit()


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)


## Same flows through simulated key / mouse events (real input path, not direct calls).
func _run_p1_input_tour() -> void:
	Dice.rng.seed = 9
	Game.clock_running = false
	await wait_for_sprites()
	var p: PrototypePlayer = world.player
	_place_player(VisualLab.CRATE_POS + Vector3(0.3, 0, 1.2), 0.0)
	await _frames(5)
	await _key(KEY_E)
	print("[input] E at crate -> panel %s (%s)" % [game_hud._panel_kind, game_hud.panel_open()])
	await _key(KEY_E)
	print("[input] E again -> panel open %s" % game_hud.panel_open())
	await _key(KEY_TAB)
	print("[input] Tab -> panel %s" % game_hud._panel_kind)
	await _key(KEY_TAB)
	print("[input] Tab again -> open %s" % game_hud.panel_open())
	await _key(KEY_G)
	print("[input] G -> log level %d" % Game.combat_log.level)
	var sp0 := Game.player_state.sp
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	Input.parse_input_event(mb)
	await _frames(2)
	mb = mb.duplicate()
	mb.pressed = false
	Input.parse_input_event(mb)
	await _frames(2)
	print("[input] click -> SP %.0f -> %.0f" % [sp0, Game.player_state.sp])
	# camper: get in with E, out with E, must stay out
	_place_player(world.camper.to_global(Vector3(2.5, 0, 2.4)), 0.0)
	await _frames(5)
	await _key(KEY_E)
	await _frames(5)
	print("[input] E at cab -> driving %s" % world.vehicle.driving)
	var veh: CamperVehicle = world.vehicle
	veh.collision_mask = 0  # open-ground key test, the camp is cluttered
	var yaw0 := veh.rotation.y
	await _hold(KEY_W, 40)
	print("[input] hold W -> speed %.1f, heading change %.0f deg (straight ahead)" % [veh.speed, rad_to_deg(angle_difference(yaw0, veh.rotation.y))])
	await _frames(20)
	print("[input] let go -> speed %.2f" % veh.speed)
	yaw0 = veh.rotation.y
	await _hold(KEY_A, 30)
	print("[input] hold A -> nose turned %.0f deg (left = +)" % rad_to_deg(angle_difference(yaw0, veh.rotation.y)))
	yaw0 = veh.rotation.y
	await _hold(KEY_D, 30)
	print("[input] hold D -> nose turned %.0f deg (right = -)" % rad_to_deg(angle_difference(yaw0, veh.rotation.y)))
	await _hold(KEY_S, 40)
	print("[input] hold S -> speed %.1f (reverse)" % veh.speed)
	await _frames(30)
	veh.collision_mask = 1
	await _key(KEY_E)
	await _frames(20)
	print("[input] E while parked in the seat -> driving %s, player visible %s" % [world.vehicle.driving, world.player.visible])
	# door -> interior, door mat -> exterior
	_place_player(world.camper.door_world_position(), 0.0)
	await _frames(5)
	await _key(KEY_E)
	await _frames(10)
	print("[input] E at door -> world %s, cat present %s" % [current_world_id(), world.get("cat") != null])
	await wait_for_sprites()
	await _frames(5)
	await _key(KEY_E)
	await _frames(10)
	print("[input] E at door mat -> world %s" % current_world_id())
	await _key(KEY_F9)
	print("[input] F9 -> stage %d camper visible %s" % [Game.story_stage(), world.vehicle.visible])
	await _key(KEY_ESCAPE)
	print("[input] ESC -> paused %s" % get_tree().paused)
	await _key(KEY_ESCAPE)
	print("[input] ESC -> paused %s" % get_tree().paused)
	get_tree().quit()


## Cat follow smoothness: walk / pause / walk / run with the cat trailing; prints speed jitter and
## how often the pose flips between walking and sitting.
func _run_cat_follow_check() -> void:
	_touring = true
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	var p: PrototypePlayer = world.player
	_place_player(Vector3(-1.0, 0, 5.6), 0.0)
	var cat: CatCompanion = world.cat
	cat.global_position = p.global_position + Vector3(-1.5, 0, 0)
	await _frames(10)
	var plan := [[Vector2(1, 0), false, 3.0], [Vector2.ZERO, false, 1.5], [Vector2(1, -0.3), false, 3.0], [Vector2(1, -0.6), true, 2.0], [Vector2.ZERO, false, 1.5]]
	var speeds: Array[float] = []
	var rels: Array[Vector2] = []
	var flips := 0
	var last_walk := false
	var frames := 0
	for step: Array in plan:
		p.scripted_move = step[0]
		p.scripted_running = step[1]
		var t := 0.0
		while t < step[2]:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			frames += 1
			speeds.append(cat._speed_now)
			if cat.sprite and p.sprite:
				var b := Basis.from_euler(Vector3(deg_to_rad(-cat.sprite.sheet.pitch), 0, 0)).inverse()
				var rel := (b * cat.sprite.global_position - b * p.sprite.global_position) / cat.sprite.sheet.texel
				rels.append(Vector2(roundf(rel.x), roundf(rel.y)))
			var still: Variant = cat.get("_still_t")
			var walk: bool = (still as float) < 0.4 if still != null else cat._speed_now > 0.15
			if walk != last_walk:
				flips += 1
			last_walk = walk
	p.scripted_move = Vector2.ZERO
	var f := FileAccess.open(_capture_dir.path_join("cat_speeds.txt"), FileAccess.WRITE)
	if f:
		for v in speeds:
			f.store_line("%.3f" % v)
	var jerk := 0.0
	for i in range(1, speeds.size()):
		jerk += absf(speeds[i] - speeds[i - 1])
	# Steady walk (first segment after catching up): how often does the cat's on-screen offset
	# from the player change, and how often does it step back to the previous value (jitter)?
	var changes := 0
	var backsteps := 0
	for i in range(60, mini(175, rels.size())):
		if rels[i] != rels[i - 1]:
			changes += 1
			if i >= 2 and rels[i] == rels[i - 2]:
				backsteps += 1
	print("[cat] steady walk: offset changes %d, back-and-forth %d (frames 60-175)" % [changes, backsteps])
	print("[cat] frames %d, walk/sit flips %d, mean |dv| per frame %.3f m/s, final gap %.2f m" % [frames, flips, jerk / speeds.size(), cat.global_position.distance_to(p.global_position)])
	get_tree().quit()


## Wind check: raw low-res frames with the player idle at camp, wind on then off.
## Run with --fixed-fps 30 so TIME advances evenly.
func _run_wind_check() -> void:
	_touring = true
	hud.set_capture_mode(true, "")
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	# Away from the campfire (its flickering light changes many pixels every frame).
	_place_player(Vector3(-13.0, 0, 8.5), PI * 0.8)
	await _frames(10)
	for mode in [["on", 1.0, 90], ["off", 0.0, 30]]:
		StylizedMaterials.set_wind(mode[1])
		for i in mode[2]:
			await RenderingServer.frame_post_draw
			render.viewport.get_texture().get_image().save_png(_capture_dir.path_join("%s_%03d.png" % [mode[0], i]))
	StylizedMaterials.set_wind(1.0)
	await _frames(2)
	print("[wind] saved")
	get_tree().quit()


# ---------------------------------------------------------------- driving comparison

## Runs one manoeuvre: phases = [[seconds, scripted input, stop_when Callable or null], ...].
## Returns per-physics-frame samples [t, x, z, yaw, speed].
func _drive_phases(v: CamperVehicle, phases: Array) -> Array:
	var samples := []
	var t := 0.0
	for ph: Array in phases:
		v.scripted = ph[1]
		var el := 0.0
		while el < ph[0]:
			await get_tree().physics_frame
			var dt := get_physics_process_delta_time()
			el += dt
			t += dt
			samples.append([t, v.global_position.x, v.global_position.z, v.rotation.y, v.speed])
			if ph.size() > 2 and ph[2] is Callable and (ph[2] as Callable).call():
				break
	v.scripted = {}
	return samples


func _drive_reset(v: CamperVehicle, pos: Vector3, yaw: float, mask: int) -> void:
	v.scripted = {"brake": true}
	v.speed = 0.0
	v.collision_mask = mask
	v.global_position = pos
	v.rotation.y = yaw
	await get_tree().physics_frame
	await get_tree().physics_frame


## Same W/S/A/D manoeuvres with the legacy car controller and the heading controller (the
## default); writes trajectories (drive_<control>_<test>.txt) and prints the key numbers.
func _run_drive_compare() -> void:
	_touring = true
	hud.set_capture_mode(true, "")
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	var v: CamperVehicle = world.vehicle
	world.player.set_driving(true)
	v.driving = true
	world.camera.target = v
	var open_pos := Vector3(20.0, 0.0, 30.0)
	var north := PI * 0.5
	var west := PI
	var W := {"throttle": 1.0, "steer": 0.0}
	var S := {"throttle": -1.0, "steer": 0.0}
	var WA := {"throttle": 1.0, "steer": 1.0}
	var NONE := {"throttle": 0.0, "steer": 0.0}
	var only := 1 << 5  # test walls live on their own layer (the field has trees)
	for control in [CamperVehicle.DriveMode.LEGACY, CamperVehicle.DriveMode.HEADING]:
		v.control = control
		var cname: String = "legacy" if control == CamperVehicle.DriveMode.LEGACY else "heading"
		var cruise := func() -> bool: return v.speed >= 5.9
		var tests := {}
		await _drive_reset(v, open_pos, 0.0, 0)
		tests["start"] = await _drive_phases(v, [[6.0, W, func() -> bool: return v.speed >= 5.0]])
		await _drive_reset(v, open_pos, 0.0, 0)
		await _drive_phases(v, [[6.0, W, cruise]])
		tests["turn90"] = await _drive_phases(v, [[8.0, WA, func() -> bool: return absf(angle_difference(v.rotation.y, north)) < deg_to_rad(5.0)]])
		await _drive_reset(v, open_pos, 0.0, 0)
		await _drive_phases(v, [[6.0, W, cruise]])
		tests["uturn"] = await _drive_phases(v, [[10.0, WA, func() -> bool: return absf(angle_difference(v.rotation.y, west)) < deg_to_rad(5.0)]])
		await _drive_reset(v, open_pos, 0.0, 0)
		await _drive_phases(v, [[6.0, W, cruise]])
		tests["brake"] = await _drive_phases(v, [[6.0, S, func() -> bool: return v.speed <= 0.05]])
		await _drive_reset(v, open_pos, 0.0, 0)
		await _drive_phases(v, [[6.0, W, cruise]])
		tests["release"] = await _drive_phases(v, [[8.0, NONE, func() -> bool: return absf(v.speed) <= 0.05]])
		# wall ahead: S to back off 1 s, then W+A to go north
		var wall := ProtoMesh.static_box_collider(world, Vector3(0.6, 4.0, 14.0), open_pos + Vector3(9.0, 1.0, 0.0))
		wall.collision_layer = only
		await _drive_reset(v, open_pos, 0.0, only)
		await _drive_phases(v, [[2.5, W]])
		var hit := v.global_position
		tests["escape"] = await _drive_phases(v, [[1.0, S], [2.5, WA]])
		print("[drive] %s wall: S 1 s then W+A 2.5 s -> moved %.1f m, heading %.0f" % [cname, v.global_position.distance_to(hit), rad_to_deg(v.rotation.y)])
		wall.queue_free()
		# dead-end corridor (no room to turn): S to back out 3 s, then W+A
		var walls := []
		for spec in [[Vector3(0.0, 1.0, -1.75), Vector3(12.0, 4.0, 0.4)], [Vector3(0.0, 1.0, 1.75), Vector3(12.0, 4.0, 0.4)], [Vector3(6.2, 1.0, 0.0), Vector3(0.4, 4.0, 3.9)]]:
			var w := ProtoMesh.static_box_collider(world, spec[1], open_pos + Vector3(2.0, 0.0, 0.0) + spec[0])
			w.collision_layer = only
			walls.append(w)
		await _drive_reset(v, open_pos + Vector3(3.5, 0.0, 0.0), 0.0, only)
		tests["corridor"] = await _drive_phases(v, [[3.2, S], [2.5, WA]])
		print("[drive] %s dead-end corridor: S 3.2 s then W+A -> end %s heading %.0f" % [cname, v.global_position - open_pos, rad_to_deg(v.rotation.y)])
		for w in walls:
			w.queue_free()
		for key: String in tests:
			var f := FileAccess.open(_capture_dir.path_join("drive_%s_%s.txt" % [cname, key]), FileAccess.WRITE)
			for smp: Array in tests[key]:
				f.store_line("%.4f %.4f %.4f %.4f %.4f" % smp)
	v.control = CamperVehicle.DriveMode.HEADING
	await _drive_reset(v, Vector3(8.0, 0.0, 4.0), 0.0, 1)
	await _drive_phases(v, [[1.0, W], [0.6, WA]])
	v.scripted = NONE
	await _frames(4)
	print("[tour] saved ", save_screenshot("drive_heading.png"))
	get_tree().quit()

func _hold(code: Key, frames: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in frames:
		await get_tree().physics_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().physics_frame


func _hold_with(held: Key, extra: Key, frames: int) -> void:
	var a := InputEventKey.new()
	a.physical_keycode = held
	a.pressed = true
	Input.parse_input_event(a)
	var b := InputEventKey.new()
	b.physical_keycode = extra
	b.pressed = true
	Input.parse_input_event(b)
	for i in frames:
		await get_tree().physics_frame
	for e: InputEventKey in [a.duplicate(), b.duplicate()]:
		e.pressed = false
		Input.parse_input_event(e)
	await get_tree().physics_frame


# ---------------------------------------------------------------- P2-1 growth tour

## Kill slimes for general EXP, open the character sheet with a real C key press, level up,
## spend stat points and learn a basic skill; prints derived values before/after.
func _run_p2_tour() -> void:
	_touring = true
	Dice.rng.seed = 11
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	Game.combat_log.level = 2
	await wait_for_sprites()
	var st := Game.player_state
	var p: PrototypePlayer = world.player
	_place_player(Vector3(12.0, 0, 5.0), -PI * 0.5)
	await _frames(10)
	var kills := 0
	var shot := false
	for n in 6:
		if st.can_level_up() and kills >= 4:
			break
		var target := _nearest_monster(p.global_position)
		if target == null:
			break
		var swings := 0
		while is_instance_valid(target) and swings < 40:
			var d := target.global_position - p.global_position
			d.y = 0
			if d.length() > 1.2:
				p.scripted_move = Vector2(d.x, d.z).normalized()
				await get_tree().physics_frame
				continue
			p.scripted_move = Vector2.ZERO
			p.start_attack(target.global_position)
			swings += 1
			await _seconds(0.12)
			if not shot and swings == 2:
				shot = true
				await _p1_shot("p2_01_sword_swing", "sword swing", true)
			await _seconds(0.33)
			st.sp = st.max_sp()
			st.hp = st.max_hp()
		if not is_instance_valid(target):
			kills += 1
	p.scripted_move = Vector2.ZERO
	print("[p2] kills %d, Lv %d, EXP %d / %d, can level up %s" % [kills, st.level, st.gen_exp, st.exp_to_next(), st.can_level_up()])
	await _frames(20)
	await _p1_shot("p2_02_hud_levelup_ready", "HUD: level-up ready")
	_touring = false  # let the real key events through
	await _key(KEY_C)
	print("[p2] C -> panel %s" % game_hud._panel_kind)
	await _p1_shot("p2_03_character_panel", "character panel")
	var before := "HP %d SP %d carry %.0f mult %.1f hit %d crit %d" % [st.max_hp(), st.max_sp(), st.carry_capacity(), st.str_multiplier(), st.total_hit_bonus(), st.total_crit_chance()]
	var leveled := st.level_up()
	st.add_stat("STR")
	st.add_exp(30)
	st.learn_skill("accuracy")
	game_hud._refresh_panel()
	await _frames(3)
	var after := "HP %d SP %d carry %.0f mult %.1f hit %d crit %d" % [st.max_hp(), st.max_sp(), st.carry_capacity(), st.str_multiplier(), st.total_hit_bonus(), st.total_crit_chance()]
	print("[p2] level_up %s -> Lv %d, points %d, STR %d, accuracy rank %d" % [leveled, st.level, st.stat_points, st.stats["STR"], st.skill_rank("accuracy")])
	print("[p2] before: %s" % before)
	print("[p2] after:  %s" % after)
	print("[p2] combat profile hit bonus %d, phys %s" % [st.combat_profile()["hit_bonus"], st.combat_profile()["phys"]])
	await _p1_shot("p2_04_after_levelup", "after level-up + STR + skill")
	await _key(KEY_C)
	print("[p2] C again -> panel open %s" % game_hud.panel_open())
	get_tree().quit()


# ---------------------------------------------------------------- P2-2 equipment tour

func _equip_now(fn: Callable, label: String) -> void:
	var p: PrototypePlayer = world.player
	var st := Game.player_state
	var armor0 := st.total_armor()
	var gear0 := PlayerState.gear_key(st.visual_gear())
	var ok := p.begin_gear_change(fn, label)
	await _seconds(0.3)
	var mid := "armor %d gear %s" % [st.total_armor(), PlayerState.gear_key(st.visual_gear())]
	while p.is_swapping():
		await _frames(1)
	print("[gear] %s: started %s | before armor %d gear %s | at 0.3 s %s | after armor %d gear %s" % [
		label, ok, armor0, gear0, mid, st.total_armor(), PlayerState.gear_key(st.visual_gear())])


func _run_gear_tour() -> void:
	_touring = true
	Dice.rng.seed = 21
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	Game.combat_log.level = 3
	var st := Game.player_state
	# 1. camper storage: armour, shield, cap
	Game.request_world(Game.WORLD_INTERIOR)
	await wait_for_sprites()
	for id in ["leather_armor", "wooden_shield", "leather_cap"]:
		game_hud._move(Game.storage, st.inventory, id, 1, game_hud._player_can_take)
	await _equip_now(func() -> void: st.equip("leather_armor"), "가죽 갑옷 장착")
	await _equip_now(func() -> void: st.equip("wooden_shield"), "나무 방패 장착")
	await _equip_now(func() -> void: st.equip("leather_cap"), "가죽 모자 장착")
	await wait_for_sprites()
	_place_player(Vector3(0.6, 0, 0.4), PI * 0.75)
	game_hud.toggle_inventory()
	await _p1_shot("gear_01_inventory_equipped", "inventory with armour + shield")
	game_hud.close_panel()
	await _p1_shot("gear_02_shield_sprite_interior", "shield on the sprite")
	# 2. field: crate -> flame longsword (two-handed), ring, necklace
	Game.request_world(Game.WORLD_EXTERIOR)
	await wait_for_sprites()
	var crate: LootContainer = null
	for n in world.get_children():
		if n is LootContainer and n.data["id"] == "camp_crate":
			crate = n
	for id in ["flame_longsword", "strength_ring", "luck_necklace"]:
		game_hud._move(crate.inventory(), st.inventory, id, 1, game_hud._player_can_take)
	var str0 := st.stat("STR")
	await _equip_now(func() -> void: st.equip("strength_ring"), "힘의 반지 장착")
	await _equip_now(func() -> void: st.equip("luck_necklace"), "행운의 목걸이 장착")
	print("[gear] STR %d -> %d, crit %d%%, carry %.0f" % [str0, st.stat("STR"), st.total_crit_chance(), st.carry_capacity()])
	await _equip_now(func() -> void: st.equip("flame_longsword"), "불꽃 장검 장착")
	print("[gear] two-handed: main %s off '%s', bag has shield %d iron sword %d" % [st.equipment["main"], st.equipment["off"], st.inventory.count("wooden_shield"), st.inventory.count("iron_sword")])
	await wait_for_sprites()
	# 3. fight with the longsword; armour shows in the slime's hits on the player
	var p: PrototypePlayer = world.player
	_place_player(Vector3(12.0, 0, 5.0), -PI * 0.5)
	await _frames(10)
	var target := _nearest_monster(p.global_position)
	var shot := false
	for i in 30:
		if not is_instance_valid(target):
			break
		var d := target.global_position - p.global_position
		d.y = 0
		while d.length() > 1.3 and is_instance_valid(target):
			p.scripted_move = Vector2(d.x, d.z).normalized()
			await get_tree().physics_frame
			d = target.global_position - p.global_position
			d.y = 0
		p.scripted_move = Vector2.ZERO
		if not is_instance_valid(target):
			break
		p.start_attack(target.global_position)
		await _seconds(0.12)
		if not shot:
			shot = true
			await _p1_shot("gear_03_longsword_swing", "flame longsword swing", true)
		await _seconds(0.33)
		st.sp = st.max_sp()
		st.hp = st.max_hp()
	for e in Game.combat_log.entries:
		if e["detail"].contains("화염") or e["detail"].contains("방어"):
			print("[gear] log: ", e["detail"])
	# 4. off-hand item while two-handed -> the two-hander goes back to the bag
	await _equip_now(func() -> void: st.equip("wooden_shield"), "나무 방패 장착 (양손 무기 해제)")
	print("[gear] after shield: main '%s' off %s, bag longsword %d" % [st.equipment["main"], st.equipment["off"], st.inventory.count("flame_longsword")])
	await _equip_now(func() -> void: st.equip("iron_sword"), "철검 장착")
	# 5. belt off -> lantern can't be used
	Game.lantern_on = true
	await _equip_now(func() -> void: st.unequip("belt"), "등불 허리띠 해제")
	print("[gear] belt off: has_lantern %s lantern_on %s" % [st.has_lantern(), Game.lantern_on])
	await _equip_now(func() -> void: st.equip("lantern_belt"), "등불 허리띠 장착")
	# 6. random option piece
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var gid := ItemDB.acquire("leather_gloves", rng, 1.0)
	st.inventory.add(gid, 1)
	var hit0 := st.total_hit_bonus()
	await _equip_now(func() -> void: st.equip(gid), "장갑 장착")
	print("[gear] random option piece %s = '%s' (%s), armor now %d, hit %d -> %d" % [gid, ItemDB.item_name(gid), ItemDB.equip_summary(gid), st.total_armor(), hit0, st.total_hit_bonus()])
	await wait_for_sprites()
	_place_player(Vector3(-1.0, 0, 4.6), PI * 0.75)
	game_hud.toggle_inventory()
	await _p1_shot("gear_04_inventory_field", "inventory after swaps")
	game_hud.close_panel()
	get_tree().quit()


# ---------------------------------------------------------------- P2-3 consumables tour

func _run_items_tour() -> void:
	Dice.rng.seed = 5
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	Game.combat_log.level = 2
	await wait_for_sprites()
	var st := Game.player_state
	var p: PrototypePlayer = world.player
	var crate: LootContainer = null
	for n in world.get_children():
		if n is LootContainer and n.data["id"] == "camp_crate":
			crate = n
	for id in ["heal_potion", "mana_potion", "stamina_potion", "spellbook_minor_heal"]:
		game_hud._move(crate.inventory(), st.inventory, id, 9, game_hud._player_can_take)
	st.inventory.add("bread", 1)
	# open ground away from the camp props
	_place_player(Vector3(6.0, 0, 9.0), 0.0)
	await _frames(10)
	# 1. potion from quickslot 1 (real key): applies only at the end of the motion
	st.hp = 15.0
	var n0 := st.inventory.count("heal_potion")
	await _key(KEY_1)
	await _seconds(0.4)
	print("[items] key 1 -> using %s '%s', at 0.4 s HP %d, potions %d" % [p.is_using(), p.use_label(), st.hp, st.inventory.count("heal_potion")])
	await _p1_shot("items_01_drinking", "drinking (progress in the prompt)", true)
	while p.is_using():
		await _frames(1)
	print("[items] after motion: HP %d, potions %d -> %d" % [st.hp, n0, st.inventory.count("heal_potion")])
	# 2. a hit during use cancels it: no effect, potion kept
	st.hp = 15.0
	n0 = st.inventory.count("heal_potion")
	await _key(KEY_1)
	await _seconds(0.3)
	var test_hit := {"name": "시험 공격", "hit_bonus": 100, "crit_chance": 0, "phys": "1d1", "str_mult": 1.0, "ac": 10, "armor": 0}
	p.receive_attack(test_hit, world.camper)
	await _seconds(1.0)
	print("[items] hit while drinking -> using %s, HP %d (15 - hit), potions %d -> %d" % [p.is_using(), st.hp, n0, st.inventory.count("heal_potion")])
	await _seconds(0.6)
	# 3. movement while eating (stand still) vs drinking (half speed)
	var start := p.global_position
	p.begin_use_item("bread")
	p.scripted_move = Vector2(1, 0)
	await _seconds(1.0)
	var eat_move := p.global_position.distance_to(start)
	await _p1_shot("items_02_eating", "eating", true)
	while p.is_using():
		await _frames(1)
	start = p.global_position
	p.begin_use_item("heal_potion")
	await _seconds(0.6)
	var drink_move := p.global_position.distance_to(start)
	while p.is_using():
		await _frames(1)
	start = p.global_position
	await _seconds(0.6)
	var walk_move := p.global_position.distance_to(start)
	p.scripted_move = Vector2.ZERO
	print("[items] moved in 0.6-1 s: eating %.2f m, drinking %.2f m (0.6 s), walking %.2f m (0.6 s)" % [eat_move, drink_move, walk_move])
	# 4. spellbook -> learn -> skill quickslot 5 -> cast (MP, cooldown)
	p.begin_use_item("spellbook_minor_heal")
	while p.is_using():
		await _frames(1)
	print("[items] spells %s, skill slots %s" % [st.spells, st.quick_skills])
	st.hp = 10.0
	var mp0 := st.mp
	await _key(KEY_5)
	await _seconds(0.5)
	await _p1_shot("items_03_casting", "casting minor heal", true)
	while p.is_using():
		await _frames(1)
	print("[items] key 5 cast -> HP %d (10 + 12), MP %d -> %d, cooldown %.1f" % [st.hp, mp0, st.mp, st.cooldowns.get("minor_heal", 0.0)])
	await _key(KEY_5)
	print("[items] key 5 again at once -> casting %s (cooldown)" % p.is_using())
	await _p1_shot("items_04_quickbar_cooldown", "quickbar with cooldown")
	game_hud.toggle_inventory()
	await _p1_shot("items_05_inventory", "inventory consumable buttons")
	game_hud.close_panel()
	game_hud.toggle_character()
	await _p1_shot("items_06_character_spells", "character panel spells")
	game_hud.close_panel()
	get_tree().quit()


# ---------------------------------------------------------------- P2-4 shop tour

func _run_shop_tour() -> void:
	Dice.rng.seed = 8
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	var p: PrototypePlayer = world.player
	for kv in [["slime_jelly", 5], ["slime_core", 2], ["mana_shard", 1], ["leather_cap", 1]]:
		st.inventory.add(kv[0], kv[1])
	var rosa_stall: Vector3 = VisualLab.TRADE_STALLS[0][0]
	var bron_stall: Vector3 = VisualLab.TRADE_STALLS[1][0]
	_place_player(Vector3(-22.9, 0, 7.6), 0.0)
	await _frames(20)
	await _p1_shot("shop_01_trade_post_day", "trade post by day, merchants at the stalls")
	# general store via the real E key
	_place_player(rosa_stall + Vector3(0, 0, 1.5), 0.0)
	await _frames(5)
	await _key(KEY_E)
	print("[shop] E at rosa -> panel %s" % game_hud._panel_kind)
	await _p1_shot("shop_02_rosa_panel", "general store panel")
	print("[shop] sell prices rosa: jelly %d, core %d (0 = won't buy), shard %d, cap %d" % [ShopDB.sell_price("rosa", "slime_jelly"), ShopDB.sell_price("rosa", "slime_core"), ShopDB.sell_price("rosa", "mana_shard"), ShopDB.sell_price("rosa", "leather_cap")])
	print("[shop] sell prices bron: jelly %d, core %d, shard %d, cap %d, iron ore %d (rosa %d)" % [ShopDB.sell_price("bron", "slime_jelly"), ShopDB.sell_price("bron", "slime_core"), ShopDB.sell_price("bron", "mana_shard"), ShopDB.sell_price("bron", "leather_cap"), ShopDB.sell_price("bron", "iron_ore"), ShopDB.sell_price("rosa", "iron_ore")])
	var g0 := st.gold
	for i in 5:
		ShopDB.sell("rosa", "slime_jelly")
	var why := ShopDB.buy("rosa", "heal_potion", 25)
	print("[shop] sold 5 jelly, bought a potion ('%s'): gold %d -> %d, potion stock %d" % [why, g0, st.gold, ShopDB.stock_left("rosa", "heal_potion")])
	game_hud.close_panel()
	# blacksmith: specialist buys rare goods; upgrade the sword
	_place_player(bron_stall + Vector3(0, 0, 1.5), 0.0)
	await _frames(5)
	await _key(KEY_E)
	g0 = st.gold
	ShopDB.sell("bron", "slime_core")
	ShopDB.sell("bron", "slime_core")
	ShopDB.sell("bron", "mana_shard")
	ShopDB.sell("bron", "leather_cap")
	print("[shop] sold cores, shard, cap to the blacksmith: gold %d -> %d" % [g0, st.gold])
	var ok := st.enhance_equipped("main")
	print("[shop] upgrade sword: %s -> '%s' (%s), phys bonus %d, gold %d" % [ok, ItemDB.item_name(st.equipment["main"]), ItemDB.equip_summary(st.equipment["main"]), st.combat_profile()["phys_bonus"], st.gold])
	game_hud._refresh_panel()
	await _frames(3)
	await _p1_shot("shop_03_blacksmith_panel", "blacksmith panel with upgrade")
	game_hud.close_panel()
	var res := Combat.resolve(st.combat_profile().merged({"hit_bonus": 100}, true), {"name": "허수아비", "ac": 1, "armor": 0})
	print("[shop] hit with the +1 sword: %s" % res["detail"])
	# restock: buy out potions, +1 day -> refilled; equipment needs 3 days
	st.gold = 2000
	while ShopDB.buy("rosa", "heal_potion", 25) == "":
		pass
	ShopDB.buy("bron", "leather_armor", 95)
	print("[shop] bought out: potions %d, armour %d" % [ShopDB.stock_left("rosa", "heal_potion"), ShopDB.stock_left("bron", "leather_armor")])
	Game.advance_minutes(1440.0)
	ShopDB.restock("rosa")
	ShopDB.restock("bron")
	print("[shop] +1 day: potions %d (1-day cycle), armour %d (3-day cycle)" % [ShopDB.stock_left("rosa", "heal_potion"), ShopDB.stock_left("bron", "leather_armor")])
	Game.advance_minutes(1440.0 * 2)
	ShopDB.restock("bron")
	print("[shop] +3 days: armour %d" % ShopDB.stock_left("bron", "leather_armor"))
	# hours: closing time -> merchants walk home and disappear; the counter refuses
	Game.minute_of_day = 19.9 * 60.0
	await _frames(5)
	_place_player(Vector3(-22.9, 0, 7.6), 0.0)
	Game.minute_of_day = 20.0 * 60.0 + 1.0
	await _seconds(1.0)
	var rosa: Npc = world.npcs[0]
	print("[shop] 20:00 -> rosa %s, visible %s" % [Npc.Where.keys()[rosa.where], rosa.visible])
	await _p1_shot("shop_04_closing_walk_home", "closing: rosa walks home", true)
	await _seconds(5.0)
	print("[shop] later -> rosa %s, visible %s; bron %s" % [Npc.Where.keys()[rosa.where], rosa.visible, Npc.Where.keys()[world.npcs[1].where]])
	_place_player(rosa_stall + Vector3(0, 0, 1.5), 0.0)
	await _frames(5)
	print("[shop] prompt at closed stall: '%s'" % p.focus.prompt_text())
	await _key(KEY_E)
	print("[shop] E at closed stall -> panel '%s'" % game_hud._panel_kind)
	Game.minute_of_day = 8.0 * 60.0 + 1.0
	await _seconds(4.0)
	print("[shop] 08:00 -> rosa %s, visible %s" % [Npc.Where.keys()[rosa.where], rosa.visible])
	get_tree().quit()
