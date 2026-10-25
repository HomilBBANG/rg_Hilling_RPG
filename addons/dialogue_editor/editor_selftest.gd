@tool
class_name DialogueEditorSelftest
extends RefCounted
## Scripted walk through the editor: open, inspect, preview with sandbox states, build a new
## dialogue from scratch (all node types), catch validation errors, fix, save, reload and compare,
## undo / redo, copy / paste, then clean up. Run inside the real editor (plugin.gd, env
## DIALOGUE_EDITOR_SELFTEST) and inside the game (--tour=dialogue_editor). Prints [editor] lines.

const TEST_ID := "dialogue.test.editor_selftest"
const CUT_ID := "cutscene.test.editor_selftest"
const AI_ID := "ai.test.editor_selftest"
const QUEST_ID := "quest.test.editor_selftest"


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
	# 3b. the end explanation lists the conditions passed, and its button flips the test state
	var flip: Button = null
	var cond_rows := 0
	for row in panel._prev_choices.get_children():
		if row is HBoxContainer:
			cond_rows += 1
			for c in row.get_children():
				if c is Button and flip == null:
					flip = c
	fails += 0 if _check(cond_rows >= 1 and flip != null and flip.text.contains("바꿔 다시 보기"), "preview end explains %d condition(s) with a flip button" % cond_rows) else 1
	if flip:
		flip.pressed.emit()
		await _frames(panel, 2)
		var ev := panel.preview_event()
		fails += 0 if _check(ev.get("type", "") == "line" and str(ev.get("text", "")).contains("젤리"), "flip → sandbox quest ready → reward branch opens: %s" % str(ev.get("text", "")).split("\n")[0]) else 1
	# 3c. the flag catalog knows code flags and dialogue-set flags
	var fc := FlagCatalog.all()
	var bron: Dictionary = fc.get("bron.trust", {})
	fails += 0 if _check(fc.has("story.wanted") and fc["story.wanted"]["set_by"].has("게임 코드") and not bron.is_empty()
		and " ".join(bron.get("set_by", PackedStringArray())).contains("대화") and " ".join(bron.get("used_by", PackedStringArray())).contains("대화"),
		"flag catalog: %d flags; story.wanted ← 게임 코드, bron.trust ← %s" % [fc.size(), ", ".join(bron.get("set_by", PackedStringArray()))]) else 1
	var dlg := EditorWidgets.show_flag_list(panel)
	await _frames(panel, 3)
	await shot.call("editor_06_flag_list")
	dlg.hide()
	dlg.queue_free()
	var help := EditorHelp.show(panel, "dialogue")
	await _frames(panel, 3)
	await shot.call("editor_07_help")
	help.hide()
	help.queue_free()
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
	fails += await _monster_ai_checks(panel, shot)
	fails += await _quest_checks(panel, shot)
	fails += await _map_checks(panel, shot)
	fails += await _region_checks(panel, shot)
	EditorInterface.set_main_screen_editor("Dialogue")
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


## The 몬스터 AI tab: open the passive slime graph, simulate it, build a new graph (condition +
## action), catch the unconnected outputs, fix, undo / redo, save → reload, assign it to a monster
## in monsters.json (only that block changes; file restored afterwards), clean up.
static func _monster_ai_checks(dpanel: DialogueEditorPanel, shot: Callable) -> int:
	var fails := 0
	var ap := dpanel.monster_ai_panel
	var monsters_before := FileAccess.get_file_as_string(MonsterAI.MONSTERS_PATH)
	dpanel._mode_tabs.current_tab = 2
	ap.open_ai("ai.slime.passive")
	await _frames(ap, 6)
	fails += 0 if _check(ap.is_visible_in_tree() and ap.ai_id == "ai.slime.passive" and ap._views.size() == ap.doc["nodes"].size(),
		"몬스터 AI tab opens ai.slime.passive (%d nodes, %d links)" % [ap.doc["nodes"].size(), ap.doc["connections"].size()]) else 1
	fails += 0 if _check(ap.validate().is_empty(), "shipped passive graph validates clean") else 1
	# simulation: nobody hit it -> wander; hit + hero in reach -> attack; ally call alone -> still wander
	for k: String in MonsterAI.CHECKS:
		ap.set_sim(k, false)
	var r0: String = ap.run_sim()["node"]["action"]
	ap.set_sim("ally_called", true)
	var r1: String = ap.run_sim()["node"]["action"]
	ap.set_sim("provoked", true)
	ap.set_sim("player_in_reach", true)
	var r2: String = ap.run_sim()["node"]["action"]
	await _frames(ap, 3)
	await shot.call("editor_20_monster_ai_sim")
	fails += 0 if _check(r0 == "wander" and r1 == "wander" and r2 == "attack", "simulate passive: idle → %s, ally called → %s, hit + in reach → %s" % [r0, r1, r2]) else 1
	ap.open_ai("ai.slime.aggressive")
	ap.set_sim("provoked", false)
	ap.set_sim("player_in_reach", false)
	var r3: String = ap.run_sim()["node"]["action"]
	ap.set_sim("ally_called", false)
	ap.set_sim("player_near", true)
	var r4: String = ap.run_sim()["node"]["action"]
	fails += 0 if _check(r3 == "chase" and r4 == "chase" and ap.run_sim()["path"].has("e_spot"), "simulate aggressive: ally called → %s (joins), hero near → %s via 'engage'" % [r3, r4]) else 1
	# a new graph: start -> [hp low?] -> flee / wander
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MonsterAI.path_for(AI_ID)))
	fails += 0 if _check(ap.create_ai(AI_ID) and ap.ai_id == AI_ID and ap.doc["nodes"].size() == 2, "new AI: start → wander") else 1
	ap.select_node("start")
	var c := ap.add_node("condition", "hp_below")
	ap.connect_nodes("start", "next", c)
	var errs := ap.validate().filter(func(e: Dictionary) -> bool: return e["severity"] == "error")
	fails += 0 if _check(errs.size() == 2, "unconnected 예 / 아니오 caught (%s)" % ", ".join(errs.map(func(e: Dictionary) -> String: return e["message"]))) else 1
	ap.select_node(c)
	var f := ap.add_node("action", "flee")
	ap.connect_nodes(c, "false", "a_wander")
	ap.set_param(f, "step", 2.5)
	ap.set_param(c, "percent", 45.0)
	ap.arrange()
	fails += 0 if _check(ap.validate().is_empty() and MonsterAI.next_of(ap.doc, c, "true") == f, "fixed: %s 예 → %s, 아니오 → a_wander, no issues" % [c, f]) else 1
	ap.set_sim("hp_below", true)
	var r5: String = ap.run_sim()["node"]["action"]
	ap.set_sim("hp_below", false)
	var r6: String = ap.run_sim()["node"]["action"]
	fails += 0 if _check(r5 == "flee" and r6 == "wander", "simulate new graph: hp low → %s, otherwise → %s" % [r5, r6]) else 1
	ap.set_kind(f, "idle")
	var kind_changed := str(MonsterAI.node(ap.doc, f).get("action", "")) == "idle"
	ap.undo()
	var undone := str(MonsterAI.node(ap.doc, f).get("action", "")) == "flee" and is_equal_approx(MonsterAI.param(MonsterAI.node(ap.doc, f), "step"), 2.5)
	ap.redo()
	var redone := str(MonsterAI.node(ap.doc, f).get("action", "")) == "idle"
	ap.undo()
	fails += 0 if _check(kind_changed and undone and redone, "change action kind → undo → redo") else 1
	ap.select_node(f)
	await _frames(ap, 4)
	await shot.call("editor_21_monster_ai_new_graph")
	var before := JSON.stringify(ap.doc)
	var saved_ok := ap.save()
	ap.dirty = false
	ap.open_ai("ai.slime.passive")
	ap.open_ai(AI_ID)
	fails += 0 if _check(saved_ok and JSON.stringify(ap.doc) == before and ap.validate().is_empty(), "save → reload: nodes, links, settings and positions identical") else 1
	# the game reads it the same way
	MonsterAI.clear_cache()
	var g := MonsterAI.load_graph(AI_ID)
	fails += 0 if _check(is_equal_approx(MonsterAI.param(MonsterAI.node(g, c), "percent"), 45.0), "MonsterAI.load_graph sees the saved settings") else 1
	# assign it to a monster: only that block of monsters.json changes
	var ok := ap.assign_monster("meadow_slime", AI_ID, true)
	var after_text := FileAccess.get_file_as_string(MonsterAI.MONSTERS_PATH)
	var changed_lines := 0
	var a_lines := after_text.split("\n")
	var b_lines := monsters_before.split("\n")
	for i in mini(a_lines.size(), b_lines.size()):
		changed_lines += 1 if a_lines[i] != b_lines[i] else 0
	fails += 0 if _check(ok and MonsterAI.ai_for("meadow_slime") == AI_ID and MonsterDB.info("meadow_slime").get("aggressive", false) == true \
			and a_lines.size() == b_lines.size() + 1 and after_text.contains('"hp": 9,'),
		"assign to 풀밭 슬라임 → monsters.json: +1 line (\"ai\"), 선공 flag, numbers untouched") else 1
	ap.assign_monster("meadow_slime", "", false)
	fails += 0 if _check(FileAccess.get_file_as_string(MonsterAI.MONSTERS_PATH) == monsters_before, "unassign → monsters.json back to the original text") else 1
	await _frames(ap, 3)
	await shot.call("editor_22_monster_ai_monsters")
	# cleanup
	var fw := FileAccess.open(MonsterAI.MONSTERS_PATH, FileAccess.WRITE)
	fw.store_string(monsters_before)
	fw.close()
	MonsterDB.reload()
	ap.dirty = false
	ap.open_ai("ai.slime.passive")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MonsterAI.path_for(AI_ID)))
	ap.refresh_list()
	ap.refresh_monsters()
	dpanel._mode_tabs.current_tab = 0
	return fails


## The Map editor's 지도 표시물 tab: open the meadow map, add / edit / move / undo a mark, add a field
## drop placed with a canvas click, save → reload identical, the game-side MapDB sees it, then restore
## the file.
static func _map_checks(_dpanel: DialogueEditorPanel, shot: Callable) -> int:
	var fails := 0
	if MapEditorPlugin.instance == null:
		return 0 if _check(false, "Map editor plugin is enabled") else 1
	var mp: MapEditorPanel = MapEditorPlugin.instance.map_panel
	var before := FileAccess.get_file_as_string(MapDB.path_for("meadow"))
	EditorInterface.set_main_screen_editor("Map")
	MapEditorPlugin.instance.tabs.current_tab = 1
	mp.open_map("meadow")
	await _frames(mp, 6)
	fails += 0 if _check(mp.is_visible_in_tree() and mp.region == "meadow" and mp.validate().is_empty(),
		"지도 tab opens the meadow map (%d marks, %d sources, no issues)" % [mp.doc["marks"].size(), mp.doc["sources"].size()]) else 1
	await shot.call("editor_30_map_meadow")
	var n0: int = mp.doc["marks"].size()
	mp.start_place("icon")
	mp.canvas_click(mp.to_canvas(Vector2(10, -20)))
	var id := mp.selected
	var m := mp.mark(id)
	fails += 0 if _check(mp.doc["marks"].size() == n0 + 1 and m.get("type", "") == "icon" and is_equal_approx(float(m["pos"][0]), 10.0),
		"place an icon with a canvas click at (10, -20) -> %s" % id) else 1
	mp.set_mark_field(id, "icon", "quest")
	mp.set_mark_field(id, "text", "에디터 시험 표시")
	mp.move_mark(id, Vector2(12.5, -18))
	var moved: Array = mp.mark(id)["pos"]
	mp.undo()
	var undone: Array = mp.mark(id)["pos"]
	mp.redo()
	fails += 0 if _check(moved == [12.5, -18.0] and undone == [10.0, -20.0] and mp.mark(id)["pos"] == [12.5, -18.0],
		"edit icon / text, move → undo → redo") else 1
	var si := mp.add_source("drop")
	mp.start_place("drop:%d" % si)
	mp.canvas_click(mp.to_canvas(Vector2(-40, 30)))
	var drop: Dictionary = mp.doc["sources"][si]
	fails += 0 if _check(drop.get("region", "") == "meadow" and drop["pos"] == [-40.0, 30.0], "field drop placed with a canvas click at (-40, 30)") else 1
	var bad := mp.add_source("shop")
	mp.set_source_field(bad, "shop", "nobody")
	var errs := mp.validate().filter(func(e: Dictionary) -> bool: return e["severity"] == "error")
	mp.remove_source(bad)
	fails += 0 if _check(errs.size() == 1 and mp.validate().is_empty(), "unknown shop caught (%s), fixed" % (errs[0]["message"] if not errs.is_empty() else "-")) else 1
	await _frames(mp, 3)
	await shot.call("editor_31_map_edited")
	var snap := JSON.stringify(mp.doc)
	var ok := mp.save()
	mp.open_map("highland")
	mp.open_map("meadow")
	fails += 0 if _check(ok and JSON.stringify(mp.doc) == snap, "save → reload: marks, sources and positions identical") else 1
	MapDB.reload()
	var drops := MapDB.drops_in("meadow").filter(func(d: Dictionary) -> bool: return d["region"] == "meadow")
	fails += 0 if _check(drops.size() == 1 and MapDB.info("meadow")["marks"].size() == n0 + 1, "game-side MapDB sees the new mark and the drop") else 1
	# restore
	var f := FileAccess.open(MapDB.path_for("meadow"), FileAccess.WRITE)
	f.store_string(before)
	f.close()
	mp.dirty = false
	mp.open_map("meadow")
	fails += 0 if _check(FileAccess.get_file_as_string(MapDB.path_for("meadow")) == before, "meadow map file restored") else 1
	return fails


## The Map editor's 지역 배치 tab: open the meadow, move the new-character start (drag on the picture +
## the number fields), place a monster with a click, edit / move / undo / redo it, catch a bad monster
## kind and an exit to a missing arrival point, add a road point, save → reload identical and the
## game-side RegionDB sees it, then restore the file.
static func _region_checks(_dpanel: DialogueEditorPanel, shot: Callable) -> int:
	var fails := 0
	if MapEditorPlugin.instance == null:
		return 1
	var rp: RegionEditorPanel = MapEditorPlugin.instance.region_panel
	var before := FileAccess.get_file_as_string(RegionDB.path_for("meadow"))
	EditorInterface.set_main_screen_editor("Map")
	MapEditorPlugin.instance.tabs.current_tab = 0
	rp.dirty = false
	rp.open_region("meadow")
	await _frames(rp, 12)
	var open_errs := _errors(rp.validate())
	fails += 0 if _check(rp.is_visible_in_tree() and rp.region_id == "meadow" and open_errs.is_empty() and rp.doc.has("default_spawn"),
		"지역 배치 tab opens the meadow (%d monsters, %d exits, errors: %s)" % [rp.doc["monsters"].size(), rp.doc["exits"].size(),
		", ".join(open_errs.map(func(e: Dictionary) -> String: return str(e["message"])))]) else 1
	await shot.call("editor_50_region_meadow")
	var spawn0: Array = rp.doc["default_spawn"]["pos"].duplicate()
	rp.canvas_click(rp.to_canvas(rp.sel_pos({"list": "spawn"})))
	fails += 0 if _check(rp.sel.get("list", "") == "spawn", "clicking the red arrow selects the new-character start") else 1
	rp.set_sel_pos({"list": "spawn"}, Vector2(6.0, 2.0))
	var moved: Array = rp.doc["default_spawn"]["pos"]
	rp.undo()
	var undone: Array = rp.doc["default_spawn"]["pos"]
	rp.redo()
	fails += 0 if _check(moved == [6.0, 2.0] and undone == spawn0 and rp.doc["default_spawn"]["pos"] == [6.0, 2.0],
		"move the start to (6, 2) → undo → redo (was %s)" % [spawn0]) else 1
	var n0: int = rp.doc["monsters"].size()
	rp.start_place("monsters")
	rp.canvas_click(rp.to_canvas(Vector2(20, -10)))
	var m: Dictionary = rp.doc["monsters"][n0] if rp.doc["monsters"].size() > n0 else {}
	fails += 0 if _check(rp.doc["monsters"].size() == n0 + 1 and rp.sel.get("index", -1) == n0 and m.get("pos", []) == [20.0, -10.0] and MonsterDB.all().has(str(m.get("kind", ""))),
		"place a monster with a click at (20, -10) -> %s %s" % [m.get("id", ""), m.get("kind", "")]) else 1
	m["kind"] = "no_such_monster"
	rp._commit()
	var errs := _errors(rp.validate())
	m["kind"] = "meadow_slime"
	rp._commit()
	fails += 0 if _check(errs.size() == 1 and _errors(rp.validate()).is_empty(), "unknown monster kind caught (%d: %s), fixed" % [errs.size(), errs[0]["message"] if not errs.is_empty() else "-"]) else 1
	var ex: Dictionary = rp.doc["exits"][0]
	var entry0 := str(ex["to_entry"])
	ex["to_entry"] = "nowhere"
	rp._commit()
	var errs2 := _errors(rp.validate())
	ex["to_entry"] = entry0
	rp._commit()
	fails += 0 if _check(errs2.size() == 1 and _errors(rp.validate()).is_empty(), "exit to a missing arrival point caught (%d: %s), fixed" % [errs2.size(), errs2[0]["message"] if not errs2.is_empty() else "-"]) else 1
	var paths: Array = rp.doc["terrain"]["paths"]
	var np0: int = (paths[0] as Array).size()
	rp.sel = {"list": "path", "index": 0, "point": np0 - 1}
	rp.add_at("point", Vector2(-30, 25))
	fails += 0 if _check((paths[0] as Array).size() == np0 + 1 and rp.sel.get("point", -1) == np0, "add a road point at the end of road 1") else 1
	await _frames(rp, 3)
	await shot.call("editor_51_region_edited")
	var snap := JSON.stringify(rp.doc)
	var ok := rp.save()
	rp.open_region("highland")
	rp.open_region("meadow")
	fails += 0 if _check(ok and JSON.stringify(rp.doc) == snap, "save → reload: start, monster, exits and roads identical") else 1
	var game_side: Dictionary = RegionDB.all()["meadow"]
	fails += 0 if _check(game_side["default_spawn"]["pos"] == [6.0, 2.0] and game_side["monsters"].size() == n0 + 1, "game-side RegionDB sees the moved start and the new monster") else 1
	var f := FileAccess.open(RegionDB.path_for("meadow"), FileAccess.WRITE)
	f.store_string(before)
	f.close()
	RegionDB.reload()
	MapDB.clear_caches()
	rp.dirty = false
	rp.open_region("meadow")
	fails += 0 if _check(FileAccess.get_file_as_string(RegionDB.path_for("meadow")) == before and rp.doc["default_spawn"]["pos"] == spawn0, "meadow region file restored") else 1
	return fails


static func _errors(issues: Array) -> Array:
	return issues.filter(func(e: Dictionary) -> bool: return e["severity"] == "error")


## The 퀘스트 tab: open Rosa's quest (where-used finds her dialogue), every shipped quest validates
## without errors, build a new field event with every objective type, catch a bad item / unknown
## monster / duplicate id / missing trigger, fix, place the trigger with a click on the picture,
## rewards + an outcome branch, undo / redo, save → reload identical, the game-side QuestDB sees
## it, delete the file.
static func _quest_checks(dpanel: DialogueEditorPanel, shot: Callable) -> int:
	var fails := 0
	var qp := dpanel.quest_panel
	dpanel._mode_tabs.current_tab = 3
	qp.open_quest("quest.rosa.jelly")
	await _frames(qp, 6)
	fails += 0 if _check(qp.is_visible_in_tree() and qp.quest_id == "quest.rosa.jelly" and _errors(qp.validate()).is_empty(),
		"퀘스트 tab opens quest.rosa.jelly (%d objectives, used in %d places, no errors)" % [qp.doc["objectives"].size(), qp.refs.size()]) else 1
	var rosa_accept := false
	for r: Dictionary in qp.refs:
		rosa_accept = rosa_accept or (r["id"] == "dialogue.npc.rosa.main" and r["action"] == "quest_accept")
	fails += 0 if _check(rosa_accept, "where-used lists dialogue.npc.rosa.main → 퀘스트 수락") else 1
	var bad := PackedStringArray()
	for id: String in QuestDB.all():
		if not _errors(QuestDB.validate(QuestDB.all()[id], QuestDB.references(id))).is_empty():
			bad.append(id)
	fails += 0 if _check(bad.is_empty(), "every shipped quest validates without errors (%d files)%s" % [QuestDB.all().size(), "" if bad.is_empty() else ": " + ", ".join(bad)]) else 1
	await shot.call("editor_40_quest_rosa")
	# a new field event with every objective type
	if FileAccess.file_exists(QuestDB.path_for(QUEST_ID)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(QuestDB.path_for(QUEST_ID)))
	fails += 0 if _check(not qp.create_quest("bad id", "x") and qp.create_quest(QUEST_ID, "에디터 자체 점검 퀘스트") and qp.quest_id == QUEST_ID,
		"bad id refused, create %s" % QUEST_ID) else 1
	qp.set_field("source", "event", true)
	qp.set_field("giver", "bron")
	qp.set_accept("auto")
	qp.add_objective("collect")
	qp.add_objective("kill")
	qp.add_objective("flag")
	qp.set_objective_field(1, "item", "nope")
	qp.set_objective_field(2, "target", "zzz")
	qp.set_objective_field(3, "id", "obj_1")
	qp.doc.erase("trigger")
	qp._commit(true)
	var errs := _errors(qp.validate())
	var msgs := PackedStringArray()
	for e: Dictionary in errs:
		msgs.append(e["message"])
	var text := " / ".join(msgs)
	fails += 0 if _check(errs.size() >= 4 and text.contains("nope") and text.contains("zzz") and text.contains("겹치") and text.contains("시작 조건"),
		"validator caught %d errors: %s" % [errs.size(), text]) else 1
	# fix everything
	qp.set_accept("direct")
	qp.set_accept("auto")
	qp.set_objective_field(1, "item", "herb")
	qp.set_objective_field(2, "target", "meadow")
	qp.set_objective_field(3, "id", "obj_4")
	qp.set_objective_field(3, "flag", "story.arrived")
	for i in 4:
		qp.set_objective_field(i, "text", "목표 %d" % (i + 1))
	qp.set_field("desc", "자체 점검용 현장 사건.")
	fails += 0 if _check(_errors(qp.validate()).is_empty() and qp.doc.has("trigger"), "after fixes: 0 errors (%d warnings), trigger back" % qp.issues.size()) else 1
	# trigger placed with a click on the region picture
	await _frames(qp, 4)
	qp.place = true
	qp._fit()
	qp.canvas_click(qp.to_canvas(Vector2(40, -5)))
	var tp: Array = qp.doc["trigger"]["pos"]
	fails += 0 if _check(absf(float(tp[0]) - 40.0) < 0.3 and absf(float(tp[1]) + 5.0) < 0.3 and qp.doc["trigger"]["region"] == "meadow",
		"trigger placed with a canvas click at (40, -5) -> (%s, %s)" % [tp[0], tp[1]]) else 1
	var scale0: float = qp._zoom.scale
	qp.zoom_in(3.0)
	await _frames(qp, 2)
	qp.place = true
	qp.canvas_click(qp.to_canvas(Vector2(41.3, -6.2)))
	var tp2: Array = qp.doc["trigger"]["pos"]
	fails += 0 if _check(qp._zoom.scale > scale0 * 2.5 and absf(float(tp2[0]) - 41.3) < 0.15 and absf(float(tp2[1]) + 6.2) < 0.15,
		"trigger picture zoomed ×3 (%.2f → %.2f px/m), fine placement at (41.3, -6.2) -> (%s, %s)" % [scale0, qp._zoom.scale, tp2[0], tp2[1]]) else 1
	qp._reveal_canvas()
	await _frames(qp, 4)
	await shot.call("editor_43_quest_trigger_zoom")
	qp.place = true
	qp.canvas_click(qp.to_canvas(Vector2(40, -5)))
	# rewards and an outcome branch
	qp.set_reward("", "gold", 25)
	var it := qp.add_reward_item("")
	qp.set_reward_item("", "bread", 2, it)
	var oc := qp.add_outcome()
	qp.rename_outcome(oc, "reward")
	qp.set_outcome_label("reward", "사례를 받음")
	qp.set_reward("reward", "life_exp", 12)
	fails += 0 if _check(qp.doc["rewards"]["items"] == {"bread": 2} and int(qp.doc["rewards"]["gold"]) == 25 and qp.doc["outcomes"].has("reward") \
			and int(qp.doc["outcomes"]["reward"]["rewards"]["life_exp"]) == 12 and _errors(qp.validate()).is_empty(),
		"rewards: 25 gold + bread ×2, outcome 'reward' (life EXP 12)") else 1
	# undo / redo
	var n: int = qp.doc["objectives"].size()
	qp.add_objective("count")
	qp.undo()
	var after_undo: int = qp.doc["objectives"].size()
	qp.redo()
	var after_redo: int = qp.doc["objectives"].size()
	qp.undo()
	fails += 0 if _check(after_undo == n and after_redo == n + 1 and qp.doc["objectives"].size() == n, "add objective → undo → redo → undo: %d → %d → %d → %d" % [n + 1, after_undo, after_redo, n]) else 1
	await _frames(qp, 3)
	await shot.call("editor_41_quest_new_event")
	qp.scroll_to_end()
	await _frames(qp, 3)
	await shot.call("editor_42_quest_rewards_outcomes")
	# save → reload identical, game side sees it
	var snap := JSON.stringify(qp.doc)
	var ok := qp.save()
	qp.open_quest("quest.rosa.jelly")
	qp.open_quest(QUEST_ID)
	fails += 0 if _check(ok and JSON.stringify(qp.doc) == snap, "save → reload: fields, objectives, trigger, rewards and outcomes identical") else 1
	QuestDB.reload()
	var q := QuestDB.info(QUEST_ID)
	fails += 0 if _check(q.get("accept", "") == "auto" and q.get("trigger", {}).get("region", "") == "meadow" and int(QuestDB.rewards_for(QUEST_ID, "reward").get("life_exp", 0)) == 12 \
			and QuestDB.objective(QUEST_ID, "obj_4").get("type", "") == "flag" and QuestDB.reward_text(QuestDB.rewards_for(QUEST_ID)).contains("빵"),
		"game-side QuestDB: auto trigger in meadow, outcome rewards, objective obj_4 = flag, reward text '%s'" % QuestDB.reward_text(QuestDB.rewards_for(QUEST_ID))) else 1
	# delete
	qp.delete_quest(QUEST_ID)
	fails += 0 if _check(not FileAccess.file_exists(QuestDB.path_for(QUEST_ID)) and qp.quest_id != QUEST_ID and not QuestDB.all().has(QUEST_ID), "delete → file gone, another quest open") else 1
	dpanel._mode_tabs.current_tab = 0
	return fails
