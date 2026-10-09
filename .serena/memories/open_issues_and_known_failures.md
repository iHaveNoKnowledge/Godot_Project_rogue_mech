# Open Issues & Known Limitations

## Active Investigations
1. **Animation / Combat Lunge Synchronization**:
   - Mecha logic may move/lunge character before attack animation plays visually. Full body motion might not be visible.
   - Requires deep inspection of animation blend trees, pivot writers, timing, retargeting, and weapon masks before code modifications.
   - Status: UNVERIFIED / OPEN INVESTIGATION.
2. **Serena LSP Offline Workaround**:
   - Godot Editor LSP is offline; use exact pattern search (`search_for_pattern`), file inspection, and CLI test suites for validation.

## Resolved Reference
- Phase C2.8 Scene Transition Seam: `GameManager.return_to_board()` now detects campaign state and routes to `campaign_node_map.tscn`. (Resolved in `c67f8b1`).

Canonical doc: `docs/ai/OPEN_ISSUES.md`
