local _, R = ...

local EMPTY = {}

-- A recorded list that covers less than this share of the shipped one is a partial visit (a weapon
-- master, a trainer window that filtered most of its list), not the class trainer's whole list.
local COMPLETE_SHARE = 0.6

-- The abilities of one class that the spellbook does not list until they are learned, as
-- spell id -> { level, line }. A complete trainer list the player recorded is exact, so it is used on
-- its own. Otherwise the shipped table (Data/ClassSpells.lua) is the base, a close fit for everyone,
-- with whatever the player did record laid over it, and its faction-bound entries (city teleports and
-- portals) held to `faction`, the player's own. The second return says whether the trainer list stood
-- alone.
function R:ClassSpellList(classFile, faction)
    local out = {}
    if type(classFile) ~= "string" then
        return out, false
    end
    local recorded, recordedCount = {}, 0
    local record = R.Settings.account.classSpells
    record = type(record) == "table" and record[classFile]
    if type(record) == "table" then
        for spellID, entry in pairs(record) do
            if type(spellID) == "number" and type(entry) == "table" and type(entry.level) == "number" then
                recorded[spellID] = { level = entry.level, line = type(entry.line) == "string" and entry.line or "" }
                recordedCount = recordedCount + 1
            end
        end
    end
    local data = R.ClassSpells
    local list = type(data) == "table" and type(data.spells) == "table" and data.spells[classFile]
    local shipped = 0
    for _ in pairs(list or EMPTY) do
        shipped = shipped + 1
    end
    if recordedCount > 0 and recordedCount >= shipped * COMPLETE_SHARE then
        return recorded, true
    end
    if shipped > 0 then
        local lines = data.lines and data.lines[classFile] or EMPTY
        local bound = data.faction or EMPTY
        for spellID, level in pairs(list) do
            if not bound[spellID] or bound[spellID] == faction then
                out[spellID] = { level = level, line = lines[spellID] or "" }
            end
        end
    end
    for spellID, entry in pairs(recorded) do
        if entry.level >= 1 or not out[spellID] then
            out[spellID] = entry
        end
    end
    return out, false
end
