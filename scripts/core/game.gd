extends Node
## Global P0 prototype state: debug input map, game clock, light toggles.
## Everything here is prototype-only; see notes/IMPLEMENTATION_ASSUMPTIONS.md.

signal world_change_requested(world_id: StringName)

const WORLD_EXTERIOR := &"exterior"
const WORLD_INTERIOR := &"interior"
const WORLD_SCENES := {
	&"exterior": "res://scenes/visual_lab.tscn",
	&"interior": "res://scenes/camper_interior_lab.tscn",
}

## GDD 10.1 [임시]: 1 real second = 1 game minute.
const GAME_MINUTES_PER_SECOND := 1.0
const DAY_PRESET_MINUTE := 12.0 * 60.0
const NIGHT_PRESET_MINUTE := 22.0 * 60.0

var minute_of_day: float = 10.0 * 60.0
var clock_running := true

var lantern_on := false
var camper_lights_on := false

## World that bootstrap loads first (set when a lab scene is run directly with F6).
var start_world: StringName = WORLD_EXTERIOR
## Where the player came from, so the next world can pick a spawn point.
var previous_world: StringName = &""

## Set by bootstrap. Gives world scripts access to the render pipeline (mouse picking etc.).
var view: Node = null

# action -> physical keys (debug bindings from GRAPHICS_PROTOTYPE.md section 5, plus extras)
const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"camper_lights": [KEY_F],
	"preset_coarse": [KEY_1],
	"preset_mid": [KEY_2],
	"preset_soft": [KEY_3],
	"preset_native": [KEY_4],
	"cycle_camera_style": [KEY_V],
	"toggle_outline": [KEY_O],
	"toggle_pipeline": [KEY_M],
	"toggle_post": [KEY_P],
	"toggle_day_night": [KEY_N],
	"toggle_clock": [KEY_T],
	"toggle_lantern": [KEY_L],
	"toggle_interior": [KEY_I],
	"toggle_help": [KEY_H],
	"toggle_snap": [KEY_K],
	"toggle_projection": [KEY_C],
	"toggle_occlusion": [KEY_X],
	"zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"screenshot": [KEY_F12],
	"pause": [KEY_ESCAPE],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_actions()


func _register_actions() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: Key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)


func _process(delta: float) -> void:
	if clock_running and not get_tree().paused:
		minute_of_day = fposmod(minute_of_day + delta * GAME_MINUTES_PER_SECOND, 1440.0)


## 0 = full night, 1 = full day. Dawn 05:00-07:00, dusk 18:00-20:00 are prototype assumptions.
func daylight() -> float:
	var m := minute_of_day
	return smoothstep(300.0, 420.0, m) * (1.0 - smoothstep(1080.0, 1200.0, m))


## 1 at the middle of dawn/dusk, 0 otherwise (used for a warm tint).
func twilight() -> float:
	var d := daylight()
	return clampf(1.0 - absf(d - 0.5) * 2.0, 0.0, 1.0) if d > 0.0 and d < 1.0 else 0.0


func is_night() -> bool:
	return daylight() < 0.5


func toggle_day_night() -> void:
	minute_of_day = DAY_PRESET_MINUTE if is_night() else NIGHT_PRESET_MINUTE


func clock_text() -> String:
	var m := int(minute_of_day)
	return "%02d:%02d" % [m / 60, m % 60]


func request_world(world_id: StringName) -> void:
	world_change_requested.emit(world_id)
