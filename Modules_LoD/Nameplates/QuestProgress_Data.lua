--- @module nameplates.questProgress (data half, registers nothing)
--- Purpose: turn a unit token into objective numbers, with a cache keyed by NPC ID.
--- Requires: C_QuestLog.UnitIsRelatedToActiveQuest, C_QuestLog.GetQuestObjectives,
---     C_TooltipInfo.GetUnit, Enum.TooltipDataLineType.QuestTitle,
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

function Data:KindForQuest(questID, index)
    if not questID then
        return KIND_OTHER
    end
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if type(objectives) ~= "table" then
        return KIND_OTHER
    end
    local objective = objectives[index]
    if type(objective) ~= "table" then
        return KIND_OTHER
    end
    return OBJECTIVE_KINDS[objective.type] or KIND_OTHER
end

-- Writes into `out` and returns it, so a resolve allocates nothing.
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
    local questID, objectiveIndex, best, bestRatio, matches = nil, 0, nil, -1, 0
    local bestFulfilled, bestRequired, bestQuest, bestIndex, foreign = 0, 0, nil, 0, false
    for index = 1, #tooltip.lines do
        local line = tooltip.lines[index]
        local kind = line and line.type
        if kind == titleType then
            questID, objectiveIndex = line.id, 0
        elseif kind == playerType then
            -- Another player's section starts here. Their numbers are never displayed.
            foreign = true
        elseif kind == objectiveType then
            objectiveIndex = objectiveIndex + 1
            local fulfilled, required = line.numFulfilled, line.numRequired
            if type(fulfilled) ~= "number" or type(required) ~= "number" or required <= 0 then
                if not foreign then
                    fulfilled, required = self:ParseObjective(line.leftText)
                else
                    fulfilled, required = nil, nil
                end
            end
            if fulfilled and required and required > 0 then
                matches = matches + 1
                local ratio = fulfilled / required
                if line.completed then
                    ratio = 1
                end
                if ratio > bestRatio then
                    bestRatio, bestFulfilled, bestRequired = ratio, fulfilled, required
                    bestQuest, bestIndex, best = questID, objectiveIndex, line
                end
            end
        end
    end
    if not best then
        return out
    end
    out.ok = true
    out.fulfilled, out.required = bestFulfilled, bestRequired
    out.plus = matches - 1
    out.complete = best.completed == true or bestFulfilled >= bestRequired
    out.lastOne = not out.complete and bestRequired - bestFulfilled == 1
    out.kind = self:KindForQuest(bestQuest, bestIndex)
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
