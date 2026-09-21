--- @module items.deleteFill
--- Purpose: fill only the ordinary item deletion edit box, leaving acceptance manual.
--- Requires: InCombatLockdown, StaticPopup_FindVisible, DELETE_ITEM_CONFIRM_STRING
--- Events: DELETE_ITEM_CONFIRM
--- Hot: no
local _, R = ...
local DeleteFill = R:RegisterModule({
    id = "items.deleteFill", category = "Items", nameKey = "DELETE_FILL_NAME",
    descriptionKey = "DELETE_FILL_DESC", detailKey = "DELETE_FILL_DETAIL",
    requires = { "InCombatLockdown", "StaticPopup_FindVisible", "DELETE_ITEM_CONFIRM_STRING" },
    risk = "safe", defaultEnabled = false,
})

function DeleteFill:Fill()
    if InCombatLockdown() or R:Paused() then
        return
    end
    local dialog = StaticPopup_FindVisible("DELETE_GOOD_ITEM")
    if not dialog or dialog:IsProtected() then
        return
    end
    local editBox = dialog:GetEditBox()
    if editBox and not editBox:IsProtected() and editBox:GetText() == "" then
        editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
    end
end

function DeleteFill:OnConfirm()
    -- Blizzard's event handler must create/show the existing dialog first.
    R:CancelTimers(self)
    R:After(self, 0, self.Fill)
end

function DeleteFill:OnEnable()
    R.Broker:Subscribe("DELETE_ITEM_CONFIRM", self.OnConfirm, self)
end

function DeleteFill:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
end
