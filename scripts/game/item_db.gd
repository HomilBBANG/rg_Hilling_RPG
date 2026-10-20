class_name ItemDB
extends RefCounted
## Prototype item table (P1). Names/weights are development placeholders, not final data.

const ITEMS := {
	"slime_jelly": {"name": "슬라임 젤리", "weight": 0.4, "desc": "말랑한 몬스터 재료."},
	"slime_core": {"name": "슬라임 핵", "weight": 1.2, "desc": "슬라임 속 단단한 핵."},
	"mana_shard": {"name": "작은 마석 조각", "weight": 0.5, "desc": "마력이 남아 있는 결정 조각."},
	"cat_snack": {"name": "고양이 간식", "weight": 0.1, "desc": "검은 고양이가 좋아하는 간식."},
	"firewood": {"name": "장작", "weight": 2.0, "desc": "잘 마른 장작."},
	"iron_ore": {"name": "철광석", "weight": 4.0, "desc": "무거운 광석 덩어리."},
	"canned_food": {"name": "통조림", "weight": 0.5, "desc": "현실에서 가져온 통조림."},
	"rusty_sword": {"name": "낡은 철검", "weight": 3.0, "kind": "weapon", "phys": "1d4",
		"desc": "물리 1d4. 기본 무기."},
}


static func info(id: String) -> Dictionary:
	return ITEMS.get(id, {"name": id, "weight": 0.0})


static func item_name(id: String) -> String:
	return info(id)["name"]


static func weight(id: String) -> float:
	return info(id).get("weight", 0.0)
