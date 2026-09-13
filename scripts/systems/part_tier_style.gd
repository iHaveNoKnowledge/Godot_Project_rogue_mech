class_name PartTierStyle
extends RefCounted

## Central tier (0-3) -> color mapping for every part list in the game.
##
## Tier source of truth:
##   * Weapons carry an explicit `rarity` 0-3 (WeaponPart.rarity / inventory path).
##   * Armor / frames have no rarity field, so the tier is derived from the
##     catalog `type` label (and `name` as fallback):
##       T3 legendary = Valkyrion
##       T2 rare      = Wanzer / Vagrant / High-Mobility / Light Plating / Medium / Pre-Cog
##       T1 uncommon  = Heavy (incl. Super Heavy)
##       T0 common    = everything else (Standard / Light Armor ...)
##
## ItemList has no per-row border support, so rows get a tier-tinted background
## plus a solid tier-color stripe icon (reads as a left border). Buttons
## (loot picker, safehouse) get a real StyleBoxFlat border via style_button().

const TIER_NAMES: Array[String] = ["COMMON", "UNCOMMON", "RARE", "LEGENDARY"]

const TIER_COLORS: Array[Color] = [
	Color(0.62, 0.65, 0.68, 1.0), # T0 common — gray
	Color(0.25, 0.85, 0.45, 1.0), # T1 uncommon — green
	Color(0.32, 0.60, 1.00, 1.0), # T2 rare — blue
	Color(1.00, 0.70, 0.20, 1.0), # T3 legendary (Valkyrion) — gold
]

static var _stripe_cache: Dictionary = {}


static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, 0, 3)]


static func tier_color(tier: int) -> Color:
	return TIER_COLORS[clampi(tier, 0, 3)]


## Dark tinted row background so white text stays readable on every tier.
static func tier_bg_color(tier: int) -> Color:
	var c := tier_color(tier)
	return Color(c.r * 0.22 + 0.07, c.g * 0.22 + 0.07, c.b * 0.22 + 0.08, 1.0)


static func tier_tag(tier: int) -> String:
	return "[T%d %s]" % [clampi(tier, 0, 3), tier_name(tier)]


# --- tier resolution -------------------------------------------------------

static func _type_string(info: Dictionary) -> String:
	var t := str(info.get("type", ""))
	var n := str(info.get("name", info.get("part_name", "")))
	return (t + " " + n).to_lower()


## Armor instance / catalog entry -> tier 0-3.
static func armor_tier(info: Dictionary) -> int:
	if info.is_empty():
		return 0
	var s := _type_string(info)
	if s.contains("valkyrion"):
		return 3
	if s.contains("wanzer") or s.contains("vagrant") or s.contains("high-mobility") \
			or s.contains("high_mobility") or s.contains("light plating") \
			or s.contains("medium") or s.contains("pre-cog") or s.contains("pre_cog") \
			or s.contains("precog"):
		return 2
	if s.contains("heavy"):
		return 1
	return 0


## Inner-frame catalog entry -> tier 0-3.
static func frame_tier(info: Dictionary) -> int:
	if info.is_empty():
		return 0
	var s := _type_string(info)
	if s.contains("valkyrion"):
		return 3
	if s.contains("medium") or s.contains("pre-cog") or s.contains("pre_cog") \
			or s.contains("precog") or s.contains("vagrant") or s.contains("wanzer"):
		return 2
	if s.contains("heavy"):
		return 1
	return 0


## Weapon inventory dict -> tier 0-3. Prefers an explicit `rarity` key, falls
## back to loading the WeaponPart resource behind `path`.
static func weapon_tier(inv: Dictionary) -> int:
	if inv.is_empty():
		return 0
	if inv.has("rarity"):
		return clampi(int(inv["rarity"]), 0, 3)
	var path := str(inv.get("path", ""))
	if path != "" and ResourceLoader.exists(path):
		var res = load(path)
		if res != null and "rarity" in res:
			return clampi(int(res.rarity), 0, 3)
	return 0


## Battle-loot entry ({type, weapon/instance}) -> tier 0-3.
static func loot_entry_tier(entry: Dictionary) -> int:
	match str(entry.get("type", "")):
		"weapon":
			var w = entry.get("weapon")
			if w != null and "rarity" in w:
				return clampi(int(w.rarity), 0, 3)
			return 0
		"armor":
			var inst: Dictionary = entry.get("instance", {})
			return armor_tier(inst)
	return 0


# --- styling ---------------------------------------------------------------

## Solid-color stripe used as the ItemList row icon (left-border look).
static func tier_stripe(tier: int) -> Texture2D:
	tier = clampi(tier, 0, 3)
	if _stripe_cache.has(tier):
		return _stripe_cache[tier]
	var img := Image.create(6, 24, false, Image.FORMAT_RGBA8)
	img.fill(tier_color(tier))
	var tex := ImageTexture.create_from_image(img)
	_stripe_cache[tier] = tex
	return tex


## Applies tier colors to one ItemList row: tinted bg + stripe icon.
## Text color is left alone so rows stay readable in every theme.
static func apply_itemlist_row(list: ItemList, row: int, tier: int) -> void:
	if list == null or row < 0 or row >= list.item_count:
		return
	tier = clampi(tier, 0, 3)
	list.set_item_custom_bg_color(row, tier_bg_color(tier))
	list.set_item_icon(row, tier_stripe(tier))


## Real border for Button rows (loot picker, safehouse repair list).
static func style_button(btn: Button, tier: int) -> void:
	if btn == null:
		return
	tier = clampi(tier, 0, 3)
	var edge := tier_color(tier)
	var bg := tier_bg_color(tier)
	bg.a = 0.95
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg.lightened(0.12) if state == "hover" else bg
		sb.border_width_left = 3
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = edge
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
