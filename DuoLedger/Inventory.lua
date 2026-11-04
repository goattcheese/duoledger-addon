-- Inventory.lua
-- Counts what's in your bags and bank, and reads your profession skills,
-- so the Ledger's profession planner can fill in its "Have" column and
-- skill levels. Everything is stored on the character's record:
--   me.bags        = { ["Copper Bar"] = 24, ... }
--   me.bank        = { ["Rough Stone"] = 18, ... }
--   me.professions = { ["Mining"] = 95, ... }
--
-- The game only lets addons see the bank while the bank window is open,
-- so bank counts update each time you visit a banker.

local _, ns = ...

local Inventory = {}
ns.Inventory = Inventory

---------------------------------------------------------------------------
-- Which bag numbers are bags and which are bank
---------------------------------------------------------------------------

-- Each bag has a number. Enum.BagIndex names them (Backpack = 0 and so
-- on), and newer clients add bank tabs. We pick them out by name so we
-- don't depend on one game version's numbering.
local function bagIDs(patterns, fallback)
  local ids = {}
  if Enum and Enum.BagIndex then
    for key, id in pairs(Enum.BagIndex) do
      for _, pattern in ipairs(patterns) do
        if key:match(pattern) then table.insert(ids, id); break end
      end
    end
  end
  if #ids == 0 then ids = fallback end
  return ids
end

local BAGS = bagIDs({ "^Backpack$", "^Bag_%d$", "^ReagentBag$" },
  { 0, 1, 2, 3, 4 })
local BANK = bagIDs({ "^Bank$", "^BankBag_%d$", "^CharacterBankTab_%d$",
  "^Reagentbank$" }, { -1, 5, 6, 7, 8, 9, 10, 11 })

---------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------

local function numSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag) or 0
  end
  return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

-- Returns the item's name and how many are in that slot, or nil.
local function slotItem(bag, slot)
  local link, count
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then link, count = info.hyperlink, info.stackCount end
  elseif GetContainerItemInfo then
    local _
    _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
  end
  -- The name sits between [ and ] in the item link, and that works even
  -- before the game has loaded the item's full details.
  local name = link and link:match("%[(.-)%]")
  if name then return name, count or 1 end
end

local function count(bagList)
  local totals = {}
  for _, bag in ipairs(bagList) do
    for slot = 1, numSlots(bag) do
      local name, n = slotItem(bag, slot)
      if name then totals[name] = (totals[name] or 0) + n end
    end
  end
  return totals
end

---------------------------------------------------------------------------
-- Profession skills
---------------------------------------------------------------------------

-- Used only on clients without GetProfessions, where we read the old
-- skill list and need to know which lines are professions.
local PROFESSION_NAMES = {
  Alchemy = true, Blacksmithing = true, Enchanting = true,
  Engineering = true, Herbalism = true, Leatherworking = true,
  Mining = true, Skinning = true, Tailoring = true, Jewelcrafting = true,
  Inscription = true, Cooking = true, ["First Aid"] = true, Fishing = true,
}

local function readProfessions()
  local skills = {}
  if GetProfessions and GetProfessionInfo then
    -- GetProfessions returns up to six slots (two main professions, then
    -- archaeology, fishing, cooking, first aid). Empty slots are nil, so
    -- we can't use ipairs here; select("#", ...) counts them all.
    local slots = { GetProfessions() }
    for i = 1, select("#", GetProfessions()) do
      if slots[i] then
        local name, _, rank = GetProfessionInfo(slots[i])
        if name and rank then skills[name] = rank end
      end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank = GetSkillLineInfo(i)
      if name and not isHeader and PROFESSION_NAMES[name] then
        skills[name] = rank
      end
    end
  end
  return skills
end

---------------------------------------------------------------------------
-- Keeping the character record up to date
---------------------------------------------------------------------------

local bankOpen = false

local function scanBags()
  local me = ns.Tracker.CurrentCharacter()
  if me then me.bags = count(BAGS) end
end

local function scanBank()
  local me = ns.Tracker.CurrentCharacter()
  if me and bankOpen then
    me.bank = count(BANK)
    me.bankAt = time()
  end
end

local function scanProfessions()
  local me = ns.Tracker.CurrentCharacter()
  if not me then return end
  local skills = readProfessions()
  if next(skills) then me.professions = skills end   -- keep old if empty
end

function Inventory.ScanAll()
  scanBags()
  scanBank()
  scanProfessions()
end

-- Bags plus bank, added together: what the Ledger calls "inventory".
function Inventory.Totals(c)
  local totals = {}
  for _, source in ipairs({ c.bags or {}, c.bank or {} }) do
    for name, n in pairs(source) do totals[name] = (totals[name] or 0) + n end
  end
  return totals
end

local frame = CreateFrame("Frame")
local handlers = {}

handlers.PLAYER_ENTERING_WORLD = function()
  -- Wait a moment so Tracker.lua has set up the character record first.
  C_Timer.After(2, Inventory.ScanAll)
end

-- Fires once after a burst of bag changes (looting a stack, selling...).
handlers.BAG_UPDATE_DELAYED = function()
  scanBags()
  scanBank()
end

handlers.BANKFRAME_OPENED = function()
  bankOpen = true
  scanBank()
end

handlers.BANKFRAME_CLOSED = function()
  bankOpen = false
end

handlers.PLAYERBANKSLOTS_CHANGED = scanBank
handlers.SKILL_LINES_CHANGED = scanProfessions
handlers.PLAYER_LOGOUT = Inventory.ScanAll

for event in pairs(handlers) do
  -- pcall: if this client doesn't have one of these events, skip it
  -- instead of stopping the whole file with an error.
  pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(self, event, ...)
  handlers[event](...)
end)
