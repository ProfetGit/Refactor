--- @integration Questie
--- Purpose: report whether Questie is present, so quest modules can stand down.
--- Requires: C_AddOns.IsAddOnLoaded
--- Events: none
--- Hot: no
local _, R = ...

R.Integrations = R.Integrations or {}

function R.Integrations:IsLoaded(name)
    local loaded = R.Capabilities:Resolve("C_AddOns.IsAddOnLoaded")
    if not loaded then
        return false
    end
    local ok, result = pcall(loaded, name)
    return ok and result == true
end

R.Integrations.providers = R.Integrations.providers or {}
R.Integrations.providers["Questie"] = "nameplates.questProgress"
