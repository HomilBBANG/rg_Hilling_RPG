class_name VisualHud
extends Control
## High-resolution debug HUD (drawn outside the pixelated SubViewport so text stays sharp).
## Layout was designed for 1280x720 and is multiplied by UI_SCALE for the 1920x1080 canvas.

const UI_SCALE := 1.5

var font: Font
var boot: Node

var _status: Label
var _hint: Label
var _context: Label
var _toast: Label
var _help: PanelContainer
var _pause: Label
var _toast_time := 0.0
var _capture_mode := false
var _caption: Label

const HELP_TEXT := """[P0 디버그 조작 — 프로토타입 전용, 최종 키 아님]
WASD 이동 · Shift 달리기 · 마우스 클릭 = 기본 공격 1회(마우스 방향)
F  캠핑카 외부 라이트 (캠핑카 근처에서만)
V  카메라 스타일 A(기존) → B(개선 탑다운) → C(디오라마) → D(데드셀풍)
Z  스프라이트 파이프라인: 3D 모델→렌더→픽셀 스프라이트 ON/OFF
O  픽셀 외곽선 ON/OFF (기본 ON)
1/2/3/4  PXL-COARSE 320×180 / PXL-MID 480×270 / PXL-SOFT 640×360 / 3D-NATIVE
M  픽셀화 파이프라인 전환 (M1 SubViewport 확대 ↔ M2 3D 스케일링 nearest)
P  모드3: 팔레트 제한 + 디더링 후처리 ON/OFF
N  낮 ↔ 밤 (12:00 / 22:00)     T  시계 진행/정지 (1초 = 게임 1분)
L  개인 등불(허리띠) ON/OFF       I  캠핑카 실내 ↔ 야외
K  픽셀 스냅 카메라 ON/OFF (떨림 비교)   C  직교 ↔ 원근 투영
X  가림 보조: 실루엣 → 수관 투명화 → 끔   - / =  카메라 규모(줌)
F12 스크린샷 (user://captures)    F11 전체 화면    ESC 일시정지    H 이 도움말"""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = roundi(15 * UI_SCALE)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", roundi(5 * UI_SCALE))
	theme = t

	_status = _label(Vector2(14, 10) * UI_SCALE, roundi(15 * UI_SCALE))
	_context = _label(Vector2(14, 0) * UI_SCALE, roundi(17 * UI_SCALE))
	_context.position = Vector2(340, 648) * UI_SCALE
	_context.size = Vector2(600, 24) * UI_SCALE
	_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_hint = _label(Vector2.ZERO, roundi(14 * UI_SCALE))
	_hint.position = Vector2(14, 690) * UI_SCALE
	_hint.text = "WASD 이동 · 클릭 공격 · V 카메라 A~D · Z 스프라이트 · 1~4 렌더 · F 캠핑카 라이트 · N 낮밤 · L 등불 · I 실내 · H 도움말"
	_toast = _label(Vector2.ZERO, roundi(18 * UI_SCALE))
	_toast.position = Vector2(320, 150) * UI_SCALE
	_toast.size = Vector2(640, 26) * UI_SCALE
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause = _label(Vector2.ZERO, roundi(32 * UI_SCALE))
	_pause.position = Vector2(440, 330) * UI_SCALE
	_pause.size = Vector2(400, 40) * UI_SCALE
	_pause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause.text = "일시정지 (ESC)"

	_caption = _label(Vector2(14, 684) * UI_SCALE, roundi(18 * UI_SCALE))
	_caption.visible = false

	_help = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14 * UI_SCALE)
	_help.add_theme_stylebox_override("panel", sb)
	_help.position = Vector2(668, 12) * UI_SCALE
	_help.size = Vector2(600, 0) * UI_SCALE
	var help_label := Label.new()
	help_label.text = HELP_TEXT
	help_label.add_theme_font_size_override("font_size", roundi(13 * UI_SCALE))
	_help.add_child(help_label)
	add_child(_help)
	_help.visible = true


func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	add_child(l)
	return l


## Clean capture mode: hide debug text, show only a caption line.
func set_capture_mode(on: bool, caption := "") -> void:
	for c in [_status, _hint, _context, _toast]:
		c.visible = not on
	_capture_mode = on
	_caption.text = caption
	_caption.visible = on and caption != ""


func toggle_help() -> void:
	_help.visible = not _help.visible


func show_help_panel(on: bool) -> void:
	_help.visible = on


func toast(msg: String) -> void:
	_toast.text = msg
	_toast_time = 2.5


func _process(delta: float) -> void:
	if _capture_mode:
		return
	_toast_time -= delta
	_toast.visible = _toast_time > 0.0
	_pause.visible = get_tree().paused
	var r: PixelRenderController = boot.render
	var w: Node = boot.world
	if r == null or w == null:
		return
	var rs := r.render_size()
	var cam: TopdownCamera = w.camera
	var lines := PackedStringArray()
	lines.append("Denial · P0 시각 검증 — %s" % w.world_title())
	lines.append("카메라(V) %s · 외곽선(O) %s" % [boot.style_name(), "ON" if cam.outline_enabled and cam.outline_supported() else "OFF"])
	lines.append("스프라이트 파이프라인(Z) %s" % ("ON · 3D→픽셀 스프라이트" if boot.sprites_enabled else "OFF · 실시간 3D"))
	lines.append("시각 %s (%s)%s" % [Game.clock_text(), "밤" if Game.is_night() else "낮", "" if Game.clock_running else " ⏸"])
	lines.append("렌더 %s  %d×%d ×%d  |  %s" % [r.preset_name(), rs.x, rs.y, int(r.texel_screen_size()), r.pipeline_name()])
	lines.append("후처리(P) %s · 스냅(K) %s · 투영(C) %s · 화면높이 %.0fm" % [
		"ON" if r.post_enabled else "OFF", "ON" if cam.snap_enabled else "OFF",
		"직교" if cam.orthogonal else "원근", cam.view_height()])
	lines.append("등불(L) %s · 캠핑카 라이트(F) %s · 가림 보조(X) %s" % [
		"ON" if Game.lantern_on else "OFF", "ON" if Game.camper_lights_on else "OFF", w.occlusion_mode_name()])
	lines.append("FPS %d" % Engine.get_frames_per_second())
	_status.text = "\n".join(lines)
	_context.text = w.context_hint()
