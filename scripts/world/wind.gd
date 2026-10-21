class_name Wind
extends RefCounted
## GDScript copy of shaders/wind.gdshaderinc so scripted motion (campfire flame, smoke, embers,
## laundry, flags, blowing leaves) follows the same gusts as the grass and trees.
## Shader TIME counts from engine start and rolls over every hour; this uses the same clock.

const DIR := Vector2(0.94, 0.34)


static func time() -> float:
	return fmod(Time.get_ticks_msec() / 1000.0, 3600.0)


## Horizontal wind offset (x, z) at world position p, roughly 0..1.3 along DIR. 0 when wind is off.
static func offset(p: Vector3, t := -1.0) -> Vector2:
	if t < 0.0:
		t = time()
	var along := p.x * DIR.x + p.z * DIR.y
	var wave := sin(along * 0.16 - t * 1.05)
	var gust := 0.55 + 0.45 * wave * (0.55 + 0.45 * sin(along * 0.05 - t * 0.27))
	var flutter := 0.2 * sin(t * 1.5 + p.x * 0.6 + p.z * 0.45)
	return DIR * (gust + flutter) * StylizedMaterials.wind


static func vec3_at(p: Vector3) -> Vector3:
	var w := offset(p)
	return Vector3(w.x, 0.0, w.y)
