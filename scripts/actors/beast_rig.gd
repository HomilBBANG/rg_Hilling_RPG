class_name BeastRig
extends Node3D
## Temporary models of the meadow beasts (data/monsters.json "body"): 식충식물 "plant",
## 늑대 "wolf", 고슴도치 "hedgehog". Face -Z like the other rigs. Source for their baked pixel
## sprites (columns = animation frames, rows = 8 facing directions) and their live shadow casters.

const DIRECTIONS := 8
## Sprite columns per body: [animation, frames].
const ANIMS := {
	"plant": [["idle", 4], ["spit", 3]],
	"wolf": [["idle", 1], ["run", 6], ["bite", 3], ["claw", 3]],
	"hedgehog": [["idle", 1], ["walk", 4], ["ball", 4]],
}
## Sprite cell size (m) per body.
const CELLS := {"plant": Vector2(1.7, 2.1), "wolf": Vector2(2.2, 1.9), "hedgehog": Vector2(1.3, 1.1)}

var body_type := "wolf"
var p := {}  ## named pivots of the current body


func _init(body := "wolf") -> void:
	body_type = body if ANIMS.has(body) else "wolf"
	match body_type:
		"plant":
			_build_plant()
		"hedgehog":
			_build_hedgehog()
		_:
			_build_wolf()
	pose("idle", 0.0)


static func column_count(body: String) -> int:
	var n := 0
	for a: Array in ANIMS.get(body, ANIMS["wolf"]):
		n += a[1]
	return n


static func frames_of(body: String, anim: String) -> int:
	for a: Array in ANIMS.get(body, ANIMS["wolf"]):
		if a[0] == anim:
			return a[1]
	return 1


static func column_for(body: String, anim: String, frame: int) -> int:
	var c := 0
	for a: Array in ANIMS.get(body, ANIMS["wolf"]):
		if a[0] == anim:
			return c + clampi(frame, 0, a[1] - 1)
		c += a[1]
	return 0


static func sprite_bake_spec(body: String) -> Dictionary:
	return {
		"builder": func(c: int, r: int) -> Node3D:
			var rig := BeastRig.new(body)
			rig.rotation.y = r * TAU / DIRECTIONS
			rig.pose_column(c)
			return rig,
		"cols": column_count(body),
		"rows": DIRECTIONS,
		"cell": CELLS.get(body, Vector2(2.0, 2.0)),
	}


func pose_column(col: int) -> void:
	var c := col
	for a: Array in ANIMS[body_type]:
		if c < a[1]:
			pose(a[0], float(c) / a[1] if a[0] in ["run", "walk", "ball", "idle"] else float(c))
			return
		c -= a[1]


## anim + t: looping animations take 0..1 through the cycle; attack animations take the frame
## index (0 = wind-up, 1 = strike, 2 = recover).
func pose(anim: String, t: float) -> void:
	match body_type:
		"plant":
			_pose_plant(anim, t)
		"hedgehog":
			_pose_hedgehog(anim, t)
		_:
			_pose_wolf(anim, t)


func _pivot(parent: Node3D, key: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	p[key] = n
	return n


## A cone from origin along dir (spikes, teeth, ears).
static func _spike(parent: Node3D, origin: Vector3, dir: Vector3, length: float, radius: float, m: Material) -> void:
	var piv := Node3D.new()
	piv.position = origin
	piv.basis = Basis(Quaternion(Vector3.UP, dir.normalized()))
	parent.add_child(piv)
	ProtoMesh.cylinder(piv, radius, length, Vector3(0, length * 0.5, 0), m, Vector3.ZERO, 5, 0.0)


# ---------------------------------------------------------------- 늑대

func _build_wolf() -> void:
	var fur := ProtoMesh.mat(Color(0.47, 0.48, 0.52))
	var dark := ProtoMesh.mat(Color(0.3, 0.3, 0.34))
	var light := ProtoMesh.mat(Color(0.74, 0.73, 0.72))
	var eye := ProtoMesh.mat(Color(1.0, 0.82, 0.25), 0.5, Color(1.0, 0.75, 0.2), 0.7)
	var black := ProtoMesh.mat(Color(0.06, 0.06, 0.07))
	var mouth := ProtoMesh.mat(Color(0.62, 0.2, 0.22))
	var tooth := ProtoMesh.mat(Color(0.96, 0.94, 0.88))
	var torso := _pivot(self, "torso", Vector3(0, 0.58, 0))
	ProtoMesh.sphere(torso, 0.25, Vector3(0, 0.0, 0.0), fur, Vector3(0.88, 0.86, 1.9), 10, 6)
	ProtoMesh.sphere(torso, 0.27, Vector3(0, 0.03, -0.26), fur, Vector3(0.95, 1.0, 1.0), 10, 6)
	ProtoMesh.sphere(torso, 0.2, Vector3(0, -0.06, -0.36), light, Vector3(0.9, 0.95, 0.8), 8, 5)  # chest ruff
	ProtoMesh.sphere(torso, 0.22, Vector3(0, 0.02, 0.3), fur, Vector3(0.95, 0.95, 1.0), 10, 6)
	ProtoMesh.sphere(torso, 0.2, Vector3(0, 0.12, -0.08), dark, Vector3(0.7, 0.4, 1.8), 8, 4)  # dark back
	var head := _pivot(torso, "head", Vector3(0, 0.2, -0.46))
	ProtoMesh.sphere(head, 0.17, Vector3(0, 0.0, 0.0), fur, Vector3(1.0, 0.92, 1.05), 10, 6)
	ProtoMesh.sphere(head, 0.12, Vector3(0, -0.06, 0.02), light, Vector3(1.2, 0.8, 1.0), 8, 4)  # cheeks
	ProtoMesh.cylinder(head, 0.075, 0.24, Vector3(0, -0.02, -0.2), fur, Vector3(90, 0, 0), 8, 0.055)
	ProtoMesh.sphere(head, 0.04, Vector3(0, 0.0, -0.33), black)
	var jaw := _pivot(head, "jaw", Vector3(0, -0.07, -0.08))
	ProtoMesh.cylinder(jaw, 0.06, 0.2, Vector3(0, -0.0, -0.12), light, Vector3(90, 0, 0), 6, 0.045)
	ProtoMesh.sphere(jaw, 0.05, Vector3(0, 0.03, -0.12), mouth, Vector3(1.0, 0.5, 2.2), 6, 3)
	for side in [-1.0, 1.0]:
		_spike(head, Vector3(0.09 * side, 0.12, 0.02), Vector3(0.35 * side, 1.0, 0.15), 0.15, 0.06, dark)
		var e := ProtoMesh.sphere(head, 0.032, Vector3(0.08 * side, 0.05, -0.13), eye, Vector3(1.0, 0.8, 0.6), 6, 3)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spike(head, Vector3(0.035 * side, -0.06, -0.26), Vector3(0, -1, -0.2), 0.05, 0.015, tooth)
	for spec in [["fl", -0.13, -0.3], ["fr", 0.13, -0.3], ["bl", -0.13, 0.3], ["br", 0.13, 0.3]]:
		var leg := _pivot(torso, spec[0], Vector3(spec[1], -0.06, spec[2]))
		ProtoMesh.cylinder(leg, 0.065, 0.3, Vector3(0, -0.13, 0), fur, Vector3.ZERO, 6, 0.05)
		var low := _pivot(leg, spec[0] + "2", Vector3(0, -0.28, 0))
		ProtoMesh.cylinder(low, 0.045, 0.24, Vector3(0, -0.11, 0), dark, Vector3.ZERO, 6)
		ProtoMesh.sphere(low, 0.06, Vector3(0, -0.22, -0.03), dark, Vector3(1.0, 0.6, 1.3), 6, 3)
	var tail := _pivot(torso, "tail", Vector3(0, 0.1, 0.46))
	ProtoMesh.sphere(tail, 0.09, Vector3(0, -0.02, 0.2), fur, Vector3(0.9, 0.9, 2.6), 8, 4)
	ProtoMesh.sphere(tail, 0.06, Vector3(0, -0.04, 0.42), light, Vector3(1.0, 1.0, 1.6), 6, 3)


func _wolf_legs(fl: float, fr: float, bl: float, br: float, bend := 0.0) -> void:
	for spec in [["fl", fl], ["fr", fr], ["bl", bl], ["br", br]]:
		(p[spec[0]] as Node3D).rotation = Vector3(spec[1], 0, 0)
		(p[spec[0] + "2"] as Node3D).rotation = Vector3(-absf(spec[1]) * 0.6 - bend if spec[0].begins_with("f") else absf(spec[1]) * 0.6 + bend, 0, 0)


func _pose_wolf(anim: String, t: float) -> void:
	var torso: Node3D = p["torso"]
	var head: Node3D = p["head"]
	var jaw: Node3D = p["jaw"]
	var tail: Node3D = p["tail"]
	torso.position = Vector3(0, 0.58, 0)
	torso.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	head.position = Vector3(0, 0.2, -0.46)
	jaw.rotation = Vector3.ZERO
	tail.rotation = Vector3(-0.35, 0, 0)
	match anim:
		"run":
			var ph := t * TAU
			var s := sin(ph)
			_wolf_legs(s * 0.75, sin(ph + 0.5) * 0.75, -sin(ph + 0.4) * 0.7, -sin(ph + 0.9) * 0.7)
			torso.position.y = 0.58 + absf(cos(ph)) * 0.05
			torso.rotation.x = s * 0.08
			head.rotation.x = -s * 0.1 - 0.1
			tail.rotation = Vector3(-0.1 + s * 0.15, sin(ph * 0.5) * 0.2, 0)
		"bite":
			match int(t):
				0:  # crouch, head pulled back, teeth bared
					_wolf_legs(-0.25, -0.25, 0.35, 0.35, 0.35)
					torso.position = Vector3(0, 0.48, 0.12)
					torso.rotation.x = 0.12
					head.rotation.x = 0.25
					jaw.rotation.x = 0.25
				1:  # lunge, jaws wide
					_wolf_legs(0.9, 0.8, -0.7, -0.75)
					torso.position = Vector3(0, 0.6, -0.22)
					torso.rotation.x = -0.1
					head.rotation.x = -0.2
					head.position.z = -0.52
					jaw.rotation.x = 0.75
				_:
					_wolf_legs(0.3, 0.25, -0.2, -0.2)
					torso.position = Vector3(0, 0.56, -0.08)
					jaw.rotation.x = 0.3
			tail.rotation = Vector3(0.1, 0, 0)
		"claw":
			match int(t):
				0:  # rear up, right paw raised
					_wolf_legs(0.2, 1.4, -0.45, -0.45, 0.2)
					torso.rotation.x = 0.45
					torso.position = Vector3(0, 0.66, 0.1)
					head.rotation.x = -0.35
					jaw.rotation.x = 0.35
				1:  # swipe down across
					_wolf_legs(0.4, 0.5, -0.2, -0.25)
					(p["fr"] as Node3D).rotation = Vector3(0.9, 0, -0.9)
					torso.rotation = Vector3(-0.12, 0.25, 0)
					torso.position = Vector3(0, 0.55, -0.15)
					head.rotation.x = -0.1
					jaw.rotation.x = 0.5
				_:
					_wolf_legs(0.15, 0.3, -0.1, -0.1)
					torso.position = Vector3(0, 0.57, -0.05)
		_:  # idle: standing, head up, tail low
			_wolf_legs(0.05, -0.05, -0.05, 0.05)
			head.rotation.x = -0.12
			tail.rotation = Vector3(-0.6, 0, 0)


# ---------------------------------------------------------------- 고슴도치

func _build_hedgehog() -> void:
	var skin := ProtoMesh.mat(Color(0.62, 0.48, 0.36))
	var face := ProtoMesh.mat(Color(0.86, 0.74, 0.6))
	var spine := ProtoMesh.mat(Color(0.34, 0.25, 0.18))
	var tip := ProtoMesh.mat(Color(0.9, 0.86, 0.76))
	var black := ProtoMesh.mat(Color(0.05, 0.04, 0.05))
	var feet := ProtoMesh.mat(Color(0.5, 0.36, 0.28))
	var body := _pivot(self, "body", Vector3(0, 0.24, 0))
	ProtoMesh.sphere(body, 0.27, Vector3.ZERO, skin, Vector3(1.0, 0.82, 1.22), 10, 6)
	var head := _pivot(body, "head", Vector3(0, -0.04, -0.28))
	ProtoMesh.sphere(head, 0.13, Vector3(0, 0, 0), face, Vector3(1.0, 0.9, 1.0), 8, 5)
	ProtoMesh.cylinder(head, 0.075, 0.14, Vector3(0, -0.03, -0.13), face, Vector3(90, 0, 0), 7, 0.03)
	ProtoMesh.sphere(head, 0.035, Vector3(0, -0.03, -0.21), black)
	for side in [-1.0, 1.0]:
		ProtoMesh.sphere(head, 0.03, Vector3(0.07 * side, 0.04, -0.08), black)
		ProtoMesh.sphere(head, 0.04, Vector3(0.09 * side, 0.1, 0.02), face, Vector3(1.0, 1.0, 0.5), 6, 3)
	for spec in [["fl", -0.13, -0.16], ["fr", 0.13, -0.16], ["bl", -0.13, 0.16], ["br", 0.13, 0.16]]:
		var leg := _pivot(body, spec[0], Vector3(spec[1], -0.12, spec[2]))
		ProtoMesh.sphere(leg, 0.06, Vector3(0, -0.07, -0.02), feet, Vector3(1.0, 0.7, 1.3), 6, 3)
	# spines on the back (walking) and all round (curled into a ball)
	var back := _pivot(body, "spines", Vector3.ZERO)
	var ball := _pivot(self, "ball", Vector3(0, 0.3, 0))
	ProtoMesh.sphere(ball, 0.25, Vector3.ZERO, spine, Vector3.ONE, 10, 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var golden := PI * (3.0 - sqrt(5.0))
	var n := 70
	for i in n:
		var y := 1.0 - 2.0 * (i + 0.5) / n
		var r := sqrt(1.0 - y * y)
		var d := Vector3(cos(golden * i) * r, y, sin(golden * i) * r)
		var m: Material = tip if i % 4 == 0 else spine
		_spike(ball, d * 0.22, d + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)), 0.2, 0.035, m)
		if d.y > -0.15 and d.z > -0.45:  # back half only
			var at := Vector3(d.x * 0.25, d.y * 0.2, d.z * 0.3)
			_spike(back, at, d + Vector3(0, 0.15, 0.55), 0.17, 0.03, m)


func _pose_hedgehog(anim: String, t: float) -> void:
	var body: Node3D = p["body"]
	var ball: Node3D = p["ball"]
	var curled := anim == "ball"
	body.visible = not curled
	ball.visible = curled
	body.position = Vector3(0, 0.24, 0)
	body.rotation = Vector3.ZERO
	(p["head"] as Node3D).rotation = Vector3.ZERO
	for k in ["fl", "fr", "bl", "br"]:
		(p[k] as Node3D).rotation = Vector3.ZERO
	match anim:
		"walk":
			var ph := t * TAU
			(p["fl"] as Node3D).rotation.x = sin(ph) * 0.8
			(p["br"] as Node3D).rotation.x = sin(ph) * 0.8
			(p["fr"] as Node3D).rotation.x = -sin(ph) * 0.8
			(p["bl"] as Node3D).rotation.x = -sin(ph) * 0.8
			body.position.y = 0.24 + absf(sin(ph)) * 0.025
			body.rotation.z = sin(ph) * 0.05
			(p["head"] as Node3D).rotation.x = sin(ph * 2.0) * 0.06
		"ball":
			ball.rotation = Vector3(-t * TAU * 0.25, 0, 0)  # 4 frames = a quarter turn; spines repeat
		_:
			(p["head"] as Node3D).rotation.x = 0.1  # sniffing the ground


# ---------------------------------------------------------------- 식충식물

func _build_plant() -> void:
	var leaf := ProtoMesh.mat(Color(0.32, 0.56, 0.24))
	var leaf_dark := ProtoMesh.mat(Color(0.2, 0.4, 0.18))
	var stem := ProtoMesh.mat(Color(0.26, 0.46, 0.2))
	var outer := ProtoMesh.mat(Color(0.42, 0.62, 0.22))
	var inner := ProtoMesh.mat(Color(0.86, 0.32, 0.36))
	var tooth := ProtoMesh.mat(Color(0.95, 0.92, 0.72))
	var spot := ProtoMesh.mat(Color(0.86, 0.78, 0.25))
	var root := _pivot(self, "root", Vector3.ZERO)
	for i in 6:  # leaves fanned out round the base
		var lp := Node3D.new()
		lp.rotation.y = TAU * i / 6.0 + 0.3
		root.add_child(lp)
		ProtoMesh.sphere(lp, 0.22, Vector3(0, 0.06, 0.28), leaf if i % 2 == 0 else leaf_dark, Vector3(0.55, 0.2, 1.4), 8, 4)
	var s1 := _pivot(root, "stem1", Vector3(0, 0.08, 0))
	ProtoMesh.capsule(s1, 0.07, 0.48, Vector3(0, 0.22, 0), stem)
	var s2 := _pivot(s1, "stem2", Vector3(0, 0.42, 0))
	ProtoMesh.capsule(s2, 0.06, 0.42, Vector3(0, 0.19, 0), stem)
	var head := _pivot(s2, "head", Vector3(0, 0.4, 0))
	ProtoMesh.sphere(head, 0.12, Vector3(0, 0, 0.06), outer, Vector3(1.0, 1.0, 1.0), 8, 5)
	for key in ["jaw_top", "jaw_bot"]:
		var top: bool = key == "jaw_top"
		var j := _pivot(head, key, Vector3(0, 0.02 if top else -0.02, 0.1))
		var sy := 1.0 if top else -1.0
		ProtoMesh.sphere(j, 0.26, Vector3(0, 0.05 * sy, -0.24), outer, Vector3(0.95, 0.38, 1.05), 10, 5)
		ProtoMesh.sphere(j, 0.22, Vector3(0, 0.0, -0.24), inner, Vector3(0.88, 0.22, 0.95), 10, 4)
		for k in 7:
			var a2 := deg_to_rad(-75.0 + 150.0 * k / 6.0)
			var rim := Vector3(sin(a2) * 0.24, 0.0, -0.24 - cos(a2) * 0.25)
			_spike(j, rim, Vector3(sin(a2) * 0.3, -sy, -cos(a2) * 0.3), 0.09, 0.022, tooth)
		if top:
			for sp in [Vector3(-0.1, 0.13, -0.3), Vector3(0.09, 0.14, -0.2), Vector3(0.02, 0.15, -0.38)]:
				ProtoMesh.sphere(j, 0.035, sp, spot, Vector3(1.0, 0.5, 1.0), 6, 3)
	_pivot(head, "mouth", Vector3(0, 0, -0.3))


func _pose_plant(anim: String, t: float) -> void:
	var s1: Node3D = p["stem1"]
	var s2: Node3D = p["stem2"]
	var head: Node3D = p["head"]
	var open := 0.3
	s1.rotation = Vector3.ZERO
	s2.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	head.scale = Vector3.ONE
	match anim:
		"spit":
			match int(t):
				0:  # rear back, cheeks puffed, jaws shut
					s1.rotation.x = 0.3
					s2.rotation.x = 0.25
					head.rotation.x = -0.45
					head.scale = Vector3(1.12, 1.12, 1.0)
					open = 0.04
				1:  # snap forward, jaws wide
					s1.rotation.x = -0.25
					s2.rotation.x = -0.3
					head.rotation.x = 0.25
					open = 0.85
				_:
					s1.rotation.x = -0.08
					s2.rotation.x = -0.05
					open = 0.4
		_:  # idle sway, jaws breathing
			var ph := t * TAU
			s1.rotation.z = sin(ph) * 0.07
			s2.rotation.z = sin(ph + 0.8) * 0.08
			s2.rotation.x = cos(ph) * 0.05
			open = 0.28 + sin(ph) * 0.08
	(p["jaw_top"] as Node3D).rotation.x = open
	(p["jaw_bot"] as Node3D).rotation.x = -open * 0.55


## Where the plant's mouth is (spit start), world space.
func mouth_position() -> Vector3:
	return (p["mouth"] as Node3D).global_position if p.has("mouth") else global_position + Vector3(0, 1.0, 0)
