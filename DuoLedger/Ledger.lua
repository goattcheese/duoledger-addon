-- Ledger.lua
-- Reads what the Forever Duo Ledger sent us in LedgerData.lua and answers
-- questions about it: who's my partner, what should I mail, what's on my
-- wishlist? It also adds "Ledger wishlist" lines to item tooltips.

local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

-- LedgerData.lua loads before this file (see the .toc), so the global
-- DuoLedgerLedgerData is already set, or nil if nothing was sent yet.
local function data()
  local d = DuoLedgerLedgerData
  if type(d) == "table" and d.app == "ForeverDuoLedger" then return d end
  return nil
end

function Ledger.HasData()
  return data() ~= nil
end

-- When the Ledger wrote the file, as the ISO text it sent.
function Ledger.SentAt()
  local d = data()
  return d and d.at
end

-- The Ledger's entry for a character, found by name (any capitals).
function Ledger.Character(name)
  local d = data()
  if not d or not name then return nil end
  for _, c in ipairs(d.characters or {}) do
    if c.name and c.name:lower() == name:lower() then return c end
  end
  return nil
end

-- Every character whose Ledger wishlist still needs this item.
-- Returns a list of names, possibly empty.
function Ledger.WantedBy(itemID)
  local names = {}
  local d = data()
  if not d or not itemID then return names end
  for _, c in ipairs(d.characters or {}) do
    for _, item in ipairs(c.wishlist or {}) do
      if item.id == itemID then
        table.insert(names, c.name)
        break
      end
    end
  end
  return names
end

---------------------------------------------------------------------------
-- Tooltips: "Ledger wishlist: Grumtusk" under any item someone needs
---------------------------------------------------------------------------

-- TooltipDataProcessor lets addons add lines to Blizzard's tooltips after
-- the game has filled them in. We check it exists before using it.
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,
    function(tooltip, tooltipData)
      local id = tooltipData and tooltipData.id
      -- Tooltip data can be secret in some situations; skip it then.
      if not id or (issecretvalue and issecretvalue(id)) then return end
      local names = Ledger.WantedBy(id)
      if #names > 0 then
        tooltip:AddLine("Ledger wishlist: " .. table.concat(names, ", "),
          0.4, 1, 0.75)        -- red, green, blue from 0 to 1: a soft green
      end
    end)
end
