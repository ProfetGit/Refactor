--- @module nameplates.questProgress (data half, registers nothing)
--- Purpose: turn a unit token into objective numbers, with a cache keyed by NPC ID.
--- Requires: C_QuestLog.UnitIsRelatedToActiveQuest, C_QuestLog.GetQuestObjectives, C_QuestLog.IsOnQuest,
---     IsInGroup, C_TooltipInfo.GetUnit, Enum.TooltipDataLineType.QuestTitle,
---     Enum.TooltipDataLineType.QuestObjective, Enum.TooltipDataLineType.QuestPlayer
--- Events: none, the module owns invalidation
--- Hot: yes
-- @hot
local _, R = ...

local Data = {}
R.QuestData = Data

local KIND_KILL, KIND_ITEM, KIND_OTHER = "kill", "item", "other"
local OBJECTIVE_KINDS = {
    monster = KIND_KILL,
    item = KIND_ITEM,
}

Data.cache = {}
Data.kinds = OBJECTIVE_KINDS
-- An open objective ranks by its share done, 0 up to below 1. A finished one ranks under
-- all of them and over the -1 nothing starts from, so it shows only when nothing is open.
local FINISHED_RANK = -0.5
-- Where an objective line sits in a group tooltip: before any name (solo, or a quest only
-- the player shows), under the player's own name, or under someone else's.
local SECTION_NONE, SECTION_OWN, SECTION_OTHER = 0, 1, 2
-- The player's name as a group tooltip heads their section, short and full. Set by the
-- module at enable: on Forever the tooltip writes name and surname, "Profet Ashbringer",
-- where UnitName's first value is "Profet" alone.
local ownShort, ownFull
-- Log objectives already counted in one resolve, so one objective read from two sections
-- counts once. Emptied before Resolve returns.
local claimed = {}

function Data:SetPlayerNames(short, full)
    ownShort, ownFull = short, full
end

local function lineTypes()
    local enum = R.Capabilities:Resolve("Enum.TooltipDataLineType")
    if type(enum) ~= "table" then
        return nil
    end
    return enum.QuestTitle, enum.QuestObjective, enum.QuestPlayer
end

-- "Creature-0-3061-1-42177-38038-002FAC4343": the sixth field is the NPC ID. Pets,
-- players and vehicles are deliberately not cached, their ids mean something else.
function Data:NPCID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local id = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return id and tonumber(id) or nil
end

-- Fallback only. The tooltip carries numFulfilled and numRequired as fields; this runs
-- when it does not, which is progress bars and anything the client words differently.
function Data:ParseObjective(text)
    if type(text) ~= "string" then
        return nil
    end
    local fulfilled, required = text:match("(%d+)%s*/%s*(%d+)")
    if fulfilled then
        return tonumber(fulfilled), tonumber(required)
    end
    local percent = text:match("(%d+)%s*%%")
    if percent then
        return tonumber(percent), 100
    end
    return nil
end

-- The tooltip writes each objective with the quest log's own text, counts included: the
-- Probe dump has "0/6 Tiki Target slain" in both. A line with exactly the player's text is
-- the player's objective in whoever's section it sits, since equal text means equal counts.
local function ownObjective(objectives, text)
    if not objectives or type(text) ~= "string" then
        return nil
    end
    for position = 1, #objectives do
        local objective = objectives[position]
        if type(objective) == "table" and objective.text == text then
            return objective
        end
    end
    return nil
end

-- The tooltip lists only the objectives this mob serves, so a line's position is not the
-- quest log's: a mob that drops the item but is not the kill target shows the item first.
-- Text is the match; equal counts next, in case the two ever word it differently; position
-- last.
local function findObjective(objectives, index, text, fulfilled, required)
    local objective = ownObjective(objectives, text)
    if objective then
        return objective
    end
    for position = 1, #objectives do
        objective = objectives[position]
        if type(objective) == "table" and objective.numFulfilled == fulfilled
            and objective.numRequired == required then
            return objective
        end
    end
    return objectives[index]
end

local function kindOf(objectives, index, text, fulfilled, required)
    if type(objectives) ~= "table" then
        return KIND_OTHER
    end
    local objective = findObjective(objectives, index, text, fulfilled, required)
    if type(objective) ~= "table" then
        return KIND_OTHER
    end
    return OBJECTIVE_KINDS[objective.type] or KIND_OTHER
end

function Data:KindForQuest(questID, index, text, fulfilled, required)
    if not questID then
        return KIND_OTHER
    end
    return kindOf(C_QuestLog.GetQuestObjectives(questID), index, text, fulfilled, required)
end

-- Whether a line counts as the player's: its text is one of the player's own objectives,
-- or it sits under the player's name, or under no name at all. In a group a nameless line
-- also needs the quest to be the player's, in case a party member's quest is listed bare.
local function counts(own, section, onQuest)
    if own then
        if claimed[own] then
            return false
        end
        claimed[own] = true
        return true
    end
    return section == SECTION_OWN or (section == SECTION_NONE and onQuest)
end

-- Writes into `out` and returns it, so a resolve allocates nothing of its own.
function Data:Resolve(unit, out)
    out.ok, out.fulfilled, out.required, out.plus = false, 0, 0, 0
    out.kind, out.complete, out.lastOne = KIND_OTHER, false, false
    if not C_QuestLog.UnitIsRelatedToActiveQuest(unit) then
        return out
    end
    local titleType, objectiveType, playerType = lineTypes()
    if not objectiveType then
        return out
    end
    local tooltip = C_TooltipInfo.GetUnit(unit)
    if type(tooltip) ~= "table" or type(tooltip.lines) ~= "table" then
        return out
    end
    for key in pairs(claimed) do
        claimed[key] = nil
    end
    -- Solo, every line is the player's: the guard stays off so a bonus objective the log
    -- does not count as "on" can never be lost to it.
    local isOnQuest = IsInGroup() and C_QuestLog.IsOnQuest or nil
    local objectives, onQuest, section, objectiveIndex = nil, true, SECTION_NONE, 0
    local best, bestRatio, matches, bestFulfilled, bestRequired = nil, -1, 0, 0, 0
    local bestObjectives, bestIndex = nil, 0
    for index = 1, #tooltip.lines do
        local line = tooltip.lines[index]
        local kind = line and line.type
        if kind == titleType then
            local questID = line.id
            section, objectiveIndex = SECTION_NONE, 0
            objectives = questID and C_QuestLog.GetQuestObjectives(questID) or nil
            if type(objectives) ~= "table" then
                objectives = nil
            end
            onQuest = not questID or not isOnQuest or isOnQuest(questID) ~= false
        elseif kind == playerType then
            -- In a group every player's objectives sit under their name, the player's own
            -- included, each list starting again from the first objective.
            local name = line.leftText
            if name ~= nil and (name == ownShort or name == ownFull) then
                section = SECTION_OWN
            else
                section = SECTION_OTHER
            end
            objectiveIndex = 0
        elseif kind == objectiveType then
            objectiveIndex = objectiveIndex + 1
            if counts(ownObjective(objectives, line.leftText), section, onQuest) then
                local fulfilled, required = line.numFulfilled, line.numRequired
                if type(fulfilled) ~= "number" or type(required) ~= "number" or required <= 0 then
                    fulfilled, required = self:ParseObjective(line.leftText)
                end
                if fulfilled and required and required > 0 then
                    -- Anything still open outranks everything finished: a mob that already
                    -- counted 8/8 for one objective and still drops for another must show the
                    -- other, or the plate reads complete and fades while work is left.
                    local ratio = FINISHED_RANK
                    if line.completed ~= true and fulfilled < required then
                        matches, ratio = matches + 1, fulfilled / required
                    end
                    if ratio > bestRatio then
                        bestRatio, bestFulfilled, bestRequired = ratio, fulfilled, required
                        bestObjectives, bestIndex, best = objectives, objectiveIndex, line
                    end
                end
            end
        end
    end
    for key in pairs(claimed) do
        claimed[key] = nil
    end
    if not best then
        return out
    end
    out.ok = true
    out.fulfilled, out.required = bestFulfilled, bestRequired
    out.plus = matches > 0 and matches - 1 or 0
    out.complete = best.completed == true or bestFulfilled >= bestRequired
    out.lastOne = not out.complete and bestRequired - bestFulfilled == 1
    out.kind = kindOf(bestObjectives, bestIndex, best.leftText, bestFulfilled, bestRequired)
    return out
end

function Data:Get(npcID)
    return npcID and self.cache[npcID] or nil
end

function Data:Put(npcID, entry)
    if npcID then
        self.cache[npcID] = entry
    end
end

-- Named invalidation only: QUEST_LOG_UPDATE and UNIT_QUEST_LOG_CHANGED. No expiry.
function Data:Invalidate()
    local cache = self.cache
    for key in pairs(cache) do
        cache[key] = nil
    end
end
