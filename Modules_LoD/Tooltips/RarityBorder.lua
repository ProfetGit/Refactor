--- @module tooltips.rarityBorder
--- Purpose: tint the tooltip border with the shown item's quality colour, or a hovered player's class
--- colour, and untint on clear.
--- Requires: TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, Enum.TooltipDataType.Unit,
---     TooltipUtil.GetDisplayedUnit, UnitIsPlayer, UnitClassBase, C_Item.GetItemQualityByID,
---     C_Item.GetItemQualityColor, GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2
--- Events: GET_ITEM_INFO_RECEIVED (contextual, only while a quality lookup is pending)
--- Hot: yes, see RarityBorder_Data.lua
local _, R = ...
local Border = R.RarityBorderData
local RarityBorder = R:RegisterModule({
    id = "tooltips.rarityBorder", category = "Tooltips", nameKey = "TOOLTIP_BORDER_NAME",
    descriptionKey = "TOOLTIP_BORDER_DESC", detailKey = "TOOLTIP_BORDER_DETAIL",
    requires = { "TooltipDataProcessor.AddTooltipPostCall", "Enum.TooltipDataType.Item",
        "Enum.TooltipDataType.Unit", "TooltipUtil.GetDisplayedUnit", "UnitIsPlayer", "UnitClassBase",
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

-- A unit tooltip carries a GUID, not a unit; the client's own helper turns it back into a
-- token. Only players are coloured: a mob's class is not something the rest of the UI
-- colours, and the border staying white is how you tell one from a player.
function RarityBorder:OnUnit(tooltip)
    if self.state ~= "enabled" or not watched[tooltip] then
        return
    end
    if R.Settings:GetOption("tooltipClassBorder") ~= true then
        return
    end
    local _, unit = TooltipUtil.GetDisplayedUnit(tooltip)
    if unit == nil or not UnitIsPlayer(unit) then
        return
    end
    local classFile = UnitClassBase(unit)
    if type(classFile) == "string" then
        Border:TintClass(tooltip, classFile)
    end
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
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            R:SafeCall(self, self.OnUnit, "unit tooltip", tooltip)
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
