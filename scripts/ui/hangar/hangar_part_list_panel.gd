class_name HangarPartListPanel
extends RefCounted

## Part list populate + selection logic for the hangar customize page. Extracted
## from hangar_controller.gd.
##
## Builds the per-slot item list (upgrade / attachment / frame / weapon / armor
## modes), drives the stats label for the selected row, resolves the selected
## part's info for the ACTION MENU popup, and answers equipped/durability
## queries shared with the catalog panel. The controller owns the ItemList /
## stats Label nodes; this panel fills and reacts to them.

var controller: Node

# Selection state (moved out of the controller with this cluster).
var _is_populating: bool = false
var _last_selected_item_index: int = -1


func populate(slot: String) -> void:
	controller.action_panel.close()
	controller.part_item_list.clear()
	_last_selected_item_index = -1
	controller.visible_salvage_indices.clear()
	_is_populating = true  # Block 3D preview during auto-populate

	if controller.current_mode == "upgrade":
		var cost = controller._get_upgrade_cost()
		controller.part_item_list.add_item("Upgrade Inner Frame to Level %d (%d cr)" % [
			GlobalData.frame_upgrade_level + 1, cost
		])
		if controller.part_item_list.item_count > 0:
			controller.part_item_list.select(0)
			_last_selected_item_index = 0
			on_item_selected(0)
		_is_populating = false
		return

	if controller.current_mode == "attachment":
		if slot not in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
			controller.part_item_list.add_item("Select a body section first")
		else:
			var capacity = controller.garage_panel.get_attachment_capacity(slot)
			for info in controller.attachment_catalog:
				var prefix = "[E] " if controller.garage_panel.has_attachment(info["id"], slot) else "    "
				controller.part_item_list.add_item("%s%s (%.1fkg / %.1fkg capacity)" % [prefix, info["name"], info["weight"], capacity])
			if controller.part_item_list.item_count > 0:
				controller.part_item_list.select(0)
				_last_selected_item_index = 0
				on_item_selected(0)
		_is_populating = false
		return

	var is_destroyed = GlobalData.part_damage.get(slot + "_frame", 0.0) >= 1.0

	if controller.current_mode == "frame" and controller.frame_catalog.has(slot):
		var items = controller.frame_catalog[slot]
		# Roguelike: a destroyed frame is gone (same is_destroyed flag above). Hide
		# the equipped broken frame so it can no longer be repaired or re-selected.
		for info in items:
			var is_eq = is_item_equipped(slot, info)
			if is_eq and is_destroyed:
				continue
			var prefix = "[X] " if is_eq and is_destroyed else ("[E] " if is_eq else "     ")
			# A frame already installed on ANOTHER parked mech is marked so the
			# player sees it is taken (and equipping it here would remove it there).
			var other_user := other_mech_frame_user(slot, info)
			if prefix.strip_edges() == "" and other_user != "":
				prefix = "[E·%s] " % other_user
			var fname = info.get("name", "Frame Part")
			var fhp = info.get("hp", 20.0)
			var fwt = info.get("weight", 3.0)
			var state_tag = " [DESTROYED]" if (is_eq and is_destroyed) else ""
			var label_str = "%s%s (HP: %.0f, %.1fkg)%s" % [prefix, fname, fhp, fwt, state_tag]
			controller.part_item_list.add_item(label_str)
		if items.size() > 0:
			controller.part_item_list.select(0)
			_last_selected_item_index = 0
			on_item_selected(0)
	elif slot.begins_with("weapon"):
		# A destroyed arm cannot hold a weapon: the hand is gone, so hide the
		# weapon list for that hand and show why instead (mirrors the combat rule
		# that a broken arm cannot fire or wield anything).
		if slot == "weapon_left" or slot == "weapon_right":
			var hand := "left" if slot == "weapon_left" else "right"
			var arm_slot := "arm_left" if hand == "left" else "arm_right"
			if float(GlobalData.part_damage.get(arm_slot + "_frame", 0.0)) >= 1.0:
				controller.visible_weapon_indices.clear()
				controller.part_item_list.add_item("ARM DESTROYED — cannot equip a weapon to this hand. Repair or replace the arm.")
				_is_populating = false
				return
		# Weapons come from the central inventory stash (GlobalData.weapon_inventory),
		# NOT from armor_catalog — the stash is the single source of owned weapons.
		# Each inventory entry is one physical copy; the equipped copy is matched
		# by INSTANCE uid so only that row ever shows "[E]" (same-model copies are
		# separate rows). Equipped / other-mech-taken rows sort to the BOTTOM so
		# the free spares read first.
		controller.visible_weapon_indices.clear()
		var wrows: Array = []
		for index in range(GlobalData.weapon_inventory.size()):
			var inv = GlobalData.weapon_inventory[index]
			var other_user := other_mech_weapon_user(str(inv.get("uid", "")), str(inv.get("path", "")))
			wrows.append({"idx": index, "eq": weapon_in_loadout(slot, inv), "other": other_user})
		wrows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ea := 1 if (a["eq"] or a["other"] != "") else 0
			var eb := 1 if (b["eq"] or b["other"] != "") else 0
			if ea != eb:
				return ea < eb
			return int(a["idx"]) < int(b["idx"]))
		for row in wrows:
			var index: int = row["idx"]
			var inv = GlobalData.weapon_inventory[index]
			var wname = inv.get("name", "Weapon")
			var wdur = GlobalData.get_durability_ratio(inv)
			var is_eq = weapon_in_loadout(slot, inv)
			var prefix = "[E] " if is_eq else "    "
			# A weapon model already carried by ANOTHER parked mech is marked so
			# it never reads as an unclaimed spare (equipping it transfers it).
			var other_user := str(row["other"])
			if prefix.strip_edges() == "" and other_user != "":
				prefix = "[E·%s] " % other_user
			var label_str = "%s%s (DUR: %.0f%%)" % [prefix, wname, wdur * 100.0]
			controller.part_item_list.add_item(label_str)
			controller.visible_weapon_indices.append(index)
		if controller.part_item_list.item_count > 0:
			controller.part_item_list.select(0)
			_last_selected_item_index = 0
			on_item_selected(0)
	elif controller.armor_catalog.has(slot):
		# EQUIP list = owned armor instances only. The equipped slot is matched
		# strictly by instance uid, so exactly one item ever shows "[E]". The
		# currently equipped instance is always included by uid even if its stored
		# slot tag is missing/stale (legacy saves). Crafting lives in the separate
		# Craftery window and never alters what appears here.
		controller.visible_salvage_indices.clear()
		var shown_uids := {}
		var equipped_uid := ""
		var eq_part = GlobalData.equipped_parts.get(slot)
		if eq_part is Dictionary:
			equipped_uid = str(eq_part.get("uid", ""))
		var arows: Array = []
		for inst_index in range(GlobalData.armor_inventory.size()):
			var inst = GlobalData.armor_inventory[inst_index]
			var uid = str(inst.get("uid", ""))
			if str(inst.get("slot", "")) != slot and uid != equipped_uid:
				continue
			if uid in shown_uids and uid != "":
				continue
			if uid != "":
				shown_uids[uid] = true
			var is_eq = is_item_equipped(slot, inst)
			# Roguelike: a destroyed part is gone. Hide the equipped broken armor
			# so it can no longer be selected, repaired, or re-equipped.
			if is_eq and (GlobalData.part_damage.get(slot, 0.0) >= 1.0 or GlobalData.part_damage.get(slot + "_frame", 0.0) >= 1.0):
				continue
			var other_user := other_mech_armor_user(uid) if not is_eq else ""
			arows.append({"idx": inst_index, "eq": is_eq, "other": other_user})
		# Free plates first; equipped / other-mech-taken plates sort to the bottom.
		arows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ea := 1 if (a["eq"] or a["other"] != "") else 0
			var eb := 1 if (b["eq"] or b["other"] != "") else 0
			if ea != eb:
				return ea < eb
			return int(a["idx"]) < int(b["idx"]))
		for row in arows:
			var inst = GlobalData.armor_inventory[int(row["idx"])]
			var uid = str(inst.get("uid", ""))
			var is_eq = is_item_equipped(slot, inst)
			var prefix = "[E] " if is_eq else "    "
			var other_user := str(row["other"])
			if prefix.strip_edges() == "" and other_user != "":
				prefix = "[E·%s] " % other_user
			var state_tag = " [DESTROYED]" if (is_eq and is_destroyed) else ""
			var dur_pct = instance_durability(slot, inst)
			var inst_label = "%s%s [%s] (%.0f%%)%s" % [prefix, inst.get("name", "Armor"), inst.get("type", "Instance"), dur_pct * 100.0, state_tag]
			controller.part_item_list.add_item(inst_label)
			controller.visible_salvage_indices.append(int(row["idx"]))
		if controller.part_item_list.item_count > 0:
			controller.part_item_list.select(0)
			_last_selected_item_index = 0
			on_item_selected(0)

	_is_populating = false  # Restore flag


func on_item_selected(index: int) -> void:
	if controller.current_mode == "upgrade":
		var cost = controller._get_upgrade_cost()
		controller.stats_label.text = "INNER FRAME REACTOR LEVEL: %d -> %d\n\nEFFECTS:\n+25 FRAME HP per slot\n+15.0 kg MAX WEIGHT CAPACITY\n+1.5 m/s DASH THRUST SPEED\n\nUPGRADE COST: %d Credits" % [
			GlobalData.frame_upgrade_level, GlobalData.frame_upgrade_level + 1, cost
		]
		controller.selected_salvage_info = {}
		controller.update_tier_display({"upgrade_level": GlobalData.frame_upgrade_level}, "")
		return

	if controller.current_mode == "attachment":
		if index < 0 or index >= controller.attachment_catalog.size(): return
		controller.selected_attachment_info = controller.attachment_catalog[index].duplicate(true)
		controller.selected_attachment_info["slot"] = controller.selected_slot
		var capacity = controller.garage_panel.get_attachment_capacity(controller.selected_slot)
		var used = controller.garage_panel.get_attachment_weight(controller.selected_slot, controller.selected_attachment_info["id"])
		controller.stats_label.text = "ATTACHMENT: %s\n\nTARGET SECTION: %s\nWEIGHT: %.1f kg\nSECTION CAPACITY: %.1f kg\nCURRENT LOAD: %.1f kg\nPOWER COST: %.1f\n\nDrag on the 3D Mecha to place this module." % [
			controller.selected_attachment_info["name"], controller.selected_slot.to_upper(), controller.selected_attachment_info["weight"], capacity, used, controller.selected_attachment_info["power_cost"]
		]
		return

	if controller.current_mode == "frame" and controller.frame_catalog.has(controller.selected_slot):
		var frame_items = controller.frame_catalog[controller.selected_slot]
		if index >= 0 and index < frame_items.size():
			controller.selected_frame_info = frame_items[index]
			controller.selected_part_path = ""
			controller.selected_part_id = ""
			controller.selected_salvage_info = {}

			var fname = controller.selected_frame_info.get("name", controller.selected_frame_info.get("part_name", "Inner Frame"))
			var fcap = HangarPartText.frame_capability_text(controller.selected_frame_info)
			var is_eq = is_item_equipped(controller.selected_slot, controller.selected_frame_info)
			if is_eq:
				var frame_dmg = GlobalData.part_damage.get(controller.selected_slot + "_frame", 0.0)
				controller.stats_label.text = "INNER FRAME PART: %s  [E]\nDURABILITY: %.0f%%\n\n%s\n\nThis frame is currently equipped." % [
					fname, (1.0 - clampf(frame_dmg, 0.0, 1.0)) * 100.0, fcap
				]
			else:
				controller.stats_label.text = "INNER FRAME PART: %s\nDURABILITY: 100%%\n\n%s\n\nEquip this frame to install it fresh at 100%% HP." % [
					fname, fcap
				]
			# Only change 3D model when user explicitly picks a part, not on section switch
			if not _is_populating:
				controller.garage_panel.apply_frame_preview(controller.selected_slot, controller.selected_frame_info)
		controller.update_tier_display(controller.selected_frame_info, controller.selected_slot)
		controller.stats_panel.update()
		return

	if controller.selected_slot.begins_with("weapon"):
		if index >= 0 and index < controller.visible_weapon_indices.size():
			var inv_idx = controller.visible_weapon_indices[index]
			var inv = GlobalData.weapon_inventory[inv_idx]
			var wpath = inv.get("path", "")
			controller.selected_part_path = wpath
			controller.selected_part_id = wpath
			controller.selected_weapon_uid = str(inv.get("uid", ""))
			controller.selected_frame_info = {}
			controller.selected_salvage_info = {}

			var wname = inv.get("name", "Weapon")
			var wdur = GlobalData.get_durability_ratio(inv)
			var wwt := 0.0
			var wtype := "Unknown"
			var wcap := ""
			var res = null
			if wpath != "" and ResourceLoader.exists(wpath):
				res = load(wpath)
				if res:
					wwt = float(res.weight) if "weight" in res and res.weight != null else 0.0
					wtype = HangarPartText.weapon_type_label(res.weapon_type) if "weapon_type" in res else "Unknown"
					wcap = HangarPartText.weapon_capability_text(res)

			if controller.selected_slot == "weapon_carry":
				var eq = LoadoutSystem.is_weapon_in_carry(wpath)
				var carried := LoadoutSystem.count_carry_weapon(wpath)
				var owned := LoadoutSystem.count_owned_weapon(wpath)
				var prefix = "[E] " if eq else ""
				var copies := ""
				if owned > 1:
					copies = "\nOWNED: x%d | ON PACK: x%d" % [owned, carried]
				controller.stats_label.text = "BACK CARRY: %s%s\nDURABILITY: %.0f%%%s\n\n%s\nWEIGHT: %.1f kg\n\nAssigns a copy to the mech's back pack (FIELD PACK).\nFIELD PACK: %.1f / %.1f kg\nPick weapons from the stash below." % [
					prefix, wname, wdur * 100.0, copies, wcap if not wcap.is_empty() else "TYPE: %s" % wtype,
					wwt,
					LoadoutSystem.get_field_pack_weight(), LoadoutSystem.get_field_pack_capacity()
				]
			else:
				var hand = "left" if controller.selected_slot == "weapon_left" else "right"
				var eq = LoadoutSystem.get_equipped_weapon_uid(hand) == str(inv.get("uid", ""))
				var prefix = "[E] " if eq else ""
				controller.stats_label.text = "%s HAND WEAPON: %s%s\nDURABILITY: %.0f%%\n\n%s\nWEIGHT: %.1f kg\n\nEquip this weapon to the %s hand.\nFIELD PACK: %.1f / %.1f kg" % [
					hand.to_upper(), prefix, wname, wdur * 100.0, wcap if not wcap.is_empty() else "TYPE: %s" % wtype,
					wwt, hand,
					LoadoutSystem.get_field_pack_weight(), LoadoutSystem.get_field_pack_capacity()
				]
			# Only change 3D model when user explicitly picks a part, not on section switch
			if not _is_populating:
				controller.garage_panel.preview_weapon_on_hand(controller.selected_slot, inv)
			controller.update_tier_display(inv, controller.selected_slot)
		controller.stats_panel.update()
		return

	if controller.armor_catalog.has(controller.selected_slot):
		if index >= 0 and index < controller.visible_salvage_indices.size():
			var salvaged_idx = controller.visible_salvage_indices[index]
			controller.selected_salvage_info = GlobalData.armor_inventory[salvaged_idx]
			controller.selected_part_path = ""
			controller.selected_part_id = ""
			controller.selected_frame_info = {}

			var item_name = controller.selected_salvage_info.get("name", controller.selected_salvage_info.get("part_name", "Armor Instance"))
			var acap = HangarPartText.armor_capability_text(controller.selected_salvage_info, instance_durability(controller.selected_slot, controller.selected_salvage_info))

			var is_eq = is_item_equipped(controller.selected_slot, controller.selected_salvage_info)
			if is_eq:
				controller.stats_label.text = "OWNED ARMOR: %s  [E]\nDURABILITY: %.0f%%\n\n%s\n\nThis plate is currently equipped." % [
					item_name, instance_durability(controller.selected_slot, controller.selected_salvage_info) * 100.0, acap
				]
			else:
				var dur_pct = instance_durability(controller.selected_slot, controller.selected_salvage_info)
				controller.stats_label.text = "OWNED ARMOR: %s\nDURABILITY: %.0f%%\n\n%s\n\nEquip this plate to install it." % [
					item_name, dur_pct * 100.0, acap
				]
			# Only change 3D model when user explicitly picks a part, not on section switch
			if not _is_populating:
				controller.garage_panel.apply_salvage_preview(controller.selected_slot, controller.selected_salvage_info)
	controller.update_tier_display(controller.selected_salvage_info, controller.selected_slot)
	controller.stats_panel.update()


func on_item_clicked(index: int, _at_position: Vector2 = Vector2.ZERO, _mouse_button_index: int = 1) -> void:
	# Single click: select & close any open modal. The Action Popup opens on
	# double-click (item_activated) so a click never accidentally triggers it.
	if index != _last_selected_item_index:
		_last_selected_item_index = index
		on_item_selected(index)
	controller.action_panel.close()


func on_item_activated(index: int) -> void:
	# Double-click (or Enter): Open the Action Popup Modal!
	var info_to_show: Dictionary = resolve_info_for_index(index)
	if not info_to_show.is_empty():
		controller.action_panel.show(info_to_show)


func resolve_info_for_index(index: int) -> Dictionary:
	var info_to_show: Dictionary = {}
	if not controller.selected_salvage_info.is_empty():
		info_to_show = controller.selected_salvage_info
	elif not controller.selected_frame_info.is_empty():
		info_to_show = controller.selected_frame_info
	elif controller.current_mode == "frame" and controller.frame_catalog.has(controller.selected_slot):
		var items = controller.frame_catalog[controller.selected_slot]
		if index >= 0 and index < items.size():
			info_to_show = items[index]
	elif controller.selected_slot.begins_with("weapon"):
		if index >= 0 and index < controller.visible_weapon_indices.size():
			var inv_idx = controller.visible_weapon_indices[index]
			info_to_show = GlobalData.weapon_inventory[inv_idx]
	elif controller.armor_catalog.has(controller.selected_slot):
		if index >= 0 and index < controller.visible_salvage_indices.size():
			info_to_show = GlobalData.armor_inventory[controller.visible_salvage_indices[index]]
	return info_to_show


func is_item_equipped(slot: String, info: Dictionary) -> bool:
	if info.is_empty():
		return false

	if slot.begins_with("weapon"):
		return weapon_in_loadout(slot, info)

	if controller.current_mode == "frame":
		var cur_frame = GlobalData.equipped_frames.get(slot, {})
		if cur_frame is Dictionary and not cur_frame.is_empty():
			var name_a = cur_frame.get("name", cur_frame.get("part_name", "")).to_lower()
			var name_b = info.get("name", info.get("part_name", "")).to_lower()
			if name_a != "" and name_b != "":
				return name_a == name_b
		return false
	else:
		var cur = GlobalData.equipped_parts.get(slot)
		if cur == null:
			return false

		# 0. Match by instance uid (authoritative for owned instances)
		if cur is Dictionary and cur.has("uid") and info.has("uid"):
			return cur["uid"] == info["uid"]

		# 1. Match by unique ID if available
		var cur_id = ""
		if cur is Dictionary:
			cur_id = cur.get("id", "")
		elif cur is Resource and "id" in cur:
			cur_id = cur.id
		var info_id = info.get("id", "")
		# Catalog IDs are authoritative. Do not fall back to path/name when both
		# entries share the same Resource path.
		if info_id != "":
			return cur_id != "" and cur_id == info_id
		if cur_id != "":
			return false

		# 2. Match by Resource file path
		var cur_path = ""
		if cur is Dictionary:
			cur_path = cur.get("path", "")
		elif cur is Resource:
			cur_path = cur.resource_path
		var info_path = info.get("path", "")
		if cur_path != "" and info_path != "" and cur_path == info_path:
			return true

		# 3. Match by Part Name
		var cur_name = ""
		if cur is Dictionary:
			cur_name = cur.get("name", cur.get("part_name", "")).to_lower()
		elif cur is Resource and "part_name" in cur:
			cur_name = cur.part_name.to_lower()
		var info_name = info.get("name", info.get("part_name", "")).to_lower()
		if cur_name != "" and info_name != "":
			return cur_name == info_name

		return false


# Current durability fraction (0..1) of an owned armor instance. Uses the live
# combat damage cache for the equipped one, otherwise the instance's persisted
# durability.
func instance_durability(slot: String, inst: Dictionary) -> float:
	if is_item_equipped(slot, inst):
		return GlobalData.get_part_durability(slot)
	return GlobalData.get_durability_ratio(inst)


# Whether this weapon INSTANCE (matched by uid) is part of the current loadout
# for this weapon slot. Only the equipped copy's uid matches, so same-model
# copies never share the "[E]" badge.
func weapon_in_loadout(slot: String, inv: Dictionary) -> bool:
	var uid := str(inv.get("uid", ""))
	if uid == "":
		return false
	if slot == "weapon_carry":
		return LoadoutSystem.is_weapon_in_carry_by_uid(uid)
	var hand = "left" if slot == "weapon_left" else "right"
	return LoadoutSystem.get_equipped_weapon_uid(hand) == uid


# ---------------------------------------------------------------------------
# PARTS USED BY OTHER MECHS
# A parked mech's snapshot owns its equipped parts. The shared inventories
# (armor instances, weapon stash, frame catalog) are shown in EVERY mech's
# list, so a part that another berth already wears must be marked as taken —
# otherwise it reads as an unclaimed spare and gets "duplicated" by equipping.
# These helpers return the name of the other mech using a part, or "".
# ---------------------------------------------------------------------------

# A weapon COPY (matched by instance uid) counts as used by another mech when
# that EXACT copy sits in another berth's loadout. Same-model copies are
# separate physical units, so a free spare is never marked as taken. Legacy
# path rows fall back to a model-level check: the model only reads as taken
# when every owned copy is already carried somewhere in the fleet.
func other_mech_weapon_user(uid: String, path: String) -> String:
	var editing_id: String = controller.get_editing_mech_id()
	if uid != "":
		var by_uid := _other_mech_weapon_uid_user(uid, editing_id)
		if by_uid != "":
			return by_uid
	if path == "":
		return ""
	if LoadoutSystem.has_fleet_spare_weapon(path, editing_id):
		return ""
	var first_user := ""
	for mech in GlobalData.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mid := str(mech.get("id", ""))
		if mid == "" or mid == editing_id:
			continue
		var loadout = mech.get("weapon_loadout", {})
		if not (loadout is Dictionary):
			continue
		if LoadoutSystem.weapon_slot_in_loadout(loadout, path) != "":
			if first_user == "":
				first_user = str(mech.get("name", "Mech"))
	return first_user


# The OTHER parked mech whose loadout holds this exact instance uid.
func _other_mech_weapon_uid_user(uid: String, editing_id: String) -> String:
	if uid == "":
		return ""
	for mech in GlobalData.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mid := str(mech.get("id", ""))
		if mid == "" or mid == editing_id:
			continue
		var loadout = mech.get("weapon_loadout", {})
		if not (loadout is Dictionary):
			continue
		if str(loadout.get("left", "")) == uid or str(loadout.get("right", "")) == uid:
			return str(mech.get("name", "Mech"))
		var carry = loadout.get("carry", [])
		if carry is Array and uid in carry:
			return str(mech.get("name", "Mech"))
	return ""


# An armor instance (matched by uid) is used by another mech when its parts
# snapshot references the same uid in any slot.
func other_mech_armor_user(uid: String) -> String:
	if uid == "":
		return ""
	var editing_id: String = controller.get_editing_mech_id()
	for mech in GlobalData.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mid := str(mech.get("id", ""))
		if mid == "" or mid == editing_id:
			continue
		var parts = mech.get("parts", {})
		if not (parts is Dictionary):
			continue
		for slot in parts:
			var part = parts[slot]
			if part is Dictionary and str(part.get("uid", "")) == uid:
				return str(mech.get("name", "Mech"))
	return ""


# A frame model (matched by id, falling back to name) is used by another mech
# when its frames snapshot holds the same entry in this slot.
func other_mech_frame_user(slot: String, info: Dictionary) -> String:
	if info.is_empty():
		return ""
	var editing_id: String = controller.get_editing_mech_id()
	var info_id := str(info.get("id", ""))
	var info_name := str(info.get("name", info.get("part_name", ""))).to_lower()
	for mech in GlobalData.hangar_mechs:
		if not (mech is Dictionary):
			continue
		var mid := str(mech.get("id", ""))
		if mid == "" or mid == editing_id:
			continue
		var frames = mech.get("frames", {})
		if not (frames is Dictionary):
			continue
		var f = frames.get(slot)
		if not (f is Dictionary):
			continue
		if info_id != "" and str(f.get("id", "")) == info_id:
			return str(mech.get("name", "Mech"))
		if info_name != "" and str(f.get("name", f.get("part_name", ""))).to_lower() == info_name:
			return str(mech.get("name", "Mech"))
	return ""
