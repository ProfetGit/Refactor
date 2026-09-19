--- @module vendor.itemCosts
--- Purpose: merchant costs grey out only what you are short of, every cost shows, and the coin box lists the
---     items a merchant is priced in.
--- Requires: hooksecurefunc, GameTooltip, MerchantFrame, MerchantItem1, MerchantFrame_Update,
---     MerchantFrame_UpdateCurrencies, MERCHANT_ITEMS_PER_PAGE, MAX_ITEM_COST, MAX_MERCHANT_CURRENCIES,
---     MerchantMoneyFrame, MerchantExtraCurrencyInset, MerchantExtraCurrencyBg, GetMerchantNumItems,
---     C_MerchantFrame.GetItemInfo, C_MerchantFrame.GetMerchantCurrencies, CanAffordMerchantItem,
---     GetMerchantItemCostInfo, GetMerchantItemCostItem, GetMoney, C_CurrencyInfo.GetCurrencyInfoFromLink,
---     C_Item.GetItemCount, AltCurrencyFrame_Update, SetMoneyFrameColor, MoneyFrame_SetMaxDisplayWidth,
---     MoneyFrame_Update
--- Events: none, it rides Blizzard's own merchant update
--- Hot: no
local _, R = ...
local ItemCosts = R:RegisterModule({
    id = "vendor.itemCosts", category = "Vendor", nameKey = "VENDOR_COSTS_NAME",
    descriptionKey = "VENDOR_COSTS_DESC", detailKey = "VENDOR_COSTS_DETAIL",
    requires = { "hooksecurefunc", "GameTooltip", "MerchantFrame", "MerchantItem1", "MerchantFrame_Update",
        "MerchantFrame_UpdateCurrencies", "MERCHANT_ITEMS_PER_PAGE", "MAX_ITEM_COST", "MAX_MERCHANT_CURRENCIES",
        "MerchantMoneyFrame", "MerchantExtraCurrencyInset", "MerchantExtraCurrencyBg", "GetMerchantNumItems",
        "C_MerchantFrame.GetItemInfo", "C_MerchantFrame.GetMerchantCurrencies", "CanAffordMerchantItem",
        "GetMerchantItemCostInfo", "GetMerchantItemCostItem", "GetMoney", "C_CurrencyInfo.GetCurrencyInfoFromLink",
        "C_Item.GetItemCount", "AltCurrencyFrame_Update", "SetMoneyFrameColor", "MoneyFrame_SetMaxDisplayWidth",
        "MoneyFrame_Update" },
    tier = "standard", risk = "visible", defaultEnabled = false,
})

function ItemCosts:OnEnable()
    self.costs = R.UI:CreateMerchantCosts(self)
    self.costs:Apply()
end

function ItemCosts:OnDisable()
    if self.costs then
        self.costs:Restore()
    end
end
