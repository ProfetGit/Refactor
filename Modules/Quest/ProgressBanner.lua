--- @module quest.progressBanner
--- Purpose: show quest progress, a quest ready to hand in and a hand-in as Refactor's own banner, in
---     place of the plain yellow line Blizzard's error text prints for them.
--- Requires: UIErrorsFrame and its SetMessageTypeEnabled and GetMessagesSuppressed, GetGameMessageInfo,
---     PlaySound, C_Sound.PlayVocalErrorSound, C_QuestLog (log entries, objectives, IsComplete), and the
---     LE_GAME_ERR_QUEST_* message types with their ERR_QUEST_* format strings
--- Events: UI_INFO_MESSAGE, PLAYER_LEVEL_UP, QUEST_LOG_UPDATE (contextual: for a few seconds after an
---     objective finishes), REFACTOR_QUEST_BANNER_TEST
--- Hot: no
local _, R = ...
local Banner = R:RegisterModule({
    id = "quest.progressBanner", category = "Quest", nameKey = "QUEST_BANNER_NAME",
    descriptionKey = "QUEST_BANNER_DESC", detailKey = "QUEST_BANNER_DETAIL",
    requires = { "UIErrorsFrame", "UIErrorsFrame.SetMessageTypeEnabled", "UIErrorsFrame.GetMessagesSuppressed",
        "GetGameMessageInfo", "PlaySound", "C_Sound.PlayVocalErrorSound", "C_QuestLog.GetNumQuestLogEntries",
        "C_QuestLog.GetInfo", "C_QuestLog.GetQuestObjectives", "C_QuestLog.IsComplete",
        "C_QuestLog.GetTitleForQuestID",
        "LE_GAME_ERR_QUEST_ADD_KILL_SII", "LE_GAME_ERR_QUEST_ADD_PLAYER_KILL_SII", "LE_GAME_ERR_QUEST_ADD_ITEM_SII",
        "LE_GAME_ERR_QUEST_ADD_FOUND_SII", "LE_GAME_ERR_QUEST_OBJECTIVE_COMPLETE_S",
        "LE_GAME_ERR_QUEST_UNKNOWN_COMPLETE", "LE_GAME_ERR_QUEST_COMPLETE_S",
        "ERR_QUEST_ADD_KILL_SII", "ERR_QUEST_ADD_PLAYER_KILL_SII", "ERR_QUEST_ADD_ITEM_SII",
        "ERR_QUEST_ADD_FOUND_SII", "ERR_QUEST_OBJECTIVE_COMPLETE_S", "ERR_QUEST_UNKNOWN_COMPLETE",
        "ERR_QUEST_COMPLETE_S" },
    risk = "visible", defaultEnabled = true,
})

-- Long enough to read twice without hurrying; LEAVE covers the row's fade out.
local PROGRESS_HOLD, BANNER_HOLD, LEAVE = 4, 5.5, 1
-- The count that finishes a quest gets a moment of its own before the banner takes its place.
local READY_DELAY = 0.8
-- The log can catch up after the line that finished an objective; past this it has.
local WATCH_WINDOW, LOG_THROTTLE = 3, 0.2
-- Blizzard's level-up toast and the new-abilities strip under it are gone by about 7.2 s.
local LEVEL_UP_YIELD = 7.5
local EMPTY = {}
local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"
local TOKEN = "()%%(%d?)%$?([sd])()"
local COUNTS = "[%s:]*%%%d?%$?d%s*/%s*%%%d?%$?d[%s:]*"
local NAME = "%%%d?%$?s"
local ICONS = { monster = "kill", item = "item" }

local function escape(text)
    return (text:gsub(MAGIC, "%%%0"))
end

-- The client's own format string as a pattern, so a line reads back into its parts on any locale.
-- A positional argument (%2$d) keeps its slot.
local function compile(format)
    local pattern, slots, from = "^", {}, 1
    for start, index, kind, stop in format:gmatch(TOKEN) do
        pattern = pattern .. escape(format:sub(from, start - 1)) .. (kind == "s" and "(.-)" or "(%d+)")
        slots[#slots + 1] = { slot = tonumber(index) or #slots + 1, kind = kind }
        from = stop
    end
    return pattern .. escape(format:sub(from)) .. "$", slots
end

-- What the objective is called without its count: "%s slain: %d/%d" becomes "%s slain".
local function labelFormat(format)
    return (format:gsub(COUNTS, " "):match("^%s*(.-)%s*$"))
end

local function parse(spec, message)
    local captures = { message:match(spec.pattern) }
    if captures[1] == nil then
        return false
    end
    local ordered = {}
    for index, slot in ipairs(spec.slots) do
        ordered[slot.slot] = { kind = slot.kind, value = captures[index] }
    end
    local name, have, need
    for slot = 1, #spec.slots do
        local part = ordered[slot]
        if part and part.kind == "s" then
            name = name or part.value
        elseif part and not have then
            have = tonumber(part.value)
        elseif part then
            need = need or tonumber(part.value)
        end
    end
    return true, name, have, need
end

local function stripCount(text)
    return (text:gsub("^%d+%s*/%s*%d+%s*", ""):gsub("[%s:]*%d+%s*/%s*%d+%s*$", ""))
end

function Banner:Specs()
    local list = {
        { LE_GAME_ERR_QUEST_ADD_KILL_SII, ERR_QUEST_ADD_KILL_SII, "kill" },
        { LE_GAME_ERR_QUEST_ADD_PLAYER_KILL_SII, ERR_QUEST_ADD_PLAYER_KILL_SII, "kill" },
        { LE_GAME_ERR_QUEST_ADD_ITEM_SII, ERR_QUEST_ADD_ITEM_SII, "item" },
        { LE_GAME_ERR_QUEST_ADD_FOUND_SII, ERR_QUEST_ADD_FOUND_SII, "other" },
        { LE_GAME_ERR_QUEST_OBJECTIVE_COMPLETE_S, ERR_QUEST_OBJECTIVE_COMPLETE_S, "objective" },
        { LE_GAME_ERR_QUEST_UNKNOWN_COMPLETE, ERR_QUEST_UNKNOWN_COMPLETE, "objective" },
        { LE_GAME_ERR_QUEST_COMPLETE_S, ERR_QUEST_COMPLETE_S, "turnin" },
    }
    local specs = {}
    for _, item in ipairs(list) do
        local messageType, format, kind = item[1], item[2], item[3]
        if type(messageType) == "number" and type(format) == "string" then
            local pattern, slots = compile(format)
            specs[messageType] = { pattern = pattern, slots = slots, kind = kind, label = labelFormat(format) }
        end
    end
    return specs
end

-- The quest an objective line belongs to. Two quests can want the same item; the one asking for
-- the count the line names wins.
function Banner:FindQuest(name, need)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local fallbackID, fallbackTitle
    for index = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local info = C_QuestLog.GetInfo(index)
        local questID = type(info) == "table" and not info.isHeader and info.questID
        if type(questID) == "number" then
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or EMPTY) do
                local text = type(objective) == "table" and objective.text
                if type(text) == "string" and text:find(name, 1, true) then
                    if need == nil or objective.numRequired == need then
                        return questID, info.title
                    end
                    if not fallbackID then
                        fallbackID, fallbackTitle = questID, info.title
                    end
                end
            end
        end
    end
    return fallbackID, fallbackTitle
end

function Banner:FindByTitle(title)
    if type(title) ~= "string" or title == "" then
        return nil
    end
    for index = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local info = C_QuestLog.GetInfo(index)
        if type(info) == "table" and not info.isHeader and info.title == title and type(info.questID) == "number" then
            return info.questID, info.title
        end
    end
    return nil
end

-- Suppressing Blizzard's line also silences it, so its sound is played here exactly as
-- UIErrorsMixin:TryDisplayMessage would have (12.1.0).
function Banner:Echo(messageType)
    local _, soundKitID, voiceID = GetGameMessageInfo(messageType)
    if voiceID then
        C_Sound.PlayVocalErrorSound(voiceID)
    elseif soundKitID then
        PlaySound(soundKitID)
    end
end

function Banner:Arm(key, hold)
    local lifetimes = self.lifetimes
    if lifetimes[key] then
        lifetimes[key]:Cancel()
    end
    lifetimes[key] = R:After(self, hold, function()
        R.UI:QuestBannerLeave(self.ui, key)
        lifetimes[key] = R:After(self, LEAVE, function()
            lifetimes[key] = nil
            self.anonymous[key] = nil
            R.UI:QuestBannerDrop(self.ui, key)
        end)
    end)
end

function Banner:Present(entry, hold)
    R.UI:QuestBannerPut(self.ui, entry)
    self:Arm(entry.key, hold)
end

function Banner:Ready(questID, title)
    title = title or C_QuestLog.GetTitleForQuestID(questID)
    R:After(self, READY_DELAY, function()
        self:Present({ key = "r:" .. questID, kind = "ready", questID = questID, title = title,
            label = R.L.QUEST_BANNER_READY }, BANNER_HOLD)
        -- An "Objective Complete." that came before the count would say the same twice.
        for key in pairs(self.anonymous) do
            self:Arm(key, 0)
        end
    end)
end

-- "Objective Complete." names no objective. Right after a count or a named objective finished,
-- it only repeats that row's tick and the ready banner that follows it.
function Banner:Settle()
    if self.settleTimer then
        self.settleTimer:Cancel()
    end
    self.settleTimer = R:After(self, WATCH_WINDOW, function() self.settleTimer = nil end)
end

-- QUEST_LOG_UPDATE is held only while a finished objective may have finished its quest too.
function Banner:Watch(questID, title)
    if C_QuestLog.IsComplete(questID) then
        self.watching[questID] = nil
        return self:Ready(questID, title)
    end
    self.watching[questID] = title or false
    if self.watchTimer then
        self.watchTimer:Cancel()
    else
        R.Broker:Subscribe("QUEST_LOG_UPDATE", self.OnLogUpdate, self, LOG_THROTTLE)
    end
    self.watchTimer = R:After(self, WATCH_WINDOW, self.StopWatching)
end

function Banner:StopWatching()
    if self.watchTimer then
        self.watchTimer:Cancel()
        self.watchTimer = nil
    end
    self.watching = {}
    R.Broker:Unsubscribe("QUEST_LOG_UPDATE", self)
end

function Banner:OnLogUpdate()
    for questID, title in pairs(self.watching) do
        if C_QuestLog.IsComplete(questID) then
            self.watching[questID] = nil
            self:Ready(questID, title or nil)
        end
    end
    if next(self.watching) == nil then
        self:StopWatching()
    end
end

function Banner:OnInfo(_, messageType, message)
    local spec = self.specs[messageType]
    if not spec or type(message) ~= "string" or UIErrorsFrame:GetMessagesSuppressed() then
        return
    end
    self:Echo(messageType)
    local matched, name, have, need = parse(spec, message)
    if spec.kind == "turnin" then
        local title = matched and name or message
        self:Present({ key = "t:" .. title, kind = "turnin", title = title, label = R.L.QUEST_BANNER_TURNED_IN },
            BANNER_HOLD)
        return
    end
    if spec.kind == "objective" then
        local readyID, readyTitle = self:FindByTitle(name)
        if readyID then
            self:Settle()
            return self:Watch(readyID, readyTitle)
        end
        local questID, title = self:FindQuest(name)
        if not questID and self.settleTimer then
            return
        end
        local key = "o:" .. message
        self:Present({ key = key, kind = "progress", questID = questID, title = title,
            label = matched and name or message, icon = "other", done = true }, PROGRESS_HOLD)
        if questID then
            self:Settle()
            self:Watch(questID, title)
        else
            self.anonymous[key] = true
        end
        return
    end
    if not (matched and have and need) then
        -- A line that does not read back still has to reach the player.
        self:Present({ key = "m:" .. message, kind = "progress", label = message, icon = spec.kind },
            PROGRESS_HOLD)
        return
    end
    local questID, title = self:FindQuest(name, need)
    local label = spec.label:gsub(NAME, function() return name or "" end)
    self:Present({ key = "p:" .. tostring(questID or 0) .. ":" .. label, kind = "progress", questID = questID,
        title = title, label = label, icon = spec.kind, have = have, need = need }, PROGRESS_HOLD)
    if have >= need then
        self:Settle()
        if questID then
            self:Watch(questID, title)
        end
    end
end

function Banner:OnLevelUp()
    if self.lowerTimer then
        self.lowerTimer:Cancel()
    end
    R.UI:QuestBannerLower(self.ui, true)
    self.lowerTimer = R:After(self, LEVEL_UP_YIELD, function()
        self.lowerTimer = nil
        R.UI:QuestBannerLower(self.ui, false)
    end)
end

-- The first counted objective in the log, or a stand-in when there is none.
function Banner:Sample()
    for index = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local info = C_QuestLog.GetInfo(index)
        local questID = type(info) == "table" and not info.isHeader and info.questID
        if type(questID) == "number" then
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or EMPTY) do
                if type(objective) == "table" and type(objective.text) == "string"
                    and (objective.numRequired or 0) > 1 then
                    return questID, info.title, stripCount(objective.text), objective.numRequired,
                        ICONS[objective.type] or "other"
                end
            end
        end
    end
    return 0, R.L.QUEST_BANNER_SAMPLE_TITLE, R.L.QUEST_BANNER_SAMPLE_OBJECTIVE, 4, "item"
end

-- /refactor questtest: one objective counted up to done, its quest as ready, then as handed in.
function Banner:Test()
    self:StopWatching()
    R:CancelTimers(self)
    self.lifetimes, self.anonymous, self.settleTimer = {}, {}, nil
    R.UI:QuestBannerHide(self.ui)
    local questID, title, label, need, icon = self:Sample()
    local key = "p:" .. questID .. ":" .. label
    local function step(have)
        self:Present({ key = key, kind = "progress", questID = questID, title = title, label = label,
            icon = icon, have = have, need = need }, PROGRESS_HOLD)
    end
    step(1)
    R:After(self, 1.2, function() step(math.max(1, need - 1)) end)
    R:After(self, 2.4, function() step(need) end)
    R:After(self, 2.4, function() self:Ready(questID, title) end)
    R:After(self, 10, function()
        self:Present({ key = "t:" .. title, kind = "turnin", title = title, label = R.L.QUEST_BANNER_TURNED_IN },
            BANNER_HOLD)
    end)
    R:Print(string.format(R.L.CMD_QUEST_TEST_SHOWN, title))
end

-- Blizzard's own switch for a message type (UIErrorsMixin:SetMessageTypeEnabled, 12.1.0): only
-- these lines stop drawing, every other info and error line is untouched, and OnDisable turns
-- each one back on.
function Banner:OnEnable()
    self.specs = self:Specs()
    self.lifetimes, self.watching, self.watchTimer, self.lowerTimer = {}, {}, nil, nil
    self.anonymous, self.settleTimer = {}, nil
    self.ui = self.ui or R.UI:QuestBannerCreate()
    R.UI:QuestBannerAnchor(self.ui, UIErrorsFrame)
    for messageType in pairs(self.specs) do
        UIErrorsFrame:SetMessageTypeEnabled(messageType, false)
    end
    R.Broker:Subscribe("UI_INFO_MESSAGE", self.OnInfo, self)
    R.Broker:Subscribe("PLAYER_LEVEL_UP", self.OnLevelUp, self)
    R.Broker:Subscribe("REFACTOR_QUEST_BANNER_TEST", self.Test, self)
end

function Banner:OnDisable()
    for messageType in pairs(self.specs or EMPTY) do
        UIErrorsFrame:SetMessageTypeEnabled(messageType, true)
    end
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
    self.lifetimes, self.watching, self.watchTimer, self.lowerTimer = {}, {}, nil, nil
    self.anonymous, self.settleTimer = {}, nil
    if self.ui then
        R.UI:QuestBannerHide(self.ui)
    end
end
