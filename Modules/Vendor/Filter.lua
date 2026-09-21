--- @module vendor.filter
--- Purpose: a dropdown in the merchant window to show only mounts, pets, toys, appearances or recipes, owned or
---     missing, paged as if the rest were not there.
--- Requires: hooksecurefunc, MerchantFrame, MerchantItem1, MerchantFrame_Update,
---     MerchantFrame_UpdateItemQualityBorders, MerchantFrame_UpdateAltCurrency, MerchantFrameItem_UpdateQuality,
---     MERCHANT_ITEMS_PER_PAGE, MERCHANT_PAGE_NUMBER,
---     MerchantPrevPageButton, MerchantNextPageButton, MerchantPageText, TEXTURE_ITEM_QUEST_BANG, GetMerchantNumItems,
---     GetMerchantItemLink, GetMerchantItemID, C_MerchantFrame.GetItemInfo, C_MerchantFrame.IsMerchantItemRefundable,
---     CanAffordMerchantItem, CurrencyContainerUtil.GetCurrencyContainerInfo, C_Heirloom.IsItemHeirloom,
---     C_Heirloom.PlayerHasHeirloom, SetItemButtonCount, SetItemButtonStock, SetItemButtonTexture,
---     SetItemButtonDesaturated, SetItemButtonNameFrameVertexColor, SetItemButtonSlotVertexColor,
---     SetItemButtonTextureVertexColor, SetItemButtonNormalTextureVertexColor, MoneyFrame_SetMaxDisplayWidth,
---     MoneyFrame_Update, SetMoneyFrameColor, C_Item.GetItemInfoInstant, C_MountJournal.GetMountFromItem,
---     C_MountJournal.GetMountInfoByID, C_PetJournal.GetPetInfoByItemID, C_PetJournal.GetNumCollectedInfo,
---     C_ToyBox.GetToyInfo, PlayerHasToy, C_TransmogCollection.GetItemInfo,
---     C_TransmogCollection.PlayerHasTransmogByItemInfo, C_TooltipInfo.GetMerchantItem, ITEM_SPELL_KNOWN,
---     Enum.ItemClass.Miscellaneous, Enum.ItemClass.Recipe, Enum.ItemClass.Armor, Enum.ItemClass.Weapon,
---     Enum.ItemMiscellaneousSubclass.CompanionPet
--- Events: MERCHANT_SHOW, NEW_RECIPE_LEARNED
--- Hot: no
local _, R = ...
local Filter = R:RegisterModule({
    id = "vendor.filter", category = "Vendor", nameKey = "VENDOR_FILTER_NAME",
    descriptionKey = "VENDOR_FILTER_DESC", detailKey = "VENDOR_FILTER_DETAIL",
    requires = { "hooksecurefunc", "MerchantFrame", "MerchantItem1", "MerchantFrame_Update",
        "MerchantFrame_UpdateItemQualityBorders", "MerchantFrame_UpdateAltCurrency", "MerchantFrameItem_UpdateQuality",
        "MERCHANT_ITEMS_PER_PAGE", "MERCHANT_PAGE_NUMBER", "MerchantPrevPageButton", "MerchantNextPageButton",
        "MerchantPageText", "TEXTURE_ITEM_QUEST_BANG", "GetMerchantNumItems", "GetMerchantItemLink",
        "GetMerchantItemID", "C_MerchantFrame.GetItemInfo", "C_MerchantFrame.IsMerchantItemRefundable",
        "CanAffordMerchantItem", "CurrencyContainerUtil.GetCurrencyContainerInfo", "C_Heirloom.IsItemHeirloom",
        "C_Heirloom.PlayerHasHeirloom", "SetItemButtonCount", "SetItemButtonStock", "SetItemButtonTexture",
        "SetItemButtonDesaturated", "SetItemButtonNameFrameVertexColor", "SetItemButtonSlotVertexColor",
        "SetItemButtonTextureVertexColor", "SetItemButtonNormalTextureVertexColor", "MoneyFrame_SetMaxDisplayWidth",
        "MoneyFrame_Update", "SetMoneyFrameColor", "C_Item.GetItemInfoInstant", "C_MountJournal.GetMountFromItem",
        "C_MountJournal.GetMountInfoByID", "C_PetJournal.GetPetInfoByItemID", "C_PetJournal.GetNumCollectedInfo",
        "C_ToyBox.GetToyInfo", "PlayerHasToy", "C_TransmogCollection.GetItemInfo",
        "C_TransmogCollection.PlayerHasTransmogByItemInfo", "C_TooltipInfo.GetMerchantItem", "ITEM_SPELL_KNOWN",
        "Enum.ItemClass.Miscellaneous", "Enum.ItemClass.Recipe", "Enum.ItemClass.Armor", "Enum.ItemClass.Weapon",
        "Enum.ItemMiscellaneousSubclass.CompanionPet" },
    risk = "visible", defaultEnabled = true,
})

function Filter:OnShow()
    self.filter:Reset()
end

function Filter:OnRecipeLearned()
    self.filter:ForgetRecipes()
    self.filter:Refresh()
end

function Filter:OnEnable()
    self.filter = R.UI:CreateMerchantFilter(self)
    R.Broker:Subscribe("MERCHANT_SHOW", self.OnShow, self)
    R.Broker:Subscribe("NEW_RECIPE_LEARNED", self.OnRecipeLearned, self)
    self.filter:Enable()
end

function Filter:OnDisable()
    R.Broker:UnsubscribeAll(self)
    if self.filter then
        self.filter:Disable()
    end
end
