-- Gnistify shot caller ("leder"): pick one group member as the shot caller,
-- then press one key to target whatever the caller is targeting.
--
-- Targeting is a protected action on Forever's modern client: addon code may
-- not call TargetUnit/AssistUnit itself. So the actual targeting is done by a
-- hidden SECURE button, GnistAssistButton (type "assist", unit = the caller's
-- unit token such as "raid7"). Players press it with:
--   * the key binding "Mål lederens mål" (Options -> Keybindings -> Gnistify), or
--   * a macro with "/click GnistAssistButton" (/gnist makro creates one).
-- Secure attributes can only be changed out of combat. A caller picked in
-- combat, or a group change in combat, is applied as soon as combat ends.
--
-- Picking the caller shares it with the group on the GnistDing prefix
-- ("LEDER;Navn", empty name = no caller), so everyone with Gnistify follows the
-- same caller (setting callerFollow). Older versions ignore LEDER; messages.
--
-- Clicking the window does the same as the key (it IS the secure button).
-- The small "Leder" window opens by itself in battlegrounds, arenas and
-- dungeons; elsewhere via /gnist leder or the button in /gnist. It shows the caller, the caller's target and whether
-- you have the same target. A short ping plays when the caller switches to a
-- new enemy you don't have targeted yet (setting callerSound).

local ns = select(2, ...)
local PREFIX = ns.PREFIX
local Readable, FullName, Me, Short, Print = ns.Readable, ns.FullName, ns.Me, ns.Short, ns.Print

local BUTTON = "GnistAssistButton"
local MACRO_NAME = "GnistMål"
local PING_SOUND = (SOUNDKIT and SOUNDKIT.MAP_PING) or 3175
local PING_GAP = 1.5          -- seconds between pings
local REBROADCAST_GAP = 5     -- the caller re-announces at most this often

BINDING_HEADER_GNISTIFY = "|cffffcc00Gnist|r|cffff6600ify|r"
_G["BINDING_NAME_CLICK " .. BUTTON .. ":LeftButton"] = "Mål lederens mål"

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- Group ----------------------------------------------------------------------
local function GroupUnits()
    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do units[#units + 1] = "raid" .. i end
    elseif IsInGroup and IsInGroup() then
        units[1] = "player"
        for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 4) do
            units[#units + 1] = "party" .. i
        end
    end
    return units
end

local function FindUnit(name)
    if not name then return nil end
    for _, unit in ipairs(GroupUnits()) do
        if Readable(UnitExists(unit)) and FullName(unit) == name then return unit end
    end
end

local function GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function Share(name)
    local channel = GroupChannel()
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if channel and send then pcall(send, PREFIX, "LEDER;" .. (name or ""), channel) end
end

-- The secure button ------------------------------------------------------------
-- The same button is the clickable body of the Leder window: the window is
-- anchored TO the button (never the other way round, because anchoring a
-- secure frame to an insecure one would make the window protected, and then
-- resizing it in combat would be blocked). The button can only be moved,
-- resized, shown or hidden out of combat; SyncButton catches up afterwards.
-- Left click (and the key binding / /click) assists; right-drag moves.
local button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
button:Hide()
-- Down AND up: a key binding or /click may send either one depending on the
-- "cast on key down" setting. Assisting twice does no harm.
button:RegisterForClicks("AnyUp", "AnyDown")
button:SetSize(200, 58)
button:SetFrameStrata("MEDIUM")
button:SetMovable(true)
button:SetClampedToScreen(true)
button:RegisterForDrag("RightButton")

local callerUnit        -- unit token the button points at (nil = nobody)
local pending = false   -- the button needs updating once combat ends

local UpdateWindow      -- defined below

local function ApplyButton()
    local unit = FindUnit(GnistifyDB.callerName)
    if InCombat() then
        if unit ~= callerUnit then pending = true end
        return
    end
    pending = false
    callerUnit = unit
    button:SetAttribute("type1", unit and "assist" or nil)   -- left button only
    button:SetAttribute("unit", unit)
end

local function SetCaller(name, share, by)
    GnistifyDB.callerName = name
    ApplyButton()
    if share then Share(name) end
    if name then
        local who = (name == Me()) and "Du er nu leder" or ("|cffff6600" .. name .. "|r er nu leder")
        Print(who .. (by and (" (valgt af " .. by .. ")") or "") .. ".")
        if pending then Print("Du er i kamp - knappen virker så snart kampen er slut.") end
    else
        Print("Ingen leder" .. (by and (" (fjernet af " .. by .. ")") or "") .. ".")
    end
    UpdateWindow()
end

-- Window -----------------------------------------------------------------------
local win = CreateFrame("Frame", "GnistifyCallerFrame", UIParent, "BackdropTemplate")
win:SetSize(200, 58)
win:SetFrameStrata("MEDIUM")
win:SetFrameLevel(button:GetFrameLevel() + 2)   -- Vælg and X sit above the button
win:EnableMouse(false)                          -- clicks fall through to the button
win:SetPoint("TOPLEFT", button, "TOPLEFT")

local hover = win:CreateTexture(nil, "OVERLAY")
hover:SetPoint("TOPLEFT", 3, -3)
hover:SetPoint("BOTTOMRIGHT", -3, 3)
hover:SetColorTexture(1, 0.6, 0, 0.12)
hover:Hide()

button:SetScript("OnDragStart", function(self)
    if not InCombat() then self:StartMoving() end
end)
button:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    GnistifyDB.callerPos = { point, rel, x, y }
end)
button:SetScript("OnEnter", function(self)
    hover:Show()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Gnistify leder")
    GameTooltip:AddLine("Klik: tag lederens mål", 1, 1, 1)
    GameTooltip:AddLine("Højreklik og træk: flyt vinduet", 1, 1, 1)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function()
    hover:Hide()
    GameTooltip:Hide()
end)

-- Size and show/hide the click area like the window, but only out of combat.
local buttonDirty = false
local function SyncButton()
    if InCombat() then buttonDirty = true return end
    buttonDirty = false
    button:SetSize(win:GetWidth(), win:GetHeight())
    if win:IsShown() then button:Show() else button:Hide() end
end
if win.SetBackdrop then
    win:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    win:SetBackdropColor(0, 0, 0, 0.75)
    win:SetBackdropBorderColor(1, 0.6, 0, 0.9)
end
win:Hide()

local line1 = win:CreateFontString(nil, "ARTWORK", "GameFontNormal")
line1:SetPoint("TOPLEFT", 8, -8)
line1:SetJustifyH("LEFT")
local line2 = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
line2:SetPoint("TOPLEFT", line1, "BOTTOMLEFT", 0, -4)
line2:SetJustifyH("LEFT")
local line3 = win:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
line3:SetPoint("TOPLEFT", line2, "BOTTOMLEFT", 0, -3)
line3:SetJustifyH("LEFT")
-- No right anchor and no wrapping: the window grows to fit the longest line
-- (Forever names with surnames are long), see FitWindow.
for _, fs in ipairs({ line1, line2, line3 }) do
    if fs.SetWordWrap then fs:SetWordWrap(false) end
end
local MIN_WIDTH, BUTTONS_WIDTH = 200, 70   -- BUTTONS_WIDTH: room for Vælg and X
local HEIGHT, BAR_HEIGHT = 58, 8

-- Health bar of the caller's target. On Forever health can be a secret value,
-- which addon code can't read but a StatusBar can display, so the raw values
-- go straight into the bar (in a pcall, just in case). The game sends no
-- UNIT_HEALTH for "raidNtarget", so the bar is refreshed 10 times a second
-- while it's shown.
local bar = CreateFrame("StatusBar", nil, win)
bar:SetPoint("TOPLEFT", line2, "BOTTOMLEFT", 0, -3)
bar:SetPoint("RIGHT", win, "RIGHT", -8, 0)
bar:SetHeight(BAR_HEIGHT)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetMinMaxValues(0, 1)
local barBg = bar:CreateTexture(nil, "BACKGROUND")
barBg:SetAllPoints()
barBg:SetColorTexture(0, 0, 0, 0.6)
bar:Hide()

local barUnit   -- unit the bar follows, nil = hidden

local function RefreshBar()
    if not barUnit then return end
    pcall(bar.SetMinMaxValues, bar, 0, UnitHealthMax(barUnit))
    pcall(bar.SetValue, bar, UnitHealth(barUnit))
end

local function ShowBar(unit, enemy)
    barUnit = unit
    line3:ClearAllPoints()
    if unit then
        if enemy then bar:SetStatusBarColor(0.85, 0.15, 0.15)
        else bar:SetStatusBarColor(0.1, 0.8, 0.1) end
        bar:Show()
        line3:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -3)
        win:SetHeight(HEIGHT + BAR_HEIGHT + 3)
        RefreshBar()
    else
        bar:Hide()
        line3:SetPoint("TOPLEFT", line2, "BOTTOMLEFT", 0, -3)
        win:SetHeight(HEIGHT)
    end
end

local sinceBar = 0
win:SetScript("OnUpdate", function(_, elapsed)
    sinceBar = sinceBar + elapsed
    if sinceBar < 0.1 then return end
    sinceBar = 0
    RefreshBar()
end)

local pick = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
pick:SetSize(42, 18)
pick:SetPoint("TOPRIGHT", -24, -5)
pick:SetText("Vælg")

-- Picker: one button per group member, plus "Ingen".
local list = CreateFrame("Frame", nil, win, "BackdropTemplate")
list:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 0, -2)
list:SetFrameStrata("DIALOG")
if list.SetBackdrop then
    list:SetBackdrop(win:GetBackdrop())
    list:SetBackdropColor(0, 0, 0, 0.9)
    list:SetBackdropBorderColor(1, 0.6, 0, 0.9)
end
list:Hide()
local rows = {}
local ROW_W, ROW_H, PER_COLUMN = 130, 16, 20

local function Row(i)
    if rows[i] then return rows[i] end
    local b = CreateFrame("Button", nil, list)
    b:SetSize(ROW_W, ROW_H)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self)
        list:Hide()
        SetCaller(self.name, true)
    end)
    rows[i] = b
    return b
end

local function ClassColor(unit)
    local class = Readable((select(2, UnitClass(unit))))
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and c.colorStr or "ffffffff"
end

local function FillList()
    local entries = {}
    for _, unit in ipairs(GroupUnits()) do
        local name = Readable(UnitExists(unit)) and FullName(unit)
        if name then entries[#entries + 1] = { name = name, unit = unit } end
    end
    table.sort(entries, function(a, b) return a.name < b.name end)
    table.insert(entries, 1, { name = nil })   -- "Ingen leder"
    for i, e in ipairs(entries) do
        local b = Row(i)
        local col, row = math.floor((i - 1) / PER_COLUMN), (i - 1) % PER_COLUMN
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 6 + col * ROW_W, -6 - row * ROW_H)
        b.name = e.name
        if e.name then
            local mark = (e.name == GnistifyDB.callerName) and " |cffffcc00<|r" or ""
            b.text:SetText("|c" .. ClassColor(e.unit) .. ns.Alias(e.name) .. "|r" .. mark)
        else
            b.text:SetText("|cff999999Ingen leder|r")
        end
        b:Show()
    end
    for i = #entries + 1, #rows do rows[i]:Hide() end
    local cols = math.ceil(#entries / PER_COLUMN)
    list:SetSize(12 + cols * ROW_W, 12 + math.min(#entries, PER_COLUMN) * ROW_H)
end

pick:SetScript("OnClick", function()
    if list:IsShown() then list:Hide() return end
    if #GroupUnits() == 0 then
        Print("Du er ikke i en gruppe.")
        return
    end
    FillList()
    list:Show()
end)

-- The window opens by itself in battlegrounds, arenas and dungeons (setting
-- callerFrame). Anywhere else only when opened by hand (forceShow). The X
-- hides it until the next loading screen.
local AUTO_TYPES = { pvp = true, arena = true, party = true }
local forceShow = false
local dismissed = false

local function AutoZone()
    local inInstance, instanceType = IsInInstance()
    return Readable(inInstance) and AUTO_TYPES[Readable(instanceType) or ""] or false
end

local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetSize(20, 20)
close:SetPoint("TOPRIGHT", -2, -2)
close:SetScript("OnClick", function()
    forceShow, dismissed = false, true
    list:Hide()
    win:Hide()
end)

local function TextWidth(fs)
    return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
end

local function FitWindow()
    win:SetWidth(math.ceil(math.max(MIN_WIDTH,
        8 + TextWidth(line1) + BUTTONS_WIDTH,
        16 + TextWidth(line2),
        16 + TextWidth(line3))))
end

local function FillWindow()
    local name = GnistifyDB.callerName
    local inGroup = #GroupUnits() > 0
    local auto = GnistifyDB.callerFrame and AutoZone() and not dismissed
    if not inGroup or not (forceShow or auto) then
        win:Hide()
        list:Hide()
        return
    end
    win:Show()
    local unit = FindUnit(name)
    if not name then
        line1:SetText("|cffffcc00Leder:|r ingen")
        line2:SetText("Tryk Vælg for at vælge en leder")
        line3:SetText("")
        return
    end
    line1:SetText("|cffffcc00Leder:|r " .. ns.Alias(unit and ("|c" .. ClassColor(unit) .. name .. "|r") or name))
    if not unit then
        line2:SetText("|cff999999Ikke i din gruppe|r")
        line3:SetText("")
        return
    end
    local tunit = unit .. "target"
    local tname = Readable(UnitExists(tunit)) and FullName(tunit)
    local enemy
    if tname then
        enemy = Readable(UnitCanAttack("player", tunit))
        line2:SetText("Mål: " .. (enemy and "|cffff4040" or "|cffffffff") .. ns.Alias(tname) .. "|r")
        if unit == "player" or name == Me() then
            line3:SetText("|cff00ff00Du er leder - de andre følger dit mål|r")
        elseif Readable(UnitIsUnit("target", tunit)) then
            line3:SetText("|cff00ff00Du har samme mål|r")
        else
            line3:SetText("|cffff9900Tryk din leder-tast!|r")
        end
    else
        line2:SetText("Mål: |cff999999intet|r")
        line3:SetText("")
    end
    if pending then line3:SetText("|cffff9900Opdateres efter kamp|r") end
    if tname then return tunit, enemy end
end

UpdateWindow = function()
    local barFor, enemy = FillWindow()
    if win:IsShown() then
        ShowBar(barFor, enemy)
        FitWindow()
    else
        ShowBar(nil)
    end
    SyncButton()
end

local positioned = false
local function RestorePosition()
    if InCombat() then return end   -- tried again when combat ends
    positioned = true
    button:ClearAllPoints()
    local p = GnistifyDB.callerPos
    if p and p[1] then
        button:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        button:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

-- Ping when the caller switches to a new enemy that isn't my target yet.
local lastPing, lastCallerTarget = 0, nil
local function CallerTargetChanged()
    local unit = FindUnit(GnistifyDB.callerName)
    if not unit or unit == "player" or FullName(unit) == Me() then return end
    local tunit = unit .. "target"
    local guid = Readable(UnitGUID(tunit))
    if guid == lastCallerTarget then return end
    lastCallerTarget = guid
    if not guid or not GnistifyDB.callerSound then return end
    if not Readable(UnitCanAttack("player", tunit)) or Readable(UnitIsDead(tunit)) then return end
    if Readable(UnitIsUnit("target", tunit)) then return end
    if GetTime() - lastPing < PING_GAP then return end
    lastPing = GetTime()
    PlaySound(PING_SOUND, "Master")
end

-- Macro ------------------------------------------------------------------------
local function MakeMacro()
    if InCombat() then Print("Det kan ikke lade sig gøre i kamp.") return end
    if not CreateMacro or not GetMacroIndexByName then
        Print("Lav selv en makro med teksten: /click " .. BUTTON)
        return
    end
    local body = "/click " .. BUTTON
    local index = GetMacroIndexByName(MACRO_NAME)
    if not index or index == 0 then
        local ok, result = pcall(CreateMacro, MACRO_NAME, 134400, body, true)
        index = ok and result or nil
    end
    if not index or index == 0 then
        Print("Kunne ikke lave makroen (er der plads?). Lav selv en med teksten: /click " .. BUTTON)
        return
    end
    if PickupMacro then PickupMacro(index) end
    Print("Makroen |cffffcc00" .. MACRO_NAME .. "|r sidder på musen - slip den på en action bar.")
end

-- Commands (called from /gnist leder and /gnist makro in Gnistify.lua) -------
function ns.CallerCommand(arg)
    arg = arg and arg:match("^%s*(.-)%s*$") or ""
    local lower = arg:lower()
    if lower == "" then
        local tname = Readable(UnitExists("target")) and FullName("target")
        if tname and FindUnit(tname) then
            SetCaller(tname, true)
        else
            ns.OpenCallerWindow()
        end
    elseif lower == "mig" or lower == "me" then
        SetCaller(Me(), true)
    elseif lower == "ingen" or lower == "fra" or lower == "none" then
        SetCaller(nil, true)
    else
        -- A name: "Torden", "Torden Tim" or "Torden-Tim"
        local want = (Short(arg) or arg):lower()
        for _, unit in ipairs(GroupUnits()) do
            local name = Readable(UnitExists(unit)) and FullName(unit)
            if name and (name:lower() == want or name:lower():match("^(%S+)") == want) then
                SetCaller(name, true)
                return
            end
        end
        Print("Fandt ingen ved navn \"" .. arg .. "\" i din gruppe.")
    end
end

function ns.OpenCallerWindow()
    if #GroupUnits() == 0 then
        Print("Du er ikke i en gruppe. Leder-vinduet kan kun bruges i en gruppe.")
        return
    end
    forceShow, dismissed = true, false
    UpdateWindow()
end

ns.MakeCallerMacro, ns.RefreshCaller = MakeMacro, function() UpdateWindow() end

-- Events -----------------------------------------------------------------------
local lastBroadcast = 0
local ev = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "UNIT_TARGET",
    "PLAYER_TARGET_CHANGED", "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD",
}) do
    pcall(ev.RegisterEvent, ev, event)
end

ev:SetScript("OnEvent", function(_, event, ...)
    if not GnistifyDB then return end
    if event == "PLAYER_LOGIN" then
        RestorePosition()
        ApplyButton()
        UpdateWindow()

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if event == "PLAYER_ENTERING_WORLD" then dismissed = false end
        ApplyButton()
        if #GroupUnits() == 0 then forceShow = false end
        UpdateWindow()
        -- The caller tells newcomers who leads (throttled).
        local name = GnistifyDB.callerName
        if name and name == Me() and #GroupUnits() > 0
           and GetTime() - lastBroadcast > REBROADCAST_GAP then
            lastBroadcast = GetTime()
            if C_Timer then C_Timer.After(2, function() Share(GnistifyDB.callerName) end) end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if not positioned then RestorePosition() end
        if pending then ApplyButton() end
        UpdateWindow()

    elseif event == "UNIT_TARGET" then
        local unit = ...
        if unit and unit == FindUnit(GnistifyDB.callerName) then
            CallerTargetChanged()
            UpdateWindow()
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateWindow()

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        prefix, msg = Readable(prefix), Readable(msg)
        if prefix ~= PREFIX or type(msg) ~= "string" then return end
        local name = msg:match("^LEDER;(.*)$")
        if not name then return end
        local by = Short(sender)
        if not by or by == Me() or not FindUnit(by) then return end   -- own echo / not my group
        if not GnistifyDB.callerFollow then return end
        if name == "" then name = nil end
        if name == GnistifyDB.callerName then return end
        SetCaller(name, false, by)
    end
end)
