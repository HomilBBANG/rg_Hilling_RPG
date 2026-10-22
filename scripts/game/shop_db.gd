class_name ShopDB
extends RefCounted
## Shops (GDD 16 [확정]): gold, prices differ by merchant speciality, common goods sell to most
## merchants, rare goods only to specialists, limited stock that restocks on a fixed game-day
## cycle (16.2: common materials 1 day, rare materials / special equipment 3 days [임시]).
## No dynamic economy. Stock lists, prices, hours and the other numbers are [미정] placeholders.

## stock entry: [item id, list price, max stock, restock group]
const SHOPS := {
	"rosa": {
		"name": "로사의 잡화점", "keeper": "로사", "open": 8 * 60, "close": 20 * 60,
		"stock": [
			["heal_potion", 25, 5, "consumable"], ["stamina_potion", 20, 3, "consumable"],
			["mana_potion", 30, 3, "consumable"], ["bread", 6, 8, "consumable"],
			["canned_food", 10, 4, "consumable"], ["cat_snack", 5, 10, "consumable"],
			["firewood", 4, 6, "material"], ["fishing_rod", 35, 2, "equip"], ["fuel_can", 30, 4, "consumable"],
		],
		# share of the item value paid when the player sells; 0 = doesn't buy
		"buy_rates": {"common": 0.5, "rare": 0.0, "equip": 0.2},
	},
	"bron": {
		"name": "브론의 대장간", "keeper": "브론", "open": 9 * 60, "close": 18 * 60, "smith": true,
		"stock": [
			["iron_sword", 70, 2, "equip"], ["wooden_shield", 55, 1, "equip"], ["leather_cap", 40, 2, "equip"],
			["leather_gloves", 35, 2, "equip"], ["sturdy_boots", 45, 1, "equip"], ["leather_armor", 95, 1, "equip"],
			["flame_longsword", 320, 1, "equip"], ["iron_ore", 18, 4, "material"], ["mana_shard", 45, 2, "rare"],
			["repair_kit", 60, 2, "material"],
		],
		"buy_rates": {"common": 0.25, "rare": 0.6, "equip": 0.45},
		"special_rates": {"iron_ore": 0.7},  # its own speciality pays better
	},
}

const RESTOCK_DAYS := {"consumable": 1, "material": 1, "rare": 3, "equip": 3}


static func info(shop_id: String) -> Dictionary:
	return SHOPS[shop_id]


static func is_open(shop_id: String) -> bool:
	var s: Dictionary = SHOPS[shop_id]
	return Game.minute_of_day >= s["open"] and Game.minute_of_day < s["close"]


static func hours_text(shop_id: String) -> String:
	var s: Dictionary = SHOPS[shop_id]
	return "%02d:00~%02d:00" % [int(s["open"]) / 60, int(s["close"]) / 60]


## Runtime stock, kept in Game.shops across scene reloads.
static func state(shop_id: String) -> Dictionary:
	if not Game.shops.has(shop_id):
		var left := {}
		var last := {}
		for e: Array in SHOPS[shop_id]["stock"]:
			left[e[0]] = e[2]
			last[e[3]] = Game.total_minutes()
		Game.shops[shop_id] = {"left": left, "last": last}
	return Game.shops[shop_id]


## Refill each restock group whose period has passed, counted from its last restock
## ("since the last delivery", not a midnight reset - that detail is [미정]).
static func restock(shop_id: String) -> void:
	var st := state(shop_id)
	var now := Game.total_minutes()
	for group: String in st["last"]:
		var period: float = RESTOCK_DAYS[group] * 1440.0
		var elapsed: float = now - st["last"][group]
		if elapsed >= period:
			st["last"][group] += floorf(elapsed / period) * period
			for e: Array in SHOPS[shop_id]["stock"]:
				if e[3] == group:
					st["left"][e[0]] = e[2]


static func stock_left(shop_id: String, item: String) -> int:
	return state(shop_id)["left"].get(item, 0)


## Gold the merchant pays for one unit (0 = this merchant doesn't buy it).
static func sell_price(shop_id: String, item: String) -> int:
	var s: Dictionary = SHOPS[shop_id]
	var rate: float = s.get("special_rates", {}).get(ItemDB.base_id(item), s["buy_rates"].get(ItemDB.category(item), 0.0))
	if rate <= 0.0:
		return 0
	return maxi(1, roundi(ItemDB.value(item) * rate))


## Buy one unit; returns "" on success or the reason it failed.
static func buy(shop_id: String, item: String, price: int) -> String:
	var ps := Game.player_state
	if stock_left(shop_id, item) <= 0:
		return "재고가 없다"
	if ps.gold < price:
		return "골드가 부족하다"
	if not ps.can_carry(ItemDB.weight(item)):
		return "너무 무겁다 — 더 들 수 없다"
	ps.gold -= price
	state(shop_id)["left"][item] -= 1
	ps.inventory.add(item, 1)
	return ""


static func sell(shop_id: String, item: String) -> int:
	var price := sell_price(shop_id, item)
	var ps := Game.player_state
	if price <= 0 or ps.inventory.remove(item, 1) <= 0:
		return 0
	ps.gold += price
	ps.changed.emit()
	return price
