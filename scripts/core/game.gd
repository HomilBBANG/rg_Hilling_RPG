extends Node
## Global prototype state: input map, game clock, light toggles and the P1 play state
## (player stats/bag, camper storage, story flags, cat affection, field persistence).
## Numbers are prototype assumptions; see notes/IMPLEMENTATION_ASSUMPTIONS.md.

signal world_change_requested(world_id: StringName)
signal story_changed

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
## Whole days passed (minute_of_day wraps into it), for respawn / corpse timers.
var day := 1
var clock_running := true

var lantern_on := false
var camper_lights_on := false

## World that bootstrap loads first (set when a lab scene is run directly with F6).
var start_world: StringName = WORLD_EXTERIOR
## Where the player came from, so the next world can pick a spawn point.
var previous_world: StringName = &""

## Set by bootstrap. Gives world scripts access to the render pipeline (mouse picking etc.).
var view: Node = null
## Set by bootstrap: the game HUD (floating text, prompts, panels) and bootstrap itself.
var hud: Node = null
var boot: Node = null

# ---------------------------------------------------------------- P1 play state
var player_state := PlayerState.new()
var combat_log := CombatLog.new()
## Camper storage: separate weight-limited container (GDD 8.3 [확정]); capacity [미정].
var storage := Inventory.new()
const STORAGE_CAPACITY := 100.0
## Story flags (GDD 2.3: the cat joins before the camper exists). F9 cycles the stages.
var has_camper := true
var cat_joined := true
## Cat affection: snacks raise it (GDD 2.5 [확정]); amount / cap [미정].
var cat_affection := 0
const CAT_AFFECTION_MAX := 100
const SNACK_AFFECTION := 10
## Exterior persistence across scene reloads: dead monsters, corpses, death bags, camper parking.
var field := {"dead": {}, "loot": [], "camper": {}}
## One-shot spawn instruction for the next world load (death wake-up, vehicle exit, ...).
var spawn_override := {}
## Set when actors appear after a world load (respawn, cat joins): bootstrap re-applies sprites.
var sprites_dirty := false

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
	"toggle_wind": [KEY_B],
	"toggle_sprites": [KEY_Z],
	"toggle_fullscreen": [KEY_F11],
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
	"interact": [KEY_E],
	"interact_alt": [KEY_R],
	"inventory": [KEY_TAB],
	"combat_log": [KEY_G],
	"debug_status": [KEY_F3],
	"debug_heal": [KEY_F8],
	"debug_stage": [KEY_F9],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_actions()
	# Camper storage starts with a few supplies so storage / snacks can be tested.
	storage.add("cat_snack", 6)
	storage.add("canned_food", 4)
	storage.add("firewood", 3)


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
	if get_tree().paused:
		return
	if clock_running:
		advance_minutes(delta * GAME_MINUTES_PER_SECOND)
	player_state.tick(delta)


func advance_minutes(m: float) -> void:
	minute_of_day += m
	while minute_of_day >= 1440.0:
		minute_of_day -= 1440.0
		day += 1


## Monotonic game time in minutes.
func total_minutes() -> float:
	return day * 1440.0 + minute_of_day


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


# ---------------------------------------------------------------- story stages (debug F9)

const STAGE_NAMES := ["A 혼자 여행 (고양이·캠핑카 없음)", "B 고양이 동행 (캠핑카 없음)", "C 캠핑카 보유 + 고양이"]


func story_stage() -> int:
	if has_camper:
		return 2
	return 1 if cat_joined else 0


func set_story_stage(stage: int) -> void:
	stage = posmod(stage, 3)
	cat_joined = stage >= 1
	has_camper = stage >= 2
	story_changed.emit()


func join_cat() -> void:
	if not cat_joined:
		cat_joined = true
		story_changed.emit()


func add_cat_affection(n: int) -> void:
	cat_affection = clampi(cat_affection + n, 0, CAT_AFFECTION_MAX)


func take_spawn_override() -> Dictionary:
	var s := spawn_override
	spawn_override = {}
	return s
