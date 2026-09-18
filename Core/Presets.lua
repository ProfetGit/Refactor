--- @core presets
--- Purpose: decide preset membership from each module's declared tier and risk.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...
local Presets = {}
R.Presets = Presets

-- Ranked, so Standard contains Minimal and Full contains Standard (PRD 6.2).
local RANK = { minimal = 1, standard = 2, full = 3 }
Presets.order = { "minimal", "standard", "full" }

-- Automation makes a decision for the player, so it is in no preset, Full included (PRD 6.3).
function Presets:Includes(preset, module)
    if module.risk == "automation" then
        return false
    end
    local wanted, tier = RANK[preset], RANK[module.tier]
    return wanted ~= nil and tier ~= nil and tier <= wanted
end

function Presets:Members(preset, into)
    local members = into or {}
    for index = #members, 1, -1 do
        members[index] = nil
    end
    for _, module in ipairs(R.modules) do
        if self:Includes(preset, module) then
            members[#members + 1] = module.id
        end
    end
    table.sort(members)
    return members
end

function Presets:Count(preset)
    local count = 0
    for _, module in ipairs(R.modules) do
        if self:Includes(preset, module) then
            count = count + 1
        end
    end
    return count
end

-- A preset writes account defaults, never character overrides: it is the starting point
-- every character inherits, which is what makes a new alt cost zero clicks.
function Presets:Apply(preset)
    if preset ~= nil and not RANK[preset] then
        return false
    end
    for _, module in ipairs(R.modules) do
        R.Settings:SetAccount(module.id, preset ~= nil and self:Includes(preset, module) or false)
    end
    R.Settings:MarkFirstRunDone(preset or "none")
    return true
end
