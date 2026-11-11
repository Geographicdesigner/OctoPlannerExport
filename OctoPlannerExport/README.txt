Octo Planner Export
===================
Saves everything the Octo Druid Gear Planner needs:
  1. Your talents, worn gear, bags and professions (automatically, on login, logout and gear changes).
  2. Your bank (open your bank once).
  3. Octo's own item tooltips and icons, when you run /ope scan.
With this addon you don't need Bagshui or another bag addon for the planner.

Install
  Copy the OctoPlannerExport folder into  World of Warcraft/Interface/AddOns/
  Make sure it is enabled on the character select screen (AddOns button).

Talents and gear
  Nothing to do. Log in on each character once, open your bank once, then log out.

Item scan (once per patch)
  /ope scan        start, or continue where it stopped
  /ope stop        pause
  /ope speed N     items per second, 1 to 10 (default 4). Lower it if you ever get disconnected.
  /ope rescan      throw away the saved items and start over
  /ope             show progress and help
  About 10,500 items: roughly 45 minutes at the default speed. Stand somewhere quiet (a city, an inn).
  Progress is saved, so you can log out and continue later; it resumes when you log back in.

Target dummy runs
  /ope dummy [name]   start recording, for example /ope dummy opener. The clock starts at your first hit.
  /ope dummy          type it again to stop. The run is saved with its damage, DPS and a breakdown per ability.
  A run still recording when you /reload or log out is saved automatically.
  /ope dummy clear    delete this character's saved runs
  /ope cc             show in chat which ability uses each Clearcasting (type again to turn off)
  Each run also measures how much each ability grows with attack power. Do runs at different
  attack power (no buffs, raid buffs, buffs plus consumables) to fill the planner's scaling table.
  /reload after your runs, then upload the file. The runs show on the planner's Rotation tab.

Fight log (raids and dungeons)
  /ope log [name]     start, for example /ope log mc. From then on everything is saved, in and
                      out of combat: all combat text (you, your group, enemies), every spell cast
                      near you with who cast it and on whom (needs SuperWoW), your energy, rage,
                      mana and health, your group and any swaps, your target, zone and resets.
                      Each fight also keeps a summary: hit table per ability, damage per target,
                      damage you took, deaths, consumables and buff uptime.
  /ope log            type it again to stop.
  /ope log clear      delete saved logs.
  A /reload or disconnect does not stop the log. Upload the file afterwards.

Upload
  After logging out, upload  WTF/Account/<ACCOUNT>/SavedVariables/OctoPlannerExport.lua
  to the planner, or a zip of your whole WTF folder (it is picked up next to your bag addon file).

Updating from version 1
  Replace the folder and /reload (or relog). A running scan keeps its progress.
  Items scanned with version 1 have no icon yet; /ope scan revisits them to add icons.
