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

-- Left opens the window; right goes straight to Diagnostics, where a problem is explained
-- instead of printed. Shared by the minimap button and any broker display.
function UI:LauncherClick(mouseButton)
    if mouseButton == "RightButton" then
        self:OpenPanel("Diagnostics")
    else
        self:Toggle()
    end
end

-- What the launcher tooltip says: the name, how many features run here, recorded errors when
-- there are any, and the two clicks.
function UI:LauncherTooltip(tooltip)
    local on = 0
    for _, module in ipairs(R.modules) do
        if module.state == "enabled" then on = on + 1 end
    end
    tooltip:AddLine(R.L.UI_TITLE)
    local body, muted = Theme.colors.TEXT_BODY, Theme.colors.TEXT_MUTED
    tooltip:AddLine(string.format(R.L.UI_LAUNCHER_ON, on, #R.modules), body[1], body[2], body[3])
    if #R.errors > 0 then
        local warn = Theme.colors.TEXT_WARNING
        tooltip:AddLine(string.format(R.L.UI_LAUNCHER_ERRORS, #R.errors), warn[1], warn[2], warn[3])
    end
    tooltip:AddLine(R.L.UI_MINIMAP_HINT, muted[1], muted[2], muted[3], true)
end

-- Broker displays (Titan Panel, ChocolateBar, ElvUI's datatexts) get the same launcher when
-- another addon has already loaded LibDataBroker. Refactor does not embed it.
function UI:RegisterBroker()
    local broker = LibStub("LibDataBroker-1.1", true)
    if not broker or self.brokerObject then return end
    self.brokerObject = broker:NewDataObject(R.name, {
        type = "launcher", icon = Theme.icons.app, label = R.L.UI_TITLE,
        OnClick = function(_, mouseButton) self:LauncherClick(mouseButton) end,
        OnTooltipShow = function(tooltip) self:LauncherTooltip(tooltip) end,
    })
end

function UI:CreateMinimapButton()
    if self.minimapButton or not Minimap then
        return self.minimapButton
    end
    local button = Theme:MinimapButton(Minimap, BUTTON_SIZE, ICON_INSET)
    self.minimapButton = button
    button:SetScript("OnClick", function(_, mouseButton) self:LauncherClick(mouseButton) end)
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
        self:LauncherTooltip(GameTooltip)
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
