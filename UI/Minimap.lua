local _, R = ...
local Theme = R.Theme
local UI = R.UI

local BUTTON_SIZE, ICON_INSET, ORBIT_MARGIN = 31, 3, 5
local DEFAULT_ANGLE = 225

-- Match BugSack's LibDBIcon rim spacing while keeping the saved angle.
local function orbitRadius(parent)
    local width = parent:GetWidth()
    if type(width) ~= "number" or width <= 0 then
        width = 140
    end
    return width / 2 + ORBIT_MARGIN
end

local function saved()
    local character = R.Settings.character
    if not character then
        return nil
    end
    character.minimap = type(character.minimap) == "table" and character.minimap or {}
    return character.minimap
end

local function place(button, angle)
    local radians = math.rad(angle)
    local parent = button:GetParent()
    local radius = orbitRadius(parent)
    button:ClearAllPoints()
    button:SetPoint("CENTER", parent, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

-- Dragging is the one thing here that genuinely animates, so it takes an OnUpdate and
-- gives it back the moment the mouse is released.
local function drag(button)
    local x, y = GetCursorPosition()
    local scale = button:GetParent():GetEffectiveScale()
    local centerX, centerY = button:GetParent():GetCenter()
    local angle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX))
    local store = saved()
    if store then
        store.angle = angle
    end
    place(button, angle)
end

function UI:CreateMinimapButton()
    if self.minimapButton or not Minimap then
        return self.minimapButton
    end
    local button = Theme:MinimapButton(Minimap, BUTTON_SIZE, ICON_INSET)
    self.minimapButton = button
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            for _, line in ipairs(R.Commands:Dispatch("errors") or {}) do
                R:Print(line)
            end
        else
            self:Toggle()
        end
    end)
    button:SetScript("OnDragStart", function(widget)
        widget:SetScript("OnUpdate", drag)
    end)
    button:SetScript("OnDragStop", function(widget)
        widget:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(widget)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(widget, "ANCHOR_LEFT")
        GameTooltip:AddLine(R.L.UI_TITLE)
        GameTooltip:AddLine(R.L.UI_MINIMAP_HINT, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    self:RefreshMinimapButton()
    return button
end

function UI:RefreshMinimapButton()
    local button = self.minimapButton
    if not button then
        return
    end
    local store = saved()
    place(button, store and type(store.angle) == "number" and store.angle or DEFAULT_ANGLE)
    button:SetShown(R.Settings:GetOption("minimapButton") ~= false)
end
