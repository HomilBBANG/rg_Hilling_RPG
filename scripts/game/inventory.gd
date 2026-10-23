class_name Inventory
extends RefCounted
## Slot-less, weight-based item container (GDD 8.1/8.3 [확정]): no cell count, only weight.
## Same item ids stack into one entry (stacking itself is a prototype assumption).

signal changed

var items: Array[Dictionary] = []  # {"id": String, "count": int}


func count(id: String) -> int:
	for e in items:
		if e["id"] == id:
			return e["count"]
	return 0


func add(id: String, n := 1) -> void:
	if n <= 0:
		return
	for e in items:
		if e["id"] == id:
			e["count"] += n
			changed.emit()
			return
	items.append({"id": id, "count": n})
	changed.emit()


## Removes up to n; returns how many were removed.
func remove(id: String, n := 1) -> int:
	for i in items.size():
		var e := items[i]
		if e["id"] == id:
			var k := mini(n, e["count"])
			e["count"] -= k
			if e["count"] <= 0:
				items.remove_at(i)
			changed.emit()
			return k
	return 0


func weight() -> float:
	var w := 0.0
	for e in items:
		w += ItemDB.weight(e["id"]) * e["count"]
	return w


func unit_count() -> int:
	var n := 0
	for e in items:
		n += e["count"]
	return n


func is_empty() -> bool:
	return items.is_empty()


func clear() -> void:
	items.clear()
	changed.emit()


## "정렬": equipment, consumables, materials, camper goods, decor, then the rest; by name within.
func sort() -> void:
	var rank := {"equip": 0, "consumable": 1, "": 2, "tool": 3, "camper": 4, "decor": 5}
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: int = rank.get(str(ItemDB.info(a["id"]).get("kind", "")), 6)
		var rb: int = rank.get(str(ItemDB.info(b["id"]).get("kind", "")), 6)
		if ra != rb:
			return ra < rb
		return ItemDB.item_name(a["id"]) < ItemDB.item_name(b["id"]))
	changed.emit()


func duplicate_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in items:
		out.append(e.duplicate())
	return out
