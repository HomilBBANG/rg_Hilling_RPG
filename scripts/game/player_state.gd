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
## Hover text per stat (character sheet): what it affects and what one point does — the numbers
## follow the formulas below (max_hp() etc.), so change both together.
const STAT_HELP := {
	"STR": "무기 물리 주사위 피해에 곱하는 배율과 최대 소지 중량에 영향을 준다.\n1포인트마다 물리 배율 +0.1, 소지 중량 +2 kg (한계 +3 kg).",
	"INT": "고급 마법·생활 기술을 배우는 조건이 된다.\n지금은 수치에 주는 효과가 없다.",
	"END": "최대 SP(스태미나)에 영향을 준다 — 달리기·공격에 SP를 쓴다.\n1포인트마다 최대 SP +4.",
	"DIV": "최대 MP에 영향을 준다 — 마법에 MP를 쓴다.\n1포인트마다 최대 MP +2.",
	"VIT": "최대 HP와 SP 회복 속도에 영향을 준다.\n1포인트마다 최대 HP +4, SP 회복 +0.4/초.",
	"MNT": "정신계 상태이상 저항(아직 없음)과 MP 회복 속도에 영향을 준다.\n1포인트마다 MP 회복 +0.04/초.",
	"HLT": "불리한 상태이상(독·질병 등) 저항에 영향을 준다.\n상태이상이 아직 없어 지금은 수치 효과가 없다.",
}
## Derived numbers on the character sheet: [key, label, value format, hover text].
const DERIVED := [
	["max_hp", "최대 HP", "%d", "쓰러지기 전까지 버틸 수 있는 피해.\n20 + 체력(VIT)×4 + 장비."],
	["max_sp", "최대 SP", "%d", "달리기·공격에 쓰는 스태미나.\n20 + 지구력(END)×4 + 장비."],
	["max_mp", "최대 MP", "%d", "마법에 쓰는 마력.\n10 + 신성력(DIV)×2."],
	["sp_regen", "SP 회복", "%.1f/초", "SP를 쓰지 않을 때 1초마다 차오르는 양.\n4 + 체력(VIT)×0.4."],
	["mp_regen", "MP 회복", "%.2f/초", "1초마다 차오르는 MP.\n0.2 + 멘탈(MNT)×0.04."],
	["carry", "소지 중량", "%.0f kg", "이만큼까지는 보통 속도로 걷는다. 넘으면 느려진다.\n20 + 힘(STR)×2 + 짐 꾸리기 요령 + 장비."],
	["carry_limit", "소지 한계", "%.0f kg", "이보다 무거우면 더 주울 수 없다 (소지 중량 ×1.5)."],
	["str_mult", "물리 배율", "×%.1f", "무기의 물리 주사위 피해에 곱한다 (원소 피해에는 안 곱함).\n1 + (힘(STR) − 5)×0.1."],
	["hit", "명중", "+%d", "d20 명중 굴림에 더하는 값. 상대 방어도(AC) 이상이면 맞는다.\n기본 3 + 명중 훈련 + 장비."],
	["crit", "치명타", "%d%%", "명중했을 때 따로 굴리는 치명타 확률.\n기본 5% + 급소 노리기 + 장비."],
	["armor", "방어", "%d", "받는 피해에서 빼는 값.\n장비 방어구 합계."],
]
## Basic skills learned without a teacher by spending general EXP (GDD 5.3 [확정]); the list,
## costs and effects are [미정] prototype examples. Learned skills here are passive.
const SKILLS := {
	"accuracy": {"name": "명중 훈련", "desc": "명중 굴림 +1", "max": 3, "cost": [25, 45, 70]},
	"vital_aim": {"name": "급소 노리기", "desc": "치명타 확률 +3%", "max": 2, "cost": [40, 70]},
	"pack_mule": {"name": "짐 꾸리기 요령", "desc": "최대 소지 중량 +5 kg", "max": 2, "cost": [30, 55]},
}

# ---------------------------------------------------------------- quickslots (GDD 5.3 / 6.4)
## Consumable quickslots and skill/magic quickslots are separate; slot counts are [미정] (4 + 4).
const QUICK_ITEM_SLOTS := 4
const QUICK_SKILL_SLOTS := 4
var quick_items: Array[String] = ["heal_potion", "", "", ""]
var quick_skills: Array[String] = ["", "", "", ""]
var spells: Array[String] = []   ## learned magic / special skills (need a quickslot to use)
var cooldowns := {}              ## spell id -> seconds left

## Currency (GDD 16.1 [확정]: 골드). Starting amount [미정].
var gold := 50

var level := 1
var gen_exp := 0    ## general EXP (combat, quests)
var life_exp := 0   ## life EXP (life activities, quests): spent on life skills (GDD 5.2 / 5.4)
## Mastery points per life field (GDD 5.4: grows automatically by repeating the activity).
var mastery := {"gathering": 0, "fishing": 0, "cooking": 0, "crafting": 0}
var life_skills: Array[String] = []
## Learned recipes (GDD 14.4); "known" ones are there from the start.
var recipes: Array[String] = []
var stat_points := 0
var skills := {}    ## id -> rank


## General EXP needed for the next level-up [미정 formula]: 20, 40, 60, ...
func mastery_level(field: String) -> int:
	return LifeDB.level_for(int(mastery.get(field, 0)))


## Adds mastery points; returns the new level when it went up, else 0.
func add_mastery(field: String, n: int) -> int:
	var before := mastery_level(field)
	mastery[field] = int(mastery.get(field, 0)) + n
	var after := mastery_level(field)
	changed.emit()
	return after if after > before else 0


func knows_recipe(id: String) -> bool:
	return id in recipes or RecipeDB.info(id).get("learn", "") == "known"


## Special recipes (NPC / book / quest / exploration) are simply given; returns false if known.
func learn_recipe(id: String) -> bool:
	if RecipeDB.info(id).is_empty() or knows_recipe(id):
		return false
	recipes.append(id)
	changed.emit()
	return true


## Basic recipes cost life EXP (and sometimes a minimum mastery). "" = ok, else why not.
func recipe_learn_block(id: String) -> String:
	var r := RecipeDB.info(id)
	if r.is_empty():
		return "없는 레시피"
	if knows_recipe(id):
		return "이미 배움"
	if r.get("learn", "") != "basic":
		return "특수 레시피 — %s" % r.get("source", "NPC·책·퀘스트·탐험")
	var req: Dictionary = r.get("req", {})
	for f: String in req:
		if mastery_level(f) < int(req[f]):
			return "%s 숙련도 Lv %d 필요" % [LifeDB.field_name(f), int(req[f])]
	if life_exp < int(r.get("cost", 0)):
		return "생활 EXP %d 필요" % int(r.get("cost", 0))
	return ""


func buy_recipe(id: String) -> bool:
	if recipe_learn_block(id) != "":
		return false
	life_exp -= int(RecipeDB.info(id).get("cost", 0))
	recipes.append(id)
	changed.emit()
	return true


func has_life_skill(id: String) -> bool:
	return id in life_skills


## "" = ok, else why not (cost in life EXP, minimum mastery).
func life_skill_block(id: String) -> String:
	var sk := LifeDB.skill(id)
	if sk.is_empty():
		return "없는 기술"
	if has_life_skill(id):
		return "이미 배움"
	var req: Dictionary = sk.get("req", {})
	for f: String in req:
		if mastery_level(f) < int(req[f]):
			return "%s 숙련도 Lv %d 필요" % [LifeDB.field_name(f), int(req[f])]
	if life_exp < int(sk.get("cost", 0)):
		return "생활 EXP %d 필요" % int(sk.get("cost", 0))
	return ""


func learn_life_skill(id: String) -> bool:
	if life_skill_block(id) != "":
		return false
	life_exp -= int(LifeDB.skill(id).get("cost", 0))
	life_skills.append(id)
	changed.emit()
	return true


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


## Derived numbers (DERIVED keys) as they are now.
func derived() -> Dictionary:
	return {"max_hp": max_hp(), "max_sp": max_sp(), "max_mp": max_mp(), "sp_regen": sp_regen(), "mp_regen": mp_regen(),
		"carry": carry_capacity(), "carry_limit": carry_limit(), "str_mult": str_multiplier(),
		"hit": total_hit_bonus(), "crit": total_crit_chance(), "armor": total_armor()}


## Derived numbers if the planned points (stat key -> amount) were spent — nothing is changed.
func derived_with(plan: Dictionary) -> Dictionary:
	var keep := stats.duplicate()
	for k: String in plan:
		if stats.has(k):
			stats[k] += int(plan[k])
	var out := derived()
	stats = keep
	return out


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
## Blacksmith upgrade of an equipped piece; the slot keeps the (new instance) id.
func enhance_equipped(slot: String) -> bool:
	var id: String = equipment.get(slot, "")
	if id == "" or not ItemDB.can_enhance(id):
		return false
	var cost := ItemDB.enhance_cost(id)
	if gold < cost:
		return false
	gold -= cost
	equipment[slot] = ItemDB.enhanced(id)
	changed.emit()
	return true


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
		"phys_bonus": w.get("phys_bonus", 0),
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


func assign_quick_item(slot: int, id: String) -> void:
	for i in QUICK_ITEM_SLOTS:  # one item per slot, one slot per item
		if quick_items[i] == id:
			quick_items[i] = ""
	quick_items[slot] = id
	changed.emit()


func assign_quick_skill(slot: int, id: String) -> void:
	for i in QUICK_SKILL_SLOTS:
		if quick_skills[i] == id:
			quick_skills[i] = ""
	quick_skills[slot] = id
	changed.emit()


func learn_spell(id: String) -> bool:
	if id in spells:
		return false
	spells.append(id)
	var free := quick_skills.find("")
	if free >= 0:
		quick_skills[free] = id  # convenience: drop it in the first free skill slot
	changed.emit()
	return true


## Applies a consumable / spell effect; returns a short summary.
func apply_effect(effect: Dictionary) -> String:
	if effect.has("hp"):
		hp = minf(max_hp(), hp + effect["hp"])
	if effect.has("sp"):
		sp = minf(max_sp(), sp + effect["sp"])
	if effect.has("mp"):
		mp = minf(max_mp(), mp + effect["mp"])
	if effect.has("learn"):
		learn_spell(effect["learn"])
	if effect.has("recipe"):
		learn_recipe(str(effect["recipe"]))
	changed.emit()
	return ItemDB.effect_text(effect)


func tick(delta: float) -> void:
	for k in cooldowns.keys():
		cooldowns[k] = maxf(0.0, cooldowns[k] - delta)
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
