class_name PlayerRig
extends Node3D
## The player's 3D model (procedural low-poly person) with poseable limbs.
## Used two ways: as the source model that SpriteBaker renders into pixel sprite sheets,
## and live (shadow-only) so the baked sprite still casts a correct animated shadow.

const ATTACK_TIME := 0.32
## Short legs: hip height 0.6 m (was 0.8) for chubby, cute proportions.
const HIP_HEIGHT := 0.6
## Sprite sheet columns: [animation, frame count]. Rows are 8 facing directions.
const ANIMS := [["idle", 2], ["walk", 8], ["attack", 5]]
const DIRECTIONS := 8

var hips: Node3D
var lantern_anchor: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _lantern_glass: MeshInstance3D
var _glass_on: Material
var _glass_off: Material


func _init() -> void:
	_build()


static func column_count() -> int:
	var n := 0
	for a: Array in ANIMS:
		n += a[1]
	return n


static func column_for(anim: String, frame: int) -> int:
	var c := 0
	for a: Array in ANIMS:
		if a[0] == anim:
			return c + clampi(frame, 0, a[1] - 1)
		c += a[1]
	return 0


static func direction_index(yaw: float) -> int:
	return posmod(roundi(yaw / (TAU / DIRECTIONS)), DIRECTIONS)


static func direction_yaw(index: int) -> float:
	return index * TAU / DIRECTIONS


## Protagonist (pixel concept art, simplified and cute): chubby bald man, big brown moustache
## and brows, rosy cheeks, open red plaid flannel over a white tank top, brown belt,
## olive cargo pants, brown boots, short legs.
## Flat colours only; shading comes from the cel lighting.
func _build() -> void:
	var skin := ProtoMesh.mat(Color(0.95, 0.68, 0.5))
	var cheek := ProtoMesh.mat(Color(0.96, 0.52, 0.46))
	var stache := ProtoMesh.mat(Color(0.36, 0.22, 0.14))
	var dark := ProtoMesh.mat(Color(0.1, 0.08, 0.08))
	var tank := ProtoMesh.mat(Color(0.97, 0.96, 0.93))
	var flannel := _plaid_mat()
	var flannel_dark := ProtoMesh.mat(Color(0.56, 0.12, 0.12))
	var pants := ProtoMesh.mat(Color(0.47, 0.5, 0.26))
	var pants_dark := ProtoMesh.mat(Color(0.38, 0.41, 0.2))
	var belt := ProtoMesh.mat(Color(0.36, 0.22, 0.13))
	var buckle := ProtoMesh.mat(Color(0.82, 0.82, 0.8))
	var boot := ProtoMesh.mat(Color(0.55, 0.34, 0.18))
	var boot_dark := ProtoMesh.mat(Color(0.32, 0.2, 0.11))

	hips = Node3D.new()
	hips.position.y = HIP_HEIGHT
	add_child(hips)

	# Short legs: olive cargo pants with side pockets and a rolled hem, chunky brown boots
	_leg_l = _limb(hips, Vector3(-0.15, 0.0, 0.0))
	_leg_r = _limb(hips, Vector3(0.15, 0.0, 0.0))
	for i in 2:
		var leg: Node3D = [_leg_l, _leg_r][i]
		var side := -1.0 if i == 0 else 1.0
		ProtoMesh.capsule(leg, 0.15, 0.52, Vector3(0, -0.22, 0), pants)
		ProtoMesh.box(leg, Vector3(0.06, 0.13, 0.15), Vector3(side * 0.15, -0.2, 0.0), pants_dark)
		ProtoMesh.cylinder(leg, 0.15, 0.06, Vector3(0, -0.43, 0), pants_dark, Vector3.ZERO, 10)
		ProtoMesh.cylinder(leg, 0.12, 0.09, Vector3(0, -0.5, -0.01), boot, Vector3.ZERO, 10)
		ProtoMesh.box(leg, Vector3(0.22, 0.09, 0.34), Vector3(0, -0.555, -0.06), boot)
		ProtoMesh.box(leg, Vector3(0.23, 0.03, 0.35), Vector3(0, -0.59, -0.06), boot_dark)

	# Torso: round belly in a white tank top, brown belt with a silver buckle
	ProtoMesh.sphere(hips, 0.34, Vector3(0, 0.36, -0.06), tank, Vector3(0.95, 1.0, 0.95), 12, 8)
	ProtoMesh.box(hips, Vector3(0.44, 0.26, 0.32), Vector3(0, 0.6, 0.02), tank)
	ProtoMesh.box(hips, Vector3(0.18, 0.08, 0.05), Vector3(0, 0.7, -0.15), skin)
	ProtoMesh.cylinder(hips, 0.33, 0.08, Vector3(0, 0.06, 0.0), belt, Vector3.ZERO, 12)
	ProtoMesh.box(hips, Vector3(0.1, 0.07, 0.04), Vector3(0, 0.06, -0.33), buckle)
	# Open red flannel shirt: back + side panels and collar, chest left open
	ProtoMesh.sphere(hips, 0.36, Vector3(0, 0.4, 0.06), flannel, Vector3(1.05, 1.05, 0.9), 12, 8)
	for side in [-1.0, 1.0]:
		ProtoMesh.box(hips, Vector3(0.17, 0.64, 0.44), Vector3(side * 0.3, 0.4, -0.02), flannel, Vector3(0, 0, side * -4.0))
		ProtoMesh.box(hips, Vector3(0.1, 0.58, 0.06), Vector3(side * 0.21, 0.4, -0.27), flannel, Vector3(0, side * 18.0, 0))
		ProtoMesh.box(hips, Vector3(0.12, 0.06, 0.16), Vector3(side * 0.15, 0.73, -0.12), flannel_dark, Vector3(0, side * 25.0, side * -20.0))

	# Head: big round bald head, ears, rosy cheeks, bushy brown moustache and brows
	ProtoMesh.cylinder(hips, 0.12, 0.08, Vector3(0, 0.75, 0), skin, Vector3.ZERO, 8)
	ProtoMesh.sphere(hips, 0.28, Vector3(0, 1.0, 0), skin, Vector3(1.0, 0.98, 0.95), 12, 8)
	ProtoMesh.sphere(hips, 0.065, Vector3(0, 0.96, -0.27), skin, Vector3(1.1, 0.9, 1.0), 8, 5)
	for side in [-1.0, 1.0]:
		ProtoMesh.sphere(hips, 0.07, Vector3(side * 0.28, 0.99, 0.02), skin, Vector3(0.55, 1.0, 0.9), 6, 4)
		ProtoMesh.sphere(hips, 0.06, Vector3(side * 0.15, 0.93, -0.22), cheek, Vector3(1.0, 0.7, 0.5), 6, 4)
		ProtoMesh.box(hips, Vector3(0.045, 0.07, 0.03), Vector3(side * 0.09, 1.03, -0.255), dark)
		ProtoMesh.box(hips, Vector3(0.12, 0.045, 0.05), Vector3(side * 0.1, 1.1, -0.24), stache, Vector3(0, 0, side * -12.0))
		ProtoMesh.box(hips, Vector3(0.19, 0.1, 0.08), Vector3(side * 0.1, 0.89, -0.25), stache, Vector3(0, 0, side * 20.0))

	# Arms: flannel sleeves rolled to the elbow, bare forearms
	_arm_l = _limb(hips, Vector3(-0.4, 0.62, 0.0))
	_arm_r = _limb(hips, Vector3(0.4, 0.62, 0.0))
	for i in 2:
		var arm: Node3D = [_arm_l, _arm_r][i]
		ProtoMesh.capsule(arm, 0.13, 0.34, Vector3(0, -0.1, 0), flannel)
		ProtoMesh.cylinder(arm, 0.135, 0.07, Vector3(0, -0.22, 0), flannel_dark, Vector3.ZERO, 10)
		var elbow := _limb(arm, Vector3(0, -0.24, 0))
		ProtoMesh.capsule(elbow, 0.095, 0.28, Vector3(0, -0.11, 0), skin)
		ProtoMesh.sphere(elbow, 0.105, Vector3(0, -0.27, 0), skin)
		if i == 0:
			_elbow_l = elbow
		else:
			_elbow_r = elbow

	# Belt lantern on the left hip (GDD 10.3: 허리띠에 끼우는 등불)
	lantern_anchor = Node3D.new()
	lantern_anchor.position = Vector3(-0.36, 0.0, -0.04)
	hips.add_child(lantern_anchor)
	ProtoMesh.box(lantern_anchor, Vector3(0.11, 0.03, 0.11), Vector3(0, 0.07, 0), dark)
	ProtoMesh.box(lantern_anchor, Vector3(0.11, 0.03, 0.11), Vector3(0, -0.09, 0), dark)
	_glass_off = ProtoMesh.mat(Color(0.62, 0.56, 0.4))
	_glass_on = ProtoMesh.mat(Color(1.0, 0.85, 0.5), 0.4, Color(1.0, 0.7, 0.3), 3.0)
	_lantern_glass = ProtoMesh.box(lantern_anchor, Vector3(0.09, 0.13, 0.09), Vector3(0, -0.01, 0), _glass_off)
	_lantern_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Simplified red/dark-red buffalo plaid (big checks so it survives pixelation).
static func _plaid_mat() -> StandardMaterial3D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	var red := Color(0.85, 0.22, 0.18)
	var mid := Color(0.66, 0.16, 0.15)
	var dark := Color(0.42, 0.1, 0.12)
	for y in 4:
		for x in 4:
			var a := x < 2
			var b := y < 2
			img.set_pixel(x, y, dark if a and b else (mid if a or b else red))
	var m := ProtoMesh.unique_mat(Color.WHITE)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.2
	m.roughness = 0.06
	return m


func _limb(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func set_lantern(on: bool) -> void:
	_lantern_glass.material_override = _glass_on if on else _glass_off


## walk_phase in radians; moving 0..1; attack_t seconds since swing start (< 0 = none).
## Idle: both arms relaxed, left hand in the pocket.
func pose(walk_phase: float, moving: float, attack_t: float, breathe := 0.0) -> void:
	var swing := sin(walk_phase) * 0.55 * moving
	_leg_l.rotation = Vector3(swing, 0, 0)
	_leg_r.rotation = Vector3(-swing, 0, 0)
	_arm_l.rotation = Vector3(-swing * 0.8 - 0.1, 0, deg_to_rad(-12.0))
	_elbow_l.rotation = Vector3(lerpf(0.5, 0.25, moving), 0, 0)
	_arm_r.rotation = Vector3(swing * 0.8 - 0.05, 0, deg_to_rad(10.0))
	_elbow_r.rotation = Vector3(lerpf(0.25, 0.3, moving), 0, 0)
	hips.position.y = HIP_HEIGHT + absf(sin(walk_phase)) * 0.04 * moving + breathe
	hips.rotation = Vector3(0, 0, sin(walk_phase) * 0.04 * moving)
	if attack_t >= 0.0:
		var t := clampf(attack_t / ATTACK_TIME, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - t, 3.0)
		# Placeholder strike: right arm sweeps forward right -> left (no weapon in the concept).
		_arm_r.rotation = Vector3(deg_to_rad(80.0), deg_to_rad(lerpf(75.0, -80.0, e)), 0.0)
		_elbow_r.rotation = Vector3(0.2, 0, 0)
		hips.rotation.y = deg_to_rad(lerpf(20.0, -15.0, e))


## Pose for a sprite sheet column (see ANIMS).
func pose_column(col: int) -> void:
	var c := col
	for a: Array in ANIMS:
		if c < a[1]:
			match a[0]:
				"idle":
					pose(0.0, 0.0, -1.0, 0.012 * c)
				"walk":
					pose(TAU * c / a[1], 1.0, -1.0)
				"attack":
					pose(0.0, 0.0, ATTACK_TIME * c / (a[1] - 1))
			return
		c -= a[1]
