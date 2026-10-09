# Valkren Campaign V2 Architecture

## Strategic Systems
- **CampaignNodeRegistry**: Strategic Node and Route authority. Nodes have `map_position` Vector2 coordinates and explicit routes.
- **CampaignPlayerMovement**: Strategic route-based movement authority (1-hop hops along registered routes). Current node is tracked in `GlobalData.current_campaign_player_node_id`.
- **CampaignPlayerDispatch**: Action dispatch and capability validation (`investigate`, `resupply`, `trade`, `capture`, `attack`).
- **CampaignNodeInspection**: Node situation inspection authority.
- **CampaignTurnExecutive**: Campaign-level turn progression authority.

## Strategic UI Flow
- **Scene**: `res://scenes/ui/campaign_node_map.tscn` (`scripts/ui/campaign_node_map.gd`)
- **GameManager transitions**: `enter_node_map()`, `return_to_board()`, `return_to_node_map()`
- **Decoupling**: Strategic node map is fully decoupled from tactical 35x35 grid board.

Canonical documentation:
- `docs/ai/ARCHITECTURE_AUTHORITY_MAP.md`
- `docs/ai/PROJECT_BIBLE.md`
- `docs/ai/PHASE_STATUS.md`
