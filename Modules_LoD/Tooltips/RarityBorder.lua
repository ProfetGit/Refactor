--- @module tooltips.rarityBorder
--- Purpose: tint the tooltip border with the shown item's quality colour, and untint on clear.
--- Requires: TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, C_Item.GetItemQualityByID,
---     C_Item.GetItemQualityColor, GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2
--- Events: GET_ITEM_INFO_RECEIVED (contextual, only while a quality lookup is pending)
--- Hot: yes, see RarityBorder_Data.lua
local _, R = ...
local Border = R.RarityBorderData
local RarityBorder = R:RegisterModule({
    id = "tooltips.rarityBorder", category = "Tooltips", nameKey = "TOOLTIP_BORDER_NAME",
    descriptionKey = "TOOLTIP_BORDER_DESC", detailKey = "TOOLTIP_BORDER_DETAIL",
    requires = { "TooltipDataProcessor.AddTooltipPostCall", "Enum.TooltipDataType.Item",
        "C_Item.GetItemQualityByID", "C_Item.GetItemQualityColor", "GameTooltip", "ItemRefTooltip",
        "ShoppingTooltip1", "ShoppingTooltip2" },
    tier = "full", risk = "visible", defaultEnabled = false,
})

local watched = {}

function RarityBorder:Watch(tooltip)
    if not watched[tooltip] and tooltip.NineSlice and tooltip.HookScript then
        watched[tooltip] = true
        tooltip:HookScript("OnTooltipCleared", function(widget)
            -- The standard bug: a recycled tooltip keeping the last item's colour.
            if self.state == "enabled" then
                Border:Clear(widget)
            end
        end)
    end
end

function RarityBorder:OnItemInfo(_, itemID)
    if itemID ~= self.pendingID then
        return
    end
    local quality = Border:Quality(itemID)
    if quality then
        R.Broker:Unsubscribe("GET_ITEM_INFO_RECEIVED", self)
        local tooltip = self.pendingTooltip
        self.pendingID, self.pendingTooltip = nil, nil
        if tooltip and tooltip:IsShown() then
            Border:Tint(tooltip, quality)
        end
    end
end

function RarityBorder:OnItem(tooltip, data)
    if self.state ~= "enabled" or not watched[tooltip] or type(data) ~= "table" then
        return
    end
    local nameLine = data.lines and data.lines[1]
    local color = nameLine and nameLine.leftColor
    if color and color.GetRGB and Border:TintColor(tooltip, color:GetRGB()) then
        return
    end
    local itemID = data.id
    if type(itemID) ~= "number" then
        return
    end
    local quality = Border:Quality(itemID)
    if not quality then
        -- Not cached yet: stay neutral now, colour when the data arrives.
        self.pendingID, self.pendingTooltip = itemID, tooltip
        R.Broker:Subscribe("GET_ITEM_INFO_RECEIVED", self.OnItemInfo, self)
        return
    end
    Border:Tint(tooltip, quality)
end

function RarityBorder:OnEnable()
    Border:LoadColors()
    self:Watch(GameTooltip)
    self:Watch(ItemRefTooltip)
    self:Watch(ShoppingTooltip1)
    self:Watch(ShoppingTooltip2)
    if not self.installed then
        self.installed = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            R:SafeCall(self, self.OnItem, "tooltip", tooltip, data)
        end)
    end
end

function RarityBorder:OnDisable()
    self.pendingID, self.pendingTooltip = nil, nil
    R.Broker:UnsubscribeAll(self)
    for tooltip in pairs(watched) do
        Border:Clear(tooltip)
    end
end
