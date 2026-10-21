class_name Combat
extends RefCounted
## TRPG resolution of one attack that already made physical contact (GDD 6.2 [확정]):
##   1) hit roll  2) separate crit roll  3) weapon dice (+ element dice)  4) armour reduction.
## Profiles: {name, hit_bonus, crit_chance, phys: "1d4", elem: [{type, dice}], str_mult, ac, armor}.
## The concrete formulas (d20 vs AC, crit x2, armour subtraction, min 1) are [미정] assumptions.

const CRIT_MULTIPLIER := 2


static func resolve(attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var nat := Dice.d(20)
	var hit_total: int = nat + attacker["hit_bonus"]
	var ac: int = defender["ac"]
	var hit := nat != 1 and (nat == 20 or hit_total >= ac)
	var res := {"hit": hit, "nat": nat, "hit_total": hit_total, "ac": ac, "crit": false, "damage": 0,
		"attacker": attacker["name"], "defender": defender["name"]}
	var hit_text := "명중 d20(%d)%+d=%d %s AC %d" % [nat, attacker["hit_bonus"], hit_total, "≥" if hit else "<", ac]
	if nat == 20:
		hit_text += " (자연 20)"
	elif nat == 1:
		hit_text += " (자연 1)"
	if not hit:
		res["detail"] = "%s → %s: %s → 빗나감" % [attacker["name"], defender["name"], hit_text]
		return res
	var crit_roll := Dice.d(100)
	var crit: bool = crit_roll <= attacker["crit_chance"]
	res["crit"] = crit
	var phys := Dice.roll(attacker["phys"])
	var str_mult: float = attacker.get("str_mult", 1.0)
	var phys_bonus: int = attacker.get("phys_bonus", 0)  # blacksmith upgrade, flat
	var phys_dmg := roundi(phys["total"] * str_mult) + phys_bonus
	var parts := PackedStringArray(["물리 %s×%.1f%s=%d" % [phys["text"], str_mult, "+%d(강화)" % phys_bonus if phys_bonus > 0 else "", phys_dmg]])
	var total := phys_dmg
	for e: Dictionary in attacker.get("elem", []):
		var r := Dice.roll(e["dice"])
		total += r["total"]
		parts.append("%s %s=%d" % [e["type"], r["text"], r["total"]])
	if crit:
		total *= CRIT_MULTIPLIER
	var armor: int = defender.get("armor", 0)
	var final := maxi(1, total - armor)
	res["damage"] = final
	res["detail"] = "%s → %s: %s · 치명 d100(%d)%s%d%% · 피해 %s%s%s = %d" % [
		attacker["name"], defender["name"], hit_text, crit_roll, "≤" if crit else ">", attacker["crit_chance"],
		" + ".join(parts), " ×%d(치명타)" % CRIT_MULTIPLIER if crit else "",
		" − 방어 %d" % armor if armor > 0 else "", final]
	return res


static func short_text(res: Dictionary) -> String:
	if not res["hit"]:
		return "%s의 공격이 빗나갔다" % res["attacker"]
	if res["crit"]:
		return "치명타! %s → %s %d 피해" % [res["attacker"], res["defender"], res["damage"]]
	return "%s → %s %d 피해" % [res["attacker"], res["defender"], res["damage"]]
