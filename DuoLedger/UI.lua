-- UI.lua
-- The Duo Ledger window. Two views:
--   Summary: your character and this session at a glance
--   Export:  the text to copy into the Ledger's Import box
--
-- Ways to open it:
--   keyboard: /ledger, or a key you bind in Options > Keybindings > AddOns
--   mouse:    the AddOns button by the minimap (the "addon compartment")
--   gamepad:  bind "Toggle Duo Ledger" to a controller button the same way
-- Inside the window a controller can use A (export), B (close) and the
-- D-pad left/right (switch view).

local _, ns = ...

local UI = {}
ns.UI = UI

local panel           -- the window, built the first time it's opened
local summaryText     -- FontString for the summary view
local exportBox       -- EditBox holding the export text
local summaryView, exportView, ledgerView
local ledgerText      -- FontString for the Ledger view
local ledgerChild     -- the frame inside the Ledger view's scroll area

---------------------------------------------------------------------------
-- Summary text
---------------------------------------------------------------------------

local function commas(n)
  -- 12345 -> "12,345". BreakUpLargeNumbers is Blizzard's helper for this.
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n or 0) end
  return tostring(n or 0)
end

local function minutesSince(t)
  return math.floor((time() - (t or time())) / 60)
end

local function buildSummary()
  local c = ns.Tracker.CurrentCharacter()
  local s = ns.Tracker.CurrentSession()
  if not c or not s then return "Waiting for login..." end

  local pct = (c.xpMax and c.xpMax > 0) and math.floor(c.xp / c.xpMax * 100) or 0
  local lines = {
    -- |cffffd100 ... |r colours text gold, like Blizzard's headings.
    string.format("|cffffd100%s|r  level %d %s %s",
      c.name or "?", c.level or 0, c.race or "", c.class or ""),
    string.format("XP %s / %s (%d%%)   Rested %s%s",
      commas(c.xp), commas(c.xpMax), pct, commas(c.restXP),
      c.resting and "  |cff40ff40(resting)|r" or ""),
    string.format("Zone: %s   Hearth: %s", c.zone or "?", c.hearth or "?"),
    "",
    "|cffffd100Since login or last export|r  (" .. minutesSince(s.start) .. " min)",
    string.format("Levels %d to %d   XP gained %s",
      s.levelFrom or 0, s.levelTo or 0, commas(s.xpGained)),
    -- # gives the length of a list.
    string.format("Quests %d   Items %d   Dungeons %d",
      #s.quests, #s.items, #s.dungeons),
    string.format("Deaths %d   Items mailed %d", s.deaths, #s.mail),
    "",
    string.format("|cff999999Finished sessions stored: %d|r",
      #ns.db.sessions),
    -- The bank can only be counted while it's open, so say how old it is.
    "|cff999999Bank last counted: " .. (c.bankAt
      and (minutesSince(c.bankAt) .. " min ago") or "never, visit a banker")
      .. "|r",
  }
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Ledger text: what the Ledger sent us (see Ledger.lua)
---------------------------------------------------------------------------

local GOLD, GREY, END = "|cffffd100", "|cff999999", "|r"

local function buildLedger()
  if not ns.Ledger.HasData() then
    return "Nothing from the Ledger yet.\n\n"
      .. "In the Ledger, press Send to game and save LedgerData.lua into "
      .. "Interface\\AddOns\\DuoLedger. Then type /reload."
  end
  local me = ns.Tracker.CurrentCharacter()
  local c = me and ns.Ledger.Character(me.name)
  if not c then
    return "The Ledger has no character called " .. (me and me.name or "?")
      .. ".\nName it on the Ledger's Pairs tab exactly as in game, then send again."
  end

  local lines = {}
  local function add(s) lines[#lines + 1] = s end

  if c.partner and c.partner ~= "" then
    add(string.format("%sPartner|r  %s, level %d", GOLD, c.partner, c.partnerLevel or 0))
  end

  add("")
  add(GOLD .. "Mail to send" .. END)
  if #(c.mail or {}) == 0 then add(GREY .. "Nothing queued." .. END) end
  for _, m in ipairs(c.mail or {}) do
    add(string.format("%s x%d to %s%s", m.item, m.qty or 1,
      (m.to ~= "" and m.to or "your partner"),
      m.standing and (GREY .. " (every time)" .. END) or ""))
  end

  add("")
  add(GOLD .. "Wishlist" .. END .. GREY .. "  (also shown on item tooltips)" .. END)
  if #(c.wishlist or {}) == 0 then add(GREY .. "Nothing left on it." .. END) end
  for _, item in ipairs(c.wishlist or {}) do
    add(string.format("%s %s(level %d)%s", item.name, GREY, item.level or 0, END))
  end

  add("")
  add(GREY .. "Sent from the Ledger " .. (ns.Ledger.SentAt() or "?"):gsub("T", " "):gsub("Z", " UTC") .. END)
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Switching views
---------------------------------------------------------------------------

local function hideViews()
  summaryView:Hide()
  exportView:Hide()
  ledgerView:Hide()
end

local function showSummary()
  hideViews()
  summaryView:Show()
  summaryText:SetText(buildSummary())
end

local function showLedger()
  hideViews()
  ledgerView:Show()
  ledgerText:SetText(buildLedger())
  -- The scroll area needs to know how tall the text is.
  ledgerChild:SetHeight(ledgerText:GetStringHeight() + 8)
end

local function showExport()
  hideViews()
  exportView:Show()
  ns.Tracker.SplitSession()      -- see Tracker.lua for why
  exportBox:SetText(ns.BuildExport())
  -- Select everything so Ctrl+C copies it in one go.
  exportBox:SetFocus()
  exportBox:HighlightText()
end

function UI.Refresh()
  if panel and panel:IsShown() and summaryView:IsShown() then
    summaryText:SetText(buildSummary())
  end
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

local function makeButton(parent, label, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(130, 32)               -- big enough to hit easily
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function build()
  panel = CreateFrame("Frame", "DuoLedgerPanel", UIParent,
    "BasicFrameTemplateWithInset")
  panel:SetSize(480, 340)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:Hide()

  -- Let the mouse drag it around by the window.
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

  -- Frames listed in UISpecialFrames close when you press Escape.
  table.insert(UISpecialFrames, "DuoLedgerPanel")

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("Duo Ledger")

  -- Summary view ----------------------------------------------------------
  summaryView = CreateFrame("Frame", nil, panel)
  summaryView:SetPoint("TOPLEFT", 16, -36)
  summaryView:SetPoint("BOTTOMRIGHT", -16, 56)

  summaryText = summaryView:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
  summaryText:SetPoint("TOPLEFT")
  summaryText:SetPoint("TOPRIGHT")
  summaryText:SetJustifyH("LEFT")
  summaryText:SetSpacing(4)

  -- Ledger view -----------------------------------------------------------
  ledgerView = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  ledgerView:SetPoint("TOPLEFT", 16, -36)
  ledgerView:SetPoint("BOTTOMRIGHT", -42, 56)
  ledgerView:Hide()

  ledgerChild = CreateFrame("Frame", nil, ledgerView)
  ledgerChild:SetSize(420, 10)
  ledgerView:SetScrollChild(ledgerChild)

  ledgerText = ledgerChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
  ledgerText:SetPoint("TOPLEFT")
  ledgerText:SetWidth(420)
  ledgerText:SetJustifyH("LEFT")
  ledgerText:SetSpacing(4)

  -- Export view -----------------------------------------------------------
  exportView = CreateFrame("Frame", nil, panel)
  exportView:SetPoint("TOPLEFT", 16, -36)
  exportView:SetPoint("BOTTOMRIGHT", -16, 56)
  exportView:Hide()

  local hint = exportView:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  hint:SetPoint("TOPLEFT")
  hint:SetPoint("TOPRIGHT")
  hint:SetJustifyH("LEFT")
  hint:SetText("Press Ctrl+C to copy, then paste into the Ledger's Import.")

  -- A scrolling text box: a ScrollFrame with an EditBox inside it.
  local scroll = CreateFrame("ScrollFrame", nil, exportView,
    "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -22)
  scroll:SetPoint("BOTTOMRIGHT", -26, 0)

  exportBox = CreateFrame("EditBox", nil, scroll)
  exportBox:SetMultiLine(true)
  exportBox:SetAutoFocus(false)
  exportBox:SetMaxLetters(0)                     -- 0 = no length limit
  exportBox:SetFontObject(ChatFontNormal)
  exportBox:SetWidth(420)
  exportBox:SetScript("OnEscapePressed", function() panel:Hide() end)
  -- If you click in the box, select it all again, ready to copy.
  exportBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
  scroll:SetScrollChild(exportBox)

  -- Buttons ---------------------------------------------------------------
  -- Four buttons in a row, each 104 wide with an 8-pixel gap.
  local buttons = {
    { "Summary", showSummary },
    { "Ledger",  showLedger },
    { "Export",  showExport },
    { "Close",   function() panel:Hide() end },
  }
  for i, def in ipairs(buttons) do
    local b = makeButton(panel, def[1], def[2])
    b:SetWidth(104)
    b:SetPoint("BOTTOMLEFT", 16 + (i - 1) * 112, 14)
  end

  -- Gamepad ---------------------------------------------------------------
  -- Frames can listen to controller buttons directly. The "if" checks that
  -- this client has the feature before we use it.
  if panel.EnableGamePadButton then
    panel:EnableGamePadButton(true)
    panel:SetScript("OnGamePadButtonDown", function(self, button)
      local handled = true
      if button == "PAD2" then                      -- B: close
        self:Hide()
      elseif button == "PAD1" then                  -- A: export
        showExport()
      elseif button == "PADDLEFT" or button == "PADDRIGHT" then
        -- Cycle Summary -> Ledger -> Export (right) or the other way (left).
        local order = { showSummary, showLedger, showExport }
        local now = summaryView:IsShown() and 1 or ledgerView:IsShown() and 2 or 3
        local step = (button == "PADDRIGHT") and 1 or -1
        order[(now - 1 + step) % 3 + 1]()
      else
        handled = false
      end
      -- Pass buttons we don't use back to the game (movement, abilities).
      if self.SetPropagateKeyboardInput and not InCombatLockdown() then
        self:SetPropagateKeyboardInput(not handled)
      end
    end)
  end

  panel:SetScript("OnShow", showSummary)
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

function UI.Toggle()
  -- Our window isn't protected, but to stay well clear of the combat
  -- rules (and out of your way) we don't open it in combat.
  if InCombatLockdown() then
    print("|cffffd100Duo Ledger:|r not during combat.")
    return
  end
  if not panel then build() end
  panel:SetShown(not panel:IsShown())
end

function UI.OpenExport()
  if InCombatLockdown() then return end
  if not panel then build() end
  panel:Show()
  showExport()
end

-- Close the window automatically when combat starts.
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatcher:SetScript("OnEvent", function()
  if panel and panel:IsShown() then panel:Hide() end
end)

-- Global (no "local") on purpose: Bindings.xml and the minimap AddOns
-- button call this by name.
function DuoLedger_Toggle()
  UI.Toggle()
end

-- Text shown in Options > Keybindings.
BINDING_HEADER_DUOLEDGER = "Duo Ledger"
BINDING_NAME_DUOLEDGER_TOGGLE = "Toggle Duo Ledger"

---------------------------------------------------------------------------
-- Slash commands: /ledger, /ledger export, /ledger clear
---------------------------------------------------------------------------

StaticPopupDialogs["DUOLEDGER_CLEAR"] = {
  text = "Delete saved Duo Ledger sessions? Only do this after importing them into the Ledger. Your current session is kept.",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    ns.Tracker.ClearSessions()
    UI.Refresh()
    print("|cffffd100Duo Ledger:|r saved sessions cleared.")
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

SLASH_DUOLEDGER1 = "/ledger"
SLASH_DUOLEDGER2 = "/duoledger"
SlashCmdList.DUOLEDGER = function(msg)
  msg = (msg or ""):lower():trim()
  if msg == "export" then
    UI.OpenExport()
  elseif msg == "clear" then
    StaticPopup_Show("DUOLEDGER_CLEAR")
  else
    UI.Toggle()
  end
end
