class_name CamperExterior
extends Node3D
## Stylized modern Class-C motorhome. Front faces local +X, door side is local +Z (camera side).
## Body = extruded rounded side profile with bevelled edges + painted livery shader,
## rounded windows, roof cargo box, spare wheel cover (no awning).

const LENGTH := 7.4
const WIDTH := 2.4
const DOOR_LOCAL := Vector3(-1.0, 0.0, 1.25)
const HEADLIGHT_LOCAL := Vector3(3.8, 0.98, 0.78)
const TAILLIGHT_LOCAL := Vector3(-3.63, 1.05, 0.92)
const WHEEL_X := [2.5, -2.0]

## Baked sprite directions (P1 driving): 16 yaws in a 4 x 4 atlas, starting at the parking yaw.
const SPRITE_DIRECTIONS := 16
const SPRITE_COLS := 4

var lights: PrototypeCamperLights
var paint: ShaderMaterial
## False when a CamperVehicle body provides the collision (and in bake instances).
var with_collider := true
var sprite_dir := 0
## Attachment nodes by part id (GDD 9.2 외장): shown when switched on in Game.camper_mods.parts.
var _parts := {}


func _ready() -> void:
	_build_body()
	_build_details()
	_build_parts()
	apply_look()
	if with_collider:
		ProtoMesh.static_box_collider(self, Vector3(LENGTH, 6.0, WIDTH), Vector3(0, 2.0, 0))
	lights = PrototypeCamperLights.new()
	lights.name = "Lights"
	add_child(lights)
	lights.build(self)


## Bake request: 16 yaws (cell i = base_yaw + i * 22.5 deg), lamps off / on emission variants.
static func sprite_bake_spec(base_yaw_deg: float) -> Dictionary:
	return {
		"builder": func(c: int, r: int) -> Node3D:
			var cam := CamperExterior.new()
			cam.with_collider = false
			cam.rotation_degrees.y = base_yaw_deg + (r * SPRITE_COLS + c) * 360.0 / SPRITE_DIRECTIONS
			return cam,
		"cols": SPRITE_COLS,
		"rows": SPRITE_DIRECTIONS / SPRITE_COLS,
		# Facing the camera the long body stands up to ~4.9 m above the anchor.
		"cell": Vector2(10.5, 10.2),
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
		sprite.set_inner_lines(true)  # pixel-art inner lines: panel edges, windows
		add_child(sprite)
	elif sheet == null and sprite:
		sprite.queue_free()
		sprite = null
	if sprite and sprite.sheet != sheet:
		sprite.set_sheet(sheet)
		set_sprite_dir(sprite_dir)
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


func set_sprite_dir(i: int) -> void:
	sprite_dir = posmod(i, SPRITE_DIRECTIONS)
	if sprite:
		sprite.set_frame(sprite_dir % SPRITE_COLS, sprite_dir / SPRITE_COLS)


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


## Paint scheme and attachments from the upgrades (Game.camper_mods). Bake instances built later
## read the same state, so the sprite matches (its sheet name includes CamperUpgrades.look_key()).
func apply_look() -> void:
	var pc := CamperUpgrades.paint_colors()
	for k in ["body", "skirt", "stripe_a", "stripe_b"]:
		if pc.has(k):
			var c: Array = pc[k]
			paint.set_shader_parameter(k, Color(float(c[0]), float(c[1]), float(c[2])))
	var on: Array = Game.camper_mods.get("parts", [])
	for id: String in _parts:
		(_parts[id] as Node3D).visible = on.has(id)


func _build_parts() -> void:
	# side awning over the door: striped canopy sloping out from the roof edge, two poles
	var aw := Node3D.new()
	add_child(aw)
	var stripe_a := ProtoMesh.mat(Color(0.92, 0.42, 0.32))
	var stripe_b := ProtoMesh.mat(Color(0.96, 0.92, 0.84))
	for i in 6:
		var x := -2.5 + i * 0.5 + 0.25
		var cm := ProtoMesh.box(aw, Vector3(0.5, 0.05, 1.5), Vector3(x, 2.72, WIDTH * 0.5 + 0.72), stripe_a if i % 2 == 0 else stripe_b, Vector3(-14, 0, 0))
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var pole := ProtoMesh.mat(Color(0.75, 0.76, 0.78), 0.4)
	for x in [-2.45, 0.45]:
		ProtoMesh.cylinder(aw, 0.03, 2.5, Vector3(x, 1.25, WIDTH * 0.5 + 1.42), pole, Vector3.ZERO, 6)
	_parts["awning"] = aw
	# travel flag on the rear ladder
	var fl := Node3D.new()
	add_child(fl)
	ProtoMesh.cylinder(fl, 0.025, 1.6, Vector3(-3.7, 3.9, -0.62), pole, Vector3.ZERO, 6)
	ProtoMesh.box(fl, Vector3(0.7, 0.42, 0.03), Vector3(-4.05, 4.45, -0.62), ProtoMesh.mat(Color(0.98, 0.78, 0.3)))
	ProtoMesh.box(fl, Vector3(0.7, 0.12, 0.035), Vector3(-4.05, 4.45, -0.62), ProtoMesh.mat(Color(0.3, 0.6, 0.58)))
	_parts["flag"] = fl
	# front bull bar: tubes around the grille
	var bb := Node3D.new()
	add_child(bb)
	var tube := ProtoMesh.mat(Color(0.2, 0.21, 0.24), 0.5)
	ProtoMesh.capsule(bb, 0.07, WIDTH * 0.9, Vector3(4.0, 1.1, 0), tube, Vector3(90, 0, 0))
	ProtoMesh.capsule(bb, 0.07, WIDTH * 0.9, Vector3(4.0, 0.62, 0), tube, Vector3(90, 0, 0))
	for z in [-0.75, 0.0, 0.75]:
		ProtoMesh.box(bb, Vector3(0.1, 0.6, 0.08), Vector3(4.0, 0.86, z), tube)
	_parts["bullbar"] = bb


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

	# Door (camera side) with window and handle (no step / ground mat: they travelled with the camper)
	var dz := WIDTH * 0.5
	_panel(Vector2(0.78, 1.86), Vector3(DOOR_LOCAL.x, 1.56, dz), 0.1, 0.04, door_mat)
	_panel(Vector2(0.42, 0.42), Vector3(DOOR_LOCAL.x, 2.1, dz + 0.04), 0.1, 0.02, glass)
	ProtoMesh.box(self, Vector3(0.14, 0.05, 0.05), Vector3(DOOR_LOCAL.x + 0.26, 1.5, dz + 0.07), chrome)

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
