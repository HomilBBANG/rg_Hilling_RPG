class_name NpcRig
extends Node3D
## Villager model in the protagonist's chibi proportions (big round head, round body, short legs),
## flat colours, brows instead of eyes. Looks are data (LOOKS); source for the NPC's baked sprite.

const ANIMS := [["idle", 2], ["walk", 8]]
const DIRECTIONS := 8
const HIP := 0.42

const LOOKS := {
	# 로사 (general store): auburn hair in a bun, green shirt, cream apron
	"rosa": {"skin": Color(0.96, 0.72, 0.56), "hair": Color(0.62, 0.28, 0.16), "style": "bun",
		"shirt": Color(0.32, 0.58, 0.42), "apron": Color(0.94, 0.88, 0.74), "pants": Color(0.42, 0.3, 0.22),
		"boots": Color(0.38, 0.24, 0.14), "beard": false},
	# 브론 (blacksmith): short dark hair, full beard, grey shirt, leather apron
	"bron": {"skin": Color(0.84, 0.6, 0.44), "hair": Color(0.22, 0.16, 0.12), "style": "short",
		"shirt": Color(0.42, 0.44, 0.5), "apron": Color(0.5, 0.32, 0.18), "pants": Color(0.26, 0.24, 0.24),
		"boots": Color(0.2, 0.15, 0.12), "beard": true},
	# 왕 (demo dialogue speaker, dialogue portrait only for now): grey hair and beard, gold crown,
	# royal red shirt, purple robe front
	"king": {"skin": Color(0.94, 0.74, 0.6), "hair": Color(0.82, 0.8, 0.78), "style": "crown",
		"shirt": Color(0.66, 0.16, 0.18), "apron": Color(0.42, 0.24, 0.56), "pants": Color(0.3, 0.2, 0.32),
		"boots": Color(0.24, 0.16, 0.12), "beard": true},
}

var hips: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []


func _init(look_id := "rosa") -> void:
	var look: Dictionary = LOOKS[look_id]
	var skin := ProtoMesh.mat(look["skin"])
	var hair := ProtoMesh.mat(look["hair"])
	var shirt := ProtoMesh.mat(look["shirt"])
	var apron := ProtoMesh.mat(look["apron"])
	var pants := ProtoMesh.mat(look["pants"])
	var boots := ProtoMesh.mat(look["boots"])
	hips = Node3D.new()
	hips.position.y = HIP
	add_child(hips)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.13 * side, 0, 0)
		hips.add_child(leg)
		ProtoMesh.sphere(leg, 0.14, Vector3(0, -0.12, 0), pants, Vector3(1.0, 1.2, 1.0), 10, 6)
		ProtoMesh.sphere(leg, 0.125, Vector3(0, -0.33, -0.04), boots, Vector3(1.0, 0.75, 1.3), 10, 6)
		_legs.append(leg)
	# body, apron front, collar
	ProtoMesh.sphere(hips, 0.34, Vector3(0, 0.38, 0), shirt, Vector3(1.0, 1.08, 0.95), 12, 8)
	ProtoMesh.sphere(hips, 0.26, Vector3(0, 0.3, -0.2), apron, Vector3(1.05, 1.35, 0.5), 12, 8)
	ProtoMesh.box(hips, Vector3(0.36, 0.035, 0.05), Vector3(0, 0.62, -0.25), apron)
	# head, nose, ears, brows
	ProtoMesh.cylinder(hips, 0.11, 0.08, Vector3(0, 0.74, 0), skin, Vector3.ZERO, 8)
	ProtoMesh.sphere(hips, 0.29, Vector3(0, 0.99, 0), skin, Vector3(1.0, 0.97, 0.95), 12, 8)
	ProtoMesh.sphere(hips, 0.06, Vector3(0, 0.95, -0.3), ProtoMesh.mat(Color(look["skin"]).darkened(0.12)), Vector3(1, 0.9, 1.2), 8, 5)
	for side in [-1.0, 1.0]:
		ProtoMesh.sphere(hips, 0.07, Vector3(side * 0.28, 0.97, 0.02), skin, Vector3(0.55, 1.0, 0.85), 6, 4)
		var brow := ProtoMesh.box(hips, Vector3(0.1, 0.035, 0.03), Vector3(side * 0.1, 1.04, -0.27), hair)
		brow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# hair cap (+ bun) and optional beard
	ProtoMesh.sphere(hips, 0.3, Vector3(0, 1.06, 0.03), hair, Vector3(1.04, 0.78, 1.0), 12, 8)
	if look["style"] == "bun":
		ProtoMesh.sphere(hips, 0.13, Vector3(0, 1.2, 0.22), hair, Vector3.ONE, 8, 5)
	elif look["style"] == "crown":
		var gold := ProtoMesh.mat(Color(0.95, 0.76, 0.26), 0.4)
		ProtoMesh.cylinder(hips, 0.2, 0.1, Vector3(0, 1.25, 0.02), gold, Vector3.ZERO, 10)
		for i in 5:
			var a := TAU * i / 5.0
			ProtoMesh.cylinder(hips, 0.045, 0.1, Vector3(sin(a) * 0.17, 1.34, 0.02 + cos(a) * 0.17), gold, Vector3.ZERO, 4, 0.0)
	if look["beard"]:
		ProtoMesh.sphere(hips, 0.2, Vector3(0, 0.83, -0.18), hair, Vector3(1.15, 0.9, 0.7), 10, 6)
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.38 * side, 0.58, 0)
		hips.add_child(arm)
		ProtoMesh.sphere(arm, 0.13, Vector3(0, -0.06, 0), shirt, Vector3(1.0, 1.3, 1.0), 10, 6)
		ProtoMesh.capsule(arm, 0.09, 0.22, Vector3(0, -0.28, 0), skin)
		ProtoMesh.sphere(arm, 0.1, Vector3(0, -0.42, 0), skin)
		_arms.append(arm)
	pose(0.0, 0.0)


static func column_count() -> int:
	return 10


static func column_for(anim: String, frame: int) -> int:
	return clampi(frame, 0, 1) if anim == "idle" else 2 + posmod(frame, 8)


static func direction_index(yaw: float) -> int:
	return posmod(roundi(yaw / (TAU / DIRECTIONS)), DIRECTIONS)


func pose(walk_phase: float, moving: float, breathe := 0.0) -> void:
	var swing := sin(walk_phase) * 0.55 * moving
	_legs[0].rotation = Vector3(swing, 0, 0)
	_legs[1].rotation = Vector3(-swing, 0, 0)
	_arms[0].rotation = Vector3(-swing * 0.8, 0, deg_to_rad(-10.0))
	_arms[1].rotation = Vector3(swing * 0.8, 0, deg_to_rad(10.0))
	hips.position.y = HIP + absf(sin(walk_phase)) * 0.04 * moving + breathe


func pose_column(col: int) -> void:
	if col < 2:
		pose(0.0, 0.0, 0.012 * col)
	else:
		pose(TAU * (col - 2) / 8.0, 1.0)
