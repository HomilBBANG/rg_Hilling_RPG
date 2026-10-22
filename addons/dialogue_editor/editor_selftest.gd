@tool
class_name DialogueEditorSelftest
extends RefCounted
## Scripted walk through the editor: open, inspect, preview with sandbox states, build a new
## dialogue from scratch (all node types), catch validation errors, fix, save, reload and compare,
## undo / redo, copy / paste, then clean up. Run inside the real editor (plugin.gd, env
## DIALOGUE_EDITOR_SELFTEST) and inside the game (--tour=dialogue_editor). Prints [editor] lines.

const TEST_ID := "dialogue.test.editor_selftest"
const CUT_ID := "cutscene.test.editor_selftest"


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
	fails += await _cutscene_checks(panel, shot)
	print("[editor] done: %d failed checks" % fails)


## The 컷씬 tab: open the intro, build a new cutscene with every step type, catch errors, reorder,
## undo / redo, save → reload, new-game order on/off (restored), preview to the end, clean up.
static func _cutscene_checks(dpanel: DialogueEditorPanel, shot: Callable) -> int:
	var fails := 0
	var cp := dpanel.cutscene_panel
	var story_before := CutsceneData.new_game_cutscenes()
	dpanel.edit_cutscene("cutscene.intro")
	await _frames(cp, 5)
	fails += 0 if _check(cp.is_visible_in_tree() and str(cp.doc.get("cutscene_id", "")) == "cutscene.intro",
		"cutscene tab opens cutscene.intro (%d steps)" % cp._step_count()) else 1
	cp.select_step(2)
	await _frames(cp, 4)
	await shot.call("editor_10_cutscene_intro")
	# new cutscene with every step type
	fails += 0 if _check(cp.create_cutscene(CUT_ID, "에디터 자체 점검 컷씬"), "create " + CUT_ID) else 1
	cp.select_step(cp._step_count() - 1)
	for t: String in CutsceneData.ORDER:
		cp.add_step(t)
	var types := PackedStringArray()
	for st: Dictionary in cp.doc["steps"]:
		types.append(st["type"])
	fails += 0 if _check(cp._step_count() == 2 + CutsceneData.ORDER.size(), "added every step type: " + ", ".join(types)) else 1
	# empty texts / flag key are errors
	var errs := cp.validate(false)
	fails += 0 if _check(errs >= 4, "validator caught %d errors (empty narration/line/caption/flag key)" % errs) else 1
	for st: Dictionary in cp.doc["steps"]:
		match st["type"]:
			"narration":
				st["text"] = "점검 내레이션\n두 번째 줄"
			"line":
				st["speaker_id"] = "player"
				st["expression"] = "surprised"
				st["text"] = "점검 대사"
			"caption":
				st["text"] = "점검 자막"
			"set_flag":
				st["key"] = "test.cutscene_editor"
			"image":
				st["path"] = "res://assets/ui/title_background.webp"
			"quest":
				st["quest_id"] = "quest.main.audience"
	cp._commit()
	var cut_errs := cp.validate(false)
	fails += 0 if _check(cut_errs == 0, "after fixes: %d errors (%d warnings)" % [cut_errs, cp.issues.size()]) else 1
	# reorder + undo / redo
	var first := str(cp.doc["steps"][0]["type"])
	cp.move_step(0, 1)
	var moved := str(cp.doc["steps"][1]["type"]) == first
	cp.undo()
	var undone := str(cp.doc["steps"][0]["type"]) == first
	cp.redo()
	fails += 0 if _check(moved and undone and str(cp.doc["steps"][1]["type"]) == first, "move step, undo, redo") else 1
	# save -> reload identical
	var ok := cp.save(true, true)
	var before := var_to_str(CutsceneData.normalized(cp.doc))
	cp.open_cutscene("cutscene.intro")
	cp.open_cutscene(CUT_ID)
	var after := var_to_str(CutsceneData.normalized(cp.doc))
	fails += 0 if _check(ok and before == after and after.contains("두 번째 줄"), "save → reload: steps, fields and Korean text identical") else 1
	# new-game order on, then restored
	cp.story_add(CUT_ID)
	var added := CUT_ID in CutsceneData.new_game_cutscenes()
	CutsceneData.set_new_game_cutscenes(story_before)
	cp.refresh_list()
	fails += 0 if _check(added and CutsceneData.new_game_cutscenes() == story_before, "new-game order: add → data/story.json, restored") else 1
	# preview plays every step to the end (keys pressed for narration / lines)
	cp.select_step(3)
	await _frames(cp, 3)
	await shot.call("editor_11_cutscene_steps")
	cp.preview_start(0)
	var t := 0
	var shot_taken := false
	while (cp.previewing or t < 10) and t < 1200:
		await _frames(cp, 1)
		t += 1
		if cp.previewing and not shot_taken and cp.preview_step >= 0 and cp.doc["steps"][cp.preview_step]["type"] == "line":
			await _frames(cp, 4)
			await shot.call("editor_12_cutscene_preview_line")
			shot_taken = true
		if t % 20 == 0:
			cp.preview_next()
	fails += 0 if _check(not cp.previewing and shot_taken, "preview played all %d steps (%d frames)" % [cp._step_count(), t]) else 1
	# cleanup
	cp.open_cutscene("cutscene.intro")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CutsceneData.path_for(CUT_ID)))
	cp.refresh_list()
	dpanel._mode_tabs.current_tab = 0
	return fails
