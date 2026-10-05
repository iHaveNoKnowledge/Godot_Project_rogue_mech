class_name FactionSystem
extends RefCounted

## ---------------------------------------------------------------------------
## FACTION SYSTEM — สหพันธ์ / ซีออน / พเนจร + Tier 1-3 แบบอิงเวลาจริงและ Event
##
## - เริ่มเกม heat ต่ำ ศัตรูยังไม่รู้จักเรา → ไม่มีการพัฒนา (Tier 1)
## - พอเราสู้บ่อยขึ้น heat สูง, ศัตรูรู้ตัวตนเรา, สู้เราไม่ได้ → Trigger วิจัยหุ่นรุ่นใหม่
## - ไม่อัพ Tier แบบ turn อัตโนมัติ ต้องมีเหตุการณ์ (combat, heat, การสูญเสีย, เวลา)
## - เวลาจริงคือ board_day + time_hour (24h) ไม่ใช่ turn count
##
## Factions:
##   federation - สหพันธ์ (น้ำเงิน/เทา) เน้นสมดุล
##   zeon       - ซีออน (แดง/ดำ) เน้นหนัก+บุก
##   outland    - พเนจร (ส้ม/เหลือง) ใช้หุ่นนอกระบบทั้งสองฝั่ง แบบแรนดอม
##
## Tier 1-3: เลือกพาร์ทตาม HP/weight (Tier 1 เบา, Tier 3 หนัก) + สี
## ---------------------------------------------------------------------------

enum FactionId { FEDERATION, ZEON, OUTLAND }

const FACTION_DEFS: Dictionary = {
	"federation": {
		"id": "federation",
		"name": "สหพันธ์โลก",
		"name_en": "Federation",
		"short": "FED",
		"color": Color(0.22, 0.42, 0.78),
		"accent": Color(0.55, 0.75, 0.95),
		"trim": Color(0.35, 0.50, 0.70),
		"desc": "กองกำลังหลักของโลก เน้นหุ่นสมดุล มาตรฐานสูง"
	},
	"zeon": {
		"id": "zeon",
		"name": "ซีออน",
		"name_en": "Zeon",
		"short": "ZEO",
		"color": Color(0.72, 0.15, 0.18),
		"accent": Color(0.95, 0.45, 0.25),
		"trim": Color(0.55, 0.20, 0.22),
		"desc": "กองกำลังแบ่งแยก เน้นหุ่นหนัก บุกทะลวง"
	},
	"outland": {
		"id": "outland",
		"name": "พเนจร",
		"name_en": "Outland",
		"short": "OUT",
		"color": Color(0.78, 0.62, 0.18),
		"accent": Color(0.92, 0.75, 0.35),
		"trim": Color(0.65, 0.55, 0.30),
		"desc": "กลุ่มขับหุ่นอิสระ ใช้หุ่นนอกระบบทั้งสองฝั่ง ปะปน Tier"
	},
	"scavenger": {
		"id": "scavenger",
		"name": "สแกเวนเจอร์",
		"name_en": "Scavengers",
		"short": "SCV",
		"color": Color(0.62, 0.45, 0.20),
		"accent": Color(0.85, 0.65, 0.30),
		"trim": Color(0.40, 0.32, 0.22),
		"desc": "กลุ่มเก็บกู้อิสระ ลาดตระเวนซากสนามรบและตั้งค่ายนอกระบบ"
	}
}

const TIER_MAX: int = 3

# Phase 2 (Campaign V2): canonical campaign faction registry. Deterministic
# order, stable serializable IDs (never display names). Patrol encounter
# labels ("hostile"/"unknown") and tech diffusion tags ("all"/"rival"/
# "convoy") are NOT campaign factions and stay out of this registry.
const REGISTERED_FACTION_IDS: Array[String] = ["federation", "zeon", "outland", "scavenger"]

static func get_faction_ids() -> Array[String]:
	return REGISTERED_FACTION_IDS.duplicate()

static func get_registered_factions() -> Array[String]:
	return REGISTERED_FACTION_IDS.duplicate()

static func has_faction(faction_id: String) -> bool:
	return REGISTERED_FACTION_IDS.has(faction_id)

static func get_faction(faction_id: String) -> Dictionary:
	return get_faction_def(faction_id)

static func get_faction_def(faction: String) -> Dictionary:
	return FACTION_DEFS.get(faction, FACTION_DEFS["outland"]).duplicate(true)

static func get_faction_name(faction: String) -> String:
	return str(get_faction_def(faction).get("name", faction))

static func get_faction_paint(faction: String) -> Dictionary:
	var def := get_faction_def(faction)
	return {
		"base": def.get("color", Color(0.6, 0.6, 0.6)),
		"accent": def.get("accent", def.get("color", Color(0.6, 0.6, 0.6))),
		"trim": def.get("trim", def.get("color", Color(0.6, 0.6, 0.6))),
	}

# --- Tier access (stored in GlobalData.narrative) ---
static func get_tier(faction: String) -> int:
	if faction == "federation":
		var v = GlobalData.narrative.get("federation_tier")
		if v != null:
			return int(v)
		var v2 = GlobalData.narrative.get("enemy_tech_tier")
		if v2 != null:
			return int(v2)
		return 1
	if faction == "zeon":
		var v = GlobalData.narrative.get("zeon_tier")
		if v != null:
			return int(v)
		var v2 = GlobalData.narrative.get("enemy_tech_tier")
		if v2 != null:
			return int(v2)
		return 1
	if faction == "outland":
		var day: int = int(GlobalData.board.board_day) if GlobalData.board else 1
		if day >= 20:
			return randi_range(1, 3)
		elif day >= 10:
			return randi_range(1, 2)
		return 1
	return 1

static func set_tier(faction: String, tier: int) -> void:
	tier = clampi(tier, 1, TIER_MAX)
	if faction == "federation":
		GlobalData.narrative.set("federation_tier", tier)
	elif faction == "zeon":
		GlobalData.narrative.set("zeon_tier", tier)
	# Keep legacy enemy_tech_tier in sync for old systems (max of both)
	var f = GlobalData.narrative.get("federation_tier")
	var z = GlobalData.narrative.get("zeon_tier")
	var f_val: int = int(f) if f != null else 1
	var z_val: int = int(z) if z != null else 1
	GlobalData.narrative.enemy_tech_tier = maxi(f_val, z_val)

# Real time in days (fractional): board_day + time_hour/24.0
static func get_time_days() -> float:
	var day: float = float(GlobalData.board.board_day) if GlobalData.board else 1.0
	var hour: float = float(GlobalData.board.time_hour) if GlobalData.board and "time_hour" in GlobalData.board else 8.0
	return day + hour / 24.0

# --- Trigger evaluation (event-driven, not automatic) ---
static func evaluate_triggers() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var time_days: float = get_time_days()
	var heat: int = int(GlobalData.board.heat) if GlobalData.board else 0
	var battles_v = GlobalData.narrative.get("mech_battles_survived")
	var battles: int = int(battles_v) if battles_v != null else 0
	var wanted: int = int(GlobalData.board.wanted_level) if GlobalData.board else 0

	for faction in ["federation", "zeon"]:
		var tier: int = get_tier(faction)
		if tier >= TIER_MAX:
			continue
		var rd_key: String = faction + "_research"
		var active_v = GlobalData.narrative.get(rd_key + "_active")
		var active: bool = bool(active_v) if active_v != null else false
		if active:
			continue

		var trigger_reason: String = ""
		var should_trigger: bool = false

		if tier == 1:
			if heat >= 4 and battles >= 3 and time_days >= 3.0:
				var losses_v = GlobalData.narrative.get("enemy_losses")
				var losses: int = int(losses_v) if losses_v != null else 0
				var research_v = GlobalData.narrative.get("enemy_research_progress")
				var research: float = float(research_v) if research_v != null else 0.0
				if losses >= 5 or research >= 1.0 or wanted >= 1:
					should_trigger = true
					trigger_reason = "ศัตรูตรวจพบการมีอยู่ของคุณ (Heat %d) และพ่ายแพ้หลายครั้ง — %s เริ่มโครงการพัฒนาหุ่น Tier 2" % [heat, get_faction_name(faction)]
		elif tier == 2:
			if heat >= 7 and battles >= 6 and time_days >= 8.0:
				var losses_v = GlobalData.narrative.get("enemy_losses")
				var losses: int = int(losses_v) if losses_v != null else 0
				var research_v = GlobalData.narrative.get("enemy_research_progress")
				var research: float = float(research_v) if research_v != null else 0.0
				if losses >= 12 or wanted >= 2 or research >= 1.5:
					should_trigger = true
					trigger_reason = "%s วิเคราะห์ข้อมูลการรบและพบว่าหุ่นปัจจุบันสู้คุณไม่ได้ — เริ่มวิจัย Tier 3" % get_faction_name(faction)

		if should_trigger:
			_start_research(faction, trigger_reason)
			events.append({"faction": faction, "old_tier": tier, "reason": trigger_reason, "type": "research_started"})

	return events

static func _start_research(faction: String, reason: String) -> void:
	var rd_key: String = faction + "_research"
	GlobalData.narrative.set(rd_key + "_active", true)
	GlobalData.narrative.set(rd_key + "_progress", 0.0)
	var tier: int = get_tier(faction)
	var required: float = 2.5 if tier == 1 else 3.5
	GlobalData.narrative.set(rd_key + "_required", required)
	GlobalData.narrative.set(rd_key + "_start_day", get_time_days())
	GlobalData.narrative.set(rd_key + "_reason", reason)
	if EventBus.has_signal("faction_research_started"):
		EventBus.emit_signal("faction_research_started", faction, tier + 1, reason)
	if EventBus.has_signal("enemy_tech_escalated"):
		EventBus.emit_signal("enemy_tech_escalated", tier + 1)

static func tick_research(delta_days: float = 1.0) -> Array[Dictionary]:
	var completed: Array[Dictionary] = []
	for faction in ["federation", "zeon"]:
		var rd_key: String = faction + "_research"
		var active_v = GlobalData.narrative.get(rd_key + "_active")
		var active: bool = bool(active_v) if active_v != null else false
		if not active:
			continue
		var prog_v = GlobalData.narrative.get(rd_key + "_progress")
		var prog: float = float(prog_v) if prog_v != null else 0.0
		var req_v = GlobalData.narrative.get(rd_key + "_required")
		var req: float = float(req_v) if req_v != null else 2.5
		prog += delta_days
		GlobalData.narrative.set(rd_key + "_progress", prog)
		if prog >= req:
			var old_tier: int = get_tier(faction)
			set_tier(faction, old_tier + 1)
			GlobalData.narrative.set(rd_key + "_active", false)
			GlobalData.narrative.set(rd_key + "_progress", 0.0)
			var reason_v = GlobalData.narrative.get(rd_key + "_reason")
			var reason: String = str(reason_v) if reason_v != null else ""
			completed.append({"faction": faction, "new_tier": old_tier + 1, "reason": reason})
			if EventBus.has_signal("faction_tier_upgraded"):
				EventBus.emit_signal("faction_tier_upgraded", faction, old_tier + 1)
			GlobalData.board.run_notice = "【%s】 อัพเกรดเป็น Tier %d แล้ว! %s" % [get_faction_name(faction), old_tier + 1, reason]
	return completed

static func record_enemy_loss(count: int = 1) -> void:
	var cur_v = GlobalData.narrative.get("enemy_losses")
	var cur: int = int(cur_v) if cur_v != null else 0
	GlobalData.narrative.set("enemy_losses", cur + count)

static func pick_next_faction() -> String:
	if randf() < 0.15:
		return "outland"
	var day: float = get_time_days()
	if day < 5:
		return "federation" if randf() < 0.7 else "zeon"
	elif day < 12:
		return "federation" if randf() < 0.5 else "zeon"
	else:
		return "zeon" if randf() < 0.6 else "federation"

static func random_faction_for_pilot() -> String:
	var r := randf()
	if r < 0.10:
		return "outland"
	elif r < 0.55:
		return "federation"
	else:
		return "zeon"

static func get_tier_equipment_tier(faction: String) -> int:
	return get_tier(faction)

static func reset() -> void:
	for faction in ["federation", "zeon"]:
		GlobalData.narrative.set(faction + "_research_active", false)
		GlobalData.narrative.set(faction + "_research_progress", 0.0)
		GlobalData.narrative.set(faction + "_research_required", 2.5)
		GlobalData.narrative.set(faction + "_research_start_day", 0.0)
		set_tier(faction, 1)
	GlobalData.narrative.set("enemy_losses", 0)


# ===========================================================================
# RELATION MATRIX — Phase 2 (Campaign V2 foundation, NOT a combat migration).
#
# Single authoritative faction-to-faction relation state. Combat allegiance,
# AI targeting, spawning, projectiles and War Mode teams keep their existing
# binary logic untouched; they do NOT read this matrix yet (later phase).
#
# Invariants (all tested):
#   - Symmetric: set(A,B) reads back identically for (B,A).
#   - Self-relation is always ALLIED; setting a self-relation is rejected.
#   - Unset pairs read as DEFAULT_RELATION (NEUTRAL) — hostility is never
#     inferred merely because two factions differ.
#   - Unknown faction IDs: reads return NEUTRAL (safe default), writes are
#     rejected (false) without mutating state or inventing factions.
#   - No EventBus traffic: queries never emit; Phase 2 adds no mutation
#     signal (no existing consumer needs one).
# ===========================================================================

enum Relation { HOSTILE = 0, NEUTRAL = 1, COOPERATIVE = 2, ALLIED = 3 }

const DEFAULT_RELATION: int = Relation.NEUTRAL
const SELF_RELATION: int = Relation.ALLIED

const RELATION_NAMES := {
	Relation.HOSTILE: "hostile",
	Relation.NEUTRAL: "neutral",
	Relation.COOPERATIVE: "cooperative",
	Relation.ALLIED: "allied",
}

static var _relations: Dictionary = {}


static func relation_to_name(relation: int) -> String:
	return str(RELATION_NAMES.get(relation, "neutral"))


static func relation_from_name(raw_name: String) -> int:
	for key in RELATION_NAMES:
		if str(RELATION_NAMES[key]) == raw_name:
			return int(key)
	return -1


static func _relation_key(a: String, b: String) -> String:
	# Canonical pair ordering keeps the matrix symmetric with one entry.
	return a + "|" + b if a <= b else b + "|" + a


## Authoritative read. Self-pairs are ALLIED; unknown IDs or unset pairs read
## NEUTRAL (safe default — never invent hostility or factions on read).
static func get_relation(a: String, b: String) -> int:
	if a == b and has_faction(a):
		return SELF_RELATION
	if not has_faction(a) or not has_faction(b):
		return DEFAULT_RELATION
	return int(_relations.get(_relation_key(a, b), DEFAULT_RELATION))


static func get_relation_name(a: String, b: String) -> String:
	return relation_to_name(get_relation(a, b))


## Authoritative write (symmetric). Returns false without mutating when either
## ID is unregistered, the pair is a self-pair, or the value is not a
## canonical Relation.
static func set_relation(a: String, b: String, relation: int) -> bool:
	if not has_faction(a) or not has_faction(b):
		return false
	if a == b:
		return false
	if not RELATION_NAMES.has(relation):
		return false
	_relations[_relation_key(a, b)] = relation
	return true


static func is_hostile(a: String, b: String) -> bool:
	return get_relation(a, b) == Relation.HOSTILE


static func is_neutral(a: String, b: String) -> bool:
	return get_relation(a, b) == Relation.NEUTRAL


static func is_cooperative(a: String, b: String) -> bool:
	return get_relation(a, b) == Relation.COOPERATIVE


static func is_allied(a: String, b: String) -> bool:
	return get_relation(a, b) == Relation.ALLIED


## Clears every explicit override back to deterministic defaults. Called from
## the established run-reset lifecycle (NOT from the legacy tier reset()).
static func reset_relations() -> void:
	_relations.clear()


## Mutable state only: sorted explicit overrides with stable string values.
## Registered defs are static and never serialized.
static func serialize_relations() -> Dictionary:
	var pairs: Array = []
	var keys := _relations.keys()
	keys.sort()
	for key in keys:
		var parts := str(key).split("|")
		if parts.size() != 2:
			continue
		pairs.append({
			"a": str(parts[0]),
			"b": str(parts[1]),
			"relation": relation_to_name(int(_relations[key])),
		})
	return {"relations": pairs}


## Restores overrides; unknown IDs, malformed rows and bad values are skipped
## deterministically. Missing/empty input resets to defaults (old saves).
static func deserialize_relations(data: Variant) -> void:
	reset_relations()
	if not (data is Dictionary):
		return
	var pairs = data.get("relations", [])
	if not (pairs is Array):
		return
	for row in pairs:
		if not (row is Dictionary):
			continue
		var a := str(row.get("a", ""))
		var b := str(row.get("b", ""))
		var rel := relation_from_name(str(row.get("relation", "")))
		set_relation(a, b, rel)
