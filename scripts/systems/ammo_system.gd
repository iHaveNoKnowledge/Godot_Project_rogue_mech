class_name AmmoSystem
extends RefCounted

## Central ammo catalog — every gun family gets its own ammo type so sharing
## a pool is the exception (missiles/rockets stay separate, heavies don't eat
## the same rounds as sidearms).
##
##   bullet       — Machine Gun, Light MG, Pilot Pistol, Assault Rifle
##   heavy_round  — Heavy MG, Gatling Gun, Minigun
##   shell        — Shotgun, Combat Shotgun, Sawed-Off
##   spike        — Railgun, Anti-Tank Rifle, Pile Bunker (piercing rods/stakes)
##   energy_cell  — Beam Rifle / MK2 / Carbine / Sniper (renamed from "energy")
##   rocket       — Micro Missile Pod, Swarm Missile (unguided small rockets)
##   missile      — Missile Launcher, Heavy Missile (guided heavies)
##   explosive    — Assault Cannon, Bazooka
##   none         — melee / shields (never consumed)
##
## All ammo pools (pilot_ammo, ammo_inventory, loadout "ammo", battle_reserve)
## are plain Dictionaries keyed by these ids, so no other system needs to know
## the list — iterate ORDER for UI rows.

const ORDER: Array[String] = [
	"bullet", "heavy_round", "shell", "spike",
	"energy_cell", "rocket", "missile", "explosive",
]

const NAMES: Dictionary = {
	"bullet": "Bullets",
	"heavy_round": "Heavy Rounds",
	"shell": "Shells",
	"spike": "Spikes",
	"energy_cell": "Energy Cells",
	"rocket": "Rockets",
	"missile": "Missiles",
	"explosive": "Explosives",
}

const DESCS: Dictionary = {
	"bullet": "Standard rounds for Machine Guns, sidearms, and Rifles.",
	"heavy_round": "Belt-fed heavy rounds for HMGs, Gatlings, and Miniguns.",
	"shell": "Scatter shells for Shotguns.",
	"spike": "Armor-piercing rods for Railguns, AT Rifles, and Pile Bunkers.",
	"energy_cell": "Capacitor cells for Beam Rifles, Carbines, and Snipers.",
	"rocket": "Unguided rockets for Micro and Swarm pods.",
	"missile": "Guided heavy missiles for Launchers.",
	"explosive": "High-explosive rounds for Cannons and Bazookas.",
}

# Credits per unit at city shops (single source of truth — PilotSystem reads it).
const PRICES: Dictionary = {
	"bullet": 2,
	"heavy_round": 4,
	"shell": 4,
	"spike": 6,
	"energy_cell": 3,
	"rocket": 8,
	"missile": 15,
	"explosive": 8,
}

# Field-pack kg per unit (single source of truth — GlobalData mirrors it).
const WEIGHTS: Dictionary = {
	"bullet": 0.01,
	"heavy_round": 0.03,
	"shell": 0.05,
	"spike": 0.04,
	"energy_cell": 0.02,
	"rocket": 0.25,
	"missile": 0.50,
	"explosive": 0.20,
}

const COLORS: Dictionary = {
	"bullet": Color(0.95, 0.80, 0.35),
	"heavy_round": Color(1.00, 0.60, 0.20),
	"shell": Color(0.50, 0.85, 0.35),
	"spike": Color(0.75, 0.85, 0.95),
	"energy_cell": Color(0.30, 0.85, 1.00),
	"rocket": Color(1.00, 0.45, 0.75),
	"missile": Color(0.70, 0.45, 1.00),
	"explosive": Color(1.00, 0.30, 0.10),
}

# Fresh-run mech reserve / loadout allocation.
const STARTER_RESERVE: Dictionary = {
	"bullet": 250,
	"heavy_round": 100,
	"shell": 80,
	"spike": 24,
	"energy_cell": 150,
	"rocket": 16,
	"missile": 12,
	"explosive": 30,
}

# Fresh-run pilot pockets (pilot guns: pistol/bullet, AT rifle/spike, bazooka/explosive).
const STARTER_PILOT_AMMO: Dictionary = {
	"bullet": 120,
	"spike": 10,
	"explosive": 8,
}

# Old (4-type) save keys -> their successor type(s). A legacy pool copies its
# full amount into EVERY successor so no owned gun is ever stranded by the
# split (one-time migration, single-player game — generosity is intended).
const MIGRATION: Dictionary = {
	"kinetic": ["bullet", "heavy_round", "shell", "spike"],
	"energy": ["energy_cell"],
	"missile": ["missile", "rocket"],
	"explosive": ["explosive"],
}


static func display_name(ammo_type: String) -> String:
	return str(NAMES.get(ammo_type, ammo_type.capitalize()))


static func price(ammo_type: String) -> int:
	return int(PRICES.get(ammo_type, 0))


static func weight_per_unit(ammo_type: String) -> float:
	return float(WEIGHTS.get(ammo_type, 0.01))


static func chip_color(ammo_type: String) -> Color:
	return COLORS.get(ammo_type, Color(0.8, 0.8, 0.8))


## Normalizes any ammo pool in place: migrates legacy 4-type keys, drops
## unknown/empty keys. Returns the same Dictionary for chaining.
static func migrate_dict(pool: Dictionary) -> Dictionary:
	for old_key in MIGRATION:
		if not pool.has(old_key):
			continue
		var amount := int(pool.get(old_key, 0))
		pool.erase(old_key)
		if amount <= 0:
			continue
		for successor in MIGRATION[old_key]:
			if not pool.has(successor):
				pool[successor] = amount
	for key in pool.keys():
		if str(key) == "none" or int(pool.get(key, 0)) <= 0:
			pool.erase(key)
	return pool
