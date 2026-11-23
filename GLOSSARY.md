# Campaign Territory & Turf War

The strategic campaign layer: districts the player and factions hold, the Turf Wars fought to take them, and the manpower used to fight. Tactical mech combat is described in the tactical docs, not here.

## Map & Territory

**Territory**:
A geographic district on the strategic map. May contain zero, one, or several Nodes.
_Avoid_: Region, zone, sector

**Node**:
A discrete point on the strategic map used for travel, encounters, bases, and missions.
_Avoid_: Location, tile

**Route**:
A direct link between two Nodes used for travel. Routes do not define Territory adjacency.
_Avoid_: Path, road

**Territory Adjacency**:
A neighbour relation between two Territories. It exists independently of Routes, so a Route crossing a border does not by itself make two Territories adjacent.
_Avoid_: Border, connection

**Control**:
The state of a Territory: **Uncontrolled** (no faction holds it), **Controlled** (one faction holds it), or **Contested** (a Turf War is unresolved over it).
_Avoid_: Ownership (when referring to the control state)

**Campaign Clock**:
The single in-game day timeline. Every timed activity in the campaign, including battles, advances it.
_Avoid_: Turn, timer (for the campaign day)

## Forces & Manpower

**Mecha**:
The player's customized mech, piloted in direct tactical combat. Counts as one unit in a Force Count while piloted.
_Avoid_: Robot, frame

**Grunt**:
A standard mass-production soldier. Counts as one unit in a Force Count. A Grunt lost in battle is permanently gone.
_Avoid_: Infantry, trooper

**Manpower Pool**:
The player's reserve of Grunts that are not currently committed to a battle.
_Avoid_: Roster, army

**Force Count**:
The number of units one side has in a battle at a given moment: Grunts plus a piloted Mecha. This is the number that decides victory and defeat.
_Avoid_: Strength, HP

**In Transit**:
Units that have been dispatched toward a battle but have not yet arrived. They are not part of the Force Count until they arrive.
_Avoid_: Incoming (ambiguous with arrival)

## Turf War

**Turf War**:
A battle a player starts to take a Controlled territory held by an enemy faction, where the territory is adjacent to one the player controls.
_Avoid_: Raid, siege, assault

**Dispatch**:
The choice made when committing to a Turf War: either deploy the **Mecha** into tactical combat, or deploy as a **Grunt**.
_Avoid_: Deploy (alone, ambiguous), mission

**Round**:
One **Battle Segment** of a Turf War. Force Counts carry over from one round to the next.
_Avoid_: Turn, phase

**Battle Segment**:
A fixed amount of in-battle time. When it elapses, the Campaign Clock advances by that amount, other campaign events happen, and the Turf War continues unless it has been decided.
_Avoid_: Timer (alone, ambiguous with the Campaign Clock)

**Reinforcement**:
Units that arrive at an ongoing Turf War's Node during a Battle Segment boundary, either from an NPC squad or from the player's Manpower Pool. An NPC reinforcement joins the side of the faction it belongs to.
_Avoid_: Backup, support

**Defender**:
The enemy faction that holds the territory under attack in a Turf War.
_Avoid_: Garrison (for the faction)

**Victory**:
A Turf War is won when the defender's Force Count reaches zero in a round. The territory then becomes Controlled by the player.
_Avoid_: Win (alone)

**Defeat**:
A Turf War is lost when the player's Force Count reaches zero in a round. The territory stays with the defender.
_Avoid_: Loss (alone)

**Withdrawal**:
The player leaves the Mecha mid-battle and continues as a Grunt until the Turf War is decided. A Withdrawal adds a small amount of **Strategic Heat**. It does not trigger an immediate counter-attack.
_Avoid_: Retreat (ambiguous with leaving the battle entirely)

**Strategic Heat**:
A campaign-level measure of how much attention the player has drawn. Defined in the C4 heat and detection design.
_Avoid_: Alert, notoriety
