-- Refactor Addon - Speed Display Module
-- Displays real-time character movement speed near the player frame

local addonName, addon = ...
local L = addon.L

local Module = addon:NewModule("SpeedDisplay", {
    settingKey = "SpeedDisplay"
})

----------------------------------------------
-- Constants
----------------------------------------------
local BASE_SPEED = 7        -- Base walking speed in yards per second (100%)
local UPDATE_INTERVAL = 0.1 -- Update every 0.1 seconds

----------------------------------------------
-- Module State
----------------------------------------------
local speedFrame = nil
local speedTicker = nil

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

    return speedFrame
end

----------------------------------------------
-- Lifecycle
----------------------------------------------
function Module:OnEnable()
    -- Ensure frame exists
    speedFrame = CreateSpeedFrame()

    -- Initial update
    local percent = GetSpeedPercent()
    speedFrame.text:SetText(FormatSpeed(percent))

    -- Start ticker
    if not speedTicker then
        speedTicker = C_Timer.NewTicker(UPDATE_INTERVAL, function()
            if speedFrame and speedFrame:IsShown() then
                local pct = GetSpeedPercent()
                speedFrame.text:SetText(FormatSpeed(pct))
            end
        end)
    end

    speedFrame:Show()
end

function Module:OnDisable()
    if speedTicker then
        speedTicker:Cancel()
        speedTicker = nil
    end

    if speedFrame then
        speedFrame:Hide()
    end
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    -- Refresh display when decimals setting changes
    addon.CallbackRegistry:Register("SettingChanged.SpeedDisplay_Decimals", function()
        if self.isEnabled and speedFrame then
            local percent = GetSpeedPercent()
            speedFrame.text:SetText(FormatSpeed(percent))
        end
    end)
end
