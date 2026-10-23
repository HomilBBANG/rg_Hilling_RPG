class_name GameDialogueContext
extends DialogueContext
## Dialogue context for real play: queries and actions go to the live game state
## (Game.narrative flags/events, Game.quests, the player's bag and gold).


func get_flag(key: String) -> bool:
	return Game.narrative.get_flag(key)


func quest_state(quest_id: String) -> String:
	return Game.quests.state(quest_id)


func item_count(id: String) -> int:
	return Game.player_state.inventory.count(id)


func gold() -> int:
	return Game.player_state.gold


func event_done(event_id: String) -> bool:
	return Game.narrative.event_done(event_id)


func _apply(action: String, args: Dictionary) -> String:
	var qid := str(args.get("quest_id", ""))
	match action:
		"set_flag":
			Game.narrative.set_flag(str(args.get("key", "")), bool(args.get("value", true)))
			return "플래그 %s = %s" % [args.get("key", ""), bool(args.get("value", true))]
		"quest_accept":
			var why := Game.quests.accept(qid)
			return "퀘스트 수락: %s" % qid if why == "" else "퀘스트 %s: %s" % [qid, why]
		"quest_advance":
			return Game.quests.advance(qid, str(args.get("objective", "")), int(args.get("amount", 1)))
		"quest_complete":
			return Game.quests.complete(qid, str(args.get("outcome", "")))
		"mark_event_complete":
			var first := Game.narrative.mark_event(str(args.get("event_id", "")))
			return "이벤트 완료 기록: %s%s" % [args.get("event_id", ""), "" if first else " (이미 기록됨)"]
		"learn_recipe":
			var rid := str(args.get("recipe_id", ""))
			var first := Game.player_state.learn_recipe(rid)
			if first and Game.hud:
				Game.hud.toast_quest("레시피 습득: " + RecipeDB.recipe_name(rid))
			return "레시피 습득: %s%s" % [RecipeDB.recipe_name(rid), "" if first else " (이미 알고 있음)"]
		"receive_camper":
			if not Game.receive_camper():
				return "캠핑카: 이미 가지고 있다"
			var where := RegionDB.region_name(str(Game.camper.get("region", "")))
			Game.combat_log.add("캠핑카를 얻었다", "왕의 소원 — %s 성 앞 광장에 세워져 있다. 이제 캠핑카가 여행의 거점이 된다." % where, "info")
			if Game.hud:
				Game.hud.toast_quest("캠핑카를 얻었다! — %s 성 앞 광장" % where)
			return "캠핑카 받음 (%s)" % where
		"give_map":
			var r := str(args.get("region", ""))
			return "지도 받음: %s%s" % [MapDB.title(r), "" if MapDB.give(r) else " (이미 있음)"]
		"give_item":
			var it := str(args.get("item", ""))
			var n := maxi(1, int(args.get("count", 1)))
			Game.player_state.inventory.add(it, n)
			Game.combat_log.add("획득: %s ×%d" % [ItemDB.item_name(it), n], "", "info")
			if Game.hud:
				Game.hud.toast_quest("받았다: %s ×%d" % [ItemDB.item_name(it), n])
			return "아이템 받음: %s ×%d" % [ItemDB.item_name(it), n]
		"wish_ceremony":
			if Game.boot and Game.boot.has_method("start_wish_ceremony"):
				Game.boot.start_wish_ceremony.call_deferred()
				return "소원 의식 시작"
			return "소원 의식: 게임 밖에서는 실행할 수 없다"
		"cat_join":
			var aff := int(args.get("affection", 0))
			var first := not Game.cat_joined
			Game.join_cat()
			if aff > 0:
				Game.add_cat_affection(aff)
			if first:
				Game.combat_log.add("검은 고양이가 따라오기 시작했다", "길에서 만난 검은 고양이가 주인공을 따라오기로 했다 — 동행 시작", "info")
				if Game.hud:
					Game.hud.toast_quest("검은 고양이가 함께하게 되었다")
			return "고양이 동행 시작%s%s" % ["" if first else " (이미 함께)", " · 호감도 +%d" % aff if aff > 0 else ""]
	return "지원하지 않는 액션 %s — 무시" % action
