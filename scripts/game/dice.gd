class_name Dice
extends RefCounted
## TRPG dice ("1d4", "2d6+1"). One shared RNG so a seed makes a whole fight reproducible.

static var rng := RandomNumberGenerator.new()


## Returns {"total": int, "rolls": Array[int], "bonus": int, "text": "1d4(3)"}.
static func roll(expr: String) -> Dictionary:
	var e := expr.strip_edges().to_lower()
	var bonus := 0
	for sign_char in ["+", "-"]:
		var i := e.find(sign_char, 1)
		if i > 0:
			bonus = int(e.substr(i))
			e = e.substr(0, i)
			break
	var parts := e.split("d")
	var n := maxi(1, int(parts[0]) if parts[0] != "" else 1)
	var sides := maxi(1, int(parts[1]) if parts.size() > 1 else 1)
	var rolls: Array[int] = []
	var total := bonus
	for i in n:
		var r := rng.randi_range(1, sides)
		rolls.append(r)
		total += r
	var shown := ",".join(PackedStringArray(rolls.map(func(r: int) -> String: return str(r))))
	var text := "%s(%s)" % [expr, shown]
	return {"total": total, "rolls": rolls, "bonus": bonus, "text": text}


static func d(sides: int) -> int:
	return rng.randi_range(1, sides)
