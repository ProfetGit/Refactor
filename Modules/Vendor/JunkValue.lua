--- @module vendor.junkValue
--- Purpose: show the count and sell value of grey items while a merchant is open.
--- Requires: MerchantFrame, NUM_TOTAL_EQUIPPED_BAG_SLOTS, C_Container.GetContainerNumSlots,
---     C_Container.GetContainerItemInfo, C_Item.GetItemInfo
--- Events: MERCHANT_SHOW; MERCHANT_CLOSED, BAG_UPDATE_DELAYED (contextual)
--- Hot: no, one bag scan per merchant visit and per bag change while it is open
local _, R = ...
local JunkValue = R:RegisterModule({
    id = "vendor.junkValue", category = "Vendor", nameKey = "JUNK_VALUE_NAME",
    descriptionKey = "JUNK_VALUE_DESC", detailKey = "JUNK_VALUE_DETAIL",
    requires = { "MerchantFrame", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "C_Container.GetContainerNumSlots",
        "C_Container.GetContainerItemInfo", "C_Item.GetItemInfo" },
    tier = "standard", risk = "visible", defaultEnabled = false,
})

local function moneyText(amount)
    return string.format(R.L.MONEY_TEXT, math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
end

function JunkValue:Scan()
    local neverSell = R.Settings:GetOption("neverSellIDs") or {}
    local count, value = 0, 0
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == 0 and not info.hasNoValue and not neverSell[info.itemID] then
                local price = select(11, C_Item.GetItemInfo(info.hyperlink))
                if type(price) == "number" and price > 0 then
                    count = count + info.stackCount
                    value = value + price * info.stackCount
                end
            end
        end
    end
    return count, value
end

function JunkValue:Refresh()
    if not MerchantFrame:IsShown() then
        return
    end
    local count, value = self:Scan()
    self.readout:SetText(count > 0 and string.format(R.L.JUNK_VALUE_LINE, count, moneyText(value))
        or R.L.JUNK_VALUE_NONE)
    self.readout:Show()
end

function JunkValue:OnClosed()
    self.readout:Hide()
    R.Broker:Unsubscribe("MERCHANT_CLOSED", self)
    R.Broker:Unsubscribe("BAG_UPDATE_DELAYED", self)
end

function JunkValue:OnShow()
    R.Broker:Subscribe("MERCHANT_CLOSED", self.OnClosed, self)
    R.Broker:Subscribe("BAG_UPDATE_DELAYED", self.Refresh, self, 0.2)
    self:Refresh()
end

function JunkValue:OnEnable()
    self.readout = R.UI:CreateJunkReadout(self)
    R.Broker:Subscribe("MERCHANT_SHOW", self.OnShow, self)
end

function JunkValue:OnDisable()
    if self.readout then
        self.readout:Hide()
    end
    R.Broker:UnsubscribeAll(self)
end
