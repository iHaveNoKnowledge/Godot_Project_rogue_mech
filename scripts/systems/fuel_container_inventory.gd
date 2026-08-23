extends RefCounted

## ---------------------------------------------------------------------------
## FUEL CONTAINER INVENTORY — GDD §4.1
##
## Each fuel container is an Item Slot in the inventory.  Containers come in
## fixed capacity tiers (1 %, 6 %, 10 %, 20 %, 100 %) and each occupies
## exactly ONE inventory slot.
##
## Auto-stacking: when new fuel arrives the system fills the first incomplete
## container of the same type, then only creates a new container when every
## existing container of that type is full (or inventory is empty).
##
## Three fuel types:
##   CRUDE_OIL    — Convoy / Direct Combustion Core (no penalty)
##   REFINED_CELL — All Mecha Cores (no penalty)
##   BIO_FUEL     — Convoy / Combustion Core only; adds Heat in Hybrid Cores
## ---------------------------------------------------------------------------

enum FuelType { CRUDE_OIL, REFINED_CELL, BIO_FUEL }

# ---- Container size definitions (percent of a full tank) ----
const CONTAINER_SIZES: Array[float] = [1.0, 6.0, 10.0, 20.0, 100.0]

## Default inventory capacity (number of slots).
const DEFAULT_MAX_SLOTS: int = 12


## ---- Internal representation ----
# Each container: { "type": int (FuelType), "capacity": float, "current": float }
var _containers: Array[Dictionary] = []
var _max_slots: int = DEFAULT_MAX_SLOTS


# ==========================================================================
# CONTAINER FACTORY
# ==========================================================================

## Creates a new container dict.  `size_pct` is one of CONTAINER_SIZES.
static func create_container(fuel_type: int, size_pct: float) -> Dictionary:
	return {
		"type": fuel_type,
		"capacity": size_pct,
		"current": 0.0,
	}


## Creates a pre-filled container (used for initial loadout / migration).
static func create_filled_container(fuel_type: int, size_pct: float) -> Dictionary:
	return {
		"type": fuel_type,
		"capacity": size_pct,
		"current": size_pct,
	}


# ==========================================================================
# READ-ONLY QUERIES
# ==========================================================================

func get_slot_count() -> int:
	return _containers.size()


func get_max_slots() -> int:
	return _max_slots


func get_containers() -> Array[Dictionary]:
	return _containers


func is_full() -> bool:
	return _containers.size() >= _max_slots


func has_any_containers() -> bool:
	return not _containers.is_empty()


## Total fuel across ALL containers (sum of current / capacity * 100 equiv).
func total_fuel() -> float:
	var sum := 0.0
	for c in _containers:
		sum += float(c.get("current", 0.0))
	return sum


## Total fuel for a specific type.
func total_fuel_by_type(fuel_type: int) -> float:
	var sum := 0.0
	for c in _containers:
		if int(c.get("type", -1)) == fuel_type:
			sum += float(c.get("current", 0.0))
	return sum


## Total fuel for all types compatible with a core class (GDD §4.2).
##   "convoy"          -> CRUDE_OIL + BIO_FUEL
##   "combustion"      -> CRUDE_OIL + BIO_FUEL
##   "hybrid"          -> REFINED_CELL + BIO_FUEL (with heat penalty on bio)
##   "ancient"         -> REFINED_CELL
##   "all" / default   -> everything
func total_fuel_compatible(core_class: String = "all") -> float:
	match core_class:
		"convoy", "combustion":
			return total_fuel_by_type(FuelType.CRUDE_OIL) + total_fuel_by_type(FuelType.BIO_FUEL)
		"hybrid":
			return total_fuel_by_type(FuelType.REFINED_CELL) + total_fuel_by_type(FuelType.BIO_FUEL)
		"ancient":
			return total_fuel_by_type(FuelType.REFINED_CELL)
		_:
			return total_fuel()


## Returns true if there is room for at least one more container.
func has_room() -> bool:
	return _containers.size() < _max_slots


## Finds the first incomplete container of the given type, or null.
func _find_partial_container(fuel_type: int) -> Dictionary:
	for c in _containers:
		if int(c.get("type", -1)) == fuel_type:
			var cur: float = float(c.get("current", 0.0))
			var cap: float = float(c.get("capacity", 1.0))
			if cur > 0.001 and cur < cap:
				return c
	return {}


## Finds the first full container of the given type, or empty dict.
func _find_full_container(fuel_type: int) -> Dictionary:
	for c in _containers:
		if int(c.get("type", -1)) == fuel_type:
			var cur: float = float(c.get("current", 0.0))
			var cap: float = float(c.get("capacity", 1.0))
			if cur >= cap:
				return c
	return {}


## Removes empty containers from the inventory.
func _compact() -> void:
	var cleaned: Array[Dictionary] = []
	for c in _containers:
		if float(c.get("current", 0.0)) > 0.001:
			cleaned.append(c)
	_containers = cleaned


# ==========================================================================
# ADD FUEL  (GDD §4.1 auto-stacking)
# ==========================================================================

## Adds `amount` fuel of the given type using auto-stacking logic.
## 1. Fill incomplete containers of the same type first.
## 2. If all are full and room exists, create a new container of the best-fit size.
## Returns the amount actually absorbed.
func add_fuel(fuel_type: int, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var remaining := amount

	# Step 1: fill partial containers of this type
	while remaining > 0.001:
		var partial := _find_partial_container(fuel_type)
		if partial.is_empty():
			break
		var cap: float = float(partial.get("capacity", 1.0))
		var cur: float = float(partial.get("current", 0.0))
		var space := cap - cur
		var fill := minf(remaining, space)
		partial["current"] = cur + fill
		remaining -= fill

	# Step 2: if still fuel left and room available, create new containers
	while remaining > 0.001 and _containers.size() < _max_slots:
		var best_size := _pick_best_container_size(remaining)
		if best_size <= 0.0:
			break
		var new_cont := create_container(fuel_type, best_size)
		var fill := minf(remaining, best_size)
		new_cont["current"] = fill
		_containers.append(new_cont)
		remaining -= fill

	return amount - remaining


## Creates a new container with the given pre-filled amount (no auto-stacking).
## Used for events that reward a specific container, e.g. "Found a 6% cell".
## Returns true if the container was added.
func add_container(fuel_type: int, size_pct: float, fill_pct: float = -1.0) -> bool:
	if _containers.size() >= _max_slots:
		return false
	if fill_pct < 0.0:
		fill_pct = size_pct  # fully filled by default
	var cont := create_container(fuel_type, size_pct)
	cont["current"] = clampf(fill_pct, 0.0, size_pct)
	_containers.append(cont)
	return true


# ==========================================================================
# CONSUME FUEL  (GDD §4.1 — drain full containers first, then partial)
# ==========================================================================

## Consumes `amount` fuel.  Drains full containers first (to keep partials
## topped-off for later), then partials.  Returns actual amount consumed.
func consume_fuel(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var remaining := amount

	# Phase 1: drain FULL containers (capacity == current)
	while remaining > 0.001:
		var full := _find_any_full_container()
		if full.is_empty():
			break
		var cur: float = float(full.get("current", 0.0))
		var drain := minf(remaining, cur)
		full["current"] = cur - drain
		remaining -= drain

	# Phase 2: drain PARTIAL containers
	while remaining > 0.001:
		var partial := _find_any_partial_container()
		if partial.is_empty():
			break
		var cur: float = float(partial.get("current", 0.0))
		var drain := minf(remaining, cur)
		partial["current"] = cur - drain
		remaining -= drain

	_compact()
	return amount - remaining


## Consumes fuel of a specific type only.
func consume_fuel_by_type(fuel_type: int, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var remaining := amount

	# Phase 1: full containers of this type
	while remaining > 0.001:
		var full := _find_full_container(fuel_type)
		if full.is_empty():
			break
		var cur: float = float(full.get("current", 0.0))
		var drain := minf(remaining, cur)
		full["current"] = cur - drain
		remaining -= drain

	# Phase 2: partial containers of this type
	while remaining > 0.001:
		var partial := _find_partial_container(fuel_type)
		if partial.is_empty():
			break
		var cur: float = float(partial.get("current", 0.0))
		var drain := minf(remaining, cur)
		partial["current"] = cur - drain
		remaining -= drain

	_compact()
	return amount - remaining


func _find_any_full_container() -> Dictionary:
	for c in _containers:
		var cur: float = float(c.get("current", 0.0))
		var cap: float = float(c.get("capacity", 1.0))
		if cur >= cap:
			return c
	return {}


func _find_any_partial_container() -> Dictionary:
	for c in _containers:
		var cur: float = float(c.get("current", 0.0))
		var cap: float = float(c.get("capacity", 1.0))
		if cur > 0.001 and cur < cap:
			return c
	return {}


# ==========================================================================
# CONTAINER SIZE SELECTION
# ==========================================================================

## Picks the smallest container size that can hold `amount` fuel without
## too much wasted capacity.  Falls back to the smallest available if amount
## is tiny.
func _pick_best_container_size(amount: float) -> float:
	# Find the smallest size that fits
	for size in CONTAINER_SIZES:
		if size >= amount:
			return size
	# If amount exceeds all sizes, use the largest
	return CONTAINER_SIZES[CONTAINER_SIZES.size() - 1]


# ==========================================================================
# DISPLAY HELPERS
# ==========================================================================

## Returns a display string like: "Crude: [100%][16%] (116.0) | Refined: [20%]"
func inventory_display() -> String:
	var parts: Array[String] = []
	for fuel_type_value in [FuelType.CRUDE_OIL, FuelType.REFINED_CELL, FuelType.BIO_FUEL]:
		var type_int = int(fuel_type_value)
		var type_name := _fuel_type_name(type_int)
		var type_total := total_fuel_by_type(type_int)
		if type_total <= 0.0 and not _has_any_of_type(type_int):
			continue
		var slots: Array[String] = []
		for c in _containers:
			if int(c.get("type", -1)) == type_int:
				var cur: float = float(c.get("current", 0.0))
				var cap: float = float(c.get("capacity", 1.0))
				slots.append("[%.0f%%]" % (cur / cap * 100.0 if cap > 0.0 else 0.0))
		parts.append("%s %s (%.0f)" % [type_name, " ".join(slots), type_total])
	if parts.is_empty():
		return "EMPTY"
	return " | ".join(parts)


func _has_any_of_type(fuel_type: int) -> bool:
	for c in _containers:
		if int(c.get("type", -1)) == fuel_type:
			return true
	return false


static func _fuel_type_name(fuel_type: int) -> String:
	match fuel_type:
		FuelType.CRUDE_OIL:
			return "Crude"
		FuelType.REFINED_CELL:
			return "Refined"
		FuelType.BIO_FUEL:
			return "Bio"
		_:
			return "???"


# ==========================================================================
# RESET
# ==========================================================================

func reset(starting_containers: Array = []) -> void:
	_containers.clear()
	_max_slots = DEFAULT_MAX_SLOTS
	for c in starting_containers:
		if c is Dictionary:
			_containers.append(c.duplicate())


func clear() -> void:
	_containers.clear()


# ==========================================================================
# SERIALIZATION (JSON-safe)
# ==========================================================================

func serialize() -> Array:
	var result: Array = []
	for c in _containers:
		result.append({
			"type": int(c.get("type", 0)),
			"capacity": float(c.get("capacity", 1.0)),
			"current": float(c.get("current", 0.0)),
		})
	return result


func deserialize(data: Array) -> void:
	_containers.clear()
	for entry in data:
		if entry is Dictionary:
			_containers.append({
				"type": int(entry.get("type", 0)),
				"capacity": float(entry.get("capacity", 1.0)),
				"current": float(entry.get("current", 0.0)),
			})
