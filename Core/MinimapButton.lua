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
local function UpdatePosition()
    local angle = addon.GetDBValue("MinimapButtonAngle") or 220
    local radius = 100

    local x = math.cos(math.rad(angle)) * radius
    local y = math.sin(math.rad(angle)) * radius

    MinimapButton:ClearAllPoints()
    MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function SavePosition()
    local mx, my = Minimap:GetCenter()
    local bx, by = MinimapButton:GetCenter()
    local angle = math.deg(math.atan(by - my, bx - mx))

    addon.SetDBValue("MinimapButtonAngle", angle)
end

----------------------------------------------
-- Dragging
----------------------------------------------
local isDragging = false

MinimapButton:SetScript("OnDragStart", function(self)
    isDragging = true
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale

        local angle = math.deg(math.atan(cy - my, cx - mx))
        local radius = 100

        local x = math.cos(math.rad(angle)) * radius
        local y = math.sin(math.rad(angle)) * radius

        self:ClearAllPoints()
        self:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end)
end)

MinimapButton:SetScript("OnDragStop", function(self)
    isDragging = false
    self:SetScript("OnUpdate", nil)
    SavePosition()
end)

----------------------------------------------
-- Click Handlers
----------------------------------------------
MinimapButton:SetScript("OnClick", function(self, button)
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
