@tool  # read by the dialogue editor (item ids / names in conditions)
class_name ItemDB
extends RefCounted
## Prototype item table. Names/weights/numbers are development placeholders, not final data.
##
## Equipment (GDD 15.1/15.2 [확정]): fixed base stats per kind, no blanket rarity grades; some
## pieces roll a random extra option when acquired. Such a piece becomes a unique instance id
## "base#n" (never stacks), so the slot-less weight inventory and transfers work unchanged.
## Equipment keys: slot (main/off/head/body/hands/feet/neck/ring/belt), hands (1/2 for weapons),
## phys / elem dice, armor (damage reduction), bonus {stat: value}, lantern (belt hook).
## Bonus keys: STR..HLT, hit, crit, hp, sp, carry, armor.

const ITEMS := {
	"slime_jelly": {"name": "슬라임 젤리", "value": 3, "weight": 0.4, "desc": "말랑한 몬스터 재료."},
	"slime_core": {"name": "슬라임 핵", "cat": "rare", "value": 20, "weight": 1.2, "desc": "슬라임 속 단단한 핵."},
	"mana_shard": {"name": "작은 마석 조각", "cat": "rare", "value": 30, "weight": 0.5, "desc": "마력이 남아 있는 결정 조각."},
	"cat_snack": {"name": "고양이 간식", "value": 4, "weight": 0.1, "desc": "검은 고양이가 좋아하는 간식."},
	"firewood": {"name": "장작", "value": 3, "weight": 2.0, "desc": "잘 마른 장작."},
	"iron_ore": {"name": "철광석", "value": 12, "weight": 4.0, "desc": "무거운 광석 덩어리."},
	# --- gathering / fishing (P3-4, GDD 14.2/14.3): cooking / crafting ingredients
	"herb": {"name": "약초", "value": 4, "weight": 0.1, "desc": "상처에 좋은 들풀. 물약 재료."},
	"wild_berry": {"name": "산딸기", "value": 2, "weight": 0.05, "kind": "consumable", "use": "eat", "effect": {"hp": 3, "sp": 8},
		"desc": "새콤한 산딸기. HP +3, SP +8."},
	"edible_mushroom": {"name": "식용 버섯", "value": 3, "weight": 0.1, "desc": "익혀 먹는 버섯."},
	"moon_petal": {"name": "달빛 꽃잎", "cat": "rare", "value": 28, "weight": 0.05, "desc": "밤에만 피는 꽃의 꽃잎. 희귀 재료."},
	"small_fish": {"name": "붕어", "value": 5, "weight": 0.4, "desc": "연못에서 흔히 잡히는 물고기."},
	"trout": {"name": "송어", "value": 9, "weight": 0.7, "desc": "살이 단단한 물고기."},
	"golden_carp": {"name": "황금 잉어", "cat": "rare", "value": 60, "weight": 1.0, "desc": "보기 드문 황금빛 잉어."},
	"fishing_rod": {"name": "낚싯대", "value": 30, "weight": 1.5, "kind": "tool", "desc": "연못가 나무 부두에서 낚시할 때 필요하다."},
	# quest items: no merchant buys them, goblins don't take them
	"lost_parcel": {"name": "흩어진 짐 꾸러미", "cat": "quest", "value": 0, "weight": 1.5, "desc": "대장간 표식이 찍힌 꾸러미."},
	# --- consumables (GDD 6.4): effect applies when the use motion ends; a hit cancels it
	"canned_food": {"name": "통조림", "value": 8, "weight": 0.5, "kind": "consumable", "use": "eat", "effect": {"hp": 15},
		"desc": "현실에서 가져온 통조림. HP +15."},
	"heal_potion": {"name": "회복 물약", "value": 20, "weight": 0.3, "kind": "consumable", "use": "drink", "effect": {"hp": 20},
		"desc": "HP +20."},
	"stamina_potion": {"name": "기력 물약", "value": 16, "weight": 0.3, "kind": "consumable", "use": "drink", "effect": {"sp": 30},
		"desc": "SP +30."},
	"mana_potion": {"name": "마나 물약", "value": 24, "weight": 0.3, "kind": "consumable", "use": "drink", "effect": {"mp": 12},
		"desc": "MP +12."},
	"bread": {"name": "빵", "value": 5, "weight": 0.3, "kind": "consumable", "use": "eat", "effect": {"hp": 8, "sp": 20},
		"desc": "HP +8, SP +20."},
	"spellbook_minor_heal": {"name": "마법서: 작은 치유", "value": 120, "weight": 0.6, "kind": "consumable", "use": "read",
		"effect": {"learn": "minor_heal"}, "desc": "읽으면 마법 '작은 치유'를 배운다 (GDD 5.3: 마법서로 습득)."},
	# --- weapons (GDD 6.2 examples)
	"iron_sword": {"name": "철검", "value": 50, "weight": 3.0, "kind": "equip", "slot": "main", "hands": 1,
		"phys": "1d4", "desc": "한손 무기. 물리 1d4."},
	"flame_longsword": {"name": "불꽃 장검", "value": 240, "weight": 5.0, "kind": "equip", "slot": "main", "hands": 2,
		"phys": "1d6", "elem": [{"type": "화염", "dice": "1d4"}], "desc": "양손 무기. 물리 1d6 + 화염 1d4 (STR 배율은 물리에만)."},
	"wooden_shield": {"name": "나무 방패", "value": 40, "weight": 3.0, "kind": "equip", "slot": "off", "armor": 1,
		"desc": "보조 손. 방어 +1."},
	# --- armour
	"leather_cap": {"name": "가죽 모자", "value": 28, "weight": 0.8, "kind": "equip", "slot": "head", "armor": 1,
		"random": true, "desc": "머리. 방어 +1."},
	"leather_armor": {"name": "가죽 갑옷", "value": 70, "weight": 6.0, "kind": "equip", "slot": "body", "armor": 2,
		"random": true, "desc": "몸통. 방어 +2."},
	"leather_gloves": {"name": "가죽 장갑", "value": 25, "weight": 0.6, "kind": "equip", "slot": "hands", "armor": 1,
		"random": true, "desc": "장갑. 방어 +1."},
	"sturdy_boots": {"name": "튼튼한 장화", "value": 35, "weight": 1.5, "kind": "equip", "slot": "feet", "armor": 1,
		"random": true, "desc": "신발. 방어 +1."},
	# --- accessories
	"luck_necklace": {"name": "행운의 목걸이", "value": 80, "weight": 0.1, "kind": "equip", "slot": "neck",
		"bonus": {"crit": 3}, "desc": "목걸이. 치명타 확률 +3%."},
	"strength_ring": {"name": "힘의 반지", "value": 90, "weight": 0.05, "kind": "equip", "slot": "ring",
		"bonus": {"STR": 1}, "desc": "반지. STR +1."},
	"lantern_belt": {"name": "등불 허리띠", "value": 30, "weight": 1.0, "kind": "equip", "slot": "belt", "lantern": true,
		"desc": "허리띠. 등불을 걸 수 있다 (GDD 10.3: 등불은 허리띠에 끼움)."},
}

## Common use motion per consumable kind (GDD 6.4 [확정]); times / movement are [미정].
const USE_TYPES := {
	"drink": {"name": "마시는 중", "time": 0.8, "move": 0.5, "anim": "drink"},
	"eat": {"name": "먹는 중", "time": 1.8, "move": 0.0, "anim": "eat"},
	"read": {"name": "읽는 중", "time": 1.2, "move": 0.0, "anim": "cast"},
}

## Magic / special skills: learned from books, NPCs, quests (GDD 5.3), used only from the
## skill/magic quickslots. MP (and for some SP) cost, cast time, cooldown are [미정].
const SPELLS := {
	"minor_heal": {"name": "작은 치유", "desc": "HP +12", "mp": 8, "sp": 0, "time": 1.0, "cooldown": 3.0,
		"effect": {"hp": 12}, "anim": "cast", "move": 0.0},
}

const SLOT_NAMES := {"main": "주무기 손", "off": "보조 손", "head": "머리", "body": "몸통", "hands": "장갑",
	"feet": "신발", "neck": "목걸이", "ring1": "반지 1", "ring2": "반지 2", "belt": "허리띠"}
const SLOT_ORDER := ["main", "off", "head", "body", "hands", "feet", "neck", "ring1", "ring2", "belt"]

## Random extra options [미정 pool]: one of these, rolled on acquisition.
const OPTION_POOL := [
	{"hit": 1}, {"crit": 2}, {"hp": 4}, {"sp": 4}, {"armor": 1}, {"carry": 3}, {"STR": 1}, {"VIT": 1},
]
const OPTION_TEXT := {"hit": "명중 +%d", "crit": "치명 +%d%%", "hp": "최대 HP +%d", "sp": "최대 SP +%d",
	"armor": "방어 +%d", "carry": "소지 +%d kg", "STR": "STR +%d", "VIT": "VIT +%d", "END": "END +%d",
	"DIV": "DIV +%d", "INT": "INT +%d", "MNT": "MNT +%d", "HLT": "HLT +%d"}

## Instance id -> {"base": String, "opts": Dictionary}
static var instances := {}
static var _next_instance := 1


static func base_id(id: String) -> String:
	var i := id.find("#")
	return id if i < 0 else id.substr(0, i)


static func info(id: String) -> Dictionary:
	if not instances.has(id):
		return ITEMS.get(id, {"name": id, "weight": 0.0})
	var inst: Dictionary = instances[id]
	var d: Dictionary = ITEMS[inst["base"]].duplicate(true)
	var opts: Dictionary = inst["opts"]
	var bonus: Dictionary = d.get("bonus", {})
	var parts := PackedStringArray()
	for k: String in opts:
		bonus[k] = bonus.get(k, 0) + opts[k]
		parts.append(OPTION_TEXT.get(k, k + " +%d") % opts[k])
	d["bonus"] = bonus
	d["opts"] = opts
	# Blacksmith upgrade level (GDD 15.3): weapons +1 physical damage, armour +1 defence per level.
	var enh: int = inst.get("enh", 0)
	d["enh"] = enh
	if enh > 0:
		if d.has("phys"):
			d["phys_bonus"] = enh
		elif d.has("armor"):
			d["armor"] += enh
		d["name"] = "%s +%d" % [d["name"], enh]
	if not parts.is_empty():
		d["name"] = "%s · %s" % [d["name"], ", ".join(parts)]
	d["value"] = roundi(d.get("value", 0) * (1.3 if not opts.is_empty() else 1.0) + enh * 20)
	return d


static func item_name(id: String) -> String:
	return info(id)["name"]


static func weight(id: String) -> float:
	return info(id).get("weight", 0.0)


## Trade category (GDD 16.1/16.2): common goods, rare materials (specialists only), equipment.
static func category(id: String) -> String:
	var d := info(id)
	if d.get("kind", "") == "equip":
		return "equip"
	return d.get("cat", "common")


static func value(id: String) -> int:
	return info(id).get("value", 0)


## Blacksmith upgrade (GDD 15.3: always succeeds, no failure / downgrade / breaking).
const MAX_ENHANCE := 3  # [미정]


static func can_enhance(id: String) -> bool:
	var d := info(id)
	return d.get("kind", "") == "equip" and (d.has("phys") or d.has("armor")) and d.get("enh", 0) < MAX_ENHANCE


static func enhance_cost(id: String) -> int:
	return 30 * (info(id).get("enh", 0) + 1)  # [미정]


## Returns the id of the upgraded piece (a base item becomes a unique instance).
static func enhanced(id: String) -> String:
	var new_id := id
	if not instances.has(id):
		new_id = "%s#%d" % [id, _next_instance]
		_next_instance += 1
		instances[new_id] = {"base": id, "opts": {}}
	instances[new_id]["enh"] = instances[new_id].get("enh", 0) + 1
	return new_id


static func is_consumable(id: String) -> bool:
	return info(id).get("kind", "") == "consumable"


static func effect_text(effect: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: String in effect:
		match k:
			"hp": parts.append("HP +%d" % effect[k])
			"sp": parts.append("SP +%d" % effect[k])
			"mp": parts.append("MP +%d" % effect[k])
			"learn": parts.append("마법 습득: %s" % SPELLS[effect[k]]["name"])
	return ", ".join(parts)


static func is_equipment(id: String) -> bool:
	return info(id).get("kind", "") == "equip"


## Piece found as loot: pieces marked "random" get one random extra option with this chance.
static func acquire(base: String, rng: RandomNumberGenerator, option_chance := 0.5) -> String:
	if not ITEMS[base].get("random", false) or rng.randf() >= option_chance:
		return base
	var id := "%s#%d" % [base, _next_instance]
	_next_instance += 1
	instances[id] = {"base": base, "opts": OPTION_POOL[rng.randi() % OPTION_POOL.size()].duplicate()}
	return id


## One-line summary of an equipment piece for the UI.
static func equip_summary(id: String) -> String:
	var d := info(id)
	var parts := PackedStringArray()
	if d.has("phys"):
		var dmg: String = "물리 " + d["phys"]
		for e: Dictionary in d.get("elem", []):
			dmg += " + %s %s" % [e["type"], e["dice"]]
		parts.append(dmg)
		parts.append("양손" if d.get("hands", 1) == 2 else "한손")
	if d.get("armor", 0) > 0:
		parts.append("방어 +%d" % d["armor"])
	for k: String in d.get("bonus", {}):
		if not d.get("opts", {}).has(k) or d["bonus"][k] != d["opts"][k]:
			parts.append(OPTION_TEXT.get(k, k + " +%d") % d["bonus"][k])
	if d.get("lantern", false):
		parts.append("등불 걸이")
	return " · ".join(parts)
