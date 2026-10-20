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


## Protagonist (based on the concept art, then revised): chubby adult traveller, bald,
## thick black brows and moustache, stubble, big red nose, white sleeveless tank top,
## compass necklace, khaki cargo shorts, sandals, wristwatch. No bag.
## Flat colours only; shading comes from the cel lighting.
func _build() -> void:
	var skin := ProtoMesh.mat(Color(0.93, 0.64, 0.48))
	var stubble := ProtoMesh.mat(Color(0.66, 0.48, 0.38))
	var nose := ProtoMesh.mat(Color(0.9, 0.42, 0.36))
	var hair := ProtoMesh.mat(Color(0.12, 0.1, 0.1))
	var tee := ProtoMesh.mat(Color(0.96, 0.96, 0.94))
	var tee_shade := ProtoMesh.mat(Color(0.84, 0.84, 0.82))
	var shorts := ProtoMesh.mat(Color(0.62, 0.54, 0.34))
	var shorts_dark := ProtoMesh.mat(Color(0.52, 0.45, 0.28))
	var sandal := ProtoMesh.mat(Color(0.24, 0.17, 0.13))
	var cord := ProtoMesh.mat(Color(0.34, 0.22, 0.13))
	var gold := ProtoMesh.mat(Color(0.86, 0.66, 0.3))
	var dark := ProtoMesh.mat(Color(0.1, 0.09, 0.09))

	hips = Node3D.new()
	hips.position.y = HIP_HEIGHT
	add_child(hips)

	# Short, stubby legs (cute proportions): khaki shorts with rolled cuffs, bare calves, sandals
	_leg_l = _limb(hips, Vector3(-0.15, 0.0, 0.0))
	_leg_r = _limb(hips, Vector3(0.15, 0.0, 0.0))
	for i in 2:
		var leg: Node3D = [_leg_l, _leg_r][i]
		var side := -1.0 if i == 0 else 1.0
		ProtoMesh.capsule(leg, 0.15, 0.32, Vector3(0, -0.11, 0), shorts)
		ProtoMesh.cylinder(leg, 0.155, 0.05, Vector3(0, -0.25, 0), shorts_dark, Vector3.ZERO, 10)
		ProtoMesh.box(leg, Vector3(0.05, 0.12, 0.13), Vector3(side * 0.15, -0.13, 0.0), shorts_dark)
		ProtoMesh.capsule(leg, 0.11, 0.3, Vector3(0, -0.4, 0), skin)
		ProtoMesh.box(leg, Vector3(0.21, 0.05, 0.32), Vector3(0, -0.575, -0.05), sandal)
		ProtoMesh.box(leg, Vector3(0.22, 0.04, 0.06), Vector3(0, -0.53, -0.12), sandal)
		ProtoMesh.box(leg, Vector3(0.22, 0.04, 0.06), Vector3(0, -0.52, 0.03), sandal)
		ProtoMesh.box(leg, Vector3(0.17, 0.05, 0.08), Vector3(0, -0.545, -0.17), skin)

	# Torso: white sleeveless tank top over a round belly; bare shoulders, thin straps
	ProtoMesh.box(hips, Vector3(0.6, 0.12, 0.42), Vector3(0, 0.03, 0.0), shorts)
	ProtoMesh.sphere(hips, 0.36, Vector3(0, 0.36, 0.0), tee, Vector3(1.0, 1.05, 0.95), 12, 8)
	ProtoMesh.box(hips, Vector3(0.36, 0.22, 0.3), Vector3(0, 0.58, 0.02), tee)
	ProtoMesh.box(hips, Vector3(0.52, 0.16, 0.34), Vector3(0, 0.65, 0.02), skin)
	for side in [-1.0, 1.0]:
		ProtoMesh.box(hips, Vector3(0.07, 0.04, 0.32), Vector3(side * 0.13, 0.735, 0.02), tee)
	ProtoMesh.box(hips, Vector3(0.18, 0.1, 0.05), Vector3(0, 0.66, -0.16), tee_shade)
	# Compass necklace
	ProtoMesh.box(hips, Vector3(0.012, 0.16, 0.012), Vector3(-0.05, 0.64, -0.15), cord, Vector3(0, 0, -25))
	ProtoMesh.box(hips, Vector3(0.012, 0.16, 0.012), Vector3(0.05, 0.64, -0.15), cord, Vector3(0, 0, 25))
	ProtoMesh.cylinder(hips, 0.045, 0.02, Vector3(0, 0.56, -0.17), gold, Vector3(90, 0, 0), 10)

	# Head: big round bald head, stubble, red nose, moustache, thick brows
	ProtoMesh.cylinder(hips, 0.11, 0.1, Vector3(0, 0.74, 0), skin, Vector3.ZERO, 8)
	ProtoMesh.sphere(hips, 0.25, Vector3(0, 0.98, 0), skin, Vector3(1.0, 1.0, 0.95), 12, 8)
	ProtoMesh.sphere(hips, 0.235, Vector3(0, 0.9, -0.03), stubble, Vector3(1.0, 0.6, 0.95), 12, 6)
	ProtoMesh.sphere(hips, 0.07, Vector3(0, 0.95, -0.25), nose, Vector3(1.1, 0.9, 1.0), 8, 5)
	ProtoMesh.box(hips, Vector3(0.28, 0.07, 0.07), Vector3(0, 0.88, -0.24), hair)
	ProtoMesh.box(hips, Vector3(0.08, 0.05, 0.05), Vector3(-0.12, 0.86, -0.22), hair, Vector3(0, 0, 25))
	ProtoMesh.box(hips, Vector3(0.08, 0.05, 0.05), Vector3(0.12, 0.86, -0.22), hair, Vector3(0, 0, -25))
	for side in [-1.0, 1.0]:
		ProtoMesh.box(hips, Vector3(0.05, 0.065, 0.03), Vector3(side * 0.09, 1.01, -0.235), dark)
		ProtoMesh.box(hips, Vector3(0.11, 0.04, 0.04), Vector3(side * 0.09, 1.07, -0.23), hair, Vector3(0, 0, side * -10.0))
		ProtoMesh.sphere(hips, 0.06, Vector3(side * 0.25, 0.98, 0.02), skin, Vector3(0.6, 1.0, 1.0), 6, 4)

	# Arms with elbows: bare arms (tank top), watch on the left wrist
	_arm_l = _limb(hips, Vector3(-0.38, 0.62, 0.0))
	_arm_r = _limb(hips, Vector3(0.38, 0.62, 0.0))
	for i in 2:
		var arm: Node3D = [_arm_l, _arm_r][i]
		ProtoMesh.sphere(arm, 0.12, Vector3(0, 0.0, 0), skin)
		ProtoMesh.capsule(arm, 0.105, 0.3, Vector3(0, -0.1, 0), skin)
		var elbow := _limb(arm, Vector3(0, -0.24, 0))
		ProtoMesh.capsule(elbow, 0.09, 0.28, Vector3(0, -0.11, 0), skin)
		ProtoMesh.sphere(elbow, 0.1, Vector3(0, -0.27, 0), skin)
		if i == 0:
			_elbow_l = elbow
			ProtoMesh.cylinder(elbow, 0.095, 0.05, Vector3(0, -0.19, 0), dark, Vector3.ZERO, 8)
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
