--- @module vendor.extendedUI
--- Purpose: a searchable, filterable list of a merchant's stock beside the merchant window.
--- Requires: InCombatLockdown, IsShiftKeyDown, MerchantFrame, GetMerchantNumItems, C_MerchantFrame.GetItemInfo,
---     GetMerchantItemLink, GetMerchantItemMaxStack, BuyMerchantItem, GetNumBuybackItems,
---     GetBuybackItemInfo, BuybackItem, C_Item.GetItemQualityByID
--- Events: MERCHANT_SHOW; MERCHANT_CLOSED, MERCHANT_UPDATE (contextual)
--- Hot: no
local _, R = ...
local ExtendedUI = R:RegisterModule({
    id = "vendor.extendedUI", category = "Vendor", nameKey = "VENDOR_UI_NAME",
    descriptionKey = "VENDOR_UI_DESC", detailKey = "VENDOR_UI_DETAIL",
    requires = { "InCombatLockdown", "IsShiftKeyDown", "MerchantFrame", "GetMerchantNumItems",
        "C_MerchantFrame.GetItemInfo", "GetMerchantItemLink", "GetMerchantItemMaxStack", "BuyMerchantItem",
        "GetNumBuybackItems", "GetBuybackItemInfo", "BuybackItem", "C_Item.GetItemQualityByID" },
    tier = "standard", risk = "visible", defaultEnabled = false,
})

local MAX_BUYBACK = 3

-- Rebuilds the flat list the panel shows: only gold-priced stock, filtered by the search
-- text and the usable toggle. Rows are reused, never created here.
function ExtendedUI:Collect()
    local panel, items = self.panel, self.items
    for index = #items, 1, -1 do
        items[index] = nil
    end
    local query = panel:GetQuery()
    local usableOnly = panel:UsableOnly()
    for index = 1, GetMerchantNumItems() do
        local info = C_MerchantFrame.GetItemInfo(index)
        if info and info.price and info.price > 0 and not info.hasExtendedCost and (not usableOnly or info.isUsable)
            and (query == "" or (info.name or ""):lower():find(query, 1, true)) then
            local link = GetMerchantItemLink(index)
            local itemID = link and tonumber(link:match("item:(%d+)"))
            items[#items + 1] = {
                index = index, name = info.name, texture = info.texture, price = info.price,
                stackCount = info.stackCount, numAvailable = info.numAvailable,
                quality = itemID and C_Item.GetItemQualityByID(itemID) or nil,
            }
        end
    end
    local buyback = self.buyback
    for index = #buyback, 1, -1 do
        buyback[index] = nil
    end
    local total = GetNumBuybackItems()
    for index = total, math.max(1, total - MAX_BUYBACK + 1), -1 do
        local name, texture, price, quantity = GetBuybackItemInfo(index)
        if name then
            buyback[#buyback + 1] = { index = index, name = name, texture = texture, price = price,
                stackCount = quantity }
        end
    end
end

function ExtendedUI:Refresh()
    if not MerchantFrame:IsShown() then
        return
    end
    self:Collect()
    self.panel:Render(self.items, self.buyback)
end

function ExtendedUI:Buy(index, stack)
    if InCombatLockdown() or not MerchantFrame:IsShown() then
        return
    end
    local quantity = 1
    if stack or IsShiftKeyDown() then
        quantity = math.max(1, GetMerchantItemMaxStack(index) or 1)
    end
    BuyMerchantItem(index, quantity)
end

function ExtendedUI:Buyback(index)
    if InCombatLockdown() or not MerchantFrame:IsShown() then
        return
    end
    BuybackItem(index)
end

function ExtendedUI:OnClosed()
    self.panel:Hide()
    R.Broker:Unsubscribe("MERCHANT_CLOSED", self)
    R.Broker:Unsubscribe("MERCHANT_UPDATE", self)
end

function ExtendedUI:OnShow()
    R.Broker:Subscribe("MERCHANT_CLOSED", self.OnClosed, self)
    R.Broker:Subscribe("MERCHANT_UPDATE", self.Refresh, self, 0.1)
    self.panel:Show()
    self:Refresh()
end

function ExtendedUI:OnEnable()
    self.items, self.buyback = {}, {}
    self.panel = R.UI:CreateVendorPanel(self)
    R.Broker:Subscribe("MERCHANT_SHOW", self.OnShow, self)
end

function ExtendedUI:OnDisable()
    if self.panel then
        self.panel:Hide()
    end
    R.Broker:UnsubscribeAll(self)
end
