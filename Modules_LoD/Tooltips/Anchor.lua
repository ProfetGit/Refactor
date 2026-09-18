--- @module tooltips.anchor
--- Purpose: move tooltips that ask for the default anchor to the cursor or a chosen screen point.
--- Requires: hooksecurefunc, GameTooltip_SetDefaultAnchor, UIParent
--- Events: none, secure post-hook only
--- Hot: no, the default anchor is requested once per tooltip shown
local _, R = ...
local Anchor = R:RegisterModule({
    id = "tooltips.anchor", category = "Tooltips", nameKey = "TOOLTIP_ANCHOR_NAME",
    descriptionKey = "TOOLTIP_ANCHOR_DESC", detailKey = "TOOLTIP_ANCHOR_DETAIL",
    requires = { "hooksecurefunc", "GameTooltip_SetDefaultAnchor", "UIParent" },
    tier = "full", risk = "visible", defaultEnabled = false,
})

-- ANCHOR_CURSOR takes no offset, the other two do. These are the only cursor anchor
-- names SetOwner accepts, see Blizzard_AuraButton.lua's validAnchorPointNames.
local CURSOR_ANCHORS = {
    RIGHT = "ANCHOR_CURSOR_RIGHT", LEFT = "ANCHOR_CURSOR_LEFT", CENTER = "ANCHOR_CURSOR",
}

-- The client positions a cursor-anchored tooltip itself. Refactor never repositions a
-- tooltip per frame (PRD 7.7.1).
function Anchor:OnDefaultAnchor(tooltip, parent)
    if self.state ~= "enabled" or type(tooltip) ~= "table" then
        return
    end
    -- Anything that is not the fixed point means the cursor, including the legacy
    -- "default" value saved before the mode list dropped it.
    if R.Settings:GetOption("tooltipAnchor") == "point" then
        local point = R.Settings:GetOption("tooltipPoint") or "BOTTOMRIGHT"
        tooltip:ClearAllPoints()
        tooltip:SetPoint(point, UIParent, point, R.Settings:GetOption("tooltipX") or 0,
            R.Settings:GetOption("tooltipY") or 0)
    else
        local side = R.Settings:GetOption("tooltipCursorSide") or "RIGHT"
        -- GameTooltip_SetDefaultAnchor has already hard-anchored the tooltip to the default
        -- container. Those points outlive SetOwner and would win over the cursor anchor.
        tooltip:ClearAllPoints()
        tooltip:SetOwner(parent or UIParent, CURSOR_ANCHORS[side] or "ANCHOR_CURSOR_RIGHT",
            R.Settings:GetOption("tooltipCursorX") or 16, R.Settings:GetOption("tooltipCursorY") or 0)
    end
end

function Anchor:OnEnable()
    if not self.installed then
        self.installed = true
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
            R:SafeCall(self, self.OnDefaultAnchor, "anchor", tooltip, parent)
        end)
    end
end

function Anchor:OnDisable()
    R.Broker:UnsubscribeAll(self)
end
