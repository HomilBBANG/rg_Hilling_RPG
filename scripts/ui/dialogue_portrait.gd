class_name DialoguePortrait
extends Control
## One side of the dialogue window: the speaker's own game model (PlayerRig / NpcRig / CatRig)
## rendered live into a small SubViewport with its own world and light, scaled up with nearest
## filtering so it reads as pixel art like the field sprites, with a dark 1-px outline, a dithered
## fade at the bottom edge and a name plate below. Which model a speaker uses is data (data/speakers.json "portrait").
## The side that is not speaking is drawn at 50% opacity (set_active).

const RES := Vector2i(120, 120)
const PIXEL := 3
const DIM := 0.5
const FACE_TURN := 0.55  # yaw towards the other side (3/4 view)
const OUTLINE_SHADER := """
shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(0.09, 0.07, 0.08, 1.0);
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	if (c.a < 0.5) {
		float n = max(max(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
			max(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
		c = n >= 0.5 ? outline_color : vec4(0.0);
	} else {
		c.a = 1.0;
	}
	// ordered-dither dissolve over the bottom rows so the bust has no hard cut edge
	ivec2 p = ivec2(UV / px) % 4;
	int bayer[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	if (float(bayer[p.y * 4 + p.x]) / 16.0 < smoothstep(0.84, 1.0, UV.y)) {
		c.a = 0.0;
	}
	COLOR = c * tint;
}
"""

## -1 = left (faces right), 1 = right (faces left)
var side := -1
var speaker := ""
var active := false

var _vp: SubViewport
var _cam: Camera3D
var _model: Node3D
var _image: TextureRect
var _plate: PanelContainer
var _plate_label: Label
var _t := 0.0
var _tween: Tween


func _init(p_side := -1) -> void:
	side = p_side


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(RES * PIXEL) + Vector2(0, 40)
	_vp = SubViewport.new()
	_vp.size = RES
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.64, 0.74)
	env.environment.ambient_light_energy = 0.75
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	# from the front, above, slightly from the side the character looks towards
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(28.0 * -side), 0)
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	_image = TextureRect.new()
	_image.texture = _vp.get_texture()
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_image.size = Vector2(RES * PIXEL)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = OUTLINE_SHADER
	_image.material = sm
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


## Shows this speaker's model and name (re-uses the model when the speaker did not change).
func set_speaker(id: String) -> void:
	if id == speaker:
		return
	speaker = id
	if _model:
		_model.queue_free()
		_model = null
	var info: Dictionary = DialogueData.speakers().get(id, {})
	_plate_label.text = str(info.get("name", id)) if id != "" else ""
	_plate.visible = _plate_label.text != ""
	_plate.reset_size()
	_plate.position = Vector2((size.x - _plate.size.x) * 0.5, RES.y * PIXEL - 22)
	_model = _build_model(info.get("portrait", {}))
	_image.visible = _model != null
	visible = id != ""
	if _model:
		_model.rotation.y = PI - FACE_TURN * side
		_vp.add_child(_model)
		_pose(0.0)
		_frame()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED


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


func _build_model(p: Variant) -> Node3D:
	if not p is Dictionary or (p as Dictionary).is_empty():
		return null
	match str(p.get("rig", "")):
		"player":
			var rig := PlayerRig.new()
			var w: Node = Game.boot.world if Game.boot else null
			var pl: PrototypePlayer = w.get("player") if w else null
			if pl and pl.model:
				rig.set_gear(pl.model.gear)  # same weapon / shield as on the field
			return rig
		"npc":
			var look := str(p.get("look", ""))
			return NpcRig.new(look) if NpcRig.LOOKS.has(look) else null
		"cat":
			return CatRig.new()
	return null


func _pose(t: float) -> void:
	var breathe := sin(t * TAU * 0.4) * 0.008
	if _model is PlayerRig:
		(_model as PlayerRig).pose(0.0, 0.0, -1.0, breathe)
	elif _model is NpcRig:
		(_model as NpcRig).pose(0.0, 0.0, breathe)
	elif _model is CatRig:
		(_model as CatRig).pose_sit()


## Bust framing from the model's bounds: the top ~1 m of a person (head and chest), all of a cat.
func _frame() -> void:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		var b: AABB = _model.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var top := box.end.y
	var span := minf(box.size.y, 1.0)
	_cam.size = span * 1.08
	_cam.position = Vector3(0, top - span * 0.5 + span * 0.02, 4.0)


func _process(delta: float) -> void:
	if _model == null or not is_visible_in_tree():
		return
	_t += delta
	_pose(_t)
