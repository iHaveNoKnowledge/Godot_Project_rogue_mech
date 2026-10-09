# Open Issues & Known Limitations

This document tracks unresolved investigations, technical debt, and known runtime limitations with concrete evidence.

---

## 1. Active Investigations

### Issue 1: Animation & Combat Lunge Synchronization
- **Category:** Combat / Animation Pipeline
- **Status:** **UNVERIFIED / OPEN INVESTIGATION**
- **Symptom Description:**
  - Mecha attack logic may move or lunge the character before the imported attack animation visually plays.
  - Full-body motion may not be visible; only certain body parts may appear animated during certain attacks.
- **Investigation Plan:**
  - Inspect animation blend trees, pivot writers, attack timing, bone retargeting, and weapon-layer masks.
  - Must not mark as resolved without a dedicated, reproducible regression test and visual confirmation.

### Issue 2: Offline LSP Server Environment
- **Category:** Developer Tooling / Serena Semantic Analysis
- **Status:** **ACTIVE WORKAROUND**
- **Description:**
  - Serena's GDScript LSP language backend expects Godot Editor running with LSP enabled on port 6008.
  - When Godot is not running in editor mode, LSP-based tools (`find_symbol`, `get_symbols_overview`, `find_referencing_symbols`) return connection errors.
- **Remediation / Standard Operating Procedure:**
  - Use exact text pattern search (`search_for_pattern`), direct file inspection (`view_file`), and Godot headless CLI test runners (`& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless ...`) for symbol and architecture validation.

---

## 2. Resolved Issues (Reference)
- **Phase C2.8 Scene Transition Seam (Resolved in `c67f8b1`):**
  - Exiting Hangar or finishing tactical combat previously returned unconditionally to `res://scenes/board/game_board.tscn`.
  - Resolved by adding campaign state check to `GameManager.return_to_board()`: if `current_campaign_player_node_id`, scenario ID, or registered campaign nodes are present, route to `res://scenes/ui/campaign_node_map.tscn`.
