--- @module interface.autoStand
--- Purpose: explain why Retail standing automation is intentionally unavailable.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...
local AutoStand = R:RegisterModule({
    id = "interface.autoStand", category = "Interface", nameKey = "AUTO_STAND_NAME",
    descriptionKey = "AUTO_STAND_DESC", detailKey = "AUTO_STAND_DETAIL", requires = {},
    tier = "minimal", risk = "safe", defaultEnabled = false,
    unavailableReasonKey = "AUTO_STAND_UNAVAILABLE",
})

-- PlayerScriptDocumentation marks SitStandOrDescendStart HasRestrictions=true.
-- A capability check alone cannot establish permission to call a protected action.
function AutoStand:OnEnable() end
function AutoStand:OnDisable() end
