local _, R = ...
R.UI = R.UI or {}
local UI = R.UI

function UI:ModuleText(module, field)
    local key = module[field .. "Key"]
    return key and R.L[key] or module[field] or module.id
end

function UI:Category(module)
    -- Anything that decides for the player is shown in one place, never mixed in with
    -- the harmless settings of its own category (PRD 6.3).
    return module.risk == "automation" and "Automation" or module.category
end

-- The filter is one category name, or a set of them for a sidebar group. A search query
-- ignores the filter altogether: search is global (PRD 8.2).
function UI:Matches(module, query, filter)
    query = (query or ""):lower()
    if query == "" then
        if not filter then return true end
        local category = self:Category(module)
        if type(filter) == "table" then return filter[category] == true end
        return category == filter
    end
    local haystack = self:ModuleText(module, "name") .. " " .. self:ModuleText(module, "description")
        .. " " .. (R.L["UI_" .. self:Category(module)] or self:Category(module)) .. " " .. module.id
    if module.tags then
        if type(module.tags) == "table" then haystack = haystack .. " " .. table.concat(module.tags, " ")
        else haystack = haystack .. " " .. module.tags end
    end
    haystack = haystack:lower()
    -- Plain matching avoids treating a player's search text as a Lua pattern.
    for word in query:gmatch("%S+") do
        if not haystack:find(word, 1, true) then return false end
    end
    return true
end

function UI:ParseNeverSell(text)
    local result = {}
    for token in (text or ""):gmatch("[^,%s]+") do
        local id = tonumber(token)
        if not id or id <= 0 or id ~= math.floor(id) or not token:match("^%d+$") then return nil end
        result[id] = true
    end
    return result
end
