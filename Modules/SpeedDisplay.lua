-- Refactor Addon - Speed Display Module
-- Displays real-time character movement speed near the player frame

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Constants
----------------------------------------------
local BASE_SPEED = 7        -- Base walking speed in yards per second (100%)
local UPDATE_INTERVAL = 0.1 -- Update every 0.1 seconds

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false
local speedFrame = nil
local timeSinceLastUpdate = 0

----------------------------------------------
-- Speed Calculation
----------------------------------------------
local function GetSpeedPercent()
    local currentSpeed = GetUnitSpeed("player")
    if not currentSpeed then return 0 end
    return (currentSpeed / BASE_SPEED) * 100
end

local function FormatSpeed(percent)
    if addon.GetDBBool("SpeedDisplay_Decimals") then
        return string.format("%.1f%%", percent)
    else
        return string.format("%d%%", math.floor(percent + 0.5))
    end
end

----------------------------------------------
-- Frame Creation
----------------------------------------------
local function CreateSpeedFrame()
    if speedFrame then return speedFrame end

    speedFrame = CreateFrame("Frame", "RefactorSpeedDisplay", UIParent)
    speedFrame:SetSize(60, 20)
    speedFrame:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", 100, 10)
    speedFrame:SetFrameStrata("HIGH")

    -- Speed text
    speedFrame.text = speedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    speedFrame.text:SetPoint("CENTER")
    speedFrame.text:SetTextColor(1, 1, 1, 1)
    speedFrame.text:SetShadowOffset(1, -1)
    speedFrame.text:SetShadowColor(0, 0, 0, 1)

    -- Update handler with throttle
    speedFrame:SetScript("OnUpdate", function(self, elapsed)
        timeSinceLastUpdate = timeSinceLastUpdate + elapsed
        if timeSinceLastUpdate < UPDATE_INTERVAL then return end
        timeSinceLastUpdate = 0

        local percent = GetSpeedPercent()
        self.text:SetText(FormatSpeed(percent))
    end)

    return speedFrame
end

----------------------------------------------
-- Enable/Disable
----------------------------------------------
function Module:Enable()
    isEnabled = true

    -- Ensure frame exists
    speedFrame = CreateSpeedFrame()

    -- Initial update
    local percent = GetSpeedPercent()
    speedFrame.text:SetText(FormatSpeed(percent))

    speedFrame:Show()
end

function Module:Disable()
    isEnabled = false

    if speedFrame then
        speedFrame:Hide()
    end
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    if addon.GetDBBool("SpeedDisplay") then
        self:Enable()
    end

    addon.CallbackRegistry:Register("SettingChanged.SpeedDisplay", function(value)
        if value then
            Module:Enable()
        else
            Module:Disable()
        end
    end)

    -- Refresh display when decimals setting changes
    addon.CallbackRegistry:Register("SettingChanged.SpeedDisplay_Decimals", function()
        if isEnabled and speedFrame then
            local percent = GetSpeedPercent()
            speedFrame.text:SetText(FormatSpeed(percent))
        end
    end)
end

-- Register the module
addon.RegisterModule("SpeedDisplay", Module)
