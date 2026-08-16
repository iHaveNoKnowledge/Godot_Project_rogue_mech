class_name PilotSystem
extends RefCounted

# -----------------------------------------------------------------------------
# PILOT SYSTEM — the player pilot's own condition, kept separate from the mech.
#
# The mech has its armor/frame HP; the pilot has their own body. This system
# owns the pilot's:
#   - HP (pilot_hp / pilot_max_hp) — reduced when the mech is destroyed in
#     battle or when combat goes badly; restored with healing items or rest.
#   - Personal weapons (pilot_weapons) — what the pilot carries on their body
#     (sidearm / backup), independent of the mech's weapon loadout.
#   - Personal ammo (pilot_ammo) — reserves for the pilot's own weapons.
#   - Items (pilot_items) — consumables such as medkits that heal the pilot.
#
# Healing items are bought from CITY board nodes (trading) and used from the
# intermission / safehouse screens. City shops also sell personal ammo.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# HEALING ITEM CATALOG — static definitions (single source of truth).
# Each entry: id, name, desc, heal (HP restored), price (credits at a city).
# -----------------------------------------------------------------------------
const HEAL_ITEMS: Array = [
	{
		"id": "medkit_small",
		"name": "Field Medkit",
		"desc": "A compact first-aid kit. Restores 30 pilot HP.",
		"heal": 30,
		"price": 50,
	},
	{
		"id": "medkit_medium",
		"name": "Combat Medkit",
		"desc": "Military-grade trauma kit. Restores 60 pilot HP.",
		"heal": 60,
		"price": 110,
	},
	{
		"id": "medkit_large",
		"name": "Surgical Kit",
		"desc": "A full field surgery kit. Restores the pilot to full HP.",
		"heal": 0,  # 0 = fully restores
		"price": 200,
	},
]

# Personal ammo sold at city nodes (type -> credits per unit).
const AMMO_PRICES: Dictionary = {
	"kinetic": 2,
	"energy": 3,
	"explosive": 8,
	"missile": 15,
}

const PILOT_MAX_HP_DEFAULT := 100.0

# Damage the pilot takes when their mech is destroyed and they eject.
const EJECT_DAMAGE := 35.0


static func get_heal_item(item_id: String) -> Dictionary:
	for item in HEAL_ITEMS:
		if str(item.get("id", "")) == item_id:
			return item
	return {}


# --- HP ----------------------------------------------------------------------

static func get_max_hp() -> float:
	return maxf(float(GlobalData.pilot_max_hp), 1.0)


static func get_hp() -> float:
	return clampf(float(GlobalData.pilot_hp), 0.0, get_max_hp())


# True while the pilot's HP is below full (needs healing).
static func is_injured() -> bool:
	return get_hp() < get_max_hp()


# PERMANENT DEATH: a pilot whose HP reaches 0 is dead, not merely wounded.
# Dead pilots cannot be healed and never fight again. This is the SAME rule
# for both sides — the player pilot (GlobalData.pilot_hp) and every ejected
# enemy pilot (their own HP pool) — so getting shot can end a pilot for good
# instead of the player always ejecting and fleeing.
static func is_dead() -> bool:
	return get_hp() <= 0.0


# Restores HP up to max. `amount <= 0` (or a "full restore" item) heals all.
# A dead pilot stays dead: healing does nothing.
static func heal(amount: float) -> float:
	if is_dead():
		return 0.0
	var restored: float
	if amount <= 0.0:
		restored = get_max_hp() - get_hp()
	else:
		restored = minf(amount, get_max_hp() - get_hp())
	GlobalData.pilot_hp = get_hp() + restored
	return restored


static func take_damage(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := get_hp()
	GlobalData.pilot_hp = maxf(before - amount, 0.0)
	return before - get_hp()


# Instantly kills the pilot (HP to 0).
static func kill() -> void:
	GlobalData.pilot_hp = 0.0


# The pilot ejects from a destroyed mech: they take eject damage. Wounded
# pilots survive (healable), but a pilot already badly hurt can be killed by
# the eject itself — HP hitting 0 is permanent death, exactly like being shot.
static func on_mecha_destroyed() -> void:
	take_damage(EJECT_DAMAGE)


# --- Pilot weapons -----------------------------------------------------------

# Pilot's personal weapons: an array of WeaponPart resource paths. Independent
# of the mech's weapon_loadout — this is what the pilot carries on their body.
static func get_weapons() -> Array:
	var result: Array = []
	for path in GlobalData.pilot_weapons:
		var wp := load(path) as WeaponPart
		if wp != null:
			result.append(wp)
	return result


static func add_weapon(path: String) -> void:
	if path == "" or GlobalData.pilot_weapons.has(path):
		return
	if ResourceLoader.exists(path):
		GlobalData.pilot_weapons.append(path)


static func remove_weapon(path: String) -> void:
	GlobalData.pilot_weapons.erase(path)


# --- Pilot ammo --------------------------------------------------------------

static func get_ammo(ammo_type: String) -> int:
	return int(GlobalData.pilot_ammo.get(ammo_type, 0))


static func get_ammo_dict() -> Dictionary:
	return GlobalData.pilot_ammo.duplicate()


static func add_ammo(ammo_type: String, amount: int) -> void:
	if amount <= 0:
		return
	GlobalData.pilot_ammo[ammo_type] = get_ammo(ammo_type) + amount


static func consume_ammo(ammo_type: String, amount: int) -> int:
	var current := get_ammo(ammo_type)
	var spent := mini(current, maxi(amount, 0))
	GlobalData.pilot_ammo[ammo_type] = current - spent
	return spent


# --- Items -------------------------------------------------------------------

# Returns the pilot's item inventory as an array of {id, count}.
static func get_items() -> Array:
	var result: Array = []
	for item_id in GlobalData.pilot_items:
		result.append({
			"id": str(item_id),
			"count": int(GlobalData.pilot_items[item_id]),
		})
	return result


static func get_item_count(item_id: String) -> int:
	return int(GlobalData.pilot_items.get(item_id, 0))


static func add_item(item_id: String, amount: int = 1) -> void:
	if amount <= 0 or get_heal_item(item_id).is_empty():
		return
	GlobalData.pilot_items[item_id] = get_item_count(item_id) + amount


# Uses a healing item if the pilot has one. Returns the HP restored (0 if the
# item was missing / unusable / the pilot is already at full HP).
static func use_heal_item(item_id: String) -> float:
	var item := get_heal_item(item_id)
	if item.is_empty():
		return 0.0
	if get_item_count(item_id) <= 0:
		return 0.0
	if not is_injured():
		return 0.0
	var restored := heal(float(item.get("heal", 0.0)))
	if restored <= 0.0:
		return 0.0
	GlobalData.pilot_items[item_id] = get_item_count(item_id) - 1
	if GlobalData.pilot_items[item_id] <= 0:
		GlobalData.pilot_items.erase(item_id)
	return restored


# --- City trading ------------------------------------------------------------

# Credit price for one healing item / one unit of ammo at a city node.
static func get_item_price(item_id: String) -> int:
	var item := get_heal_item(item_id)
	if item.is_empty():
		return 0
	return int(item.get("price", 0))


static func get_ammo_price(ammo_type: String) -> int:
	return int(AMMO_PRICES.get(ammo_type, 0))


# Buys a healing item at a city. Returns true on success (credits spent, item
# added to the pilot's inventory).
static func buy_item(item_id: String) -> bool:
	var price := get_item_price(item_id)
	if price <= 0:
		return false
	if not GlobalData.try_spend_credits(price):
		return false
	add_item(item_id)
	return true


# Buys `amount` units of personal ammo at a city. Returns the units actually
# bought (0 when unaffordable / unknown type).
static func buy_ammo(ammo_type: String, amount: int) -> int:
	if amount <= 0 or not AMMO_PRICES.has(ammo_type):
		return 0
	var price := get_ammo_price(ammo_type)
	var affordable := int(GlobalData.credits / price)
	var bought := mini(amount, affordable)
	if bought <= 0:
		return 0
	if not GlobalData.try_spend_credits(bought * price):
		return 0
	add_ammo(ammo_type, bought)
	return bought
