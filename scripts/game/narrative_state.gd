class_name NarrativeState
extends RefCounted
## Story flags set by dialogues / events (Game.narrative). Completed events are flags named
## "event.<id>", so a replayed dialogue sees them and never pays out twice.

signal changed

var flags := {}


func get_flag(key: String) -> bool:
	return bool(flags.get(key, false))


func set_flag(key: String, value := true) -> void:
	if get_flag(key) == value:
		return
	if value:
		flags[key] = true
	else:
		flags.erase(key)
	changed.emit()


func mark_event(event_id: String) -> bool:
	if event_done(event_id):
		return false
	set_flag("event." + event_id)
	return true


func event_done(event_id: String) -> bool:
	return get_flag("event." + event_id)
