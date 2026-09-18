--- @module social.acceptResurrect
--- Purpose: accept a player's resurrection when out of combat.
--- Requires: InCombatLockdown, AcceptResurrect, StaticPopup_Hide
--- Events: RESURRECT_REQUEST
--- Hot: no
local _, R = ...
local AcceptRes = R:RegisterModule({
    id = "social.acceptResurrect", category = "Social", nameKey = "SOCIAL_RESURRECT_NAME",
    descriptionKey = "SOCIAL_RESURRECT_DESC", detailKey = "SOCIAL_RESURRECT_DETAIL",
    requires = { "InCombatLockdown", "AcceptResurrect", "StaticPopup_Hide" },
    tier = "manual", risk = "automation", defaultEnabled = false,
})

function AcceptRes:OnRequest()
    if InCombatLockdown() or R:Paused() then
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
