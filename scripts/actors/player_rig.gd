class_name PlayerRig
extends Node3D
## The player's 3D model (procedural low-poly person) with poseable limbs.
## Used two ways: as the source model that SpriteBaker renders into pixel sprite sheets,
## and live (shadow-only) so the baked sprite still casts a correct animated shadow.

const ATTACK_TIME := 0.32
## Sprite sheet columns: [animation, frame count]. Rows are 8 facing directions.
const ANIMS := [["idle", 2], ["walk", 8], ["attack", 5]]
const DIRECTIONS := 8

var hips: Node3D
var lantern_anchor: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
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


func _build() -> void:
	var skin := ProtoMesh.mat(Color(0.95, 0.76, 0.62))
	var hair := ProtoMesh.mat(Color(0.24, 0.15, 0.1))
	var jacket := ProtoMesh.mat(Color(0.82, 0.34, 0.2))
	var jacket_dark := ProtoMesh.mat(Color(0.62, 0.24, 0.16))
	var shirt := ProtoMesh.mat(Color(0.95, 0.91, 0.8))
	var pants := ProtoMesh.mat(Color(0.2, 0.25, 0.42))
	var shoes := ProtoMesh.mat(Color(0.18, 0.13, 0.1))
	var leather := ProtoMesh.mat(Color(0.45, 0.29, 0.16))
	var pack := ProtoMesh.mat(Color(0.36, 0.46, 0.28))
	var steel := ProtoMesh.mat(Color(0.82, 0.84, 0.88), 0.35)
	var dark := ProtoMesh.mat(Color(0.08, 0.07, 0.07))

	hips = Node3D.new()
	hips.position.y = 0.86
	add_child(hips)
	_leg_l = _limb(hips, Vector3(-0.12, 0.0, 0.0))
	_leg_r = _limb(hips, Vector3(0.12, 0.0, 0.0))
	for leg: Node3D in [_leg_l, _leg_r]:
		ProtoMesh.capsule(leg, 0.11, 0.78, Vector3(0, -0.39, 0), pants)
		ProtoMesh.box(leg, Vector3(0.19, 0.11, 0.32), Vector3(0, -0.8, -0.05), shoes)
	# Torso: jacket with collar and hem, shirt, belt, backpack with bedroll
	ProtoMesh.box(hips, Vector3(0.5, 0.56, 0.32), Vector3(0, 0.3, 0), jacket)
	ProtoMesh.box(hips, Vector3(0.52, 0.08, 0.34), Vector3(0, 0.06, 0), jacket_dark)
	ProtoMesh.box(hips, Vector3(0.2, 0.42, 0.04), Vector3(0, 0.34, -0.16), shirt)
	ProtoMesh.box(hips, Vector3(0.36, 0.08, 0.3), Vector3(0, 0.56, 0), jacket_dark)
	ProtoMesh.box(hips, Vector3(0.53, 0.07, 0.35), Vector3(0, 0.0, 0), leather)
	ProtoMesh.box(hips, Vector3(0.4, 0.46, 0.22), Vector3(0, 0.32, 0.26), pack)
	ProtoMesh.cylinder(hips, 0.09, 0.46, Vector3(0, 0.6, 0.27), ProtoMesh.mat(Color(0.86, 0.72, 0.42)), Vector3(0, 0, 90), 8)
	ProtoMesh.box(hips, Vector3(0.05, 0.4, 0.05), Vector3(-0.15, 0.32, 0.38), leather)
	ProtoMesh.box(hips, Vector3(0.05, 0.4, 0.05), Vector3(0.15, 0.32, 0.38), leather)
	# Head: slightly big for readability at sprite size
	ProtoMesh.box(hips, Vector3(0.14, 0.08, 0.14), Vector3(0, 0.62, 0), skin)
	ProtoMesh.sphere(hips, 0.22, Vector3(0, 0.82, 0), skin, Vector3.ONE, 10, 6)
	ProtoMesh.sphere(hips, 0.235, Vector3(0, 0.89, 0.04), hair, Vector3(1.0, 0.78, 1.0), 10, 6)
	ProtoMesh.box(hips, Vector3(0.3, 0.1, 0.14), Vector3(0, 0.96, -0.12), hair, Vector3(-15, 0, 0))
	ProtoMesh.box(hips, Vector3(0.05, 0.07, 0.03), Vector3(-0.08, 0.81, -0.205), dark)
	ProtoMesh.box(hips, Vector3(0.05, 0.07, 0.03), Vector3(0.08, 0.81, -0.205), dark)
	# Arms + placeholder iron sword in the right hand
	_arm_l = _limb(hips, Vector3(-0.32, 0.52, 0.0))
	_arm_r = _limb(hips, Vector3(0.32, 0.52, 0.0))
	for arm: Node3D in [_arm_l, _arm_r]:
		ProtoMesh.capsule(arm, 0.085, 0.58, Vector3(0, -0.26, 0), jacket)
		ProtoMesh.sphere(arm, 0.09, Vector3(0, -0.56, 0), skin)
	ProtoMesh.box(_arm_r, Vector3(0.05, 0.16, 0.05), Vector3(0, -0.64, 0), leather)
	ProtoMesh.box(_arm_r, Vector3(0.24, 0.045, 0.07), Vector3(0, -0.72, 0), steel)
	ProtoMesh.box(_arm_r, Vector3(0.08, 0.66, 0.025), Vector3(0, -1.06, 0), steel)
	# Belt lantern on the left hip (GDD 10.3)
	lantern_anchor = Node3D.new()
	lantern_anchor.position = Vector3(-0.31, 0.0, -0.06)
	hips.add_child(lantern_anchor)
	ProtoMesh.box(lantern_anchor, Vector3(0.12, 0.03, 0.12), Vector3(0, 0.08, 0), dark)
	ProtoMesh.box(lantern_anchor, Vector3(0.12, 0.03, 0.12), Vector3(0, -0.1, 0), dark)
	_glass_off = ProtoMesh.mat(Color(0.6, 0.55, 0.38), 0.4)
	_glass_on = ProtoMesh.mat(Color(1.0, 0.85, 0.5), 0.4, Color(1.0, 0.7, 0.3), 3.0)
	_lantern_glass = ProtoMesh.box(lantern_anchor, Vector3(0.1, 0.15, 0.1), Vector3(0, -0.01, 0), _glass_off)
	_lantern_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _limb(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func set_lantern(on: bool) -> void:
	_lantern_glass.material_override = _glass_on if on else _glass_off


## walk_phase in radians; moving 0..1; attack_t seconds since swing start (< 0 = none).
func pose(walk_phase: float, moving: float, attack_t: float, breathe := 0.0) -> void:
	var swing := sin(walk_phase) * 0.65 * moving
	_leg_l.rotation = Vector3(swing, 0, 0)
	_leg_r.rotation = Vector3(-swing, 0, 0)
	_arm_l.rotation = Vector3(-swing * 0.7, 0, 0)
	_arm_r.rotation = Vector3(swing * 0.5 + 0.25, 0.0, 0.0)
	hips.position.y = 0.86 + absf(sin(walk_phase)) * 0.05 * moving + breathe
	hips.rotation.y = 0.0
	if attack_t >= 0.0:
		var t := clampf(attack_t / ATTACK_TIME, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - t, 3.0)
		# Horizontal slash: arm raised forward, sweeping right -> left.
		_arm_r.rotation = Vector3(deg_to_rad(80.0), deg_to_rad(lerpf(75.0, -80.0, e)), 0.0)
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
