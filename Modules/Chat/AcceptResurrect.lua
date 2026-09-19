--- @module social.acceptResurrect
--- Purpose: accept a player's resurrection when out of combat, in the areas the player chose.
--- Requires: InCombatLockdown, IsInInstance, AcceptResurrect, StaticPopup_Hide
--- Events: RESURRECT_REQUEST
--- Hot: no
local _, R = ...
local AcceptRes = R:RegisterModule({
    id = "social.acceptResurrect", category = "Social", nameKey = "SOCIAL_RESURRECT_NAME",
    descriptionKey = "SOCIAL_RESURRECT_DESC", detailKey = "SOCIAL_RESURRECT_DETAIL",
    requires = { "InCombatLockdown", "IsInInstance", "AcceptResurrect", "StaticPopup_Hide" },
    tier = "manual", risk = "automation", defaultEnabled = false,
})

-- Every instanceType the client returns today maps to one of the three area options. An
-- unknown one means a patch added a type nobody here has seen, and an automation module
-- that does nothing is a better answer than one that accepts somewhere unasked.
local AREA_OPTION = {
    pvp = "resurrectPvp", arena = "resurrectPvp",
    party = "resurrectInstance", raid = "resurrectInstance", scenario = "resurrectInstance",
    none = "resurrectWorld",
}

function AcceptRes:AreaAllowed()
    local _, instanceType = IsInInstance()
    local option = AREA_OPTION[instanceType or "none"]
    return option ~= nil and R.Settings:GetOption(option) == true
end

function AcceptRes:OnRequest()
    if InCombatLockdown() or R:Paused() or not self:AreaAllowed() then
        return
    end
    AcceptResurrect()
    StaticPopup_Hide("RESURRECT")
    StaticPopup_Hide("RESURRECT_NO_SICKNESS")
    StaticPopup_Hide("RESURRECT_NO_TIMER")
end

function AcceptRes:OnEnable()
    R.Broker:Subscribe("RESURRECT_REQUEST", self.OnRequest, self)
end

function AcceptRes:OnDisable()
    R.Broker:UnsubscribeAll(self)
end
