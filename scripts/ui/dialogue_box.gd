class_name DialogueBox
extends PanelContainer
## In-game dialogue window (bottom of the screen). Plays a dialogue file through DialogueRunner
## with the live game context; CutsceneCall nodes hand over to the CutsceneRunner and resume.
## E / Space / Enter / click = next line, 1-9 or click = pick a choice. Layout is a [미정] HUD
## placeholder (GDD 17). Player control is locked while it is open; the camera is not touched.

signal closed(dialogue_id: String)

const WIDTH := 1120.0
const BOTTOM := 862.0

var runner: DialogueRunner
var cutscenes: CutsceneRunner
var dialogue_id := ""
var event := {}

var _name: Label
var _text: Label
var _choices: VBoxContainer
var _hint: Label
var _in_cutscene := false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.065, 0.09, 0.95)
	sb.border_color = Color(0.72, 0.58, 0.36)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(20)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(WIDTH, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 24)
	_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	v.add_child(_name)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 25)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(WIDTH - 40, 64)
	v.add_child(_text)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	v.add_child(_choices)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_hint)


func active() -> bool:
	return runner != null


func play(id: String) -> bool:
	var doc := DialogueData.load_dialogue(id)
	if doc.is_empty():
		push_warning("[dialogue] no file for " + id)
		return false
	dialogue_id = id
	runner = DialogueRunner.new(doc, GameDialogueContext.new())
	_set_player_talking(true)
	_show(runner.start())
	return true


func _set_player_talking(on: bool) -> void:
	var w: Node = Game.boot.world if Game.boot else null
	var p: PrototypePlayer = w.get("player") if w else null
	if p:
		p.set_talking(on)


func _show(ev: Dictionary) -> void:
	event = ev
	for c in _choices.get_children():
		c.queue_free()
	match ev.get("type", ""):
		"line":
			visible = true
			_name.text = ev["name"]
			_name.visible = ev["name"] != ""
			_text.text = ev["text"]
			_hint.text = "E / Space — 다음"
		"choice":
			visible = true
			var i := 1
			for o: Dictionary in ev["options"]:
				var b := Button.new()
				b.text = "%d. %s" % [i, o["text"]]
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.focus_mode = Control.FOCUS_NONE
				b.add_theme_font_size_override("font_size", 23)
				var port: String = o["port"]
				b.pressed.connect(func() -> void: choose(port))
				_choices.add_child(b)
				i += 1
			_hint.text = "1~%d 또는 클릭 — 선택" % ev["options"].size()
		"cutscene":
			visible = false
			_in_cutscene = true
			await cutscenes.play(ev["cutscene_id"])
			_in_cutscene = false
			if runner:
				_show(runner.next())
		"end":
			_close(ev.get("error", ""))
	reset_size()
	position = Vector2(960.0 - size.x * 0.5, BOTTOM - size.y)


func advance() -> void:
	if runner == null:
		return
	if _in_cutscene:
		cutscenes.hurry()
	elif event.get("type", "") == "line":
		_show(runner.next())


func choose(port: String) -> void:
	if runner and event.get("type", "") == "choice":
		_show(runner.choose(port))


func choose_index(i: int) -> void:
	if event.get("type", "") == "choice" and i >= 0 and i < event["options"].size():
		choose(event["options"][i]["port"])


## Key routing from bootstrap while the box is open. Returns true when the event was used.
func handle_key(ev: InputEvent) -> bool:
	if ev.is_action("interact") or (ev is InputEventKey and ev.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]):
		advance()
		return true
	if ev is InputEventKey and ev.physical_keycode >= KEY_1 and ev.physical_keycode <= KEY_9:
		choose_index(ev.physical_keycode - KEY_1)
		return true
	return false


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and event.get("type", "") == "line":
		advance()
		accept_event()


func _close(error: String) -> void:
	visible = false
	var id := dialogue_id
	runner = null
	event = {}
	_set_player_talking(false)
	if error != "" and Game.boot:
		Game.boot.hud.toast("대화 데이터 오류 (%s): %s" % [id, error])
	closed.emit(id)
