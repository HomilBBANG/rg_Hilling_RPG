@tool
class_name DialogueRunner
extends RefCounted
## Steps through a dialogue graph. The same runner drives the editor preview (sandbox context)
## and the in-game dialogue box (GameDialogueContext). It is synchronous: start()/next()/choose()
## return the next thing to show, and Start / Condition / Action nodes are passed through.
##
## Events: {"type": "line", "node", "speaker", "name", "text", "expression"}
##         {"type": "choice", "node", "options": [{"port", "text"}]}
##         {"type": "cutscene", "node", "cutscene_id"}   -> call next() once it has played
##         {"type": "end", "node", "error": ""}

const MAX_AUTO_STEPS := 256

var doc: Dictionary
var ctx: DialogueContext
var current := ""
var finished := false
## Every node visited, in order (preview highlight / debugging).
var trace: Array[String] = []


func _init(d: Dictionary, c: DialogueContext) -> void:
	doc = d
	ctx = c


func start(from := "") -> Dictionary:
	finished = false
	trace.clear()
	return _run(from if from != "" else str(doc.get("start_node_id", "start")))


## Continue after a line or a cutscene.
func next() -> Dictionary:
	if finished:
		return _end(current, "")
	return _run(DialogueData.target(doc, current, "next"), current, "next")


func choose(port: String) -> Dictionary:
	if finished:
		return _end(current, "")
	return _run(DialogueData.target(doc, current, port), current, port)


func visible_options(n: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Dictionary in n.get("options", []):
		var cond: Dictionary = o.get("condition", {})
		if cond.is_empty() or DialogueData.eval_condition(cond, ctx):
			out.append({"port": str(o.get("port", "")), "text": str(o.get("text", ""))})
	return out


func _run(id: String, from := "", port := "") -> Dictionary:
	for i in MAX_AUTO_STEPS:
		if id == "":
			return _end(from, "연결 없는 출력 (%s → %s)" % [from, port] if from != "" else "시작 노드가 없다")
		var n := DialogueData.node_by_id(doc, id)
		if n.is_empty():
			return _end(from, "존재하지 않는 노드 '%s'" % id)
		current = id
		trace.append(id)
		match n.get("type", ""):
			"start":
				from = id
				port = "next"
			"line":
				var sp := str(n.get("speaker_id", ""))
				return {"type": "line", "node": id, "speaker": sp, "name": ctx.speaker_name(sp), "text": str(n.get("text", "")),
					"expression": str(n.get("expression", ""))}
			"choice":
				var opts := visible_options(n)
				if opts.is_empty():
					return _end(id, "보이는 선택지가 없다")
				return {"type": "choice", "node": id, "options": opts}
			"condition":
				from = id
				port = "true" if DialogueData.eval_condition(n.get("check", {}), ctx) else "false"
			"action":
				ctx.run_action(str(n.get("action", "")), n.get("args", {}))
				from = id
				port = "next"
			"cutscene":
				return {"type": "cutscene", "node": id, "cutscene_id": str(n.get("cutscene_id", ""))}
			"end":
				var ev := str(n.get("complete_event", ""))
				if ev != "":
					ctx.run_action("mark_event_complete", {"event_id": ev})
				return _end(id, "")
			_:
				return _end(id, "알 수 없는 노드 종류 '%s'" % n.get("type", ""))
		id = DialogueData.target(doc, from, port)
	return _end(current, "자동 노드가 %d번 넘게 이어짐 (순환 연결?)" % MAX_AUTO_STEPS)


func _end(node: String, error: String) -> Dictionary:
	finished = true
	if error != "":
		push_warning("[dialogue] %s: %s" % [doc.get("dialogue_id", "?"), error])
	return {"type": "end", "node": node, "error": error}
