class_name PlayerState
extends RefCounted
## Player stats, HP/MP/SP, the weight-based bag (GDD 4.2, 5.1, 8.1 [확정]) and growth (5.2/5.3 [확정]):
## general EXP is spent by the player on a level-up (+1 stat point [임시]) or on basic skills;
## nothing levels up automatically. Life EXP is a separate pool (no sources yet).
## Every formula and number here is a P1 development assumption (GDD [미정]),
## see notes/IMPLEMENTATION_ASSUMPTIONS.md.

signal changed
signal died
signal leveled_up(level: int)

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
## Equipped items by slot (GDD 15.1 [확정]); "" = empty. Equipped items are not in the bag and
## don't count toward carried weight [가정].
var equipment := {"main": "iron_sword", "off": "", "head": "", "body": "", "hands": "", "feet": "",
	"neck": "", "ring1": "", "ring2": "", "belt": "lantern_belt"}
## Prototype combat numbers [미정]: d20 + hit_bonus >= target AC (skills / gear add to it).
var hit_bonus := 3
var armor_class := 10
var armor := 0
var crit_chance := 5  # percent, separate roll from the hit (GDD 6.2 [확정])

var _sp_idle := 0.0

# ---------------------------------------------------------------- growth (GDD 5.2 / 5.3)
const STAT_POINTS_PER_LEVEL := 1  # GDD 5.2 [임시]
const STAT_INFO := {
	"STR": ["힘", "물리 기본 주사위 피해 배율, 최대 소지 중량"],
	"INT": ["지능", "고급 마법·생활 기술 학습 조건 (아직 효과 없음)"],
	"END": ["지구력", "최대 SP"],
	"DIV": ["신성력", "최대 MP"],
	"VIT": ["체력", "최대 HP, SP 회복 속도"],
	"MNT": ["멘탈", "정신계 상태이상 저항(미구현), MP 회복 속도"],
	"HLT": ["건강", "불리한 상태이상 저항 (아직 효과 없음)"],
}
## Basic skills learned without a teacher by spending general EXP (GDD 5.3 [확정]); the list,
## costs and effects are [미정] prototype examples. Learned skills here are passive.
const SKILLS := {
	"accuracy": {"name": "명중 훈련", "desc": "명중 굴림 +1", "max": 3, "cost": [25, 45, 70]},
	"vital_aim": {"name": "급소 노리기", "desc": "치명타 확률 +3%", "max": 2, "cost": [40, 70]},
	"pack_mule": {"name": "짐 꾸리기 요령", "desc": "최대 소지 중량 +5 kg", "max": 2, "cost": [30, 55]},
}

var level := 1
var gen_exp := 0    ## general EXP (combat, quests)
var life_exp := 0   ## life EXP (life activities, quests) - no sources yet
var stat_points := 0
var skills := {}    ## id -> rank


## General EXP needed for the next level-up [미정 formula]: 20, 40, 60, ...
func exp_to_next() -> int:
	return 20 * level


func can_level_up() -> bool:
	return gen_exp >= exp_to_next()


func add_exp(n: int) -> void:
	gen_exp += n
	changed.emit()


## Player-chosen level-up (GDD 5.2: never automatic).
func level_up() -> bool:
	if not can_level_up():
		return false
	gen_exp -= exp_to_next()
	level += 1
	stat_points += STAT_POINTS_PER_LEVEL
	changed.emit()
	leveled_up.emit(level)
	return true


## Spend one stat point; raised maximums also raise the current value by the same amount.
func add_stat(key: String) -> bool:
	if stat_points <= 0 or not stats.has(key):
		return false
	var before := [max_hp(), max_sp(), max_mp()]
	stats[key] += 1
	stat_points -= 1
	_apply_max_change(before)
	return true


func skill_rank(id: String) -> int:
	return skills.get(id, 0)


## EXP cost of the next rank, or -1 when maxed.
func skill_cost(id: String) -> int:
	var info: Dictionary = SKILLS[id]
	var r := skill_rank(id)
	return -1 if r >= info["max"] else info["cost"][r]


func learn_skill(id: String) -> bool:
	var cost := skill_cost(id)
	if cost < 0 or gen_exp < cost:
		return false
	gen_exp -= cost
	skills[id] = skill_rank(id) + 1
	changed.emit()
	return true


func total_hit_bonus() -> int:
	return hit_bonus + skill_rank("accuracy") + gear_bonus("hit")


func total_crit_chance() -> int:
	return crit_chance + 3 * skill_rank("vital_aim") + gear_bonus("crit")


# ---------------------------------------------------------------- equipment (GDD 15.1 / 15.2)

func gear_bonus(key: String) -> int:
	var total := 0
	for slot: String in equipment:
		var id: String = equipment[slot]
		if id != "":
			total += ItemDB.info(id).get("bonus", {}).get(key, 0)
	return total


## Armour reduces damage taken (GDD 6.2: no manual block input).
func total_armor() -> int:
	var total := armor + gear_bonus("armor")
	for slot: String in equipment:
		if equipment[slot] != "":
			total += ItemDB.info(equipment[slot]).get("armor", 0)
	return total


func has_lantern() -> bool:
	return equipment["belt"] != "" and ItemDB.info(equipment["belt"]).get("lantern", false)


func two_handed() -> bool:
	return equipment["main"] != "" and ItemDB.info(equipment["main"]).get("hands", 1) == 2


## Which slot an item would go into (rings: first free ring slot, else ring 1).
func target_slot(id: String) -> String:
	var slot: String = ItemDB.info(id).get("slot", "")
	if slot == "ring":
		return "ring2" if equipment["ring1"] != "" and equipment["ring2"] == "" else "ring1"
	return slot


## Equip an item from the bag. One/two-hand rules (GDD 15.1): a two-handed weapon frees the off
## hand, an off-hand item puts a two-handed weapon away. Displaced items go back to the bag
## (even past the weight limit - you can't drop them mid-swap) [가정].
func equip(id: String) -> bool:
	if not ItemDB.is_equipment(id) or inventory.count(id) <= 0:
		return false
	var slot := target_slot(id)
	var before := [max_hp(), max_sp(), max_mp()]
	inventory.remove(id, 1)
	if slot == "main" and ItemDB.info(id).get("hands", 1) == 2:
		_store("off")
	if slot == "off" and two_handed():
		_store("main")
	_store(slot)
	equipment[slot] = id
	_apply_max_change(before)
	return true


func unequip(slot: String) -> bool:
	if equipment.get(slot, "") == "":
		return false
	var before := [max_hp(), max_sp(), max_mp()]
	_store(slot)
	_apply_max_change(before)
	return true


func _store(slot: String) -> void:
	if equipment[slot] != "":
		inventory.add(equipment[slot], 1)
		equipment[slot] = ""
	if slot == "belt" and not has_lantern():
		Game.lantern_on = false


## Raised maximums raise the current value by the same amount; lowered ones clamp it.
func _apply_max_change(before: Array) -> void:
	hp = clampf(hp + max_hp() - before[0], 1.0 if hp > 0.0 else 0.0, max_hp())
	sp = clampf(sp + max_sp() - before[1], 0.0, max_sp())
	mp = clampf(mp + max_mp() - before[2], 0.0, max_mp())
	changed.emit()


## What the character model shows (weapon / shield / lantern on the belt) and a cache key for it.
func visual_gear() -> Dictionary:
	return {"main": ItemDB.base_id(equipment["main"]), "off": ItemDB.base_id(equipment["off"]),
		"lantern": has_lantern()}


static func gear_key(g: Dictionary) -> String:
	return "%s,%s,%s" % [g["main"], g["off"], "L" if g["lantern"] else "-"]


func _init() -> void:
	hp = max_hp()
	mp = max_mp()
	sp = max_sp()
	inventory.changed.connect(func() -> void: changed.emit())


## Stat including equipment bonuses (rings, random options).
func stat(key: String) -> int:
	return stats[key] + gear_bonus(key)


func max_hp() -> float:
	return 20.0 + stat("VIT") * 4.0 + gear_bonus("hp")  # VIT -> max HP


func max_sp() -> float:
	return 20.0 + stat("END") * 4.0 + gear_bonus("sp")  # END -> max SP


func max_mp() -> float:
	return 10.0 + stat("DIV") * 2.0  # DIV -> max MP


func sp_regen() -> float:
	return 4.0 + stat("VIT") * 0.4  # VIT -> SP recovery speed


func mp_regen() -> float:
	return 0.2 + stat("MNT") * 0.04  # MNT -> MP recovery speed


## STR -> carry weight (GDD 5.1). Over capacity: slower; above the hard limit: no pickups.
func carry_capacity() -> float:
	return 20.0 + stat("STR") * 2.0 + 5.0 * skill_rank("pack_mule") + gear_bonus("carry")


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
	return 1.0 + (stat("STR") - 5) * 0.1


## Main-hand weapon, or bare fists (1d2) when the hand is empty [가정].
func weapon() -> Dictionary:
	if equipment["main"] == "":
		return {"name": "맨손", "phys": "1d2"}
	return ItemDB.info(equipment["main"])


func combat_profile() -> Dictionary:
	var w := weapon()
	return {"name": "주인공", "hit_bonus": total_hit_bonus(), "crit_chance": total_crit_chance(),
		"phys": w.get("phys", "1d2"), "elem": w.get("elem", []), "str_mult": str_multiplier(),
		"ac": armor_class, "armor": total_armor()}


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
