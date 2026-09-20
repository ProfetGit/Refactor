local _, R = ...
local UI, L, Settings = R.UI, R.L, R.Settings
local Theme = R.Theme

local SECONDS_PER_MINUTE = 60
-- A named choice is a dropdown, not a button that cycles: a button hides every option but
-- the one showing, and says nothing about how many presses the one you want is away.
local MODIFIER_ENTRIES = {
    { value = "CTRL", labelKey = "UI_CTRL" },
    { value = "SHIFT", labelKey = "UI_SHIFT" },
    { value = "ALT", labelKey = "UI_ALT" },
}
-- Each rarity carries its own colour as a swatch in front of the name, so the list is read
-- by colour before it is read as words. quality is the value here, named separately because
-- it is what decorates the entry rather than what the entry stores.
local QUALITY_ENTRIES = {
    { value = 0, quality = 0, labelKey = "UI_QUALITY_0" },
    { value = 1, quality = 1, labelKey = "UI_QUALITY_1" },
    { value = 2, quality = 2, labelKey = "UI_QUALITY_2" },
    { value = 3, quality = 3, labelKey = "UI_QUALITY_3" },
    { value = 4, quality = 4, labelKey = "UI_QUALITY_4" },
    { value = 5, quality = 5, labelKey = "UI_QUALITY_5" },
}

-- Decoration, so a client without the colour lookup loses a dot rather than the dropdown.
local function qualitySwatch(quality)
    local lookup = C_Item and C_Item.GetItemQualityColor
    if not lookup then return "" end
    local r, g, b = lookup(quality)
    if not r then return "" end
    return Theme:Dot(r, g, b) .. " "
end
local PRICE_ENTRIES = {
    { value = "auto", labelKey = "PRICE_SOURCE_AUTO" },
    { value = "tsm", labelKey = "PRICE_SOURCE_TSM" },
    { value = "auctionator", labelKey = "PRICE_SOURCE_AUCTIONATOR" },
    { value = "vendor", labelKey = "PRICE_SOURCE_VENDOR" },
}
-- A slider is a row of its own height, not a 30 px button, so a block of them steps by the
-- theme's slider height plus a gap.
local SLIDER_WIDTH, SLIDER_GAP = 380, 6
local SLIDER_STEP = LibStub("LibRefactorTheme-1.0").sliderRowHeight + SLIDER_GAP

-- Blizzard's minimal slider for anything that is a magnitude: a position on a track says
-- how much of the range a value is, which four named steps behind a button never did.
-- Named choices (item quality, a price provider, a modifier key) keep the button, because
-- there is no "more" for a slider to mean.
--
-- Each range is the range Settings itself accepts, so the track cannot reach a value the
-- validator would refuse. Where a setting is stored as a factor, show converts it for the
-- slider and store converts it back, the way Blizzard shows a scale as a percentage.
local function percentText(value)
    return string.format(L.UI_TOAST_PERCENT, math.floor(value + 0.5))
end

local function secondsText(value)
    return string.format(L.UI_TOAST_SECONDS, value)
end

local function rowsText(value)
    return string.format(L.UI_TOAST_ROWS, value)
end

local function minutesText(value)
    return string.format(L.UI_FARM_MINUTES, value)
end

local function columnsText(value)
    return string.format(L.UI_VENDOR_COLUMN_COUNT, value)
end

local function vendorRowsText(value)
    return string.format(L.UI_VENDOR_ROW_COUNT, value)
end

local function toPercent(stored) return math.floor((stored or 1) * 100 + 0.5) end
local function fromPercent(value) return value / 100 end

local TOAST_OPACITY = { key = "toastOpacity", minimum = 20, maximum = 100, step = 5,
    labelKey = "UI_TOAST_OPACITY", formatter = percentText, show = toPercent, store = fromPercent }
local TOAST_LIFETIME = { key = "toastLifetime", minimum = 1, maximum = 20, step = 1,
    labelKey = "UI_TOAST_LIFETIME", formatter = secondsText }
local TOAST_ROWS = { key = "toastMaxRows", minimum = 1, maximum = 10, step = 1,
    labelKey = "UI_TOAST_MAX_ROWS", formatter = rowsText }
local TOAST_SCALE = { key = "toastScale", minimum = 70, maximum = 150, step = 5,
    labelKey = "UI_TOAST_SCALE", formatter = percentText, show = toPercent, store = fromPercent }
local FARM_OPACITY = { key = "farmOpacity", minimum = 20, maximum = 100, step = 5,
    labelKey = "UI_FARM_OPACITY", formatter = percentText, show = toPercent, store = fromPercent }
-- Whole minutes, because "pause after 137 seconds" is not a thing anyone wants to choose.
local FARM_IDLE = { key = "farmIdleSeconds", minimum = 1, maximum = 60, step = 1,
    labelKey = "UI_FARM_IDLE", formatter = minutesText,
    show = function(stored) return math.floor((stored or 180) / SECONDS_PER_MINUTE) end,
    store = function(value) return value * SECONDS_PER_MINUTE end }
-- The same caps the merchant grid builds its cell pool to and Settings validates.
local VENDOR_COLUMNS = { key = "vendorColumns", minimum = 2, maximum = 5, step = 1,
    labelKey = "UI_VENDOR_COLUMNS", formatter = columnsText }
local VENDOR_ROWS = { key = "vendorRows", minimum = 2, maximum = 8, step = 1,
    labelKey = "UI_VENDOR_ROWS", formatter = vendorRowsText }
-- Automatic is the whole chain in order. The rest name one provider and stay on it, which
-- is what a player with two price addons installed and an opinion is asking for.
local function learnedCount()
    local count = 0
    for _, entries in pairs(Settings:GetOption("gossipLearned") or {}) do
        for _ in pairs(entries) do
            count = count + 1
        end
    end
    return count
end

-- Applies on click, re-reads through LoadDisplay, and puts its own label into what a search
-- over the block can match, so a setting is reachable without knowing which feature owns it.
function UI:OptionCheckbox(block, key, labelKey, y)
    local box = Theme:Checkbox(block, 300, L[labelKey], function(widget)
        Settings:SetOption(key, widget:GetChecked() == true)
        self:LoadDisplay()
    end)
    box:SetPoint("TOPLEFT", 0, y)
    box.optionKey = key
    block:Index(L[labelKey])
    self.displayToggles[#self.displayToggles + 1] = box
    return box
end

-- Undo sits on the slider itself and is shown only while the value differs from the
-- shipped default, the same rule the feature rows follow.
function UI:OptionSlider(block, spec, y)
    local slider = Theme:Slider(block, SLIDER_WIDTH, spec.minimum, spec.maximum, spec.step,
        function(value)
            Settings:SetOption(spec.key, spec.store and spec.store(value) or value)
            self:LoadDisplay()
        end)
    slider:SetPoint("TOPLEFT", 0, y)
    slider:SetLabel(L[spec.labelKey], spec.formatter)
    slider.spec = spec
    slider.onUndo = function()
        Settings:SetOption(spec.key, Settings.optionDefaults[spec.key])
        self:LoadDisplay()
    end
    block:Index(L[spec.labelKey])
    self.optionSliders[#self.optionSliders + 1] = slider
    return slider
end

-- Entries are built from locale keys once here, so a builder names choices the same way it
-- names anything else and no user-facing string is spelled out in this file.
function UI:OptionDropdown(block, key, entries, labelKey, y)
    local list = {}
    for index, entry in ipairs(entries) do
        local text = L[entry.labelKey]
        list[index] = { value = entry.value,
            text = entry.quality and (qualitySwatch(entry.quality) .. text) or text }
        -- Indexed by the words alone: a search matches the name, never the escape.
        block:Index(text)
    end
    local dropdown = Theme:Dropdown(block, SLIDER_WIDTH, list,
        function(value) return Settings:GetOption(key) == value end,
        function(value)
            Settings:SetOption(key, value)
            self:LoadDisplay()
        end)
    dropdown:SetPoint("TOPLEFT", 0, y)
    dropdown:SetLabel(L[labelKey])
    dropdown.optionKey, dropdown.entryList = key, list
    block:Index(L[labelKey])
    self.optionDropdowns[#self.optionDropdowns + 1] = dropdown
    return dropdown
end

-- What a dropdown shows when closed: the text of whichever entry matches the stored value.
function UI:DropdownText(dropdown)
    local stored = Settings:GetOption(dropdown.optionKey)
    for _, entry in ipairs(dropdown.entryList) do
        if entry.value == stored then return entry.text end
    end
    return dropdown.entryList[1] and dropdown.entryList[1].text or ""
end

function UI:BuildToastSettings(parent)
    local toasts = self.Widgets:SettingsBlock(parent, L.UI_TOAST_MOVE_HELP)
    local top = toasts.top
    self.toastQualityDropdown = self:OptionDropdown(toasts, "toastMinQuality", QUALITY_ENTRIES,
        "UI_TOAST_QUALITY", top)
    local sliders = top - 36
    self.toastOpacitySlider = self:OptionSlider(toasts, TOAST_OPACITY, sliders)
    self.toastLifetimeSlider = self:OptionSlider(toasts, TOAST_LIFETIME, sliders - SLIDER_STEP)
    self.toastRowsSlider = self:OptionSlider(toasts, TOAST_ROWS, sliders - SLIDER_STEP * 2)
    self.toastScaleSlider = self:OptionSlider(toasts, TOAST_SCALE, sliders - SLIDER_STEP * 3)
    local boxes = sliders - SLIDER_STEP * 4 - 8
    self:OptionCheckbox(toasts, "toastShowPrice", "UI_TOAST_PRICE", boxes)
    self:OptionCheckbox(toasts, "toastShowSource", "UI_TOAST_SOURCE", boxes - 32)
    self:OptionCheckbox(toasts, "toastAggregate", "UI_TOAST_AGGREGATE", boxes - 64)
    self:OptionCheckbox(toasts, "toastGold", "UI_TOAST_GOLD", boxes - 96)
    self:OptionCheckbox(toasts, "toastCurrency", "UI_TOAST_CURRENCY", boxes - 128)
    toasts:SetBodyHeight(top - (boxes - 128) + 26)
    self:RegisterModuleSettings("toasts.loot", toasts)
end

function UI:BuildFarmSettings(parent)
    local farm = self.Widgets:SettingsBlock(parent, L.UI_FARM_HELP)
    local top = farm.top
    self:OptionCheckbox(farm, "farmShowHud", "UI_FARM_SHOW", top)
    self:OptionCheckbox(farm, "farmLocked", "UI_FARM_LOCKED", top - 32)
    self:OptionCheckbox(farm, "farmShowMeter", "UI_FARM_METER", top - 64)
    self:OptionCheckbox(farm, "farmExpand", "UI_FARM_EXPAND", top - 96)
    self:OptionCheckbox(farm, "farmShowRates", "UI_FARM_RATES", top - 128)
    self.farmOpacitySlider = self:OptionSlider(farm, FARM_OPACITY, top - 164)
    self.farmIdleSlider = self:OptionSlider(farm, FARM_IDLE, top - 164 - SLIDER_STEP)
    local goal = top - 164 - SLIDER_STEP * 2 - 4
    local goalLabel = Theme:Text(farm, L.UI_FARM_GOAL_HELP, "small", "TEXT_MUTED")
    goalLabel:SetPoint("TOPLEFT", 0, goal)
    goalLabel:SetPoint("RIGHT")
    farm:Index(L.UI_FARM_GOAL_HELP)
    self.farmGoal = self.Widgets:Input(farm, 120, 26)
    self.farmGoal:SetPoint("TOPLEFT", 0, goal - 16)
    local saveGoal = Theme:Button(farm, 104, L.UI_SAVE_SHORT, function()
        local gold = tonumber(self.farmGoal:GetText())
        if gold and Settings:SetOption("farmGoalGold", math.floor(gold)) then
            self.farmStatus:SetText(L.UI_SAVED)
        else
            self.farmStatus:SetText(L.UI_FARM_GOAL_INVALID)
        end
        self.farmGoal:ClearFocus()
    end)
    saveGoal:SetPoint("LEFT", self.farmGoal, "RIGHT", 8, 0)
    self.farmStatus = Theme:Text(farm, "", "small", "TEXT_TITLE")
    self.farmStatus:SetPoint("LEFT", saveGoal, "RIGHT", 12, 0)
    self.farmStatus:SetPoint("RIGHT")
    farm:SetBodyHeight(top - goal + 42)
    self:RegisterModuleSettings("loot.farmSession", farm)
end

-- Price sources feed the toasts, the farm HUD, the vendor list and the tooltips alike, so
-- they belong to no single feature and sit in General with the other cross-cutting options.
function UI:BuildPriceControls(block, top)
    block:Index(L.UI_PRICE_OPTIONS)
    self:OptionCheckbox(block, "priceTSM", "UI_PRICE_TSM", top)
    self:OptionCheckbox(block, "priceAuctionator", "UI_PRICE_AUCTIONATOR", top - 32)
    self.priceSourceDropdown = self:OptionDropdown(block, "priceSource", PRICE_ENTRIES,
        "UI_FARM_SOURCE", top - 64)
    local tsmLabel = Theme:Text(block, L.UI_PRICE_TSM_STRING, "small", "TEXT_MUTED")
    tsmLabel:SetPoint("TOPLEFT", 0, top - 102)
    block:Index(L.UI_PRICE_TSM_STRING)
    self.tsmString = self.Widgets:Input(block, 200, 26)
    self.tsmString:SetPoint("TOPLEFT", 0, top - 118)
    local saveTSM = Theme:Button(block, 104, L.UI_SAVE_SHORT, function()
        if Settings:SetOption("tsmPriceString", self.tsmString:GetText()) then
            self.displayStatus:SetText(L.UI_SAVED)
        else
            self.displayStatus:SetText(L.UI_PRICE_STRING_INVALID)
        end
        self.tsmString:ClearFocus()
    end)
    saveTSM:SetPoint("LEFT", self.tsmString, "RIGHT", 8, 0)
    self.displayStatus = Theme:Text(block, "", "small", "TEXT_TITLE")
    self.displayStatus:SetPoint("LEFT", saveTSM, "RIGHT", 12, 0)
    self.displayStatus:SetPoint("RIGHT")
    self.priceNote = Theme:Text(block, "", "small", "TEXT_MUTED")
    self.priceNote:SetPoint("TOPLEFT", 0, top - 152)
    self.priceNote:SetPoint("RIGHT")
    self.priceNote:SetHeight(40)
    self.priceNote:SetJustifyV("TOP")
    return 192
end

function UI:BuildVendorListSettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_VENDOR_HELP)
    local top = block.top
    self.vendorColumnsSlider = self:OptionSlider(block, VENDOR_COLUMNS, top)
    self.vendorRowsSlider = self:OptionSlider(block, VENDOR_ROWS, top - SLIDER_STEP)
    block:SetBodyHeight(SLIDER_STEP * 2)
    self:RegisterModuleSettings("vendor.extendedUI", block)
end

function UI:BuildQuestSettings(parent)
    local quests = self.Widgets:SettingsBlock(parent)
    self:OptionCheckbox(quests, "questAcceptLists", "UI_QUEST_LISTS", quests.top)
    self:OptionCheckbox(quests, "questAcceptItemsOnly", "UI_QUEST_ITEMS_ONLY", quests.top - 32)
    quests:SetBodyHeight(58)
    self:RegisterModuleSettings("quest.autoAccept", quests)
end

function UI:BuildResurrectSettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_RESURRECT_HELP)
    local top = block.top
    self:OptionCheckbox(block, "resurrectPvp", "UI_RESURRECT_PVP", top)
    self:OptionCheckbox(block, "resurrectInstance", "UI_RESURRECT_INSTANCE", top - 32)
    self:OptionCheckbox(block, "resurrectWorld", "UI_RESURRECT_WORLD", top - 64)
    block:SetBodyHeight(90)
    self:RegisterModuleSettings("social.acceptResurrect", block)
end

function UI:BuildQuickInviteSettings(parent)
    local block = self.Widgets:SettingsBlock(parent, L.UI_QUICKINVITE_HELP)
    self.inviteModifierDropdown = self:OptionDropdown(block, "inviteModifier", MODIFIER_ENTRIES,
        "UI_QUICKINVITE_MODIFIER", block.top)
    block:SetBodyHeight(36)
    self:RegisterModuleSettings("social.quickInvite", block)
end

function UI:BuildGossipSettings(parent)
    local gossip = self.Widgets:SettingsBlock(parent, L.UI_GOSSIP_HELP)
    local top = gossip.top
    self:OptionCheckbox(gossip, "gossipOpenQuests", "UI_GOSSIP_QUESTS", top)
    self:OptionCheckbox(gossip, "gossipOpenServices", "UI_GOSSIP_SERVICES", top - 32)
    self:OptionCheckbox(gossip, "gossipSkipDialogue", "UI_GOSSIP_DIALOGUE", top - 64)
    self:OptionCheckbox(gossip, "gossipInInstances", "UI_GOSSIP_INSTANCES", top - 96)
    self.gossipLearnDropdown = self:OptionDropdown(gossip, "gossipLearnModifier", MODIFIER_ENTRIES,
        "UI_GOSSIP_LEARN_MODIFIER", top - 130)
    self.gossipForgetButton = Theme:Button(gossip, 300, "", function()
        Settings:SetOption("gossipLearned", {})
        self:LoadDisplay()
    end)
    self.gossipForgetButton:SetPoint("TOPLEFT", 0, top - 166)
    gossip:SetBodyHeight(192)
    self:RegisterModuleSettings("quest.autoGossip", gossip)
end

function UI:LoadDisplay()
    if not self.toastQualityDropdown then return end
    for _, dropdown in ipairs(self.optionDropdowns) do
        dropdown:SetValueText(self:DropdownText(dropdown))
    end
    for _, slider in ipairs(self.optionSliders) do
        local spec = slider.spec
        local stored = Settings:GetOption(spec.key)
        slider:SetValue(spec.show and spec.show(stored) or stored)
        slider.undo:SetShown(stored ~= Settings.optionDefaults[spec.key])
    end
    if not self.farmGoal:HasFocus() then
        self.farmGoal:SetText(tostring(Settings:GetOption("farmGoalGold") or 0))
    end
    if not self.tsmString:HasFocus() then self.tsmString:SetText(Settings:GetOption("tsmPriceString") or "") end
    self.gossipForgetButton.label:SetText(string.format(L.UI_GOSSIP_FORGET, learnedCount()))
    local integrations = R.Integrations or {}
    self.priceNote:SetText(string.format(L.UI_PRICE_NOTE,
        integrations.tsmAvailable and L.UI_PRICE_FOUND or L.UI_PRICE_MISSING,
        integrations.auctionatorAvailable and L.UI_PRICE_FOUND or L.UI_PRICE_MISSING))
    for _, box in ipairs(self.displayToggles) do
        box:SetChecked(Settings:GetOption(box.optionKey) == true)
    end
end
