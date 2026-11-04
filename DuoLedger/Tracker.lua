-- Tracker.lua
-- Listens to game events and records two things in DuoLedgerDB:
--   * a snapshot of each character (level, XP, zone, rested...)
--   * play sessions (from login to logout, with XP, quests, deaths...)
--
-- DuoLedgerDB is our SavedVariable (named in the .toc). WoW loads it at
-- login or /reload and writes it to disk at logout or /reload. It is
-- account-wide, so every character on the account ends up in one file.

local _, ns = ...

local Tracker = {}
ns.Tracker = Tracker

local db        -- shortcut to DuoLedgerDB once it's loaded
local charKey   -- "Name-Realm", our key for the current character
local me        -- this character's record inside db.characters

-- XP we saw last time, so we can work out how much was gained.
-- Plain locals: they don't need saving, we re-read them after a reload.
local lastLevel, lastXP, lastXPMax

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

-- Since Midnight, some API answers can be "secret values" (mostly combat
-- info). Addons may display them but not read or compare them; trying
-- throws an error. Our data isn't combat data, but we check anyway.
-- issecretvalue only exists on clients with the restrictions, hence the
-- "issecretvalue and" guard.
local function readable(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

-- Sets t[key] only when the game gave us a usable value, so a missing or
-- secret answer never wipes out a good value we stored earlier.
local function setIf(t, key, v)
  v = readable(v)
  if v ~= nil then t[key] = v end
end

local function newSession()
  return {
    character = me.name,
    start     = time(),          -- seconds since 1970 (Unix time)
    -- "end" is a Lua keyword, so it must be written with brackets
    -- and quotes: session["end"]. session.end would be a syntax error.
    ["end"]   = time(),
    levelFrom = UnitLevel("player"),
    levelTo   = UnitLevel("player"),
    xpGained  = 0,
    deaths    = 0,
    quests    = {},   -- list of {id = 123, name = "Quest title"}
    items     = {},   -- list of {id = 456, name = "Item name"}
    dungeons  = {},   -- list of dungeon names
    mail      = {},   -- list of {to = "Name", item = "Item name", qty = 5}
  }
end

-- The session currently being recorded, or nil before login finishes.
local function current()
  return me and me.current
end

---------------------------------------------------------------------------
-- Character snapshot
---------------------------------------------------------------------------

function Tracker.Snapshot()
  if not me then return end
  setIf(me, "name",    (UnitName("player")))
  -- UnitClass returns two values: "Paladin" (in your language) and
  -- "PALADIN" (the same in every language). The Ledger wants the second.
  -- select(2, ...) picks the second value.
  setIf(me, "class",   (select(2, UnitClass("player"))))   -- e.g. "PALADIN"
  setIf(me, "race",    (select(2, UnitRace("player"))))    -- e.g. "Scourge"
  setIf(me, "level",   UnitLevel("player"))
  setIf(me, "xp",      UnitXP("player"))
  setIf(me, "xpMax",   UnitXPMax("player"))
  -- GetXPExhaustion returns nil when you have no rested XP.
  setIf(me, "restXP",  GetXPExhaustion() or 0)
  setIf(me, "resting", IsResting() and true or false)
  setIf(me, "zone",    GetRealZoneText() or GetZoneText())
  setIf(me, "hearth",  GetBindLocation())

  local s = current()
  if s then
    s["end"] = time()
    setIf(s, "levelTo", UnitLevel("player"))
  end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

---------------------------------------------------------------------------
-- XP gained
---------------------------------------------------------------------------

local function updateXP()
  local level = readable(UnitLevel("player"))
  local xp    = readable(UnitXP("player"))
  local xpMax = readable(UnitXPMax("player"))
  if not (level and xp and xpMax) then return end

  local s = current()
  if s and lastLevel then
    if level == lastLevel and xp > lastXP then
      s.xpGained = s.xpGained + (xp - lastXP)
    elseif level > lastLevel then
      -- Dinged: the rest of the old bar, plus what's on the new one.
      s.xpGained = s.xpGained + (lastXPMax - lastXP) + xp
    end
  end
  lastLevel, lastXP, lastXPMax = level, xp, xpMax
end

---------------------------------------------------------------------------
-- Loot: count items from "You receive loot: [Item]x3." chat lines
---------------------------------------------------------------------------

-- Blizzard keeps the loot message in a global like
-- LOOT_ITEM_SELF = "You receive loot: %s." (translated per language).
-- We turn that format into a Lua pattern so it works in any language.
local function toPattern(fmt)
  fmt = fmt:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
  fmt = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")   -- escape magic chars
  fmt = fmt:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
  return "^" .. fmt .. "$"
end

local LOOT_MULTI  = LOOT_ITEM_SELF_MULTIPLE and toPattern(LOOT_ITEM_SELF_MULTIPLE)
local LOOT_SINGLE = LOOT_ITEM_SELF and toPattern(LOOT_ITEM_SELF)

-- Only green (uncommon) or better items go in the list, so the Ledger
-- isn't flooded with grey junk and linen cloth. 2 = uncommon.
local MIN_QUALITY = 2

local function recordLoot(msg)
  local s = current()
  if not s or not readable(msg) then return end
  -- Is this our own loot? (A party member's loot uses a different line.)
  -- Check the "x3" version first: the single pattern would also match it.
  local link = LOOT_MULTI and msg:match(LOOT_MULTI)
  if not link then link = LOOT_SINGLE and msg:match(LOOT_SINGLE) end
  if not link then return end

  -- An item link looks like |cff1eff00|Hitem:2589:...|h[Linen Cloth]|h|r
  -- The pattern captures the number after "item:" and the text in [ ].
  local id   = tonumber(link:match("|Hitem:(%d+)"))
  local name = link:match("|h%[(.-)%]|h")
  if not id or not name then return end

  local quality = C_Item and C_Item.GetItemQualityByID
    and C_Item.GetItemQualityByID(id)
  if quality and quality < MIN_QUALITY then return end

  for _, item in ipairs(s.items) do
    if item.id == id then return end     -- already listed this session
  end
  table.insert(s.items, { id = id, name = name })
end

---------------------------------------------------------------------------
-- Dungeons: count each time we zone into a 5-player dungeon
---------------------------------------------------------------------------

local inDungeon = false

local function checkDungeon(isReload)
  local _, instanceType = IsInInstance()
  local nowInDungeon = (instanceType == "party")
  -- Don't count: a /reload inside the dungeon, or running back in as a
  -- ghost after a wipe.
  if nowInDungeon and not inDungeon and not isReload
     and not UnitIsDeadOrGhost("player") then
    local s = current()
    local name = GetInstanceInfo()       -- first value is the dungeon name
    if s and name then table.insert(s.dungeons, name) end
  end
  inDungeon = nowInDungeon
end

---------------------------------------------------------------------------
-- Login, reload and logout
---------------------------------------------------------------------------

-- Moves a finished session from a character into the shared list.
local function closeSession(char)
  if char.current then
    table.insert(db.sessions, char.current)
    char.current = nil
  end
end

local function onLogin(isReload)
  local name, realm = UnitFullName("player")
  realm = realm or GetNormalizedRealmName() or ""
  charKey = name .. "-" .. realm

  db.characters[charKey] = db.characters[charKey] or {}
  me = db.characters[charKey]
  me.name = name

  -- PLAYER_LOGOUT fires for both /reload and a real logout, and we can't
  -- tell them apart at that moment. So each session stays "open" on its
  -- character until the next load. Here we decide: a /reload continues
  -- this character's session, anything else closes every open session.
  for _, char in pairs(db.characters) do
    if not (isReload and char == me) then closeSession(char) end
  end
  if not me.current then me.current = newSession() end

  lastLevel = nil
  updateXP()             -- remember starting XP
  checkDungeon(isReload)
  Tracker.Snapshot()
end

---------------------------------------------------------------------------
-- Event wiring
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}   -- event name -> function

handlers.ADDON_LOADED = function(addonName)
  if addonName ~= "DuoLedger" then return end    -- fires for every addon
  -- First run: the SavedVariable is nil, so create the empty layout.
  DuoLedgerDB = DuoLedgerDB or {}
  db = DuoLedgerDB
  db.characters = db.characters or {}
  db.sessions   = db.sessions or {}
  ns.db = db
  frame:UnregisterEvent("ADDON_LOADED")
end

local loggedIn = false
handlers.PLAYER_ENTERING_WORLD = function(isInitialLogin, isReloadingUi)
  -- This fires after every loading screen, not just at login.
  if not loggedIn then
    loggedIn = true
    onLogin(isReloadingUi)
  else
    checkDungeon(false)
    Tracker.Snapshot()
  end
end

handlers.PLAYER_XP_UPDATE = function()
  updateXP()
  Tracker.Snapshot()
end

handlers.PLAYER_LEVEL_UP = function()
  -- UnitLevel can lag behind this event for a moment, so check again
  -- after a short delay.
  C_Timer.After(1, function() updateXP(); Tracker.Snapshot() end)
end

handlers.PLAYER_DEAD = function()
  local s = current()
  if s then s.deaths = s.deaths + 1 end
  Tracker.Snapshot()
end

-- QUEST_COMPLETE fires when the quest's reward window opens. We note the
-- title then, because by the time QUEST_TURNED_IN fires it may be gone.
local pendingQuest = {}
handlers.QUEST_COMPLETE = function()
  pendingQuest.id   = GetQuestID and GetQuestID()
  pendingQuest.name = GetTitleText and GetTitleText()
end

handlers.QUEST_TURNED_IN = function(questID)
  local s = current()
  if not s then return end
  local name = (pendingQuest.id == questID) and pendingQuest.name or nil
  if not name and C_QuestLog and C_QuestLog.GetTitleForQuestID then
    name = C_QuestLog.GetTitleForQuestID(questID)
  end
  -- The Ledger matches quests by name, so a name matters more than the id.
  table.insert(s.quests, { id = questID, name = name or ("Quest " .. questID) })
  Tracker.Snapshot()
end

handlers.CHAT_MSG_LOOT = function(msg)
  recordLoot(msg)
end

-- Mail: the game doesn't tell us what was in a letter once it's sent, so we
-- look at the attachments the moment you press Send, then keep them only
-- if MAIL_SEND_SUCCESS follows. hooksecurefunc runs our function right after
-- Blizzard's SendMail, without changing or slowing Blizzard's code.
local pendingMail
local function onSendMail(recipient)
  if not recipient then return end
  pendingMail = {}
  local to = recipient:match("^([^-]+)") or recipient   -- drop "-Realm"
  for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
    local name, _, _, count = GetSendMailItem(i)
    if name then
      table.insert(pendingMail, { to = to, item = name, qty = count or 1 })
    end
  end
end
if C_Mail and C_Mail.SendMail then hooksecurefunc(C_Mail, "SendMail", onSendMail) end
if SendMail then hooksecurefunc("SendMail", onSendMail) end

handlers.MAIL_SEND_SUCCESS = function()
  local s = current()
  if s and pendingMail then
    for _, m in ipairs(pendingMail) do table.insert(s.mail, m) end
  end
  pendingMail = nil
end

handlers.MAIL_FAILED = function()
  pendingMail = nil
end

handlers.PLAYER_LOGOUT = function()
  Tracker.Snapshot()
  if me then me.logout = time() end
  -- Keep the latest export string in the saved file too, so it can be
  -- copied from WTF\...\SavedVariables\DuoLedger.lua outside the game.
  if ns.BuildExport then db.lastExport = ns.BuildExport(true) end
end

-- These only change the snapshot, so they share one handler.
for _, event in ipairs({
  "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_UPDATE_RESTING",
  "UPDATE_EXHAUSTION", "HEARTHSTONE_BOUND",
}) do
  handlers[event] = Tracker.Snapshot
end

for event in pairs(handlers) do
  frame:RegisterEvent(event)
end

-- One OnEvent script for everything: look up the handler by event name
-- and pass along the event's arguments ("..." means "all the rest").
frame:SetScript("OnEvent", function(self, event, ...)
  handlers[event](...)
end)

---------------------------------------------------------------------------
-- Used by the export and the window
---------------------------------------------------------------------------

function Tracker.CurrentCharacter() return me end
function Tracker.CurrentSession()   return current() end

-- Deletes finished sessions (after you've imported them into the Ledger).
-- The session you're playing right now is kept.
function Tracker.ClearSessions()
  wipe(db.sessions)
end

local function isEmpty(s)
  return s.xpGained == 0 and s.deaths == 0 and #s.quests == 0
    and #s.items == 0 and #s.dungeons == 0 and #s.mail == 0
    and s.levelFrom == s.levelTo and (s["end"] - s.start) < 60
end

-- Called when you open the Export view. The Ledger imports each session
-- only once (it recognises it by character + start time), so anything
-- added to a session after you've imported it would be ignored. To avoid
-- that, exporting closes the current session and starts a fresh one that
-- carries on from here. Nothing is lost, and nothing is counted twice.
function Tracker.SplitSession()
  if not me or not me.current then return end
  Tracker.Snapshot()
  local finished = me.current
  me.current = newSession()
  if not isEmpty(finished) then table.insert(db.sessions, finished) end
end
