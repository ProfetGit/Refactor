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

local MOUSE_OVER_CHECK_INTERVAL = 0.05 -- 20 FPS for bounds checking

local inCombat = false
local mouseCheckTimer = nil

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
            if frame then
                addon.Utils.MakeFadingObject(frame)
                table.insert(actionBarObjects, frame)
            end
        end
    end

    for _, name in ipairs(playerFrameNames) do
        local frame = _G[name]
        if frame then
            addon.Utils.MakeFadingObject(frame)
            table.insert(playerFrameObjects, frame)
        end
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
    if not settings.actionBarsEnabled or inCombat or mouseOverBars then
        for _, frame in ipairs(actionBarObjects) do
            if frame.FadeIn then frame:FadeIn() end
        end
    else
        for _, frame in ipairs(actionBarObjects) do
            if frame.FadeOut then
                frame:SetFadeOutAlpha(settings.actionBarMinAlpha)
                frame:FadeOut()
            end
        end
    end

    -- Player Frame Target Alpha Calculations
    if not settings.playerFrameEnabled or inCombat or mouseOverPlayer then
        for _, frame in ipairs(playerFrameObjects) do
            if frame.FadeIn then frame:FadeIn() end
        end
    else
        for _, frame in ipairs(playerFrameObjects) do
            if frame.FadeOut then
                frame:SetFadeOutAlpha(settings.playerFrameMinAlpha)
                frame:FadeOut()
            end
        end
    end
end

function Module:StartMouseCheck()
    if mouseCheckTimer then return end
    mouseCheckTimer = C_Timer.NewTicker(MOUSE_OVER_CHECK_INTERVAL, function()
        Module:UpdateFadeState()
    end)
end

function Module:StopMouseCheck()
    if mouseCheckTimer then
        mouseCheckTimer:Cancel()
        mouseCheckTimer = nil
    end
end

function Module:ForceShow()
    if not initialized then InitFrames() end

    for _, frame in ipairs(actionBarObjects) do
        if frame.SetAlpha then frame:SetAlpha(1) end
    end

    for _, frame in ipairs(playerFrameObjects) do
        if frame.SetAlpha then frame:SetAlpha(1) end
    end

end

Module.eventMap = {
    ["PLAYER_REGEN_DISABLED"] = function(self)
        inCombat = true
        self:UpdateFadeState()
    end,
    ["PLAYER_REGEN_ENABLED"] = function(self)
        inCombat = false
        self:UpdateFadeState()
    end
}

function Module:OnEnable()
    UpdateCachedSettings()

    inCombat = InCombatLockdown and InCombatLockdown() or false

    C_Timer.After(1, function()
        if self.isEnabled then
            if not initialized then InitFrames() end
            self:StartMouseCheck()
            self:UpdateFadeState()
        end
    end)
end

function Module:OnDisable()
    self:StopMouseCheck()
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
