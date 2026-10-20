class_name CamperExterior
extends Node3D
## Stylized modern Class-C motorhome. Front faces local +X, door side is local +Z (camera side).
## Body = extruded rounded side profile with bevelled edges + painted livery shader,
## rounded windows, awning with string lights, roof cargo box, spare wheel cover.

const LENGTH := 7.4
const WIDTH := 2.4
const DOOR_LOCAL := Vector3(-1.0, 0.0, 1.25)
const HEADLIGHT_LOCAL := Vector3(3.8, 0.98, 0.78)
const TAILLIGHT_LOCAL := Vector3(-3.63, 1.05, 0.92)
const WHEEL_X := [2.5, -2.0]

var lights: PrototypeCamperLights
var paint: ShaderMaterial


func _ready() -> void:
	_build_body()
	_build_details()
	_build_awning()
	ProtoMesh.static_box_collider(self, Vector3(LENGTH, 6.0, WIDTH), Vector3(0, 2.0, 0))
	lights = PrototypeCamperLights.new()
	lights.name = "Lights"
	add_child(lights)
	lights.build(self)


## Bake request: one static cell (lamps off / on emission variants).
static func sprite_bake_spec(yaw_deg: float) -> Dictionary:
	return {
		"builder": func(_c: int, _r: int) -> Node3D:
			var cam := CamperExterior.new()
			cam.rotation_degrees.y = yaw_deg
			return cam,
		"cols": 1,
		"rows": 1,
		"cell": Vector2(10.5, 8.5),
		"albedo_setup": func(insts: Array[Node3D]) -> void:
			for i in insts:
				(i as CamperExterior).lights._apply(false),
		"emission": {
			"off": func(insts: Array[Node3D]) -> void:
				for i in insts:
					(i as CamperExterior).lights._apply(false),
			"on": func(insts: Array[Node3D]) -> void:
				for i in insts:
					(i as CamperExterior).lights._apply(true),
		},
	}


var sprite: BakedSprite
var _shadow_backup := {}


## Show the baked pixel sprite instead of the 3D model (null = back to 3D).
## Meshes stay as shadow-only casters; lights and collider are unchanged.
func use_sprite_sheet(sheet: SpriteSheet) -> void:
	if sheet and sprite == null:
		sprite = BakedSprite.new()
		sprite.name = "Sprite"
		sprite.anchor = self
		sprite.silhouette_enabled = false
		add_child(sprite)
	elif sheet == null and sprite:
		sprite.queue_free()
		sprite = null
	if sprite:
		sprite.set_sheet(sheet)
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi == sprite:
			continue
		var g := mi as MeshInstance3D
		if not _shadow_backup.has(g):
			_shadow_backup[g] = g.cast_shadow
		var orig: int = _shadow_backup[g]
		if sprite == null:
			g.cast_shadow = orig
			g.visible = true
		elif orig == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			g.visible = false
		else:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


func _process(_delta: float) -> void:
	if sprite:
		sprite.set_emission("on" if Game.camper_lights_on else "off", 1.0)


func door_world_position() -> Vector3:
	return to_global(DOOR_LOCAL + Vector3(0, 0, 1.0))


static func _profile() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-3.55, 0.5), Vector2(3.6, 0.5), Vector2(3.76, 0.6), Vector2(3.8, 0.95),
		Vector2(3.74, 1.18), Vector2(3.58, 1.31), Vector2(3.22, 1.42), Vector2(2.8, 2.12),
		Vector2(2.88, 2.2), Vector2(3.06, 2.3), Vector2(3.16, 2.52), Vector2(3.12, 2.76),
		Vector2(2.96, 2.94), Vector2(2.7, 3.07), Vector2(2.3, 3.14), Vector2(-3.05, 3.14),
		Vector2(-3.32, 3.1), Vector2(-3.49, 2.98), Vector2(-3.58, 2.78), Vector2(-3.6, 0.9),
		Vector2(-3.58, 0.62),
	])


func _build_body() -> void:
	paint = ShaderMaterial.new()
	paint.shader = preload("res://shaders/camper_paint.gdshader")
	paint.set_shader_parameter("wheel_a", Vector2(WHEEL_X[0], 0.42))
	paint.set_shader_parameter("wheel_b", Vector2(WHEEL_X[1], 0.42))
	StylizedMaterials.register(paint)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = OrganicMesh.extrude_profile(_profile(), WIDTH, 0.12)
	body.material_override = paint
	add_child(body)


## Rounded panel (window, door...) lying on a side of the body.
func _panel(size: Vector2, center: Vector3, radius: float, depth: float, material: Material, facing_z := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = OrganicMesh.extrude_profile(OrganicMesh.rounded_rect(-size * 0.5, size * 0.5, radius, 3), depth, minf(depth * 0.4, 0.02))
	mi.position = center + Vector3(0, 0, facing_z * depth * 0.5)
	mi.material_override = material
	add_child(mi)
	return mi


func _window(size: Vector2, center_xy: Vector2, radius := 0.12) -> void:
	var frame := ProtoMesh.mat(Color(0.25, 0.26, 0.3), 0.6)
	var glass := ProtoMesh.mat(Color(0.2, 0.32, 0.45), 0.15)
	var shine := ProtoMesh.mat(Color(0.62, 0.78, 0.88), 0.2)
	for s in [1.0, -1.0]:
		var z: float = s * WIDTH * 0.5
		_panel(size + Vector2(0.1, 0.1), Vector3(center_xy.x, center_xy.y, z), radius + 0.04, 0.03, frame, s)
		_panel(size, Vector3(center_xy.x, center_xy.y, z + s * 0.02), radius, 0.03, glass, s)
		# diagonal reflection streak
		var streak := ProtoMesh.box(self, Vector3(0.07, size.y * 0.8, 0.01), Vector3(center_xy.x - size.x * 0.22, center_xy.y, z + s * 0.055), shine, Vector3(0, 0, -25))
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_details() -> void:
	var trim := ProtoMesh.mat(Color(0.27, 0.28, 0.32), 0.6)
	var chrome := ProtoMesh.mat(Color(0.82, 0.84, 0.86), 0.3)
	var tire := ProtoMesh.mat(Color(0.12, 0.12, 0.13))
	var door_mat := ProtoMesh.mat(Color(0.9, 0.86, 0.77), 0.5)
	var glass := ProtoMesh.mat(Color(0.2, 0.32, 0.45), 0.15)
	var teal := ProtoMesh.mat(Color(0.32, 0.6, 0.58), 0.5)
	var mustard := ProtoMesh.mat(Color(0.95, 0.74, 0.3), 0.6)
	var cream := ProtoMesh.mat(Color(0.95, 0.93, 0.87), 0.5)

	# Windows
	_window(Vector2(1.0, 0.62), Vector2(-2.45, 2.12))
	_window(Vector2(1.35, 0.62), Vector2(0.45, 2.12))
	_window(Vector2(0.62, 0.5), Vector2(2.62, 1.76), 0.1)
	_window(Vector2(0.5, 0.24), Vector2(2.35, 2.66), 0.08)
	# Windshield along the slanted face
	var ws := ProtoMesh.box(self, Vector3(0.04, 0.78, WIDTH - 0.36), Vector3(3.03, 1.78, 0), glass, Vector3(0, 0, 31))
	ws.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ProtoMesh.box(self, Vector3(0.05, 0.6, 0.08), Vector3(3.06, 1.8, 0.4), ProtoMesh.mat(Color(0.62, 0.78, 0.88), 0.2), Vector3(0, 0, 31))

	# Door (camera side) with window, handle, step and mat
	var dz := WIDTH * 0.5
	_panel(Vector2(0.78, 1.86), Vector3(DOOR_LOCAL.x, 1.56, dz), 0.1, 0.04, door_mat)
	_panel(Vector2(0.42, 0.42), Vector3(DOOR_LOCAL.x, 2.1, dz + 0.04), 0.1, 0.02, glass)
	ProtoMesh.box(self, Vector3(0.14, 0.05, 0.05), Vector3(DOOR_LOCAL.x + 0.26, 1.5, dz + 0.07), chrome)
	ProtoMesh.box(self, Vector3(0.82, 0.07, 0.42), Vector3(DOOR_LOCAL.x, 0.36, dz + 0.22), trim)
	ProtoMesh.box(self, Vector3(1.0, 0.02, 0.6), Vector3(DOOR_LOCAL.x, 0.01, dz + 0.75), ProtoMesh.mat(Color(0.8, 0.42, 0.32)))
	ProtoMesh.box(self, Vector3(0.9, 0.025, 0.5), Vector3(DOOR_LOCAL.x, 0.015, dz + 0.75), ProtoMesh.mat(Color(0.93, 0.78, 0.5)))

	# Wheels: tyre, rim, hub
	for wx: float in WHEEL_X:
		for s in [1.0, -1.0]:
			var z: float = s * (WIDTH * 0.5 - 0.05)
			ProtoMesh.cylinder(self, 0.42, 0.3, Vector3(wx, 0.42, z), tire, Vector3(90, 0, 0), 12)
			ProtoMesh.cylinder(self, 0.25, 0.32, Vector3(wx, 0.42, z), chrome, Vector3(90, 0, 0), 10)
			ProtoMesh.cylinder(self, 0.1, 0.34, Vector3(wx, 0.42, z), trim, Vector3(90, 0, 0), 8)

	# Front: grille, bumper, mirrors
	ProtoMesh.box(self, Vector3(0.05, 0.32, 1.0), Vector3(3.8, 0.88, 0), trim)
	for i in 3:
		ProtoMesh.box(self, Vector3(0.06, 0.03, 0.9), Vector3(3.82, 0.79 + i * 0.09, 0), chrome)
	ProtoMesh.capsule(self, 0.08, WIDTH + 0.05, Vector3(3.84, 0.56, 0), trim, Vector3(90, 0, 0))
	ProtoMesh.capsule(self, 0.07, WIDTH, Vector3(-3.64, 0.56, 0), trim, Vector3(90, 0, 0))
	for s in [1.0, -1.0]:
		ProtoMesh.box(self, Vector3(0.05, 0.05, 0.25), Vector3(3.0, 1.78, s * (WIDTH * 0.5 + 0.12)), trim)
		ProtoMesh.box(self, Vector3(0.08, 0.3, 0.14), Vector3(3.0, 1.75, s * (WIDTH * 0.5 + 0.27)), trim)

	# Rear: ladder and spare wheel cover
	for i in 6:
		ProtoMesh.box(self, Vector3(0.04, 0.04, 0.42), Vector3(-3.68, 1.05 + i * 0.36, -0.62), chrome)
	for lz in [-0.83, -0.41]:
		ProtoMesh.box(self, Vector3(0.04, 2.2, 0.04), Vector3(-3.68, 2.0, lz), chrome)
	ProtoMesh.cylinder(self, 0.36, 0.2, Vector3(-3.7, 1.75, 0.45), teal, Vector3(0, 0, 90), 12)
	ProtoMesh.cylinder(self, 0.2, 0.22, Vector3(-3.7, 1.75, 0.45), cream, Vector3(0, 0, 90), 10)

	# Roof: AC unit, solar panels, rack + mustard cargo box, skylight
	var ac := MeshInstance3D.new()
	ac.mesh = OrganicMesh.extrude_profile(OrganicMesh.rounded_rect(Vector2(-0.45, 0.0), Vector2(0.45, 0.32), 0.1, 3), 0.8, 0.05)
	ac.position = Vector3(-0.3, 3.14, 0)
	ac.material_override = cream
	add_child(ac)
	ProtoMesh.box(self, Vector3(0.7, 0.03, 0.6), Vector3(-0.3, 3.47, 0), ProtoMesh.mat(Color(0.75, 0.75, 0.72)))
	var solar := ProtoMesh.mat(Color(0.16, 0.24, 0.45), 0.25)
	var grid := ProtoMesh.mat(Color(0.5, 0.6, 0.8), 0.3)
	for pz in [-0.5, 0.5]:
		ProtoMesh.box(self, Vector3(1.3, 0.05, 0.85), Vector3(-2.35, 3.17, pz), solar)
		ProtoMesh.box(self, Vector3(0.02, 0.055, 0.85), Vector3(-2.35, 3.175, pz), grid)
		ProtoMesh.box(self, Vector3(1.3, 0.055, 0.02), Vector3(-2.35, 3.175, pz), grid)
	for rz in [-0.85, 0.85]:
		ProtoMesh.box(self, Vector3(1.6, 0.05, 0.05), Vector3(1.2, 3.25, rz), trim)
	var cargo := MeshInstance3D.new()
	cargo.mesh = OrganicMesh.extrude_profile(OrganicMesh.rounded_rect(Vector2(-0.7, 0.0), Vector2(0.7, 0.38), 0.16, 3), 1.2, 0.08)
	cargo.position = Vector3(1.25, 3.18, 0)
	cargo.material_override = mustard
	add_child(cargo)
	ProtoMesh.box(self, Vector3(0.5, 0.06, 0.5), Vector3(0.75, 3.15, 0), ProtoMesh.mat(Color(0.55, 0.7, 0.85), 0.2))


func _build_awning() -> void:
	## Extended striped awning over the door, poles, valance and string lights.
	var x0 := -2.8
	var x1 := 0.8
	var z_in := WIDTH * 0.5 + 0.05
	var z_out := WIDTH * 0.5 + 2.1
	var y_in := 2.88
	var y_out := 2.42
	var stripes := 8
	var col_a := ProtoMesh.mat(Color(0.97, 0.94, 0.86), 0.8)
	var col_b := ProtoMesh.mat(Color(0.93, 0.5, 0.4), 0.8)
	var slope := rad_to_deg(atan2(y_in - y_out, z_out - z_in))
	var depth := Vector2(z_out - z_in, y_in - y_out).length()
	var w := (x1 - x0) / stripes
	for i in stripes:
		var cx := x0 + w * (i + 0.5)
		ProtoMesh.box(self, Vector3(w, 0.03, depth), Vector3(cx, (y_in + y_out) * 0.5, (z_in + z_out) * 0.5), col_a if i % 2 == 0 else col_b, Vector3(slope, 0, 0))
		# scalloped valance
		ProtoMesh.box(self, Vector3(w, 0.14, 0.03), Vector3(cx, y_out - 0.07, z_out), col_b if i % 2 == 0 else col_a)
	var trim := ProtoMesh.mat(Color(0.55, 0.57, 0.6), 0.5)
	ProtoMesh.cylinder(self, 0.08, x1 - x0 + 0.1, Vector3((x0 + x1) * 0.5, y_in + 0.02, z_in), trim, Vector3(0, 0, 90), 8)
	for px in [x0 + 0.05, x1 - 0.05]:
		ProtoMesh.cylinder(self, 0.03, y_out, Vector3(px, y_out * 0.5, z_out - 0.05), trim, Vector3.ZERO, 6)
	# String lights (subtle by day; glow at night via emission)
	var bulb_cols := [Color(1.0, 0.85, 0.45), Color(0.98, 0.55, 0.45), Color(0.5, 0.85, 0.8), Color(1.0, 0.95, 0.85)]
	var n := 11
	for i in n:
		var t := float(i) / (n - 1)
		var x := lerpf(x0 + 0.1, x1 - 0.1, t)
		var sag := sin(t * PI * 3.0) * 0.06
		var c: Color = bulb_cols[i % bulb_cols.size()]
		var b := ProtoMesh.sphere(self, 0.05, Vector3(x, y_out - 0.2 - absf(sag), z_out + 0.02), ProtoMesh.mat(c, 0.4, c, 1.1), Vector3.ONE, 6, 3)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
