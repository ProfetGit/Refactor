--- @integration TSM
--- Purpose: offer TradeSkillMaster's custom price as an opt-in provider, labelled as such.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...
local Price = R.Price

R.Integrations = R.Integrations or {}

-- TSM_API is another addon's global, so it is resolved by name at login and never
-- declared as a client API. A missing or changed TSM simply means no provider.
function R.Integrations:RegisterTSM()
    local getValue = R.Capabilities:Resolve("TSM_API.GetCustomPriceValue")
    local toItemString = R.Capabilities:Resolve("TSM_API.ToItemString")
    if type(getValue) ~= "function" or type(toItemString) ~= "function" then
        return false
    end
    Price:RegisterProvider("tsm", 100, function(item)
        local itemString = toItemString(item)
        if not itemString then
            return nil
        end
        return getValue(R.Settings:GetOption("tsmPriceString") or "dbMarket", itemString)
    end)
    return true
end
