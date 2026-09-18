local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme

local QUALITY_KEYS = { [0] = "UI_QUALITY_0", "UI_QUALITY_1", "UI_QUALITY_2", "UI_QUALITY_3", "UI_QUALITY_4",
    "UI_QUALITY_5" }

-- Three sections of the Options page. Everything here applies on click, except the typed
-- field, which waits for Save.
function UI:BuildDisplay(parent)
    self.displayToggles = {}
    local function toggle(section, key, labelKey, y)
        local box = Theme:Checkbox(section, 300, L[labelKey], function(widget)
            Settings:SetOption(key, widget:GetChecked() == true)
            self:LoadDisplay()
        end)
        box:SetPoint("TOPLEFT", 0, section.top + y)
        box.optionKey = key
        self.displayToggles[#self.displayToggles + 1] = box
        return box
    end

    local toasts = self.Widgets:Section(parent, L.UI_TOAST_OPTIONS)
    self.toastQualityButton = Theme:Button(toasts, 300, "", function()
        Settings:SetOption("toastMinQuality", ((Settings:GetOption("toastMinQuality") or 0) + 1) % 6)
        self:LoadDisplay()
    end)
    self.toastQualityButton:SetPoint("TOPLEFT", 0, toasts.top)
    toggle(toasts, "toastShowPrice", "UI_TOAST_PRICE", -30)
    toggle(toasts, "toastGold", "UI_TOAST_GOLD", -62)
    toggle(toasts, "toastCurrency", "UI_TOAST_CURRENCY", -94)
    toasts:SetBodyHeight(120)

    local prices = self.Widgets:Section(parent, L.UI_PRICE_OPTIONS)
    toggle(prices, "priceTSM", "UI_PRICE_TSM", 0)
    toggle(prices, "priceAuctionator", "UI_PRICE_AUCTIONATOR", -32)
    local tsmLabel = Theme:Text(prices, L.UI_PRICE_TSM_STRING, "small", "TEXT_MUTED")
    tsmLabel:SetPoint("TOPLEFT", 0, prices.top - 70)
    self.tsmString = self.Widgets:Input(prices, 200, 26)
    self.tsmString:SetPoint("TOPLEFT", 0, prices.top - 86)
    local saveTSM = Theme:Button(prices, 104, L.UI_SAVE_SHORT, function()
        if Settings:SetOption("tsmPriceString", self.tsmString:GetText()) then
            self.displayStatus:SetText(L.UI_SAVED)
        else
            self.displayStatus:SetText(L.UI_PRICE_STRING_INVALID)
        end
        self.tsmString:ClearFocus()
    end)
    saveTSM:SetPoint("LEFT", self.tsmString, "RIGHT", 8, 0)
    self.displayStatus = Theme:Text(prices, "", "small", "TEXT_TITLE")
    self.displayStatus:SetPoint("LEFT", saveTSM, "RIGHT", 12, 0)
    self.displayStatus:SetPoint("RIGHT")
    self.priceNote = Theme:Text(prices, "", "small", "TEXT_MUTED")
    self.priceNote:SetPoint("TOPLEFT", 0, prices.top - 120)
    self.priceNote:SetPoint("RIGHT")
    self.priceNote:SetHeight(40)
    self.priceNote:SetJustifyV("TOP")
    prices:SetBodyHeight(160)

    local quests = self.Widgets:Section(parent, L.UI_QUEST_OPTIONS)
    toggle(quests, "questAcceptItemsOnly", "UI_QUEST_ITEMS_ONLY", 0)
    quests:SetBodyHeight(26)
    return { toasts, prices, quests }
end

function UI:LoadDisplay()
    if not self.toastQualityButton then return end
    local quality = Settings:GetOption("toastMinQuality") or 0
    self.toastQualityButton.label:SetText(string.format(L.UI_TOGGLE_FORMAT, L.UI_TOAST_QUALITY,
        L[QUALITY_KEYS[quality] or "UI_QUALITY_0"]))
    if not self.tsmString:HasFocus() then self.tsmString:SetText(Settings:GetOption("tsmPriceString") or "") end
    local integrations = R.Integrations or {}
    self.priceNote:SetText(string.format(L.UI_PRICE_NOTE,
        integrations.tsmAvailable and L.UI_PRICE_FOUND or L.UI_PRICE_MISSING,
        integrations.auctionatorAvailable and L.UI_PRICE_FOUND or L.UI_PRICE_MISSING))
    for _, box in ipairs(self.displayToggles) do
        box:SetChecked(Settings:GetOption(box.optionKey) == true)
    end
end
