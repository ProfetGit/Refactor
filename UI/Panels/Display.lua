local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme

local QUALITY_KEYS = { [0] = "UI_QUALITY_0", "UI_QUALITY_1", "UI_QUALITY_2", "UI_QUALITY_3", "UI_QUALITY_4",
    "UI_QUALITY_5" }
-- Cyclers rather than sliders: every other numeric option in this window is one, and the
-- useful values here are few.
local OPACITY_STEPS = { 0.5, 0.65, 0.85, 1 }
local LIFETIME_STEPS = { 3, 5, 8, 12, 20 }
local ROW_STEPS = { 3, 5, 7, 10 }
local SCALE_STEPS = { 0.8, 0.9, 1, 1.1, 1.25 }

local function nextStep(steps, current)
    for index, value in ipairs(steps) do
        if math.abs(value - (current or 0)) < 0.001 then
            return steps[index % #steps + 1]
        end
    end
    return steps[1]
end

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

    local toasts = self.Widgets:Section(parent, L.UI_TOAST_OPTIONS, L.UI_TOAST_MOVE_HELP)
    local function cycler(key, steps, y)
        local button = Theme:Button(toasts, 300, "", function()
            Settings:SetOption(key, nextStep(steps, Settings:GetOption(key)))
            self:LoadDisplay()
        end)
        button:SetPoint("TOPLEFT", 0, toasts.top + y)
        return button
    end

    self.toastQualityButton = Theme:Button(toasts, 300, "", function()
        Settings:SetOption("toastMinQuality", ((Settings:GetOption("toastMinQuality") or 0) + 1) % 6)
        self:LoadDisplay()
    end)
    self.toastQualityButton:SetPoint("TOPLEFT", 0, toasts.top)
    self.toastOpacityButton = cycler("toastOpacity", OPACITY_STEPS, -30)
    self.toastLifetimeButton = cycler("toastLifetime", LIFETIME_STEPS, -60)
    self.toastRowsButton = cycler("toastMaxRows", ROW_STEPS, -90)
    self.toastScaleButton = cycler("toastScale", SCALE_STEPS, -120)
    toggle(toasts, "toastShowPrice", "UI_TOAST_PRICE", -152)
    toggle(toasts, "toastShowSource", "UI_TOAST_SOURCE", -184)
    toggle(toasts, "toastAggregate", "UI_TOAST_AGGREGATE", -216)
    toggle(toasts, "toastGold", "UI_TOAST_GOLD", -248)
    toggle(toasts, "toastCurrency", "UI_TOAST_CURRENCY", -280)
    toasts:SetBodyHeight(306)

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
    self.toastOpacityButton.label:SetText(string.format(L.UI_TOGGLE_FORMAT, L.UI_TOAST_OPACITY,
        string.format(L.UI_TOAST_PERCENT, math.floor((Settings:GetOption("toastOpacity") or 1) * 100 + 0.5))))
    self.toastLifetimeButton.label:SetText(string.format(L.UI_TOGGLE_FORMAT, L.UI_TOAST_LIFETIME,
        string.format(L.UI_TOAST_SECONDS, Settings:GetOption("toastLifetime") or 5)))
    self.toastRowsButton.label:SetText(string.format(L.UI_TOGGLE_FORMAT, L.UI_TOAST_MAX_ROWS,
        string.format(L.UI_TOAST_ROWS, Settings:GetOption("toastMaxRows") or 5)))
    self.toastScaleButton.label:SetText(string.format(L.UI_TOGGLE_FORMAT, L.UI_TOAST_SCALE,
        string.format(L.UI_TOAST_PERCENT, math.floor((Settings:GetOption("toastScale") or 1) * 100 + 0.5))))
    if not self.tsmString:HasFocus() then self.tsmString:SetText(Settings:GetOption("tsmPriceString") or "") end
    local integrations = R.Integrations or {}
    self.priceNote:SetText(string.format(L.UI_PRICE_NOTE,
        integrations.tsmAvailable and L.UI_PRICE_FOUND or L.UI_PRICE_MISSING,
        integrations.auctionatorAvailable and L.UI_PRICE_FOUND or L.UI_PRICE_MISSING))
    for _, box in ipairs(self.displayToggles) do
        box:SetChecked(Settings:GetOption(box.optionKey) == true)
    end
end
