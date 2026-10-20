class_name CombatLog
extends RefCounted
## Combat log data (GDD 6.3 [확정]): 3 display levels are handled by the HUD widget.
##   1 = icon only (default), 2 = latest result in one line, 3 = detailed log.

signal added(entry: Dictionary)

const MAX_ENTRIES := 60

var entries: Array[Dictionary] = []  # {"time": "10:32", "short": String, "detail": String, "kind": String}
var level := 1


## kind: "hit", "miss", "crit", "hurt", "info", "death"
func add(short: String, detail := "", kind := "info") -> void:
	var e := {"time": Game.clock_text(), "short": short, "detail": detail if detail != "" else short, "kind": kind}
	entries.append(e)
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	added.emit(e)


func cycle_level() -> int:
	level = level % 3 + 1
	return level
