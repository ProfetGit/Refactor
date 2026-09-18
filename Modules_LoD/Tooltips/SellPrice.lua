--- @module tooltips.sellPrice
--- Purpose: append a labelled unit and stack price to item tooltips.
--- Requires: TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, TooltipUtil.GetDisplayedItem,
---     SetTooltipMoney, MerchantFrame, GameTooltip, ItemRefTooltip, C_Item.GetItemInfo
--- Events: none, tooltip post-call only
--- Hot: yes, but the client throttles tooltip refreshes to one per item shown
local _, R = ...
local Price = R.Price
local SellPrice = R:RegisterModule({
    id = "tooltips.sellPrice", category = "Tooltips", nameKey = "TOOLTIP_PRICE_NAME",
    descriptionKey = "TOOLTIP_PRICE_DESC", detailKey = "TOOLTIP_PRICE_DETAIL",
    requires = { "TooltipDataProcessor.AddTooltipPostCall", "Enum.TooltipDataType.Item",
        "TooltipUtil.GetDisplayedItem", "SetTooltipMoney", "MerchantFrame", "GameTooltip", "ItemRefTooltip",
        "C_Item.GetItemInfo" },
    tier = "standard", risk = "visible", defaultEnabled = false,
})

local SOURCE_KEYS = { tsm = "TOOLTIP_SOURCE_TSM", auctionator = "TOOLTIP_SOURCE_AUCTIONATOR" }

function SellPrice:Label(source)
    if source == "vendor" then
        return R.L.TOOLTIP_SELL_PRICE
    end
    local key = SOURCE_KEYS[source]
    if key == "TOOLTIP_SOURCE_TSM" then
        return string.format(R.L[key], R.Settings:GetOption("tsmPriceString") or "")
    end
    return key and R.L[key] or source
end

function SellPrice:OnItem(tooltip)
    if self.state ~= "enabled" or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then
        return
    end
    -- The merchant window already shows sell prices; a second line there is noise.
    if MerchantFrame:IsShown() then
        return
    end
    local _, link = TooltipUtil.GetDisplayedItem(tooltip)
    if not link then
        return
    end
    local unit, source = Price:Get(link, 1)
    if not unit then
        return
    end
    SetTooltipMoney(tooltip, unit, nil, self:Label(source))
    local stackSize = select(8, C_Item.GetItemInfo(link))
    if type(stackSize) == "number" and stackSize > 1 then
        SetTooltipMoney(tooltip, unit * stackSize, nil, string.format(R.L.TOOLTIP_STACK_PRICE, stackSize))
    end
    if tooltip:IsShown() then
        tooltip:Show()
    end
end

function SellPrice:OnEnable()
    -- A post-call cannot be removed, so it is installed once and consults the module state.
    if not self.installed then
        self.installed = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            R:SafeCall(self, self.OnItem, "tooltip", tooltip)
        end)
    end
end

function SellPrice:OnDisable()
    R.Broker:UnsubscribeAll(self)
end
