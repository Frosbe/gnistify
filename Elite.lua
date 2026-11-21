-- Gnistify elite dragon: the PvP-tavle's leaders get the original WoW elite
-- dragon around their portrait, on the player frame (you), the party frames and
-- the target frame. The best title decides:
--   rare-elite (winged)  : Gnistkejseren (all-time #1)
--   elite (gold)         : #1 this month
--   rare (silver)        : #1 today or this week
-- If the client has no rare-elite texture (Leatrix Plus ships its own copy,
-- so it may be missing on Forever), Gnistkejseren gets the gold one.
-- Setting: eliteFrames.
--
-- The classic textures and placement are the same as Leatrix Plus' "player
-- chain" on Forever: a 113x99 piece of the 256x128 target frame art, made for
-- a 64x64 portrait, flipped for portraits on the left side of a frame.

local ns = select(2, ...)

local TEXTURES = {
    rareelite = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
    elite     = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
    rare      = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
}
local L, R, T, B = 0.5567, 1, 0, 0.78125   -- the dragon part of the art

local dragons = {}   -- frame -> texture

-- portrait: the portrait texture; left: true when the portrait is on the left
-- of its frame (player, party), so the dragon is flipped to face that way.
local function Dragon(parent, portrait, left)
    local d = dragons[parent]
    if d then return d end
    d = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    local s = (portrait:GetWidth() or 64) / 64
    if s <= 0 then s = 1 end
    d:SetSize(113 * s, 99 * s)
    if left then
        d:SetTexCoord(R, L, T, B)
        d:SetPoint("TOPLEFT", portrait, "CENTER", -73 * s, 44 * s)
    else
        d:SetTexCoord(L, R, T, B)
        d:SetPoint("TOPRIGHT", portrait, "CENTER", 73 * s, 44 * s)
    end
    d:Hide()
    dragons[parent] = d
    return d
end

local function Show(parent, portrait, left, unit)
    if not parent or not portrait then return end
    local kind = GnistifyDB.eliteFrames and ns.Readable(UnitExists(unit))
        and ns.EliteKind and ns.EliteKind(ns.FullName(unit))
    if not kind then
        if dragons[parent] then dragons[parent]:Hide() end
        return
    end
    local d = Dragon(parent, portrait, left)
    local ok = d:SetTexture(TEXTURES[kind])
    if kind == "rareelite" and (ok == false or not d:GetTexture()) then
        d:SetTexture(TEXTURES.elite)   -- not in this client
    end
    d:Show()
end

local function PlayerFrameParts()
    local c = PlayerFrame and PlayerFrame.PlayerFrameContainer
    if c and c.PlayerPortrait then return c, c.PlayerPortrait end
    if PlayerFrame and PlayerPortrait then return PlayerFrame, PlayerPortrait end   -- older UI
end

local function TargetFrameParts()
    local c = TargetFrame and TargetFrame.TargetFrameContainer
    if c and c.Portrait then return c, c.Portrait end
    if TargetFrame and TargetFramePortrait then return TargetFrame, TargetFramePortrait end
end

-- Party frame i: the modern PartyFrame.MemberFrameN, or the older PartyMemberFrameN
local function PartyFrameParts(i)
    local f = PartyFrame and PartyFrame["MemberFrame" .. i]
    if f and f.Portrait then return f, f.Portrait, f.unit or ("party" .. i) end
    f = _G["PartyMemberFrame" .. i]
    local p = f and (f.portrait or _G["PartyMemberFrame" .. i .. "Portrait"])
    if f and p then return f, p, "party" .. i end
end

function ns.RefreshElite()
    if not GnistifyDB then return end
    local f, p = PlayerFrameParts()
    Show(f, p, true, "player")
    f, p = TargetFrameParts()
    Show(f, p, false, "target")
    for i = 1, 4 do
        local pf, pp, unit = PartyFrameParts(i)
        if pf then
            pcall(Show, pf, pp, true, unit)
        end
    end
end

local ev = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
    "PLAYER_TARGET_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, event)   -- an unknown event must not break the rest
end
ev:SetScript("OnEvent", function()
    pcall(ns.RefreshElite)
end)
-- "Today" and "this week" end at midnight, so look again now and then
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(60, function() pcall(ns.RefreshElite) end)
end
