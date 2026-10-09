# VALKREN — Campaign Design V2: Master Design & Architecture Specification

Status: Design Consolidation / Pre-Implementation
Engine: Godot 4.6.2.stable
Primary Philosophy: Living War Campaign / Pilot-Centric Roguelite / Modular Mecha

Synced from user master spec (2026-10-09) + Serena memory `campaign/design_v2_master_spec`.
Canonical doc family: `docs/ai/PROJECT_BIBLE.md`, `docs/ai/ARCHITECTURE_AUTHORITY_MAP.md`, `docs/ai/PHASE_STATUS.md`.

## 0. Design North Star

Valkren ไม่ควรเป็นเกมที่ผู้เล่นค่อย ๆ เคลียร์กระดานให้ครบ แต่ควรเป็นสงครามที่ดำเนินต่อไปโดยไม่มีผู้เล่น และ Pilot เป็นคนหนึ่งคนที่พยายามเอาชีวิตรอด สร้างกำลังของตัวเอง และเปลี่ยนสมดุลของสงคราม.

Core fantasy: Pilot → Mecha → Build → Small Force → Base → Technology → Faction → War.
ทุกอย่างที่ผู้เล่นสร้างขึ้นสามารถสูญเสีย / ถูกโจมตี / ถูกขโมย / ถูกทรยศ / ถูกยึด / ถูกกู้คืน / ถูกพัฒนาต่อ ได้.

## 1. Run Identity (LOCKED)

ลำดับ: PILOT → MECHA → FRAME → PARTS → WEAPONS.
- Pilot เป็นตัวตนของ Run. Pilot ตาย → Run End.
- Mecha เปลี่ยนได้ / ทำลายได้ / ขโมยได้ / ยึดได้ / ผลิต-กู้คืนได้.
- Part พังได้ / เปลี่ยนได้ / Salvage ได้. Weapon พัง-หาย-เปลี่ยนได้.
- Design rule: การเสีย Mecha ต้องสร้าง "การเปลี่ยนแปลง" ไม่ใช่ "Game Over" (Heavy destroyed → ไม่มี replacement → Pilot ใช้ Light → playstyle เปลี่ยนทั้งรัน). นี่คือ feature ไม่ใช่ punishment อย่างเดียว.

## 2. Campaign Core Loop

PLAN → MOVE → OBSERVE → DECIDE → ACT → CONSEQUENCE → WORLD ADVANCES → REPEAT.
ไม่ใช่ Node → Battle → Reward → Next Node.

## 3. Campaign Turn

ทุกการเคลื่อนที่/กิจกรรมสำคัญทำให้โลกก้าวไปข้างหน้า: PLAYER ACTION → CAMPAIGN TURN → Faction/Patrol/Convoy/Base/Supply movement+battle+changes → WORLD STATE UPDATED.
สิ่งที่เปลี่ยนได้: faction movement, patrol/convoy location, base battle, supply, heat, threat, detection, research, events, territory.

## 4. Node (LOCKED)

Node = สถานที่/เหตุการณ์/สิ่งที่ผู้เล่นกระทำต่อได้. ตัวอย่าง: Patrol (avoid/engage/observe), Data Center (steal data), Hangar (steal mecha), Supply Depot (raid), Research Facility (steal/sabotage/capture), Military Base (attack/capture), Rescue Site, Convoy (intercept), Battlefield (salvage/observe), Prison Transport, Boss.
Node ≠ Territory. ไม่ใช่ทุก Node ต้องยึด.

## 5. Route (LOCKED)

Route = movement / frontier / contact space. States: safe / unknown / patrol / convoy / ambush / interception / blocked / faction movement.
NODE ── ROUTE (world activity) ── NODE.

## 6. Faction System (LOCKED DIRECTION)

ไม่ใช้แค่ PLAYER vs ENEMY. ใช้ PLAYER, AUTHORITY, MILITIA, SCAVENGERS, MERCENARIES, SPECIAL/UNKNOWN (จำนวนจริงยังไม่ล็อก). Relations: HOSTILE / NEUTRAL / COOPERATIVE / ALLY, เปลี่ยนได้.

## 7. Multi-Sided War

Combat/world events รองรับมากกว่า 2 forces (PLAYER vs AUTHORITY; AUTHORITY vs MILITIA; AUTHORITY vs SCAVENGERS; PLAYER+MILITIA vs AUTHORITY; 3-way; player อาจไม่เข้าร่วม).

## 8. Faction Movement

Faction ไม่รอผู้เล่น: ย้ายกำลัง, โจมตี base, ส่ง convoy, ยึด node, ถอนกำลัง, ช่วยพันธมิตร, โจมตี faction อื่น, เปลี่ยนเป้าหมาย.

## 9. Player Faction Starting State (PROPOSED — ยังต้องล็อก)

A — Lone Pilot (pilot+mecha+small supply, ไม่มี base/force → survivors → camp → forward base → small force → faction). B — Small Resistance (pilot+mecha+small force+small base+low supply). Recommendation: A (ทำให้การสร้างฝ่ายของเราเป็นส่วนหนึ่งของ run) แต่ต้อง audit กับ opening/progression ที่มีอยู่ก่อนล็อก.

## 10. Supply (LOCKED DIRECTION)

Supply เป็น campaign resource สำหรับ mecha recovery, force readiness, base operation, reinforcement, logistics, campaign operations. เบื้องต้น: SUPPLY / MATERIALS / DATA / SALVAGE (ไม่บวมเป็น 15 types).

## 11. Supply Overtime (PROPOSED → ควรล็อก)

ฐานผลิต supply/turn (เช่น 42/100, +4/turn) จาก base production, supply depot, convoy, captured facilities, faction support, logistics, salvage processing. Supply 0 ≠ Game Over → Supply Crisis (replacement/reinforcement ลด, repair จำกัด, บาง ops ทำไม่ได้, base defense อ่อน) แต่ Split ออกไปหา supplyเพิ่มได้.

## 12. Base — Capability Hub (ไม่ใช่ management simulator)

Core: Supply/Logistics, Arsenal, Factory/Mecha Recovery, Intelligence, Research, Force Capacity. ไม่ควรมีอาคาร 30 ชนิด.

## 13. Base Upgrade — ปลด Capability มากกว่า +5% Damage

Arsenal (weapon pools/advanced/experimental), Factory (archetypes/replacement/production), Logistics (capacity/income/reinforcement/forward ops), Intelligence (unknown → patrol → convoy → faction movement → upcoming ops), Research (advanced tech), Force (capacity).

## 14. Base Attack (OWNED → UNDER ATTACK → CRITICAL → CAPTURED)

ไม่ใช่ attack แล้วหายทันที. ผู้เล่นกลับไปช่วยได้: base attacked → player 2 nodes away → travel → battle continues → INTERVENTION playable combat.

## 15. Auto Battle (LOCKED DIRECTION)

Force battle ข้ามหลาย turns (70→55→40 vs 90→70→48), รองรับ 3+ factions, ไม่ต้องจบใน turn เดียว.

## 16. Intervention

CAMPAIGN BATTLE → PLAYER ARRIVES → INTERVENTION? → PLAYABLE COMBAT. ถอนตัวแล้ว battle กลับเป็น world battle ต่อ (ไม่ reset).

## 17. Heat (Heat ≠ Territory)

Heat = enemy awareness/pursuit pressure. ขึ้นจากทำลาย patrol, ขโมย prototype, บุกฐาน, ภารกิจสำคัญ, ถูกพบ, ฆ่า commander. Heat สูง → patrol/detection/pursuit เพิ่ม, route อันตรายขึ้น.

## 18. Threat (ต่างจาก Heat)

Threat = enemy willingness/capability to attack our assets. Heat high = ตามล่า pilot; Threat high = ส่งกำลังตี base.

## 19. Detection (LOCKED)

DETECTION → SUSPICION → RESPONSE → ENGAGEMENT? ไม่ใช่ enter enemy node แล้ว battle 100%. Outcomes: undetected / suspicious / investigated / patrol / pursuit / escape / stealth objective / battle.

## 20. Stolen Mecha / Disguise

Enemy mecha (เช่น Mk-II) ให้ IFF-compatible infiltration (detection ลด) แต่ไม่สมบูรณ์. ปัจจัย: IFF, restricted zone, behavior, wrong equipment, suspicious movement. Ladder: low detection → suspicion → identity compromised → interception.

## 21. Research (LOCKED DIRECTION)

Research = new way of fighting (ไม่ใช่ damage +10%). Improvement / Specialized (archetypes) / Advanced (เปลี่ยน gameplay) / Unique-Experimental (หายาก).

## 22. Unique Technology (ตัวอย่าง)

Field Modular Assembly (part damaged → detach → spare/salvage → field assembly ถึงขั้นใช้แขนศัตรู), Salvage Engineering (recover/reverse-engineer/reuse), Directed Energy Warfare (laser frame/beam platform/energy blade + trade-off heat/energy/cooling/capacitor), Autonomous Warfare (recon/attack/shield/repair/decoy drones — ไม่เป็น RTS micro), Distributed Control (ทำงานต่อแม้ subsystem เสีย), Experimental Frame (mechanics เฉพาะ).

## 23. Technology Discovery

ไม่เปิดหมดจาก tree. แหล่ง: research facility+data, elite/prototype salvage reverse-engineering, faction relationship sharing.

## 24. Technology Can Be Lost

Research ถูกขโมย/ทำลาย/scientist ถูกจับ/facility โดนตี/data หาย ได้ — ผูกกับ living world.

## 25. Technology Proliferation

Tech ผู้เล่นแพร่สู่โลกได้ (player develops field assembly → enemy steals data → enemy fields it).

## 26. Salvage

Battlefield ไม่หายหลัง combat → กลายเป็น Battlefield Node (wrecks/parts/weapons/data/survivors/prototype) กลับมาเก็บทีหลังได้.

## 27. Convoy

ไม่ได้ขนแค่ supply: supply/mecha/parts/prisoners/research data/scientists/weapons/prototype/commander — เห็น convoy แล้วไม่รู้ทันทีว่าคุ้มหรือไม่.

## 28. Personnel

States: recruit / injure / capture / rescue / defect / die / leave / return.

## 29-30. Defection / Betrayal (PROPOSED → HIGH PRIORITY, ห้าม RNG ล้วน)

Levels: individual / commander / unit / faction / faction split. Drivers: trust/loyalty/payment/fear/ideology/faction pressure/player actions. Warnings: dissatisfaction → suspicious activity → ultimatum → defection (ผู้เล่นต้องรู้สึกว่า "ฉันปล่อยให้เกิด" ไม่ใช่ "เกมสุ่มแกล้ง").

## 31. Capture / Prisoner

Pilot/commander/scientist ถูกจับ → Prison Transport / Prison Facility nodes. Spieler: rescue / intercept / exchange / ignore / negotiate.

## 32. Faction Request

Faction ขอความช่วยเหลือ (intercept convoy, defend base, rescue commander, deliver supply, steal data). Spieler: accept / ignore / betray / sell information / help rival.

## 33. Reputation

Faction จำการกระทำ (เช่น Militia +40, Authority −60) แต่ไม่เป็น spreadsheet — ใช้เปลี่ยน event/trust/prices/recruitment/tech sharing/defection/alliance.

## 34. Information Is Not Always True

Intel ≠ omniscience: เก่า/ไม่สมบูรณ์/ผิด/ถูกหลอก/decoy (เช่น convoy ที่ detect ได้อาจเป็น decoy).

## 35. Scout / Recon

ส่ง pilot / recon mecha / drone / stolen enemy mecha สำรวจก่อนเข้า node.

## 36. Black Market

Campaign/event node: ซื้อ supply/mecha/IFF/ข้อมูล, ขาย salvage, ติดต่อ mercenary, หา pilot, ซื้อ prototype — พร้อมความเสี่ยง.

## 37. Companion Design (LOCKED DIRECTION)

ลด customization: Character → Role → Personality → Ability → Mecha Archetype → Preset Loadout (deep modular เก็บไว้ที่ main pilot). Companion หาย/ถูกจับ/ทรยศ/ตาย/ย้ายฝ่ายได้.

## 38. Player Action → World Memory (CORE PRINCIPLE)

ทุก action สำคัญสร้าง state change (steal prototype → recovery team; kill commander → new commander; help militia → stronger militia; ignore base attack → enemy gains base; raid supply → weakened logistics; save scientist → research unlocked).

## 39-40. Event System (WORLD STATE + CONDITIONS + RELATIONS + HISTORY + RANDOMNESS)

Randomness ช่วย ไม่ใช่ตัดสินทุกอย่าง. Examples: betrayal, technology theft, base attack, scavenger opportunism, faction split.

## 41. Resource Model

SUPPLY (war/base/force) / MATERIALS (produce/repair/build) / DATA (research) / SALVAGE (battlefield → material/data/prototype). ห้ามเพิ่ม resource ใหม่เพื่อระบบเดียว.

## 42. Existing Architecture (ห้ามสร้างซ้ำโดยไม่ audit)

Campaign/board nodes, board→combat lifecycle, player authority, mecha identity, hangar, mecha base, modular parts, PartMeshManager, WeaponVisualFactory, AttachmentManager, weapon mount/handling, MechaWeaponLayer, frame capability, save system, progression, combat lifecycle, board-to-battle identity. Campaign V2 ต้องเชื่อมของเดิม ไม่สร้างเกมซ้อน.

## 43. Pre-Implementation Audit (ห้ามแก้ production code ใน audit phase)

ตรวจ A. campaign (node/route/movement/turn/board/save) B. faction (abstraction, hardcode, relations) C. base (ownership/persistence/attack/capture/progression) D. supply (inventory/repair/replacement/campaign resource) E. research (tech/unlock/data/save) F. personnel (pilot/companion/commander/character data) G. world/random events + mutation H. combat (multi-force/identity/replacement/salvage hooks).

## 44. Feature Status

LOCKED: pilot=run, replaceable mecha, node≠territory, route=movement/frontier, living world, campaign turns, multi-faction, detection ladder, heat≠threat, base attack/capture/recover, auto-battle+intervention, gameplay research, supply, reduced companion customization.
PROPOSED/NEEDS DECISION: lone-pilot start, supply formula, force model, base upgrade levels, resource numbers, tech tier count, faction count, personnel/prisoner/black-market depth.
NEW TO DESIGN: defection, faction split, tech theft, battlefield persistence, convoy cargo, dynamic events, info reliability, research discovery, field assembly, drones.
DO NOT BUILD YET: full economy sim, individual soldiers, 20+ resources, tower defense, huge diplomacy, staff mgmt, giant base-building, drone RTS micro, complex politics sim.

## 45. Implementation Order

C1 state foundation → C2 node/route/turn → C3 faction/relations → C4 detection/heat/threat → C5 base/ownership/force → C6 supply/logistics → C7 dynamic world movement → C8 auto-battle/intervention → C9 events → C10 research/tech → C11 salvage/prototype → C12 defection/betrayal → C13 advanced (drone/field assembly/etc.). Event/research/defection ต้องมี world state ที่เชื่อถือได้ก่อน.

## 46. Agent Hard Constraints

DO NOT IMPLEMENT THIS DESIGN FROM THE DOCUMENT ALONE. First audit existing Valkren architecture; identify existing/partial/extend/obsolete; no duplicates, no unrelated refactors, no behavior removal without evidence, no speculative features during audit. Produce evidence-based migration plan first. ทุก phase: BASELINE → AUDIT → CHANGE PLAN → IMPLEMENT → TEST → REGRESSION → COMMIT → PUSH.

## 47. Heart (7 sentences)

1. Pilot คือ Run. 2. Mecha คือสิ่งที่ pilot ใช้ ไม่ใช่ตัวตนของ run. 3. โลกเดินต่อแม้ผู้เล่นไม่อยู่. 4. Node คือสถานที่/โอกาส ไม่ใช่ช่องที่ต้องยึด. 5. Faction มีเป้าหมายและเปลี่ยนความสัมพันธ์ได้. 6. Technology เปลี่ยนวิธีทำสงคราม ไม่ใช่แค่ตัวเลข. 7. การกระทำของผู้เล่นต้องทิ้งร่องรอยในโลก.
Next: อย่าเพิ่งให้ agent coding — ให้ทำ Campaign Architecture Audit จาก spec นี้ก่อน แล้วทำตาราง EXISTING → MODIFY → NEW → REMOVE กับ code จริงก่อนเริ่ม phase ใหม่.
