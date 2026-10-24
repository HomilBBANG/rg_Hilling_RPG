class_name DayNightController
extends Node
## Drives sun/moon light, ambient light and background from Game.daylight().
## Exterior: full sun/moon cycle. Interior: only ambient + window glow change.
## All values are tuning placeholders for the P0 comparison.

@export var interior := false
## Underground (fixed dungeon): no sun or sky, dim cool ambient - torches and lanterns do the rest.
var cave := false
var cave_ambient := Color(0.22, 0.21, 0.3)  ## lit halls (throne room) override the dark cave light
var cave_ambient_energy := 0.55

var sun: DirectionalLight3D
var environment: Environment
## Materials that glow as "daylight through windows" (interior).
var window_materials: Array[StandardMaterial3D] = []

const SUN_DAY := Color(1.0, 0.9, 0.74)
const SUN_TWILIGHT := Color(1.0, 0.62, 0.38)
const MOON := Color(0.6, 0.7, 1.0)
const AMBIENT_DAY := Color(0.6, 0.7, 0.88)
const AMBIENT_NIGHT := Color(0.24, 0.3, 0.5)
const BG_DAY := Color(0.55, 0.68, 0.5)
## Haze colour for the tilted diorama camera (depth fog).
const HAZE_DAY := Color(0.78, 0.86, 0.95)
const HAZE_NIGHT := Color(0.1, 0.13, 0.22)

## Camera-style dependent extras (set by bootstrap through the world).
var style_ssao := true
var style_fog := false
var style_grade := true
var camera_distance := 40.0
## "soft" (B/C) or "deadcells" (D): warm low key light + violet ambient, stronger bloom.
var palette := "soft"

const DC_SUN_DAY := Color(1.0, 0.96, 0.88)  # near-white daylight like the reference (was a warm orange key)
const DC_AMBIENT_DAY := Color(0.42, 0.55, 0.88)  # cooler, lighter shade (reference: clear blue shadows)
const DC_AMBIENT_NIGHT := Color(0.18, 0.2, 0.58)
const DC_MOON := Color(0.5, 0.58, 1.0)
## Background / haze follow the sea around the regions (clear turquoise by day, deep blue at night).
const DC_BG_DAY := Color(0.13, 0.5, 0.7)
const DC_HAZE_DAY := Color(0.74, 0.9, 0.96)
const DC_HAZE_NIGHT := Color(0.06, 0.1, 0.24)
const BG_NIGHT := Color(0.04, 0.05, 0.09)


static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.5
	env.ssao_radius = 0.6
	env.ssao_intensity = 0.5
	env.ssao_power = 1.0
	env.ssao_detail = 0.5
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_sky_affect = 0.0
	env.fog_depth_curve = 1.6
	env.adjustment_enabled = true
	return env


func set_style(ssao: bool, fog: bool, grade: bool, cam_distance: float) -> void:
	style_ssao = ssao
	style_fog = fog
	style_grade = grade
	camera_distance = cam_distance


func _process(_delta: float) -> void:
	apply(Game.daylight(), Game.twilight())


func apply(d: float, tw: float) -> void:
	if cave:
		if environment:
			environment.ambient_light_color = cave_ambient
			environment.ambient_light_energy = cave_ambient_energy
			environment.background_color = Color(0.01, 0.01, 0.015)
			environment.fog_enabled = false
			environment.ssao_enabled = style_ssao
			environment.glow_intensity = 0.4
			environment.glow_hdr_threshold = 1.1
		if sun:
			sun.visible = false
		return
	if environment:
		if interior:
			# soft, warm (user request: 은은한 주황색) — a little brighter and warmer in the morning sun
			var mo := Game.morning()
			# Dim, cool ambient (reference: deep shade between pools of warm light); the key light
			# and the lamps carry the room, so the shadow sides stay dark.
			environment.ambient_light_color = Color(0.34, 0.36, 0.48).lerp(Color(0.46, 0.44, 0.48), d).lerp(Color(0.76, 0.74, 0.66), mo * 0.6)
			environment.ambient_light_energy = lerpf(0.08, 0.1, d) + mo * 0.03
			environment.background_color = Color(0.02, 0.02, 0.03)
		elif palette == "deadcells":
			environment.ambient_light_color = DC_AMBIENT_NIGHT.lerp(DC_AMBIENT_DAY, d)
			environment.ambient_light_energy = lerpf(0.5, 0.78, d)
			environment.background_color = BG_NIGHT.lerp(DC_BG_DAY, d)
			environment.fog_enabled = style_fog
			environment.fog_light_color = DC_HAZE_NIGHT.lerp(DC_HAZE_DAY, d)
			environment.fog_light_energy = 1.0
			environment.fog_density = 0.4
			environment.fog_depth_begin = camera_distance - 3.0
			environment.fog_depth_end = camera_distance + 22.0
		else:
			environment.ambient_light_color = AMBIENT_NIGHT.lerp(AMBIENT_DAY, d)
			environment.ambient_light_energy = lerpf(0.42, 0.5 if style_grade else 0.45, d)
			environment.background_color = BG_NIGHT.lerp(BG_DAY, d)
			environment.fog_enabled = style_fog
			environment.fog_light_color = HAZE_NIGHT.lerp(HAZE_DAY, d)
			environment.fog_light_energy = 1.0
			environment.fog_density = 0.55
			environment.fog_depth_begin = camera_distance - 2.0
			environment.fog_depth_end = camera_distance + 26.0
		environment.ssao_enabled = style_ssao
		var dc := palette == "deadcells" and not interior
		environment.glow_intensity = 0.45 if dc else 0.25
		environment.glow_hdr_threshold = 1.05 if dc else 1.5
		environment.glow_bloom = 0.0
		environment.adjustment_saturation = (1.1 if interior else 1.04) if style_grade else 1.0
		environment.adjustment_contrast = (1.14 if interior else 1.06) if style_grade else 1.0
		if interior:  # lamp strips bloom a little
			environment.glow_intensity = 0.3
			environment.glow_hdr_threshold = 1.15
	if sun:
		var dc := palette == "deadcells"
		var col := (DC_MOON if dc else MOON).lerp(DC_SUN_DAY if dc else SUN_DAY, d)
		col = col.lerp(SUN_TWILIGHT, tw * 0.7)
		sun.light_color = col
		sun.light_energy = lerpf(0.38 if dc else 0.3, 1.05 if dc else 1.0, d)
		# Sun from the south-east by day (lower and longer shadows for D), moon from the south-west.
		var day_rot := Vector3(deg_to_rad(-34.0 if dc else -52.0), deg_to_rad(-48.0 if dc else -35.0), 0.0)
		var night_rot := Vector3(deg_to_rad(-62.0), deg_to_rad(28.0), 0.0)
		sun.rotation = night_rot.lerp(day_rot, d)
	var mo := Game.morning()
	for m in window_materials:
		m.emission_energy_multiplier = lerpf(0.05, 1.1, d) + mo * 0.7
		m.emission = Color(0.25, 0.3, 0.5).lerp(Color(0.85, 0.9, 0.95), d).lerp(Color(1.0, 0.95, 0.8), mo)
