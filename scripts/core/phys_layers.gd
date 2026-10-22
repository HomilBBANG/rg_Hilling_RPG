class_name PhysLayers
extends RefCounted
## Physics layers, one place (user request: nothing walks through NPCs, monsters, the cat, big
## rocks, trees, the camper or buildings). Static obstacles — trees' trunks, big rocks, buildings,
## walls, props, the parked camper — are on WORLD; moving bodies each have their own layer and
## list what stops them in their mask.

const WORLD := 1          ## layer 1: terrain props, buildings, walls, the camper body
const PLAYER := 1 << 1    ## layer 2: the hero
const MONSTER := 1 << 2   ## layer 3: slimes, the dragon
const CAT := 1 << 3       ## layer 4: the black cat
const NPC := 1 << 4       ## layer 5: villagers, merchants, the king, vendors

const PLAYER_MASK := WORLD | MONSTER | CAT | NPC
const MONSTER_MASK := WORLD | MONSTER | PLAYER | CAT | NPC
const CAT_MASK := WORLD | MONSTER | PLAYER | NPC
const CAMPER_MASK := WORLD | NPC  ## driving: blocked by the world and people; monsters get rammed
