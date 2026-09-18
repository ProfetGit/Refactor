--- @module social.declineDuels
--- Purpose: cancel duel requests as they arrive.
--- Requires: CancelDuel, StaticPopup_Hide
--- Events: DUEL_REQUESTED
--- Hot: no
local _, R = ...
local DeclineDuels = R:RegisterModule({
    id = "social.declineDuels", category = "Social", nameKey = "SOCIAL_DUEL_NAME",
    descriptionKey = "SOCIAL_DUEL_DESC", detailKey = "SOCIAL_DUEL_DETAIL",
    requires = { "CancelDuel", "StaticPopup_Hide" },
    tier = "manual", risk = "automation", defaultEnabled = false,
})

function DeclineDuels:OnRequest()
    if R:Paused() then
        return
    end
    CancelDuel()
    StaticPopup_Hide("DUEL_REQUESTED")
end

function DeclineDuels:OnEnable()
    R.Broker:Subscribe("DUEL_REQUESTED", self.OnRequest, self)
end

function DeclineDuels:OnDisable()
    R.Broker:UnsubscribeAll(self)
end
