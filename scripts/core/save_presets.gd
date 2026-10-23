class_name SavePresets
extends RefCounted
## Ready-made saves for trying later parts of the game without replaying (user request).
## Built in code from the live game rules (quests completed through the quest manager, levels
## through level-ups...), so a preset always matches the current save format. Installing writes
## it into a slot; the game state from before is put back afterwards.
##
## "chapter1": chapter 1 cleared (user story) — king's audience, the dragon talked out of its nest,
## the camper wished for and fallen on the king, wanted, escaped through the south gate (story
## stage C, the cat along); standing in the meadow at the end of the north road beside the camper,
## the capital closed for good. Goes into slot 3 by itself the first time the title opens with
## slot 3 empty; the load screen can put it in again.

static var marker := "user://presets.cfg"  ## remembers which presets were put in once
const PRESETS := {"chapter1": {"slot": 3, "name": "1챕터 클리어 — 캠핑카·고양이"}}


static func preset_name(id: String) -> String:
	return str(PRESETS.get(id, {}).get("name", id))


## First title screen with the preset's slot empty: put it there once (a later delete is respected).
static func auto_install() -> void:
	var cf := ConfigFile.new()
	cf.load(marker)
	for id: String in PRESETS:
		var slot := int(PRESETS[id]["slot"])
		if cf.get_value("installed", id, false) or SaveManager.exists(slot):
			continue
		if install(id, slot):
			cf.set_value("installed", id, true)
	cf.save(marker)


## Writes preset id into slot (overwriting it). Returns true when written.
static func install(id: String, slot: int) -> bool:
	var keep := SaveManager.capture_state()
	var keep_run := Game.run
	var keep_spawn := Game.spawn_override
	var keep_prev := Game.previous_world
	var data := {}
	match id:
		"chapter1":
			data = _chapter1()
	SaveManager.apply_state(keep)
	Game.run = keep_run
	Game.spawn_override = keep_spawn
	Game.previous_world = keep_prev
	if data.is_empty():
		return false
	var ok := SaveManager.write(slot, data)
	var cf := ConfigFile.new()
	cf.load(marker)
	cf.set_value("installed", id, true)
	cf.save(marker)
	return ok


static func _chapter1() -> Dictionary:
	SaveManager.apply_state({})  # a fresh character, then play chapter 1 through on paper
	var st := Game.player_state
	var q := Game.quests
	var n := Game.narrative
	Game.day = 4
	Game.minute_of_day = 10.0 * 60.0 + 30.0
	Game.play_seconds = 2.0 * 3600.0 + 40.0 * 60.0
	# story: arrival, the king, the road and the nest, the dragon persuaded, the wish, the escape
	for f in ["story.new_game_seen", "story.arrived", "story.pass_reached", "story.dragon_signs",
			"story.nest_found", "story.nest_entered", "story.dragon_met", "story.dragon_left", "story.camper_received",
			"story.king_dead", "story.wanted", "story.escaped", "story.chapter1_done", "story.chapter1_note"]:
		n.set_flag(f)
	n.mark_event("story.king_audience")
	n.mark_event("story.dragon_persuaded")
	n.mark_event("story.camper_wish")
	q.accept("quest.main.audience")
	q.advance("quest.main.audience", "audience")
	q.complete("quest.main.audience")
	q.accept("quest.main.dragon")
	q.complete("quest.main.dragon")  # objectives are flags (above)
	q.accept("quest.main.escape")
	q.advance("quest.main.escape", "gate")
	q.complete("quest.main.escape")
	Game.cat_joined = true
	Game.cat_affection = 40
	Game.maps_owned = ["meadow", "highland", "capital", "ashen_pass"]  # bought / found / the king's on the way
	Game.has_camper = true
	Game.camper = {"region": "meadow", "pos": Vector3(-17.4, 0.0, -79.5), "yaw": PI}  # out of the capital's gate
	Game.camper_fuel = Game.camper_fuel_max()
	Game.camper_durability = Game.CAMPER_DURABILITY_MAX
	# places seen on the way
	for k in ["region:meadow", "region:highland", "region:capital", "region:throne_room", "region:ashen_pass",
			"region:dragon_nest", "city:capital", "city:pinecone", "meadow:camp", "meadow:trade", "meadow:north_sign",
			"highland:village", "highland:pass", "ashen_pass:foot", "ashen_pass:camp", "ashen_pass:south_road",
			"trig:ashen_pass:arrive", "trig:ashen_pass:signs", "trig:ashen_pass:nest", "trig:dragon_nest:lair"]:
		Game.discovered[k] = true
	# the nest remembers its dragon: gone for good (flew off over the sea)
	var t := Game.total_minutes() - 600.0
	Game.fields["dragon_nest"] = {"dead": {}, "loot": [], "defeated": {"dragon_nest_D1": t}}
	# the hero at the end of chapter 1: EXP from the road (the dragon's came with its quest), levelled up, points spent
	st.add_exp(40)
	while st.can_level_up():
		st.level_up()
	var plan := ["STR", "STR", "VIT", "VIT", "END", "STR", "VIT", "END", "HLT", "STR"]
	var i := 0
	while st.stat_points > 0 and i < 40:
		st.add_stat(plan[i % plan.size()])
		i += 1
	for item in ["flame_longsword", "leather_armor", "leather_cap", "sturdy_boots"]:
		st.inventory.add(item, 1)
		st.equip(item)
	for spec in [["dragon_token", 1], ["mana_shard", 2], ["heal_potion", 4], ["mana_potion", 1],
			["stamina_potion", 1], ["bread", 3], ["cat_snack", 4]]:
		st.inventory.add(str(spec[0]), int(spec[1]))
	for spec in [["fuel_can", 2], ["repair_kit", 1], ["slime_jelly", 6], ["iron_ore", 2], ["firewood", 3]]:
		Game.storage.add(str(spec[0]), int(spec[1]))  # spares in the camper's storage
	st.gold += 380
	st.life_exp += 18
	st.restore_all()
	Game.region = "meadow"
	var data := SaveManager.capture(String(Game.WORLD_EXTERIOR), Vector3(-20.0, 0.0, -76.5), PI)
	data["meta"]["saved_at"] = "준비된 세이브 — " + preset_name("chapter1")
	return data
