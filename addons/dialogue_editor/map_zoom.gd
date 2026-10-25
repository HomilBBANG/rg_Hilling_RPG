@tool
class_name MapZoom
extends RefCounted
## Zoom + pan for the editors' region pictures (quest start spot, map marks, region layout).
## The panel keeps one of these next to its canvas Control: call fit() when the picture or the
## canvas size changes, to_canvas()/to_region() to convert, handle() from the canvas' gui_input
## (wheel = zoom at the cursor, right / middle drag = pan) and toolbar() to add the ＋ － 전체 buttons
## so nobody needs to know about the wheel.

signal changed

var zoom := 1.0
var pan := Vector2.ZERO
var scale := 1.0
var origin := Vector2.ZERO
var rect := Rect2(-100, -100, 200, 200)
var pad := 20.0

var _panning := false
var _hover: Label


func reset() -> void:
	zoom = 1.0
	pan = Vector2.ZERO


## Recompute scale / origin for the canvas size (keeps the current zoom and pan).
func fit(canvas: Control, r := Rect2()) -> void:
	if r.size.x > 0.0 and r.size.y > 0.0:
		rect = r
	if canvas == null or canvas.size.x < 10.0 or canvas.size.y < 10.0:
		return
	scale = minf((canvas.size.x - pad * 2) / rect.size.x, (canvas.size.y - pad * 2) / rect.size.y) * zoom
	origin = (canvas.size - rect.size * scale) * 0.5 - rect.position * scale + pan


func to_canvas(p: Vector2) -> Vector2:
	return origin + p * scale


func to_region(c: Vector2) -> Vector2:
	return (c - origin) / scale


## Zoom by a factor around a canvas point (the cursor or the middle).
func zoom_by(factor: float, canvas: Control, at := Vector2(-1, -1)) -> void:
	if at.x < 0.0:
		at = canvas.size * 0.5
	var before := to_region(at)
	zoom = clampf(zoom * factor, 0.5, 16.0)
	fit(canvas)
	pan -= to_canvas(before) - at
	fit(canvas)
	canvas.queue_redraw()
	changed.emit()


## Wheel zoom and right / middle drag pan; returns true when the event was used.
func handle(ev: InputEvent, canvas: Control) -> bool:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8, canvas, mb.position)
			return true
		if mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_panning = mb.pressed
			return true
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _hover:
			var p := to_region(mm.position)
			_hover.text = "마우스 자리: x %.1f, z %.1f" % [p.x, p.y]
		if _panning:
			pan += mm.relative
			fit(canvas)
			canvas.queue_redraw()
			changed.emit()
			return true
	return false


## ＋ － 전체 buttons plus a hint and the hovered coordinates, for people who don't know the wheel.
func toolbar(parent: Control, canvas: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = "그림:"
	row.add_child(l)
	var plus := Button.new()
	plus.text = "＋ 확대"
	plus.tooltip_text = "마우스 휠 위로도 됨"
	plus.pressed.connect(func() -> void: zoom_by(1.5, canvas))
	row.add_child(plus)
	var minus := Button.new()
	minus.text = "－ 축소"
	minus.tooltip_text = "마우스 휠 아래로도 됨"
	minus.pressed.connect(func() -> void: zoom_by(1.0 / 1.5, canvas))
	row.add_child(minus)
	var whole := Button.new()
	whole.text = "전체 보기"
	whole.pressed.connect(func() -> void:
		reset()
		fit(canvas)
		canvas.queue_redraw()
		changed.emit())
	row.add_child(whole)
	var hint := Label.new()
	hint.text = "휠 = 확대/축소 · 오른쪽 버튼 끌기 = 그림 옮기기"
	hint.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
	hint.add_theme_font_size_override("font_size", 12)
	row.add_child(hint)
	_hover = Label.new()
	_hover.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))
	_hover.add_theme_font_size_override("font_size", 12)
	_hover.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hover.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_hover)
	return row
