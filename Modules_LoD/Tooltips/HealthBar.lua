--- @module tooltips.hideHealthBar
--- Purpose: hides the health bar the game draws under the unit tooltip.
--- Requires: hooksecurefunc, GameTooltip
--- Events: none, secure post-hook only
--- Hot: no, the bar is shown once per unit tooltip
local _, R = ...

local HideHealthBar = R:RegisterModule({
    id = "tooltips.hideHealthBar", category = "Tooltips", nameKey = "TOOLTIP_HEALTHBAR_NAME",
    descriptionKey = "TOOLTIP_HEALTHBAR_DESC", detailKey = "TOOLTIP_HEALTHBAR_DETAIL",
    requires = { "hooksecurefunc", "GameTooltip" },
    risk = "visible", defaultEnabled = false,
})

-- The bar is GameTooltip's own child (parentKey StatusBar) and it shows itself from
-- GameTooltipUnitHealthBarMixin:SetWatch. Hiding it also stops its OnUpdate, which is
-- the only per-frame handler on a tooltip.
function HideHealthBar:OnEnable()
    local bar = GameTooltip and GameTooltip.StatusBar
    if not bar then
        return
    end
    if not self.installed then
        self.installed = true
        hooksecurefunc(bar, "Show", function(statusBar)
            if self.state == "enabled" then
                statusBar:Hide()
            end
        end)
    end
    bar:Hide()
end

function HideHealthBar:OnDisable()
    R.Broker:UnsubscribeAll(self)
end
