@tool
class_name MapEditorPlugin
extends EditorPlugin
## The "Map" main screen (next to Dialogue): 지역 배치 (RegionEditorPanel — the designer lays out a
## region: terrain shapes, roads, the new-character start, exits, monsters, NPCs, story spots) and
## 지도 (MapEditorPanel — the collectible map's marks and how it is obtained). The game reads the same
## JSON files; nothing here is needed at runtime.

const PLAYTEST_PATH := "user://dialogue_playtest.json"

static var instance: MapEditorPlugin

var tabs: TabContainer
var region_panel: RegionEditorPanel
var map_panel: MapEditorPanel


func _enter_tree() -> void:
	instance = self
	tabs = TabContainer.new()
	tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	region_panel = RegionEditorPanel.new()
	region_panel.name = "지역 배치"
	region_panel.can_play_in_game = true
	region_panel.play_requested.connect(_play_region_in_game)
	region_panel.saved.connect(func(_p: String) -> void: EditorInterface.get_resource_filesystem().scan())
	tabs.add_child(region_panel)
	map_panel = MapEditorPanel.new()
	map_panel.name = "지도 표시물"
	map_panel.saved.connect(func(_p: String) -> void: EditorInterface.get_resource_filesystem().scan())
	tabs.add_child(map_panel)
	EditorInterface.get_editor_main_screen().add_child(tabs)
	_make_visible(false)


func _exit_tree() -> void:
	if tabs:
		tabs.queue_free()
	if instance == self:
		instance = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if tabs:
		tabs.visible = visible


func _get_plugin_name() -> String:
	return "Map"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("World3D", "EditorIcons")


## "게임에서 실행": the game starts in that region at its new-character start (default_spawn).
func _play_region_in_game(region_id: String) -> void:
	var f := FileAccess.open(PLAYTEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"region_id": region_id}))
	f.close()
	EditorInterface.play_main_scene()
