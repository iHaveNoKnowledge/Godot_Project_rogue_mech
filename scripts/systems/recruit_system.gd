class_name RecruitSystem
extends RefCounted

# -----------------------------------------------------------------------------
# RECRUITABLE CHARACTERS — named pilots with signature mechs the player can
# meet on the board. Each character is a fleet-ally template (see
# research_catalogs.tres -> ally_unit_templates) plus a 1v1 duel encounter:
#
#   - Talk nicely        -> they join the convoy as a pilot + their mech parks
#                           in the hangar (recurit_ally effect).
#   - Challenge to a duel -> win earns their respect -> they join.
#   - Mock / threaten     -> a fight to the death. On a win the player salvages
#                           the mech either as a wreck (low HP, repairable) or
#                           only as parts; the pilot may die or be wounded and
#                           need recovery time.
#
# A duel is a "duel" combat node that spawns exactly one full-rig enemy — the
# character's signature mech. Duel state is stored in GlobalData.hangar.pending_duel
# and resolved when that combat ends. Outcome text is written to
# GlobalData.hangar.duel_result_text for the combat rewards screen.
# -----------------------------------------------------------------------------

const CHARACTERS: Array = [
	{
		"id": "serra",
		"pilot_name": "Serra Voss",
		"mech_name": "Iron Mantis",
		"ally_template_id": "ally_serra",
		"archetype": HangarManager.ARCHETYPE_HEAVY,
		"duel_scene": "heavy_full",
		"duel_archetype": HangarManager.ARCHETYPE_HEAVY,
		"duel_hp_scale": 2.2,
		"themes": ["soldier"],
		"weight": 6,
		"min_reputation": 0,
		"desc": "A scarred army deserter pilots an Iron Mantis heavy frame. She blocks the road and raises her cannon — then lowers it. \"State your business, wanderer. Make it good.\"",
		"friendly_label": "Offer an Alliance",
		"friendly_desc": "Speak plainly and offer her a place in the convoy.",
		"duel_label": "Challenge Her to a Duel",
		"duel_desc": "One machine, one duel. Win her respect with your piloting.",
		"threat_label": "Demand the Mech",
		"threat_desc": "Cut the talk. You are taking that frame by force.",
		"recruit_notice": "Serra Voss respects a straight talker. The Iron Mantis rolls into the convoy, and its pilot rides along as a teammate.",
		"reconcile_notice": "After the duel, Serra Voss lowers her cannon for good. \"You fight like a soldier. I'll follow that.\" She and the Iron Mantis join the convoy.",
		"wreck_notice": "The Iron Mantis is brought down. The wreck still rolls — barely. Whatever remains of the frame is towed into the hangar.",
		"parts_notice": "The duel ends with the Iron Mantis shattered. Your team drags back only the parts that survived the fight.",
		"wounded_notice": "The pilot is dragged from the wreck, badly hurt. She will fight again once her wounds heal.",
		"dead_notice": "The cockpit is silent. There is no pulling the pilot out of this one.",
		"defeat_notice": "Serra Voss proves the stronger pilot. You are forced off the field with nothing to show for the challenge.",
	},
	{
		"id": "ren",
		"pilot_name": "Ren Kagami",
		"mech_name": "Crimson Fang",
		"ally_template_id": "ally_ren",
		"archetype": HangarManager.ARCHETYPE_RUSHER,
		"duel_scene": "rusher_full",
		"duel_archetype": HangarManager.ARCHETYPE_RUSHER,
		"duel_hp_scale": 2.0,
		"themes": ["valkyrion_merc"],
		"weight": 6,
		"min_reputation": 0,
		"desc": "A mercenary in a Crimson Fang melee frame circles your position, heat blade still smoking. \"You're the one with the rep. Show me what you've got.\"",
		"friendly_label": "Talk Terms",
		"friendly_desc": "Offer credits and a place in the crew. Everyone has a price.",
		"duel_label": "Duel for Respect",
		"duel_desc": "Mercs respect only one thing. Meet the Crimson Fang blade to blade.",
		"threat_label": "Run Them Down",
		"threat_desc": "This is a contract dispute. Settle it with a kill.",
		"recruit_notice": "Ren Kagami takes the offer. The Crimson Fang parks in your hangar and its pilot signs on.",
		"reconcile_notice": "Ren Kagami nods after the duel. \"Good fight. The Crimson Fang is yours to command.\" A new ace rides with the convoy.",
		"wreck_notice": "The Crimson Fang lies in a smoking heap. Your team hauls the wreck back — it might fly again.",
		"parts_notice": "The Crimson Fang comes apart under your fire. Only scattered parts are worth salvaging.",
		"wounded_notice": "Ren Kagami crawls from the wreck. Wounded, but alive — given time to heal, the pilot will fight again.",
		"dead_notice": "Ren Kagami never answers the comms again. The cockpit does not open.",
		"defeat_notice": "The Crimson Fang is faster and sharper. You withdraw in shame, paying nothing but your pride.",
	},
	{
		"id": "jax",
		"pilot_name": "Jax 'Scrapdog' Molina",
		"mech_name": "Mudhorn",
		"ally_template_id": "ally_jax",
		"archetype": HangarManager.ARCHETYPE_RANGED,
		"duel_scene": "ranged_full",
		"duel_archetype": HangarManager.ARCHETYPE_RANGED,
		"duel_hp_scale": 2.0,
		"themes": ["scavenger"],
		"weight": 6,
		"min_reputation": 0,
		"desc": "A scavenger in a patchwork Mudhorn rig watches you from a ridge, rifle steady. \"Nobody crosses my scrap line without a story. You got one?\"",
		"friendly_label": "Share Your Story",
		"friendly_desc": "Talk like one survivor to another. A convoy is worth more than a scrap line.",
		"duel_label": "Prove It With a Duel",
		"duel_desc": "The wasteland respects only skill. Shoot it out, one on one.",
		"threat_label": "Take the Rig",
		"threat_desc": "The Mudhorn is a pile of parts. Take it by force.",
		"recruit_notice": "Jax 'Scrapdog' Molina takes the story well and rides along. The Mudhorn joins the hangar.",
		"reconcile_notice": "After the duel, Jax drops the rifle. \"Fine shooting. I'll ride with the convoy.\" The Mudhorn rolls in behind you.",
		"wreck_notice": "The Mudhorn's frame collapses. The wreck is towed in — dented, low on fuel, but parked and repairable.",
		"parts_notice": "The Mudhorn blows apart. You salvage a few intact parts and little else.",
		"wounded_notice": "Jax is pulled from the rubble, hurt but breathing. The pilot will recover in time.",
		"dead_notice": "Jax 'Scrapdog' never makes it out of the wreck. The scrap line falls silent.",
		"defeat_notice": "The Mudhorn outguns you today. You fall back, empty-handed.",
	},
	{
		"id": "vagrant_ace",
		"pilot_name": "Gale 'The Vagrant' Kurogane",
		"mech_name": "Scrap Pilgrim",
		"ally_template_id": "ally_vagrant",
		"archetype": HangarManager.ARCHETYPE_RUSHER,
		"duel_scene": "rusher_full",
		"duel_archetype": HangarManager.ARCHETYPE_RUSHER,
		"duel_hp_scale": 1.6,
		"themes": ["scavenger", "desert"],
		"weight": 1,
		"min_sector": 2,
		"min_reputation": 0,
		"is_vagrant": true,
		"perk_id": "precognitive_flow",
		"perk_name": "Pre-Cognitive Flow",
		"perk_desc": "Effortless movement reading: -50% Dash Energy Cost, +25% Evasion, Zero-Waste Momentum.",
		"desc": "A ragged wanderer in an oil-soaked scrap cloak leans against a battered machine. His eyes anticipate every breath you take before you move. \"You fight the machine, kid. Let me show you how to listen to it.\"",
		"friendly_label": "Seek His Guidance",
		"friendly_desc": "Bow respectfully and ask the master to teach you the Pre-Cognitive Flow.",
		"duel_label": "Challenge the Master",
		"duel_desc": "Draw your weapons and test your predictive reflexes against the legendary wanderer.",
		"threat_label": "Share Supplies & Fuel",
		"threat_desc": "Offer high-grade fuel and med supplies in exchange for tactical guidance.",
		"recruit_notice": "Gale Kurogane nods with a faint smile. The Scrap Pilgrim silently rolls into your convoy. You have recruited The Vagrant Ace!",
		"reconcile_notice": "After the lightning duel, the Vagrant Ace lowers his weapon. \"Not bad. Your machine moves with purpose now.\" Gale and the Scrap Pilgrim join your fleet!",
		"wreck_notice": "The Scrap Pilgrim is brought to a standstill. Even in defeat, the internal joints are undamaged mastercraft engineering.",
		"parts_notice": "The Scrap Pilgrim shatters, revealing high-spec internal reactive vectors and legendary kinetic dampers.",
		"wounded_notice": "Gale leaps out effortlessly before impact, brushing dust from his cloak. \"You've got fire, kid. We'll cross paths again.\"",
		"dead_notice": "The wanderer's blade falls to the gravel. The legend has come to an end.",
		"defeat_notice": "The Vagrant Ace slips past every single shot with millimeter precision. You fall back in awe of his mastery.",
	},
]


static func get_character(character_id: String) -> Dictionary:
	for character in CHARACTERS:
		if character.get("id", "") == character_id:
			return character
	return {}


static func is_character_recruited(character_id: String) -> bool:
	return character_id in GlobalData.hangar.recruited_characters


# True when the player can still meet this character this run (not recruited).
static func is_character_available(character_id: String) -> bool:
	if is_character_recruited(character_id):
		return false
	return true


# Board-event availability filter: hide events for already-recruited characters
# and skip the whole encounter while the player is on foot (a duel cannot be
# fought without a mech, so the encounter is skipped entirely).
static func is_event_available(event: Dictionary) -> bool:
	var params: Dictionary = event.get("params", {})
	var character_id := str(params.get("character_id", ""))
	if character_id != "" and not is_character_available(character_id):
		return false
	if GlobalData.narrative.mech_less:
		for choice in params.get("choices", []):
			if choice is Dictionary and str(choice.get("effect", "")) == "duel":
				return false
	return true


# --- Recruitment (no combat) -------------------------------------------------

# Friendly talk succeeds: the character joins the convoy. Their mech parks in
# the hangar and their fleet unit fights alongside the player. Text is shown
# through the board convoy-report popup (run_notice).
static func recruit(character_id: String) -> bool:
	var character := get_character(character_id)
	if character.is_empty():
		return false
	var template_id := str(character.get("ally_template_id", ""))
	if not FleetSystem.add_ally_unit(template_id):
		# Already a convoy unit (e.g. previously recruited) — nothing to do.
		return false
	var text := str(character.get("recruit_notice", ""))
	var berth := _park_signature_mech(character, template_id)
	if berth != "":
		text += "\n" + berth
	GlobalData.hangar.recruited_characters.append(character_id)
	GlobalData.board.run_notice = text
	return true


# Helper to retrieve signature weapons for named recruit characters
static func get_character_signature_weapons(character_id: String) -> Dictionary:
	match character_id:
		"serra":
			return {
				"left": "res://resources/mech/stock/weapon_combat_shotgun.tres",
				"right": "res://resources/mech/stock/weapon_assault_cannon.tres",
				"carry": ["res://resources/mech/stock/weapon_heavy_missile.tres"]
			}
		"ren":
			return {
				"left": "res://resources/mech/stock/weapon_heat_blade.tres",
				"right": "res://resources/mech/stock/weapon_beam_carbine.tres",
				"carry": ["res://resources/mech/stock/weapon_combat_knife.tres"]
			}
		"jax":
			return {
				"left": "res://resources/mech/stock/weapon_beam_rifle.tres",
				"right": "res://resources/mech/stock/weapon_missile.tres",
				"carry": ["res://resources/mech/stock/weapon_machine_gun.tres"]
			}
		"vagrant_ace":
			return {
				"left": "res://resources/mech/stock/weapon_heat_blade.tres",
				"right": "res://resources/mech/stock/weapon_beam_rifle_mk2.tres",
				"carry": ["res://resources/mech/stock/weapon_combat_shotgun.tres"]
			}
	return {}


# Parks the character's signature mech as a hangar berth piloted by them.
# Returns a human-readable berth line, or "" when no berth was available.
static func _park_signature_mech(character: Dictionary, template_id: String) -> String:
	var weapons := get_character_signature_weapons(str(character.get("id", "")))
	var mech := HangarManager.park_ally_mech(
		str(character.get("mech_name", "Recruit Mech")),
		"fleet_%s" % template_id,
		int(character.get("archetype", HangarManager.ARCHETYPE_RANGED)),
		{},
		weapons
	)
	if mech.is_empty():
		return ""
	return "%s is parked in the hangar (%d/%d berths)." % [
		str(mech.get("name", "Mech")),
		GlobalData.hangar.hangar_mechs.size(),
		HangarManager.get_capacity(),
	]


# --- Duel --------------------------------------------------------------------

# Player chose a fight: record the pending duel and force a scene transition.
# `intent` is "test" (duel for respect) or "kill" (fight to the death).
static func start_duel(character_id: String, intent: String) -> bool:
	var character := get_character(character_id)
	if character.is_empty() or not is_character_available(character_id):
		return false
	GlobalData.hangar.pending_duel = {
		"character_id": character_id,
		"intent": intent,
	}
	return true


static func has_pending_duel() -> bool:
	return not GlobalData.hangar.pending_duel.is_empty()


static func get_pending_character() -> Dictionary:
	var character_id := str(GlobalData.hangar.pending_duel.get("character_id", ""))
	return get_character(character_id)


# Called from GlobalData._on_combat_ended when a duel battle finishes.
static func resolve_duel(victory: bool) -> void:
	var pending := GlobalData.hangar.pending_duel
	GlobalData.hangar.pending_duel = {}
	if pending.is_empty():
		return
	var character_id := str(pending.get("character_id", ""))
	var character := get_character(character_id)
	if character.is_empty():
		return
	var intent := str(pending.get("intent", "test"))

	if not victory:
		GlobalData.hangar.duel_result_text = str(character.get("defeat_notice", "You lost the duel."))
		return

	if intent == "kill":
		_resolve_kill_outcome(character)
	else:
		# Duel for respect: victory earns the character's loyalty.
		var text := str(character.get("reconcile_notice", ""))
		var berth := _recruit_from_duel(character)
		if berth != "":
			text += "\n" + berth
		GlobalData.hangar.duel_result_text = text


# Win a respect-duel -> the character joins the convoy. Returns berth text.
static func _recruit_from_duel(character: Dictionary) -> String:
	var template_id := str(character.get("ally_template_id", ""))
	if not FleetSystem.add_ally_unit(template_id):
		return ""
	var berth := _park_signature_mech(character, template_id)
	GlobalData.hangar.recruited_characters.append(str(character.get("id", "")))
	return berth


# Win a kill-duel -> salvage the mech (wreck or parts) and resolve the pilot's
# fate (dead or wounded/recovering).
static func _resolve_kill_outcome(character: Dictionary) -> void:
	var character_id := str(character.get("id", ""))
	var template_id := str(character.get("ally_template_id", ""))

	if randf() < 0.5:
		# The mech is salvaged as a wreck: low HP, heavy part damage, repairable.
		var pilot_survives := randf() < 0.5
		if pilot_survives:
			if FleetSystem.add_ally_unit(template_id):
				var unit := FleetSystem.get_fleet_unit(template_id)
				if not unit.is_empty():
					unit["hp"] = float(unit.get("max_hp", 50.0)) * 0.15
					unit["fielded"] = false
					unit["wounded"] = true
					unit["wound_turns"] = 2
				GlobalData.hangar.recruited_characters.append(character_id)
				GlobalData.hangar.duel_result_text = str(character.get("wreck_notice", "")) + " " + str(character.get("wounded_notice", ""))
		else:
			# Pilot dies: the wreck is parked as a pilotless, repairable berth.
			var mech := _park_salvage_wreck(character, template_id)
			GlobalData.hangar.recruited_characters.append(character_id)
			if not mech.is_empty():
				GlobalData.hangar.duel_result_text = str(character.get("wreck_notice", "")) + " %s is parked in the hangar. " % str(mech.get("name", "The wreck")) + str(character.get("dead_notice", ""))
			else:
				GlobalData.hangar.duel_result_text = str(character.get("parts_notice", "")) + " " + str(character.get("dead_notice", ""))
		return

	# Too damaged to salvage whole: only parts are recovered.
	var scrap_gained := randi_range(18, 30)
	var credits_gained := randi_range(40, 70)
	GlobalData.currency.gain_scrap(scrap_gained)
	GlobalData.currency.gain_credits(credits_gained)
	GlobalData.hangar.recruited_characters.append(character_id)
	var fate := str(character.get("dead_notice", "")) if randf() < 0.5 else str(character.get("wounded_notice", ""))
	GlobalData.hangar.duel_result_text = str(character.get("parts_notice", "")) + " +%d scrap, +%d credits. " % [scrap_gained, credits_gained] + fate


# Parks the shattered signature mech as a pilotless hangar berth with heavy
# part damage (repairable later). Returns the parked mech, or {} when no berth.
static func _park_salvage_wreck(character: Dictionary, template_id: String) -> Dictionary:
	var damage: Dictionary = {}
	for slot in GlobalData.MECHA_SLOTS:
		damage[slot] = randf_range(0.55, 0.95)
	var weapons := get_character_signature_weapons(str(character.get("id", "")))
	var mech := HangarManager.park_ally_mech(
		"%s (Wreck)" % str(character.get("mech_name", "Recruit Mech")),
		"",
		int(character.get("archetype", HangarManager.ARCHETYPE_RANGED)),
		damage,
		weapons
	)
	return mech


# -----------------------------------------------------------------------------
# EARLY HEAL — spend credits on the hangar roster to clear a wounded pilot's
# recovery countdown immediately (the alternative is waiting out wound_turns on
# board moves). Flat base + a premium per remaining turn, so healing a fresh
# two-turn wound costs more than one that's almost healed.
# -----------------------------------------------------------------------------
const HEAL_BASE_CREDITS := 40
const HEAL_PER_TURN_CREDITS := 20


# Credit price to heal `template_id`'s pilot right now (0 when not healable).
static func get_wound_heal_cost(template_id: String) -> int:
	var unit := FleetSystem.get_fleet_unit(template_id)
	if unit.is_empty() or not bool(unit.get("wounded", false)):
		return 0
	if bool(unit.get("destroyed", false)):
		return 0
	var turns := maxi(int(unit.get("wound_turns", 1)), 1)
	return HEAL_BASE_CREDITS + turns * HEAL_PER_TURN_CREDITS


# Spends credits to clear a wounded pilot's recovery timer: they return to the
# field at full HP (the natural-recovery tick only restores half). Returns false
# when the unit isn't wounded, is destroyed, or the credits can't be afforded.
static func heal_wounded_pilot(template_id: String) -> bool:
	var unit := FleetSystem.get_fleet_unit(template_id)
	if unit.is_empty() or not bool(unit.get("wounded", false)):
		return false
	if bool(unit.get("destroyed", false)):
		return false
	var cost := get_wound_heal_cost(template_id)
	if not GlobalData.currency.try_spend_credits(cost):
		return false
	unit["wounded"] = false
	unit["wound_turns"] = 0
	unit["fielded"] = true
	unit["hp"] = float(unit.get("max_hp", 50.0))
	return true


# Tick wounded pilots toward recovery (called on each board move).
static func tick_recovery() -> void:
	var recovered := false
	for unit in GlobalData.hangar.fleet_roster:
		if not (unit is Dictionary):
			continue
		if not unit.get("wounded", false):
			continue
		var turns := int(unit.get("wound_turns", 0))
		turns -= 1
		unit["wound_turns"] = turns
		if turns <= 0:
			unit["wounded"] = false
			unit["fielded"] = true
			unit["hp"] = float(unit.get("max_hp", 50.0)) * 0.5
			recovered = true
	if recovered:
		GlobalData.board.run_notice = "A wounded pilot has recovered and is ready to fight again."
