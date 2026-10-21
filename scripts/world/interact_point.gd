class_name InteractPoint
extends Node3D
## Generic interaction target (E, optional R). The player picks the nearest one in range and
## the HUD shows its prompt. Callables keep the owning world in charge of what happens.
##
## Interactables (this class, LootContainer, CatCompanion) share the duck-typed API:
##   interact_range: float, prompt_text() -> String, interact(player),
##   optional alt_prompt_text() -> String, interact_alt(player), can_interact() -> bool

var interact_range := 1.6
var prompt := ""
var action: Callable
var alt_prompt := ""
var alt_action: Callable
## Optional Callable() -> bool (e.g. only while the camper is owned).
var enabled_func: Callable
## Optional Callable() -> String for a prompt that changes (e.g. shop open / closed).
var prompt_func: Callable


## Crafting facility (GDD 14.4): opens the recipe panel for that facility type.
static func facility(parent: Node, pos: Vector3, kind: String, label: String) -> InteractPoint:
	var ip := make(parent, pos, "E %s — 요리·제작" % label, Callable(), 1.5)
	ip.add_to_group("facility")
	ip.set_meta("facility", kind)
	ip.action = func(_p: Node) -> void: Game.hud.open_crafting(kind, ip)
	return ip


static func make(parent: Node, pos: Vector3, text: String, cb: Callable, radius := 1.6) -> InteractPoint:
	var ip := InteractPoint.new()
	ip.prompt = text
	ip.action = cb
	ip.interact_range = radius
	ip.position = pos
	parent.add_child(ip)
	return ip


func _ready() -> void:
	add_to_group("interactable")


func can_interact() -> bool:
	return visible and (not enabled_func.is_valid() or enabled_func.call())


func prompt_text() -> String:
	return prompt_func.call() if prompt_func.is_valid() else prompt


func interact(player: Node) -> void:
	if action.is_valid():
		action.call(player)


func alt_prompt_text() -> String:
	return alt_prompt


func interact_alt(player: Node) -> void:
	if alt_action.is_valid():
		alt_action.call(player)
