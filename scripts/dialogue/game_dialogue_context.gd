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
	return "지원하지 않는 액션 %s — 무시" % action
