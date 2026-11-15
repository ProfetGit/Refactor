local _, R = ...
local Theme = LibStub("LibRefactorTheme-1.0")

-- One layer of pins per kind (dungeons, travel, exits) over the world map's canvas. The pins
-- are plain buttons of ours, not Blizzard map pins, so they never enter the map's own pin
-- pools and need nothing from its secure code.
local MapPins = {}
R.UI.MapPins = MapPins

-- Blizzard puts every map pin at an absolute frame level from 2000 up to 9000 (its pin frame
-- levels manager), and the zone map's explored-area art is one of them, so a layer any lower
-- is painted over there while still taking the mouse. Ours sits just under the ceiling.
local MAX_PINS, PIN_SIZE, ARROW_SIZE, FRAME_LEVEL = 24, 22, 32, 8500
local layers = {}

local function onEnter(pin)
    local entry = pin.entry
    if not entry then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(entry.title)
    if type(entry.subtitle) == "string" and entry.subtitle ~= "" then
        GameTooltip:AddLine(entry.subtitle, nil, nil, nil, true)
    end
    if entry.mapID then
        GameTooltip:AddLine(R.L.MAP_PIN_CLICK_OPEN)
    end
    if entry.exit then
        GameTooltip:AddLine(R.L.MAP_PIN_EXIT_HINT)
    end
    GameTooltip:Show()
end

local function onLeave()
    GameTooltip:Hide()
end

-- Where a pin ended up, as a share of the map canvas. Frame coordinates are in the frame's own
-- scale, so both are brought to the screen's before they are compared.
local function dropPosition(pin)
    local canvas = WorldMapFrame:GetCanvas()
    local cx, cy = pin:GetCenter()
    local left, top = canvas:GetLeft(), canvas:GetTop()
    if not cx or not left or not top then
        return nil
    end
    local scale, canvasScale = pin:GetEffectiveScale(), canvas:GetEffectiveScale()
    local width, height = canvas:GetSize()
    local x = (cx * scale - left * canvasScale) / (width * canvasScale)
    local y = (top * canvasScale - cy * scale) / (height * canvasScale)
    return math.min(1, math.max(0, x)), math.min(1, math.max(0, y))
end

local function onClick(pin, button)
    local entry = pin.entry
    if pin.justMoved then
        pin.justMoved = nil
        return
    end
    if not entry then return end
    if button == "RightButton" then
        if entry.exit and IsControlKeyDown() then
            R.MapData:SetExit(entry.exit.from, entry.exit.to, nil)
        end
        return
    end
    if entry.mapID then
        WorldMapFrame:SetMapID(entry.mapID)
    end
end

-- The way out is a judgement the zone shapes only approximate, so an exit arrow can be moved
-- with shift and a drag, and put back with ctrl and a right click.
local function onDragStart(pin)
    if pin.entry and pin.entry.exit and IsShiftKeyDown() then
        GameTooltip:Hide()
        pin.dragging = true
        pin:StartMoving()
    end
end

local function onDragStop(pin)
    if not pin.dragging then return end
    pin.dragging = nil
    pin:StopMovingOrSizing()
    pin.justMoved = true
    local x, y = dropPosition(pin)
    local entry = pin.entry
    if x then
        R.MapData:SetExit(entry.exit.from, entry.exit.to, x, y)
    end
end

local function buildPin(parent)
    local pin = CreateFrame("Button", nil, parent)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin:SetScript("OnEnter", onEnter)
    pin:SetScript("OnLeave", onLeave)
    pin:SetScript("OnClick", onClick)
    pin:SetMovable(true)
    pin:RegisterForDrag("LeftButton")
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetScript("OnDragStart", onDragStart)
    pin:SetScript("OnDragStop", onDragStop)
    pin:Hide()
    return pin
end

local function resetPin(pin)
    pin:Hide()
    pin:ClearAllPoints()
    pin.entry = nil
end

-- Frames are made here, when a module is enabled, and never while the map is refreshing: the
-- pool is filled to its cap up front and entries past the cap are dropped.
function MapPins:Layer(kind)
    local layer = layers[kind]
    if layer then
        return layer
    end
    local canvas = WorldMapFrame:GetCanvas()
    local frame = CreateFrame("Frame", nil, canvas)
    frame:SetAllPoints(canvas)
    frame:SetFrameLevel(FRAME_LEVEL)
    layer = { frame = frame }
    layer.pins = R.Pools:Create(function() return buildPin(frame) end, resetPin)
    local warm = {}
    for index = 1, MAX_PINS do
        warm[index] = layer.pins:Acquire()
    end
    for index = 1, MAX_PINS do
        layer.pins:Release(warm[index])
    end
    layers[kind] = layer
    return layer
end

local function paint(pin, entry)
    local icon = pin.icon
    pin:SetSize(entry.rotation and ARROW_SIZE or PIN_SIZE, entry.rotation and ARROW_SIZE or PIN_SIZE)
    if entry.rotation then
        Theme:ApplyAsset(icon, "mapExitArrow")
        icon:SetRotation(entry.rotation)
    elseif entry.asset then
        icon:SetRotation(0)
        Theme:ApplyAsset(icon, entry.asset)
    elseif entry.atlas and C_Texture.GetAtlasInfo(entry.atlas) then
        icon:SetRotation(0)
        icon:SetAtlas(entry.atlas, false)
    else
        icon:SetRotation(0)
        Theme:ApplyAsset(icon, "mapPinFallback")
    end
end

local function place(layer, pin, entry, width, height, scale)
    pin:SetScale(scale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", layer.frame, "TOPLEFT", entry.x * width / scale, -entry.y * height / scale)
end

function MapPins:Set(kind, entries)
    local layer = self:Layer(kind)
    layer.pins:ReleaseAll()
    local canvas = WorldMapFrame:GetCanvas()
    local width, height = canvas:GetSize()
    -- Pins stay one size on screen however far the map is zoomed.
    local scale = 1 / WorldMapFrame:GetCanvasScale()
    layer.shown = {}
    for index, entry in ipairs(entries) do
        if index > MAX_PINS then break end
        local pin = layer.pins:Acquire()
        pin.entry = entry
        paint(pin, entry)
        place(layer, pin, entry, width, height, scale)
        pin:Show()
        layer.shown[#layer.shown + 1] = pin
    end
    layer.frame:Show()
end

function MapPins:Clear(kind)
    local layer = layers[kind]
    if layer then
        layer.pins:ReleaseAll()
        layer.shown = nil
        layer.frame:Hide()
    end
end

function MapPins:Rescale()
    local canvas = WorldMapFrame:GetCanvas()
    local width, height = canvas:GetSize()
    local scale = 1 / WorldMapFrame:GetCanvasScale()
    for _, layer in pairs(layers) do
        for _, pin in ipairs(layer.shown or {}) do
            place(layer, pin, pin.entry, width, height, scale)
        end
    end
end

-- The map redraws its own pins from these two calls, so a post-hook on each keeps ours in
-- step without an event of our own. Hooks cannot be removed, so each checks the module is on.
function MapPins:Attach(module, kind, collect)
    self:Layer(kind)
    local function refresh()
        if module.state == "enabled" then
            R:SafeCall(module, function() self:Refresh(module, kind, collect) end, "map pins")
        end
    end
    module.refreshPins = refresh
    if not module.pinHooksInstalled then
        module.pinHooksInstalled = true
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function() module.refreshPins() end)
        hooksecurefunc(WorldMapFrame, "RefreshAllDataProviders", function() module.refreshPins() end)
        hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function()
            if module.state == "enabled" then self:Rescale() end
        end)
    end
    if WorldMapFrame:IsShown() then
        refresh()
    end
end

function MapPins:Refresh(module, kind, collect)
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then
        return self:Clear(kind)
    end
    local entries = collect(module, mapID)
    if #entries == 0 then
        return self:Clear(kind)
    end
    self:Set(kind, entries)
end

function MapPins:Detach(kind)
    self:Clear(kind)
end
