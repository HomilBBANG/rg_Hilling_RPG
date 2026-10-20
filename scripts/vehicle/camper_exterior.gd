class_name CamperExterior
extends Node3D
## Modern Class-C motorhome placeholder built from primitives. Front faces local +X.
## Has headlights (spot), marker/porch light; toggled via Game.camper_lights_on.

const LENGTH := 7.2
const WIDTH := 2.4
## Local position of the entry door (on the +Z side, i.e. the side facing the camera).
const DOOR_LOCAL := Vector3(-1.2, 0.0, 1.25)

var lights: PrototypeCamperLights


func _ready() -> void:
	_build()
	ProtoMesh.static_box_collider(self, Vector3(LENGTH, 6.0, WIDTH), Vector3(0, 2.0, 0))
	lights = PrototypeCamperLights.new()
	lights.name = "Lights"
	add_child(lights)
	lights.build(self)


func door_world_position() -> Vector3:
	return to_global(DOOR_LOCAL + Vector3(0, 0, 0.9))


func _build() -> void:
	var white := ProtoMesh.mat(Color(0.93, 0.93, 0.9), 0.5)
	var cream := ProtoMesh.mat(Color(0.86, 0.85, 0.8), 0.6)
	var trim := ProtoMesh.mat(Color(0.25, 0.27, 0.3), 0.6)
	var glass := ProtoMesh.mat(Color(0.12, 0.2, 0.3), 0.15)
	var stripe_a := ProtoMesh.mat(Color(0.12, 0.55, 0.62), 0.5)
	var stripe_b := ProtoMesh.mat(Color(0.95, 0.55, 0.18), 0.5)
	var tire := ProtoMesh.mat(Color(0.08, 0.08, 0.09), 0.95)
	var hub := ProtoMesh.mat(Color(0.7, 0.72, 0.75), 0.3)
	var solar := ProtoMesh.mat(Color(0.12, 0.17, 0.35), 0.2)
	var awning := ProtoMesh.mat(Color(0.5, 0.53, 0.56), 0.6)

	# Living box + alcove over the cab + cab + hood
	ProtoMesh.box(self, Vector3(5.5, 2.5, WIDTH), Vector3(-0.85, 1.85, 0), white)
	ProtoMesh.box(self, Vector3(1.3, 0.85, WIDTH - 0.04), Vector3(2.5, 2.62, 0), white)
	ProtoMesh.box(self, Vector3(0.5, 0.55, WIDTH - 0.1), Vector3(3.02, 2.55, 0), white, Vector3(0, 0, -25))
	ProtoMesh.box(self, Vector3(1.4, 1.45, WIDTH - 0.1), Vector3(2.55, 1.32, 0), cream)
	ProtoMesh.box(self, Vector3(0.65, 0.75, WIDTH - 0.14), Vector3(3.3, 0.95, 0), cream)
	# Windshield (slanted)
	ProtoMesh.box(self, Vector3(0.08, 0.85, WIDTH - 0.3), Vector3(3.12, 1.62, 0), glass, Vector3(0, 0, -28))
	# Bumpers / skirt
	ProtoMesh.box(self, Vector3(0.2, 0.3, WIDTH), Vector3(3.62, 0.62, 0), trim)
	ProtoMesh.box(self, Vector3(0.15, 0.3, WIDTH), Vector3(-3.62, 0.62, 0), trim)
	ProtoMesh.box(self, Vector3(6.9, 0.22, WIDTH + 0.02), Vector3(-0.1, 0.62, 0), trim)
	# Grille
	ProtoMesh.box(self, Vector3(0.04, 0.3, 1.0), Vector3(3.64, 0.98, 0), trim)

	for side in [-1.0, 1.0]:
		var z: float = side * (WIDTH * 0.5 + 0.005)
		# Side stripes (modern RV livery)
		ProtoMesh.box(self, Vector3(5.4, 0.12, 0.02), Vector3(-0.85, 1.05, z), stripe_a)
		ProtoMesh.box(self, Vector3(4.2, 0.06, 0.02), Vector3(-1.45, 1.2, z), stripe_b)
		ProtoMesh.box(self, Vector3(1.25, 0.08, 0.02), Vector3(2.5, 2.3, z), stripe_a)
		# Living windows
		ProtoMesh.box(self, Vector3(1.0, 0.55, 0.03), Vector3(-2.6, 2.15, z), glass)
		ProtoMesh.box(self, Vector3(1.2, 0.55, 0.03), Vector3(0.6, 2.15, z), glass)
		# Cab side window
		ProtoMesh.box(self, Vector3(0.7, 0.55, 0.03), Vector3(2.65, 1.65, z), glass)
		# Mirrors
		ProtoMesh.box(self, Vector3(0.1, 0.28, 0.12), Vector3(3.0, 1.72, side * (WIDTH * 0.5 + 0.18)), trim)
		# Wheels: front + tandem rear
		for wx in [2.55, -1.75, -2.55]:
			ProtoMesh.cylinder(self, 0.42, 0.3, Vector3(wx, 0.42, side * (WIDTH * 0.5 - 0.12)), tire, Vector3(90, 0, 0), 10)
			ProtoMesh.cylinder(self, 0.2, 0.32, Vector3(wx, 0.42, side * (WIDTH * 0.5 - 0.12)), hub, Vector3(90, 0, 0), 8)

	# Entry door (+Z side, facing the camera) with window, handle and step
	var dz := WIDTH * 0.5 + 0.015
	ProtoMesh.box(self, Vector3(0.78, 1.85, 0.03), Vector3(DOOR_LOCAL.x, 1.62, dz), cream)
	ProtoMesh.box(self, Vector3(0.4, 0.4, 0.03), Vector3(DOOR_LOCAL.x, 2.15, dz + 0.01), glass)
	ProtoMesh.box(self, Vector3(0.12, 0.05, 0.05), Vector3(DOOR_LOCAL.x + 0.25, 1.55, dz + 0.02), trim)
	ProtoMesh.box(self, Vector3(0.8, 0.08, 0.4), Vector3(DOOR_LOCAL.x, 0.4, dz + 0.2), trim)

	# Rear: window, ladder
	ProtoMesh.box(self, Vector3(0.03, 0.5, 1.0), Vector3(-3.61, 2.2, 0), glass)
	for i in 6:
		ProtoMesh.box(self, Vector3(0.04, 0.04, 0.42), Vector3(-3.66, 1.0 + i * 0.4, -0.6), trim)
	for lz in [-0.8, -0.4]:
		ProtoMesh.box(self, Vector3(0.04, 2.3, 0.04), Vector3(-3.66, 2.05, lz), trim)

	# Roof: AC unit, solar panels, skylight
	ProtoMesh.box(self, Vector3(0.9, 0.3, 0.8), Vector3(-0.2, 3.25, 0), cream)
	ProtoMesh.box(self, Vector3(1.4, 0.05, 0.9), Vector3(-2.3, 3.13, -0.45), solar)
	ProtoMesh.box(self, Vector3(1.4, 0.05, 0.9), Vector3(-2.3, 3.13, 0.5), solar)
	ProtoMesh.box(self, Vector3(0.6, 0.12, 0.6), Vector3(1.2, 3.15, 0.3), glass)

	# Rolled awning along the door side
	ProtoMesh.cylinder(self, 0.1, 4.6, Vector3(-1.0, 2.9, WIDTH * 0.5 + 0.12), awning, Vector3(0, 0, 90), 8)
