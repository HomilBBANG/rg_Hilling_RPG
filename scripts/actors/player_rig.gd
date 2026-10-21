class_name PlayerRig
extends Node3D
## The player's 3D model: the AI-generated character (assets/characters/player/player.glb, scaled,
## decimated and skinned to a simple humanoid skeleton by tools/blender/player_model_prepare.py),
## posed from code through its bones. Used two ways: as the source model that SpriteBaker renders
## into pixel sprite sheets, and live (shadow-only) so the baked sprite still casts a correct
## animated shadow. Held items (weapon, shield, potion, bread) ride on the hand / forearm bones and
## the belt lantern on the hips bone.

const MODEL := preload("res://assets/characters/player/player.glb")
const ATTACK_TIME := 0.32
## Sprite sheet columns: [animation, frame count]. Rows are 8 facing directions.
## drink / eat / cast: common use motions per consumable kind (GDD 6.4) and for spells.
## run: Shift running - arms pumping, sword held upright.
const ANIMS := [["idle", 2], ["walk", 8], ["attack", 5], ["drink", 2], ["eat", 2], ["cast", 2], ["run", 6]]
const DIRECTIONS := 8
## Wrist tilt of the sword at rest (blade forward-down).
const SWORD_REST_TILT := 1.05

var lantern_anchor: Node3D
var _skel: Skeleton3D
var _bone := {}          # bone name -> index
var _rest_rig := {}      # bone index -> rest orientation in rig axes (front -Z, right +X)
var _skel_to_rig: Transform3D
var _hips_rest := Vector3.ZERO
var _sword: Node3D
var _shield: Node3D
var _bottle: Node3D
var _bun: Node3D
## Shown equipment: {"main": base id, "off": base id, "lantern": bool}.
var gear := {"main": "iron_sword", "off": "", "lantern": true}
var _lantern_glass: MeshInstance3D
var _glass_on: Material
var _glass_off: Material
static var _body_mat: StandardMaterial3D
static var _shirt_mat: StandardMaterial3D


func _init() -> void:
	_build()
	set_gear(gear)


## Poses set before entering the tree (the sprite baker poses each copy first) never reach the skin:
## Skeleton3D only schedules an update for changes made while inside. Nudge the root bone once
## everything is in the tree so the whole skeleton recomputes with the stored pose.
func _ready() -> void:
	var i: int = _bone["hips"]
	var p := _skel.get_bone_pose_position(i)
	_skel.set_bone_pose_position(i, p + Vector3(0, 0.0001, 0))
	_skel.set_bone_pose_position(i, p)


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
	var model: Node3D = MODEL.instantiate()
	model.rotation.y = PI  # the export faces +Z; every actor here faces -Z
	add_child(model)
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	# The sprite baker disables processing on its instances: the skeleton must still apply poses.
	_skel.process_mode = Node.PROCESS_MODE_ALWAYS
	_skel_to_rig = Transform3D.IDENTITY
	var n: Node = _skel
	while n != self:
		_skel_to_rig = (n as Node3D).transform * _skel_to_rig
		n = n.get_parent()
	for i in _skel.get_bone_count():
		_bone[_skel.get_bone_name(i)] = i
		_rest_rig[i] = (_skel_to_rig.basis * _skel.get_bone_global_rest(i).basis).orthonormalized()
	_hips_rest = _skel.get_bone_rest(_bone["hips"]).origin
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _toon(mi as MeshInstance3D)

	# Weapon wrist pivot in the right fist (blade along its -Y: forward-down at rest, in line with
	# the arm during the swing), shield on the outside of the left forearm, props in the left fist.
	_sword = _attach("hand_R", _bone_point("hand_R", 0.085) + Vector3(0, 0, -0.02))
	_shield = _attach("forearm_L", _bone_point("forearm_L", 0.12) + Vector3(-0.1, 0, 0))
	_bottle = _attach("hand_L", _bone_point("hand_L", 0.1) + Vector3(0, 0, -0.04))
	# pale glass so it reads against the red flannel
	ProtoMesh.cylinder(_bottle, 0.05, 0.11, Vector3.ZERO, ProtoMesh.mat(Color(0.62, 0.9, 0.98), 0.3), Vector3.ZERO, 8)
	ProtoMesh.cylinder(_bottle, 0.02, 0.05, Vector3(0, -0.07, 0), ProtoMesh.mat(Color(0.8, 0.85, 0.9), 0.3), Vector3.ZERO, 6)
	ProtoMesh.cylinder(_bottle, 0.022, 0.025, Vector3(0, -0.105, 0), ProtoMesh.mat(Color(0.55, 0.38, 0.22)), Vector3.ZERO, 6)
	_bun = _attach("hand_L", _bone_point("hand_L", 0.1) + Vector3(0, 0, -0.04))
	ProtoMesh.sphere(_bun, 0.08, Vector3.ZERO, ProtoMesh.mat(Color(0.78, 0.55, 0.28)), Vector3(1.2, 0.8, 1.0), 8, 5)
	_bottle.visible = false
	_bun.visible = false

	# Belt lantern on the left hip, a little behind the hanging arm (GDD 10.3: 허리띠에 끼우는 등불)
	lantern_anchor = _attach("hips", Vector3(-0.43, 0.47, 0.08))
	var dark := ProtoMesh.mat(Color(0.1, 0.08, 0.08))
	ProtoMesh.box(lantern_anchor, Vector3(0.11, 0.03, 0.11), Vector3(0, 0.07, 0), dark)
	ProtoMesh.box(lantern_anchor, Vector3(0.11, 0.03, 0.11), Vector3(0, -0.09, 0), dark)
	_glass_off = ProtoMesh.mat(Color(0.62, 0.56, 0.4))
	_glass_on = ProtoMesh.mat(Color(1.0, 0.85, 0.5), 0.4, Color(1.0, 0.7, 0.3), 3.0)
	_lantern_glass = ProtoMesh.box(lantern_anchor, Vector3(0.09, 0.13, 0.09), Vector3(0, -0.01, 0), _glass_off)
	_lantern_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pose(0.0, 0.0, -1.0)


## Same flat cel look as the rest of the game (ProtoMesh toon). The body carries flat palette
## colours per face (vertex colours, see the prepare script); the shirt is its own mesh and gets
## big buffalo plaid checks projected on it, like the old model, so the pattern reads at sprite size.
static func _toon(mi: MeshInstance3D) -> StandardMaterial3D:
	if mi.name.begins_with("Shirt"):
		if _shirt_mat == null:
			_shirt_mat = _plaid_mat()
		return _shirt_mat
	if _body_mat == null:
		_body_mat = ProtoMesh.unique_mat(Color.WHITE)
		_body_mat.vertex_color_use_as_albedo = true
	return _body_mat


## Simplified red/dark-red buffalo plaid (big checks so it survives pixelation).
static func _plaid_mat() -> StandardMaterial3D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	var red := Color(0.8, 0.2, 0.19)
	var mid := Color(0.6, 0.14, 0.14)
	var dark := Color(0.38, 0.09, 0.1)
	for y in 4:
		for x in 4:
			var a := x < 2
			var b := y < 2
			img.set_pixel(x, y, dark if a and b else (mid if a or b else red))
	var m := ProtoMesh.unique_mat(Color.WHITE)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.2   # one repeat = 0.45 m: checks of about 23 cm
	return m


## A point along a bone at rest (rig space), `along` metres from its head.
func _bone_point(bone: String, along: float) -> Vector3:
	var i: int = _bone[bone]
	var rest := _skel_to_rig * _skel.get_bone_global_rest(i)
	return rest.origin + (_rest_rig[i] as Basis).y.normalized() * along


## Node riding on a bone whose axes match the rig's axes while the bone is at rest, placed at
## `pivot` (rig space) - so props keep the offsets / rotations they had on the old procedural rig.
func _attach(bone: String, pivot: Vector3) -> Node3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	ba.process_mode = Node.PROCESS_MODE_ALWAYS
	_skel.add_child(ba)
	var frame := Node3D.new()
	var rest := _skel_to_rig * _skel.get_bone_global_rest(_bone[bone])
	frame.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY, pivot)
	ba.add_child(frame)
	var holder := Node3D.new()  # free to rotate (sword tilt) without losing the frame's alignment
	frame.add_child(holder)
	return holder


## Rotates a bone by `euler` (YXZ, in rig axes, like Node3D.rotation on the old rig's limb pivots);
## children follow, so a forearm turn is relative to its upper arm.
func _rot(bone: String, euler: Vector3) -> void:
	var i: int = _bone[bone]
	var rg: Basis = _rest_rig[i]
	var delta := rg.inverse() * Basis.from_euler(euler) * rg
	_skel.set_bone_pose_rotation(i, (_skel.get_bone_rest(i).basis.orthonormalized() * delta).get_rotation_quaternion())


func _hips_lift(dy: float) -> void:
	_skel.set_bone_pose_position(_bone["hips"], _hips_rest + Vector3(0, dy, 0))


## Rebuilds the held weapon / shield and shows the belt lantern only with a lantern belt.
func set_gear(g: Dictionary) -> void:
	gear = g.duplicate()
	for n in [_sword, _shield]:
		for c in n.get_children():
			n.remove_child(c)
			c.free()
	var iron := ProtoMesh.mat(Color(0.36, 0.37, 0.42), 0.4)
	var leather := ProtoMesh.mat(Color(0.42, 0.26, 0.15))
	match gear.get("main", ""):
		"iron_sword":  # 철검: plain steel, 0.46 m blade
			var steel := ProtoMesh.mat(Color(0.8, 0.83, 0.87), 0.3)
			ProtoMesh.sphere(_sword, 0.035, Vector3(0, 0.09, 0), iron, Vector3.ONE, 6, 4)        # pommel
			ProtoMesh.cylinder(_sword, 0.026, 0.13, Vector3(0, 0.02, 0), leather, Vector3.ZERO, 6)  # grip
			ProtoMesh.box(_sword, Vector3(0.21, 0.035, 0.05), Vector3(0, -0.055, 0), iron)            # crossguard
			ProtoMesh.box(_sword, Vector3(0.08, 0.46, 0.024), Vector3(0, -0.3, 0), steel)             # blade
			ProtoMesh.box(_sword, Vector3(0.056, 0.056, 0.024), Vector3(0, -0.53, 0), steel, Vector3(0, 0, 45))
		"flame_longsword":  # 불꽃 장검: long two-hander, ember-red blade with a bright edge, gold guard
			var blade := ProtoMesh.mat(Color(0.86, 0.38, 0.22), 0.3)
			var edge := ProtoMesh.mat(Color(1.0, 0.78, 0.38), 0.3)
			var gold := ProtoMesh.mat(Color(0.86, 0.66, 0.24), 0.3)
			ProtoMesh.sphere(_sword, 0.04, Vector3(0, 0.15, 0), gold, Vector3.ONE, 6, 4)
			ProtoMesh.cylinder(_sword, 0.028, 0.24, Vector3(0, 0.03, 0), leather, Vector3.ZERO, 6)
			ProtoMesh.box(_sword, Vector3(0.28, 0.045, 0.06), Vector3(0, -0.1, 0), gold)
			ProtoMesh.box(_sword, Vector3(0.1, 0.72, 0.026), Vector3(0, -0.48, 0), blade)
			ProtoMesh.box(_sword, Vector3(0.03, 0.7, 0.03), Vector3(0, -0.48, 0), edge)
			ProtoMesh.box(_sword, Vector3(0.07, 0.07, 0.026), Vector3(0, -0.84, 0), blade, Vector3(0, 0, 45))
	match gear.get("off", ""):
		"wooden_shield":  # round wooden shield on the outside of the left forearm
			var wood := ProtoMesh.mat(Color(0.62, 0.42, 0.24))
			ProtoMesh.cylinder(_shield, 0.2, 0.035, Vector3(0, 0, 0), iron, Vector3(0, 0, 90), 12)
			ProtoMesh.cylinder(_shield, 0.17, 0.05, Vector3(-0.01, 0, 0), wood, Vector3(0, 0, 90), 12)
			ProtoMesh.sphere(_shield, 0.055, Vector3(-0.04, 0, 0), iron, Vector3(0.7, 1, 1), 8, 4)
	lantern_anchor.visible = gear.get("lantern", true)


## Sprite cell width needed for the held weapon's sweep.
static func cell_width(g: Dictionary) -> float:
	return 4.0 if g.get("main", "") == "flame_longsword" else 3.3


func set_lantern(on: bool) -> void:
	_lantern_glass.material_override = _glass_on if on else _glass_off


## walk_phase in radians; moving 0..1; attack_t seconds since swing start (< 0 = none).
## Idle: arms hanging relaxed beside the belly, fists loose.
func pose(walk_phase: float, moving: float, attack_t: float, breathe := 0.0) -> void:
	var swing := sin(walk_phase) * 0.55 * moving
	_rot("thigh_L", Vector3(swing, 0, 0))
	_rot("thigh_R", Vector3(-swing, 0, 0))
	# the trailing leg bends at the knee
	_rot("shin_L", Vector3(minf(0.0, swing) * 0.9, 0, 0))
	_rot("shin_R", Vector3(minf(0.0, -swing) * 0.9, 0, 0))
	_rot("upper_arm_L", Vector3(-swing * 0.8 - 0.05, 0, 0))
	_rot("forearm_L", Vector3(lerpf(0.12, 0.3, moving), 0, 0))
	_rot("upper_arm_R", Vector3(swing * 0.8 - 0.05, 0, 0))
	_rot("forearm_R", Vector3(lerpf(0.2, 0.3, moving), 0, 0))
	_rot("hips", Vector3(0, 0, sin(walk_phase) * 0.04 * moving))
	_rot("spine", Vector3.ZERO)
	_rot("chest", Vector3.ZERO)
	_rot("head", Vector3.ZERO)
	_hips_lift(absf(sin(walk_phase)) * 0.04 * moving + breathe)
	_sword.rotation = Vector3(SWORD_REST_TILT, 0, 0)
	_bottle.visible = false
	_bun.visible = false
	if attack_t >= 0.0:
		var t := clampf(attack_t / ATTACK_TIME, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - t, 3.0)
		# Strike: right arm sweeps the sword forward right -> left.
		_rot("upper_arm_R", Vector3(deg_to_rad(80.0), deg_to_rad(lerpf(75.0, -80.0, e)), 0.0))
		_rot("forearm_R", Vector3(0.2, 0, 0))
		_sword.rotation = Vector3(lerpf(0.5, 0.1, e), 0, 0)  # blade lines up with the arm
		_rot("hips", Vector3(0, deg_to_rad(lerpf(20.0, -15.0, e)), 0))


## Running: arms pumping opposite to the legs with the elbows bent, longer strides with the knee
## of the trailing leg folding, a forward lean with the chest turning against the hips, a bounce
## on every step. The sword is held upright (blade up) while running.
## phase in radians (one full stride = TAU, two steps).
func pose_run(phase: float) -> void:
	var step := sin(phase)
	var bob := absf(sin(phase))
	_rot("thigh_L", Vector3(step * 0.7 + 0.1, 0, 0))
	_rot("thigh_R", Vector3(-step * 0.7 + 0.1, 0, 0))
	# the leg swinging back folds at the knee, the leading one stays a little bent
	_rot("shin_L", Vector3(-0.2 - maxf(0.0, -step) * 1.2, 0, 0))
	_rot("shin_R", Vector3(-0.2 - maxf(0.0, step) * 1.2, 0, 0))
	_rot("hips", Vector3(0, step * 0.1, 0))
	_rot("spine", Vector3(-0.18, 0, 0))   # lean into the run
	_rot("chest", Vector3(-0.05, -step * 0.18, 0))
	_rot("head", Vector3(0.15, step * 0.08, 0))  # eyes ahead
	_hips_lift(bob * 0.07 - 0.03)
	# arms swing opposite to the legs, elbows bent, a little closer to the body
	var arm_l := -step * 0.65
	var arm_r := step * 0.65
	_rot("upper_arm_L", Vector3(arm_l, 0, 0.18))
	_rot("upper_arm_R", Vector3(arm_r, 0, -0.18))
	_rot("forearm_L", Vector3(1.3, 0, 0))
	_rot("forearm_R", Vector3(1.3, 0, 0))
	# blade straight up (slightly forward) whatever the arm swing: undo the arm's tilt
	_sword.rotation = Vector3(PI - (arm_r + 1.3) + 0.35, 0, 0)
	_bottle.visible = false
	_bun.visible = false


## Use motion on top of the standing pose: kind "drink" / "eat" (left hand to the mouth with a
## bottle / bread roll) or "cast" (both arms forward); frame 0/1 alternates.
func pose_action(kind: String, frame: int) -> void:
	match kind:
		"drink", "eat":
			_rot("upper_arm_L", Vector3(1.35, -0.6, 0.0))
			_rot("forearm_L", Vector3(1.5 + 0.3 * frame, 0, 0))
			_bottle.visible = kind == "drink"
			_bun.visible = kind == "eat"
			_rot("hips", Vector3(-0.05 * frame if kind == "drink" else 0.0, 0, 0))
			if kind == "eat":
				_hips_lift(0.015 * frame)
		"cast":
			_rot("upper_arm_L", Vector3(1.45 + 0.15 * frame, 0.3, 0.0))
			_rot("upper_arm_R", Vector3(1.45 + 0.15 * frame, -0.3, 0.0))
			_rot("forearm_L", Vector3(0.1, 0, 0))
			_rot("forearm_R", Vector3(0.1, 0, 0))
			_sword.rotation = Vector3(0.4, 0, 0)


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
				"drink", "eat", "cast":
					pose(0.0, 0.0, -1.0)
					pose_action(a[0], c)
				"run":
					pose(0.0, 0.0, -1.0)
					pose_run(TAU * c / a[1])
			return
		c -= a[1]
