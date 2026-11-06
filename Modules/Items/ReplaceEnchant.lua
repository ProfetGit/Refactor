--- @module items.replaceEnchant
--- Purpose: answer Yes when applying an enchant or item enhancement would replace one already on the item.
--- Requires: InCombatLockdown, StaticPopup_Hide, C_Item.ReplaceEnchant, C_Item.ReplaceTradeskillEnchant
--- Events: REPLACE_ENCHANT, REPLACE_TRADESKILL_ENCHANT
--- Hot: no
local _, R = ...
local ReplaceEnchant = R:RegisterModule({
    id = "items.replaceEnchant", category = "Items", nameKey = "REPLACE_ENCHANT_NAME",
    descriptionKey = "REPLACE_ENCHANT_DESC", detailKey = "REPLACE_ENCHANT_DETAIL",
    requires = { "InCombatLockdown", "StaticPopup_Hide", "C_Item.ReplaceEnchant",
        "C_Item.ReplaceTradeskillEnchant" },
    risk = "automation", defaultEnabled = false,
})

-- Two dialogs ask the same question: an enchant or kit used from the bags, and an enchant cast
-- from the profession window. Each answer is the call that dialog's Yes makes (GameDialogDefs.lua).
-- Blizzard shows the dialog from the same event, in no fixed order with us, so it closes a tick later.
function ReplaceEnchant:Answer(which, accept)
    if InCombatLockdown() or R:Paused() then
        return
    end
    accept()
    R:After(self, 0, function() StaticPopup_Hide(which) end)
end

function ReplaceEnchant:OnReplace()
    self:Answer("REPLACE_ENCHANT", C_Item.ReplaceEnchant)
end

function ReplaceEnchant:OnReplaceTradeskill()
    self:Answer("REPLACE_TRADESKILL_ENCHANT", C_Item.ReplaceTradeskillEnchant)
end

function ReplaceEnchant:OnEnable()
    R.Broker:Subscribe("REPLACE_ENCHANT", self.OnReplace, self)
    R.Broker:Subscribe("REPLACE_TRADESKILL_ENCHANT", self.OnReplaceTradeskill, self)
end

function ReplaceEnchant:OnDisable()
    R.Broker:UnsubscribeAll(self)
    R:CancelTimers(self)
end
