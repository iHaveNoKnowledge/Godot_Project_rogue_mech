class_name HangarScrapPanel
extends RefCounted
# Owns the hangar's scrap-repair editor callbacks:
#   * refresh() — the editor applied a patch or was dismissed: re-sync the
#                 hangar's own 3D mech preview so the crude scrap armor shows
#                 on the correct skeleton parts.
#
# Both editor signals route here (applied passes a slot that is intentionally
# discarded — the original code never used it either), so the panel exposes a
# single method instead of two identical ones.
#
# The emergency editor itself is created by HangarNavPanel (it owns the
# emergency submenu); this panel only handles the editor's signals. The preview
# refresh goes through `controller.` so the seam matches the other Hangar*Panel
# scripts.

var controller  # hangar_controller.gd


# A patch was applied (or the editor closed): re-sync the 3D preview.
func refresh() -> void:
	controller.garage_panel.call_deferred("update_all_slots_preview")
