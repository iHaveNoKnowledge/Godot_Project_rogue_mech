# Setup checklist for a new machine

Project-level pieces (already in the repo):
- `addons/godot_ai/` (Godot AI v3.2.5, enabled in `project.godot`)
- `.claude/settings.json` (declares the godot-claude-skills marketplace and plugin)

Per-machine steps (cannot be committed):
1. Godot 4.6.2 (project is pinned to this version in AGENTS.md).
2. Install uv (`irm https://astral.sh/uv/install.ps1 | iex` on Windows), then open a new terminal and confirm `uv --version`.
3. Open the project in Godot. Confirm Project Settings > Plugins shows Godot AI enabled.
4. In Godot AI dock, click Configure for Claude Code, then restart Claude Code.
5. When Claude Code asks, trust the godot-claude-skills marketplace. Confirm with `claude plugin list` that `godot-claude-skills` is enabled.
6. Optional: `mattpocock-skills` is user-scope and is not shared by this repo. Install it per machine if needed.
7. Run `sh ./run_tests.sh` with `GODOT_EXE` pointing to the local Godot 4.6.2 console binary.

Do not use Godot AI v4.x: its release line requires Godot 4.7 or newer.
