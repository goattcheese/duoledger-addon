-- Export.lua
-- Builds the text you paste into the Ledger's Import box:
-- {app:'ForeverDuoLedger', v:1, characters:[...], sessions:[...]}

local _, ns = ...

-- The Ledger wants times as ISO 8601 text, like "2026-10-06T17:37:00Z".
-- We store Unix time (seconds since 1970) and convert here. In date(),
-- "!" means UTC, which is what the "Z" on the end promises.
local function formatTime(t)
  if not t then return nil end
  return date("!%Y-%m-%dT%H:%M:%SZ", t)
end

-- The Ledger only accepts hearths from its own list. Where the game's name
-- for a place differs from the Ledger's, translate it here.
local HEARTH_NAMES = {
  ["Stormwind City"] = "Stormwind",
}

-- Copies a list into a fresh table tagged as a JSON array, so an empty
-- list prints as [] rather than {}.
local function list(t)
  local out = ns.Json.array()
  for i, v in ipairs(t or {}) do out[i] = v end
  return out
end

-- The order fields appear in, matching the Ledger's format.
local KEY_ORDER = {
  "id",   -- quests and items read best as {"id":..., "name":...}
  "app", "v", "characters", "sessions",
  -- characters
  "name", "class", "race", "level", "xp", "zone", "hearth",
  "restXP", "xpMax", "resting", "logout", "professions", "inventory",
  -- sessions
  "character", "start", "end", "levelFrom", "levelTo", "xpGained",
  "deaths", "deathLog", "moneyGained", "quests", "items", "dungeons", "mail",
  -- inside deathLog
  "at", "killer",
  -- inside mail
  "to", "item", "qty",
}

-- Returns t, or nil when it's empty, so empty lists are left out.
local function nonEmpty(t)
  if t and next(t) ~= nil then return t end
  return nil
end

local function exportCharacter(c, isOnline)
  return {
    name    = c.name,
    class   = c.class,
    race    = c.race,
    level   = c.level,
    xp      = c.xp,
    zone    = c.zone,
    hearth  = HEARTH_NAMES[c.hearth] or c.hearth,
    restXP  = c.restXP or 0,
    xpMax   = c.xpMax,
    resting = c.resting and true or false,
    -- The character you're on hasn't logged out yet. Its numbers are
    -- "as of now", so we use now as its logout time.
    logout  = formatTime(isOnline and time() or c.logout),
    -- For the profession planner: skill by profession name, and how many
    -- of each item you have in bags and bank together.
    professions = nonEmpty(c.professions),
    inventory   = nonEmpty(ns.Inventory.Totals(c)),
  }
end

-- Each death as {at, zone, killer}, with the time as ISO text.
local function deathLog(t)
  local out = ns.Json.array()
  for i, d in ipairs(t or {}) do
    out[i] = { at = formatTime(d.at), zone = d.zone, killer = d.killer }
  end
  return out
end

local function exportSession(s)
  return {
    character = s.character,
    start     = formatTime(s.start),
    ["end"]   = formatTime(s["end"]),
    levelFrom = s.levelFrom,
    levelTo   = s.levelTo,
    xpGained  = s.xpGained,
    deaths    = s.deaths,
    deathLog  = nonEmpty(deathLog(s.deathLog)),
    moneyGained = s.moneyGained,
    quests    = list(s.quests),
    items     = list(s.items),
    dungeons  = list(s.dungeons),
    mail      = list(s.mail),
  }
end

-- includeOpen: also include the session you're still playing. The Export
-- window leaves it out (it has just split the session, see Tracker.lua).
-- The copy saved at logout puts it in, because by then it's finished.
function ns.BuildExport(includeOpen)
  local db = ns.db
  if not db then return "" end
  ns.Tracker.Snapshot()                    -- make sure numbers are fresh
  ns.Inventory.ScanAll()
  local online = ns.Tracker.CurrentCharacter()

  local characters = ns.Json.array()
  local sessions   = ns.Json.array()
  local raw = {}

  for _, c in pairs(db.characters) do
    if c.name and c.level then
      table.insert(characters, exportCharacter(c, c == online))
    end
    if includeOpen and c.current then table.insert(raw, c.current) end
  end
  for _, s in ipairs(db.sessions) do table.insert(raw, s) end

  table.sort(characters, function(a, b) return a.name < b.name end)
  table.sort(raw, function(a, b) return a.start < b.start end)
  for _, s in ipairs(raw) do table.insert(sessions, exportSession(s)) end

  return ns.Json.encode({
    app = "ForeverDuoLedger",
    v = 1,
    characters = characters,
    sessions = sessions,
  }, KEY_ORDER)
end
