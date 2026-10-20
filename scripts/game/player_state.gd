class_name PlayerState
extends RefCounted
## Player stats, HP/MP/SP and the weight-based bag (GDD 4.2, 5.1, 8.1 [확정]).
## Every formula and number here is a P1 development assumption (GDD [미정]),
## see notes/IMPLEMENTATION_ASSUMPTIONS.md.

signal changed
signal died

const STAT_KEYS := ["STR", "INT", "END", "DIV", "VIT", "MNT", "HLT"]
const RUN_SP_PER_SEC := 8.0
const ATTACK_SP := 4.0
const SP_REGEN_DELAY := 1.0
## Over capacity the speed drops linearly down to this factor at the hard limit.
const MIN_SPEED_FACTOR := 0.5

var stats := {"STR": 5, "INT": 5, "END": 5, "DIV": 5, "VIT": 5, "MNT": 5, "HLT": 5}
var hp := 0.0
var mp := 0.0
var sp := 0.0
var inventory := Inventory.new()
var weapon_id := "rusty_sword"
## Prototype combat numbers [미정]: d20 + hit_bonus >= target AC.
var hit_bonus := 3
var armor_class := 10
var armor := 0
var crit_chance := 5  # percent, separate roll from the hit (GDD 6.2 [확정])

var _sp_idle := 0.0


func _init() -> void:
	hp = max_hp()
	mp = max_mp()
	sp = max_sp()
	inventory.changed.connect(func() -> void: changed.emit())


func max_hp() -> float:
	return 20.0 + stats["VIT"] * 4.0  # VIT -> max HP


func max_sp() -> float:
	return 20.0 + stats["END"] * 4.0  # END -> max SP


func max_mp() -> float:
	return 10.0 + stats["DIV"] * 2.0  # DIV -> max MP


func sp_regen() -> float:
	return 4.0 + stats["VIT"] * 0.4  # VIT -> SP recovery speed


func mp_regen() -> float:
	return 0.2 + stats["MNT"] * 0.04  # MNT -> MP recovery speed


## STR -> carry weight (GDD 5.1). Over capacity: slower; above the hard limit: no pickups.
func carry_capacity() -> float:
	return 20.0 + stats["STR"] * 2.0


func carry_limit() -> float:
	return carry_capacity() * 1.5


func carried_weight() -> float:
	return inventory.weight()


func can_carry(extra: float) -> bool:
	return carried_weight() + extra <= carry_limit() + 0.0001


func speed_factor() -> float:
	var w := carried_weight()
	var cap := carry_capacity()
	if w <= cap:
		return 1.0
	return lerpf(1.0, MIN_SPEED_FACTOR, clampf((w - cap) / (carry_limit() - cap), 0.0, 1.0))


func weight_state() -> String:
	var w := carried_weight()
	if w > carry_limit() - 0.0001 and w > carry_capacity():
		return "한계"
	if w > carry_capacity():
		return "과적"
	return "정상"


## STR multiplier for the weapon's physical dice only (GDD 5.1 [확정]); formula [미정].
func str_multiplier() -> float:
	return 1.0 + (stats["STR"] - 5) * 0.1


func weapon() -> Dictionary:
	return ItemDB.info(weapon_id)


func combat_profile() -> Dictionary:
	var w := weapon()
	return {"name": "주인공", "hit_bonus": hit_bonus, "crit_chance": crit_chance,
		"phys": w.get("phys", "1d2"), "elem": w.get("elem", []), "str_mult": str_multiplier(),
		"ac": armor_class, "armor": armor}


func spend_sp(amount: float) -> bool:
	if sp < amount:
		return false
	sp -= amount
	_sp_idle = 0.0
	changed.emit()
	return true


## Continuous drain (running). Returns false when empty.
func drain_sp(amount: float) -> bool:
	if sp <= 0.0:
		return false
	sp = maxf(0.0, sp - amount)
	_sp_idle = 0.0
	return true


func tick(delta: float) -> void:
	_sp_idle += delta
	if _sp_idle >= SP_REGEN_DELAY and sp < max_sp():
		sp = minf(max_sp(), sp + sp_regen() * delta)
	if mp < max_mp():
		mp = minf(max_mp(), mp + mp_regen() * delta)


func take_damage(amount: int) -> void:
	if hp <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	changed.emit()
	if hp <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	hp = minf(max_hp(), hp + amount)
	changed.emit()


func restore_all() -> void:
	hp = max_hp()
	mp = max_mp()
	sp = max_sp()
	changed.emit()


func is_dead() -> bool:
	return hp <= 0.0
