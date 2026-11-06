# Duo Ledger addon (v0.3)

Records your leveling sessions in game and gives you a block of text to paste into the Forever Duo Ledger's Import. Written 6 Oct 2026.

## Install

1. Copy the whole `DuoLedger` folder into `World of Warcraft/_forever_/Interface/AddOns/` (the `_forever_` name may differ on your PC).
2. Start the game, or restart it if it was already running. New addons need a full restart, not just `/reload`.
3. On the character select screen, click **AddOns** and make sure Duo Ledger is ticked. If it says "out of date", either tick "Load out of date AddOns" or fix the Interface number (see "First run checks").

## Using it

| You want to | Keyboard / mouse | Gamepad |
|---|---|---|
| Open or close the window | `/ledger`, a bound key, or the AddOns button by the minimap | Bind **Toggle Duo Ledger** to a button in Options > Keybindings > AddOns |
| See the export text | **Export** button, or `/ledger export` | **A** |
| Switch Summary / Ledger / Export | Buttons at the bottom | D-pad left or right |
| Close | **Close**, the X, or Escape | **B** |
| Wipe sessions you've already imported | `/ledger clear` (asks first) | |

## Syncing with the Ledger

The game and the Ledger each write their own file, so they never overwrite each other:

| File | Written by | Read by |
|---|---|---|
| `WTF\Account\<ACCOUNT>\SavedVariables\DuoLedger.lua` | the game, at /reload or logout | the Ledger's **Sync from game** |
| `Interface\AddOns\DuoLedger\LedgerData.lua` | the Ledger's **Send to game** | the game, at login or /reload |

**Game to Ledger.** Type `/reload` (or log out), then press **Sync from game** in the Ledger's session log and pick `DuoLedger.lua`. Check the summary and press **Import**. Syncing twice is safe, and a session that grew since the last sync is updated rather than duplicated. Copying the in-game Export text still works too.

**Ledger to game.** Press **Send to game** and save `LedgerData.lua` into the addon folder, replacing the old one. Then `/reload`. The **Ledger** view shows your partner, the mail queued for you to send, and what's left on your wishlist, and item tooltips show "Ledger wishlist: name" for anything someone still needs. You can do this mid-session, from a second screen, or after your cousin changes something, because nothing in the game touches that file.

**Deleted or remade characters.** The addon remembers every character you log in on, and saves each one's game id (`UnitGUID`), which never changes and is new for every new character, even one that reuses an old name. When you archive or delete a character in the Ledger, the next **Send to game** lists it in `LedgerData.lua`, and at that `/reload` the addon forgets it and its saved sessions, then says so in chat. A character archived before it had an id is matched by name, but only if it has no id yet, so a remake with the same name is never forgotten by mistake.

**Why it isn't one click.** The Ledger runs inside claude.ai, and browsers don't let a page embedded that way open folders on your PC. I tested this. So each sync picks the file, and each send saves one. If your browser saves straight to Downloads, turn on "Ask where to save each file" so you can save into the addon folder.

## What gets recorded

A **session** runs from login to logout. A `/reload` doesn't split it. Switching characters does, and so does opening the Export view (see "Exporting is safe to repeat" below).

| Field | What it holds |
|---|---|
| `start`, `end` | When the session started and ended, as ISO 8601 text in UTC (`2026-10-06T19:00:00Z`) |
| `levelFrom`, `levelTo` | Your level at the start, and at the end |
| `xpGained` | Every XP change added up, counting the rest of the bar when you ding |
| `deaths` | How many times you died |
| `deathLog` | Each death as `{at, zone, killer}`. The killer comes from the game's Death Recap, like `Scarlet Zealot (Holy Strike)` or `Falling`. If the recap has nothing readable, the death is still logged without a killer |
| `moneyGained` | Copper earned from loot and quests (100 copper is 1 silver). Money that comes in while a vendor, mailbox, trade or auction window is open isn't counted |
| `quests` | Each quest turned in, as `{id, name}`. The Ledger ticks off dungeon quests by name |
| `items` | Each green-or-better item you looted, as `{id, name}`. The Ledger marks wishlist items obtained by id |
| `dungeons` | The name of each 5-player dungeon you zoned into. Running back in as a ghost or reloading inside doesn't count |
| `mail` | Each item you mailed, as `{to, item, qty}`. The Ledger marks matching Mailbox entries sent |
| `dings` | Each level-up as `{at, level, zone, played, levelTime}`. `played` is your total /played in seconds at that moment, and `levelTime` is how long the level you just finished took, in /played seconds |
| `grouped` | Seconds you spent in a group this session |
| `groupedWith` | Seconds with each person, by name, like `{"Mendra": 5400}`. The Ledger works out which of them are your partner's characters |
| `xpFrom` | XP split into `quest`, `kill`, `explore` and `other` (whatever couldn't be told apart, like a rested bonus the game didn't spell out) |
| `kills` | How many kills gave you XP. Grey mobs give none, so they aren't counted |
| `gear` | Each upgrade you equipped, as `{at, slot, id, name, ilvl, was, wasIlvl, from, where, level}`. `from` is `quest`, `drop`, `dungeon`, `crafted`, `vendor`, `mail`, `trade`, `other` or `unknown`, and `where` names the quest, zone or dungeon |
| `firsts` | Firsts as `{at, kind, name, level, zone}`, where `kind` is `zone`, `flight`, `spell` or `mount` |

A **character** is a snapshot of each character you've logged into on this account: name, class and race (as the game's English codes, like `PALADIN` and `Scourge`), level, XP, XP to level (`xpMax`), rested XP (`restXP`), whether you're resting, zone, hearthstone location, and `logout`. For the character you're on, `logout` is "now", because the numbers are as of now. It also carries your profession skills (`professions`) and how many of each item you have in bags and bank together (`inventory`), which fill the Ledger's profession planner. The game only shows addons your bank while it's open, so bank counts update each time you visit a banker. The Summary says when that last happened.

**Names must match.** The Ledger finds characters by name, so name them on its Pairs tab exactly as in game.

**Exporting is safe to repeat.** The Ledger imports each session once, recognising it by character and start time. Anything added to a session after you'd imported it would be ignored, so opening Export closes the current session and starts a fresh one from that moment. Nothing is lost or counted twice, and pasting the same export twice is harmless. `/ledger clear` is just tidying.

## The files, and what to read first

Start with `Tracker.lua`. It's the heart of the addon and uses every idea from the step 1 guide.

- **DuoLedger.toc**: the addon's ID card (guide section 3). Lists the files to load and names `DuoLedgerDB` as the SavedVariable.
- **Bindings.xml**: adds "Toggle Duo Ledger" to the Keybindings menu. WoW finds it on its own, so it isn't in the `.toc`.
- **Json.lua**: turns Lua tables into JSON text. A good example of plain Lua with no WoW in it.
- **Tracker.lua**: listens to events (guide section 6) and keeps the data in `DuoLedgerDB` (section 7). Look for `handlers.QUEST_TURNED_IN` to see the simplest example.
- **Inventory.lua**: counts bags and bank, and reads profession skills.
- **Journey.lua**: level-ups, time grouped, where XP comes from, gear upgrades and firsts. It has its own event frame, like Tracker.lua, and shows `pcall` for events a client might not have.
- **Export.lua**: turns the saved data into the Ledger's import format.
- **LedgerData.lua**: written by the Ledger's Send to game. The addon only reads it.
- **Ledger.lua**: looks things up in LedgerData.lua, and adds the wishlist line to item tooltips.
- **UI.lua**: the window (section 5), gamepad buttons (section 11) and the `/ledger` command (section 8).

Lua ideas you'll meet that the guide didn't cover:
- `local _, ns = ...` at the top of each file. WoW hands every file the addon's name and a private table. The files share data through that table instead of globals.
- `session["end"]`. `end` is a Lua keyword, so that field can't be written `session.end`.
- `handlers[event](...)`. A table of functions, looked up by event name. `...` passes along whatever the event sent.

## First run checks

These are the parts I couldn't test outside the game. I ran the code against a fake WoW to check the tracking and the export format, but not in the real client.

1. **Interface number.** Confirmed in game on 5 Nov 2026: Forever is `16001`, already set in `DuoLedger.toc`.
2. **Errors.** Run `/console scriptErrors 1` once so any Lua error pops up instead of failing silently.
3. **Gamepad buttons inside the window.** A, B and the D-pad use retail's frame gamepad support. If they do nothing, or stop your character moving while the window is open, tell me what happened.
4. **Loot counting.** Loot a stack and check the Summary's Items number goes up.
5. **Journey (v0.3).** None of these are tested in the real client yet:
   - **Dings.** At each ding the chat shows "Total time played". That line is the addon asking for /played, and it's expected.
   - **Grouped.** Group with your partner for a few minutes, then check the Summary's Grouped number climbs.
   - **Kills and XP sources.** Kill a mob that gives XP and check Kills goes up. This reads the "dies, you gain N experience" chat line, so if Kills stays at 0 tell me, because the new addon rules may hide that line.
   - **Exploring.** Discover a new area and check the Ledger shows exploring XP after the next sync.
   - **Gear.** Equip a quest reward that's better than what you wear and check Upgrades goes up. Upgrades compare item levels, so an item with the same level doesn't count.
   - **Flight paths.** The first time you open a flight map, the places you already know are saved quietly. After that each new one shows up as a first.
   - **Spells and mounts.** Learning a spell at a trainer, or a mount, should add a first. The event for new spells changed name in a recent expansion; the addon listens for both names.
   - **Zones.** For a character that existed before v0.3, each zone you enter once more counts as "new" one time, because the addon has no record of earlier visits.

## Checked against the Ledger

I ran the Ledger's own import code on an export from the fake WoW. It found every session, level, quest turn-in, wishlist item, hearth, rested value and mailed item.

Two things still to check in the real game:
- **Hearth names.** The Ledger only accepts hearths from its own list. The game may call Stormwind's inn "Stormwind City", which `Export.lua` already translates. If the Ledger doesn't pick up your hearth, tell me what the Summary shows.
- **Dungeon names.** These come from the game and should match the Ledger's list, but a wing like Scarlet Monastery might be named differently.

The Ledger also accepts a top-level `addons` list for Launch prep, which this version doesn't send yet. Kill counts come from the XP chat line rather than the combat log, which the new addon rules block, so kills that give no XP aren't counted.
