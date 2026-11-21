-- Gnistify PvP-tavle: a world PvP leaderboard for Gnisterne.
--
-- Every killing blow on an enemy player OUTSIDE battlegrounds and arenas counts.
-- The board ranks guild members by kills today, this week (from Monday), this
-- month and of all time. #1 in each gets a title (an honour):
--   I dag: Dagens Gnistsprutter    Uge: Ugens Brandfakkel
--   Måned: Månedens Bålkonge       Altid: Gnistkejseren (#2 Gnistprinsen, #3 Gnistridderen)
--
-- Every client keeps a copy of everybody's record in GnistifyDB.pvpBoard:
--   [name] = { total = N, days = { [dayNumber] = kills } }
-- Each player is the source of their own record; total only ever goes up, so it
-- works as a version number: a record with a higher total always wins.
--
-- Sync (all on the GnistDing prefix, to GUILD; older versions ignore it):
--   LB;name;total;start;c1,c2,...;live
--       A record. start is the day number of the first count; the counts run
--       up to the sender's today (empty = 0). live = 1 when sent right after
--       the kill, which is when new title holders are announced.
--   LBREQ
--       Sent a little after login. Everyone online (and the newcomer) then
--       queues every record they know. A queued record is dropped when someone
--       else sends the same or a newer one first, and anyone hearing an older
--       record than their own queues theirs as a correction. That way records
--       of players who are offline still travel from friend to friend.

local ns = select(2, ...)
local PREFIX = ns.PREFIX
local Readable = ns.Readable

local GNIST_ICON = "|TInterface\\AddOns\\Gnistify\\emojis\\gnist:0|t"
local KEEP_DAYS = 40      -- day counts older than this are thrown away (total stays)
local SEND_GAP = 1.1      -- seconds between queued records (the game throttles addon messages)
local ROWS = 5            -- names shown per list

local PERIODS = {
    { key = "today", label = "I dag",       titles = { "Dagens Gnistsprutter" } },
    { key = "week",  label = "Denne uge",   titles = { "Ugens Brandfakkel" } },
    { key = "month", label = "Denne måned", titles = { "Månedens Bålkonge" } },
    { key = "all",   label = "Nogensinde",  titles = { "Gnistkejseren", "Gnistprinsen", "Gnistridderen" } },
}
-- Shown when a kill makes someone the new (sole) #1. {name}, {titles}
local CROWN_MSGS = {
    "Kronen skifter hoved: {name} er nu {titles}!",
    "Bøj jer i støvet! {name} er nu {titles}!",
    "{name} har gnistret sig til titlen {titles}!",
    "Ny gnist på tronen: {name} er nu {titles}!",
    "Hils på {titles}: {name}! Længe leve gnisten!",
}
local MEDALS = { "ffd700", "c0c0c0", "cd7f32" }

-- Days ---------------------------------------------------------------------

-- A whole number per calendar day (local time). Noon, so daylight saving
-- can't push it over a day boundary.
local function DayNum(t)
    local d = date("*t", t)
    return math.floor(time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / 86400)
end

-- today, first day of this week (Monday), first day of this month
local function Ranges()
    local t = date("*t")
    local today = DayNum()
    return today, today - (t.wday + 5) % 7, today - (t.day - 1)
end

-- Board --------------------------------------------------------------------

local function Board()
    GnistifyDB.pvpBoard = GnistifyDB.pvpBoard or {}
    return GnistifyDB.pvpBoard
end

local function Count(rec, key, today, weekStart, monthStart)
    if key == "all" then return rec.total or 0 end
    local from = key == "today" and today or key == "week" and weekStart or monthStart
    local n = 0
    for d, c in pairs(rec.days or {}) do
        if d >= from and d <= today then n = n + c end
    end
    return n
end

-- { { name, n }, ... } best first, only players with kills in that period
local function Ranked(key)
    local today, ws, ms = Ranges()
    local list = {}
    for name, rec in pairs(Board()) do
        local n = Count(rec, key, today, ws, ms)
        if n > 0 then list[#list + 1] = { name = name, n = n } end
    end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    return list
end

-- Rank with ties: 1 + the number of players with strictly more kills
local function RankOf(list, i)
    local r = i
    while r > 1 and list[r - 1].n == list[i].n do r = r - 1 end
    return r
end

-- The title a name holds in one period, or nil
local function PeriodTitle(p, name, list)
    list = list or Ranked(p.key)
    for i, e in ipairs(list) do
        if e.name == name then return p.titles[RankOf(list, i)] end
    end
end

-- The best title a guild member holds right now (for the kill lines), or nil.
-- The all-time titles (top 3) beat month, week and today.
function ns.LeaderTitle(name)
    if not GnistifyDB or not GnistifyDB.pvpBoard or not name then return nil end
    return PeriodTitle(PERIODS[4], name) or PeriodTitle(PERIODS[3], name)
        or PeriodTitle(PERIODS[2], name) or PeriodTitle(PERIODS[1], name)
end

-- Who is alone at the top of each period
local function SoleLeaders()
    local tops = {}
    for _, p in ipairs(PERIODS) do
        local list = Ranked(p.key)
        if list[1] and (not list[2] or list[2].n < list[1].n) then tops[p.key] = list[1].name end
    end
    return tops
end

-- "a", "a og b", "a, b og c"
local function JoinWords(words)
    if #words <= 1 then return words[1] or "" end
    return table.concat(words, ", ", 1, #words - 1) .. " og " .. words[#words]
end

-- After a live kill: announce titles the killer has just taken
local function AnnounceCrowns(name, before)
    if not GnistifyDB.kills then return end
    local after, won = SoleLeaders(), {}
    for _, p in ipairs(PERIODS) do
        if after[p.key] == name and before[p.key] ~= name then
            won[#won + 1] = "|cffffcc00" .. p.titles[1] .. "|r"
        end
    end
    if #won == 0 then return end
    local text = ns.Fill(ns.Pick(CROWN_MSGS), { name = "|cffff6600" .. name .. "|r", titles = JoinWords(won) })
    DEFAULT_CHAT_FRAME:AddMessage(GNIST_ICON .. " " .. text)
    -- A new emperor deserves the big letters too
    if after.all == name and before.all ~= name and GnistifyDB.killBanner
       and RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame,
            GNIST_ICON .. " " .. ns.Fill("{name} er den nye Gnistkejser!", { name = name }),
            ChatTypeInfo["GUILD"])
    end
end

local function Prune()
    local oldest = DayNum() - KEEP_DAYS
    for _, rec in pairs(Board()) do
        rec.days = rec.days or {}
        for d in pairs(rec.days) do
            if d < oldest then rec.days[d] = nil end
        end
    end
end

-- Window (defined further down) ---------------------------------------------
local Refresh

-- Sending ------------------------------------------------------------------

local function Encode(name)
    local rec = Board()[name]
    if not rec then return nil end
    local today, ws, ms = Ranges()
    local start = math.min(ws, ms)
    local counts = {}
    for d = start, today do
        local c = rec.days and rec.days[d]
        counts[#counts + 1] = (c and c > 0) and tostring(c) or ""
    end
    return table.concat({ "LB", name, rec.total or 0, start, table.concat(counts, ",") }, ";")
end

local function SendRecord(name, live)
    if not IsInGuild() then return end
    -- Turned off sharing my kills: don't spread my own record either
    if name == ns.Me() and not GnistifyDB.killsSend then return end
    local msg = Encode(name)
    if msg then ns.SendAddon(msg .. ";" .. (live and "1" or "0")) end
end

local queue, queued, sending = {}, {}, false

local function SendNext()
    while #queue > 0 do
        local name = table.remove(queue, 1)
        if queued[name] then
            queued[name] = nil
            SendRecord(name, false)
            C_Timer.After(SEND_GAP, SendNext)
            return
        end
    end
    sending = false
end

-- Send a record soon. The random wait gives someone else the chance to send
-- it first, so not everyone online sends the same thing.
local function Queue(name)
    if queued[name] or not C_Timer then return end
    queued[name] = true
    queue[#queue + 1] = name
    if not sending then
        sending = true
        C_Timer.After(1 + math.random() * 4, SendNext)
    end
end

local function QueueAll()
    for name in pairs(Board()) do Queue(name) end
end

-- Receiving ----------------------------------------------------------------

local function Receive(msg)
    local _, name, total, start, counts, live = strsplit(";", msg)
    total, start = tonumber(total), tonumber(start)
    if type(name) ~= "string" or name == "" or not total or not start or total < 0 then return end
    local board = Board()
    local rec = board[name]
    local have = rec and rec.total or -1
    if have >= total then
        if have > total then
            Queue(name)           -- they have an older record: send ours
        else
            queued[name] = nil    -- someone else already sent the same one
        end
        return
    end
    local before = live == "1" and SoleLeaders()
    local days, i = {}, 0
    for c in ((counts or "") .. ","):gmatch("([^,]*),") do
        local n = tonumber(c)
        if n and n > 0 then days[start + i] = n end
        i = i + 1
        if i > 62 then break end
    end
    board[name] = { total = total, days = days }
    queued[name] = nil
    if before then AnnounceCrowns(name, before) end
    if Refresh then Refresh() end
end

-- A kill of mine (called by Kills.lua after the kill line is shown) ----------

function ns.LeaderboardKill()
    local _, instanceType = IsInInstance()
    instanceType = Readable(instanceType)
    if instanceType == "pvp" or instanceType == "arena" then return end   -- world PvP only
    local me = ns.Me()
    if not me then return end
    local board = Board()
    local before = SoleLeaders()
    local rec = board[me] or { total = 0, days = {} }
    board[me] = rec
    rec.days = rec.days or {}
    local today = DayNum()
    rec.total = (rec.total or 0) + 1
    rec.days[today] = (rec.days[today] or 0) + 1
    AnnounceCrowns(me, before)
    queued[me] = nil
    SendRecord(me, true)
    if Refresh then Refresh() end
end

-- Window -------------------------------------------------------------------

local CELL_W, CELL_H = 260, 150
local win = CreateFrame("Frame", "GnistifyPvPFrame", UIParent, "BasicFrameTemplateWithInset")
win:SetSize(CELL_W * 2 + 30, CELL_H * 2 + 70)
win:SetPoint("CENTER")
win:SetFrameStrata("DIALOG")
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:SetClampedToScreen(true)
win:Hide()
tinsert(UISpecialFrames, "GnistifyPvPFrame")   -- Esc closes it

local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOP", 0, -5)
title:SetText(GNIST_ICON .. " |cffffcc00Gnisternes|r |cffff6600PvP-tavle|r")

local footer = win:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
footer:SetPoint("BOTTOM", 0, 12)
footer:SetText("Kun killing blows i world PvP tæller (ikke BG og arena).")

local cells = {}
for i, p in ipairs(PERIODS) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local x, y = 16 + col * CELL_W, -32 - row * CELL_H
    local c = { period = p, rows = {} }
    c.header = win:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    c.header:SetPoint("TOPLEFT", x, y)
    c.header:SetText(p.label)
    c.sub = win:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    c.sub:SetPoint("TOPLEFT", x, y - 16)
    c.sub:SetText("Titel: " .. p.titles[1])
    for r = 1, ROWS do
        local ry = y - 34 - (r - 1) * 16
        local name = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        name:SetPoint("TOPLEFT", x + 4, ry)
        name:SetWidth(CELL_W - 50)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        local n = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        n:SetPoint("TOPRIGHT", win, "TOPLEFT", x + CELL_W - 14, ry)
        n:SetJustifyH("RIGHT")
        c.rows[r] = { name = name, n = n }
    end
    c.me = win:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    c.me:SetPoint("TOPLEFT", x + 4, y - 36 - ROWS * 16)
    cells[i] = c
end

Refresh = function()
    if not win:IsShown() then return end
    local me = ns.Me()
    for _, c in ipairs(cells) do
        local list = Ranked(c.period.key)
        local myRank
        for i, e in ipairs(list) do
            if e.name == me then myRank = RankOf(list, i) end
        end
        for r, row in ipairs(c.rows) do
            local e = list[r]
            if e then
                local rank = RankOf(list, r)
                local color = e.name == me and "ff6600" or "ffffff"
                local t = c.period.titles[rank]
                row.name:SetText(("|cff%s%d.|r |cff%s%s|r%s"):format(MEDALS[rank] or "aaaaaa", rank,
                    color, ns.Alias(e.name), t and (" |cffffcc00(" .. t .. ")|r") or ""))
                row.n:SetText(e.n)
            elseif r == 1 then
                row.name:SetText("|cffaaaaaaIngen drab endnu. Gnisten venter...|r")
                row.n:SetText("")
            else
                row.name:SetText("")
                row.n:SetText("")
            end
        end
        if myRank and myRank > ROWS then
            local mine = 0
            for _, e in ipairs(list) do if e.name == me then mine = e.n end end
            c.me:SetText(("Dig: nr. %d med %d drab"):format(myRank, mine))
        else
            c.me:SetText("")
        end
    end
end

win:SetScript("OnShow", Refresh)
-- Keep "today" right across midnight while the window is open
local elapsed = 0
win:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed > 30 then elapsed = 0; Refresh() end
end)

function ns.ToggleLeaderboard()
    if win:IsShown() then win:Hide() else win:Show() end
end

-- Events -------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON" }) do
    pcall(f.RegisterEvent, f, event)   -- an unknown event must not break the rest
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        Prune()
        -- Guild info isn't there right at login; ask for the board a bit later
        if C_Timer then
            C_Timer.After(15, function()
                if not IsInGuild() then return end
                ns.SendAddon("LBREQ")
                QueueAll()
            end)
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        prefix, msg, channel = Readable(prefix), Readable(msg), Readable(channel)
        if prefix ~= PREFIX or channel ~= "GUILD" or type(msg) ~= "string" then return end
        if not msg:find("^LB") then return end
        if ns.Short(sender) == ns.Me() then return end   -- my own echo
        if msg == "LBREQ" then
            QueueAll()
        elseif msg:find("^LB;") then
            Receive(msg)
        end
    end
end)
