local _, R = ...
local Theme = R.Theme
local UI = R.UI

-- Low on the rim and clear of LibDBIcon's own 225, so a button not gathered yet never sits on
-- top of this one.
local DEFAULT_ANGLE = 200
-- Over the minimap, the objective tracker and whatever docks beside them, under dialogs.
local DRAWER_STRATA = "HIGH"
local DRAWER_GAP = 2
-- Blizzard's menus appear at once; a tenth of a second of fade is the least that still reads
-- as the drawer opening rather than as something popping in.
local OPEN_FADE = 0.12
local POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- Kept per character, as the angle of Refactor's own button is.
local function saved()
    local character = R.Settings.character
    if not character then
        return nil
    end
    character.minimapButtons = type(character.minimapButtons) == "table" and character.minimapButtons or {}
    return character.minimapButtons
end

-- The drawer opens away from the nearest screen edges: below a button in the top half, and
-- leftwards from one in the right half, its edge flush with the button's. Coordinates are in
-- UIParent's units; without a screen rect it opens down and left, the minimap's usual corner.
function UI.MinimapDrawerCorner(x, y, width, height)
    local below, leftward = true, true
    if x and y and width and height then
        below = y > height / 2
        leftward = x > width / 2
    end
    local side = leftward and "RIGHT" or "LEFT"
    if below then
        return "TOP" .. side, "BOTTOM" .. side, -DRAWER_GAP, leftward
    end
    return "BOTTOM" .. side, "TOP" .. side, DRAWER_GAP, leftward
end

function UI:LibDBIcon()
    return LibStub and LibStub("LibDBIcon-1.0", true) or nil
end

local Collector = {}
Collector.__index = Collector

local function orbit(button)
    local angle = UI:MinimapCursorAngle(button)
    local store = saved()
    if store then
        store.angle = angle
    end
    UI:PlaceOnMinimapRim(button, angle)
end

-- Where the button's centre is, in UIParent's units, or nil before it has a screen rect.
function Collector:ScreenCenter()
    local x, y = self.button:GetCenter()
    if not x or not y then
        return nil
    end
    local scale = self.button:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * scale, y * scale
end

-- On the rim the button is a child of the minimap, so it moves, scales and fades with it like
-- every other minimap button. Free, it is a child of UIParent at the spot it was dragged to.
function Collector:Place(attached)
    local button, store = self.button, saved() or {}
    local x, y = self:ScreenCenter()
    self.attached = attached
    button:ClearAllPoints()
    if attached then
        button:SetParent(Minimap)
        button:SetFrameStrata("MEDIUM")
        button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
        UI:PlaceOnMinimapRim(button, type(store.angle) == "number" and store.angle or DEFAULT_ANGLE)
        return
    end
    button:SetParent(UIParent)
    button:SetFrameStrata("MEDIUM")
    if POINTS[store.point] and POINTS[store.relativePoint] and type(store.x) == "number"
        and type(store.y) == "number" then
        button:SetPoint(store.point, UIParent, store.relativePoint, store.x, store.y)
    elseif x then
        -- The first time it comes off the rim it stays where it was, rather than jumping.
        button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        self:SaveFree()
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function Collector:SaveFree()
    local store = saved()
    local point, _, relativePoint, x, y = self.button:GetPoint(1)
    if store and POINTS[point] and POINTS[relativePoint] and type(x) == "number" and type(y) == "number" then
        store.point, store.relativePoint, store.x, store.y = point, relativePoint, x, y
    end
end

-- Dragging round the rim is the one thing here that animates, so it takes an OnUpdate for
-- the length of the drag. Free dragging is the client's own StartMoving.
function Collector:StartDrag()
    if GameTooltip then
        GameTooltip:Hide()
    end
    self.button:LockHighlight()
    if self.attached then
        self.button:SetScript("OnUpdate", orbit)
    else
        self.button:StartMoving()
    end
end

function Collector:StopDrag()
    self.button:SetScript("OnUpdate", nil)
    if not self.attached then
        self.button:StopMovingOrSizing()
        self:SaveFree()
    end
    if self:IsOpen() then
        self:Anchor()
    else
        self.button:UnlockHighlight()
    end
end

function Collector:Corner()
    local x, y = self:ScreenCenter()
    return UI.MinimapDrawerCorner(x, y, UIParent:GetWidth(), UIParent:GetHeight())
end

-- The drawer hangs from UIParent, so a minimap faded by UI visibility does not fade it with it;
-- it takes the button's scale, so a gathered button is the size it was on the rim.
function Collector:Anchor()
    local point, relativePoint, offset = self:Corner()
    self.drawer:SetScale(self.button:GetEffectiveScale() / UIParent:GetEffectiveScale())
    self.drawer:ClearAllPoints()
    self.drawer:SetPoint(point, self.button, relativePoint, 0, offset)
end

-- The grid's size, without the panel's own padding. An empty drawer says so instead.
function Collector:Resize(width, height)
    local inset = Theme.drawerInsets
    local empty = width <= 0 or height <= 0
    self.empty:SetShown(empty)
    if empty then
        width, height = self.empty:GetStringWidth(), self.empty:GetStringHeight()
    end
    self.drawer:SetSize(width + inset.left + inset.right, height + inset.top + inset.bottom)
end

function Collector:IsOpen()
    return self.drawer:IsShown()
end

function Collector:IsMouseOver()
    return self.drawer:IsMouseOver() or self.button:IsMouseOver()
end

function Collector:Open()
    if GameTooltip then
        GameTooltip:Hide()
    end
    self:Anchor()
    self.drawer:Show()
    self.fader:Snap(0)
    self.fader:To(1)
    self.button:LockHighlight()
end

function Collector:Close()
    self.fader:Snap(0)
    self.drawer:Hide()
    self.button:UnlockHighlight()
end

function Collector:SetShown(shown)
    if not shown then
        self:Close()
    end
    self.button:SetShown(shown)
end

function Collector:ShowTooltip()
    if not GameTooltip or self:IsOpen() then
        return
    end
    local L, colors = R.L, Theme.colors
    local _, _, _, leftward = self:Corner()
    GameTooltip:SetOwner(self.button, leftward and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.MINIMAP_BUTTONS_TITLE)
    local count = self.count or 0
    local text = count == 0 and L.MINIMAP_BUTTONS_NONE or count == 1 and L.MINIMAP_BUTTONS_ONE
        or string.format(L.MINIMAP_BUTTONS_MANY, count)
    local body, muted = colors.TEXT_BODY, colors.TEXT_MUTED
    GameTooltip:AddLine(text, body[1], body[2], body[3])
    GameTooltip:AddLine(self.attached and L.MINIMAP_BUTTONS_HINT_RIM or L.MINIMAP_BUTTONS_HINT_FREE,
        muted[1], muted[2], muted[3], true)
    GameTooltip:Show()
end

-- Built once, at the module's first enable, and kept: the button, and the drawer the gathered
-- buttons are parented to. Clicks go back to the module, which owns what is in the drawer.
function UI:CreateMinimapCollector(owner)
    local button = Theme:MinimapIconButton(Minimap, "collectorIcon")
    button:SetClampedToScreen(true)
    local drawer = CreateFrame("Frame", nil, UIParent)
    drawer:SetFrameStrata(DRAWER_STRATA)
    drawer:SetClampedToScreen(true)
    -- A click between two buttons lands on the drawer, not on the world behind it.
    drawer:EnableMouse(true)
    Theme:Drawer(drawer)
    local inset = Theme.drawerInsets
    local content = CreateFrame("Frame", nil, drawer)
    content:SetPoint("TOPLEFT", inset.left, -inset.top)
    content:SetPoint("BOTTOMRIGHT", -inset.right, inset.bottom)
    local empty = Theme:Text(content, R.L.MINIMAP_BUTTONS_EMPTY, "small", "TEXT_MUTED")
    empty:SetPoint("TOPLEFT")
    drawer:Hide()
    local collector = setmetatable({
        owner = owner, button = button, drawer = drawer, content = content, empty = empty,
        strata = DRAWER_STRATA, fader = Theme:Fader(drawer, OPEN_FADE, OPEN_FADE), count = 0,
    }, Collector)
    button:SetScript("OnClick", function()
        if owner.state == "enabled" then
            R:SafeCall(owner, owner.Toggle, "minimap buttons")
        end
    end)
    button:SetScript("OnEnter", function() collector:ShowTooltip() end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    button:SetScript("OnDragStart", function() collector:StartDrag() end)
    button:SetScript("OnDragStop", function() collector:StopDrag() end)
    return collector
end
