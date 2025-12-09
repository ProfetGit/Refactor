-- Refactor Addon - Minimap Button
-- Draggable minimap button that opens settings

local addonName, addon = ...
local L = addon.L

----------------------------------------------
-- Minimap Button Creation
----------------------------------------------
local MinimapButton = CreateFrame("Button", "RefactorMinimapButton", Minimap)
addon.MinimapButton = MinimapButton

MinimapButton:SetSize(32, 32)
MinimapButton:SetFrameStrata("MEDIUM")
MinimapButton:SetFrameLevel(8)
MinimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
MinimapButton:SetMovable(true)
MinimapButton:EnableMouse(true)
MinimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
MinimapButton:RegisterForDrag("LeftButton")

-- Icon
MinimapButton.icon = MinimapButton:CreateTexture(nil, "ARTWORK")
MinimapButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
MinimapButton.icon:SetSize(20, 20)
MinimapButton.icon:SetPoint("CENTER")

-- Border
MinimapButton.border = MinimapButton:CreateTexture(nil, "OVERLAY")
MinimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
MinimapButton.border:SetSize(56, 56)
MinimapButton.border:SetPoint("TOPLEFT")

-- Background (for pushed state)
MinimapButton.background = MinimapButton:CreateTexture(nil, "BACKGROUND")
MinimapButton.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
MinimapButton.background:SetSize(24, 24)
MinimapButton.background:SetPoint("CENTER")

----------------------------------------------
-- Position Management
----------------------------------------------

-- Minimap shape definitions for proper positioning
-- https://wowwiki-archive.fandom.com/wiki/USERAPI_GetMinimapShape
local minimapShapes = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function GetButtonPosition(angle, radius)
    local rad = math.rad(angle)
    local cos = math.cos(rad)
    local sin = math.sin(rad)

    -- Determine which quadrant we're in (1-4)
    local q = 1
    if cos < 0 then q = q + 1 end
    if sin > 0 then q = q + 2 end

    local width = (Minimap:GetWidth() / 2) + radius
    local height = (Minimap:GetHeight() / 2) + radius

    -- Check minimap shape and adjust positioning accordingly
    local minimapShape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local shapeTable = minimapShapes[minimapShape] or minimapShapes["ROUND"]

    local x, y
    if shapeTable[q] then
        -- Circular positioning for this quadrant
        x = cos * width
        y = sin * height
    else
        -- Square positioning - clamp to edges
        local diagRadius = math.sqrt(2 * width ^ 2) - 10
        x = math.max(-width, math.min(cos * diagRadius, width))
        y = math.max(-height, math.min(sin * diagRadius, height))
    end

    return x, y
end

local function UpdatePosition()
    local angle = addon.GetDBValue("MinimapButtonAngle") or 220
    local x, y = GetButtonPosition(angle, 5)

    MinimapButton:ClearAllPoints()
    MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

----------------------------------------------
-- Dragging
----------------------------------------------
local isDragging = false
local hasDragged = false

local function OnUpdate(self)
    local minimapScale = Minimap:GetEffectiveScale()
    local minimapX, minimapY = Minimap:GetCenter()

    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / minimapScale
    cursorY = cursorY / minimapScale

    -- Calculate angle using atan2 and normalize to 0-360
    local angle = math.deg(math.atan2(cursorY - minimapY, cursorX - minimapX)) % 360

    -- Update button position
    local x, y = GetButtonPosition(angle, 5)
    self:ClearAllPoints()
    self:SetPoint("CENTER", Minimap, "CENTER", x, y)

    -- Store the angle for saving
    self.currentAngle = angle
    hasDragged = true
end

MinimapButton:SetScript("OnDragStart", function(self)
    isDragging = true
    hasDragged = false
    self:LockHighlight()
    self:SetScript("OnUpdate", OnUpdate)
end)

MinimapButton:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)

    if hasDragged and self.currentAngle then
        addon.SetDBValue("MinimapButtonAngle", self.currentAngle)
    end

    isDragging = false
    -- Delay resetting hasDragged so OnClick can check it
    C_Timer.After(0.01, function()
        hasDragged = false
    end)
end)

----------------------------------------------
-- Click Handlers
----------------------------------------------
MinimapButton:SetScript("OnClick", function(self, button)
    -- Ignore clicks if we just finished dragging
    if hasDragged then
        return
    end

    if button == "LeftButton" then
        -- Open settings
        if addon.SettingsPanel then
            addon.SettingsPanel:Toggle()
        end
    elseif button == "RightButton" then
        -- Quick toggle menu (future feature)
        if addon.SettingsPanel then
            addon.SettingsPanel:Toggle()
        end
    end
end)

----------------------------------------------
-- Tooltip
----------------------------------------------
MinimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(L.ADDON_NAME, 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff00ff00Left-click|r to open settings", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff00ff00Right-click|r to open settings", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff00ff00Drag|r to move this button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

MinimapButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

----------------------------------------------
-- Push Effect
----------------------------------------------
MinimapButton:SetScript("OnMouseDown", function(self)
    self.icon:SetPoint("CENTER", 1, -1)
end)

MinimapButton:SetScript("OnMouseUp", function(self)
    self.icon:SetPoint("CENTER", 0, 0)
end)

----------------------------------------------
-- Show/Hide Toggle
----------------------------------------------
function addon.ToggleMinimapButton(show)
    if show then
        MinimapButton:Show()
    else
        MinimapButton:Hide()
    end
    addon.SetDBValue("MinimapButtonHidden", not show)
end

----------------------------------------------
-- Initialization
----------------------------------------------
addon.CallbackRegistry:Register("AddonLoaded", function()
    -- Set initial position
    UpdatePosition()

    -- Check if hidden
    if addon.GetDBBool("MinimapButtonHidden") then
        MinimapButton:Hide()
    else
        MinimapButton:Show()
    end
end)
