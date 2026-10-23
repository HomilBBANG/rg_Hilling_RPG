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
var title: TitleScreen
var pause_menu: PauseMenu
## GDD 17 [미정] autosave interval (real seconds of play), see IMPLEMENTATION_ASSUMPTIONS.md.
const AUTOSAVE_SECONDS := 300.0
var _autosave_t := 0.0
var _arriving := false


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
	_consume_pending_start()
	_load_world(Game.start_world)
	pause_menu = PauseMenu.new()
	pause_menu.boot = self
	pause_menu.theme = game_hud.theme
	pause_menu.visible = false
	layer.add_child(pause_menu)
	title = TitleScreen.new()
	title.boot = self
	title.theme = game_hud.theme
	title.visible = false
	layer.add_child(title)
	var playtest := FileAccess.file_exists(PLAYTEST_PATH)
	var tour := _cmd_tour()
	_parse_args()
	_check_dialogue_playtest()
	if Game.boot_note != "":
		_arrive()
	elif Game.slot == 0 and tour == "" and not playtest:
		show_title()


## The dialogue editor's "게임에서 실행" writes this file and starts the game: play that dialogue
## in the real dialogue box with the live game state (the editor never edits saves).
const PLAYTEST_PATH := "user://dialogue_playtest.json"


func _check_dialogue_playtest() -> void:
	if not FileAccess.file_exists(PLAYTEST_PATH):
		return
	var d: Variant = DialogueData.read_json(PLAYTEST_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAYTEST_PATH))
	if not d is Dictionary:
		return
	await wait_for_sprites()
	await _frames(10)
	if d.has("cutscene_id"):  # the editor's 컷씬 tab
		var cid := str(d["cutscene_id"])
		hud.toast("대화 에디터에서 실행: " + cid)
		if cid == "story.new_game":
			await play_new_game_story()
		elif CutsceneRunner.info(cid).is_empty():
			hud.toast("컷씬 파일을 찾을 수 없다: " + cid)
		else:
			await game_hud.cutscene.play(cid)
		return
	var id := str(d.get("dialogue_id", ""))
	hud.toast("대화 에디터에서 실행: " + id)
	if not game_hud.start_dialogue(id):
		hud.toast("대화 파일을 찾을 수 없다: " + id)


# ---------------------------------------------------------------- save slots

## Applies what the title screen / pause menu asked for before the scene was rebuilt.
func _consume_pending_start() -> void:
	var ps: Dictionary = Game.pending_start
	if ps.is_empty():
		return
	Game.pending_start = {}
	var slot := int(ps.get("slot", 0))
	var data := SaveManager.read(slot) if slot > 0 and not ps.get("new", false) else {}
	if data.has("state"):
		SaveManager.apply_state(data["state"])
		Game.start_world = StringName(str(data.get("world", Game.WORLD_EXTERIOR)))
		if Game.start_world == Game.WORLD_INTERIOR and not Game.has_camper:
			Game.start_world = Game.WORLD_EXTERIOR
		Game.spawn_override = {"kind": "load", "pos": data["pos"], "yaw": float(data["yaw"])}
		Game.slot = slot
		Game.boot_note = "load"
		return
	SaveManager.apply_state({})
	Game.start_world = Game.WORLD_EXTERIOR
	Game.slot = slot if ps.get("new", false) else 0
	if Game.slot > 0:
		# a new character arrives alone (GDD 2.1/2.3): no cat, no camper yet — stage A.
		# Tours and test runs keep the stage-C test defaults.
		Game.has_camper = false
		Game.cat_joined = false
	Game.boot_note = "new" if Game.slot > 0 else ""


## Fade in after a slot was chosen; a new game claims its slot with a first save right away.
func _arrive() -> void:
	var note := Game.boot_note
	Game.boot_note = ""
	_arriving = true
	get_tree().paused = true  # no game time or monster passes behind the loading screen
	game_hud.fade_to(1.0, 0.01, "불러오는 중…")
	await wait_for_sprites()
	await _frames(6)
	get_tree().paused = false
	if note == "new":
		save_game("new")
	if note == "new" and _cmd_tour() == "" and not CutsceneData.new_game_cutscenes().is_empty():  # tours skip the story
		# the story takes over from the loading screen: its first cutscene fades in from black
		game_hud.overlay.fade_rect.modulate.a = 1.0
		await game_hud.fade_to(0.0, 0.01)
		_arriving = false
		await play_new_game_story()
		save_game("story")
		hud.toast("슬롯 %d — 새 캐릭터로 시작했다" % Game.slot)
		return
	await game_hud.fade_to(0.0, 0.6)
	hud.toast("슬롯 %d — %s" % [Game.slot, "새 캐릭터로 시작했다" if note == "new" else "이어하기 · %d일차 %s" % [Game.day, Game.clock_text()]])
	_arriving = false


## data/story.json "new_game": the cutscenes a new game opens with, played back to back (each
## but the last ends on black so the next fades in). Skipping one (ESC) moves on to the next.
func play_new_game_story() -> void:
	var ids: Array = CutsceneData.new_game_cutscenes()
	for i in ids.size():
		await game_hud.cutscene.play(str(ids[i]), i < ids.size() - 1)
	Game.narrative.set_flag("story.new_game_seen")


func title_open() -> bool:
	return title != null and title.visible


## Title, pause menu or the loading fade covers the game.
func menu_open() -> bool:
	return title_open() or _arriving or (pause_menu != null and pause_menu.visible)


func show_title() -> void:
	game_hud.close_panel()
	hud.show_help_panel(false)
	game_hud.visible = false  # the title is its own screen (the scene is rebuilt when it closes)
	hud.visible = false
	pause_menu.visible = false
	get_tree().paused = true
	title.refresh()
	title.visible = true


## Title screen choice: the scene is rebuilt and the new bootstrap applies the slot (see above).
func start_slot(slot: int, new_game: bool) -> void:
	if new_game == SaveManager.exists(slot) or (not new_game and not SaveManager.read(slot).has("state")):
		return  # new games only go into empty slots; broken files can only be deleted
	Game.pending_start = {"slot": slot, "new": new_game}
	title.visible = false
	game_hud.visible = true  # for the loading fade
	await game_hud.fade_to(1.0, 0.35, "불러오는 중…")
	get_tree().paused = false
	get_tree().reload_current_scene()


func to_title() -> void:
	Game.pending_start = {"slot": 0}
	get_tree().paused = false
	get_tree().reload_current_scene()


func set_paused(on: bool) -> void:
	get_tree().paused = on
	pause_menu.visible = on
	if on:
		pause_menu.open()


## "" when the game can be saved right now, else why not (GDD 17 [미정] save rules).
func save_block() -> String:
	if Game.slot <= 0:
		return "저장 슬롯이 없다 (테스트 실행)"
	if _busy:
		return "지금은 저장할 수 없다 (이동·수면·기상 중)"
	if Game.in_run():
		return "변덕의 미궁 안에서는 저장할 수 없다 — 출구로 나가면 자동 저장"
	if game_hud.dialogue_active() or game_hud.cutscene.playing:
		return "대화 중에는 저장할 수 없다"
	if game_hud.fishing.active:
		return "낚시 중에는 저장할 수 없다"
	if world is VisualLab and world.vehicle.driving:
		return "운전 중에는 저장할 수 없다 — 차를 세우고 내리자"
	var p: PrototypePlayer = world.get("player") if world else null
	if p == null or p.dead or p.is_using():
		return "동작 중에는 저장할 수 없다"
	return ""


## Writes this character's slot. kind: "manual" | "auto" | "new". Returns "" or why not.
func save_game(kind := "manual") -> String:
	var why := save_block()
	if why != "":
		return why
	if world is VisualLab:
		world._save_parking()
	var p: PrototypePlayer = world.player
	if not SaveManager.write(Game.slot, SaveManager.capture(String(current_world_id()), p.global_position, p.facing_yaw())):
		return "저장 실패 — 파일을 쓸 수 없다"
	_autosave_t = 0.0
	game_hud.show_save_note({"manual": "저장했다", "auto": "자동 저장", "new": "새 캐릭터 저장"}.get(kind, "저장") + " — 슬롯 %d" % Game.slot)
	return ""


func _autosave() -> void:
	if save_block() == "":
		save_game("auto")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not title_open():
		_autosave()


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
	if world_id == Game.WORLD_EXTERIOR and prev == Game.WORLD_INTERIOR:
		Game.region = str(Game.camper.get("region", Game.region))  # step out where the camper is parked
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
	if _touring or not event.is_pressed() or event.is_echo() or title_open() or _arriving:
		return
	if _busy and not event.is_action("pause"):
		return
	# Dialogue / cutscene own the keys while open (ESC still pauses).
	if not event.is_action("pause") and game_hud.fishing.active:
		game_hud.fishing.handle_key(event)
		return
	if not event.is_action("pause") and (game_hud.dialogue_active() or game_hud.cutscene.playing):
		if game_hud.dialogue_active():
			game_hud.dialogue.handle_key(event)
		else:
			game_hud.cutscene.handle_key(event)
		return
	# placing camper decor: E place / R turn / X cancel go to the interior (ESC still pauses)
	if not event.is_action("pause") and world is CamperInteriorLab and world.placing():
		if world.handle_place_key(event):
			return
	if event.is_action("pause") and game_hud.cutscene.playing and game_hud.cutscene.skippable:
		game_hud.cutscene.skip_all()  # ESC skips a skippable cutscene instead of pausing
		return
	if event.is_action("pause"):
		set_paused(not get_tree().paused)
	elif event.is_action("inventory"):
		game_hud.toggle_inventory()
	elif event.is_action("character"):
		game_hud.toggle_character()
	elif event.is_action("journal"):
		game_hud.toggle_journal()
	elif event.is_action("world_map"):
		game_hud.toggle_map()
	elif event.is_action("crafting"):
		game_hud.toggle_crafting()
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
	elif event.is_action("toggle_interior") and Game.in_run():
		hud.toast("미궁에서는 출구를 찾아야 나갈 수 있다")
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

func _cmd_tour() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour="):
			return a.trim_prefix("--tour=")
	return ""


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
	elif tour == "quest":
		_run_quest_tour()
	elif tour == "region":
		_run_region_tour()
	elif tour == "dungeon":
		_run_dungeon_tour()
	elif tour == "rift":
		_run_rift_tour()
	elif tour == "life":
		_run_life_tour()
	elif tour == "craft":
		_run_craft_tour()
	elif tour == "save":
		_run_save_tour()
	elif tour == "run":
		_run_run_tour()
	elif tour == "dialogue":
		_run_dialogue_tour()
	elif tour == "cutscene":
		_run_cutscene_tour()
	elif tour == "world":
		_run_world_tour()
	elif tour == "camper":
		_run_camper_tour()
	elif tour == "king":
		_run_king_tour()
	elif tour == "dragonroad":
		_run_dragon_road_tour()
	elif tour == "dragon":
		_run_dragon_tour()
	elif tour == "wish":
		_run_wish_tour()
	elif tour == "upgrades":
		_run_upgrades_tour()
	elif tour == "drive":
		_run_drive_compare()
	elif tour == "drivegta":
		_run_drive_gta_tour()
	elif tour == "preset":
		_run_preset_tour()
	elif tour == "collide":
		_run_collide_tour()
	elif tour == "monsterai":
		_run_monster_ai_tour()
	elif tour == "catmeet":
		_run_cat_meet_tour()
	elif tour == "expressions":
		_run_expressions_tour()
	elif tour == "statui":
		_run_stat_ui_tour()
	elif tour == "invui":
		_run_inv_ui_tour()
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
		if not is_instance_valid(p):  # walked through an exit: that world is gone
			return
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

func _process(delta: float) -> void:
	if Game.slot > 0 and not get_tree().paused:
		_autosave_t += delta
		if _autosave_t >= AUTOSAVE_SECONDS:
			_autosave()
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


func is_busy() -> bool:
	return _busy


## Road exit (GDD 11.1 [확정]): loading screen, then the other region. Driving through takes the
## camper along (parked at the arrival point); on foot the camper stays where it was (9.4).
func travel(to_region: String, entry_id: String, driving: bool) -> void:
	if _busy or not RegionDB.all().has(to_region):
		return
	_busy = true
	game_hud.close_panel()
	var info := RegionDB.info(to_region)
	var tips: Array = info.get("tips", [])
	var tip: String = str(tips[randi() % tips.size()]) if not tips.is_empty() else ""
	var title: String = info.get("name", to_region)
	if RegionDB.is_random_dungeon(to_region) and Game.in_run():
		title += " %d층" % int(Game.run["floor"])
	await game_hud.fade_to(1.0, 0.6, "%s\n위험도 %s\n\n%s" % [title, RegionDB.danger_text(to_region), tip])
	var e := RegionDB.entry(to_region, entry_id)
	if driving and world is VisualLab:
		world._leaving_with_camper = true
		world.vehicle.driving = false
		Game.camper = {"region": to_region, "pos": RegionDB.v3(e.get("camper_pos", e.get("pos", [0, 0]))), "yaw": float(e.get("camper_yaw", 0.0))}
	Game.spawn_override = {"kind": "drive_in" if driving else "walk_in", "pos": RegionDB.v3(e.get("pos", [0, 0])), "yaw": float(e.get("yaw", 0.0))}
	var from := Game.region
	Game.region = to_region
	Game.request_world(Game.WORLD_EXTERIOR)
	await _frames(3)
	await wait_for_sprites()
	await _frames(8)
	Game.combat_log.add("%s → %s" % [RegionDB.region_name(from), info.get("name", to_region)], "지역 이동%s — %s (위험도 %s)" % [
		" (캠핑카와 함께)" if driving else " (캠핑카는 %s에)" % RegionDB.region_name(str(Game.camper.get("region", ""))) if Game.has_camper else "",
		info.get("name", to_region), RegionDB.danger_text(to_region)], "info")
	await game_hud.fade_to(0.0, 0.6)
	var arrive := "%s — 위험도 %s" % [info.get("name", to_region), RegionDB.danger_text(to_region)]
	if RegionDB.is_dungeon(to_region) and not Game.lantern_on and str(info.get("style", "")) not in ["hall", "lair"]:
		arrive += (" · 어둡다 — L로 등불을 켜자" if Game.player_state.has_lantern() else " · 어둡다 — 횃불 빛을 따라가자")
	hud.toast(arrive)
	_busy = false
	_autosave()


# ---------------------------------------------------------------- fast travel (GDD 11.4)

## Pace of fast travel ([미정] distance → time / fare formulas, IMPLEMENTATION_ASSUMPTIONS.md).
const FAST_MIN_PER_M := 0.6         # by paid carriage: game minutes per map metre
const FAST_CAMPER_MIN_PER_M := 0.3  # driving the camper
const FAST_FARE_BASE := 10
const FAST_FARE_PER_M := 0.08


## The town the player is standing in (and has visited), or "".
func current_city() -> String:
	if not (world is VisualLab) or world.is_dungeon():
		return ""
	var at: Vector3 = world.vehicle.global_position if world.vehicle.driving else world.player.global_position
	for ct: Dictionary in world.cities:
		if (ct["rect"] as Rect2).grow(4.0).has_point(Vector2(at.x, at.z)) and Game.discovered.has("city:" + str(ct["id"])):
			return str(ct["id"])
	return ""


## Whether / how the player can fast-travel to a town right now: {ok, why, from, from_name,
## distance (map m), minutes, gold, with_camper}. Only between visited major towns; with the camper
## when it is owned and parked in this region (free), otherwise by paid carriage.
func fast_travel_quote(city_id: String) -> Dictionary:
	var cities := RegionDB.cities()
	if not cities.has(city_id):
		return {"ok": false, "why": "그런 도시는 없다"}
	if not Game.discovered.has("city:" + city_id):
		return {"ok": false, "why": "아직 가 보지 않은 도시다"}
	if Game.in_run() or (world is VisualLab and world.is_dungeon()):
		return {"ok": false, "why": "던전 안에서는 빠른 이동을 할 수 없다"}
	if not (world is VisualLab):
		return {"ok": false, "why": "밖에서만 빠른 이동을 할 수 있다"}
	var from := current_city()
	if from == "":
		return {"ok": false, "why": "가 본 도시 안에서만 출발할 수 있다 (도시끼리만 빠른 이동)"}
	if from == city_id:
		return {"ok": false, "why": "지금 이 도시에 있다"}
	if world.vehicle.driving:
		return {"ok": false, "why": "캠핑카에서 내려서 지도를 다시 열자"}
	var dist: float = (cities[from]["map"] as Vector2).distance_to(cities[city_id]["map"])
	var camper := Game.has_camper and str(Game.camper.get("region", "")) == Game.region
	var fuel := 0.0 if Game.camper_infinite_power else dist * CamperUpgrades.fuel_per_m()
	var camper_note := ""
	if camper and Game.camper_broken():  # GDD 9.5: broken -> no fast travel with the camper
		camper = false
		camper_note = "캠핑카가 고장나 함께 갈 수 없다 — 마차로"
	elif camper and Game.camper_fuel < fuel:  # GDD 11.4: not enough fuel -> can't start with it
		camper = false
		camper_note = "캠핑카 연료가 모자란다 (필요 %.0f L, 남은 %.0f L) — 마차로" % [fuel, Game.camper_fuel]
	var q := {"ok": true, "why": "", "from": from, "from_name": cities[from]["name"], "distance": dist, "with_camper": camper,
		"fuel": fuel if camper else 0.0, "camper_note": camper_note,
		"minutes": dist * (FAST_CAMPER_MIN_PER_M if camper else FAST_MIN_PER_M), "gold": 0 if camper else FAST_FARE_BASE + roundi(dist * FAST_FARE_PER_M)}
	if not camper and Game.player_state.gold < int(q["gold"]):
		q["ok"] = false
		q["why"] = "마차 삯 %d 골드가 모자란다" % int(q["gold"])
	return q


## Skips the trip (GDD 11.4 [확정]: real travel left out, game time passes by distance). With the
## camper both arrive and it is parked at the town's arrival parking spot.
func fast_travel(city_id: String) -> String:
	var q := fast_travel_quote(city_id)
	if not q.get("ok", false) or _busy:
		return str(q.get("why", "지금은 이동할 수 없다"))
	_busy = true
	var ct: Dictionary = RegionDB.cities()[city_id]
	game_hud.close_panel()
	var hours := WorldMap._hours(float(q["minutes"]))
	await game_hud.fade_to(1.0, 0.6, "%s(으)로 이동 중…
%s

%s" % [ct["name"], hours, "캠핑카와 함께" if q["with_camper"] else "마차 삯 %d 골드" % int(q["gold"])])
	if not q["with_camper"]:
		Game.player_state.gold -= int(q["gold"])
	else:
		Game.use_camper_fuel(float(q["fuel"]))
	Game.advance_minutes(float(q["minutes"]))
	var arr: Dictionary = ct["arrival"]
	if q["with_camper"]:
		var pk: Dictionary = ct["parking"]
		Game.camper = {"region": ct["region"], "pos": RegionDB.v3(pk.get("pos", arr.get("pos", [0, 0]))), "yaw": float(pk.get("yaw", 0.0))}
	Game.spawn_override = {"kind": "fast_travel", "pos": RegionDB.v3(arr.get("pos", [0, 0])), "yaw": float(arr.get("yaw", 0.0))}
	var from_name := RegionDB.region_name(Game.region)
	Game.region = str(ct["region"])
	Game.request_world(Game.WORLD_EXTERIOR)
	await _frames(3)
	await wait_for_sprites()
	await _frames(8)
	Game.combat_log.add("빠른 이동 → %s" % ct["name"], "빠른 이동: %s → %s (%s, %s)" % [from_name, ct["name"], hours,
		"캠핑카와 함께" if q["with_camper"] else "마차 삯 %d 골드" % int(q["gold"])], "info")
	await game_hud.fade_to(0.0, 0.6)
	hud.toast("%s 도착 — %s 지났다" % [ct["name"], hours])
	_busy = false
	_autosave()
	return ""


# ---------------------------------------------------------------- camper fuel / repair items (GDD 9.3 / 9.5)

## Uses a camper item from the bag ("fuel_can" = refuel, "repair_kit" = emergency repair). It has
## to be done beside the camper. Returns what happened (shown as a toast).
func use_camper_item(id: String) -> String:
	var info := ItemDB.info(id)
	var st := Game.player_state
	if st.inventory.count(id) <= 0:
		return "가방에 없다"
	if not Game.has_camper:
		return "아직 캠핑카가 없다"
	if not (world is VisualLab) or not world.camper_here() or not world.player_near_camper():
		return "캠핑카 곁에서 써야 한다"
	var amount := float(info.get("amount", 10.0))
	var cmax := Game.camper_fuel_max()
	match str(info.get("camper", "")):
		"fuel":
			if Game.camper_infinite_power:
				return "영구 마력 핵이 있어 연료가 필요 없다"
			if str(info.get("fuel_kind", "gasoline")) != CamperUpgrades.fuel_kind():
				return "마력 변환 엔진에는 마력 연료병을 넣어야 한다" if CamperUpgrades.fuel_kind() == "magic" else "휘발유 엔진에는 휘발유를 넣어야 한다"
			if Game.camper_fuel >= cmax - 0.5:
				return "연료 탱크가 가득 차 있다"
			Game.camper_fuel = minf(cmax, Game.camper_fuel + amount)
			st.inventory.remove(id, 1)
			Game.combat_log.add("주유 +%d" % roundi(amount), "%s 1개를 넣었다 — %s %d/%d" % [info["name"], CamperUpgrades.fuel_name(), roundi(Game.camper_fuel), roundi(cmax)], "info")
			return "주유했다 — %s %d/%d" % [CamperUpgrades.fuel_name(), roundi(Game.camper_fuel), roundi(cmax)]
		"repair":
			# GDD 9.5: the kit alone = emergency fix up to 30; with the advanced skill = full repair
			var full := CamperUpgrades.full_field_repair()
			var to := Game.CAMPER_DURABILITY_MAX if full else amount
			if Game.camper_durability >= to:
				return "고칠 곳이 없다" if full else "응급 수리는 내구도가 %d 아래일 때만 — 완전 수리는 대장간에서 (고급 정비 기술이 있으면 현장에서)" % roundi(amount)
			Game.camper_durability = to
			st.inventory.remove(id, 1)
			var what := "현장 완전 수리" if full else "응급 복구"
			Game.combat_log.add("캠핑카 %s" % what, "수리 공구로 캠핑카를 손봤다 (%s) — 내구도 %d/%d" % [what, roundi(Game.camper_durability), roundi(Game.CAMPER_DURABILITY_MAX)], "info")
			return "%s — 내구도 %d/%d" % [what, roundi(Game.camper_durability), roundi(Game.CAMPER_DURABILITY_MAX)]
	return "쓸 수 없는 물건"


## Full repair by the smith (GDD 9.5: an NPC mechanic for gold). He comes out to the camper, so it
## has to be parked in this region.
const REPAIR_GOLD_PER_POINT := 2


func camper_repair_quote() -> Dictionary:
	var missing := ceili(Game.CAMPER_DURABILITY_MAX - Game.camper_durability)
	if not Game.has_camper:
		return {"ok": false, "why": "캠핑카가 없다", "gold": 0}
	if missing <= 0:
		return {"ok": false, "why": "고칠 곳이 없다", "gold": 0}
	if str(Game.camper.get("region", "")) != Game.region:
		return {"ok": false, "why": "캠핑카가 이 지역에 없다 (%s에 세워 둠)" % RegionDB.region_name(str(Game.camper.get("region", ""))), "gold": missing * REPAIR_GOLD_PER_POINT}
	var gold := missing * REPAIR_GOLD_PER_POINT
	if Game.player_state.gold < gold:
		return {"ok": false, "why": "골드가 모자란다 (%d 골드)" % gold, "gold": gold}
	return {"ok": true, "why": "", "gold": gold}


func repair_camper() -> String:
	var q := camper_repair_quote()
	if not q["ok"]:
		return str(q["why"])
	Game.player_state.gold -= int(q["gold"])
	Game.camper_durability = Game.CAMPER_DURABILITY_MAX
	Game.combat_log.add("캠핑카 수리 (-%d 골드)" % int(q["gold"]), "대장간 브론이 캠핑카를 완전히 고쳤다 — 내구도 %d/%d" % [roundi(Game.camper_durability), roundi(Game.CAMPER_DURABILITY_MAX)], "info")
	return "캠핑카를 완전히 고쳤다 (-%d 골드)" % int(q["gold"])


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
	var rift_lost := {}
	var in_rift: bool = world is VisualLab and world.is_random_dungeon()
	if in_rift:
		# GDD 12.2: everything found during this run is lost; the return place follows 12.3
		# (camper, or the checkpoint near the dungeon's entrance - the floors themselves vanish).
		var ent: Dictionary = world.region.get("entrance", {})
		rift_lost = Game.end_run(false)
		Game.region = str(ent.get("region", RegionDB.START))
		for c: Dictionary in RegionDB.info(Game.region).get("checkpoints", []):
			if c["id"] == ent.get("return_checkpoint", ""):
				cp = {"name": c["name"], "pos": RegionDB.v3(c["pos"])}
	elif world is VisualLab:
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
		var p: Vector3 = cp.get("pos", world.player.global_position if world is VisualLab else VisualLab.DEFAULT_SPAWN)
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
	if in_rift:
		var lost_names := PackedStringArray()
		for id: String in rift_lost:
			lost_names.append("%s ×%d" % [ItemDB.item_name(id), rift_lost[id]])
		detail = "미궁에서 쓰러져 이번 탐험의 전리품을 모두 잃었다%s" % (": " + ", ".join(lost_names) if not lost_names.is_empty() else " (얻은 것이 없었다)")
	Game.combat_log.add(where, "%s — %s" % [where, detail], "info")
	await game_hud.fade_to(0.0, 1.2)
	hud.toast(where)
	await _frames(150)
	hud.toast(detail)
	_busy = false
	_autosave()  # the death outcome sticks: reloading cannot undo it


## Camper sleep (GDD 9.6 / 10.1 [확정]): chosen hours pass; HP back by the bed's share of max
## (간이침대 10 % → 소파 베드 40 % → 침대 75 %, [임시]); SP / MP fully.
func sleep(hours: int, bonus := 0.0) -> void:
	if _busy:
		return
	_busy = true
	await game_hud.fade_to(1.0, 0.9, "zzz…")
	Game.advance_minutes(hours * 60.0)
	var st := Game.player_state
	var before := st.hp
	var bed := CamperUpgrades.bed_info()
	st.heal(st.max_hp() * (float(bed.get("hp", 0.1)) + bonus))
	# GDD 9.4: parked somewhere dangerous, monsters may scratch the camper while you sleep
	var scratched := 0.0
	var creg := str(Game.camper.get("region", ""))
	var danger := int(RegionDB.info(creg).get("danger", 1))
	if world is CamperInteriorLab and danger >= 2 and not RegionDB.spot_safe(creg, Game.camper.get("pos", Vector3.ZERO)):
		for h in hours:
			if randf() < 0.12 * danger:
				scratched += 3.0
		Game.damage_camper(scratched)
	st.sp = st.max_sp()
	st.mp = st.max_mp()
	st.changed.emit()
	await _frames(20)
	await game_hud.fade_to(0.0, 0.9)
	var msg := "%s에서 %d시간 잤다 — %s · HP +%d" % [bed.get("name", "간이침대"), hours, Game.clock_text(), roundi(st.hp - before)]
	hud.toast(msg)
	Game.combat_log.add(msg, "", "info")
	if scratched > 0.0:
		var warn := "자는 동안 몬스터가 캠핑카를 긁어 댔다 — 내구도 -%d (%d/%d). 위험한 곳에 세워 두었다" % [roundi(scratched), ceili(Game.camper_durability), roundi(Game.CAMPER_DURABILITY_MAX)]
		Game.combat_log.add(warn, "", "hurt")
		await _frames(120)
		hud.toast(warn)
	_busy = false
	_autosave()


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
	var walk_t := 0.0
	while is_instance_valid(target) and swings < 40 and walk_t < 20.0:
		var d := target.global_position - p.global_position
		d.y = 0
		# slimes are solid now: one that joined the fight can stand in the way — hit whatever is closest
		var near := _nearest_monster(p.global_position)
		if near and Vector2(near.global_position.x - p.global_position.x, near.global_position.z - p.global_position.z).length() < 1.3:
			d = near.global_position - p.global_position
			d.y = 0
			target = near if d.length() < 1.3 else target
		if d.length() > 1.3:
			p.scripted_move = Vector2(d.x, d.z).normalized()
			await get_tree().physics_frame
			walk_t += get_physics_process_delta_time()
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
		if game_hud.dialogue_active():  # the roadside meeting scene + dialogue (keys go through)
			_touring = false
			await _talk_through(["pet"], "[p1]", 400)
			_touring = true
			continue
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


## Bodies that must not be walked through (user request): the hero pushes for 2 s straight at a
## villager, a slime, the cat, the camper, a tree, a big rock and a building and must stop at
## its surface; a slime hopping at the hero stops too; the cat steps aside.
## Stage A on the road: the hero walks up to the waiting cat -> in-game scene (letterbox, the cat
## walks over, they face each other) + dialogue; the hero can't move while it runs; afterwards
## the cat follows. Meeting it again doesn't replay the scene.
func _run_cat_meet_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 10.0 * 60.0
	Game.set_story_stage(0)
	await _frames(5)
	_place_player(Vector3(1.0, 0, 5.4), -PI * 0.5)
	await wait_for_sprites()
	await _frames(5)
	var p: PrototypePlayer = world.player
	var cat: CatCompanion = world.cat
	print("[catmeet] stage A: cat mode %s, joined %s, meeting seen %s" % [CatCompanion.Mode.keys()[cat.mode], Game.cat_joined, Game.narrative.event_done(CatCompanion.MEET_EVENT)])
	await _p1_shot("catmeet_01_waiting", "the cat waits on the road", true)
	var aff0 := Game.cat_affection
	var t := 0.0
	while not game_hud.dialogue_active() and t < 6.0:
		p.scripted_move = Vector2(1, -0.2)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	p.scripted_move = Vector2.ZERO
	print("[catmeet] walked %.1f s -> dialogue '%s' open %s at %.1f m from the cat" % [t, game_hud.dialogue.dialogue_id, game_hud.dialogue_active(),
		Vector2(cat.global_position.x - p.global_position.x, cat.global_position.z - p.global_position.z).length()])
	# held still: the movement keys do nothing while the scene / dialogue runs
	await _frames(20)
	var p0 := p.global_position
	Input.action_press("move_right")
	Input.action_press("move_up")
	await _seconds(1.2)
	var cut_on: bool = game_hud.cutscene.playing
	await _p1_shot("catmeet_02_scene", "in-game scene: letterbox, the cat walks over", true)
	Input.action_release("move_right")
	Input.action_release("move_up")
	print("[catmeet] during the scene (cutscene playing %s): controls %s, hero moved %.2f m holding W+D -> %s" % [cut_on, p.controls_enabled,
		Vector2(p.global_position.x - p0.x, p.global_position.z - p0.z).length(), "정지 ✔" if not p.controls_enabled and p.global_position.distance_to(p0) < 0.05 else "움직임 ✘"])
	var shots := 0
	var said := PackedStringArray()
	for i in 600:
		if not game_hud.dialogue_active():
			break
		var ev: Dictionary = game_hud.dialogue.event
		match ev.get("type", ""):
			"line":
				if shots < 1:
					Input.action_press("move_left")
					await _seconds(0.5)
					Input.action_release("move_left")
					print("[catmeet] dialogue line, holding A 0.5 s: controls %s, hero moved %.2f m" % [p.controls_enabled, Vector2(p.global_position.x - p0.x, p.global_position.z - p0.z).length()])
					await _p1_shot("catmeet_03_line", "dialogue: the cat's first line", true)
					shots += 1
				said.append("%s: %s" % [ev["name"], str(ev["text"]).split("\n")[0]])
				await _key(KEY_E)
			"choice":
				await _p1_shot("catmeet_04_choice", "choice: pet it / say sorry", true)
				said.append("[선택 쓰다듬기]")
				var idx := 0
				for j in ev["options"].size():
					if ev["options"][j]["port"] == "pet":
						idx = j
				await _key(KEY_1 + idx)
			_:
				await _frames(5)
	print("[catmeet]   %s" % " | ".join(said))
	await _frames(10)
	print("[catmeet] after: joined %s, affection %d -> %d, event done %s, cat mode %s, controls %s" % [Game.cat_joined, aff0, Game.cat_affection,
		Game.narrative.event_done(CatCompanion.MEET_EVENT), CatCompanion.Mode.keys()[cat.mode], p.controls_enabled])
	# walk off: it follows
	t = 0.0
	while t < 3.0:
		p.scripted_move = Vector2(-1, 0.3)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	p.scripted_move = Vector2.ZERO
	await _seconds(1.0)
	print("[catmeet] walked off 3 s: cat %.1f m behind, mode %s" % [Vector2(cat.global_position.x - p.global_position.x, cat.global_position.z - p.global_position.z).length(),
		CatCompanion.Mode.keys()[cat.mode]])
	await _p1_shot("catmeet_05_following", "the cat follows", true)
	# the meeting is once: back on the road with a fresh roadside cat, no dialogue
	Game.cat_joined = false
	world._spawn_cat(false)
	await _frames(5)
	_place_player(VisualLab.CAT_ENCOUNTER_POS + Vector3(-2.0, 0, 0.5), 0.0)
	await _seconds(2.0)
	print("[catmeet] met again (meeting seen): dialogue %s, joined %s (walks up and joins)" % [game_hud.dialogue_active(), Game.cat_joined])
	var dv := DialogueData.validate(DialogueData.load_dialogue(CatCompanion.MEET_DIALOGUE))
	var cv := CutsceneData.validate(CutsceneData.load_cutscene("cutscene.cat.meeting"))
	print("[catmeet] data check: dialogue issues %d %s, cutscene issues %d" % [dv.size(), dv.map(func(e: Dictionary) -> String: return str(e.get("message", ""))), cv.size()])
	get_tree().quit()


## Monster AI graphs: slimes are 비선공 by default — they leave the hero alone, fight back when hit,
## and their own species doesn't answer the call; the 선공 graph (old behaviour) still works.
func _run_monster_ai_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 11.0 * 60.0
	await wait_for_sprites()
	var p: PrototypePlayer = world.player
	var st := Game.player_state
	var a: SlimeMonster = null
	var b: SlimeMonster = null
	for m in world.monsters:
		if a == null:
			a = m
		elif b == null and m.kind == a.kind:
			b = m
	for m in world.monsters:
		print("[monsterai] %s (%s) aggressive %s, graph %s, loaded %s" % [m.display_name, m.kind, m.aggressive, m.ai_id, not m._ai.is_empty()])
		if m != a and m != b:
			m.set_physics_process(false)  # only the two under test move
			m.global_position += Vector3(0, 0, 200)
	b.global_position = a.global_position + Vector3(3.0, 0, 0)
	b.home = Vector3(b.global_position.x, 0, b.global_position.z)
	# 1) passive: the hero stands next to it for 6 s
	_place_player(a.global_position + Vector3(0, 0, 2.2), 0.0)
	st.restore_all()
	var hp0 := st.hp
	await _seconds(6.0)
	print("[monsterai] passive, hero 2.2 m away for 6 s: %s state %s provoked %s, hero HP %d -> %d -> %s" % [a.display_name,
		SlimeMonster.State.keys()[a.state], a.provoked, roundi(hp0), roundi(st.hp), "공격 안 함 ✔" if st.hp >= hp0 and not a.provoked else "공격함 ✘"])
	await _p1_shot("monsterai_01_passive", "passive slime ignores the hero", true)
	# 2) hit it: it fights back, its neighbour of the same species stays out
	a.receive_attack(st.combat_profile(), p)
	hp0 = st.hp
	var b_fought := false
	var t := 0.0
	while t < 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		b_fought = b_fought or b.provoked
		if st.hp < st.max_hp() * 0.3:
			st.restore_all()
	print("[monsterai] after a hit: %s provoked %s state %s, hero hit %s; same species %s 3 m away joined %s -> %s" % [a.display_name, a.provoked,
		SlimeMonster.State.keys()[a.state], st.hp < hp0 or a._cooldown > 0.0, b.display_name, b_fought, "반격만, 동족 합류 없음 ✔" if a.provoked and not b_fought else "✘"])
	await _p1_shot("monsterai_02_fights_back", "hit slime fights back, neighbour stays out", true)
	# 3) the hero walks away: it gives up and goes home
	_place_player(a.home + Vector3(0, 0, 30.0), 0.0)
	await _seconds(11.0)
	print("[monsterai] hero left: %s provoked %s state %s, %.1f m from home" % [a.display_name, a.provoked, SlimeMonster.State.keys()[a.state],
		Vector2(a.global_position.x - a.home.x, a.global_position.z - a.home.z).length()])
	# 4) switch both to the 선공 graph (what "aggressive": true / the editor does): spotted + joined
	var g := MonsterAI.load_graph("ai.slime.aggressive")
	for m in [a, b]:
		m._ai = g
		m.provoked = false
		m.state = SlimeMonster.State.WANDER
		m.global_position = m.home
	await _seconds(1.0)
	_place_player(b.global_position + Vector3(0, 0, 3.0), 0.0)
	st.restore_all()
	var a_joined := false
	t = 0.0
	while t < 5.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		a_joined = a_joined or a.provoked
	print("[monsterai] 선공 graph: %s spotted the hero %s, %s answered the call %s -> %s" % [b.display_name, b.provoked, a.display_name, a_joined,
		"선공 + 동족 합류 ✔" if b.provoked and a_joined else "✘"])
	await _p1_shot("monsterai_03_aggressive", "aggressive graph: spots and calls allies", true)
	# 5) a graph with an error falls back to the built-in rules (and says so)
	var bad := {"nodes": [{"id": "start", "type": "start", "next": "nowhere"}]}
	print("[monsterai] broken graph check: %s" % [MonsterAI.validate(bad).map(func(e: Dictionary) -> String: return e["message"])])
	get_tree().quit()


func _run_collide_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 11.0 * 60.0
	await wait_for_sprites()
	var p: PrototypePlayer = world.player
	var push := func(from: Vector3, toward: Vector3, secs := 2.0) -> float:
		_place_player(from, 0.0)
		await get_tree().physics_frame
		var t := 0.0
		while t < secs:
			var d := Vector2(toward.x - p.global_position.x, toward.z - p.global_position.z)
			p.scripted_move = d.normalized() if d.length() > 0.05 else Vector2.ZERO
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		p.scripted_move = Vector2.ZERO
		return Vector2(toward.x - p.global_position.x, toward.z - p.global_position.z).length()
	var report := func(what: String, gap: float, need: float) -> void:
		print("[collide] %s: stopped %.2f m from its centre (body edge %.2f) -> %s" % [what, gap, need, "막힘 ✔" if gap >= need - 0.05 else "뚫고 지나감 ✘"])
	var rosa: Npc = world._npc_for("rosa")
	var rp := rosa.global_position
	report.call("villager (Rosa, from the side)", await push.call(rp + Vector3(3.0, 0, 0), rp), 0.66)
	var slime: SlimeMonster = null
	for m in world.monsters:
		if m.kind == "meadow_slime":
			slime = m
			break
	slime.set_physics_process(false)  # hold it still for the push (its body stays in the world)
	var sp := slime.global_position
	report.call("slime", await push.call(sp + Vector3(2.5, 0, 0), sp), SlimeMonster.RADIUS * slime.body_scale + 0.3)
	slime.set_physics_process(true)
	var vp: Vector3 = world.vehicle.global_position
	var side: Vector3 = world.vehicle.global_transform.basis.z.normalized()
	report.call("camper (far side)", await push.call(vp - side * 4.0, vp), CamperExterior.WIDTH * 0.5 + 0.3)
	report.call("tree (broadleaf trunk)", await push.call(Vector3(-12.2, 0, 7.0), Vector3(-12.2, 0, 4.2)), 0.36 * 1.45 + 0.3)
	report.call("big rock", await push.call(Vector3(-1.0, 0, -2.6), Vector3(-1.0, 0, -5.6)), 0.8 + 0.3)
	report.call("shed (building)", await push.call(Vector3(-19.0, 0, 17.5), Vector3(-19.0, 0, 13.0)), 1.3 + 0.3)
	# the cat: solid, and it makes room when walked into
	var cat: CatCompanion = world.cat
	if cat:
		_place_player(Vector3(6.0, 0, 6.0), 0.0)
		await _frames(2)
		cat.global_position = Vector3(6.0, 0, 4.6)
		cat.mode = CatCompanion.Mode.FOLLOW
		var c0 := cat.global_position
		var gap: float = await push.call(Vector3(6.0, 0, 6.0), Vector3(6.0, 0, 2.0), 1.5)
		var overlap := p.global_position.distance_to(cat.global_position)
		print("[collide] cat in the way: hero walked %.2f m, cat moved aside %.2f m, never overlapped %s (now %.2f m apart)" % [
			6.0 - p.global_position.z, Vector2(cat.global_position.x - c0.x, cat.global_position.z - c0.z).length(), overlap > 0.4, overlap])
	# a slime hopping at the hero stops at its body (and still lands its hit)
	var aggro: SlimeMonster = null
	for m in world.monsters:
		if m.state != SlimeMonster.State.DEAD:
			aggro = m
			break
	if aggro:
		_place_player(aggro.global_position + Vector3(2.0, 0, 0), 0.0)
		aggro.engage()
		var closest := 9.0
		for i in 240:
			await get_tree().physics_frame
			closest = minf(closest, Vector2(aggro.global_position.x - p.global_position.x, aggro.global_position.z - p.global_position.z).length())
		print("[collide] %s attacking: closest %.2f m (body edges %.2f), hero HP %d/%d" % [aggro.display_name, closest, SlimeMonster.RADIUS * aggro.body_scale + 0.3,
			roundi(Game.player_state.hp), roundi(Game.player_state.max_hp())])
	await _p1_shot("collide_01_villager_blocked", "standing against a solid villager", true)
	get_tree().quit()


## The chapter-1 save preset: put into an empty slot 3 once, kept out after a delete, put back
## from the load screen, then loaded and checked (story, cat, camper, hero, the nest). Uses
## user://tour_saves, never the real slots.
func _run_preset_tour() -> void:
	_touring = true
	SaveManager.dir = "user://tour_saves"
	SavePresets.marker = "user://tour_saves/presets.cfg"
	var t: Dictionary = Game.get_meta("preset_tour", {"step": 0})
	Game.set_meta("preset_tour", t)
	var step := int(t["step"])
	t["step"] = step + 1
	await _frames(5)
	while _arriving:
		await get_tree().process_frame
	await wait_for_sprites()
	hud.show_help_panel(false)
	var st := Game.player_state
	match step:
		0:
			for i in range(1, SaveManager.SLOTS + 1):
				SaveManager.delete(i)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SavePresets.marker))
			var gold_before := st.gold
			SavePresets.auto_install()
			var d := SaveManager.read(3)
			print("[preset] auto install -> slot 3 %s: %s · live state untouched %s" % [SaveManager.exists(3), d.get("meta", {}), st.gold == gold_before])
			SaveManager.delete(3)
			SavePresets.auto_install()
			print("[preset] deleted, title again -> slot 3 refilled %s (should stay empty)" % SaveManager.exists(3))
			show_title()
			title.open_slots("load")
			await _frames(6)
			print("[tour] saved ", save_screenshot("p1_preset_01_load_screen_empty3.png"))
			SavePresets.install("chapter1", 3)
			title.open_slots("load")
			await _frames(6)
			print("[tour] saved ", save_screenshot("p1_preset_02_load_screen.png"))
			start_slot(3, false)
		1:
			print("[preset] loaded slot %d: %s, stage %s, cat joined %s (affection %d), camper here %s at %s" % [Game.slot, Game.region,
				Game.STAGE_NAMES[Game.story_stage()], Game.cat_joined, Game.cat_affection, world.camper_here(), Game.camper.get("pos", "")])
			print("[preset] quests: audience %s, dragon %s · events king %s wish %s · flags dragon %s camper %s" % [Game.quests.state("quest.main.audience"),
				Game.quests.state("quest.main.dragon"), Game.narrative.event_done("story.king_audience"), Game.narrative.event_done("story.camper_wish"),
				Game.narrative.get_flag("story.dragon_defeated"), Game.narrative.get_flag("story.camper_received")])
			print("[preset] hero: Lv %d, stats %s, HP %d/%d, gold %d, weapon %s, armor %s, scales %d, fang %d" % [st.level, st.stats, roundi(st.hp), roundi(st.max_hp()),
				st.gold, st.equipment.get("main", ""), st.equipment.get("body", ""), st.inventory.count("dragon_scale"), st.inventory.count("dragon_fang")])
			await _seconds(1.0)
			await _p1_shot("preset_03_loaded_plaza", "chapter 1 cleared: plaza, camper, cat", true)
			game_hud.toggle_map()
			await _frames(6)
			await _p1_shot("preset_04_map", "map after chapter 1", true)
			game_hud.toggle_map()
			travel("dragon_nest", "entrance", false)
			await _wait_travel()
			var dragons: int = world.monsters.filter(func(m: SlimeMonster) -> bool: return m is DragonBoss).size()
			print("[preset] the nest: dragons %d, remains %s" % [dragons, Game.field.get("remains", {})])
			Game.remove_meta("preset_tour")
			for i in range(1, SaveManager.SLOTS + 1):
				SaveManager.delete(i)
			get_tree().quit()


## GTA-style driving check (the default HEADING control): gas, W+S hold, S brake → pause →
## slow reverse, W out of reverse, no turning at a standstill, steering forward / in reverse
## (the back swings toward A), letting go.
func _run_drive_gta_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	Game.camper_mods["owned"].append("drive_offroad")  # same grip everywhere for clean numbers
	var v: CamperVehicle = world.vehicle
	world.enter_vehicle()
	await _frames(3)
	var pos := Vector3(20.0, 0.0, 30.0)
	var run := func(input: Dictionary, secs: float, until: Callable = Callable()) -> float:
		v.scripted = input
		var t := 0.0
		while t < secs:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if until.is_valid() and until.call():
				break
		return t
	var W := {"throttle": 1.0, "steer": 0.0}
	var S := {"throttle": -1.0, "steer": 0.0}
	var BOTH := {"brake": true}
	var NONE := {"throttle": 0.0, "steer": 0.0}
	# 1 gas
	await _drive_reset(v, pos, 0.0, 0)
	var t5: float = await run.call(W, 4.0, func() -> bool: return v.speed >= 5.0)
	print("[gta] W from rest: 5 m/s after %.2f s" % t5)
	# 2 W+S: stops and stays put
	await run.call(W, 2.0)
	var tb: float = await run.call(BOTH, 3.0, func() -> bool: return absf(v.speed) <= 0.01)
	var p0 := v.global_position
	await run.call(BOTH, 2.0)
	print("[gta] W+S from %.1f m/s: stopped in %.2f s, then held 2 s -> moved %.2f m" % [v.heading_max_speed, tb, v.global_position.distance_to(p0)])
	# 3 S: brake, pause, slow reverse
	await _drive_reset(v, pos, 0.0, 0)
	await run.call(W, 3.0)
	var ts: float = await run.call(S, 3.0, func() -> bool: return v.speed <= 0.05)
	var tr: float = await run.call(S, 3.0, func() -> bool: return v.speed < -0.05)
	await run.call(S, 2.5)
	print("[gta] S while driving: stopped in %.2f s, reverse starts %.2f s later, reverse speed %.2f m/s" % [ts, tr, -v.speed])
	# 4 W while reversing: brake then forward
	var tw: float = await run.call(W, 3.0, func() -> bool: return v.speed >= -0.05)
	await run.call(W, 1.0)
	print("[gta] W while reversing: stopped in %.2f s, then forward %.2f m/s after 1 s" % [tw, v.speed])
	# 5 standstill steering does nothing
	await _drive_reset(v, pos, 0.0, 0)
	await run.call({"throttle": 0.0, "steer": 1.0}, 1.0)
	print("[gta] A at a standstill 1 s -> heading %.1f deg" % rad_to_deg(v.rotation.y))
	# 6 forward + A: nose turns left
	await run.call(W, 3.0)
	var y0 := v.rotation.y
	await run.call({"throttle": 1.0, "steer": 1.0}, 2.0)
	var rate := absf(angle_difference(y0, v.rotation.y)) / 2.0
	print("[gta] W+A 2 s at %.1f m/s: heading %+.0f deg (left = +), radius %.1f m" % [v.speed, rad_to_deg(angle_difference(y0, v.rotation.y)), v.speed / maxf(rate, 0.001)])
	# 7 reverse + A: the back swings left (toward A), the nose to the right
	await _drive_reset(v, pos, 0.0, 0)
	await run.call(S, 2.5)
	var start := v.global_position
	var left := Vector3(-sin(v.rotation.y), 0, -cos(v.rotation.y))
	y0 = v.rotation.y
	await run.call({"throttle": -1.0, "steer": 1.0}, 2.5)
	await _p1_shot("drive_gta_reverse_left", "reversing with A", true)
	var moved := v.global_position - start
	print("[gta] S+A 2.5 s reversing: heading %+.0f deg, back went %.2f m to the left side (+ = left), %.2f m back" % [
		rad_to_deg(angle_difference(y0, v.rotation.y)), moved.dot(left), -moved.dot(Vector3(cos(y0), 0, -sin(y0)))])
	# 8 let go
	await _drive_reset(v, pos, 0.0, 0)
	await run.call(W, 3.0)
	p0 = v.global_position
	var tc: float = await run.call(NONE, 4.0, func() -> bool: return absf(v.speed) <= 0.01)
	print("[gta] let go at full speed: stops in %.2f s, rolls %.1f m" % [tc, v.global_position.distance_to(p0)])
	v.scripted = {}
	get_tree().quit()


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
		var walk := 0.0
		while is_instance_valid(target) and swings < 40:
			var d := target.global_position - p.global_position
			d.y = 0
			if d.length() > 1.2:
				# slimes are 비선공 now and stay put: walk to them (capped, in case one is blocked off),
				# kept topped up against the ones already fighting back
				walk += get_physics_process_delta_time()
				if walk > 8.0:
					break
				st.hp = st.max_hp()
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


# ---------------------------------------------------------------- the king's quest (main story)

## A fresh character right after the opening (stage A, story seen, "meet the king" active): no cat
## yet, the north road to the capital, the castle door, the throne room, the king's dialogue,
## the dragon quest accepted, and the cat waiting by the road afterwards.
func _run_king_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 11.0 * 60.0
	await wait_for_sprites()
	Game.set_story_stage(0)
	Game.narrative.set_flag("story.new_game_seen")
	Game.quests.accept("quest.main.audience")
	Game.request_world(Game.WORLD_EXTERIOR)
	await _frames(3)
	await wait_for_sprites()
	await _frames(5)
	var derr := DialogueData.validate(DialogueData.load_dialogue("dialogue.story.king_audience"))
	var cerr := CutsceneData.validate(CutsceneData.load_cutscene("cutscene.opening"))
	print("[king] data check: king dialogue %d issues %s, opening cutscene %d issues %s" % [derr.size(), derr, cerr.size(), cerr])
	print("[king] new character: stage %s, audience %s, dragon %s, roadside cat %s" % ["ABC"[Game.story_stage()], Game.quests.state("quest.main.audience"),
		Game.quests.state("quest.main.dragon"), world.cat != null])
	game_hud.toggle_journal()
	await _frames(4)
	await _p1_shot("king_01_journal", "main quest in the journal", true)
	game_hud.toggle_journal()
	# north road -> capital, castle door -> throne room
	travel("capital", "south_road", false)
	await _wait_travel()
	_place_player(Vector3(0, 0, -31), 0.0)
	await _seconds(1.0)
	await _p1_shot("king_02_castle_door", "castle door", true)
	_place_player(Vector3(0, 0, -34.6), 0.0)
	await _seconds(1.2)
	await _wait_travel()
	print("[king] castle door -> %s (%s), player (%.1f, %.1f), king here %s" % [Game.region, world.world_title(), world.player.global_position.x,
		world.player.global_position.z, world._npc_for("") != null])
	await _seconds(0.8)
	await _p1_shot("king_03_throne_room", "throne room", true)
	_place_player(Vector3(0, 0, -5.2), 0.0)
	await _frames(6)
	print("[king] prompt in front of the throne: '%s'" % (world.player.focus.prompt_text() if world.player.focus else ""))
	await _key(KEY_E)
	await _frames(4)
	print("[king] dialogue open %s '%s'" % [game_hud.dialogue_active(), game_hud.dialogue.dialogue_id])
	var shots_at := {"l2": "king_04_player_surprised", "choice": "king_05_choice"}
	var said := PackedStringArray()
	for i in 30:
		if not game_hud.dialogue_active():
			break
		var ev: Dictionary = game_hud.dialogue.event
		await _seconds(0.2)
		if shots_at.has(ev.get("node", "")):
			await _p1_shot(shots_at[ev["node"]], ev["node"], true)
		match ev.get("type", ""):
			"line":
				said.append("%s: %s" % [ev["name"], str(ev["text"]).split("\n")[0]])
				await _key(KEY_E)
			"choice":
				said.append("[선택: 제가요?]" if not said.has("[선택: 제가요?]") else "")
				game_hud.dialogue.choose("me")
				await _frames(3)
			_:
				await _frames(3)
	print("[king]   %s" % " | ".join(said))
	print("[king] after: audience %s, dragon %s, event %s, gold %d, bread %d" % [Game.quests.state("quest.main.audience"), Game.quests.state("quest.main.dragon"),
		Game.narrative.event_done("story.king_audience"), Game.player_state.gold, Game.player_state.inventory.count("bread")])
	await _seconds(1.0)
	await _key(KEY_E)
	await _frames(4)
	print("[king] talk again -> '%s'" % (str(game_hud.dialogue.event.get("text", "")).substr(0, 30)))
	await _key(KEY_E)
	await _frames(6)
	# out of the castle and back to the meadow: the cat is waiting by the road now
	_place_player(Vector3(0, 0, 8.6), PI)
	await _seconds(1.2)
	await _wait_travel()
	print("[king] hall exit -> %s at (%.1f, %.1f)" % [Game.region, world.player.global_position.x, world.player.global_position.z])
	travel("meadow", "north_road", false)
	await _wait_travel()
	print("[king] meadow: roadside cat %s (mode %s)" % [world.cat != null, world.cat.mode if world.cat else -1])
	get_tree().quit()


## The road to the dragon's nest: with the king's quest active, out of the highland's north pass,
## along the whole 잿빛 산길 on foot (monsters held still), past the burnt cart to the nest mouth;
## checks the quest flags, the map marks, the prompt to go down into the nest and the way back.
func _run_dragon_road_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 11.0 * 60.0
	await wait_for_sprites()
	Game.narrative.set_flag("story.new_game_seen")
	Game.quests.accept("quest.main.dragon")
	print("[dragonroad] dragon quest %s: %s" % [Game.quests.state("quest.main.dragon"), " / ".join(Game.quests.objectives_text("quest.main.dragon"))])
	travel("highland", "north_pass", false)
	await _wait_travel()
	print("[dragonroad] highland entry north_pass at (%.1f, %.1f)" % [world.player.global_position.x, world.player.global_position.z])
	_place_player(Vector3(40, 0, -72), 0.0)
	await _seconds(0.8)
	await _p1_shot("dragon_01_highland_north", "highland north pass", true)
	await _walk_to(world.player, Vector2(40, -81.5))
	await _seconds(1.2)
	await _wait_travel()
	print("[dragonroad] north pass -> %s (%s) at (%.1f, %.1f), danger %s" % [Game.region, world.world_title(), world.player.global_position.x,
		world.player.global_position.z, RegionDB.danger_text(Game.region)])
	var kinds := {}
	for m in world.monsters:
		kinds[m.kind] = int(kinds.get(m.kind, 0)) + 1
	print("[dragonroad] monsters %s, pass flag %s" % [kinds, Game.narrative.get_flag("story.pass_reached")])
	await _seconds(0.6)
	await _p1_shot("dragon_02_pass_foot", "foot of the pass", true)
	# walk the whole road with the monsters held still (is it open end to end?)
	for m in world.monsters:
		m.process_mode = Node.PROCESS_MODE_DISABLED
	var road: Array = world.region["terrain"]["paths"][0]
	var t0 := Time.get_ticks_msec()
	var stuck := 0
	for i in range(1, road.size()):
		var goal := Vector2(float(road[i][0]), float(road[i][1]))
		if i == road.size() - 1:
			goal.y += 3.0  # stop in front of the nest mouth
		await _walk_to(world.player, goal)
		var at := Vector2(world.player.global_position.x, world.player.global_position.z)
		if at.distance_to(goal) > 1.0:
			stuck += 1
			print("[dragonroad]   stuck before waypoint %d %s at %s" % [i, goal, at])
			_place_player(Vector3(goal.x, 0, goal.y), 0.0)
		if i == 7:
			await _p1_shot("dragon_03_burnt_cart", "burnt cart", true)
	world.player.scripted_move = Vector2.ZERO
	print("[dragonroad] walked the road in %.1f s, stuck %d, signs flag %s, nest flag %s" % [(Time.get_ticks_msec() - t0) / 1000.0, stuck,
		Game.narrative.get_flag("story.dragon_signs"), Game.narrative.get_flag("story.nest_found")])
	print("[dragonroad] quest now: %s" % " / ".join(Game.quests.objectives_text("quest.main.dragon")))
	await _seconds(0.6)
	await _p1_shot("dragon_04_nest_mouth", "nest mouth", true)
	Game.minute_of_day = 21.5 * 60.0
	await _seconds(0.6)
	await _p1_shot("dragon_05_nest_night", "nest mouth at night", true)
	Game.minute_of_day = 11.0 * 60.0
	_place_player(Vector3(0, 0, -98.0), 0.0)
	await _frames(6)
	print("[dragonroad] prompt at the nest: '%s' (going in: --tour=dragon)" % (world.player.focus.prompt_text() if world.player.focus else ""))
	# ember slimes awake again
	for m in world.monsters:
		m.process_mode = Node.PROCESS_MODE_INHERIT
	var em: SlimeMonster = null
	for m in world.monsters:
		if m.kind == "ember_slime":
			em = m
			break
	if em:
		_place_player(em.global_position + Vector3(0, 0, 4.5), 0.0)
		await _seconds(0.7)
		await _p1_shot("dragon_06_ember_slime", "ember slime", true)
		print("[dragonroad] %s HP %d, aggressive %s" % [em.display_name, em.hp, em.state])
	game_hud.toggle_map()
	await _frames(4)
	game_hud.map_view.center_on_player()
	await _frames(4)
	await _p1_shot("dragon_07_map", "map with the pass", true)
	game_hud.toggle_map()
	# discovered marks are saved
	var keys := PackedStringArray()
	for k in Game.discovered:
		if str(k).begins_with("trig:"):
			keys.append(str(k))
	print("[dragonroad] discovered %s" % [keys])
	# back down the south road
	_place_player(Vector3(0, 0, 104), PI)
	await _walk_to(world.player, Vector2(0, 107.6))
	await _seconds(1.2)
	await _wait_travel()
	print("[dragonroad] south road -> %s at (%.1f, %.1f)" % [Game.region, world.player.global_position.x, world.player.global_position.z])
	get_tree().quit()


## The nest and the dragon fight: down the pit into the lair, the sleeping dragon, waking it,
## each attack (its red area first, a step out of the bite circle dodges), backing off to the
## safe spot, half HP rage + the dive, the kill (EXP, corpse, quest, victory scene) and coming back
## to its remains. Player AC is lowered and HP topped up between attacks so every hit lands.
func _run_dragon_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 11.0 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	var cerr := CutsceneData.validate(CutsceneData.load_cutscene("cutscene.dragon_defeated"))
	print("[dragon] victory cutscene data: %d issues %s" % [cerr.size(), cerr])
	Game.narrative.set_flag("story.new_game_seen")
	Game.quests.accept("quest.main.dragon")
	Game.narrative.set_flag("story.pass_reached")
	Game.narrative.set_flag("story.nest_found")
	travel("ashen_pass", "south_road", false)
	await _wait_travel()
	_place_player(Vector3(0, 0, -97.6), 0.0)
	await _frames(6)
	print("[dragon] at the pit: '%s'" % (world.player.focus.prompt_text() if world.player.focus else ""))
	await _key(KEY_E)
	await _seconds(1.0)
	await _wait_travel()
	var dr: DragonBoss = null
	for m in world.monsters:
		if m is DragonBoss:
			dr = m
	print("[dragon] pit -> %s (%s) at (%.1f, %.1f); dragon %s, mode %s, HP %d, arena %s r%.0f" % [Game.region, world.world_title(),
		world.player.global_position.x, world.player.global_position.z, dr != null, dr.mode if dr else "-", dr.max_hp if dr else 0,
		dr.arena_center if dr else Vector3.ZERO, dr.arena_radius if dr else 0.0])
	await _seconds(0.6)
	await _p1_shot("dragon_10_nest_entrance", "nest entrance + safe spot", true)
	_place_player(Vector3(0, 0, 6), 0.0)
	await _seconds(0.5)
	_place_player(Vector3(0, 0, -6.2), 0.0)
	await _seconds(0.8)
	print("[dragon] lair flag %s, still asleep %s at %.1f m" % [Game.narrative.get_flag("story.nest_entered"), dr.mode, world.player.global_position.distance_to(dr.global_position)])
	dr.set_physics_process(false)  # (shot only) hold it asleep while the camera gets close enough to see it
	_place_player(Vector3(-2.5, 0, -10.5), 0.0)
	await _seconds(0.6)
	await _p1_shot("dragon_11_sleeping", "dragon asleep on its hoard", true)
	_place_player(Vector3(0, 0, -6.2), 0.0)
	await _frames(3)
	dr.set_physics_process(true)
	await _walk_to(world.player, Vector2(0, -8.5))
	world.player.scripted_move = Vector2.ZERO
	await _frames(4)
	print("[dragon] walked close -> mode %s, boss bar %s, caption '%s'" % [dr.mode, game_hud._boss_box.visible, game_hud._caption.text])
	await _seconds(0.5)
	await _p1_shot("dragon_12_wakes", "the dragon wakes", true)
	await _seconds(1.6)
	st.armor_class = 1  # every hit lands (except a natural 1)
	var hold := func(pos: Vector3) -> void:
		dr._cd = 99.0
		_place_player(pos, 0.0)
		st.hp = st.max_hp()
	# --- bite: stay in the circle, then dodge one by stepping out
	for dodge in [false, true]:
		hold.call(dr.global_position + dr._forward() * 3.4)
		await _frames(2)
		dr._spot = dr.global_position + dr._forward() * DragonBoss.BITE_REACH
		dr._set_mode("bite")
		var hp0 := st.hp
		await _seconds(0.4)
		if not dodge:
			await _p1_shot("dragon_13_bite_warning", "bite: red circle first", true)
		else:
			_place_player(dr.global_position + dr._forward() * 3.4 + dr._forward().cross(Vector3.UP) * 4.0, 0.0)
		await _seconds(1.4)
		print("[dragon] bite (%s): HP %d -> %d" % ["stepped out" if dodge else "stayed in", hp0, st.hp])
	# --- tail sweep from behind: hit + shove
	hold.call(dr.global_position - dr._forward() * 3.0)
	await _frames(2)
	var at0: Vector3 = world.player.global_position
	var hp1 := st.hp
	dr._set_mode("tail")
	await _seconds(0.5)
	await _p1_shot("dragon_14_tail_warning", "tail: red ring", true)
	await _seconds(1.4)
	print("[dragon] tail: HP %d -> %d, shoved %.1f m" % [hp1, st.hp, world.player.global_position.distance_to(at0)])
	# --- fire breath at mid range
	hold.call(dr.global_position + dr._forward() * 8.0)
	await _frames(2)
	var hp2 := st.hp
	dr._set_mode("breath")
	dr._show_cone()
	await _seconds(0.7)
	await _p1_shot("dragon_15_fire_warning", "fire: red cone", true)
	await _seconds(0.9)
	await _p1_shot("dragon_16_fire", "fire breath", true)
	await _seconds(1.6)
	print("[dragon] fire: HP %d -> %d (ticks while standing in the cone)" % [hp2, st.hp])
	dr._end_attack(1.0)
	# --- the player's own sword reaches the big body
	hold.call(dr.global_position + dr._forward() * 3.8)
	await _frames(3)
	var dhp := dr.hp
	var log0 := Game.combat_log.entries.size()
	for i in 6:
		st.sp = st.max_sp()
		world.player.start_attack(dr.global_position + Vector3(0, 1, 0))
		await _seconds(0.7)
	var swings := PackedStringArray()
	for e: Dictionary in Game.combat_log.entries.slice(log0):
		if str(e.get("short", "")).begins_with("주인공") or str(e.get("short", "")).begins_with("치명타! 주인공"):
			swings.append(str(e["short"]))
	print("[dragon] 6 sword swings (hit bonus %+d vs AC %d): dragon HP %d -> %d  %s" % [st.total_hit_bonus(), dr.profile["ac"], dhp, dr.hp, swings])
	# --- back off to the safe spot: it goes home and lies down again (no healing)
	_place_player(Vector3(0, 0, 19), PI)
	var hp_before := dr.hp
	await _seconds(7.0)
	print("[dragon] player at the safe spot -> dragon %s, boss bar %s, HP kept %s" % [dr.mode, game_hud._boss_box.visible, dr.hp == hp_before])
	# --- half HP: rage, then the dive
	hold.call(dr.global_position + dr._forward() * 9.0)
	dr.engage()
	await _seconds(2.0)
	var strong := {"name": "시험 일격", "hit_bonus": 99, "crit_chance": 0, "phys": "1d1", "str_mult": 1.0, "phys_bonus": 0, "ac": 0}
	while dr.hp > dr.max_hp / 2:
		strong["phys"] = "%dd1" % maxi(1, dr.hp - dr.max_hp / 2)
		dr.receive_attack(strong, world.player)
	dr._cd = 99.0
	await _frames(4)
	print("[dragon] HP %d/%d -> phase %d, mode %s, caption '%s'" % [dr.hp, dr.max_hp, dr.phase, dr.mode, game_hud._caption.text])
	await _p1_shot("dragon_17_rage", "rage", true)
	await _seconds(1.6)
	hold.call(dr.global_position + dr._forward() * 9.0)
	await _frames(2)
	var hp3 := st.hp
	dr._from = dr.global_position
	dr._set_mode("dive")
	for s2 in dr._shapes:
		s2.disabled = true
	await _seconds(1.5)
	await _p1_shot("dragon_18_dive_warning", "dive: circle follows the player", true)
	await _seconds(2.0)
	await _p1_shot("dragon_19_dive_impact", "dive impact", true)
	print("[dragon] dive: HP %d -> %d, dragon landed at (%.1f, %.1f) inside the lair %s" % [hp3, st.hp, dr.global_position.x, dr.global_position.z,
		dr._in_arena(dr.global_position)])
	await _seconds(0.6)
	# --- the kill
	st.hp = st.max_hp()
	var exp0 := st.gen_exp
	strong["phys"] = "999d1"
	dr.receive_attack(strong, world.player)
	await _seconds(1.5)
	await _p1_shot("dragon_20_down", "the dragon falls", true)
	var corpse := ""
	for d: Dictionary in Game.field["loot"]:
		if str(d["id"]).begins_with("corpse_dragon"):
			var parts := PackedStringArray()
			for it: Dictionary in (d["inv"] as Inventory).items:
				parts.append("%s×%d" % [ItemDB.item_name(str(it["id"])), int(it["count"])])
			corpse = "%s: %s" % [d["title"], ", ".join(parts)]
	print("[dragon] dead: flag %s, EXP +%d, quest %s (%s), corpse '%s', once %s" % [Game.narrative.get_flag("story.dragon_defeated"),
		st.gen_exp - exp0 if st.gen_exp >= exp0 else -1, Game.quests.state("quest.main.dragon"), " / ".join(Game.quests.objectives_text("quest.main.dragon")),
		corpse, Game.field.get("defeated", {}).keys()])
	for i in 40:
		if game_hud.cutscene.playing:
			break
		await _frames(5)
	print("[dragon] victory cutscene playing %s (%s)" % [game_hud.cutscene.playing, game_hud.cutscene.current])
	await _seconds(2.0)
	await _p1_shot("dragon_21_victory", "victory scene", true)
	for i in 12:
		if not game_hud.cutscene.playing:
			break
		await _key(KEY_E)
		await _seconds(0.4)
	print("[dragon] cutscene over %s" % (not game_hud.cutscene.playing))
	st.armor_class = 10
	# --- out and back in: no dragon, its remains where it fell
	_place_player(Vector3(0, 0, 25.6), PI)
	await _seconds(1.5)
	await _wait_travel()
	print("[dragon] left -> %s" % Game.region)
	_place_player(Vector3(0, 0, -97.6), 0.0)
	await _frames(6)
	await _key(KEY_E)
	await _seconds(1.0)
	await _wait_travel()
	var again := 0
	for m in world.monsters:
		if m is DragonBoss:
			again += 1
	print("[dragon] back in the nest: dragons %d, remains %s" % [again, Game.field.get("remains", {})])
	_place_player(Vector3(0, 0, -6), 0.0)
	await _seconds(0.8)
	await _p1_shot("dragon_22_remains", "remains in the lair", true)
	get_tree().quit()


## Reporting the dragon to the king: dragon quest done (stage B, no camper yet) → throne room →
## "think about it" first (nothing changes) → the camper wish → wish cutscene → quest complete →
## camper parked in front of the castle (stage C) → out of the castle to the camper, into the
## driver's seat → talking to the king once more.
func _run_wish_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 11.0 * 60.0
	await wait_for_sprites()
	var derr := DialogueData.validate(DialogueData.load_dialogue("dialogue.story.king_audience"))
	var cerr := CutsceneData.validate(CutsceneData.load_cutscene("cutscene.camper_wish"))
	print("[wish] data check: king dialogue %d issues %s, wish cutscene %d issues %s" % [derr.size(), derr, cerr.size(), cerr])
	Game.narrative.set_flag("story.new_game_seen")
	Game.set_story_stage(1)  # with the cat, no camper yet
	Game.quests.accept("quest.main.audience")
	Game.quests.advance("quest.main.audience", "audience")
	Game.quests.complete("quest.main.audience")
	Game.quests.accept("quest.main.dragon")
	for f in ["story.pass_reached", "story.nest_found", "story.dragon_defeated"]:
		Game.narrative.set_flag(f)
	Game.quests.advance("quest.main.dragon", "dragon")
	print("[wish] before: stage %s, camper %s, dragon quest %s" % ["ABC"[Game.story_stage()], Game.has_camper, Game.quests.state("quest.main.dragon")])
	travel("throne_room", "entrance", false)
	await _wait_travel()
	var talk := func(pick: String, shots: Dictionary) -> PackedStringArray:
		_place_player(Vector3(0, 0, -5.2), 0.0)
		await _frames(6)
		await _key(KEY_E)
		await _frames(4)
		var said := PackedStringArray()
		var shot_cut := false
		for i in 60:
			if not game_hud.dialogue_active() and not game_hud.cutscene.playing:
				break
			if game_hud.cutscene.playing:
				await _seconds(0.5)
				if not shot_cut and shots.has("cutscene"):
					shot_cut = true
					await _seconds(2.0)  # past the fade: the illustration card + narration
					await _p1_shot(shots["cutscene"], "wish cutscene", true)
				if game_hud.cutscene.playing:  # (it may have just ended: then E belongs to the next line)
					var tag := "[컷씬 %s]" % game_hud.cutscene.current
					said.append(tag if not said.has(tag) else "")
					await _key(KEY_E)
				continue
			var ev: Dictionary = game_hud.dialogue.event
			await _seconds(0.2)
			if shots.has(ev.get("node", "")):
				await _p1_shot(shots[ev["node"]], ev["node"], true)
			match ev.get("type", ""):
				"line":
					said.append("%s: %s" % [ev["name"], str(ev["text"]).split("\n")[0].substr(0, 34)])
					await _key(KEY_E)
				"choice":
					said.append("[선택 %s]" % pick)
					game_hud.dialogue.choose(pick)
					await _frames(3)
				_:
					await _frames(3)
		var out := PackedStringArray()
		for t in said:
			if t != "":
				out.append(t)
		return out
	var s1: PackedStringArray = await talk.call("later", {"wish": "wish_01_report_choice"})
	print("[wish] talk 1:   %s" % " | ".join(s1))
	print("[wish] after 'later': quest %s, camper %s" % [Game.quests.state("quest.main.dragon"), Game.has_camper])
	await _seconds(0.6)
	var exp0 := Game.player_state.gen_exp
	var s2: PackedStringArray = await talk.call("camper", {"r4": "wish_02_camper", "cutscene": "wish_03_cutscene", "r8": "wish_04_got_it"})
	print("[wish] talk 2:   %s" % " | ".join(s2))
	print("[wish] after the wish: quest %s, EXP +%d, stage %s, camper %s at %s %s, flag %s, event %s" % [Game.quests.state("quest.main.dragon"),
		Game.player_state.gen_exp - exp0, "ABC"[Game.story_stage()], Game.has_camper, Game.camper.get("region", ""), Game.camper.get("pos", ""),
		Game.narrative.get_flag("story.camper_received"), Game.narrative.event_done("story.camper_wish")])
	await _seconds(0.6)
	var s3: PackedStringArray = await talk.call("", {})
	print("[wish] talk 3:   %s" % " | ".join(s3))
	# out of the castle: the camper waits in front of it
	_place_player(Vector3(0, 0, 8.6), PI)
	await _seconds(1.2)
	await _wait_travel()
	await _seconds(0.8)
	print("[wish] castle -> %s at (%.1f, %.1f): camper here %s, visible %s at (%.1f, %.1f), cat %s" % [Game.region, world.player.global_position.x,
		world.player.global_position.z, world.camper_here(), world.vehicle.visible, world.vehicle.global_position.x, world.vehicle.global_position.z,
		world.cat != null])
	_place_player(Vector3(-4.0, 0, -16.0), PI)
	await _seconds(1.0)
	await _p1_shot("wish_05_camper_at_castle", "the camper on the plaza in front of the castle", true)
	world.enter_vehicle()
	await _frames(4)
	print("[wish] driver's seat: driving %s, power %.2f, %s" % [world.vehicle.driving, world.vehicle.power, Game.camper_status_text()])
	get_tree().quit()


## Camper upgrades (GDD 9): the three capital vendors and their panels, buying in order (and what
## blocks), the infinite-power quest, naming, paint + parts on the baked sprite, off-road speed,
## the interior (bed tier, workbench, refinery bonus, two magic rooms, decor placed / picked up,
## bedroom sleep), magic fuel, the field repair skill, monsters attacking a camper parked in a
## dangerous spot and overnight scratches, a resident's parking complaint, and save / load.
func _run_upgrades_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 11.0 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	Game.set_story_stage(2)
	st.gold = 20000
	Game.camper = {"region": "capital", "pos": Vector3(7, 0, 44), "yaw": 0.0}
	travel("capital", "south_road", false)
	await _wait_travel()
	print("[upg] vendors in the capital: %s" % [world.npcs.map(func(n: Npc) -> String: return n.look)])
	# --- mechanic panel
	_place_player(Vector3(7.4, 0, -19.4), 2.356)
	await _frames(8)
	print("[upg] prompt at the mechanic: '%s'" % (world.player.focus.prompt_text() if world.player.focus else ""))
	await _key(KEY_E)
	await _frames(6)
	print("[upg] panel %s" % game_hud._panel_kind)
	await _p1_shot("upg_01_mechanic_panel", "mechanic upgrade panel", true)
	game_hud.close_panel()
	print("[upg] off-road kit first -> '%s'" % CamperUpgrades.block("drive_offroad"))
	print("[upg] infinite core first -> '%s'" % CamperUpgrades.block("engine_infinite"))
	# --- driving off the road before / after the kit (outside the walls, rough ground)
	var drive_test := func(label: String) -> float:
		world.enter_vehicle()
		await _frames(3)
		var v: CamperVehicle = world.vehicle
		v.global_position = Vector3(18, 0, 30)
		v.rotation.y = 0.0
		world._last_drive_pos = v.global_position
		var x0 := v.global_position.x
		v.scripted = {"throttle": 1.0, "steer": 0.0}
		await _seconds(2.5)
		v.scripted = {"throttle": 0.0, "steer": 0.0}
		await _seconds(0.8)
		var d := v.global_position.x - x0
		print("[upg] drive %s: on road %s, %.1f m in 2.5 s (power %.2f)" % [label, world.on_road(Vector3(24, 0, 30)), d, v.power])
		world.exit_vehicle()
		await _frames(3)
		return d
	var d0: float = await drive_test.call("stock, rough ground")
	for id in ["engine_tune", "engine_tank", "drive_tires", "drive_offroad", "workbench", "refinery", "paint_sunset", "part_awning", "part_flag", "part_bullbar", "skill_repair"]:
		var r := CamperUpgrades.buy(id)
		print("[upg]   buy %s -> %s" % [id, "ok" if r == "" else r])
	var d1: float = await drive_test.call("tires + off-road kit")
	print("[upg] off-road gain ×%.2f, fuel per m %.3f, tank %d" % [d1 / maxf(d0, 0.1), CamperUpgrades.fuel_per_m(), roundi(Game.camper_fuel_max())])
	# --- mage + carpenter
	for id in ["engine_magic", "refinery_plus", "drive_booster", "room_1", "room_2", "storage_1", "storage_2", "storage_3", "bed_sofa", "bed_full"]:
		var r2 := CamperUpgrades.buy(id)
		print("[upg]   buy %s -> %s" % [id, "ok" if r2 == "" else r2])
	print("[upg] fuel kind %s, fuel %s, storage %d kg, bed %s, rooms %d" % [CamperUpgrades.fuel_kind(), Game.camper_status_text(), roundi(Game.storage_capacity()),
		CamperUpgrades.bed_info()["name"], CamperUpgrades.rooms_max()])
	_place_player(Vector3(7.4, 0, -4.6), 0.785)
	await _frames(6)
	await _key(KEY_E)
	await _frames(6)
	await _p1_shot("upg_02_mage_panel", "mage panel with the quest", true)
	game_hud.close_panel()
	Game.quests.accept("quest.camper.infinite_core")
	st.inventory.add("dragon_scale", 3)
	st.inventory.add("dragon_fang", 1)
	st.inventory.add("mana_shard", 5)
	print("[upg] infinite core quest %s -> complete '%s' -> fit -> '%s', infinite %s" % [Game.quests.state("quest.camper.infinite_core"),
		Game.quests.complete("quest.camper.infinite_core").substr(0, 24), CamperUpgrades.buy("engine_infinite"), Game.camper_infinite_power])
	_place_player(Vector3(-7.4, 0, -4.6), -0.785)
	await _frames(6)
	await _key(KEY_E)
	await _frames(6)
	await _p1_shot("upg_03_carpenter_panel", "carpenter panel with decor", true)
	game_hud.close_panel()
	for it in ["decor_plant", "decor_lamp", "decor_cat_tower", "decor_rug"]:
		st.inventory.add(it, 1)
	# --- naming
	game_hud.open_camper_name(null)
	await _frames(4)
	var edit: LineEdit = game_hud._panel.find_children("*", "LineEdit", true, false)[0]
	edit.text = "굴러가는 집"
	edit.text_submitted.emit(edit.text)
	await _frames(3)
	print("[upg] named -> %s" % CamperUpgrades.camper_name())
	# --- the painted camper with its parts (re-baked sprite)
	world.vehicle.global_position = Vector3(7.0, 0, 44.0)  # back on the parking bay
	world.vehicle.rotation.y = 0.0
	world._save_parking()
	await wait_for_sprites()
	_place_player(Vector3(4.0, 0, 39.5), PI)
	await _seconds(1.0)
	await _p1_shot("upg_04_painted_camper", "sunset paint, awning, flag, bull bar", true)
	print("[upg] sprite sheet key: camper|%s" % CamperUpgrades.look_key())
	# --- interior: bed, workbench, refinery, rooms, decor
	Game.camper_mods["rooms"] = [{"purpose": "bedroom"}, {"purpose": "workshop"}]
	Game.request_world(Game.WORLD_INTERIOR)
	await _frames(8)
	await wait_for_sprites()
	var facil := PackedStringArray()
	for ip in get_tree().get_nodes_in_group("facility"):
		facil.append(str(ip.get_meta("facility")))
	print("[upg] interior: walk bounds %s, facilities %s" % [world.player.walk_bounds, facil])
	_place_player(Vector3(-3.0, 0, -0.2), 0.0)
	await _seconds(0.6)
	await _p1_shot("upg_05_interior_bed_refinery", "real bed, refinery, plaque", true)
	_place_player(Vector3(7.5, 0, 0.6), 0.0)
	await _seconds(0.6)
	await _p1_shot("upg_06_room_bedroom", "magic room 1: bedroom", true)
	_place_player(Vector3(13.5, 0, 0.6), 0.0)
	await _seconds(0.6)
	await _p1_shot("upg_07_room_workshop", "magic room 2: workshop", true)
	# refinery bonus: one magic fuel recipe makes 2 (+1 inside the improved refinery)
	st.inventory.add("mana_shard", 2)
	st.inventory.add("slime_core", 2)
	var mf := st.inventory.count("magic_fuel")
	await _craft_and_wait("magic_fuel", "refinery")
	print("[upg] magic fuel at the camper refinery: %d -> %d" % [mf, st.inventory.count("magic_fuel")])
	# decor: place three, pick one back up
	var spots := [Vector3(-0.8, 0, -0.6), Vector3(2.6, 0, 0.4), Vector3(6.0, 0, 1.2)]
	var items := ["decor_plant", "decor_cat_tower", "decor_lamp"]
	for k in 3:
		_place_player(spots[k], PI)
		await _frames(3)
		world.begin_place(items[k])
		await _frames(3)
		await _key(KEY_R)
		await _key(KEY_E)
		await _frames(4)
	print("[upg] decor placed: %s" % [Game.camper_mods["decor"].map(func(d: Dictionary) -> String: return "%s@(%.2f,%.2f)" % [d["item"], d["pos"][0], d["pos"][1]])])
	_place_player(Vector3(-0.8, 0, -0.6), PI)
	await _seconds(0.4)
	await _p1_shot("upg_08_decor", "placed decor", true)
	world.pick_up_decor(0)
	await _frames(4)
	print("[upg] picked up -> decor %d, plants in bag %d, cat spots %d" % [Game.camper_mods["decor"].size(), st.inventory.count("decor_plant"), world.cat.home_spots.size() if world.cat else -1])
	# bedroom sleep: bed 75 % + bedroom 10 %
	st.hp = 1.0
	sleep(1, float(CamperUpgrades.purpose_info("bedroom").get("sleep_bonus", 0.0)))
	await _seconds(3.5)
	print("[upg] bedroom sleep: HP 1 -> %d / %d" % [roundi(st.hp), roundi(st.max_hp())])
	Game.camper_mods["rooms"][1]["purpose"] = "cat_room"
	Game.request_world(Game.WORLD_INTERIOR)
	await _frames(8)
	_place_player(Vector3(13.5, 0, 0.6), 0.0)
	await _seconds(0.6)
	await _p1_shot("upg_09_room_cat", "room 2 changed to a cat room", true)
	# --- field repair with the skill
	Game.request_world(Game.WORLD_EXTERIOR)
	await _frames(8)
	_place_player(world.vehicle.global_position + Vector3(0, 0, 2.6), 0.0)
	await _frames(3)
	Game.camper_durability = 10.0
	st.inventory.add("repair_kit", 1)
	print("[upg] repair kit with the skill -> '%s'" % use_camper_item("repair_kit"))
	Game.camper_infinite_power = false
	Game.camper_fuel = 10.0
	print("[upg] magic fuel -> '%s' · gasoline can -> '%s'" % [use_camper_item("magic_fuel"), use_camper_item("fuel_can") if st.inventory.count("fuel_can") > 0 else "(없음)"])
	Game.camper_infinite_power = true
	# --- resident complaint: park on the plaza, then on the parking spot
	world.enter_vehicle()
	await _frames(3)
	world.vehicle.global_position = Vector3(-3.0, 0, 6.0)
	world.exit_vehicle()
	await _frames(4)
	var c1 := int(Game.camper_mods.get("complaints", 0))
	await _p1_shot("upg_10_complaint", "resident complaint", true)
	world.enter_vehicle()
	await _frames(3)
	world.vehicle.global_position = Vector3(7.0, 0, 44.0)
	world.exit_vehicle()
	await _frames(4)
	print("[upg] complaints: plaza %d, parking spot %d" % [c1, int(Game.camper_mods.get("complaints", 0))])
	# --- monsters go for a camper parked in a dangerous spot (slimes are 비선공 now: this run
	# switches the highland ones to the 선공 setting in memory, the way monsters.json would)
	var target: Dictionary = {}
	for m: Dictionary in RegionDB.info("highland").get("monsters", []):
		MonsterDB.info(str(m["kind"]))["aggressive"] = true
		if target.is_empty():
			target = m
	var tp := RegionDB.v3(target["pos"])
	Game.camper = {"region": "highland", "pos": tp + Vector3(4.5, 0, 0), "yaw": 0.0}
	print("[upg] highland spot (%.0f, %.0f) safe %s, near %s" % [tp.x + 4.5, tp.z, RegionDB.spot_safe("highland", tp + Vector3(4.5, 0, 0)), target["kind"]])
	travel("highland", "west_road", false)
	await _wait_travel()
	Game.camper_durability = 100.0
	_place_player(Vector3(-80, 0, 1), 0.0)
	await _seconds(14.0)
	print("[upg] after 14 s away: durability %d" % ceili(Game.camper_durability))
	_place_player(tp + Vector3(4.5, 0, 6.0), 0.0)
	await _seconds(1.0)
	await _p1_shot("upg_11_camper_attacked", "slimes attacking the parked camper", true)
	# overnight in that spot
	Game.request_world(Game.WORLD_INTERIOR)
	await _frames(8)
	var dur0 := Game.camper_durability
	seed(5)
	sleep(8)
	await _seconds(6.0)
	print("[upg] slept 8 h parked there: durability %d -> %d" % [ceili(dur0), ceili(Game.camper_durability)])
	# --- save / load keeps it all
	var saved := SaveManager.capture_state()
	var before := JSON.stringify(Game.camper_mods)
	Game.camper_mods = {"owned": [], "name": "", "paint": "classic", "parts": [], "rooms": [], "decor": []}
	SaveManager.apply_state(saved)
	print("[upg] save/load camper mods identical %s (%d upgrades, name %s)" % [JSON.stringify(Game.camper_mods) == before, Game.camper_mods["owned"].size(), CamperUpgrades.camper_name()])
	get_tree().quit()


# ---------------------------------------------------------------- camper fuel / durability

## Drives into meadow slimes until the camper breaks, then exercises fuel use, the emergency
## repair kit, the smith's full repair, refuelling, the refinery recipe, fast-travel rules and saving.
func _run_camper_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 11.0 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	var v: CamperVehicle = world.vehicle
	print("[camper] start: %s" % Game.camper_status_text())
	# --- fuel per metre: drive straight along the road for a while
	world.enter_vehicle()
	await _frames(3)
	v.global_position = Vector3(46, 0, -3.6)
	v.rotation.y = 0.0  # nose east
	world._last_drive_pos = v.global_position
	var fuel0 := Game.camper_fuel
	var x0 := v.global_position.x
	v.scripted = {"throttle": 1.0, "steer": 0.0}
	await _seconds(4.0)
	v.scripted = {"throttle": 0.0, "steer": 0.0}
	await _seconds(1.0)
	print("[camper] drove %.1f m -> fuel %.2f -> %.2f L (%.3f L/m)" % [v.global_position.x - x0, fuel0, Game.camper_fuel, (fuel0 - Game.camper_fuel) / maxf(v.global_position.x - x0, 0.01)])
	# --- ram monsters until it breaks
	var hits := 0
	for i in 12:
		var target: SlimeMonster = null
		for m in world.monsters:
			if is_instance_valid(m) and m.state != SlimeMonster.State.DEAD:
				target = m
				break
		if target == null or Game.camper_broken():
			break
		var tp := target.global_position
		v.global_position = Vector3(tp.x - 7.0, 0, tp.z)
		v.rotation.y = 0.0
		v.speed = 0.0
		world._last_drive_pos = v.global_position
		var hp0 := target.hp
		var tname := target.display_name
		var dur0 := Game.camper_durability
		v.scripted = {"throttle": 1.0, "steer": 0.0}
		var t := 0.0
		while t < 3.0 and Game.camper_durability == dur0:
			await _frames(1)
			t += get_process_delta_time()
		v.scripted = {"throttle": 0.0, "steer": 0.0}
		if Game.camper_durability < dur0:
			hits += 1
			print("[camper] hit %d: %s HP %d -> %s, durability %.0f -> %.0f, power %.2f" % [hits, tname, hp0,
				str(target.hp) if is_instance_valid(target) and target.state != SlimeMonster.State.DEAD else "쓰러짐", dur0, Game.camper_durability, v.power])
			if hits == 1:
				await _frames(2)
				await _p1_shot("camper_01_ram", "camper rams a slime", true)
		await _seconds(0.6)
	print("[camper] after %d hits: broken %s, power %.2f, status '%s'" % [hits, Game.camper_broken(), v.power, Game.camper_status_text()])
	if not Game.camper_broken():
		Game.damage_camper(Game.camper_durability)  # one more knock: check the broken state itself
		await _frames(2)
		print("[camper] one more hit -> broken %s, power %.2f" % [Game.camper_broken(), v.power])
	v.scripted = {"throttle": 1.0, "steer": 0.0}
	var bx := v.global_position.x
	await _seconds(1.5)
	v.scripted = {}
	print("[camper] broken + throttle -> moved %.2f m" % (v.global_position.x - bx))
	await _seconds(0.5)
	world.exit_vehicle()
	await _frames(3)
	world.enter_vehicle()
	print("[camper] try to drive a broken camper -> driving %s" % v.driving)
	await _p1_shot("camper_02_broken_hud", "broken camper, HUD status", true)
	# --- emergency repair kit beside it, then the smith's full repair
	st.inventory.add("repair_kit", 1)
	print("[camper] repair kit -> '%s'" % use_camper_item("repair_kit"))
	print("[camper] repair kit again -> '%s'" % use_camper_item("repair_kit"))
	st.gold = 500
	var q := camper_repair_quote()
	print("[camper] smith quote: ok %s, %d gold" % [q["ok"], int(q["gold"])])
	_place_player(VisualLab.TRADE_STALLS[1][0] + Vector3(0, 0, 1.5), 0.0)
	await _frames(5)
	game_hud.open_shop("bron", null)
	await _frames(4)
	await _p1_shot("camper_03_smith_repair", "smith offers camper repair", true)
	game_hud.close_panel()
	print("[camper] smith repair -> '%s', gold %d" % [repair_camper(), st.gold])
	# --- out of fuel: no power; refuel with a can beside the camper
	Game.camper_fuel = 0.0
	_place_player(v.global_position + Vector3(0, 0, 3.5), 0.0)
	await _frames(3)
	world.enter_vehicle()
	await _frames(2)
	print("[camper] empty tank -> power %.2f" % v.power)
	world.exit_vehicle()
	await _frames(2)
	st.inventory.add("fuel_can", 2)
	print("[camper] refuel -> '%s'" % use_camper_item("fuel_can"))
	_place_player(Vector3(-5, 0, 30), 0.0)
	await _frames(3)
	print("[camper] refuel far from the camper -> '%s'" % use_camper_item("fuel_can"))
	# --- refinery: slime jelly -> gasoline can (NPC facility, GDD 9.3)
	st.inventory.add("slime_jelly", 4)
	_place_player(VisualLab.REFINERY_POS + Vector3(0, 0, 1.0), PI)
	await _frames(5)
	var cans := st.inventory.count("fuel_can")
	print("[camper] refinery craft -> %s, fuel cans %d -> %d, jelly %d" % [await _craft_and_wait("fuel_can", "refinery"), cans, st.inventory.count("fuel_can"), st.inventory.count("slime_jelly")])
	game_hud.open_crafting("refinery", null)
	await _frames(4)
	await _p1_shot("camper_04_refinery", "refinery recipe", true)
	game_hud.close_panel()
	# --- fast travel rules (GDD 11.4): low fuel / broken -> carriage
	Game.discovered["city:capital"] = true
	Game.discovered["city:pinecone"] = true
	Game.region = "highland"
	Game.camper = {"region": "highland", "pos": Vector3(57, 0, 14), "yaw": 0.0}
	Game.spawn_override = {"kind": "load", "pos": Vector3(50, 0, 32), "yaw": 0.0}
	Game.request_world(Game.WORLD_EXTERIOR)
	await _frames(3)
	await wait_for_sprites()
	await _frames(5)
	Game.camper_fuel = 5.0
	var q1 := fast_travel_quote("capital")
	print("[camper] fast travel, 5 L left -> with camper %s, note '%s', fare %d" % [q1["with_camper"], q1.get("camper_note", ""), int(q1["gold"])])
	Game.camper_fuel = 60.0
	Game.camper_durability = 0.0
	var q2 := fast_travel_quote("capital")
	print("[camper] fast travel, broken -> with camper %s, note '%s'" % [q2["with_camper"], q2.get("camper_note", "")])
	Game.camper_durability = 100.0
	var q3 := fast_travel_quote("capital")
	print("[camper] fast travel, full tank -> with camper %s, fuel %.1f L" % [q3["with_camper"], float(q3["fuel"])])
	await fast_travel("capital")
	print("[camper]   arrived %s, fuel now %.1f L" % [Game.region, Game.camper_fuel])
	# --- saved and restored
	Game.camper_fuel = 33.0
	Game.camper_durability = 47.0
	var saved := SaveManager.capture_state()
	Game.camper_fuel = 1.0
	Game.camper_durability = 1.0
	SaveManager.apply_state(saved)
	print("[camper] save -> load: fuel %.0f, durability %.0f" % [Game.camper_fuel, Game.camper_durability])
	get_tree().quit()


# ---------------------------------------------------------------- larger world, towns, map

## Walks the enlarged world: meadow corners, the road north to the capital (walls, plaza, castle),
## the highland and its village; then the world map (see the map part below). Prints sizes.
func _run_world_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 11.0 * 60.0
	await wait_for_sprites()
	for rid: String in ["meadow", "highland", "capital"]:
		var t: Dictionary = RegionDB.info(rid).get("terrain", {})
		var mn := TerrainField._v2(t.get("min", null), Vector2.ZERO)
		var mx := TerrainField._v2(t.get("max", null), Vector2.ZERO)
		print("[world] %s %dx%d m (%d m²)" % [rid, mx.x - mn.x, mx.y - mn.y, (mx.x - mn.x) * (mx.y - mn.y)])
	var shots := [["meadow", Vector3(56, 0, 40), 0.0, "meadow_silver_lake"], ["meadow", Vector3(-62, 0, 30), 0.0, "meadow_west_forest"],
		["meadow", Vector3(-21, 0, -72), PI, "meadow_north_road"]]
	for sh: Array in shots:
		_place_player(sh[1], sh[2])
		await _seconds(1.2)
		await _p1_shot("world_" + sh[3], sh[3], true)
	# walk into the north road exit -> capital
	_place_player(Vector3(-20, 0, -84), PI)
	await _seconds(0.5)
	_place_player(Vector3(-20, 0, -86.5), PI)
	await _seconds(0.8)
	await _wait_travel()
	print("[world] north road -> %s (%s), player (%.1f, %.1f)" % [Game.region, world.world_title(), world.player.global_position.x, world.player.global_position.z])
	await _seconds(1.0)
	await _p1_shot("world_capital_road", "capital road", true)
	for sh: Array in [[Vector3(0, 0, 27), 0.0, "capital_gate"], [Vector3(0, 0, -2), 0.0, "capital_plaza"], [Vector3(0, 0, -35), 0.0, "capital_castle"],
			[Vector3(-26, 0, -20), 0.0, "capital_houses"], [Vector3(36, 0, 14), 0.0, "capital_wall_corner"]]:
		_place_player(sh[0], sh[1])
		await _seconds(1.2)
		await _p1_shot("world_" + sh[2], sh[2], true)
	print("[world] capital visited %s, safe at plaza %s" % [Game.discovered.has("city:capital"), world.is_safe(Vector3(0, 0, -6))])
	# highland village (direct travel for the test)
	travel("highland", "west_road", false)
	await _wait_travel()
	_place_player(Vector3(50, 0, 14), 0.0)
	await _seconds(1.2)
	await _p1_shot("world_village_gate", "village gate", true)
	_place_player(Vector3(50, 0, 32), 0.0)
	await _seconds(1.2)
	await _p1_shot("world_village", "village", true)
	print("[world] village visited %s" % Game.discovered.has("city:pinecone"))
	# --- world map (GDD 11.3): towns from the start, found places, pins with memos
	game_hud.toggle_map()
	await _frames(4)
	var mv: WorldMap = game_hud.map_view
	print("[map] open %s, regions on the map %s, towns %s" % [game_hud._panel_kind == "map", ", ".join(PackedStringArray(mv._known_regions())),
		", ".join(PackedStringArray(RegionDB.cities().keys()))])
	await _p1_shot("map_01_overview", "world map", true)
	var pin := mv.add_pin(RegionDB.map_pos("meadow", Vector2(72, 62)))
	Game.map_pins[pin]["text"] = "달빛 꽃 (밤)"
	mv.close_card()
	mv.center_on_player()
	await _frames(3)
	await _p1_shot("map_02_zoom_village", "map zoomed on the player", true)
	# --- fast travel (GDD 11.4): village -> capital by carriage (the camper is parked in the meadow)
	mv.fit_all()
	mv.open_city("capital")
	await _frames(3)
	var gold0 := Game.player_state.gold
	var t0 := Game.total_minutes()
	var q := fast_travel_quote("capital")
	print("[map] quote village -> capital: ok %s, from %s, %d m, %.0f min, gold %d, with camper %s" % [q["ok"], q.get("from", ""), int(q.get("distance", 0)),
		float(q.get("minutes", 0)), int(q.get("gold", 0)), q.get("with_camper", false)])
	await _p1_shot("map_03_city_card", "town card with fast travel", true)
	var why := await fast_travel("capital")
	print("[map] fast travel -> '%s': now %s at (%.1f, %.1f), +%.0f min, gold %d -> %d, camper still in %s" % [why, Game.region,
		world.player.global_position.x, world.player.global_position.z, Game.total_minutes() - t0, gold0, Game.player_state.gold, Game.camper.get("region", "")])
	await _seconds(0.8)
	await _p1_shot("map_04_arrived_capital", "arrived at the capital by fast travel", true)
	# refused outside a town; with the camper when it is parked here
	_place_player(Vector3(0, 0, 50), 0.0)
	await _frames(3)
	print("[map] outside the walls -> '%s'" % fast_travel_quote("pinecone").get("why", ""))
	Game.camper = {"region": "capital", "pos": Vector3(7, 0, 44), "yaw": 0.0}
	_place_player(Vector3(0, 0, -6), 0.0)
	await _frames(3)
	var q2 := fast_travel_quote("pinecone")
	print("[map] capital -> village with the camper parked here: ok %s, with camper %s, gold %d, %.0f min" % [q2["ok"], q2["with_camper"], int(q2["gold"]), float(q2["minutes"])])
	await fast_travel("pinecone")
	print("[map]   arrived %s, camper now in %s at %s, pin kept %s" % [Game.region, Game.camper.get("region", ""), Game.camper.get("pos", ""), Game.map_pins.size() == 1])
	await _seconds(0.8)
	await _p1_shot("map_05_arrived_village_camper", "arrived at the village with the camper", true)
	get_tree().quit()


# ---------------------------------------------------------------- cutscenes (new game story)

## Plays the new-game story (data/story.json) pressing E like a player, captures the intro's
## narration / illustration / line and the opening's letterbox scene, then checks ESC skipping.
func _run_cutscene_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	var cs: CutsceneRunner = game_hud.cutscene
	var p: PrototypePlayer = world.player
	var start_pos := p.global_position
	game_hud.overlay.fade_rect.modulate.a = 1.0
	play_new_game_story()
	await _frames(2)
	var shots := {"cutscene.intro": [2, 8, 10], "cutscene.opening": [2, 3, 6]}
	var shot_done := {}
	var t := 0.0
	var press_t := 0.0
	while (cs.playing or t < 0.5) and t < 120.0:
		await _frames(1)
		t += get_process_delta_time()
		press_t += get_process_delta_time()
		var key := "%s:%d" % [cs.current, cs.step_index]
		if cs.playing and cs.step_index in shots.get(cs.current, []) and not shot_done.has(key):
			await _seconds(1.4)  # typing / fades settle
			shot_done[key] = true
			print("[cutscene] %s step %d — narration '%s', line %s, letterbox %s, image %s, hud hidden %s, controls %s" % [cs.current, cs.step_index,
				game_hud.overlay.narration_text().split("\n")[0], game_hud.dialogue.showing_cutscene_line(), game_hud.overlay.letterbox_on(),
				game_hud.overlay.has_image(), not game_hud._info.is_visible_in_tree(), p.controls_enabled])
			await _p1_shot("cutscene_%s_%02d" % [cs.current.get_slice(".", 1), cs.step_index], "cutscene", true)
		if press_t > 1.2:
			press_t = 0.0
			cs.hurry()
	await _frames(3)  # the HUD comes back on the next frame
	print("[cutscene] story done in %.1f s: flag new_game_seen %s, arrived %s, player moved %.1f m, controls %s, screen black %s, hud back %s" % [t,
		Game.narrative.get_flag("story.new_game_seen"), Game.narrative.get_flag("story.arrived"), p.global_position.distance_to(start_pos),
		p.controls_enabled, game_hud.overlay.is_black(), game_hud._info.is_visible_in_tree()])
	# ESC skip: the whole intro at once, its end state still applied
	Game.narrative.set_flag("story.arrived", false)
	cs.play("cutscene.opening")
	await _seconds(1.0)
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	_touring = false
	_unhandled_input(ev)
	_touring = true
	var t2 := 0.0
	while cs.playing and t2 < 5.0:
		await _frames(1)
		t2 += get_process_delta_time()
	await _frames(5)
	print("[cutscene] ESC skip -> finished %s in %.2f s, paused %s, arrived flag %s, letterbox %s, controls %s" % [not cs.playing, t2,
		get_tree().paused, Game.narrative.get_flag("story.arrived"), game_hud.overlay.letterbox_on(), p.controls_enabled])
	get_tree().quit()


# ---------------------------------------------------------------- dialogue window portraits

## Plays dialogues through every speaker combination and records which portrait is lit:
## protagonist left, partner right, the one not speaking at 50% opacity, narration dims both.
func _ui_find(text: String, cls: String) -> Control:
	var stack: Array = [game_hud._panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		if n.get_class() == cls and str(n.get("text")).strip_edges().begins_with(text):
			return n
		stack.append_array(n.get_children())
	return null


## A bag / slot cell (Button) whose name label starts with text.
func _ui_cell(text: String) -> Button:
	var stack: Array = [game_hud._panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			for c in n.get_children():
				if c is Label and str(c.text).begins_with(text):
					return n
		stack.append_array(n.get_children())
	return null


func _ui_move(c: Control) -> void:
	var pos := c.get_global_rect().get_center()
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	get_viewport().warp_mouse(pos)
	Input.parse_input_event(ev)
	await _frames(3)


func _ui_click(c: Control, double := false) -> void:
	await _ui_move(c)
	var pos := c.get_global_rect().get_center()
	for i in (2 if double else 1):
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.double_click = double and i == 1 and pressed
			ev.position = pos
			ev.global_position = pos
			Input.parse_input_event(ev)
			await _frames(2)
	await _frames(4)


## Inventory + equipment window (user mockup): tabs, equipment slot grid, weight bar (bag + worn),
## 7-column bag grid with hover text, select / double-click to equip, 정렬, tab switch by click.
func _run_inv_ui_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	for spec in [["iron_ore", 3], ["leather_cap", 1], ["heal_potion", 2], ["slime_jelly", 4], ["bread", 1], ["mana_potion", 1]]:
		st.inventory.add(str(spec[0]), int(spec[1]))
	print("[invui] weight: bag %.1f + worn %.1f = %.1f (carried_weight %.1f)" % [st.inventory.weight(), st.equipped_weight(),
		st.inventory.weight() + st.equipped_weight(), st.carried_weight()])
	game_hud.toggle_inventory()
	await _frames(5)
	await _p1_shot("invui_01_window", "inventory + equipment window", true)
	await _ui_move(_ui_cell("가죽 모자"))
	print("[invui] hover 가죽 모자 -> %s" % game_hud.tip_text().replace("\n", " / "))
	await _p1_shot("invui_02_hover", "hover a bag cell", true)
	await _ui_click(_ui_cell("가죽 모자"))
	print("[invui] click -> selected %s, action button %s" % [game_hud._inv_sel, _ui_find("장착", "Button") != null])
	var w0 := st.carried_weight()
	await _ui_click(_ui_cell("가죽 모자"), true)
	await _seconds(1.2)  # gear swap motion
	print("[invui] double-click -> head slot '%s', bag cap %d, weight %.1f -> %.1f (same %s)" % [st.equipment["head"], st.inventory.count("leather_cap"),
		w0, st.carried_weight(), is_equal_approx(w0, st.carried_weight())])
	await _ui_move(_ui_cell("머리"))
	print("[invui] hover head slot -> %s" % game_hud.tip_text().replace("\n", " / "))
	var order0 := st.inventory.items.map(func(e: Dictionary) -> String: return ItemDB.item_name(e["id"]))
	await _ui_click(_ui_find("정렬", "Button"))
	var order1 := st.inventory.items.map(func(e: Dictionary) -> String: return ItemDB.item_name(e["id"]))
	print("[invui] 정렬: %s -> %s" % [", ".join(order0), ", ".join(order1)])
	await _p1_shot("invui_03_sorted_equipped", "after equip + sort", true)
	await _ui_click(_ui_find("능력치", "Button"))
	print("[invui] click 능력치 tab -> panel '%s'" % game_hud._panel_kind)
	await _p1_shot("invui_04_stats_tab", "stats tab", true)
	await _ui_click(_ui_find("소지품", "Button"))
	print("[invui] click 소지품 tab -> panel '%s'" % game_hud._panel_kind)
	get_tree().quit()


## Character sheet UI: hover descriptions (real mouse motion), + / − only plan points, the derived
## numbers preview "now → after", nothing changes before 확정, closing discards the plan.
func _run_stat_ui_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	st.add_exp(200)
	while st.can_level_up():
		st.level_up()
	print("[statui] Lv %d, stat points %d" % [st.level, st.stat_points])
	game_hud.toggle_character()
	await _frames(4)
	var find := func(text: String, cls: String) -> Control:
		var stack: Array = [game_hud._panel]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.get_class() == cls and str(n.get("text")).strip_edges().begins_with(text):
				return n
			stack.append_array(n.get_children())
		return null
	var move_to := func(c: Control) -> void:
		var pos := c.get_global_rect().get_center()
		var ev := InputEventMouseMotion.new()
		ev.position = pos
		ev.global_position = pos
		get_viewport().warp_mouse(pos)
		Input.parse_input_event(ev)
		await _frames(3)
	var click := func(c: Control) -> void:
		await move_to.call(c)
		var pos := c.get_global_rect().get_center()
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = pos
			ev.global_position = pos
			Input.parse_input_event(ev)
			await _frames(2)
		await _frames(3)
	# hover a stat name, then a derived number
	await move_to.call(find.call("힘 STR", "Label"))
	print("[statui] hover 힘 -> %s" % game_hud.tip_text().replace("\n", " / "))
	print("[statui] tip box at %s (mouse %s), on screen %s" % [game_hud._tip.position, game_hud.get_global_mouse_position(), Rect2(Vector2.ZERO, Vector2(1920, 1080)).encloses(game_hud._tip.get_rect())])
	await _p1_shot("statui_01_hover_str", "hover: STR", true)
	await move_to.call(find.call("최대 HP", "Label"))
	print("[statui] hover 최대 HP -> %s" % game_hud.tip_text().replace("\n", " / "))
	# plan STR +2, VIT +1 with real clicks on the + buttons
	var before := st.stats.duplicate()
	var hp0 := st.max_hp()
	for key in ["STR", "STR", "VIT"]:
		var row: Control = find.call(PlayerState.STAT_INFO[key][0] + " " + key, "Label").get_parent()
		await click.call(row.get_child(3))
	await _frames(4)
	var hp_lbl: Control = find.call("최대 HP", "Label")
	var preview_txt: String = hp_lbl.get_parent().get_child(1).text
	var carry_txt: String = find.call("소지 중량", "Label").get_parent().get_child(1).text
	print("[statui] planned %s (points left %d): stats unchanged %s, max HP still %d | preview HP '%s', carry '%s'" % [game_hud.stat_plan,
		st.stat_points - game_hud._plan_total(), st.stats == before, st.max_hp(), preview_txt, carry_txt])
	await move_to.call(find.call("확정", "Button"))
	await _p1_shot("statui_02_planned_preview", "planned STR+2 VIT+1, preview", true)
	# − takes one back
	await click.call(find.call("힘 STR", "Label").get_parent().get_child(2))
	print("[statui] after − on 힘: plan %s" % game_hud.stat_plan)
	await click.call(find.call("확정", "Button"))
	print("[statui] 확정 -> STR %d→%d, VIT %d→%d, max HP %d→%d, points %d, plan %s" % [before["STR"], st.stats["STR"], before["VIT"], st.stats["VIT"],
		hp0, st.max_hp(), st.stat_points, game_hud.stat_plan])
	await _p1_shot("statui_03_confirmed", "after confirm", true)
	# plan again, close without confirming -> discarded
	var before2 := st.stats.duplicate()
	var pts2 := st.stat_points
	await click.call(find.call("지구력 END", "Label").get_parent().get_child(3))
	var planned2 := game_hud.stat_plan.duplicate()
	game_hud.toggle_character()
	await _frames(3)
	print("[statui] planned %s then closed -> stats unchanged %s, points %d→%d, plan cleared %s" % [planned2, st.stats == before2, pts2, st.stat_points, game_hud.stat_plan.is_empty()])
	# the same hover box serves other panels' tooltips (inventory equipment button)
	game_hud.toggle_inventory()
	await _frames(4)
	var any_tip: Control = null
	var stack2: Array = [game_hud._panel]
	while not stack2.is_empty() and any_tip == null:
		var n2: Node = stack2.pop_back()
		if n2 is Control and n2.has_meta("tip"):
			any_tip = n2
		stack2.append_array(n2.get_children())
	if any_tip:
		await move_to.call(any_tip)
		print("[statui] inventory hover (%s) -> %s, plain tooltip left: %s" % [any_tip.get_class(), game_hud.tip_text().replace("\n", " / "), any_tip.tooltip_text != ""])
		await _p1_shot("statui_04_inventory_hover", "inventory tooltip in the same box", true)
	get_tree().quit()


## The protagonist's dialogue expressions (data/speakers.json "expressions"): each one shown in the
## real dialogue box, then the cat meeting's "sorry" branch, whose lines use sad / happy.
func _run_expressions_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	Game.set_story_stage(0)
	await wait_for_sprites()
	var box: DialogueBox = game_hud.dialogue
	var exprs: Dictionary = DialogueData.speakers()["player"].get("expressions", {})
	print("[expr] registered: %s" % exprs)
	game_hud.start_dialogue(CatCompanion.MEET_DIALOGUE)
	while box.active() and (box.event.get("type", "") != "line" or box.event.get("speaker", "") != "player"):
		if box.event.get("type", "") == "line":
			box.advance()
		await _frames(5)
	for e: String in [""] + exprs.keys():
		box._spotlight("player", e)
		await _seconds(0.3)
		var tex: Texture2D = box._left._image.texture
		var file := tex.resource_path.get_file() if tex else "(없음)"
		var want := "player%s.png" % ("_" + e if e != "" else "")
		print("[expr] %s -> %s %s" % [exprs.get(e, "기본"), file, "✔" if file == want else "✘"])
		await _p1_shot("expr_%s" % (e if e != "" else "default"), "expression %s" % e, true)
	box._spotlight("player", str(box.event.get("expression", "")))  # back to the line's own look
	var said := PackedStringArray()
	for i in 60:
		if not box.active():
			break
		var ev: Dictionary = box.event
		match ev.get("type", ""):
			"line":
				await _seconds(0.25)
				if ev.get("speaker", "") == "player":
					said.append("%s[%s → %s]" % [str(ev["text"]).left(12), ev.get("expression", ""), box._left._image.texture.resource_path.get_file()])
					if ev.get("expression", "") in ["sad", "happy"]:
						await _p1_shot("expr_line_%s" % ev["expression"], "cat meeting line", true)
				box.advance()
			"choice":
				var idx := 0
				for j in ev["options"].size():
					if ev["options"][j]["port"] == "go":
						idx = j
				box.choose_index(idx)
			_:
				await _frames(5)
		await _frames(3)
	print("[expr] cat meeting (sorry branch) hero lines: %s" % " | ".join(said))
	get_tree().quit()


func _run_dialogue_tour() -> void:
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	var p: PrototypePlayer = world.player
	var box: DialogueBox = game_hud.dialogue
	var rosa_stall: Vector3 = VisualLab.TRADE_STALLS[0][0]
	_place_player(rosa_stall + Vector3(0, 0, 1.5), 0.0)
	await _frames(5)
	var shots := {"dialogue.npc.rosa.main": ["line_offer", "choice_offer"],
		"dialogue.demo.cat_first_appearance": ["line_01", "line_02", "choice_01", "line_03"],
		"dialogue.demo.king_dragon_offer": ["line_01"]}
	for id: String in shots:
		if id == "dialogue.demo.cat_first_appearance":
			_place_player(Vector3(-4.0, 0, 3.2), 0.0)
			world.cat.global_position = p.global_position + Vector3(1.2, 0, 0.6)
			await _frames(5)
		game_hud.start_dialogue(id)
		for i in 30:
			if not box.active():
				break
			var ev: Dictionary = box.event
			if ev.get("type", "") == "cutscene" or ev.is_empty():
				box.advance()
				await _frames(5)
				continue
			await _seconds(0.2)  # let the dim fade settle
			print("[dialogue] %s %s %s '%s' | left %s%s a=%.2f image %s | right %s a=%.2f image %s" % [id.get_slice(".", 2), ev["node"], ev["type"],
				ev.get("speaker", "-"), box._left.speaker, "/" + box._left.expression if box._left.expression != "" else "", box._left.modulate.a,
				box._left.has_image(), box._right.speaker, box._right.modulate.a, box._right.has_image()])
			if ev["node"] in shots[id]:
				await _p1_shot("dialogue_%s_%s" % [id.get_slice(".", 2), ev["node"]], "dialogue portraits", true)
			if ev["type"] == "choice":
				box.choose_index(0)
			else:
				box.advance()
			await _frames(3)
		print("[dialogue] closed -> active %s, portraits cleared %s, controls %s" % [box.active(),
			box._left.speaker == "" and box._right.speaker == "", p.controls_enabled])
		await _frames(5)
	get_tree().quit()


# ---------------------------------------------------------------- P2-5 quests / dialogue

## Presses keys through an open dialogue: E for lines, the number key for choices (by port).
func _talk_through(picks: Array, log_prefix := "[quest]", max_steps := 40) -> PackedStringArray:
	var said := PackedStringArray()
	var pi := 0
	for i in max_steps:
		if not game_hud.dialogue_active():
			break
		var ev: Dictionary = game_hud.dialogue.event
		match ev.get("type", ""):
			"line":
				said.append("%s: %s" % [ev["name"], str(ev["text"]).split("\n")[0]])
				await _key(KEY_E)
			"choice":
				var want: String = picks[pi] if pi < picks.size() else ev["options"][0]["port"]
				pi += 1
				var idx := 0
				for j in ev["options"].size():
					if ev["options"][j]["port"] == want:
						idx = j
				said.append("[선택 %d. %s]" % [idx + 1, ev["options"][idx]["text"]])
				await _key(KEY_1 + idx)
			_:
				await _frames(5)  # cutscene playing
	print("%s   %s" % [log_prefix, " | ".join(said)])
	return said


func _run_quest_tour() -> void:
	Dice.rng.seed = 11
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	var p: PrototypePlayer = world.player
	var rosa_stall: Vector3 = VisualLab.TRADE_STALLS[0][0]
	var bron_stall: Vector3 = VisualLab.TRADE_STALLS[1][0]
	# --- NPC request through a dialogue (13.1: accepted directly)
	_place_player(rosa_stall + Vector3(0, 0, 1.5), 0.0)
	await _frames(5)
	var cam_before: Transform3D = world.camera.global_transform
	print("[quest] prompt at rosa: '%s'" % p.focus.prompt_text())
	await _key(KEY_R)
	print("[quest] R at rosa -> dialogue %s '%s', controls %s" % [game_hud.dialogue_active(), game_hud.dialogue.dialogue_id, p.controls_enabled])
	await _frames(3)
	await _p1_shot("quest_01_rosa_dialogue", "rosa offers a request in the dialogue box", true)
	await _key(KEY_E)
	await _frames(3)
	await _p1_shot("quest_02_choice", "choice", true)
	await _talk_through(["accept"])
	await _frames(20)
	print("[quest] after dialogue: state %s, controls %s, camera unchanged %s" % [Game.quests.state("quest.rosa.jelly"), p.controls_enabled,
		world.camera.global_transform.is_equal_approx(cam_before)])
	await _key(KEY_R)
	await _talk_through([])
	print("[quest] talk again while active -> state %s (no duplicate accept)" % Game.quests.state("quest.rosa.jelly"))
	st.inventory.add("slime_jelly", 5)
	await _frames(10)
	print("[quest] +5 jelly -> state %s" % Game.quests.state("quest.rosa.jelly"))
	var g0 := st.gold
	var e0 := st.gen_exp
	await _key(KEY_R)
	await _talk_through([])
	print("[quest] turn-in -> %s, gold %d -> %d, EXP %d -> %d, bread %d, jelly %d" % [Game.quests.state("quest.rosa.jelly"), g0, st.gold, e0, st.gen_exp,
		st.inventory.count("bread"), st.inventory.count("slime_jelly")])
	g0 = st.gold
	await _key(KEY_R)
	await _talk_through([])
	print("[quest] replay after completion -> gold %d (unchanged: %s)" % [st.gold, st.gold == g0])
	# --- notice board (repeatable, timed)
	_place_player(VisualLab.BOARD_POS + Vector3(0, 0, 1.3), 0.0)
	await _frames(5)
	await _key(KEY_E)
	print("[quest] E at board -> panel %s" % game_hud._panel_kind)
	Game.quests.accept("quest.board.slime_cull")
	Game.quests.accept("quest.board.urgent_forest")
	await _frames(5)
	await _p1_shot("quest_03_board", "notice board with two accepted requests", true)
	game_hud.close_panel()
	var killed := 0
	for m: SlimeMonster in world.monsters.duplicate():
		if m.monster_id.begins_with("meadow"):
			m._die()
			killed += 1
	await _frames(5)
	print("[quest] killed %d meadow slimes -> slime_cull %s (%s)" % [killed, Game.quests.state("quest.board.slime_cull"), ", ".join(Game.quests.objectives_text("quest.board.slime_cull"))])
	g0 = st.gold
	print("[quest] report at board: %s" % Game.quests.complete("quest.board.slime_cull"))
	print("[quest]   gold %d -> %d; repeatable can re-accept: %s -> accept '%s' state %s" % [g0, st.gold, Game.quests.can_accept("quest.board.slime_cull"),
		Game.quests.accept("quest.board.slime_cull"), Game.quests.state("quest.board.slime_cull")])
	print("[quest] urgent time left %.0f min" % Game.quests.time_left("quest.board.urgent_forest"))
	Game.advance_minutes(24.0 * 60.0 + 5.0)
	await _frames(3)
	print("[quest] +24h -> urgent %s, can re-accept %s" % [Game.quests.state("quest.board.urgent_forest"), Game.quests.can_accept("quest.board.urgent_forest")])
	Game.quests.accept("quest.board.urgent_forest")
	print("[quest] re-accepted urgent -> %s, %.0f min left" % [Game.quests.state("quest.board.urgent_forest"), Game.quests.time_left("quest.board.urgent_forest")])
	Game.minute_of_day = 10.5 * 60.0
	# --- field event: no acceptance, starts on arrival
	print("[quest] lost_parcels before arriving: %s" % Game.quests.state(VisualLab.PARCEL_QUEST))
	_place_player(VisualLab.CART_POS + Vector3(-1.0, 0, 2.6), 0.0)
	await _frames(10)
	print("[quest] arrived at the cart -> %s (auto, no acceptance)" % Game.quests.state(VisualLab.PARCEL_QUEST))
	await _p1_shot("quest_04_event_cart", "overturned cart field event", true)
	for spec: Array in VisualLab.PARCELS:
		_place_player(spec[1] + Vector3(0, 0, 0.9), 0.0)
		await _frames(5)
		await _key(KEY_E)
	await _frames(10)
	print("[quest] parcels %d -> %s" % [st.inventory.count("lost_parcel"), Game.quests.state(VisualLab.PARCEL_QUEST)])
	# --- two resolutions at the blacksmith (13.2): return for free -> life EXP only
	_place_player(bron_stall + Vector3(0, 0, 1.5), 0.0)
	await _frames(5)
	var life0 := st.life_exp
	g0 = st.gold
	await _key(KEY_R)
	await _talk_through(["return"])
	print("[quest] bron, returned for free -> %s, life EXP %d -> %d, gold %d -> %d, parcels %d, flag bron.trust %s" % [
		Game.quests.state(VisualLab.PARCEL_QUEST), life0, st.life_exp, g0, st.gold, st.inventory.count("lost_parcel"), Game.narrative.get_flag("bron.trust")])
	await _key(KEY_R)
	await _talk_through([])
	# --- journal + tracker
	await _seconds(2.8)  # let the toasts fade
	await _key(KEY_J)
	print("[quest] J -> panel %s" % game_hud._panel_kind)
	await _p1_shot("quest_05_journal", "quest journal (J)", true)
	await _key(KEY_J)
	# --- CutsceneCall through the same runner (test data)
	_place_player(Vector3(-4.0, 0, 3.2), 0.0)
	await _frames(10)
	world.cat.global_position = p.global_position + Vector3(-4.5, 0, 1.5)  # start out of the way
	var cat_from: Vector3 = world.cat.global_position
	cam_before = world.camera.global_transform
	game_hud.start_dialogue("dialogue.demo.cat_first_appearance")
	await _key(KEY_E)
	await _seconds(0.8)
	print("[quest] cutscene playing %s, caption '%s'" % [game_hud.cutscene.playing, game_hud._caption.text])
	await _p1_shot("quest_06_cutscene_caption", "cutscene caption", true)
	while game_hud.cutscene.playing:
		await _frames(2)
	print("[quest] cutscene done: cat moved %.1f m" % cat_from.distance_to(world.cat.global_position))
	await _talk_through(["look"])
	print("[quest] after cutscene dialogue: event recorded %s, controls %s, camera unchanged %s" % [Game.narrative.event_done("demo.cat_first_appearance"),
		p.controls_enabled, world.camera.global_transform.is_equal_approx(cam_before)])
	# --- the editor's "run in game" hand-off file
	var f := FileAccess.open(PLAYTEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"dialogue_id": "dialogue.demo.king_dragon_offer"}))
	f.close()
	await _check_dialogue_playtest()
	print("[quest] playtest file -> dialogue %s '%s', file removed %s" % [game_hud.dialogue_active(), game_hud.dialogue.dialogue_id, not FileAccess.file_exists(PLAYTEST_PATH)])
	await _p1_shot("quest_07_playtest_king", "editor playtest: king test dialogue", true)
	await _talk_through(["accept"])
	print("[quest] tracker:\n%s" % game_hud._tracker_text())
	get_tree().quit()


# ---------------------------------------------------------------- P3-1 regions

func _wait_travel() -> void:
	await _frames(2)
	while _busy:
		await _frames(2)
	await wait_for_sprites()
	await _frames(10)


func _run_region_tour() -> void:
	Dice.rng.seed = 21
	Game.clock_running = false
	Game.minute_of_day = 11.0 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	print("[region] start: %s, regions %s" % [Game.region, ", ".join(PackedStringArray(RegionDB.all().keys()))])
	var ex: Dictionary = world.exits[0]
	var exit_pos: Vector3 = ex["pos"]
	_place_player(exit_pos + Vector3(-5.5, 0, 0.4), -PI * 0.5)
	await _frames(10)
	print("[region] near the road exit -> hint '%s'" % world.context_hint())
	await _p1_shot("region_01_meadow_exit", "meadow road exit to the highland", true)
	# --- on foot: loading screen, camper stays in the meadow
	_place_player(exit_pos, -PI * 0.5)
	await _seconds(1.0)
	print("[region] walked into the exit -> travelling %s" % _busy)
	await _p1_shot("region_02_loading", "loading screen", true)
	await _wait_travel()
	var p: PrototypePlayer = world.player
	print("[region] now %s (%s), player at (%.1f, %.1f), camper in %s, camper here %s" % [Game.region, world.world_title(), p.global_position.x,
		p.global_position.z, Game.camper["region"], world.camper_here()])
	await _p1_shot("region_03_highland_arrival", "highland arrival (on foot, cat follows)", true)
	# --- fixed difficulty (7.5): same player, stronger monsters here
	var kinds := PackedStringArray()
	for m: SlimeMonster in world.monsters:
		if not kinds.has(m.kind):
			kinds.append(m.kind)
	print("[region] highland monsters: %s" % ", ".join(kinds))
	for kid in ["meadow_slime", "forest_slime", "moss_slime", "rock_slime"]:
		var d := MonsterDB.info(kid)
		print("[region]   %s: HP %d, 피해 %s, AC %d, 방어 %d, EXP %d, 선공 %s" % [d["name"], d["hp"], d["profile"]["phys"], d["profile"]["ac"],
			d["profile"]["armor"], d["exp"], d["aggressive"]])
	var hits := 0
	var dmg := 0
	for i in 40:
		var r := Combat.resolve(st.combat_profile(), MonsterDB.info("rock_slime")["profile"].merged({"name": "바위 슬라임"}))
		hits += 1 if r["hit"] else 0
		dmg += int(r.get("damage", 0))
	var hits2 := 0
	for i in 40:
		hits2 += 1 if Combat.resolve(st.combat_profile(), MonsterDB.info("meadow_slime")["profile"].merged({"name": "풀밭 슬라임"}))["hit"] else 0
	print("[region] 40 swings: hit rock slime %d times (damage %d total), meadow slime %d times" % [hits, dmg, hits2])
	_place_player(Vector3(-9.5, 0, -8.5), PI)
	await _frames(20)
	await _p1_shot("region_04_rock_slimes", "highland hills with rock slimes", true)
	# kill one rock slime: remembered per region
	var victim: SlimeMonster = null
	for m: SlimeMonster in world.monsters:
		if m.kind == "rock_slime":
			victim = m
			break
	var vid := victim.monster_id
	victim._die()
	await _frames(5)
	print("[region] killed %s -> highland field dead %s, loot %d" % [vid, Game.field["dead"].keys(), Game.field["loot"].size()])
	# quest trigger of the meadow event does not fire here
	Game.quests.entries.erase("quest.event.lost_parcels")
	Game.quests.check_triggers(Vector3(40.3, 0, -5.4))
	print("[region] meadow event trigger coords in the highland -> %s" % Game.quests.state("quest.event.lost_parcels"))
	# --- walk back west
	var back: Dictionary = world.exits[0]
	await _seconds(VisualLab.EXIT_GRACE)
	_place_player(back["pos"], PI * 0.5)
	await _seconds(0.5)
	await _wait_travel()
	print("[region] back in %s at (%.1f, %.1f); camper here %s; highland dead remembered %s" % [Game.region, world.player.global_position.x,
		world.player.global_position.z, world.camper_here(), Game.fields["highland"]["dead"].has(vid)])
	# --- drive the camper through: it comes along and stays parked there
	world.vehicle.global_position = Vector3(exit_pos.x - 7.0, world.ground_height(exit_pos.x - 7.0, exit_pos.z), exit_pos.z)
	world.vehicle.rotation.y = 0.0
	world.enter_vehicle()
	await _frames(5)
	world.vehicle.global_position = Vector3(exit_pos.x, world.vehicle.global_position.y, exit_pos.z)
	await _seconds(0.5)
	await _wait_travel()
	print("[region] drove through -> %s, driving %s, camper in %s at (%.1f, %.1f)" % [Game.region, world.vehicle.driving, Game.camper["region"],
		world.vehicle.global_position.x, world.vehicle.global_position.z])
	await _p1_shot("region_05_drive_in", "arrived in the highland driving the camper", true)
	world.exit_vehicle()
	await _frames(5)
	print("[region] got out -> parked in %s" % Game.camper["region"])
	# --- death in the highland with the camper here: wake inside, step out in the highland
	world.player.global_position = world.player.global_position + Vector3(4, 0, 2)
	await _frames(3)
	st.inventory.add("slime_jelly", 3)
	on_player_died(world.player.global_position)
	while _busy:
		await _frames(2)
	print("[region] died -> world %s" % ("interior" if world is CamperInteriorLab else Game.region))
	Game.request_world(Game.WORLD_EXTERIOR)
	await _frames(3)
	await wait_for_sprites()
	print("[region] stepped out of the camper -> %s, camper here %s, death bag in highland loot %d" % [Game.region, world.camper_here(), Game.field["loot"].size()])
	# --- walk to the meadow without the camper, then open the map
	await _seconds(VisualLab.EXIT_GRACE + 0.2)
	_place_player(world.exits[0]["pos"], PI * 0.5)
	await _seconds(0.5)
	await _wait_travel()
	print("[region] walked back to %s: camper here %s, F -> '%s'" % [Game.region, world.camper_here(), world.try_toggle_camper_lights()])
	_place_player(Vector3(44.6, 0, 2.0), 0.0)  # crossroad checkpoint -> discovered
	await _frames(10)
	print("[region] discovered: %s" % ", ".join(PackedStringArray(Game.discovered.keys())))
	await _seconds(2.6)
	await _key(KEY_M)
	print("[region] M -> panel %s" % game_hud._panel_kind)
	await _p1_shot("region_06_world_map", "world map: two regions, road link, camper in the highland", true)
	await _key(KEY_M)
	get_tree().quit()


# ---------------------------------------------------------------- P3-2 fixed dungeon

func _run_dungeon_tour() -> void:
	Dice.rng.seed = 33
	Game.clock_running = false
	Game.minute_of_day = 13.0 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	# drive the camper to the highland, then try to drive into the cave
	var east: Vector3 = world.exits[0]["pos"]
	world.vehicle.global_position = Vector3(east.x - 7.0, world.ground_height(east.x - 7.0, east.z), east.z)
	world.vehicle.rotation.y = 0.0
	world.enter_vehicle()
	await _frames(3)
	world.vehicle.global_position = Vector3(east.x, world.vehicle.global_position.y, east.z)
	await _seconds(0.5)
	await _wait_travel()
	var mouth: Dictionary = {}
	for ex: Dictionary in world.exits:
		if ex["to_region"] == "cave":
			mouth = ex
	var mp: Vector3 = mouth["pos"]
	await _seconds(VisualLab.EXIT_GRACE)
	world.vehicle.global_position = Vector3(mp.x, world.ground_height(mp.x, mp.z), mp.z + 0.3)
	await _seconds(1.0)
	print("[dungeon] drove into the cave mouth -> still %s (busy %s), camper stays outside" % [Game.region, _busy])
	world.vehicle.global_position = Vector3(mp.x + 4.0, world.ground_height(mp.x + 4.0, mp.z + 7.0), mp.z + 7.0)
	world.vehicle.speed = 0.0
	await _frames(3)
	world.exit_vehicle()
	await _frames(5)
	_place_player(mp + Vector3(0, 0, 5.0), PI)
	await _frames(15)
	print("[dungeon] at the cave mouth -> hint '%s'" % world.context_hint())
	await _p1_shot("dungeon_00_cave_mouth", "highland cave mouth", true)
	_place_player(mp, PI)
	await _seconds(0.5)
	await _wait_travel()
	print("[dungeon] entered -> %s (%s), dungeon %s, safe room %s" % [Game.region, world.world_title(), world.is_dungeon(),
		world.checkpoints[0]["name"] if not world.checkpoints.is_empty() else "-"])
	var kinds := {}
	for m: SlimeMonster in world.monsters:
		kinds[m.kind] = int(kinds.get(m.kind, 0)) + 1
	print("[dungeon] monsters %s" % kinds)
	await _seconds(2.6)
	await _p1_shot("dungeon_01_entrance", "dark entrance room lit by torches", true)
	# one-time chest
	var chest: LootContainer = null
	for lc in world.find_children("*", "LootContainer", false, false):
		if (lc as LootContainer).data["id"] == "chest_0":
			chest = lc
	_place_player(chest.global_position + Vector3(0, 0, 1.1), PI)
	await _frames(8)
	await _key(KEY_E)
	print("[dungeon] E at the chest -> panel %s, contents %d" % [game_hud._panel_kind, chest.inventory().unit_count()])
	await _p1_shot("dungeon_02_chest", "one-time treasure chest", true)
	for e in chest.inventory().duplicate_items():
		st.inventory.add(e["id"], e["count"])
	chest.inventory().clear()
	game_hud.close_panel()
	# the boss
	var boss: SlimeMonster = null
	for m: SlimeMonster in world.monsters:
		if m.kind == "slime_king":
			boss = m
	print("[dungeon] boss %s: HP %d, %s, AC %d, scale %.1f" % [boss.display_name, boss.max_hp, boss.profile["phys"], boss.profile["ac"], boss.body_scale])
	_place_player(boss.global_position + Vector3(-4.5, 0, 1.0), -PI * 0.4)
	await _frames(20)
	await _p1_shot("dungeon_03_boss", "slime king in the deep hall", true)
	var bid := boss.monster_id
	boss._die()
	var victim: SlimeMonster = null
	for m: SlimeMonster in world.monsters:
		if m.kind == "cave_slime":
			victim = m
	var vid := victim.monster_id
	victim._die()
	await _frames(5)
	print("[dungeon] killed boss + %s; defeated %s" % [vid, Game.field.get("defeated", {}).keys()])
	Game.advance_minutes(3 * 1440.0)
	world._respawn_check()
	await _frames(5)
	var back_ids := PackedStringArray()
	for m: SlimeMonster in world.monsters:
		back_ids.append(m.monster_id)
	print("[dungeon] +3 days: %s respawned %s, boss respawned %s" % [vid, back_ids.has(vid), back_ids.has(bid)])
	# death in the dungeon, no camper yet: field rules + nearest safe checkpoint (the entrance room)
	Game.set_story_stage(1)
	await _frames(5)
	var death_at := Vector3(10.0, 0, 6.0)
	_place_player(death_at, 0.0)
	await _frames(5)
	var before := st.inventory.unit_count()
	on_player_died(world.player.global_position)
	while _busy:
		await _frames(2)
	var bag := {}
	for d: Dictionary in Game.field["loot"]:
		if d["kind"] == "bag":
			bag = d
	print("[dungeon] died with %d items -> woke in %s at (%.1f, %.1f); bag left at (%.1f, %.1f) with %d (rest taken by goblins)" % [before, Game.region,
		world.player.global_position.x, world.player.global_position.z, bag["pos"].x, bag["pos"].z, bag["inv"].unit_count()])
	await _p1_shot("dungeon_04_wake_safe_room", "woke at the dungeon's safe room, cat beside", true)
	Game.set_story_stage(2)
	await _frames(5)
	# with the camper: rescued into the camper, step out where it is parked (the highland)
	on_player_died(world.player.global_position)
	while _busy:
		await _frames(2)
	Game.request_world(Game.WORLD_EXTERIOR)
	await _frames(3)
	await wait_for_sprites()
	print("[dungeon] died with the camper -> stepped out in %s; cave bag still there %s" % [Game.region, not Game.fields["cave"]["loot"].filter(func(d: Dictionary) -> bool: return d["kind"] == "bag").is_empty()])
	_place_player(world.player.global_position, 0.0)
	await _seconds(2.0)
	await _key(KEY_M)
	await _p1_shot("dungeon_05_map", "map with the found cave", true)
	await _key(KEY_M)
	# walk back in and out through the dungeon exit
	_place_player(mp, PI)
	await _seconds(0.5)
	await _wait_travel()
	await _seconds(VisualLab.EXIT_GRACE)
	var out: Vector3 = world.exits[0]["pos"]
	_place_player(out, 0.0)
	await _seconds(0.5)
	await _wait_travel()
	print("[dungeon] left through the exit -> %s at (%.1f, %.1f)" % [Game.region, world.player.global_position.x, world.player.global_position.z])
	get_tree().quit()


# ---------------------------------------------------------------- P3-3 random dungeon

func _take_all(lc: LootContainer) -> int:
	var n := 0
	for e in lc.inventory().duplicate_items():
		Game.player_state.inventory.add(e["id"], e["count"])
		n += int(e["count"])
	lc.inventory().clear()
	return n


func _rift_chests() -> Array:
	return world.find_children("*", "LootContainer", false, false).filter(func(lc: LootContainer) -> bool: return lc.data["kind"] == "chest")


func _gained_text() -> String:
	var g := Game.run_gained()
	var parts := PackedStringArray()
	for id: String in g:
		parts.append("%s×%d" % [ItemDB.item_name(id), g[id]])
	return ", ".join(parts) if not parts.is_empty() else "-"


func _owned_text(d: Dictionary) -> String:
	var parts := PackedStringArray()
	for id: String in d:
		parts.append("%s×%d" % [id, d[id]])
	return ", ".join(parts)


func _enter_rift() -> void:
	Game.start_run("rift")
	travel("rift", "start", false)
	await _wait_travel()


func _run_rift_tour() -> void:
	Dice.rng.seed = 44
	seed(44)
	Game.clock_running = false
	Game.minute_of_day = 12.0 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	st.inventory.add("heal_potion", 2)  # brought from outside: never lost
	var gate: Dictionary = {}
	for ex: Dictionary in world.exits:
		if ex.get("style", "") == "rift":
			gate = ex
	var gp: Vector3 = gate["pos"]
	_place_player(gp + Vector3(0, 0, 3.0), 0.0)
	await _frames(15)
	await _p1_shot("rift_00_gate", "random dungeon gate in the meadow", true)
	_place_player(gp + Vector3(0, 0, 2.1), 0.0)
	await _frames(6)
	await _key(KEY_E)
	print("[rift] E at the gate -> panel %s (walking past does not enter: region %s)" % [game_hud._panel_kind, Game.region])
	await _p1_shot("rift_01_warning", "warning before entering", true)
	game_hud.close_panel()
	# ---- run A: floor 1 -> 2, then escape with the loot
	var before_a := Game.owned_counts()
	await _enter_rift()
	var grid_a1: Array = world.region["grid"]
	print("[rift] run A floor %d: %dx%d grid, monsters %d, chests %d, exit at %s" % [Game.run["floor"], str(grid_a1[0]).length(), grid_a1.size(),
		world.monsters.size(), _rift_chests().size(), world.region.get("_floor_exit")])
	await _seconds(2.6)
	await _p1_shot("rift_02_floor1", "floor 1", true)
	for lc: LootContainer in _rift_chests():
		_take_all(lc)
	var m: SlimeMonster = world.monsters[0]
	m._die()
	await _frames(3)
	for lc: LootContainer in world.find_children("*", "LootContainer", false, false):
		if lc.data["kind"] == "corpse":
			_take_all(lc)
	print("[rift]   after chest + a kill: gained %s" % _gained_text())
	var ex: Array = world.region["_floor_exit"]
	_place_player(Vector3(float(ex[0]), 0, float(ex[1]) + 0.6), 0.0)
	await _frames(8)
	await _key(KEY_E)
	print("[rift]   E at the floor exit -> panel %s" % game_hud._panel_kind)
	await _p1_shot("rift_03_floor_exit", "floor exit: escape or go down", true)
	game_hud.close_panel()
	Game.next_floor()
	travel("rift", "start", false)
	await _wait_travel()
	var grid_a2: Array = world.region["grid"]
	print("[rift] run A floor %d: %dx%d grid (bigger), monsters %d, kinds %s" % [Game.run["floor"], str(grid_a2[0]).length(), grid_a2.size(),
		world.monsters.size(), world.region["spawn_kinds"]])
	await _seconds(2.6)
	await _p1_shot("rift_04_floor2", "floor 2", true)
	for lc: LootContainer in _rift_chests():
		_take_all(lc)
	var gained_a := Game.run_gained()
	print("[rift]   floor 2 chest -> gained %s" % _gained_text())
	# escape through the exit (same code path as the panel button)
	var did := "rift"
	var ent: Dictionary = RegionDB.all()[did]["entrance"]
	Game.end_run(true)
	travel(ent["region"], ent["entry"], false)
	await _wait_travel()
	var after_a := Game.owned_counts()
	var kept_all := true
	for id: String in gained_a:
		kept_all = kept_all and int(after_a.get(id, 0)) >= int(before_a.get(id, 0)) + int(gained_a[id])
	print("[rift] escaped -> %s, run active %s, kept everything found %s" % [Game.region, Game.in_run(), kept_all])
	# ---- run B: new layout; equip a found piece; die without a camper -> lose only the run's loot
	Game.set_story_stage(1)
	await _frames(5)
	await _seconds(VisualLab.EXIT_GRACE)
	var before_b := Game.owned_counts()
	var exp_b := st.gen_exp
	await _enter_rift()
	var grid_b1: Array = world.region["grid"]
	print("[rift] run B floor 1 layout differs from run A floor 1: %s" % (grid_b1 != grid_a1))
	for lc: LootContainer in _rift_chests():
		_take_all(lc)
	st.inventory.add("leather_cap", 1)  # stands in for a looted piece
	st.equip("leather_cap")
	m = world.monsters[0]
	m._die()
	await _frames(3)
	print("[rift]   run B gained %s (cap worn: %s), EXP %d -> %d" % [_gained_text(), st.equipment["head"], exp_b, st.gen_exp])
	await _key(KEY_I)
	print("[rift]   I (debug interior) during the run -> still %s" % Game.region)
	var exp_before_death := st.gen_exp
	on_player_died(world.player.global_position)
	while _busy:
		await _frames(2)
	var after_b := Game.owned_counts()
	print("[rift] died -> woke in %s at (%.1f, %.1f), run active %s, head slot '%s'" % [Game.region, world.player.global_position.x,
		world.player.global_position.z, Game.in_run(), st.equipment["head"]])
	print("[rift]   owned before run B: %s" % _owned_text(before_b))
	print("[rift]   owned after death : %s" % _owned_text(after_b))
	print("[rift]   same as before the run: %s; EXP kept %s (%d)" % [after_b == before_b, st.gen_exp == exp_before_death, st.gen_exp])
	await _p1_shot("rift_05_after_death", "woke at the lake checkpoint, run loot gone", true)
	# ---- run C with the camper: rescued into the camper
	Game.set_story_stage(2)
	await _frames(5)
	await _seconds(VisualLab.EXIT_GRACE)
	await _enter_rift()
	on_player_died(world.player.global_position)
	while _busy:
		await _frames(2)
	print("[rift] run C death with the camper -> %s, run active %s" % ["interior" if world is CamperInteriorLab else Game.region, Game.in_run()])
	Game.request_world(Game.WORLD_EXTERIOR)
	await _frames(3)
	await wait_for_sprites()
	print("[rift]   stepped out -> %s; random dungeon on the map: %s" % [Game.region, WorldMap.known("rift", RegionDB.all()["rift"])])
	get_tree().quit()


# ---------------------------------------------------------------- P3-4 gathering / fishing

func _gather_node(id: String) -> GatherNode:
	for n: GatherNode in world.gather_nodes:
		if n.node_id == id:
			return n
	return null


func _wait_task() -> void:
	var p: PrototypePlayer = world.player
	await _frames(2)
	while p.is_using():
		await _frames(2)
	await _frames(3)


func _run_life_tour() -> void:
	Dice.rng.seed = 55
	seed(55)
	Game.clock_running = false
	Game.minute_of_day = 11.0 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	var p: PrototypePlayer = world.player
	# --- gathering
	var herb := _gather_node("herb_1")
	_place_player(herb.global_position + Vector3(0, 0, 1.1), 0.0)
	await _frames(8)
	print("[life] at the herb -> '%s'" % p.focus.prompt_text())
	await _key(KEY_E)
	await _seconds(0.5)
	print("[life] E -> gathering motion %s ('%s')" % [p.is_using(), p.use_label()])
	await _p1_shot("life_01_gathering", "short gathering motion", true)
	await _wait_task()
	print("[life] gathered: herb %d, life EXP %d, gathering mastery %d (Lv %d), spot regrowing %s" % [st.inventory.count("herb"), st.life_exp,
		st.mastery["gathering"], st.mastery_level("gathering"), herb.depleted()])
	# hit cancels a gathering motion, nothing gained
	var berry := _gather_node("berry_1")
	_place_player(berry.global_position + Vector3(0, 0, 1.1), 0.0)
	await _frames(8)
	await _key(KEY_E)
	await _frames(5)
	p.cancel_use("피격")
	await _frames(3)
	print("[life] hit while picking berries -> berries %d, spot still full %s" % [st.inventory.count("wild_berry"), not berry.depleted()])
	await _key(KEY_E)
	await _wait_task()
	print("[life] picked berries -> %d (edible: %s)" % [st.inventory.count("wild_berry"), ItemDB.is_consumable("wild_berry")])
	# moonflower: closed by day, opens at night (rare resource with a condition)
	var moon := _gather_node("moon_1")
	_place_player(moon.global_position + Vector3(0, 0, 1.1), 0.0)
	await _frames(8)
	print("[life] moonflower by day -> '%s'" % p.focus.prompt_text())
	await _key(KEY_E)
	await _frames(5)
	print("[life]   E by day -> using %s, petals %d" % [p.is_using(), st.inventory.count("moon_petal")])
	Game.minute_of_day = 22.0 * 60.0
	await _seconds(1.2)
	await _p1_shot("life_02_moonflower_night", "moonflower glowing at night", true)
	await _key(KEY_E)
	await _wait_task()
	print("[life]   at night -> petals %d, life EXP %d" % [st.inventory.count("moon_petal"), st.life_exp])
	Game.minute_of_day = 11.0 * 60.0
	Game.advance_minutes(12.0 * 60.0 + 1.0)
	await _seconds(1.2)
	print("[life] +12h -> herb spot back %s" % [not herb.depleted()])
	# --- fishing
	st.inventory.add("fishing_rod", 1)
	var spot: Dictionary = world.region["fishing_spots"][0]
	_place_player(RegionDB.v3(spot["pos"]), 0.0)
	await _frames(8)
	print("[life] at the pier -> '%s'" % p.focus.prompt_text())
	await _key(KEY_E)
	await _seconds(0.8)
	print("[life] E -> automatic fishing %s (%s)" % [game_hud.fishing.active, game_hud.fishing._phase])
	await _p1_shot("life_03_fishing_wait", "automatic fishing, waiting for a bite", true)
	var res := {"r": ""}
	game_hud.fishing.finished.connect(func(r: String) -> void: res["r"] = r)
	while game_hud.fishing.active and game_hud.fishing._phase != "result":
		await _frames(2)
	print("[life]   auto result: %s, life EXP %d, fishing mastery %d" % [res["r"], st.life_exp, st.mastery["fishing"]])
	while game_hud.fishing.active:
		await _frames(2)
	# manual minigame: press when the marker is in the green zone
	await _key(KEY_R)
	while game_hud.fishing._phase == "wait":
		await _frames(2)
	await _frames(10)
	await _p1_shot("life_04_minigame", "manual fishing minigame", true)
	var guard := 0
	while game_hud.fishing._phase == "game" and guard < 2000:
		guard += 1
		var fp := game_hud.fishing
		var x := fp._marker.position.x / maxf(1.0, fp._bar.size.x - fp._marker.size.x)
		if x > fp._zone.x + 0.02 and x < fp._zone.y - 0.02:
			fp.press()  # pressed right on time (the key route itself is covered by E / R above)
		await _frames(1)
	print("[life]   manual result: %s, life EXP %d, fishing mastery %d" % [res["r"], st.life_exp, st.mastery["fishing"]])
	while game_hud.fishing.active:
		await _frames(2)
	# hit while fishing
	await _key(KEY_E)
	await _seconds(0.5)
	p.cancel_use("피격")
	await _frames(3)
	print("[life] hit while fishing -> %s (%s)" % [res["r"], game_hud.fishing._label.text])
	while game_hud.fishing.active:
		await _frames(2)
	# auto vs manual odds (14.2: by hand is better)
	var f := LifeDB.fishing()
	var rare_w := 0.0
	var all_w := 0.0
	for e: Dictionary in f["fish"]:
		all_w += float(e["w"])
		rare_w += float(e["w"]) if e.get("rare", false) else 0.0
	var rm := float(f["manual_rare_mult"])
	print("[life] odds: auto success %.0f%% / manual = your timing; rare fish auto %.1f%% vs manual %.1f%%; manual life EXP x%.1f" % [
		float(f["auto_success"]) * 100.0, rare_w / all_w * 100.0, rare_w * rm / (all_w - rare_w + rare_w * rm) * 100.0, float(f["manual_exp_mult"])])
	# --- mastery and life skills
	st.add_mastery("gathering", 20)
	st.life_exp = maxi(st.life_exp, 20)
	print("[life] gathering Lv %d, gather_knack block '%s' -> learn %s, life EXP left %d" % [st.mastery_level("gathering"), st.life_skill_block("gather_knack"),
		st.learn_life_skill("gather_knack"), st.life_exp])
	print("[life] angler_sense block: '%s'" % st.life_skill_block("angler_sense"))
	await _seconds(2.8)  # let toasts fade
	await _key(KEY_C)
	await _p1_shot("life_05_character", "character panel: life EXP, mastery, life skills", true)
	await _key(KEY_C)
	# life-EXP-only quest reward (13.4)
	Game.quests.accept("quest.board.herbs")
	st.inventory.add("herb", 4)
	await _frames(3)
	var le := st.life_exp
	var ge := st.gen_exp
	print("[life] herb delivery: %s -> life EXP %d -> %d, general EXP %d -> %d" % [Game.quests.complete("quest.board.herbs"), le, st.life_exp, ge, st.gen_exp])
	get_tree().quit()


# ---------------------------------------------------------------- P3-5 cooking / crafting

func _craft_and_wait(rid: String, facility: String) -> bool:
	var ok := game_hud.craft(rid, facility)
	await _wait_task()
	return ok


func _counts(ids: Array) -> String:
	var parts := PackedStringArray()
	for id: String in ids:
		parts.append("%s %d" % [ItemDB.item_name(id), Game.player_state.inventory.count(id)])
	return ", ".join(parts)


func _run_craft_tour() -> void:
	Dice.rng.seed = 66
	seed(66)
	Game.clock_running = false
	Game.minute_of_day = 15.0 * 60.0
	await wait_for_sprites()
	var st := Game.player_state
	var p: PrototypePlayer = world.player
	for kv in [["small_fish", 2], ["trout", 1], ["edible_mushroom", 3], ["herb", 9], ["wild_berry", 5], ["slime_jelly", 4],
			["firewood", 2], ["slime_core", 1], ["golden_carp", 1], ["moon_petal", 2], ["mana_shard", 1], ["recipe_moon_charm", 1]]:
		st.inventory.add(kv[0], kv[1])
	st.life_exp = 40
	# --- away from any facility: simple crafting only
	_place_player(Vector3(6.0, 0, 8.0), 0.0)
	await _frames(8)
	await _key(KEY_U)
	print("[craft] U in the field -> panel %s, facility '%s'" % [game_hud._panel_kind, game_hud.nearby_facility()])
	print("[craft]   known: %s" % ", ".join(PackedStringArray(RecipeDB.all().keys().filter(func(r: String) -> bool: return st.knows_recipe(r)))))
	print("[craft]   grilled fish here -> '%s'" % game_hud._recipe_block("grilled_fish", ""))
	print("[craft]   learn herbal salve (basic, life EXP 5): %s -> life EXP %d" % [st.buy_recipe("herbal_salve"), st.life_exp])
	game_hud._refresh_panel()
	await _frames(3)
	await _p1_shot("craft_01_field_panel", "recipe panel without a facility", true)
	print("[craft]   salve crafted anywhere: %s -> %s" % [await _craft_and_wait("herbal_salve", ""), _counts(["herbal_salve", "herb", "slime_jelly"])])
	game_hud.close_panel()
	# --- campfire: cooking
	_place_player(VisualLab.CAMPFIRE_POS + Vector3(-1.1, 0, 1.6), 0.0)
	await _frames(8)
	print("[craft] at the campfire -> '%s'" % (p.focus.prompt_text() if p.focus else "-"))
	await _key(KEY_E)
	print("[craft]   E -> panel %s, facility '%s'" % [game_hud._panel_kind, game_hud.nearby_facility()])
	var before_life := st.life_exp
	print("[craft]   grilled fish: %s -> %s, life EXP %d -> %d, cooking mastery %d" % [await _craft_and_wait("grilled_fish", "cooking"),
		_counts(["grilled_fish", "small_fish"]), before_life, st.life_exp, st.mastery["cooking"]])
	st.buy_recipe("mushroom_skewer")
	st.buy_recipe("herb_tea")
	game_hud._refresh_panel()
	await _frames(3)
	await _p1_shot("craft_02_campfire", "cooking at the campfire", true)
	game_hud.craft("herb_tea", "cooking")
	await _seconds(0.5)
	p.cancel_use("피격")
	await _frames(3)
	print("[craft]   hit while brewing tea -> %s (nothing used up)" % _counts(["herb_tea", "herb", "wild_berry"]))
	print("[craft]   skewer: %s, tea: %s -> %s" % [await _craft_and_wait("mushroom_skewer", "cooking"), await _craft_and_wait("herb_tea", "cooking"),
		_counts(["mushroom_skewer", "herb_tea"])])
	game_hud.close_panel()
	# --- workbench: complex crafting
	_place_player(VisualLab.WORKBENCH_POS + Vector3(0, 0, 1.5), 0.0)
	await _frames(8)
	await _key(KEY_E)
	print("[craft] workbench -> panel %s, facility '%s'" % [game_hud._panel_kind, game_hud.nearby_facility()])
	st.buy_recipe("fishing_rod")
	print("[craft]   fishing rod: %s -> rods %d" % [await _craft_and_wait("fishing_rod", "workbench"), st.inventory.count("fishing_rod")])
	print("[craft]   heal potion recipe -> '%s'" % st.recipe_learn_block("heal_potion"))
	st.add_mastery("crafting", 40)
	print("[craft]   crafting Lv %d -> learn %s, potion %s -> potions %d" % [st.mastery_level("crafting"), st.buy_recipe("heal_potion"),
		await _craft_and_wait("heal_potion", "workbench"), st.inventory.count("heal_potion")])
	# special: book (read the scroll) -> moon charm
	print("[craft]   moon charm before the scroll -> '%s'" % st.recipe_learn_block("moon_charm"))
	p.begin_use_item("recipe_moon_charm")
	await _wait_task()
	print("[craft]   read the scroll -> knows moon charm %s; craft %s -> charms %d" % [st.knows_recipe("moon_charm"),
		await _craft_and_wait("moon_charm", "workbench"), st.inventory.count("moon_charm")])
	game_hud._refresh_panel()
	await _frames(3)
	await _p1_shot("craft_03_workbench", "workbench panel", true)
	game_hud.close_panel()
	# special: quest reward (berry jam) and NPC (golden carp stew from Rosa)
	Game.quests.accept("quest.rosa.jelly")
	st.inventory.add("slime_jelly", 5)
	await _frames(3)
	Game.quests.complete("quest.rosa.jelly")
	print("[craft] Rosa's quest reward -> knows berry jam %s" % st.knows_recipe("berry_jam"))
	var rosa_stall: Vector3 = VisualLab.TRADE_STALLS[0][0]
	Game.minute_of_day = 11.0 * 60.0
	await _seconds(3.0)
	_place_player(rosa_stall + Vector3(0, 0, 1.5), 0.0)
	await _frames(8)
	await _key(KEY_R)
	await _talk_through([], "[craft]")
	print("[craft] talked to Rosa -> knows golden carp stew %s" % st.knows_recipe("golden_carp_stew"))
	await _key(KEY_R)
	await _talk_through([], "[craft]")
	# camper kitchen
	Game.request_world(Game.WORLD_INTERIOR)
	await _frames(5)
	await wait_for_sprites()
	await _frames(10)
	var kitchen: Node3D = null
	for ip in get_tree().get_nodes_in_group("facility"):
		kitchen = ip
	world.player.global_position = Vector3(kitchen.global_position.x, world.player.global_position.y, kitchen.global_position.z + 0.3)
	await _frames(8)
	await _key(KEY_E)
	print("[craft] camper kitchen -> panel %s, facility '%s'" % [game_hud._panel_kind, game_hud.nearby_facility()])
	print("[craft]   golden carp stew: %s -> %s, cooking Lv %d, life EXP %d" % [await _craft_and_wait("golden_carp_stew", "cooking"),
		_counts(["golden_carp_stew", "golden_carp"]), st.mastery_level("cooking"), st.life_exp])
	game_hud._refresh_panel()
	await _frames(3)
	await _p1_shot("craft_04_camper_kitchen", "cooking in the camper kitchen", true)
	var tea_eff: Dictionary = ItemDB.info("golden_carp_stew")["effect"]
	print("[craft] stew effect %s; free combination UI: none (recipes only)" % tea_eff)
	get_tree().quit()


# ---------------------------------------------------------------- save slots tour

## Save slots (3 slots, one character per slot). Every slot change rebuilds the scene, so the tour
## keeps its step in Game meta and resumes on each reload. Uses user://tour_saves, never the real slots.
func _run_save_tour() -> void:
	_touring = true
	SaveManager.dir = "user://tour_saves"
	var t: Dictionary = Game.get_meta("save_tour", {"step": 0})
	Game.set_meta("save_tour", t)
	var step := int(t["step"])
	t["step"] = step + 1
	await _frames(5)
	while _arriving:
		await get_tree().process_frame
	await wait_for_sprites()
	hud.show_help_panel(false)
	var st := Game.player_state
	match step:
		0:
			for i in range(1, SaveManager.SLOTS + 1):
				SaveManager.delete(i)
			show_title()
			await _frames(10)
			print("[tour] saved ", save_screenshot("p1_save_01_title_empty.png"))  # title hides the HUD; _p1_shot would show it
			print("[save] title open %s, paused %s, slots used %s" % [title_open(), get_tree().paused, _slots_used()])
			title.open_slots("new")
			await _frames(6)
			print("[tour] saved ", save_screenshot("p1_save_01b_new_game_slots.png"))
			title.close_panel()
			title.open_settings()
			await _frames(6)
			print("[tour] saved ", save_screenshot("p1_save_01c_settings.png"))
			title.close_panel()
			start_slot(1, true)
		1:
			print("[save] new game in slot 1 -> slot %d, file written %s, gold %d, day %d, region %s, stage %s, camper visible %s, cat following %s" % [Game.slot,
				SaveManager.exists(1), st.gold, Game.day, Game.region, Game.STAGE_NAMES[Game.story_stage()], world.vehicle.visible, world.cat.visible and Game.cat_joined])
			st.gold = 777
			st.level = 3
			st.inventory.add("herb", 5)
			st.learn_recipe("berry_jam")
			st.add_mastery("cooking", 20)
			Game.narrative.set_flag("tour.saved")
			Game.quests.accept("quest.rosa.jelly")
			st.equipment["main"] = ItemDB.enhanced("iron_sword")
			Game.cat_affection = 40
			Game.set_story_stage(2)  # this character has met the cat and owns the camper (saved and restored below)
			Game.day = 3
			Game.minute_of_day = 16.5 * 60.0
			var victim: String = world.monsters[0].monster_id
			Game.field["dead"][victim] = Game.total_minutes()
			var bag := Inventory.new()
			bag.add("iron_ore", 2)
			Game.field["loot"].append({"id": "bag_tour", "kind": "bag", "title": "테스트 꾸러미", "pos": Vector3(2, 0, 7), "inv": bag, "expires": -1.0})
			for d: Dictionary in Game.field["loot"]:
				if d["id"] == "camp_crate":
					(d["inv"] as Inventory).remove("iron_ore", 2)
			_place_player(Vector3(3.0, 0, 6.0), 1.2)
			await _frames(5)
			var pos: Vector3 = world.player.global_position
			print("[save] manual save -> '%s'" % save_game("manual"))
			t["expect"] = {"pos": pos, "victim": victim, "sword": st.equipment["main"], "minute": Game.minute_of_day}
			set_paused(true)
			await _frames(5)
			await _p1_shot("save_02_pause_menu", "pause menu (ESC)", true)
			pause_menu._leave("title")
		2:
			show_title()
			title.open_slots("load")
			await _frames(10)
			print("[tour] saved ", save_screenshot("p1_save_03_title_slot1.png"))  # title hides the HUD; _p1_shot would show it
			print("[save] back at the title: slots used %s, slot 1 card '%s'" % [_slots_used(), SaveManager.read(1)["meta"]])
			start_slot(1, true)
			await _frames(3)
			print("[save] new game into used slot 1 -> refused %s" % Game.pending_start.is_empty())
			start_slot(2, true)
		3:
			print("[save] new game in slot 2 -> slot %d: gold %d, level %d, knows berry jam %s, flag %s, quest %s, upgraded items %d, day %d, dead %d" % [
				Game.slot, st.gold, st.level, st.knows_recipe("berry_jam"), Game.narrative.get_flag("tour.saved"),
				Game.quests.state("quest.rosa.jelly"), ItemDB.instances.size(), Game.day, Game.field["dead"].size()])
			st.gold = 1234
			_autosave_t = AUTOSAVE_SECONDS - 0.5
			await _seconds(1.5)
			print("[save] periodic autosave -> slot 2 gold in file %d" % int(SaveManager.read(2)["state"]["player"]["gold"]))
			to_title()
		4:
			show_title()
			await _frames(10)
			print("[save] slots used %s" % [_slots_used()])
			start_slot(1, false)
		5:
			var e: Dictionary = t["expect"]
			var p: PrototypePlayer = world.player
			var ids := PackedStringArray()
			for m in world.monsters:
				ids.append(m.monster_id)
			var bag_ok := false
			var crate_ore := -1
			for d: Dictionary in Game.field["loot"]:
				if d["id"] == "bag_tour":
					bag_ok = d["inv"] is Inventory and (d["inv"] as Inventory).count("iron_ore") == 2
				if d["id"] == "camp_crate":
					crate_ore = (d["inv"] as Inventory).count("iron_ore")
			print("[save] continue slot 1 -> slot %d: gold %d, level %d, herb %d, knows berry jam %s, cooking mastery %d, flag %s, quest %s" % [
				Game.slot, st.gold, st.level, st.inventory.count("herb"), st.knows_recipe("berry_jam"), st.mastery["cooking"],
				Game.narrative.get_flag("tour.saved"), Game.quests.state("quest.rosa.jelly")])
			print("[save]   sword '%s' (same id %s), cat %d, stage %s, day %d %s, pos off %.2f m, yaw %.2f" % [ItemDB.item_name(st.equipment["main"]),
				st.equipment["main"] == e["sword"], Game.cat_affection, "ABC"[Game.story_stage()], Game.day, Game.clock_text(), p.global_position.distance_to(e["pos"]), p.facing_yaw()])
			print("[save]   dead monster stays dead %s, bag with items %s, crate iron ore %d (was 6, took 2)" % [not e["victim"] in ids, bag_ok, crate_ore])
			await _frames(30)
			await _p1_shot("save_05_continued", "slot 1 continued where it was saved", true)
			Game.run = {"dungeon": "rift", "floor": 1, "seed": 1, "before": {}, "from": "meadow"}
			print("[save] in the rift -> '%s'" % save_block())
			Game.run = {}
			Game.request_world(Game.WORLD_INTERIOR)
			await _frames(5)
			await wait_for_sprites()
			await _frames(5)
			world.player.global_position = Vector3(-1.0, 0, 0.4)
			print("[save] save inside the camper -> '%s'" % save_game("manual"))
			to_title()
		6:
			show_title()
			title.press_delete(2)
			await _frames(6)
			print("[tour] saved ", save_screenshot("p1_save_06_delete_confirm.png"))  # title hides the HUD; _p1_shot would show it
			print("[save] delete slot 2 once -> still there %s" % SaveManager.exists(2))
			title.press_delete(2)
			print("[save] twice -> gone %s, slots used %s" % [not SaveManager.exists(2), _slots_used()])
			start_slot(1, false)
		7:
			print("[save] continue slot 1 -> world %s, pos (%.1f, %.1f)" % [current_world_id(), world.player.global_position.x, world.player.global_position.z])
			st.gold = 4321
			_notification(NOTIFICATION_WM_CLOSE_REQUEST)
			print("[save] window close -> gold in file %d" % int(SaveManager.read(1)["state"]["player"]["gold"]))
			for i in range(1, SaveManager.SLOTS + 1):
				SaveManager.delete(i)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.dir))
			Game.remove_meta("save_tour")
			print("[save] done")
			get_tree().quit()


func _slots_used() -> Array:
	return range(1, SaveManager.SLOTS + 1).filter(func(i: int) -> bool: return SaveManager.exists(i))


## Running (Shift): the run sprite - arms pumping, sword held upright.
func _run_run_tour() -> void:
	_touring = true
	hud.show_help_panel(false)
	Game.clock_running = false
	Game.minute_of_day = 10.5 * 60.0
	await wait_for_sprites()
	var p: PrototypePlayer = world.player
	_place_player(Vector3(-2.0, 0, 3.6), 0.0)
	await _frames(10)
	for leg: Array in [["right", Vector2(1, 0)], ["down", Vector2(0, 1)], ["diag", Vector2(-0.7, 0.7)]]:
		p.scripted_move = leg[1]
		p.scripted_running = true
		await _seconds(0.6)
		for i in 3:
			await _seconds(0.07)
			print("[run] %s: running %s, speed %.1f m/s, sp %.0f" % [leg[0], p._running, p._speed_now, Game.player_state.sp])
			await _p1_shot("run_%s_%d" % [leg[0], i], "running " + leg[0], true)
	p.scripted_move = Vector2.ZERO
	p.scripted_running = false
	await _frames(10)
	print("[run] stopped: running %s" % p._running)
	get_tree().quit()

