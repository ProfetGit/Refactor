--- @module vendor.itemCosts
--- Purpose: merchant costs grey out only what you are short of, every cost shows, and the coin box lists the
---     items a merchant is priced in.
--- Requires: hooksecurefunc, GameTooltip, MerchantFrame, MerchantItem1, MerchantFrame_Update,
---     MerchantFrame_UpdateCurrencies, MERCHANT_ITEMS_PER_PAGE, MAX_ITEM_COST, MAX_MERCHANT_CURRENCIES,
---     MerchantMoneyFrame, MerchantMoneyInset, MerchantMoneyBg, MerchantExtraCurrencyInset, MerchantExtraCurrencyBg,
---     GetMerchantNumItems,
---     C_MerchantFrame.GetItemInfo, C_MerchantFrame.GetMerchantCurrencies, CanAffordMerchantItem,
---     GetMerchantItemCostInfo, GetMerchantItemCostItem, GetMoney, C_CurrencyInfo.GetCurrencyInfoFromLink,
---     C_Item.GetItemCount, AltCurrencyFrame_Update, SetMoneyFrameColor, MoneyFrame_SetMaxDisplayWidth,
---     MoneyFrame_Update
--- Events: REFACTOR_MERCHANT_FILTERED; otherwise it rides Blizzard's own merchant update
--- Hot: no
local _, R = ...
local ItemCosts = R:RegisterModule({
    id = "vendor.itemCosts", category = "Vendor", nameKey = "VENDOR_COSTS_NAME",
    descriptionKey = "VENDOR_COSTS_DESC", detailKey = "VENDOR_COSTS_DETAIL",
    requires = { "hooksecurefunc", "GameTooltip", "MerchantFrame", "MerchantItem1", "MerchantFrame_Update",
        "MerchantFrame_UpdateCurrencies", "MERCHANT_ITEMS_PER_PAGE", "MAX_ITEM_COST", "MAX_MERCHANT_CURRENCIES",
        "MerchantMoneyFrame", "MerchantMoneyInset", "MerchantMoneyBg", "MerchantExtraCurrencyInset",
        "MerchantExtraCurrencyBg", "GetMerchantNumItems",
        "C_MerchantFrame.GetItemInfo", "C_MerchantFrame.GetMerchantCurrencies", "CanAffordMerchantItem",
        "GetMerchantItemCostInfo", "GetMerchantItemCostItem", "GetMoney", "C_CurrencyInfo.GetCurrencyInfoFromLink",
        "C_Item.GetItemCount", "AltCurrencyFrame_Update", "SetMoneyFrameColor", "MoneyFrame_SetMaxDisplayWidth",
        "MoneyFrame_Update" },
    risk = "visible", defaultEnabled = true,
})

-- The merchant filter fills the page again after Blizzard's pass, with Blizzard's own
-- greying; whichever hook ran first, the costs are redone once the filter is done.
function ItemCosts:OnFiltered()
    self.costs:Refresh()
end

function ItemCosts:OnEnable()
    local owner = R.Integrations:Owner(self.id)
    if owner then
        -- Deference is decided once. Plumber's Merchant Price draws the same coin box and
        -- greys the same costs; two of each is what this stands down from.
        self.unavailableReasonKey = "VENDOR_COSTS_DEFERRED"
        self.state = "unavailable"
        self.unavailableReason = string.format(R.L.VENDOR_COSTS_DEFERRED, R.L.NEIGHBOUR_PLUMBER)
        R.Broker:Emit("REFACTOR_MODULE_CHANGED", self.id)
        return
    end
    self.costs = R.UI:CreateMerchantCosts(self)
    R.Broker:Subscribe("REFACTOR_MERCHANT_FILTERED", self.OnFiltered, self)
    self.costs:Apply()
end

function ItemCosts:OnDisable()
    R.Broker:UnsubscribeAll(self)
    if self.costs then
        self.costs:Restore()
    end
end
