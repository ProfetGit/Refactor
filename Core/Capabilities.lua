local _, R = ...
local Capabilities = {}
R.Capabilities = Capabilities

function Capabilities:Resolve(symbol)
    if type(symbol) ~= "string" or not symbol:match("^[%a_][%w_%.]*$") then
        return nil
    end
    if symbol:find("%.%.") or symbol:sub(-1) == "." then
        return nil
    end
    local value = _G
    for part in symbol:gmatch("[^%.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[part]
    end
    return value
end

function Capabilities:Check(requires)
    local missing = {}
    for _, symbol in ipairs(requires or {}) do
        if self:Resolve(symbol) == nil then
            missing[#missing + 1] = symbol
        end
    end
    return #missing == 0, missing
end
