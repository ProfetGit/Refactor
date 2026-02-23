local addonName, addon = ...
local L = addon.L

local Module = addon:NewModule("CombatFade", {
    settingKey = "CombatFade"
})

-- Action Bar frame names
local actionBarFrameNames = {
    "MainActionBar",
    "MainMenuBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarRight",
    "MultiBarLeft",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
    "StanceBar",
    "PetActionBar",
    "PossessActionBar",
    "OverrideActionBar",
    "StatusTrackingBarManager",
}

-- Player Frame names
local playerFrameNames = {
    "PlayerFrame",
}

local actionBarObjects = {}
local playerFrameObjects = {}
local initialized = false

local eventFrame = CreateFrame("Frame")
local updateFrame = CreateFrame("Frame")
local FADE_IN_TIME = 0.2
local FADE_OUT_TIME = 0.2
local MOUSE_OVER_CHECK_INTERVAL = 0.05 -- 20 FPS for bounds checking

local targetBarAlpha = 1
local targetPlayerAlpha = 1
local currentBarAlpha = 1
local currentPlayerAlpha = 1

local inCombat = false
local timeSinceLastMouseCheck = 0

local cachedSettings = {
    moduleEnabled = false,
    actionBarsEnabled = false,
    playerFrameEnabled = false,
    actionBarMinAlpha = 0,
    playerFrameMinAlpha = 0,
}

local function UpdateCachedSettings()
    cachedSettings.moduleEnabled = addon.GetDBBool("CombatFade")
    cachedSettings.actionBarsEnabled = addon.GetDBBool("CombatFade_ActionBars")
    cachedSettings.playerFrameEnabled = addon.GetDBBool("CombatFade_PlayerFrame")
    cachedSettings.actionBarMinAlpha = (addon.GetDBValue("CombatFade_ActionBars_Opacity") or 0) / 100
    cachedSettings.playerFrameMinAlpha = (addon.GetDBValue("CombatFade_PlayerFrame_Opacity") or 0) / 100
end

local function IsAnyFrameMouseOver(frameList)
    for _, frame in ipairs(frameList) do
        -- Only bounds check frames that are actually shown and have proper bounding boxes
        if frame and frame:IsShown() and frame.IsMouseOver and frame:IsMouseOver() then
            return true
        end
    end
    -- Also natively check flyouts if ActionBars is true
    if frameList == actionBarObjects and SpellFlyout and SpellFlyout:IsShown() and SpellFlyout:IsMouseOver() then
        return true
    end
    return false
end

local function InitFrames()
    if initialized then return end

    actionBarObjects = {}
    playerFrameObjects = {}

    -- Only fetch what we know are safely sized parent frames (exclude tracking bar)
    for _, name in ipairs(actionBarFrameNames) do
        if name ~= "StatusTrackingBarManager" then
            local frame = _G[name]
            if frame then table.insert(actionBarObjects, frame) end
        end
    end

    for _, name in ipairs(playerFrameNames) do
        local frame = _G[name]
        if frame then table.insert(playerFrameObjects, frame) end
    end

    initialized = true
end

function Module:UpdateFadeState()
    if not initialized or not self.isEnabled then return end

    local settings = cachedSettings

    local mouseOverBars = false
    local mouseOverPlayer = false

    -- Optimization: Only bounds check if we actually need to
    if not inCombat then
        if settings.actionBarsEnabled then mouseOverBars = IsAnyFrameMouseOver(actionBarObjects) end
        if settings.playerFrameEnabled then mouseOverPlayer = IsAnyFrameMouseOver(playerFrameObjects) end
    end

    -- Action Bar Target Alpha Calculations
    targetBarAlpha = settings.actionBarMinAlpha
    if not settings.actionBarsEnabled or inCombat or mouseOverBars then
        targetBarAlpha = 1
    end

    -- Player Frame Target Alpha Calculations
    targetPlayerAlpha = settings.playerFrameMinAlpha
    if not settings.playerFrameEnabled or inCombat or mouseOverPlayer then
        targetPlayerAlpha = 1
    end
end

updateFrame:SetScript("OnUpdate", function(_, elapsed)
    if not initialized or not cachedSettings.moduleEnabled then return end

    -- Throttled Mouse Check (Only query bounds 20 times a second max)
    timeSinceLastMouseCheck = timeSinceLastMouseCheck + elapsed
    if timeSinceLastMouseCheck > MOUSE_OVER_CHECK_INTERVAL then
        timeSinceLastMouseCheck = 0
        Module:UpdateFadeState()
    end

    -- Smooth Interpolation (Fader Engine)
    local barDiff = targetBarAlpha - currentBarAlpha
    local playerDiff = targetPlayerAlpha - currentPlayerAlpha

    if math.abs(barDiff) > 0.001 then
        local duration = barDiff > 0 and FADE_IN_TIME or FADE_OUT_TIME
        currentBarAlpha = currentBarAlpha + (barDiff / duration * elapsed)

        -- Clamp logic
        if barDiff > 0 and currentBarAlpha > targetBarAlpha then currentBarAlpha = targetBarAlpha end
        if barDiff < 0 and currentBarAlpha < targetBarAlpha then currentBarAlpha = targetBarAlpha end

        for _, frame in ipairs(actionBarObjects) do
            -- Safe check: NEVER Show(), only touch Alpha if it's strictly > 0 via engine
            if currentBarAlpha > 0 or frame:GetAlpha() ~= currentBarAlpha then
                frame:SetAlpha(currentBarAlpha)
            end
        end
    end

    if math.abs(playerDiff) > 0.001 then
        local duration = playerDiff > 0 and FADE_IN_TIME or FADE_OUT_TIME
        currentPlayerAlpha = currentPlayerAlpha + (playerDiff / duration * elapsed)

        -- Clamp logic
        if playerDiff > 0 and currentPlayerAlpha > targetPlayerAlpha then currentPlayerAlpha = targetPlayerAlpha end
        if playerDiff < 0 and currentPlayerAlpha < targetPlayerAlpha then currentPlayerAlpha = targetPlayerAlpha end

        for _, frame in ipairs(playerFrameObjects) do
            if currentPlayerAlpha > 0 or frame:GetAlpha() ~= currentPlayerAlpha then
                frame:SetAlpha(currentPlayerAlpha)
            end
        end
    end
end)

function Module:ForceShow()
    if not initialized then InitFrames() end

    for _, frame in ipairs(actionBarObjects) do
        if frame.SetAlpha then frame:SetAlpha(1) end
    end

    for _, frame in ipairs(playerFrameObjects) do
        if frame.SetAlpha then frame:SetAlpha(1) end
    end

    currentBarAlpha = 1
    currentPlayerAlpha = 1
    targetBarAlpha = 1
    targetPlayerAlpha = 1
end

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        Module:UpdateFadeState()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        Module:UpdateFadeState()
    end
end)

function Module:OnEnable()
    UpdateCachedSettings()

    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    inCombat = InCombatLockdown and InCombatLockdown() or false

    C_Timer.After(1, function()
        if self.isEnabled then
            if not initialized then InitFrames() end
            Module:UpdateFadeState()
            updateFrame:Show()
        end
    end)
end

function Module:OnDisable()
    eventFrame:UnregisterAllEvents()
    updateFrame:Hide()
    self:ForceShow()
end

function Module:OnSettingChanged()
    if self.isEnabled then
        UpdateCachedSettings()
        Module:UpdateFadeState()
    end
end

function Module:OnInitialize()
    addon.CallbackRegistry:Register("SettingChanged.CombatFade_ActionBars", function() self:OnSettingChanged() end)
    addon.CallbackRegistry:Register("SettingChanged.CombatFade_PlayerFrame", function() self:OnSettingChanged() end)
    addon.CallbackRegistry:Register("SettingChanged.CombatFade_ActionBars_Opacity",
        function() self:OnSettingChanged() end)
    addon.CallbackRegistry:Register("SettingChanged.CombatFade_PlayerFrame_Opacity",
        function() self:OnSettingChanged() end)
end
