class_name WindDrift
extends Node
## Pushes a GPUParticles3D's particles with the shared wind (gravity = base + wind * gain) and
## hides them when the wind is off. Optionally keeps the emitter upwind of a followed node.

var material: ParticleProcessMaterial
var base_gravity := Vector3.ZERO
var gain := 1.0
var follow: Node3D
var follow_offset := Vector3.ZERO


static func make(pm: ParticleProcessMaterial, base: Vector3, k: float) -> WindDrift:
	var d := WindDrift.new()
	d.material = pm
	d.base_gravity = base
	d.gain = k
	return d


func _process(_delta: float) -> void:
	var p := get_parent() as GPUParticles3D
	if p == null or material == null:
		return
	if follow and is_instance_valid(follow):
		p.global_position = follow.global_position + follow_offset
	var w := Wind.vec3_at(p.global_position)
	material.gravity = base_gravity + w * gain
	if follow:  # blowing leaves only exist while there is wind
		p.emitting = StylizedMaterials.wind > 0.5
