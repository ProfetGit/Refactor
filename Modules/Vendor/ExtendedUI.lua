--- @module vendor.extendedUI
--- Purpose: more rows and columns in Blizzard's merchant window, drawn with Blizzard's own art.
--- Requires: InCombatLockdown, hooksecurefunc, MerchantFrame, MerchantItem1, MerchantItem12, MerchantBuyBackItem,
---     MerchantNextPageButton, MerchantFrameBottomLeftBorder, MerchantFrame_Update, MERCHANT_ITEMS_PER_PAGE,
---     BUYBACK_ITEMS_PER_PAGE
--- Events: REFACTOR_SETTINGS_CHANGED; PLAYER_REGEN_ENABLED (contextual)
--- Hot: no
local _, R = ...
local ExtendedUI = R:RegisterModule({
    id = "vendor.extendedUI", category = "Vendor", nameKey = "VENDOR_UI_NAME",
    descriptionKey = "VENDOR_UI_DESC", detailKey = "VENDOR_UI_DETAIL",
    -- MerchantItem1 and MerchantItem12 stand for the twelve cells Blizzard's XML ships; the
    -- grid reaches the ones between by name. A client with fewer leaves the module unavailable.
    requires = { "InCombatLockdown", "hooksecurefunc", "MerchantFrame", "MerchantItem1", "MerchantItem12",
        "MerchantBuyBackItem", "MerchantNextPageButton", "MerchantFrameBottomLeftBorder", "MerchantFrame_Update",
        "MERCHANT_ITEMS_PER_PAGE", "BUYBACK_ITEMS_PER_PAGE" },
    tier = "standard", risk = "visible", defaultEnabled = false,
})

-- The merchant window is not a protected frame, so reshaping it in combat is allowed. It
-- is still put off until the fight ends: a window changing shape mid-pull helps nobody.
function ExtendedUI:Apply()
    if InCombatLockdown() then
        if not self.pending then
            self.pending = true
            R.Broker:Subscribe("PLAYER_REGEN_ENABLED", self.OnCombatEnded, self)
        end
        return
    end
    self.grid:Apply(R.Settings:GetOption("vendorColumns"), R.Settings:GetOption("vendorRows"))
end

function ExtendedUI:OnCombatEnded()
    self.pending = nil
    R.Broker:Unsubscribe("PLAYER_REGEN_ENABLED", self)
    self:Apply()
end

function ExtendedUI:OnSettingsChanged(_, key)
    if key == "vendorColumns" or key == "vendorRows" then
        self:Apply()
    end
end

function ExtendedUI:OnEnable()
    self.grid = R.UI:CreateMerchantGrid(self)
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettingsChanged, self)
    self:Apply()
end

function ExtendedUI:OnDisable()
    self.pending = nil
    R.Broker:UnsubscribeAll(self)
    if self.grid then
        self.grid:Restore()
    end
end
