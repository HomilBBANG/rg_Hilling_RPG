class_name BakedSprite
extends MeshInstance3D
## Camera-facing card that shows one cell of a SpriteSheet with dynamic lighting and
## depth from the baked maps. Its position snaps to the render-texel grid so sprite
## pixels line up 1:1 with screen texels (no sub-texel crawling).

var sheet: SpriteSheet
var anchor: Node3D
var emission_variant := "default"
var emission_energy := 1.0
var silhouette_enabled := true

var _mat: ShaderMaterial
var _sil: ShaderMaterial
var _col := 0
var _row := 0


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 4.0
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/sprite_card.gdshader")
	_sil = ShaderMaterial.new()
	_sil.shader = preload("res://shaders/sprite_card_silhouette.gdshader")
	_sil.render_priority = 1
	material_override = _mat
	top_level = true


func set_sheet(s: SpriteSheet) -> void:
	sheet = s
	var q := QuadMesh.new()
	q.size = s.cell_m
	mesh = q
	for m: ShaderMaterial in [_mat, _sil]:
		m.set_shader_parameter("albedo_tex", s.albedo)
		m.set_shader_parameter("depth_tex", s.depth)
	_mat.set_shader_parameter("normal_tex", s.normal)
	_apply_emission()
	set_frame(_col, _row)
	set_silhouette(silhouette_enabled)


func set_inner_lines(on: bool, darkness := 0.42) -> void:
	_mat.set_shader_parameter("inner_lines", on)
	_mat.set_shader_parameter("line_darkness", darkness)


## Hit flash: colour with strength in alpha (0 = off).
func set_flash(c: Color) -> void:
	_mat.set_shader_parameter("flash_color", c)


func set_silhouette_color(c: Color, bias := 0.8) -> void:
	_sil.set_shader_parameter("color", c)
	_sil.set_shader_parameter("self_bias", bias)


func set_silhouette(on: bool) -> void:
	silhouette_enabled = on
	_mat.next_pass = _sil if on else null


func set_emission(variant: String, energy: float) -> void:
	if variant == emission_variant and is_equal_approx(energy, emission_energy):
		return
	emission_variant = variant
	emission_energy = energy
	_apply_emission()


func _apply_emission() -> void:
	if sheet == null:
		return
	var tex: Texture2D = sheet.emission.get(emission_variant, sheet.emission.values()[0])
	_mat.set_shader_parameter("emission_tex", tex)
	_mat.set_shader_parameter("emission_energy", emission_energy)


func set_frame(col: int, row: int) -> void:
	_col = col
	_row = row
	if sheet == null:
		return
	var r := sheet.frame_rect(col, row)
	_mat.set_shader_parameter("frame_rect", r)
	_sil.set_shader_parameter("frame_rect", r)


func _process(_delta: float) -> void:
	if sheet == null or anchor == null:
		return
	var basis := Basis.from_euler(Vector3(deg_to_rad(-sheet.pitch), 0.0, 0.0))
	var local := basis.inverse() * anchor.global_position
	var t := sheet.texel
	# Snap in the camera plane (cell parity matches the screen, see SpriteBaker); keep depth.
	local.x = roundf(local.x / t) * t
	local.y = roundf(local.y / t) * t
	global_transform = Transform3D(basis, basis * local)
