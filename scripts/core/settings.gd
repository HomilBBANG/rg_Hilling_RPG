class_name Settings
extends RefCounted
## Player options from the title screen's 설정 (user://settings.cfg). Only what exists in the
## prototype so far: window/fullscreen and master volume (GDD 17 [미정]: the final options list).

const PATH := "user://settings.cfg"

static var fullscreen := false
static var volume := 1.0  # master bus, 0..1


static func load_and_apply() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return  # nothing saved yet: keep the project defaults
	fullscreen = bool(cf.get_value("display", "fullscreen", false))
	volume = clampf(float(cf.get_value("audio", "volume", 1.0)), 0.0, 1.0)
	apply()


static func apply() -> void:
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(want)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.0)


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("audio", "volume", volume)
	cf.save(PATH)
