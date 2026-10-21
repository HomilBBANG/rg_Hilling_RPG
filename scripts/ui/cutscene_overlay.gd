class_name CutsceneOverlay
extends Control
## Full-screen layers a cutscene draws with (CutsceneRunner): an illustration, narration text,
## letterbox bars and a black fade. Lives in the game HUD below the dialogue window, except the
## fade (`fade_rect`), which GameHud places above the window so a fade covers everything.
## Missing illustration files show a placeholder card naming the file to draw.

const NARRATION_CPS := 30.0  # narration types out at this many characters per second
const BAR := 120.0

var fade_rect: ColorRect
var _image: TextureRect
var _placeholder: Control
var _placeholder_path := ""
var _narration_bg: ColorRect
var _narration: Label
var _bars: Array[ColorRect] = []
var _reveal := 1.0  # 0..1 share of the narration shown
var _tweens := {}


func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image = TextureRect.new()
	_image.size = size
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.modulate.a = 0.0
	add_child(_image)
	_placeholder = Control.new()
	_placeholder.size = size
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.draw.connect(_draw_placeholder)
	_placeholder.modulate.a = 0.0
	add_child(_placeholder)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.size = Vector2(1920, BAR)
		bar.position = Vector2(0, -BAR if top else 1080)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		_bars.append(bar)
	_narration_bg = ColorRect.new()
	_narration_bg.color = Color(0, 0, 0, 0.55)
	_narration_bg.size = Vector2(1920, 300)
	_narration_bg.position = Vector2(0, 390)
	_narration_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narration_bg.modulate.a = 0.0
	add_child(_narration_bg)
	_narration = Label.new()
	_narration.size = Vector2(1400, 300)
	_narration.position = Vector2(260, 390)
	_narration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_narration.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_narration.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narration.add_theme_font_size_override("font_size", 36)
	_narration.add_theme_constant_override("line_spacing", 12)
	_narration.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82))
	_narration.add_theme_constant_override("outline_size", 6)
	_narration.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_narration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narration.modulate.a = 0.0
	add_child(_narration)
	fade_rect = ColorRect.new()
	fade_rect.color = Color.BLACK
	fade_rect.size = size
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.modulate.a = 0.0


func _tween(key: String) -> Tween:
	if _tweens.has(key) and (_tweens[key] as Tween).is_valid():
		(_tweens[key] as Tween).kill()
	var tw := create_tween()
	_tweens[key] = tw
	return tw


func fade(to_black: bool, seconds: float) -> Tween:
	var tw := _tween("fade")
	tw.tween_property(fade_rect, "modulate:a", 1.0 if to_black else 0.0, maxf(seconds, 0.01))
	return tw


func is_black() -> bool:
	return fade_rect.modulate.a > 0.5


## Shows an illustration ("" hides it). A missing file shows the placeholder card instead.
func show_image(path: String, seconds: float) -> Tween:
	var tex: Texture2D = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
	var tw := _tween("image")
	tw.set_parallel()
	var t := maxf(seconds, 0.01)
	if path == "":
		tw.tween_property(_image, "modulate:a", 0.0, t)
		tw.tween_property(_placeholder, "modulate:a", 0.0, t)
		return tw
	if tex:
		_image.texture = tex
		tw.tween_property(_image, "modulate:a", 1.0, t)
		tw.tween_property(_placeholder, "modulate:a", 0.0, t)
	else:
		_placeholder_path = path
		_placeholder.queue_redraw()
		tw.tween_property(_placeholder, "modulate:a", 1.0, t)
		tw.tween_property(_image, "modulate:a", 0.0, t)
	return tw


func has_image() -> bool:
	return _image.modulate.a > 0.01 or _placeholder.modulate.a > 0.01


func set_letterbox(on: bool, seconds := 0.5) -> Tween:
	var tw := _tween("bars")
	tw.set_parallel()
	tw.tween_property(_bars[0], "position:y", 0.0 if on else -BAR, maxf(seconds, 0.01))
	tw.tween_property(_bars[1], "position:y", 1080.0 - BAR if on else 1080.0, maxf(seconds, 0.01))
	return tw


func letterbox_on() -> bool:
	return _bars[0].position.y > -BAR * 0.5


## Narration types out; returns once it is fully shown (or at once when instant).
func show_narration(text: String, instant := false) -> void:
	_narration.text = text
	_reveal = 1.0 if instant else 0.0
	_narration.visible_ratio = _reveal
	var tw := _tween("narr")
	tw.set_parallel()
	tw.tween_property(_narration, "modulate:a", 1.0, 0.25)
	tw.tween_property(_narration_bg, "modulate:a", 1.0, 0.25)


func narration_revealing() -> bool:
	return _reveal < 1.0


func finish_reveal() -> void:
	_reveal = 1.0
	_narration.visible_ratio = 1.0


func hide_narration(seconds := 0.25) -> Tween:
	var tw := _tween("narr")
	tw.set_parallel()
	tw.tween_property(_narration, "modulate:a", 0.0, maxf(seconds, 0.01))
	tw.tween_property(_narration_bg, "modulate:a", 0.0, maxf(seconds, 0.01))
	return tw


func narration_text() -> String:
	return _narration.text if _narration.modulate.a > 0.01 else ""


## Back to nothing on screen (end of a cutscene); keep_black leaves the fade as it is.
func reset(keep_black := false) -> void:
	for k in _tweens:
		if (_tweens[k] as Tween).is_valid():
			(_tweens[k] as Tween).kill()
	_tweens.clear()
	_image.modulate.a = 0.0
	_placeholder.modulate.a = 0.0
	_narration.modulate.a = 0.0
	_narration_bg.modulate.a = 0.0
	_bars[0].position.y = -BAR
	_bars[1].position.y = 1080
	if not keep_black:
		fade_rect.modulate.a = 0.0


func _process(delta: float) -> void:
	if _reveal < 1.0:
		var n := maxf(float(_narration.text.length()), 1.0)
		_reveal = minf(1.0, _reveal + delta * NARRATION_CPS / n)
		_narration.visible_ratio = _reveal


func _draw_placeholder() -> void:
	var c := _placeholder
	c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.07, 0.1))
	var r := Rect2(Vector2(160, 100), size - Vector2(320, 200))
	c.draw_rect(r, Color(0.16, 0.15, 0.2))
	c.draw_rect(r, Color(0.62, 0.5, 0.32), false, 4.0)
	c.draw_line(r.position, r.end, Color(0.3, 0.28, 0.34), 2.0)
	c.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), Color(0.3, 0.28, 0.34), 2.0)
	c.draw_string(get_theme_default_font(), Vector2(r.position.x, r.position.y + 70), "삽화 자리 — " + _placeholder_path.get_file(),
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 34, Color(0.9, 0.86, 0.76))
