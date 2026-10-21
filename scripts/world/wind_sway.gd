class_name WindSway
extends Node3D
## Pivot that moves its children with the shared wind.
##   HANG: hanging cloth (laundry) swings its bottom downwind around the pivot at the top.
##   FLAG: a flag on a pole turns to point downwind and flutters.

enum Mode { HANG, FLAG }

var mode := Mode.HANG
var strength := 0.8
var _phase := randf() * TAU
var _yaw := 0.0


func _process(delta: float) -> void:
	_phase += delta
	var w := Wind.offset(global_position)
	match mode:
		Mode.HANG:
			# Hanging -Y pushed toward +X = +Z rotation; toward +Z = -X rotation.
			var f := 1.0 + sin(_phase * 3.1) * 0.25
			rotation = Vector3(-w.y * strength * f, 0.0, w.x * strength * f)
		Mode.FLAG:
			if w.length() > 0.05:
				var target := atan2(-w.y, w.x)
				_yaw = lerp_angle(_yaw, target, 1.0 - exp(-2.0 * delta))
			rotation = Vector3(0.0, _yaw + sin(_phase * 6.0) * 0.18 * w.length(), sin(_phase * 4.3) * 0.08)
