# VALKREN — Campaign Design V2: Master Design & Architecture Specification

Status: Design Consolidation / Pre-Implementation
Engine: Godot 4.6.2
Philosophy: Living War Campaign / Pilot-Centric Roguelite / Modular Mecha

## 0. Design North Star
Valkren is NOT a clear-the-board game. It is a war that continues without the player; the Pilot is one person trying to survive, build power, and shift the war balance.
Fantasy chain: Pilot -> Mecha -> Build -> Small Force -> Base -> Technology -> Faction -> War.
Everything the player builds can be: lost, attacked, stolen, betrayed, captured, recovered, developed further.

## 1. Run Identity (LOCKED)
Priority: PILOT > MECHA > FRAME > PARTS > WEAPONS.
- Pilot = Run identity. Pilot dies -> Run End.
- Mecha: replaceable, destroyable, stealable, capturable, producible/recoverable.
- Parts: breakable, replaceable, salvageable. Weapons: breakable/lost/replaceable.
- Rule: losing a mecha must create CHANGE, not Game Over (e.g. Heavy destroyed -> no replacement -> Pilot takes Light -> whole playstyle changes). This is a feature, not only punishment.

## 2. Campaign Core Loop
PLAN -> MOVE -> OBSERVE -> DECIDE -> ACT -> CONSEQUENCE -> WORLD ADVANCES -> REPEAT.
NOT: Node -> Battle -> Reward -> Next Node.

## 3. Campaign Turn
Every significant player move/activity can advance the world: PLAYER ACTION -> CAMPAIGN TURN -> Faction/Patrol/Convoy/Base/Supply movements+battles+changes -> WORLD STATE UPDATED.
Mutable: faction movement, patrol/convoy location, base battle, supply, heat, threat, detection, research, events, territory.

## 4. Node (LOCKED)
Node = place/event/thing the player can act on (Patrol: avoid/engage/observe; Data Center: steal; Hangar: steal mecha; Supply Depot: raid; Research Facility: steal/sabotage/capture; Military Base: attack/capture; Rescue Site; Convoy: intercept; Battlefield: salvage/observe; Prison Transport; Boss).
Node != Territory. Not every node must be captured.

## 5. Route (LOCKED)
Route = movement/frontier/contact space. States: safe/unknown/patrol/convoy/ambush/interception/blocked/faction movement. NODE --ROUTE(world activity)-- NODE.

## 6. Faction System (LOCKED DIRECTION)
Not PLAYER vs ENEMY. Use: PLAYER, AUTHORITY, MILITIA, SCAVENGERS, MERCENARIES, SPECIAL/UNKNOWN (exact count not locked). Relations: HOSTILE/NEUTRAL/COOPERATIVE/ALLY, mutable.

## 7. Multi-Sided War
Combat/world events support 3+ forces (PLAYER vs AUTHORITY; AUTHORITY vs MILITIA; AUTHORITY vs SCAVENGERS; PLAYER+MILITIA vs AUTHORITY; 3-way; player may sit out).

## 8. Faction Movement
Factions never wait: move forces, attack bases, send convoys, capture nodes, withdraw, aid allies, attack other factions, retarget.

## 9. Player Faction Start (PROPOSED, not locked)
Option A Lone Pilot (pilot+mecha+small supply, no base/force -> survivors -> camp -> forward base -> small force -> faction). Option B Small Resistance (pilot+mecha+small force+base+low supply). Recommendation: A, but must audit vs existing opening/progression before locking.

## 10-11. Supply (LOCKED DIRECTION; formula PROPOSED)
Campaign resource for mecha recovery, force readiness, base ops, reinforcement, logistics, ops. Base set: SUPPLY, MATERIALS, DATA, SALVAGE (no bloat to 15 types). Bases produce supply/turn (e.g. 42/100, +4/turn) via base production, depots, convoys, captured facilities, faction support, logistics, salvage. Supply 0 != Game Over -> Supply Crisis (fewer replacements/reinforcements, limited repair, some ops blocked, weaker defense), recoverable by foraging.

## 12-14. Base (capability hub, not management sim)
Systems: Supply/Logistics, Arsenal, Factory/Mecha Recovery, Intelligence, Research, Force Capacity (not 30 building types). Upgrades unlock CAPABILITIES (weapon pools, archetypes, supply capacity/income, intel visibility ladder unknown->patrol->convoy->faction movement->upcoming ops, advanced tech, force capacity). Base lifecycle: OWNED -> UNDER ATTACK -> CRITICAL -> CAPTURED (never instantly disappears); player can travel back and INTERVENE in ongoing playable combat.

## 15-16. Auto Battle + Intervention (LOCKED DIRECTION)
Force battle over multiple turns (70->55->40 vs 90->70->48), 3+ factions supported. Player arrival converts CAMPAIGN BATTLE -> optional INTERVENTION playable combat; withdrawal returns it to world battle (never reset).

## 17-19. Heat / Threat / Detection (LOCKED)
- Heat = enemy awareness/pursuit pressure (from killing patrols, stealing prototypes, raiding bases, key missions, being spotted, killing commanders). High heat -> more patrols/detection/pursuit, riskier routes. Heat != Territory.
- Threat = enemy willingness/capability to attack OUR assets (high heat = hunted pilot; high threat = base attack incoming).
- Detection ladder: DETECTION -> SUSPICION -> RESPONSE -> ENGAGEMENT? (never auto-100% battle). Outcomes: undetected/suspicious/investigated/patrol/pursuit/escape/stealth objective/battle.

## 20. Stolen Mecha / Disguise
Enemy mecha (e.g. Mk-II) gives IFF-compatible infiltration (lower detection) but never perfect disguise. Factors: IFF, restricted zones, behavior, wrong equipment, suspicious movement. Ladder: low detection -> suspicion -> identity compromised -> interception.

## 21-25. Research & Technology (LOCKED DIRECTION)
Research = new ways of fighting (not +10% damage): Improvement / Specialized (archetypes) / Advanced (gameplay-changing) / Unique-Experimental (rare). Examples: Field Modular Assembly (field detach+spare/salvage assembly, even enemy arms), Salvage Engineering (recover/reverse-engineer/reuse), Directed Energy Warfare (laser frames, beam platforms, energy blades + heat/energy/cooling/capacitor tradeoffs), Autonomous Warfare (recon/attack/shield/repair/decoy drones, never RTS micro), Distributed Control (fight on with subsystems down), Experimental Frames. Discovery via facilities+data, elite/prototype salvage reverse-engineering, faction sharing. Tech CAN BE LOST (theft, destruction, captured scientists, lost data) and CAN PROLIFERATE (enemy steals and fields it).

## 26. Salvage
Battlefields persist as Battlefield Nodes (wrecks, parts, weapons, data, survivors, prototypes), harvestable later.

## 27. Convoy
Cargo unknown until hit: supply, mecha, parts, prisoners, research data, scientists, weapons, prototypes, commanders (possibly decoys).

## 28-31. Personnel / Defection / Capture (defection PROPOSED HIGH PRIORITY)
Personnel states: recruit/injure/capture/rescue/defect/die/leave/return. Defection levels: individual/commander/unit/faction/faction-split, NEVER pure RNG — driven by trust/loyalty/payment/fear/ideology/faction pressure/player actions with warnings (dissatisfaction -> suspicious activity -> ultimatum -> defection). Capture creates Prison Transport/Facility nodes; player may rescue/intercept/exchange/ignore/negotiate.

## 32-33. Faction Requests & Reputation
Factions request aid (intercept/defend/rescue/deliver/steal); player may accept/ignore/betray/sell info/help rivals. Reputation is remembered per faction (not MMO spreadsheet) and gates events, trust, prices, recruitment, tech sharing, defection odds, alliances.

## 34-36. Information / Recon / Black Market
Intel is never omniscience: old/incomplete/wrong/decoy possible. Recon via pilot/recon mecha/drones/stolen mecha before committing. Black Market campaign/event node: buy supply/mecha/IFF/intel, sell salvage, hire mercs/pilots, buy prototypes — with risk.

## 37. Companion Design (LOCKED DIRECTION)
Reduce companion customization: Character -> Role -> Personality -> Ability -> Mecha Archetype -> Preset Loadout (deep modular stays on main pilot). Companions can vanish, be captured, betray, die, switch sides.

## 38-40. World Memory & Events (CORE PRINCIPLE)
Every major action must leave state change (steal prototype -> recovery team; kill commander -> replacement; help militia -> stronger militia; ignore base attack -> enemy gains base; raid supply -> weakened logistics; save scientist -> research unlocked). Events = WORLD STATE + CONDITIONS + FACTION RELATIONS + PLAYER HISTORY + RANDOMNESS (randomness assists, never solely decides). Examples: betrayal, tech theft, base attack, scavenger opportunism, faction split.

## 41. Resource Model
SUPPLY (war/base/force) / MATERIALS (produce/repair/build) / DATA (research) / SALVAGE (battlefield -> material/data/prototype). No new resource for single systems.

## 42. Existing Architecture (DO NOT DUPLICATE without audit)
Campaign/board nodes, board->combat lifecycle, player authority, mecha identity, hangar, mecha base, modular parts, PartMeshManager, WeaponVisualFactory, AttachmentManager, weapon mounts/handling, MechaWeaponLayer, frame capability, save system, progression, combat lifecycle, board-to-battle identity. Campaign V2 must CONNECT to existing architecture, not build a parallel game.

## 43. Mandatory Pre-Implementation Audit (NO production code changes during audit)
Audit: (A) campaign node/route/movement/turn/board/save; (B) faction abstraction + Enemy/Player hardcodes + relations; (C) base ownership/persistence/attack/capture/progression; (D) supply/inventory/repair/replacement/campaign resources; (E) research/tech/unlocks/data/save; (F) personnel (pilot/companion/commander/character data); (G) world/random events + campaign mutation; (H) combat multi-force/enemy identity/replacement/salvage hooks.

## 44. Feature Status
LOCKED: pilot=run, replaceable mecha, node!=territory, route=movement/frontier, living world, campaign turns, multi-faction, detection ladder, heat!=threat, attackable/capturable/recoverable bases, auto-battle+intervention, gameplay-changing research, supply exists, reduced companion customization.
PROPOSED/NEEDS DECISION: lone-pilot start, supply formula, force model, base upgrade levels, resource numbers, tech tier count, faction count, personnel/prisoner/black-market depth.
NEW TO DESIGN: defection, faction split, tech theft, battlefield persistence, convoy cargo, dynamic events, info reliability, research discovery, field assembly, drones.
DO NOT BUILD YET: full economy sim, individual soldiers, 20+ resources, tower defense, huge diplomacy, staff mgmt, giant base-building, drone RTS micro, complex politics sim.

## 45. Implementation Order
C1 state foundation -> C2 node/route/turn -> C3 faction/relations -> C4 detection/heat/threat -> C5 base/ownership/force -> C6 supply/logistics -> C7 dynamic world movement -> C8 auto-battle/intervention -> C9 events -> C10 research/tech -> C11 salvage/prototype -> C12 defection/betrayal -> C13 advanced (drone/field assembly/etc.). Events/research/defection need trustworthy world state first.

## 46. Agent Hard Constraints
DO NOT IMPLEMENT FROM THIS DOCUMENT ALONE. First audit existing Valkren architecture; identify existing/partial-overlap/extend/obsolete; no duplicates, no unrelated refactors, no behavior removal without evidence, no speculative features during audit. Produce evidence-based migration plan first. Every phase: BASELINE -> AUDIT -> CHANGE PLAN -> IMPLEMENT -> TEST -> REGRESSION -> COMMIT -> PUSH.

## 47. Heart (7 sentences)
1. Pilot is the Run. 2. Mecha is what the pilot uses, not the Run identity. 3. The world moves on even without the player. 4. Nodes are places/opportunities, not tiles to capture. 5. Factions have goals and mutable relations. 6. Technology changes how war is fought, not just numbers. 7. Player actions must leave traces in the world.
Next step recommendation: do NOT code yet — run Campaign Architecture Audit from this spec, return EXISTING->MODIFY->NEW->REMOVE table against real Valkren code before any new phase.
