@tool
extends EditorPlugin
## Adds the "Dialogue" main screen (next to 2D / 3D / Script). Only the editor needs this; the
## game reads the same JSON files through scripts/dialogue/* and never references the addon.

const PLAYTEST_PATH := "user://dialogue_playtest.json"

var panel: DialogueEditorPanel


func _enter_tree() -> void:
	panel = DialogueEditorPanel.new()
	panel.can_play_in_game = true
	panel.play_requested.connect(_play_in_game)
	panel.saved.connect(func(_p: String) -> void: EditorInterface.get_resource_filesystem().scan())
	EditorInterface.get_editor_main_screen().add_child(panel)
	# the 컷씬 tab exists once the panel is built (_ready)
	panel.cutscene_panel.can_play_in_game = true
	panel.cutscene_panel.play_requested.connect(_play_cutscene_in_game)
	panel.cutscene_panel.saved.connect(func(_p: String) -> void: EditorInterface.get_resource_filesystem().scan())
	_make_visible(false)
	var out := OS.get_environment("DIALOGUE_EDITOR_SELFTEST")
	if out != "":
		_selftest.call_deferred(out)


func _exit_tree() -> void:
	if panel:
		panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if panel:
		panel.visible = visible


func _get_plugin_name() -> String:
	return "Dialogue"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GraphEdit", "EditorIcons")


## "게임에서 실행": the game picks this file up at start and plays the dialogue in the real
## dialogue box (bootstrap._check_dialogue_playtest). Saves are never touched by the editor.
func _play_in_game(dialogue_id: String) -> void:
	var f := FileAccess.open(PLAYTEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"dialogue_id": dialogue_id}))
	f.close()
	EditorInterface.play_main_scene()


## Same hand-off for the 컷씬 tab: the game plays that cutscene ("story.new_game" = the whole
## new-game sequence from data/story.json).
func _play_cutscene_in_game(cutscene_id: String) -> void:
	var f := FileAccess.open(PLAYTEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"cutscene_id": cutscene_id}))
	f.close()
	EditorInterface.play_main_scene()


## Automated check inside the real editor (DIALOGUE_EDITOR_SELFTEST=<capture dir>).
func _selftest(out_dir: String) -> void:
	for i in 30:
		await get_tree().process_frame
	EditorInterface.set_main_screen_editor("Dialogue")
	var shot := func(name: String) -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		DirAccess.make_dir_recursive_absolute(out_dir)
		var img := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(name + ".png"))
		print("[editor] saved ", name)
	await DialogueEditorSelftest.run(panel, shot)
	get_tree().quit()
