-- Gnistify fishing: for the anglers of Gnisterne.
--
--   * Notable catches (green quality or better, rare fish, chests) are shown to
--     every Gnistify user in the guild, like PvP kills:
--       <fish> Bo halede [Old Ironjaw] op af vandet i Ironforge! (dagens fisk nr. 47)
--   * Fishing skill: every 25 points is announced, and 75/150/225/300 are
--     celebrated like a ding.
--   * Fish today: counted per character. 25, 50, 100, ... fish in a day is
--     announced, and /gnist fisk shows today's top anglers in the guild.
--   * Louder splash: while fishing, sound effects go up and music and ambience
--     go down, so the bobber is easy to hear. Restored when you stop.
--
-- Messages on the GnistDing prefix (older versions ignore them, because they
-- only match ^DING:, ^KILL; and ^LEDER;). Only ever append fields at the end.
--   FISK;count;zone;itemLink   every catch; itemLink is empty unless notable
--   FSKILL;skill               fishing skill reached a multiple of 25

local ns = select(2, ...)
local PREFIX = ns.PREFIX
local Readable = ns.Readable

local FISH_ICON = "|TInterface\\Icons\\INV_Misc_Fish_02:0|t"
-- The game's own "reel in" sound from fishing (SOUNDKIT.FISHING_REEL_IN)
local CATCH_SOUND = (SOUNDKIT and SOUNDKIT.FISHING_REEL_IN) or 3407
local DING_SOUND = 888                -- SOUNDKIT "LEVELUP"
local SPLASH_RESTORE = 10             -- seconds after the last cast before sound is restored
local SKILL_STEP = 25                 -- announce every N skill points

-- Fishing spell IDs (vanilla ranks first, later versions after)
local FISHING_SPELLS = {
    [7620] = true, [7731] = true, [7732] = true, [18248] = true,
    [33095] = true, [51294] = true, [88868] = true, [131474] = true,
}

-- Always notable, whatever the quality. English names, lower case, because
-- the item name is all we can rely on across clients. Green or better is
-- always notable too.
local NOTABLE_NAMES = {
    ["old ironjaw"] = true,
    ["old crafty"] = true,
    ["speckled tastyfish"] = true,
    ["keefer's angelfish"] = true,
    ["brownell's blue striped racer"] = true,
    ["dezian queenfish"] = true,
}
-- Fished-up chests and crates (matched anywhere in the name)
local NOTABLE_WORDS = { "chest", "trunk", "crate", "strongbox", "kiste" }

local SKILL_TITLES = {
    [75] = "udlært lærling", [150] = "svend", [225] = "ekspert", [300] = "mesterfisker",
}
-- Fish-today counts that are announced
local TALLY = { [25] = true, [50] = true, [100] = true, [150] = true, [200] = true,
    [300] = true, [400] = true, [500] = true, [750] = true, [1000] = true }

-- {fisher}, {item}, {zone}
local CATCH_MSGS = {
    "{fisher} halede {item} op af vandet i {zone}!",
    "Fiskelykke! {fisher} fangede {item} i {zone}!",
    "{fisher} fik bid: {item} fra {zone}!",
    "Gnisten bider på krogen! {fisher} fangede {item} i {zone}!",
    "Stort øjeblik ved vandkanten: {fisher} landede {item} i {zone}!",
    "Nat Pagle kan godt pakke sammen: {fisher} fangede {item} i {zone}!",
}
local CATCH_BANNERS = {
    "{fisher} fangede {item}!",
    "Fiskelykke for {fisher}: {item}!",
    "{fisher} halede {item} i land!",
}
-- {fisher}, {skill}
local SKILL_MSGS = {
    "{fisher} er nu oppe på {skill} i fiskeri!",
    "{fisher} har fisket sig op til {skill}!",
    "Snøren strammer: {fisher} har nu {skill} i fiskeri!",
}
-- {fisher}, {skill}, {title}
local MILESTONE_MSGS = {
    "Fiske-DING! {fisher} har nået {skill} i fiskeri og er nu {title}!",
    "{fisher} er nu {title} i fiskeri ({skill})! Længe leve gnisten!",
    "Hold da op! {fisher} har {skill} i fiskeri. Hils på den nye {title}!",
}
-- {fisher}, {count}
local TALLY_MSGS = {
    "{fisher} har fanget {count} fisk i dag! Gnisten er våd.",
    "{count} fisk i dag! {fisher} er ved at tømme søen.",
    "{fisher} rundede {count} fisk i dag!",
}

local function Today() return date("%Y-%m-%d") end

local function Zone()
    return Readable(GetRealZoneText()) or Readable(GetZoneText()) or "?"
end

local function SpellName(id)
    local ok, name
    if C_Spell and C_Spell.GetSpellName then
        ok, name = pcall(C_Spell.GetSpellName, id)
    elseif GetSpellInfo then
        ok, name = pcall(GetSpellInfo, id)
    end
    return ok and Readable(name) or nil
end

local fishingName   -- "Fishing" in the client's language, looked up at login

local function IsFishingSpell(spellID)
    spellID = Readable(spellID)
    if spellID and FISHING_SPELLS[spellID] then return true end
    local name = spellID and SpellName(spellID)
    return name ~= nil and name == fishingName
end

-- Today's catches per angler (me and everyone who sent FISK;), kept across
-- /reload. Wiped when the day changes.
local function Board()
    local b = GnistifyDB.fishToday
    if not b or b.day ~= Today() then
        b = { day = Today(), counts = {} }
        GnistifyDB.fishToday = b
    end
    return b.counts
end

-- Show ------------------------------------------------------------------

local function Fisher(name) return "|cffff6600" .. name .. "|r" end

local function Line(text)
    DEFAULT_CHAT_FRAME:AddMessage(FISH_ICON .. " " .. text)
end

local function Banner(text)
    if GnistifyDB.fishingBanner and RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, FISH_ICON .. " " .. text, ChatTypeInfo["GUILD"])
    end
end

local function ShowCatch(fisher, link, zone, count)
    if not GnistifyDB.fishing then return end
    local text = ns.Fill(ns.Pick(CATCH_MSGS), {
        fisher = Fisher(fisher), item = link, zone = "|cffffff00" .. zone .. "|r",
    })
    count = tonumber(count)
    if count then
        text = text .. " |cffaaaaaa(" .. (count == 1 and "dagens første fisk"
            or "dagens fisk nr. " .. count) .. ")|r"
    end
    Line(text)
    Banner(ns.Fill(ns.Pick(CATCH_BANNERS), { fisher = Fisher(fisher), item = link }))
    if GnistifyDB.fishingSound then PlaySound(CATCH_SOUND, "Master") end
end

local function ShowTally(fisher, count)
    if not GnistifyDB.fishing then return end
    Line(ns.Fill(ns.Pick(TALLY_MSGS), { fisher = Fisher(fisher), count = count },
        { count = "ffff00" }))
end

local function ShowSkill(fisher, skill)
    if not GnistifyDB.fishing then return end
    local title = SKILL_TITLES[skill]
    if title then
        local vars = { fisher = Fisher(fisher), skill = skill, title = title }
        local text = ns.Fill(ns.Pick(MILESTONE_MSGS), vars, { skill = "ffff00", title = "ffff00" })
        Line(text)
        Banner(text)
        -- The game plays no sound for a skill-up, so play the ding for everyone
        if GnistifyDB.fishingSound then PlaySound(DING_SOUND, "Master") end
    else
        Line(ns.Fill(ns.Pick(SKILL_MSGS), { fisher = Fisher(fisher), skill = skill },
            { skill = "ffff00" }))
    end
end

-- My own catches ---------------------------------------------------------

local function IsNotable(link, name, quality)
    if type(quality) == "number" and quality >= 2 then return true end
    name = type(name) == "string" and name:lower() or ""
    if NOTABLE_NAMES[name] then return true end
    for _, word in ipairs(NOTABLE_WORDS) do
        if name:find(word, 1, true) then return true end
    end
    return false
end

local function Quality(slot, link)
    local q = Readable((select(5, GetLootSlotInfo(slot))))
    if type(q) == "number" then return q end
    if link and C_Item and C_Item.GetItemQualityByID then
        local ok, iq = pcall(C_Item.GetItemQualityByID, link)
        if ok then return Readable(iq) end
    end
    if link and GetItemInfo then
        return Readable((select(3, GetItemInfo(link))))
    end
end

local lastFishing = 0   -- GetTime() when my last fishing channel ended
local counted = false   -- this loot window was already counted

local function OnFishingLoot()
    local me = ns.Me()
    if not me then return end
    local board = Board()
    local count = (board[me] or 0) + 1
    board[me] = count
    local zone = Zone()

    -- The best notable item in this catch (usually there's only one item)
    local best, bestQuality
    for slot = 1, (Readable(GetNumLootItems()) or 0) do
        local link = Readable(GetLootSlotLink(slot))
        if type(link) == "string" then
            local name = Readable((select(2, GetLootSlotInfo(slot)))) or link:match("%[(.-)%]")
            local quality = Quality(slot, link) or 1
            if IsNotable(link, name, quality) and (not best or quality > bestQuality) then
                best, bestQuality = link, quality
            end
        end
    end

    if best then ShowCatch(me, best, zone, count) end
    if TALLY[count] then ShowTally(me, count) end
    if IsInGuild() and GnistifyDB.fishingSend then
        -- ";" never appears in item links or zone names
        ns.SendAddon(table.concat({ "FISK", count, zone, best or "" }, ";"))
    end
end

-- "Your skill in %s has increased to %d." -> a Lua pattern with two captures
local SKILL_PATTERN
if type(SKILL_RANK_UP) == "string" then
    -- Escape the magic characters except "%", then turn %s and %d into captures
    SKILL_PATTERN = "^" .. SKILL_RANK_UP:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
        :gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
end

local function OnSkillMessage(msg)
    if not SKILL_PATTERN or type(msg) ~= "string" then return end
    local skillName, skill = msg:match(SKILL_PATTERN)
    skill = tonumber(skill)
    if not skill or skill % SKILL_STEP ~= 0 then return end
    if skillName ~= fishingName and not skillName:lower():find("fish") then return end
    local me = ns.Me()
    if not me then return end
    ShowSkill(me, skill)
    if IsInGuild() and GnistifyDB.fishingSend then
        ns.SendAddon("FSKILL;" .. skill)
    end
end

-- Louder splash ----------------------------------------------------------

local SPLASH_CVARS = {
    Sound_EnableSFX = "1", Sound_SFXVolume = "1.0",
    Sound_MusicVolume = "0", Sound_AmbienceVolume = "0",
}
local restoreTimer

local function RestoreSound()
    if restoreTimer then restoreTimer:Cancel(); restoreTimer = nil end
    local saved = GnistifyDB and GnistifyDB.fishingSaved
    if not saved then return end
    for cvar, value in pairs(saved) do pcall(SetCVar, cvar, value) end
    GnistifyDB.fishingSaved = nil
end

local function BoostSound()
    if restoreTimer then restoreTimer:Cancel(); restoreTimer = nil end
    if not GnistifyDB.fishingSplash or GnistifyDB.fishingSaved then return end
    local saved = {}
    for cvar in pairs(SPLASH_CVARS) do
        local value = Readable(GetCVar(cvar))
        if value == nil then return end   -- can't read it, so don't touch anything
        saved[cvar] = value
    end
    -- Saved in GnistifyDB, so a logout or crash mid-fishing is undone at login
    GnistifyDB.fishingSaved = saved
    for cvar, value in pairs(SPLASH_CVARS) do pcall(SetCVar, cvar, value) end
end

local function StopFishing()
    lastFishing = GetTime()
    if GnistifyDB.fishingSaved and C_Timer and C_Timer.NewTimer then
        if restoreTimer then restoreTimer:Cancel() end
        restoreTimer = C_Timer.NewTimer(SPLASH_RESTORE, RestoreSound)
    end
end

-- Called when a setting changes in the options window
function ns.RefreshFishing()
    if GnistifyDB and not GnistifyDB.fishingSplash then RestoreSound() end
end

-- /gnist fisk: today's top anglers
function ns.FishingCommand()
    local list = {}
    for name, n in pairs(Board()) do list[#list + 1] = { name = name, n = n } end
    if #list == 0 then
        ns.Print("Ingen har fanget noget i dag. Endnu.")
        return
    end
    table.sort(list, function(a, b) return a.n > b.n end)
    ns.Print(FISH_ICON .. " Dagens fangst:")
    for i = 1, math.min(#list, 5) do
        local e = list[i]
        local crown = i == 1 and " |cffffcc00(Dagens Gnistfisker)|r" or ""
        ns.Print(("  %d. %s - %d fisk%s"):format(i, Fisher(e.name), e.n, crown))
    end
end

-- Events -----------------------------------------------------------------

local f = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "LOOT_OPENED", "LOOT_CLOSED", "CHAT_MSG_SKILL",
    "CHAT_MSG_ADDON", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
}) do
    pcall(f.RegisterEvent, f, event)   -- an unknown event must not break the rest
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        fishingName = SpellName(7620)
        RestoreSound()   -- left over from a logout or crash while fishing

    elseif event == "PLAYER_LOGOUT" then
        RestoreSound()

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit, _, spellID = ...
        if unit == "player" and IsFishingSpell(spellID) then BoostSound() end

    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local unit, _, spellID = ...
        if unit == "player" and IsFishingSpell(spellID) then StopFishing() end

    elseif event == "LOOT_OPENED" then
        if counted then return end
        local fishing = IsFishingLoot and Readable(IsFishingLoot())
        if fishing == nil then fishing = GetTime() - lastFishing < 3 end
        if fishing then
            counted = true
            OnFishingLoot()
        end

    elseif event == "LOOT_CLOSED" then
        counted = false

    elseif event == "CHAT_MSG_SKILL" then
        OnSkillMessage(Readable((...)))

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        prefix, msg = Readable(prefix), Readable(msg)
        if prefix ~= PREFIX or type(msg) ~= "string" then return end
        local fisher = ns.Short(sender)
        if not fisher or fisher == ns.Me() then return end   -- already shown

        if msg:find("^FISK;") then
            local _, count, zone, link = strsplit(";", msg)
            count = tonumber(count)
            if not count then return end
            Board()[fisher] = count
            if link and link ~= "" then ShowCatch(fisher, link, zone or "?", count) end
            if TALLY[count] then ShowTally(fisher, count) end
        else
            local skill = tonumber(msg:match("^FSKILL;(%d+)"))
            if skill then ShowSkill(fisher, skill) end
        end
    end
end)
