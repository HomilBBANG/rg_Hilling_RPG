class_name DialoguePortrait
extends Control
## One side of the dialogue window: the speaker's portrait image with a name plate below.
## Images are drawn separately: `assets/portraits/<speaker_id>.png` is the default look and
## `<speaker_id>_<expression>.png` the expressions a line can ask for (speakers.json
## "expressions"; "portrait" points the default at another file). Full-figure art is shown as a
## bust: scaled so the top ~68% fills the box, the rest runs off the bottom of the screen.
## Until an image exists, a plain placeholder shape holds the spot. The side that is not
## speaking is drawn at 50% opacity (set_active).

const SIZE := Vector2(420, 480)
const BUST := 0.68  # share of a full-figure image (from the top) that fills the box
const DIM := 0.5
const PORTRAIT_DIR := "res://assets/portraits"

## -1 = left (protagonist), 1 = right (conversation partner)
var side := -1
var speaker := ""
var expression := ""
var active := false

var _image: TextureRect
var _placeholder: Control
var _plate: PanelContainer
var _plate_label: Label
var _color := Color.WHITE
var _tween: Tween


func _init(p_side := -1) -> void:
	side = p_side


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = SIZE
	clip_contents = true
	_placeholder = Control.new()
	_placeholder.size = SIZE
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.draw.connect(_draw_placeholder)
	add_child(_placeholder)
	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)
	_plate = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.96, 0.87, 0.56)
	sb.border_color = Color(0.36, 0.25, 0.12)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	_plate.add_theme_stylebox_override("panel", sb)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_label = Label.new()
	_plate_label.add_theme_font_size_override("font_size", 25)
	_plate_label.add_theme_color_override("font_color", Color(0.2, 0.14, 0.08))
	_plate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plate.add_child(_plate_label)
	add_child(_plate)
	modulate.a = DIM
	visible = false


## Shows this speaker's portrait for the given expression ("" = default) and name.
func set_speaker(id: String, expr := "") -> void:
	if id == speaker and expr == expression:
		return
	var same_speaker := id == speaker
	speaker = id
	expression = expr
	visible = id != ""
	if id == "":
		return
	var info: Dictionary = DialogueData.speakers().get(id, {})
	if not same_speaker:
		_plate_label.text = str(info.get("name", id))
		_plate.visible = _plate_label.text != ""
		_plate.reset_size()
		_plate.position = Vector2((SIZE.x - _plate.size.x) * 0.5, SIZE.y - _plate.size.y - 14)
		_color = Color.from_hsv(float(hash(id) % 360) / 360.0, 0.45, 0.85)
	var base := str(info.get("portrait", PORTRAIT_DIR.path_join(id + ".png")))
	var path := base
	if expr != "":
		var alt := "%s_%s.%s" % [base.get_basename(), expr, base.get_extension()]
		if ResourceLoader.exists(alt):
			path = alt
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_image.texture = tex
	_image.visible = tex != null
	_placeholder.visible = tex == null
	if tex:
		var ts := tex.get_size()
		var k := minf(SIZE.x / ts.x, SIZE.y / (ts.y * BUST))
		_image.size = ts * k
		_image.position = Vector2((SIZE.x - _image.size.x) * 0.5, 0)
	_placeholder.queue_redraw()


func has_image() -> bool:
	return _image.texture != null


## Full opacity while this side is speaking, 50% otherwise.
func set_active(on: bool) -> void:
	if on == active and _tween == null:
		modulate.a = 1.0 if on else DIM
		return
	active = on
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0 if on else DIM, 0.12)
	_tween.finished.connect(func() -> void: _tween = null)


func clear() -> void:
	set_speaker("")
	active = false
	modulate.a = DIM


## Placeholder only: a frame and a head-and-shoulders silhouette turned a little towards the
## middle of the screen, plus the file name the real image should have.
func _draw_placeholder() -> void:
	var c := _placeholder
	var frame := Rect2(Vector2(20, 20), SIZE - Vector2(40, 20))
	c.draw_rect(frame, Color(0.08, 0.08, 0.11, 0.55))
	c.draw_rect(frame, _color, false, 3.0)
	var shade := _color.darkened(0.25)
	var mid := SIZE.x * 0.5
	var body := Rect2(Vector2(mid - 100, 300), Vector2(200, SIZE.y - 300))
	c.draw_rect(body, shade)
	c.draw_circle(Vector2(body.position.x, body.position.y + 60), 60, shade)
	c.draw_circle(Vector2(body.end.x, body.position.y + 60), 60, shade)
	var head := Vector2(mid - side * 18, 190)  # turned towards the other speaker
	c.draw_circle(head, 88, _color)
	c.draw_circle(head + Vector2(side * -46, 4), 12, _color.darkened(0.5))  # eye on the facing side
	c.draw_multiline_string(get_theme_default_font(), Vector2(frame.position.x, frame.position.y + 30),
		"초상화 자리\n%s.png" % (speaker if expression == "" else speaker + "_" + expression), HORIZONTAL_ALIGNMENT_CENTER, frame.size.x, 20, -1, Color(1, 1, 1, 0.85))
