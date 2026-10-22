@tool
class_name DialogueContext
extends RefCounted
## What a running dialogue may ask about / change in the world. This base class is the editor
## preview's sandbox: test flags, quest states, items and gold live only in here, so previewing
## never touches the real game state (GameDialogueContext forwards to the live game instead).

var flags := {}
var quest_states := {}  # quest id -> DialogueData.QUEST_STATES entry
var items := {}
var gold_amount := 0
## Human-readable record of every action the dialogue ran (preview log).
var log: Array[String] = []


func duplicate_state() -> DialogueContext:
	var c := DialogueContext.new()
	c.flags = flags.duplicate()
	c.quest_states = quest_states.duplicate()
	c.items = items.duplicate()
	c.gold_amount = gold_amount
	return c


func get_flag(key: String) -> bool:
	return bool(flags.get(key, false))


func quest_state(quest_id: String) -> String:
	return str(quest_states.get(quest_id, "none"))


func item_count(id: String) -> int:
	return int(items.get(id, 0))


func gold() -> int:
	return gold_amount


func event_done(event_id: String) -> bool:
	return get_flag("event." + event_id)


func speaker_name(id: String) -> String:
	return DialogueData.speaker_name(id)


## Runs one whitelisted action and returns what happened (shown in logs / toasts).
func run_action(action: String, args: Dictionary) -> String:
	var text := _apply(action, args)
	log.append(text)
	return text


func _apply(action: String, args: Dictionary) -> String:
	var qid := str(args.get("quest_id", ""))
	match action:
		"set_flag":
			flags[str(args.get("key", ""))] = bool(args.get("value", true))
			return "플래그 %s = %s" % [args.get("key", ""), bool(args.get("value", true))]
		"quest_accept":
			var s := quest_state(qid)
			if s == "active" or s == "ready":
				return "퀘스트 %s: 이미 진행 중 (중복 수락 없음)" % qid
			quest_states[qid] = "active"
			return "퀘스트 수락: %s" % qid
		"quest_advance":
			return "퀘스트 %s 목표 %s +%d (미리보기: 상태 변화 없음)" % [qid, args.get("objective", ""), int(args.get("amount", 1))]
		"quest_complete":
			if quest_state(qid) != "ready":
				return "퀘스트 %s: 완료 조건 미달 — 보상 없음 (현재 %s)" % [qid, quest_state(qid)]
			quest_states[qid] = "completed"
			var oc := str(args.get("outcome", ""))
			return "퀘스트 완료: %s%s" % [qid, " (결과 %s)" % oc if oc != "" else ""]
		"mark_event_complete":
			flags["event." + str(args.get("event_id", ""))] = true
			return "이벤트 완료 기록: %s" % args.get("event_id", "")
		"learn_recipe":
			return "레시피 습득(미리보기): %s" % args.get("recipe_id", "")
		"receive_camper":
			return "캠핑카 받음(미리보기)"
		"cat_join":
			return "고양이 동행 시작(미리보기)%s" % (" · 호감도 +%d" % int(args.get("affection", 0)) if int(args.get("affection", 0)) > 0 else "")
	return "지원하지 않는 액션 %s — 무시" % action
