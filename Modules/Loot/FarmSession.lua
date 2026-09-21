--- @module loot.farmSession
--- Purpose: track what the current farming session is earning and show it on a small HUD.
--- Requires: UnitGUID, GetMoney, GetTime,
---     C_Item.GetItemQualityByID, C_Item.GetItemIconByID, C_Item.GetItemQualityColor,
---     C_CurrencyInfo.GetCoinTextureString
--- Events: CHAT_MSG_LOOT, LOOT_OPENED; PLAYER_MONEY, LOOT_CLOSED (contextual)
--- Hot: no, loot arrives at human speed and the clock is a one second timer, not OnUpdate
local _, R = ...
local L = R.L

local Farm = R:RegisterModule({
    id = "loot.farmSession", category = "Loot", nameKey = "FARM_SESSION_NAME",
    descriptionKey = "FARM_SESSION_DESC", detailKey = "FARM_SESSION_DETAIL",
    requires = { "UnitGUID", "GetMoney", "GetTime",
        "C_Item.GetItemQualityByID", "C_Item.GetItemIconByID", "C_Item.GetItemQualityColor",
        "C_CurrencyInfo.GetCoinTextureString" },
    -- PRD 7.2 puts the session log and gold per hour outside every preset: a number that
    -- watches you play is something you ask for, not something you find switched on.
    risk = "safe", defaultEnabled = false,
})

local SECONDS_PER_HOUR, SECONDS_PER_MINUTE = 3600, 60
local COPPER_PER_GOLD = 10000
local TICK = 1
local MONEY_GRACE = 0.5
local COIN_FONT_HEIGHT = 12
-- Real item ids, so /refactor farmtest shows real icons and real quality colours. The names
-- are in the locale file, because nothing in the client can be asked for them offline.
local TEST_ITEMS = {
    { id = 2589, nameKey = "FARM_TEST_1", count = 24, unit = 260 },
    { id = 2770, nameKey = "FARM_TEST_2", count = 40, unit = 390 },
    { id = 4306, nameKey = "FARM_TEST_3", count = 12, unit = 1450 },
    { id = 1210, nameKey = "FARM_TEST_4", count = 3, unit = 8800 },
    { id = 12361, nameKey = "FARM_TEST_5", count = 1, unit = 214000 },
}
local TEST_GOLD, TEST_MOBS, TEST_SECONDS = 312700, 148, 4320

-- The client's own coin icons, and no denomination that is zero. Display only: the copy
-- block uses PlainMoney, because a texture escape pasted into a forum is noise.
local function coinText(amount)
    local coins = C_CurrencyInfo.GetCoinTextureString(amount, COIN_FONT_HEIGHT)
    if type(coins) == "string" and coins ~= "" then
        return coins
    end
    return string.format(L.MONEY_TEXT, math.floor(amount / COPPER_PER_GOLD),
        math.floor(amount / 100) % 100, amount % 100)
end

local function plainMoney(amount)
    return string.format(L.MONEY_TEXT, math.floor(amount / COPPER_PER_GOLD),
        math.floor(amount / 100) % 100, amount % 100)
end

-- Whole gold, for the two lines that have to stay short enough to read at a glance.
local function goldText(amount)
    return string.format(L.FARM_GOLD_SHORT, math.floor(amount / COPPER_PER_GOLD))
end

local function durationText(seconds)
    seconds = math.floor(seconds)
    local hours = math.floor(seconds / SECONDS_PER_HOUR)
    local minutes = math.floor(seconds % SECONDS_PER_HOUR / SECONDS_PER_MINUTE)
    if hours > 0 then
        return string.format(L.FARM_DURATION_HM, hours, minutes)
    end
    if minutes > 0 then
        return string.format(L.FARM_DURATION_MS, minutes, seconds % SECONDS_PER_MINUTE)
    end
    return string.format(L.FARM_DURATION_S, seconds)
end

-- Locale independent: the link and the trailing "x3" are the same in every language, and
-- the global loot strings are not in Blizzard's interface source, so they are never matched.
local function parseLoot(text)
    if type(text) ~= "string" then
        return nil
    end
    local link = text:match("(|c[^|]*|Hitem:[^|]+|h%[[^%]]*%]|h|r)")
    if not link then
        return nil
    end
    return link, tonumber(link:match("|Hitem:(%d+)")), link:match("%[(.-)%]"),
        tonumber(text:match("|h|rx(%d+)", 1) or "") or 1
end

function Farm:NewSession()
    self.session = {
        startedAt = nil, activeSince = nil, activeSeconds = 0,
        pausedSince = nil, pausedSeconds = 0, manualPause = false,
        mobs = 0, itemCount = 0, itemValue = 0, gold = 0,
        items = {}, order = {}, sorted = {}, sortedDirty = true,
        bestName = nil, bestValue = 0, source = nil, sourceChanged = false,
    }
    return self.session
end

function Farm:Elapsed()
    local session = self.session
    if not session.startedAt then
        return 0
    end
    if session.activeSince then
        return session.activeSeconds + (GetTime() - session.activeSince)
    end
    return session.activeSeconds
end

function Farm:PausedSeconds()
    local session = self.session
    if session.pausedSince then
        return session.pausedSeconds + (GetTime() - session.pausedSince)
    end
    return session.pausedSeconds
end

function Farm:IsRunning()
    return self.session.startedAt ~= nil and self.session.activeSince ~= nil
end

function Farm:IsPaused()
    return self.session.startedAt ~= nil and self.session.activeSince == nil
end

function Farm:IdleSeconds()
    local seconds = R.Settings:GetOption("farmIdleSeconds")
    return type(seconds) == "number" and seconds or 180
end

function Farm:CancelIdle()
    if self.idle then
        self.idle:Cancel()
        self.idle = nil
    end
end

function Farm:ScheduleIdle()
    self:CancelIdle()
    if self:IsRunning() then
        self.idle = R:After(self, self:IdleSeconds(), self.OnIdle)
    end
end

-- Nothing looted for the whole window, so the clock stops. The next loot starts it again
-- without being asked, which is what makes the rate mean gold per hour of farming.
function Farm:OnIdle()
    self.idle = nil
    self:Pause(false)
end

function Farm:ScheduleTick()
    if self.ticker or not self:IsRunning() or not self.host or not self.host:IsShown() then
        return
    end
    self.ticker = R:After(self, TICK, self.OnTick)
end

function Farm:OnTick()
    self.ticker = nil
    self:Refresh()
    self:ScheduleTick()
end

function Farm:Start()
    local session = self.session
    if session.startedAt then
        return
    end
    session.startedAt = GetTime()
    session.activeSince = session.startedAt
    self:ScheduleIdle()
    self:ScheduleTick()
end

function Farm:Pause(manual)
    local session = self.session
    if manual then
        session.manualPause = true
    end
    if session.activeSince then
        session.activeSeconds = session.activeSeconds + (GetTime() - session.activeSince)
        session.activeSince = nil
        session.pausedSince = GetTime()
    end
    self:CancelIdle()
    self:Refresh()
end

function Farm:Resume(manual)
    local session = self.session
    if manual then
        session.manualPause = false
    end
    -- A manual pause is a decision and outlives any amount of looting; only the pause the
    -- idle timer made comes back on its own.
    if session.manualPause or not session.startedAt then
        return
    end
    if not session.activeSince then
        if session.pausedSince then
            session.pausedSeconds = session.pausedSeconds + (GetTime() - session.pausedSince)
            session.pausedSince = nil
        end
        session.activeSince = GetTime()
    end
    self:ScheduleIdle()
    self:ScheduleTick()
    self:Refresh()
end

function Farm:ToggleManualPause()
    if self.session.manualPause then
        self:Resume(true)
    else
        self:Pause(true)
    end
end

function Farm:Reset()
    R:CancelTimers(self)
    self.ticker, self.idle = nil, nil
    self:NewSession()
    self:Refresh()
end

-- fallbackUnit is what /refactor farmtest uses: an item the client has not cached yet has
-- no vendor price, and a demonstration with every number at zero shows nothing.
function Farm:RecordItem(link, itemID, name, count, fallbackUnit)
    local session = self.session
    local unit, source = R.Prices.Get(link, 1)
    unit = unit or fallbackUnit or 0
    if source then
        if not session.source then
            session.source = source
        elseif session.source ~= source then
            session.sourceChanged = true
        end
    end
    local entry = session.items[link]
    if not entry then
        local quality = C_Item.GetItemQualityByID(itemID) or 1
        local r, g, b = C_Item.GetItemQualityColor(quality)
        entry = { link = link, name = name or link, icon = C_Item.GetItemIconByID(itemID),
            count = 0, value = 0, unit = unit, r = r, g = g, b = b }
        session.items[link] = entry
        session.order[#session.order + 1] = entry
    end
    entry.unit = unit > 0 and unit or entry.unit
    entry.count = entry.count + count
    session.itemValue = session.itemValue - entry.value
    entry.value = entry.unit * entry.count
    session.itemValue = session.itemValue + entry.value
    session.itemCount = session.itemCount + count
    session.sortedDirty = true
    local dropValue = entry.unit * count
    if dropValue > session.bestValue then
        session.bestValue, session.bestName = dropValue, entry.name
    end
end

-- Sorting every second would be work nobody asked for, so the order is rebuilt only after
-- something changed it. That flag is the named invalidation; there is no timer here.
function Farm:Sorted()
    local session = self.session
    if not session.sortedDirty then
        return session.sorted
    end
    local sorted = session.sorted
    for index = #sorted, 1, -1 do
        sorted[index] = nil
    end
    for index, entry in ipairs(session.order) do
        sorted[index] = entry
    end
    table.sort(sorted, function(a, b)
        if a.value == b.value then
            return a.name < b.name
        end
        return a.value > b.value
    end)
    session.sortedDirty = false
    return sorted
end

function Farm:Total()
    return self.session.gold + self.session.itemValue
end

function Farm:PerHour(amount)
    local elapsed = self:Elapsed()
    if elapsed < 1 then
        return 0
    end
    return amount * SECONDS_PER_HOUR / elapsed
end

function Farm:SourceName()
    return self.session.source or R.Prices.CurrentSource()
end

-- Copper per hour, or nil when no goal is set, which is what hides the meter.
function Farm:GoalProgress()
    local goal = R.Settings:GetOption("farmGoalGold")
    if type(goal) ~= "number" or goal <= 0 then
        return nil
    end
    return self:PerHour(self:Total()) / (goal * COPPER_PER_GOLD)
end

function Farm:Refresh()
    local host = self.host
    if not host or not host:IsShown() then
        return
    end
    local session = self.session
    local stats = self.stats
    stats.rate = string.format(L.FARM_RATE, goldText(self:PerHour(self:Total())))
    stats.sub = string.format(L.FARM_SUB, durationText(self:Elapsed()),
        goldText(self:Total()), self:SourceName())
    stats.progress = self:GoalProgress()
    stats.paused = self:IsPaused()
    stats.tipTitle = L.FARM_TIP_RATE_TITLE
    stats.tip = stats.paused and self.tipPaused or self.tipRunning
    -- One fact per row, each under the icon that means it. Paused time and bag space are
    -- not part of what the session earned, so neither is on the HUD; paused time is still
    -- in the summary, where it explains the rate.
    local lines = stats.lines
    lines[1] = string.format(L.FARM_LINE_CLOCK, durationText(self:Elapsed()))
    lines[2] = string.format(L.FARM_LINE_RATES, math.floor(self:PerHour(session.itemCount)),
        math.floor(self:PerHour(session.mobs)))
    lines[3] = string.format(L.FARM_LINE_GOLD, coinText(session.gold))
    lines[4] = string.format(L.FARM_LINE_ITEMS, coinText(session.itemValue))
    stats.best = session.bestName and string.format(L.FARM_LINE_BEST, session.bestName,
        coinText(session.bestValue)) or L.FARM_LINE_NO_BEST
    -- The row tables are kept and refilled, so a HUD that refreshes every second while you
    -- farm for an hour allocates five tables in total, not eighteen thousand.
    local sorted, top = self:Sorted(), stats.top
    for index = 1, R.UI.farmHudTopRows do
        local entry = sorted[index]
        if entry then
            local row = self.topRows[index]
            if not row then
                row = {}
                self.topRows[index] = row
            end
            row.icon, row.r, row.g, row.b = entry.icon, entry.r, entry.g, entry.b
            row.name = entry.count > 1 and string.format(L.FARM_TOP_COUNT, entry.name, entry.count)
                or entry.name
            row.value = coinText(entry.value)
            top[index] = row
        else
            top[index] = nil
        end
    end
    host:SetStats(stats)
end

-- Plain text, no textures and no colour codes: it is meant to be pasted somewhere else.
function Farm:ReportText(report)
    local parts = { L.FARM_SUMMARY_TITLE }
    for _, line in ipairs(report.lines) do
        parts[#parts + 1] = line
    end
    parts[#parts + 1] = ""
    parts[#parts + 1] = L.FARM_SUMMARY_ITEMS
    for _, entry in ipairs(self:Sorted()) do
        parts[#parts + 1] = string.format(L.FARM_REPORT_ROW, entry.count, entry.name,
            plainMoney(entry.value))
    end
    return table.concat(parts, "\n")
end

function Farm:BuildReport()
    local session = self.session
    local lines = {
        string.format(L.FARM_REPORT_DURATION, durationText(self:Elapsed()),
            durationText(self:PausedSeconds())),
        string.format(L.FARM_REPORT_RATE, plainMoney(self:PerHour(self:Total()))),
        string.format(L.FARM_REPORT_TOTAL, plainMoney(self:Total())),
        string.format(L.FARM_REPORT_SPLIT, plainMoney(session.gold), plainMoney(session.itemValue)),
        string.format(L.FARM_REPORT_MOBS, session.mobs, session.itemCount),
        string.format(L.FARM_REPORT_SOURCE, self:SourceName()),
    }
    -- The session is never thrown away because the chain moved under it; the report simply
    -- says so, and the earlier numbers stay exactly as they were recorded.
    if session.sourceChanged then
        lines[#lines + 1] = string.format(L.FARM_REPORT_SOURCE_CHANGED, R.Prices.CurrentSource())
    end
    local rows = {}
    for index, entry in ipairs(self:Sorted()) do
        rows[index] = { count = entry.count, name = entry.name, value = coinText(entry.value),
            r = entry.r, g = entry.g, b = entry.b }
    end
    local report = { lines = lines, rows = rows }
    report.text = self:ReportText(report)
    return report
end

function Farm:OpenSummary()
    R.UI:ShowSessionSummary(function() return self:BuildReport() end)
end

-- Hiding it is not the same as switching it off, so say where it went. One line, on an
-- action the player just took: that is not debug output.
function Farm:HideHud()
    R.Settings:SetOption("farmShowHud", false)
    R:Print(L.FARM_HIDDEN)
end

-- Both the settings icon and the menu's "Set goal" land on the same page: the goal, the
-- opacity and the idle timeout are three fields in one section, not three dialogs.
function Farm:OpenSettings()
    if R.UI and R.UI.OpenModule then
        R.UI:OpenModule("loot.farmSession")
    end
end

function Farm:OnLoot(_, text, _, _, _, _, _, _, _, _, _, _, guid)
    if guid ~= self.playerGUID then
        return
    end
    local link, itemID, name, count = parseLoot(text)
    if not link or not itemID then
        return
    end
    self:Start()
    self:Resume(false)
    self:RecordItem(link, itemID, name, count)
    self:ScheduleIdle()
    self:Refresh()
end

-- One loot window is one corpse or one node. The combat log is the only thing that can say
-- "killed", and on this build it is secure: C_CombatLogSecure is Blizzard's own namespace
-- and C_CombatLog.GetCurrentEventInfo is gone, so this counts what it can actually see.
function Farm:OnLootOpened()
    self.session.mobs = self.session.mobs + 1
    self:Start()
    self:Resume(false)
    self.money = GetMoney()
    self.grouping = true
    R.Broker:Subscribe("PLAYER_MONEY", self.OnMoney, self)
    R.Broker:Subscribe("LOOT_CLOSED", self.OnLootClosed, self)
    self:ScheduleIdle()
    self:Refresh()
end

function Farm:OnLootClosed()
    R:After(self, MONEY_GRACE, self.StopMoney)
end

function Farm:StopMoney()
    R.Broker:Unsubscribe("PLAYER_MONEY", self)
    R.Broker:Unsubscribe("LOOT_CLOSED", self)
    self.grouping = nil
end

-- Money is watched only around a loot window, so a vendor sale or a mail collection never
-- lands in the session as farmed gold.
function Farm:OnMoney()
    local money = GetMoney()
    local delta = money - (self.money or money)
    self.money = money
    if delta <= 0 then
        return
    end
    self.session.gold = self.session.gold + delta
    self:Refresh()
end

-- The HUD's own options, the price chain it values loot with, or a change with no key (a
-- profile). Anything else is some other feature's slider mid-drag.
local PRICE_OPTIONS = { priceSource = true, priceTSM = true, priceAuctionator = true, tsmPriceString = true }

function Farm:OnSettingsChanged(_, key)
    if key ~= nil and string.sub(key, 1, 4) ~= "farm" and not PRICE_OPTIONS[key] then
        return
    end
    if self.host then
        self.host:ApplySettings()
    end
    self:ScheduleTick()
    self:Refresh()
end

-- /refactor farmtest. A whole fake session through the real recording path, so what shows
-- on screen is what a real hour of farming would have produced.
function Farm:Test()
    self:Reset()
    local session = self.session
    session.startedAt = GetTime()
    session.activeSeconds = TEST_SECONDS
    session.activeSince = GetTime()
    session.mobs = TEST_MOBS
    session.gold = TEST_GOLD
    for _, item in ipairs(TEST_ITEMS) do
        local link = string.format(L.FARM_TEST_LINK, item.id, L[item.nameKey])
        self:RecordItem(link, item.id, L[item.nameKey], item.count, item.unit)
    end
    self:ScheduleTick()
    self:Refresh()
    local missing = {}
    for _, key in ipairs(R.UI.farmHudTextureKeys) do
        if R.Theme.missingFiles[key] then
            missing[#missing + 1] = key
        end
    end
    R:Print(string.format(L.FARM_TEST_FILLED, #TEST_ITEMS, TEST_MOBS))
    R:Print(string.format(L.FARM_TEST_SOURCE, R.Prices.CurrentSource()))
    if #missing > 0 then
        R:Print(string.format(L.FARM_TEST_MISSING, table.concat(missing, ", ")))
    else
        R:Print(L.FARM_TEST_TEXTURES)
    end
    R:Print(L.FARM_TEST_RESTART)
    if self.host:IsShown() then
        R:Print(L.FARM_TEST_HINT)
    else
        R:Print(L.FARM_TEST_HIDDEN)
    end
end

function Farm:OnEnable()
    self.playerGUID = UnitGUID("player")
    self.stats = self.stats or { lines = {}, top = {} }
    self.topRows = self.topRows or {}
    -- Built once, not once a second: the tooltip body is two fixed sentences either way.
    self.tipRunning = L.FARM_TIP_RATE .. "\n\n" .. L.FARM_TIP_SUB
    self.tipPaused = L.FARM_TIP_PAUSED .. "\n\n" .. L.FARM_TIP_SUB
    self:NewSession()
    self.host = R.UI:CreateFarmHud(self)
    self.host.onReset = function() self:Reset() end
    self.host.onTogglePause = function() self:ToggleManualPause() end
    self.host.onOpenSummary = function() self:OpenSummary() end
    self.host.onOpenSettings = function() self:OpenSettings() end
    self.host.onSetGoal = function() self:OpenSettings() end
    self.host.onHide = function() self:HideHud() end
    self.host:ApplySettings()
    self:Refresh()
    R.Broker:Subscribe("CHAT_MSG_LOOT", self.OnLoot, self)
    R.Broker:Subscribe("LOOT_OPENED", self.OnLootOpened, self)
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettingsChanged, self)
    R.Broker:Subscribe("REFACTOR_FARM_TEST", self.Test, self)
end

function Farm:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    self.ticker, self.idle, self.grouping, self.money = nil, nil, nil, nil
    -- Off means not tracking, so the session goes with it rather than resuming later with
    -- an hour of nothing in the middle of it.
    self:NewSession()
    if self.host then
        self.host.onReset, self.host.onTogglePause = nil, nil
        self.host.onOpenSummary, self.host.onOpenSettings, self.host.onSetGoal = nil, nil, nil
        self.host.onHide = nil
        self.host:CancelHold()
        self.host:Hide()
    end
end
