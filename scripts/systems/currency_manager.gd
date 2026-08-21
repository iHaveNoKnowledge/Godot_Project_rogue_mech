class_name CurrencyManager
extends RefCounted

## ---------------------------------------------------------------------------
## CURRENCY MANAGER — single source of truth for all spendable currencies.
##
## Extracted from GlobalData so spending rules, gain guards and balance queries
## live in one place.  Every external code should mutate currencies through
## these helpers instead of touching the raw ints directly.
## ---------------------------------------------------------------------------

var credits: int = 0
var scrap: int = 0
var data_cores: int = 0

# --- Credits ---

func try_spend_credits(amount: int) -> bool:
	if amount <= 0 or credits < amount:
		return false
	credits -= amount
	return true

func gain_credits(amount: int) -> void:
	if amount > 0:
		credits += amount

# --- Scrap ---

func try_spend_scrap(amount: int) -> bool:
	if amount <= 0 or scrap < amount:
		return false
	scrap -= amount
	return true

func gain_scrap(amount: int) -> void:
	if amount > 0:
		scrap += amount

# --- Data Cores ---

func try_spend_data_cores(amount: int) -> bool:
	if amount <= 0 or data_cores < amount:
		return false
	data_cores -= amount
	return true

func gain_data_cores(amount: int) -> void:
	if amount > 0:
		data_cores += amount

# --- Reset ---

func reset(initial_credits: int = 110) -> void:
	credits = initial_credits
	scrap = 0
	data_cores = 0
