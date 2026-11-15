--- @module interface.minimapButtons
--- Purpose: gather the addon buttons around the minimap into one button, on the rim or anywhere on screen.
--- Requires: Minimap, issecurevariable, InCombatLockdown
--- Events: PLAYER_ENTERING_WORLD, ADDON_LOADED, REFACTOR_SETTINGS_CHANGED and LibDBIcon's IconCreated callback;
---     GLOBAL_MOUSE_DOWN only while the drawer is open, PLAYER_REGEN_ENABLED only while a gather waits out combat.
--- Hot: no
local _, R = ...
local MinimapButtons = R:RegisterModule({
    id = "interface.minimapButtons", category = "Interface", nameKey = "MINIMAP_BUTTONS_NAME",
    descriptionKey = "MINIMAP_BUTTONS_DESC", detailKey = "MINIMAP_BUTTONS_DETAIL",
    requires = { "Minimap", "issecurevariable", "InCombatLockdown" },
    risk = "visible", defaultEnabled = false,
})

-- MinimapButtonButton's name rules, shaped by years of its bug reports: what addons call a
-- minimap button, and the map pins (HandyNotes, GatherMate, TomTom, Questie's objectives) that
-- are children of the minimap too and must stay on it. A numbered name is a pin, except that
-- TomCats numbers its buttons with the year.
local BUTTON_NAMES = { "^LibDBIcon10_", "MinimapButton", "MinimapFrame", "MinimapIcon", "[-_]Minimap[-_]",
    "Minimap$" }
local PIN_NAMES = { "^HandyNotes", "^TomTom", "^HereBeDragons", "^Questie", "^GatherMate", "^pin", "^Pin",
    "^EasyFind" }
local YEAR_NAMED = "^TomCats%-"
-- What an addon moves its own button with. While the button is gathered these do nothing, or
-- the addon's next refresh of its saved angle would put it back on the rim, under the minimap
-- but parented to a closed drawer.
local BLOCKED = { "ClearAllPoints", "SetPoint", "SetAllPoints", "SetParent" }
-- Login is when most buttons are made: some on the next frame, a few a second or more later.
local LOGIN_GATHERS = { 0, 1, 5 }
-- A ring is about as wide as its button, so at 2 px two rings read as touching.
local SPACING = 4
-- The cell of a drawer with nothing in it, LibDBIcon's button size.
local DEFAULT_CELL = 31
local ICON_CREATED = "LibDBIcon_IconCreated"
local PREFIX = "^LibDBIcon10_"

local function noop() end

-- Whether the button's addon fixed its strata and its level. LibDBIcon and Lueur fix both, and
-- a fixed one ignores SetFrameStrata and SetFrameLevel, which left their buttons on MEDIUM under
-- the HIGH drawer, dimmed by its panel (seen in game 11 Nov 2026).
local function fixedLayer(button)
    local strata = type(button.HasFixedFrameStrata) == "function" and button:HasFixedFrameStrata() == true
    local level = type(button.HasFixedFrameLevel) == "function" and button:HasFixedFrameLevel() == true
    return strata, level
end

-- Lifts the fix for the change and puts it back as the addon had it, the way ATT moves its own
-- button between strata.
local function setLayer(button, strata, level, fixedStrata, fixedLevel)
    if fixedStrata then
        button:SetFixedFrameStrata(false)
    end
    button:SetFrameStrata(strata)
    if fixedStrata then
        button:SetFixedFrameStrata(true)
    end
    if fixedLevel then
        button:SetFixedFrameLevel(false)
    end
    button:SetFrameLevel(level)
    if fixedLevel then
        button:SetFixedFrameLevel(true)
    end
end

local function byKey(a, b)
    if a.key ~= b.key then
        return a.key < b.key
    end
    return a.name < b.name
end

-- Width and height of a grid of count cells, columns across.
function MinimapButtons:GridSize(count, columns, cell)
    if count <= 0 then
        return 0, 0
    end
    local across = math.min(count, columns)
    local down = math.ceil(count / columns)
    return across * cell + (across - 1) * SPACING, down * cell + (down - 1) * SPACING
end

-- The centre of the index-th cell, measured right and down from the grid's top left.
function MinimapButtons:GridCenter(index, columns, cell)
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    return column * (cell + SPACING) + cell / 2, row * (cell + SPACING) + cell / 2
end

-- Never Blizzard's own frames (a global the client's code set is a secure variable), never a
-- protected frame, never our own button.
function MinimapButtons:Eligible(frame)
    if type(frame) ~= "table" or self.records[frame] or frame == self.collector.button then
        return false
    end
    if type(frame.IsProtected) ~= "function" or frame:IsProtected() then
        return false
    end
    local name = type(frame.GetName) == "function" and frame:GetName()
    return type(name) == "string" and not issecurevariable(_G, name)
end

function MinimapButtons:LooksLikeButton(frame)
    local name = frame:GetName()
    if name:match(YEAR_NAMED) then
        return true
    end
    if name:match("%d$") then
        return false
    end
    for _, pattern in ipairs(PIN_NAMES) do
        if name:match(pattern) then
            return false
        end
    end
    for _, pattern in ipairs(BUTTON_NAMES) do
        if name:match(pattern) then
            return true
        end
    end
    return false
end

-- Everything needed to hand the button back exactly as it was: where it hung, how it was
-- layered, how it was dragged, and which of its methods were its own.
function MinimapButtons:Take(button, libraryName)
    local name = button:GetName()
    local record = {
        button = button, name = name, key = (name:gsub(PREFIX, "")):lower(), libraryName = libraryName,
        parent = button:GetParent(), strata = button:GetFrameStrata(), level = button:GetFrameLevel(),
        dragStart = button:GetScript("OnDragStart"), dragStop = button:GetScript("OnDragStop"),
        points = {}, own = {}, call = {}, shown = button:IsShown(),
    }
    record.fixedStrata, record.fixedLevel = fixedLayer(button)
    for index = 1, button:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = button:GetPoint(index)
        record.points[index] = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
    end
    for _, method in ipairs(BLOCKED) do
        record.own[method] = rawget(button, method)
        record.call[method] = button[method]
    end
    local collector = self.collector
    record.call.SetParent(button, collector.content)
    setLayer(button, collector.strata, collector.content:GetFrameLevel() + 2, record.fixedStrata, record.fixedLevel)
    button:SetScript("OnDragStart", nil)
    button:SetScript("OnDragStop", nil)
    for _, method in ipairs(BLOCKED) do
        button[method] = noop
    end
    -- A hook cannot be taken off again, so each button is hooked once in its life and the hook
    -- does nothing for a button that is not gathered.
    if not self.hooked[button] then
        self.hooked[button] = true
        local function changed(frame)
            if self.state == "enabled" and self.records[frame] then
                R:SafeCall(self, self.OnButtonToggled, "minimap buttons", frame)
            end
        end
        button:HookScript("OnShow", changed)
        button:HookScript("OnHide", changed)
    end
    self.records[button] = record
    self.order[#self.order + 1] = record
end

function MinimapButtons:Release(record)
    local button = record.button
    for _, method in ipairs(BLOCKED) do
        button[method] = record.own[method]
    end
    button:SetParent(record.parent)
    setLayer(button, record.strata, record.level, record.fixedStrata, record.fixedLevel)
    button:ClearAllPoints()
    local library = record.libraryName and R.UI:LibDBIcon()
    if library and type(library.SetButtonToPosition) == "function" then
        -- LibDBIcon puts its own buttons back, at the angle the player may have changed since.
        library:SetButtonToPosition(button, button.db and button.db.minimapPos or button.minimapPos)
    else
        for _, point in ipairs(record.points) do
            button:SetPoint(point.point, point.relativeTo, point.relativePoint, point.x, point.y)
        end
    end
    button:SetScript("OnDragStart", record.dragStart)
    button:SetScript("OnDragStop", record.dragStop)
end

-- LibDBIcon knows its buttons by name; everything else is found among the minimap's children.
-- Taking a button waits out combat. A protected one is never taken at all, so this is caution,
-- not a rule: no addon's button changes parent in the middle of a fight.
function MinimapButtons:Gather()
    if self.state ~= "enabled" then
        return
    end
    if InCombatLockdown() then
        R.Broker:Subscribe("PLAYER_REGEN_ENABLED", self.OnCombatEnded, self)
        return
    end
    local before = #self.order
    local library = R.UI:LibDBIcon()
    if library and type(library.GetButtonList) == "function" and type(library.GetMinimapButton) == "function" then
        for _, name in ipairs(library:GetButtonList()) do
            local button = library:GetMinimapButton(name)
            if self:Eligible(button) then
                self:Take(button, name)
            end
        end
    end
    local children = { Minimap:GetChildren() }
    for _, child in ipairs(children) do
        if self:Eligible(child) and self:LooksLikeButton(child) then
            self:Take(child)
        end
    end
    if #self.order > before then
        table.sort(self.order, byKey)
        self:Arrange()
    end
end

-- Shown buttons in name order, in rows of the chosen width. A button's own shown flag is what
-- counts: the drawer being closed hides none of them.
function MinimapButtons:Arrange()
    local collector, shown, cell = self.collector, self.shown, 0
    for index = #shown, 1, -1 do
        shown[index] = nil
    end
    for _, record in ipairs(self.order) do
        local button = record.button
        record.shown = button:IsShown()
        if record.shown then
            shown[#shown + 1] = record
            local scale = button:GetScale()
            cell = math.max(cell, button:GetWidth() * scale, button:GetHeight() * scale)
        end
    end
    if cell <= 0 then
        cell = DEFAULT_CELL
    end
    collector.count = #shown
    local columns = R.Settings:GetOption("minimapButtonsColumns")
    collector:Resize(self:GridSize(#shown, columns, cell))
    for index, record in ipairs(shown) do
        local x, y = self:GridCenter(index, columns, cell)
        local button, scale = record.button, record.button:GetScale()
        record.call.ClearAllPoints(button)
        record.call.SetPoint(button, "CENTER", collector.content, "TOPLEFT", x / scale, -y / scale)
    end
    if collector:IsOpen() then
        collector:Anchor()
    end
end

function MinimapButtons:OnButtonToggled(button)
    if self.records[button].shown ~= button:IsShown() then
        self:Arrange()
    end
end

function MinimapButtons:Toggle()
    if self.collector:IsOpen() then
        self:Close()
    else
        self:Open()
    end
end

-- Opening is also when a button made since the last look is picked up.
function MinimapButtons:Open()
    self:Gather()
    self:Arrange()
    self.collector:Open()
    if R.Settings:GetOption("minimapButtonsCloseOnClick") then
        R.Broker:Subscribe("GLOBAL_MOUSE_DOWN", self.OnMouseDown, self)
    end
end

function MinimapButtons:Close()
    R.Broker:Unsubscribe("GLOBAL_MOUSE_DOWN", self)
    self.collector:Close()
end

-- The way a Blizzard menu closes: a click anywhere but on it, or on its button.
function MinimapButtons:OnMouseDown()
    if not self.collector:IsMouseOver() then
        self:Close()
    end
end

function MinimapButtons:OnCombatEnded()
    R.Broker:Unsubscribe("PLAYER_REGEN_ENABLED", self)
    self:Gather()
end

-- CallbackHandler reports a callback's error to the client, not to Refactor's error list.
function MinimapButtons:OnIconCreated()
    R:SafeCall(self, self.Gather, "minimap buttons")
end

function MinimapButtons:OnWorldEntered()
    self.collector:Place(R.Settings:GetOption("minimapButtonsAttach"))
    self:Gather()
end

function MinimapButtons:OnSettingsChanged(_, key)
    if key == "minimapButtonsAttach" then
        self.collector:Place(R.Settings:GetOption("minimapButtonsAttach"))
        if self.collector:IsOpen() then
            self.collector:Anchor()
        end
    elseif key == "minimapButtonsColumns" then
        self:Arrange()
    elseif key == "minimapButtonsCloseOnClick" and self.collector:IsOpen() then
        self:Close()
    end
end

function MinimapButtons:OnEnable()
    local owner = R.Integrations:Owner(self.id)
    if owner then
        -- Two collectors would each take the buttons from the other, and each blocks the other
        -- from moving them, so the first one loaded keeps the job.
        self.unavailableReasonKey = "MINIMAP_BUTTONS_DEFERRED"
        self.state = "unavailable"
        self.unavailableReason = string.format(R.L.MINIMAP_BUTTONS_DEFERRED, owner)
        R.Broker:Emit("REFACTOR_MODULE_CHANGED", self.id)
        return
    end
    self.records, self.order, self.shown = {}, {}, {}
    self.hooked = self.hooked or {}
    self.collector = self.collector or R.UI:CreateMinimapCollector(self)
    self.collector:Place(R.Settings:GetOption("minimapButtonsAttach"))
    self.collector:SetShown(true)
    local library = R.UI:LibDBIcon()
    if library and type(library.RegisterCallback) == "function" then
        library.RegisterCallback(self, ICON_CREATED, "OnIconCreated")
        self.listening = library
    end
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettingsChanged, self)
    R.Broker:Subscribe("PLAYER_ENTERING_WORLD", self.OnWorldEntered, self)
    -- A load-on-demand addon makes its button when it loads, long after login.
    R.Broker:Subscribe("ADDON_LOADED", self.Gather, self)
    self:Gather()
    for _, delay in ipairs(LOGIN_GATHERS) do
        R:After(self, delay, self.Gather)
    end
end

function MinimapButtons:OnDisable()
    R.Broker:UnsubscribeAll(self)
    if self.listening then
        self.listening.UnregisterCallback(self, ICON_CREATED)
        self.listening = nil
    end
    if self.collector then
        self.collector:SetShown(false)
    end
    local order = self.order or {}
    for index = #order, 1, -1 do
        self:Release(order[index])
        order[index] = nil
    end
    self.records = {}
end
