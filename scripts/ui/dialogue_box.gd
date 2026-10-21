class_name DialogueBox
extends Control
## In-game dialogue window. Plays a dialogue file through DialogueRunner with the live game
## context; CutsceneCall nodes hand over to the CutsceneRunner and resume.
## The protagonist's portrait stands on the left and the conversation partner's on the right
## (DialoguePortrait); whoever is not speaking is dimmed to 50% opacity. Narration dims both.
## E / Space / Enter / click = next line, 1-9 or click = pick a choice. Layout is a [미정] HUD
## placeholder (GDD 17). Player control is locked while it is open; the camera is not touched.

signal closed(dialogue_id: String)

const BOX_LEFT := 430.0
const BOX_WIDTH := 1060.0
const BOTTOM := 1030.0
const PORTRAIT_Y := 600.0

var runner: DialogueRunner
var cutscenes: CutsceneRunner
var dialogue_id := ""
var event := {}

var _box: PanelContainer
var _text: Label
var _choices: VBoxContainer
var _hint: Label
var _shade: TextureRect
var _left: DialoguePortrait
var _right: DialoguePortrait
var _in_cutscene := false


func _ready() -> void:
	visible = false
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# soft dark band behind the window so the text and portraits read over any scene
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.6))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	_shade = TextureRect.new()
	_shade.texture = gt
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.position = Vector2(0, 560)
	_shade.size = Vector2(1920, 520)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_box.gui_input.connect(_box_input)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.065, 0.09, 0.94)
	sb.border_color = Color(0.72, 0.58, 0.36)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 24
	sb.content_margin_bottom = 14
	_box.add_theme_stylebox_override("panel", sb)
	_box.custom_minimum_size = Vector2(BOX_WIDTH, 190)
	add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(v)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 27)
	_text.add_theme_constant_override("line_spacing", 6)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(BOX_WIDTH - 68, 0)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_text)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	v.add_child(_choices)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_hint)
	# portraits in front of the window's ends: protagonist left, partner right
	_left = DialoguePortrait.new(-1)
	add_child(_left)
	_left.position = Vector2(BOX_LEFT - _left.size.x + 50, PORTRAIT_Y)
	_right = DialoguePortrait.new(1)
	add_child(_right)
	_right.position = Vector2(BOX_LEFT + BOX_WIDTH - 50, PORTRAIT_Y)


func active() -> bool:
	return runner != null


func play(id: String) -> bool:
	var doc := DialogueData.load_dialogue(id)
	if doc.is_empty():
		push_warning("[dialogue] no file for " + id)
		return false
	dialogue_id = id
	runner = DialogueRunner.new(doc, GameDialogueContext.new())
	_left.set_speaker("player")
	_right.set_speaker(_partner(doc))
	_set_player_talking(true)
	_show(runner.start())
	return true


## The conversation partner shown on the right from the start: the first speaker in the file
## who is neither the protagonist nor the narrator.
static func _partner(doc: Dictionary) -> String:
	for n: Dictionary in doc.get("nodes", []):
		var sp := str(n.get("speaker_id", ""))
		if n.get("type", "") == "line" and sp not in ["", "player", "narrator"]:
			return sp
	return ""


## Lights up whoever is talking; another partner taking a line moves onto the right side.
func _spotlight(sp: String) -> void:
	if sp not in ["", "player", "narrator"]:
		_right.set_speaker(sp)
	_left.set_active(sp == "player")
	_right.set_active(sp not in ["", "player", "narrator"])


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
			_spotlight(ev["speaker"])
			_text.text = ev["text"]
			_hint.text = "E / Space — 다음"
		"choice":
			visible = true
			_spotlight("player")  # the protagonist answers (the question stays above the options)
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
	_box.reset_size()
	_box.position = Vector2(BOX_LEFT, BOTTOM - _box.size.y)


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


func _box_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and event.get("type", "") == "line":
		advance()
		_box.accept_event()


func _close(error: String) -> void:
	visible = false
	var id := dialogue_id
	runner = null
	event = {}
	_left.clear()
	_right.clear()
	_set_player_talking(false)
	if error != "" and Game.boot:
		Game.boot.hud.toast("대화 데이터 오류 (%s): %s" % [id, error])
	closed.emit(id)
