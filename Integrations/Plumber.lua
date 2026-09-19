--- @integration Plumber
--- Purpose: report whether Plumber's Merchant Price module is on, so merchant cost modules stand down.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...

R.Integrations = R.Integrations or {}
R.Integrations.providers = R.Integrations.providers or {}
R.Integrations.providers["Plumber"] = "vendor.itemCosts"

-- Plumber ships the feature off, so the addon being loaded says nothing; its saved
-- setting does. PlumberDB is another addon's global, resolved by name and never
-- declared, and its absence reads as the feature being off.
R.Integrations.activeChecks = R.Integrations.activeChecks or {}
R.Integrations.activeChecks["Plumber"] = function()
    return R.Capabilities:Resolve("PlumberDB.MerchantPrice") == true
end
