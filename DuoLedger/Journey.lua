-- Journey.lua
-- Records the story of each session, on top of what Tracker.lua counts:
--   * dings:       when you level up, where, and your /played at that moment
--   * grouped:     how long you were in a group, and with whom
--   * xpFrom:      how much XP came from quests, kills and exploring
--   * gear:        each time you equip something better, and where it came from
--   * firsts:      new zones, new flight paths, new spells and mounts
--
-- Everything is written onto the current session (see Tracker.lua), so it
-- is exported and split exactly like quests and loot are.
--
-- None of this uses the combat log, which the new addon rules block. It all
-- comes from ordinary events and chat lines, and we check every value with
-- readable() in case the game hands us a "secret" one during combat.

local _, ns = ...

local Journey = {}
ns.Journey = Journey

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function readable(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function me() return ns.Tracker.CurrentCharacter() end

-- The current session, with the lists this file fills. A session that an
-- older version of the addon started doesn't have them yet, so "x = x or {}"
-- adds any that are missing. ("or" gives the right side when the left is nil.)
local function session()
  local s = ns.Tracker.CurrentSession()
  if not s then return nil end
  s.dings       = s.dings or {}
  s.grouped     = s.grouped or 0
  s.groupedWith = s.groupedWith or {}
  s.xpFrom      = s.xpFrom or { quest = 0, kill = 0, explore = 0 }
  s.kills       = s.kills or 0
  s.gear        = s.gear or {}
  s.firsts      = s.firsts or {}
  return s
end

local function zoneNow()
  return readable(GetRealZoneText()) or readable(GetZoneText())
end

local function levelNow() return readable(UnitLevel("player")) end

-- Adds an entry to the session's firsts list.
local function addFirst(kind, name)
  local s = session()
  if not s or not name then return end
  table.insert(s.firsts, {
    at = time(), kind = kind, name = name, level = levelNow(), zone = zoneNow(),
  })
end

-- Chat lines Blizzard keeps in globals, turned into patterns (Tracker.lua
-- explains how). "and" stops at a missing global instead of erroring.
local P = ns.Tracker.Pattern
local KILL_XP      = COMBATLOG_XPGAIN_FIRSTPERSON and P(COMBATLOG_XPGAIN_FIRSTPERSON, true)
local EXPLORE_XP   = ERR_ZONE_EXPLORED_XP and P(ERR_ZONE_EXPLORED_XP, true)
local LOOT_MULTI   = LOOT_ITEM_SELF_MULTIPLE and P(LOOT_ITEM_SELF_MULTIPLE)
local LOOT_SINGLE  = LOOT_ITEM_SELF and P(LOOT_ITEM_SELF)
local PUSH_MULTI   = LOOT_ITEM_PUSHED_SELF_MULTIPLE and P(LOOT_ITEM_PUSHED_SELF_MULTIPLE)
local PUSH_SINGLE  = LOOT_ITEM_PUSHED_SELF and P(LOOT_ITEM_PUSHED_SELF)
local MADE_MULTI   = LOOT_ITEM_CREATED_SELF_MULTIPLE and P(LOOT_ITEM_CREATED_SELF_MULTIPLE)
local MADE_SINGLE  = LOOT_ITEM_CREATED_SELF and P(LOOT_ITEM_CREATED_SELF)

-- Tries each pattern in turn and returns the first capture that matches.
local function firstMatch(msg, ...)
  for i = 1, select("#", ...) do
    local pattern = select(i, ...)
    local hit = pattern and msg:match(pattern)
    if hit then return hit end
  end
end

---------------------------------------------------------------------------
-- 1. Level-up moments
---------------------------------------------------------------------------
-- /played comes from the server: we ask with RequestTimePlayed() and the
-- answer arrives as the TIME_PLAYED_MSG event. The chat window prints it
-- too ("Total time played: ..."), so you'll see that line at each ding.
-- We leave it there on purpose: hiding it means replacing Blizzard's chat
-- code, which can break things under the new addon rules.

local pendingDing     -- the ding waiting for its /played answer
local playedSync      -- the last /played answer in this login: {at, level, levelTime}

local function onLevelUp(newLevel)
  local s, c = session(), me()
  if not s or not c then return end
  newLevel = readable(newLevel) or levelNow()
  local entry = { at = time(), level = newLevel, zone = zoneNow() }
  -- If /played answered earlier in this login (you typed it, or another
  -- ding asked), we know how long this level took without asking again.
  if playedSync and playedSync.level == newLevel - 1 and playedSync.levelTime then
    entry.levelTime = playedSync.levelTime + (time() - playedSync.at)
  end
  table.insert(s.dings, entry)
  pendingDing = entry
  -- Ask a moment later, so the server has finished the level change.
  C_Timer.After(2, function()
    if RequestTimePlayed then RequestTimePlayed() end
  end)
end

local function onTimePlayed(total, thisLevel)
  total, thisLevel = readable(total), readable(thisLevel)
  local c = me()
  if not c or not total then return end
  c.played = total
  playedSync = { at = time(), level = levelNow(), levelTime = thisLevel }
  local d = pendingDing
  if d then
    d.played = total
    -- Time at the level we just left = played now minus played at the
    -- last ding, when that ding was the level before.
    if not d.levelTime and c.lastDing and c.lastDing.level == d.level - 1 then
      d.levelTime = total - c.lastDing.played
    end
    c.lastDing = { level = d.level, played = total }
    pendingDing = nil
  end
end

---------------------------------------------------------------------------
-- 2. Time grouped
---------------------------------------------------------------------------
-- We remember who is in the group and since when. Each time the group
-- changes (and whenever Tracker takes a snapshot), the time since the last
-- check is added to the session: to "grouped", and to each member's name.

local roster   = {}   -- names in the group right now
local rosterAt        -- when we last added time up

local function readRoster()
  local names = {}
  if not IsInGroup() then return names end
  -- party1 to party4 are the other people in your party. In a raid these
  -- are the people in your own raid group.
  for i = 1, (GetNumSubgroupMembers() or 0) do
    local name = readable(UnitName("party" .. i))
    if name and name ~= UNKNOWNOBJECT then table.insert(names, name) end
  end
  return names
end

function Journey.Flush()
  local now = time()
  local s = session()
  if s and rosterAt and #roster > 0 then
    local secs = now - rosterAt
    -- The guard skips odd jumps, like a computer waking from sleep.
    if secs > 0 and secs < 6 * 3600 then
      s.grouped = s.grouped + secs
      for _, name in ipairs(roster) do
        s.groupedWith[name] = (s.groupedWith[name] or 0) + secs
      end
    end
  end
  rosterAt = now
end

local function onRosterChanged()
  Journey.Flush()          -- time so far goes to the old group
  roster = readRoster()
end

---------------------------------------------------------------------------
-- 3. Where XP comes from
---------------------------------------------------------------------------
-- Quests: QUEST_TURNED_IN tells us the XP reward directly.
-- Kills: the chat line "Hogger dies, you gain 120 experience." The bonus
--   in brackets, like "(+120 exp Rested bonus)", is added on.
-- Exploring: the line "Discovered Goldshire: 35 experience gained".
-- Anything else (rested bonus we couldn't read, profession XP...) is what's
-- left of the session's total, worked out at export.

local lastExplore = { msg = nil, at = 0 }

local function onXPChat(msg)
  msg = readable(msg)
  local s = session()
  if not msg or not s then return end
  local mob, base = nil, nil
  if KILL_XP then mob, base = msg:match(KILL_XP) end
  if base then
    local xp = tonumber(base) or 0
    local rest = msg:sub(#mob + 1)
    -- gmatch walks every "(+120" or "(-30" in the rest of the line.
    for sign, n in rest:gmatch("%(([%+%-])(%d+)") do
      xp = xp + (sign == "-" and -1 or 1) * tonumber(n)
    end
    s.xpFrom.kill = s.xpFrom.kill + math.max(0, xp)
    s.kills = s.kills + 1
    return
  end
  local _, explored = nil, nil
  if EXPLORE_XP then _, explored = msg:match(EXPLORE_XP) end
  -- The same line can arrive twice (as XP and as a system message), so
  -- ignore a repeat within a few seconds.
  if explored and not (lastExplore.msg == msg and time() - lastExplore.at < 5) then
    lastExplore.msg, lastExplore.at = msg, time()
    s.xpFrom.explore = s.xpFrom.explore + (tonumber(explored) or 0)
  end
end

local function onQuestXP(xpReward)
  local s = session()
  xpReward = readable(xpReward)
  if s and type(xpReward) == "number" and xpReward > 0 then
    s.xpFrom.quest = s.xpFrom.quest + xpReward
  end
end

---------------------------------------------------------------------------
-- 4. Gear upgrades
---------------------------------------------------------------------------
-- When an item reaches your bags we note where it came from, in
-- c.got[itemID]. When you equip something with a higher item level than
-- what was in that slot, we log the upgrade with that source.

local SLOTS = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist",
  [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Ring",
  [12] = "Ring", [13] = "Trinket", [14] = "Trinket", [15] = "Back",
  [16] = "Main hand", [17] = "Off hand", [18] = "Ranged",
}   -- 4 (shirt) and 19 (tabard) are left out: they're looks, not upgrades

local windows = {}       -- which windows are open: merchant, mail, trade
local questAt = 0        -- when the last quest was turned in
local questWindow = false  -- true while a quest's reward window is open
local lastQuestName

local function itemLevel(link)
  if not link then return nil end
  local get = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
  if not get then return nil end
  local ok, ilvl = pcall(get, link)   -- pcall: an odd link can't break us
  return ok and readable(ilvl) or nil
end

local function isEquippable(id)
  local check = (C_Item and C_Item.IsEquippableItem) or IsEquippableItem
  if not check then return true end
  local ok, yes = pcall(check, id)
  return not ok or yes
end

local function readSlot(slot)
  local link = readable(GetInventoryItemLink("player", slot))
  if not link then return nil end
  return {
    id   = tonumber(link:match("|Hitem:(%d+)")),
    name = link:match("|h%[(.-)%]|h"),
    link = link,
  }
end

-- Remembers where an item came from, for when it gets equipped.
local function noteSource(link, from, where)
  local c = me()
  local id = link and tonumber(link:match("|Hitem:(%d+)"))
  if not c or not id or not isEquippable(id) then return end
  c.got = c.got or {}
  c.got[id] = { from = from, where = where, at = time() }
end

local function onLootChat(msg)
  msg = readable(msg)
  if not msg then return end
  local link = firstMatch(msg, LOOT_MULTI, LOOT_SINGLE)
  if link then
    local _, instanceType = IsInInstance()
    if instanceType == "party" then
      noteSource(link, "dungeon", (GetInstanceInfo()))
    else
      noteSource(link, "drop", zoneNow())
    end
    return
  end
  link = firstMatch(msg, MADE_MULTI, MADE_SINGLE)
  if link then noteSource(link, "crafted"); return end
  -- "You receive item:" covers quest rewards, things you buy and more.
  link = firstMatch(msg, PUSH_MULTI, PUSH_SINGLE)
  if link then
    if questWindow or time() - questAt <= 5 then
      noteSource(link, "quest", lastQuestName)
    elseif windows.merchant then
      noteSource(link, "vendor")
    elseif windows.mail then
      noteSource(link, "mail")
    elseif windows.trade then
      noteSource(link, "trade")
    else
      noteSource(link, "other")
    end
  end
end

local gearReady = false   -- false until we've seen what you're wearing

-- Called a moment after a slot changes. Compares old and new item levels.
local function checkSlot(slot)
  local c, s = me(), session()
  if not c or not s then return end
  c.worn = c.worn or {}
  local old, new = c.worn[slot], readSlot(slot)
  c.worn[slot] = new
  if not new or (old and old.id == new.id) then return end
  local newL, oldL = itemLevel(new.link), old and itemLevel(old.link)
  -- An upgrade: the slot was empty, or the new item level is higher.
  -- If either level is unknown we can't tell, so we leave it out.
  local better = (old == nil) or (newL and oldL and newL > oldL)
  if not better then return end
  local src = (c.got and c.got[new.id]) or {}
  table.insert(s.gear, {
    at = time(), slot = SLOTS[slot], id = new.id, name = new.name,
    ilvl = newL, was = old and old.name, wasIlvl = oldL,
    from = src.from or "unknown", where = src.where, level = levelNow(),
  })
  if c.got then c.got[new.id] = nil end
end

local function scanGear()
  local c = me()
  if not c then return end
  c.worn = {}
  for slot in pairs(SLOTS) do c.worn[slot] = readSlot(slot) end
  -- Forget sources older than 30 days, so the list stays small.
  -- (86400 seconds is one day.)
  for id, g in pairs(c.got or {}) do
    if time() - (g.at or 0) > 30 * 86400 then c.got[id] = nil end
  end
  gearReady = true
end

---------------------------------------------------------------------------
-- 5. Zones and firsts
---------------------------------------------------------------------------

local function checkZone()
  local c = me()
  local zone = zoneNow()
  if not c or not zone or zone == "" then return end
  -- Dungeons are logged by Tracker.lua already.
  if IsInInstance() then return end
  c.zonesSeen = c.zonesSeen or {}
  if not c.zonesSeen[zone] then
    c.zonesSeen[zone] = true
    addFirst("zone", zone)
  end
end

-- Flight paths: the game has no "learned a flight path" event, but it
-- shows "New flight path discovered!", and the flight map opens right
-- after. So we compare the flight map's known places with our list.
local newTaxiAt = 0

local function knownTaxiNodes()
  local known, current = {}, nil
  if NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
    for i = 1, NumTaxiNodes() do
      local kind, name = TaxiNodeGetType(i), readable(TaxiNodeName(i))
      if name and (kind == "CURRENT" or kind == "REACHABLE") then
        known[name] = true
        if kind == "CURRENT" then current = name end
      end
    end
  elseif C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID then
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, GetTaxiMapID())
    local states = Enum and Enum.FlightPathState or {}
    for _, n in ipairs(ok and nodes or {}) do
      if n.state == states.Current or n.state == states.Reachable then
        known[n.name] = true
        if n.state == states.Current then current = n.name end
      end
    end
  end
  return known, current
end

local function onTaxiMap()
  local c = me()
  if not c then return end
  local known, current = knownTaxiNodes()
  if not c.flights then
    -- First time we look: everything you know already isn't news, except
    -- the one you just discovered, if the game said so a moment ago.
    c.flights = known
    if current and time() - newTaxiAt < 30 then addFirst("flight", current) end
    return
  end
  for name in pairs(known) do
    if not c.flights[name] then
      c.flights[name] = true
      addFirst("flight", name)
    end
  end
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return readable(C_Spell.GetSpellName(id)) end
  if GetSpellInfo then return readable((GetSpellInfo(id))) end
end

local function onSpellLearned(spellID)
  spellID = readable(spellID)
  if type(spellID) ~= "number" then return end
  local c = me()
  local name = spellName(spellID)
  if not c or not name then return end
  -- A mount you learn shows up as a spell. Ask the mount journal.
  if C_MountJournal and C_MountJournal.GetMountFromSpell
     and C_MountJournal.GetMountFromSpell(spellID) then
    c.mountsSeen = c.mountsSeen or {}
    if not c.mountsSeen[name] then
      c.mountsSeen[name] = true
      addFirst("mount", name)
    end
    return
  end
  -- Passive spells (like a weapon skill) are noise; leave them out.
  local passive = (C_Spell and C_Spell.IsSpellPassive) or IsPassiveSpell
  if passive and passive(spellID) then return end
  -- "Rank 2" and so on, when the game gives it.
  local rank = C_Spell and C_Spell.GetSpellSubtext and readable(C_Spell.GetSpellSubtext(spellID))
  if rank and rank ~= "" then name = name .. " (" .. rank .. ")" end
  addFirst("spell", name)
end

local function onMountAdded(mountID)
  local c = me()
  if not c or not (C_MountJournal and C_MountJournal.GetMountInfoByID) then return end
  local name = readable((C_MountJournal.GetMountInfoByID(mountID)))
  if not name then return end
  c.mountsSeen = c.mountsSeen or {}
  if not c.mountsSeen[name] then
    c.mountsSeen[name] = true
    addFirst("mount", name)
  end
end

---------------------------------------------------------------------------
-- Login (called by Tracker.lua once the character and session exist)
---------------------------------------------------------------------------

function Journey.OnLogin(isReload)
  roster, rosterAt = readRoster(), time()
  pendingDing = nil
  scanGear()
  checkZone()
end

---------------------------------------------------------------------------
-- Event wiring
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

handlers.PLAYER_LEVEL_UP = onLevelUp
handlers.TIME_PLAYED_MSG = onTimePlayed
handlers.GROUP_ROSTER_UPDATE = onRosterChanged
handlers.CHAT_MSG_COMBAT_XP_GAIN = onXPChat
handlers.CHAT_MSG_LOOT = onLootChat
handlers.ZONE_CHANGED_NEW_AREA = checkZone
handlers.TAXIMAP_OPENED = onTaxiMap
handlers.NEW_MOUNT_ADDED = onMountAdded
-- The event for a new spell was renamed in a recent expansion. We listen
-- for both names; the one this client doesn't know is skipped below.
handlers.LEARNED_SPELL_IN_SKILL_LINE = onSpellLearned
handlers.LEARNED_SPELL_IN_TAB = onSpellLearned

handlers.CHAT_MSG_SYSTEM = function(msg)
  onXPChat(msg)       -- exploring XP can arrive as a system message
  if readable(msg) == ERR_NEWTAXIPATH then newTaxiAt = time() end
end
handlers.UI_INFO_MESSAGE = function(_, msg)
  if readable(msg) == ERR_NEWTAXIPATH then newTaxiAt = time() end
end

-- QUEST_COMPLETE: the reward window opened. QUEST_FINISHED: it closed.
-- The reward item can arrive just before or just after the turn-in, so an
-- item counts as a quest reward while the window is open or for 5 seconds
-- after the turn-in.
handlers.QUEST_COMPLETE = function()
  questWindow = true
  lastQuestName = GetTitleText and readable(GetTitleText())
end
handlers.QUEST_FINISHED = function() questWindow = false end
handlers.QUEST_TURNED_IN = function(questID, xpReward)
  questAt = time()
  local title = C_QuestLog and C_QuestLog.GetTitleForQuestID
    and readable(C_QuestLog.GetTitleForQuestID(questID))
  lastQuestName = title or lastQuestName
  onQuestXP(xpReward)
end

handlers.PLAYER_EQUIPMENT_CHANGED = function(slot)
  slot = readable(slot)
  if not gearReady or not SLOTS[slot] then return end
  -- Wait half a second so the item's details have loaded.
  C_Timer.After(0.5, function() checkSlot(slot) end)
end

for _, pair in ipairs({
  { "MERCHANT_SHOW", "MERCHANT_CLOSED", "merchant" },
  { "MAIL_SHOW", "MAIL_CLOSED", "mail" },
  { "TRADE_SHOW", "TRADE_CLOSED", "trade" },
}) do
  handlers[pair[1]] = function() windows[pair[3]] = true end
  handlers[pair[2]] = function() windows[pair[3]] = nil end
end

for event in pairs(handlers) do
  -- RegisterEvent throws an error for an event this client doesn't have.
  -- pcall catches it, so one renamed event can't stop the rest.
  pcall(frame.RegisterEvent, frame, event)
end

frame:SetScript("OnEvent", function(self, event, ...)
  handlers[event](...)
end)
