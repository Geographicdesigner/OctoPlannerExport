# Octo Planner Export

Saves your gear, bags, bank, talents and spellbook for the [Octo Druid Gear Planner](https://claude.ai/artifact/UH8XPsJL2wonzFTwNx4ryd), and records your fights. Unzip it into Interface/AddOns, then upload SavedVariables/OctoPlannerExport.lua after a /reload.

**[Download OctoPlannerExport.zip](https://github.com/Geographicdesigner/OctoPlannerExport/raw/main/OctoPlannerExport.zip)**

### Needed for fight logs
- **SuperWoW** (client mod): where everyone stands, who cast what on whom. Get it only from the official page: [github.com/balakethelock/SuperWoW](https://github.com/balakethelock/SuperWoW) ([releases](https://github.com/balakethelock/SuperWoW/releases)). Without it the addon still records, but the map has no positions.
- **UnitXP Service Pack 3** (optional, for the cat and bear macros): distance and behind checks.

| Command | What it does |
|---|---|
| `/ope dummy [name]` | Starts recording your damage. The clock starts at your first hit. |
| `/ope dummy` | Stops and saves the run: DPS, damage per ability, crits, misses, bleed ticks, what used each Clearcasting, energy and Reshifts. Shown on the Rotation tab. |
| `/ope dummy clear` | Deletes your saved runs. |
| `/ope log [name]` | Records everything until you type `/ope log stop` (a plain `/ope log` while one is on only tells you it is still recording, and `/ope log <new name>` saves it and starts a new one): all combat text, who cast what on whom, your energy and rage, your group, the time between pulls, where everyone stands (needs SuperWoW), and everyone’s health and mana, rage or energy every second in combat. With SuperWoW the log is also written in parts to the game's `imports` folder (`octo_<start>_001.txt`, …), so it never fills up; upload those files together with OctoPlannerExport.lua. It also turns on the game's own combat log (`Logs/WoWCombatLog.txt`) for other log sites, and records where bosses stand and whom they face. A /reload or logging out keeps it going; when you log back in a message in the middle of the screen says it is still recording. Shown on the Fights page. |
| `/ope cc` | Shows in chat which ability used each Clearcasting. Type it again to turn it off. |
| `/ope save` | Saves gear, bags and talents right away. |
| `/ope scan` · `/ope stop` | Reads Octo’s item tooltips for the Atlas, and pauses it. |
