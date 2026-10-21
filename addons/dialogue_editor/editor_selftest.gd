@tool
class_name DialogueEditorSelftest
extends RefCounted
## Scripted walk through the editor: open, inspect, preview with sandbox states, build a new
## dialogue from scratch (all node types), catch validation errors, fix, save, reload and compare,
## undo / redo, copy / paste, then clean up. Run inside the real editor (plugin.gd, env
## DIALOGUE_EDITOR_SELFTEST) and inside the game (--tour=dialogue_editor). Prints [editor] lines.

const TEST_ID := "dialogue.test.editor_selftest"


static func _check(ok: bool, what: String) -> bool:
	print("[editor] %s %s" % ["PASS" if ok else "FAIL", what])
	return ok


static func _frames(panel: Control, n: int) -> void:
	for i in n:
		await panel.get_tree().process_frame


static func _walk(panel: DialogueEditorPanel, picks: Array) -> PackedStringArray:
	var said := PackedStringArray()
	var pi := 0
	for i in 40:
		var ev := panel.preview_event()
		match ev.get("type", ""):
			"line":
				said.append(str(ev["text"]).split("\n")[0])
				panel.preview_next()
			"cutscene":
				said.append("[컷씬 " + str(ev["cutscene_id"]) + "]")
				panel.preview_next()
			"choice":
				var port: String = picks[pi] if pi < picks.size() else ev["options"][0]["port"]
				pi += 1
				said.append("[선택 " + port + "]")
				panel.preview_choose(port)
			_:
				said.append("[끝 %s]" % ev.get("error", ""))
				break
	return said


static func run(panel: DialogueEditorPanel, shot: Callable) -> void:
	var fails := 0
	await _frames(panel, 5)
	# 1. open an existing dialogue
	fails += 0 if _check(panel.open_dialogue("dialogue.npc.rosa.main"), "open dialogue.npc.rosa.main (%d nodes)" % panel.doc["nodes"].size()) else 1
	await _frames(panel, 5)
	await shot.call("editor_01_rosa_graph")
	# 2. inspector of a line
	panel.select_node("line_offer")
	await _frames(panel, 4)
	await shot.call("editor_02_line_inspector")
	# 3. preview with the default sandbox (quest not taken) -> offer branch
	panel.set_sandbox_quest("quest.rosa.jelly", "none")
	panel.preview_start()
	await _frames(panel, 2)
	panel.preview_next()  # offer line -> choice
	await _frames(panel, 3)
	await shot.call("editor_03_preview_choice")
	var path1 := _walk(panel, ["accept"])
	fails += 0 if _check(" ".join(path1).contains("고마워요"), "preview (quest none) → accept: %s" % " | ".join(path1)) else 1
	var logged := PackedStringArray(panel._prev_ctx.log)
	fails += 0 if _check(" ".join(logged).contains("퀘스트 수락"), "sandbox action log: %s" % ", ".join(logged)) else 1
	# 4. same dialogue, sandbox state 'ready' -> reward branch
	panel.set_sandbox_quest("quest.rosa.jelly", "ready")
	panel.preview_start()
	var path2 := _walk(panel, [])
	fails += 0 if _check(" ".join(path2).contains("사례"), "preview (quest ready) → turn-in: %s" % " | ".join(path2)) else 1
	panel.set_sandbox_quest("quest.rosa.jelly", "none")
	# 5. build a new dialogue with every node type
	if FileAccess.file_exists(DialogueData.path_for(TEST_ID)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DialogueData.path_for(TEST_ID)))
	fails += 0 if _check(panel.create_dialogue(TEST_ID, "에디터 자체 점검"), "create %s" % TEST_ID) else 1
	await _frames(panel, 3)
	var line1 := "line_01"
	var n1 := DialogueData.node_by_id(panel.doc, line1)
	n1["speaker_id"] = "rosa"
	n1["text"] = "긴 대사도 괜찮아요.\n두 번째 줄 — 한글·줄바꿈·특수문자 \"따옴표\" 확인."
	panel.select_node(line1, false)
	var choice := panel.add_node("choice")  # linked from line_01's free... (line_01 -> end exists, so unlinked)
	var cn := DialogueData.node_by_id(panel.doc, choice)
	cn["options"] = [{"port": "yes", "text": "조건 분기로"}, {"port": "no", "text": "끝내기"},
		{"port": "rich", "text": "(골드 100 이상일 때만 보임)", "condition": {"kind": "gold", "amount": 100}}]
	panel.connect_nodes(line1, "next", choice)
	panel.select_node(choice, false)
	var cond := panel.add_node("condition")  # linked from choice.yes (first free port)
	DialogueData.node_by_id(panel.doc, cond)["check"] = {"kind": "quest", "quest_id": "quest.rosa.jelly", "state": "active"}
	panel.select_node(cond, false)
	var act := panel.add_node("action")  # cond.true
	DialogueData.node_by_id(panel.doc, act)["action"] = "set_flag"
	DialogueData.node_by_id(panel.doc, act)["args"] = {"key": "selftest.flag", "value": true}
	panel.select_node(act, false)
	var cut := panel.add_node("cutscene")  # act.next
	DialogueData.node_by_id(panel.doc, cut)["cutscene_id"] = "cutscene.cat.first_appearance"
	panel.select_node(cut, false)
	var line2 := panel.add_node("line")  # cut.next
	DialogueData.node_by_id(panel.doc, line2)["text"] = "컷씬 다음 대사."
	DialogueData.node_by_id(panel.doc, line2)["speaker_id"] = "cat"
	# typo'd action + a speaker that does not exist to prove the validator catches them
	var bad := panel.add_node("action", Vector2(300, 520))
	DialogueData.node_by_id(panel.doc, bad)["action"] = "quest_accept"
	DialogueData.node_by_id(panel.doc, bad)["args"] = {"quest_id": "quest.rosa.jely"}
	panel.connect_nodes(cond, "false", bad)
	panel._commit()
	panel._rebuild_graph()
	var errors := panel.validate(true)
	var msgs := PackedStringArray()
	for it in panel.issues:
		msgs.append("%s:%s" % [it["node"], it["message"]])
	panel.select_node(bad, false)
	await _frames(panel, 3)
	await shot.call("editor_04_validation_errors")
	var text := " / ".join(msgs)
	fails += 0 if _check(errors >= 3 and text.contains("quest.rosa.jely") and text.contains("연결 없는 출력"),
		"validator caught %d errors: %s" % [errors, text]) else 1
	# 6. fix: real quest id, wire every open output to end
	DialogueData.node_by_id(panel.doc, bad)["args"] = {"quest_id": "quest.rosa.jelly"}
	for id in [line2, bad]:
		panel.connect_nodes(id, "next", "end")
	panel.connect_nodes(choice, "no", "end")
	panel.connect_nodes(choice, "rich", "end")
	errors = panel.validate(false)
	fails += 0 if _check(errors == 0, "after fixes: %d errors (%d warnings)" % [errors, panel.issues.size()]) else 1
	panel.arrange()
	panel.select_node(choice, false)
	await _frames(panel, 3)
	await shot.call("editor_05_new_dialogue_arranged")
	# 7. preview the new graph, hidden option, flag + cutscene step
	panel.set_sandbox_quest("quest.rosa.jelly", "active")
	panel.preview_start()
	var opts_seen := 0
	panel.preview_next()
	opts_seen = (panel.preview_event().get("options", []) as Array).size()
	var path3 := _walk(panel, ["yes"])
	fails += 0 if _check(opts_seen == 2 and " ".join(path3).contains("컷씬") and " ".join(PackedStringArray(panel._prev_ctx.log)).contains("selftest.flag"),
		"preview new graph: %d options visible (gold-gated hidden), %s" % [opts_seen, " | ".join(path3)]) else 1
	panel.set_sandbox_quest("quest.rosa.jelly", "none")
	# 8. undo / redo
	var count := (panel.doc["nodes"] as Array).size()
	var extra := panel.add_node("end", Vector2(0, 700))
	panel.undo()
	var after_undo := (panel.doc["nodes"] as Array).size()
	panel.redo()
	var after_redo := (panel.doc["nodes"] as Array).size()
	fails += 0 if _check(after_undo == count and after_redo == count + 1, "undo/redo: %d → %d → %d" % [count + 1, after_undo, after_redo]) else 1
	panel.delete_nodes(PackedStringArray([extra]))
	# 9. copy / paste keeps inner links and makes new ids
	panel.select_node(cut, false)
	for c in panel._graph.get_children():
		if c is GraphNode and String(c.name) in [cut, line2]:
			c.selected = true
	panel.copy_selection()
	var pasted := panel.paste()
	var linked := false
	for c: Dictionary in panel.doc["connections"]:
		linked = linked or (pasted.has(c["from"]) and pasted.has(c["to"]))
	fails += 0 if _check(pasted.size() == 2 and linked, "copy/paste: new ids %s, inner link kept %s" % [", ".join(pasted), linked]) else 1
	panel.delete_nodes(pasted)
	# 10. rename keeps links
	panel.rename_node(line2, "line_after_cutscene")
	fails += 0 if _check(DialogueData.target(panel.doc, cut, "next") == "line_after_cutscene", "rename node keeps its links") else 1
	# 11. save -> reload from disk -> identical
	var saved_ok := panel.save(true, true)
	var before := var_to_str(DialogueData.normalized(panel.doc))
	panel.open_dialogue("dialogue.npc.rosa.main")
	panel.open_dialogue(TEST_ID)
	var after := var_to_str(DialogueData.normalized(panel.doc))
	fails += 0 if _check(saved_ok and before == after, "save → reload: nodes, links, text and positions identical (%d bytes)" % FileAccess.get_file_as_string(DialogueData.path_for(TEST_ID)).length()) else 1
	var reread := DialogueData.load_dialogue(TEST_ID)
	fails += 0 if _check(str(DialogueData.node_by_id(reread, line1).get("text", "")).contains("두 번째 줄"), "UTF-8 Korean + newline survive the file") else 1
	# 12. outside change -> conflict warning instead of silent overwrite
	var f := FileAccess.open(DialogueData.path_for(TEST_ID), FileAccess.WRITE)
	f.store_string(DialogueData.to_json(reread).replace("에디터 자체 점검", "밖에서 바뀜"))
	f.close()
	panel._mtime -= 5  # simulate the file being newer than what the editor loaded
	DialogueData.node_by_id(panel.doc, line1)["text"] = "에디터에서 고친 대사"
	panel._commit()
	var refused := not panel.save(true, false)
	fails += 0 if _check(refused, "outside change → save asks before overwriting") else 1
	panel._confirm.hide()
	# cleanup
	panel.open_dialogue("dialogue.npc.rosa.main")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DialogueData.path_for(TEST_ID)))
	panel.refresh_list()
	print("[editor] done: %d failed checks" % fails)
